import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'deployed_map_models.dart';
import 'rmf_config_export_io.dart' show safeMapDirectoryName;

Directory? _findProjectRoot() {
  final configured = Platform.environment['RMF_ROOT'];
  if (configured != null && configured.isNotEmpty) {
    final root = Directory(configured).absolute;
    if (Directory('${root.path}/rmf_maps').existsSync()) return root;
  }
  var current = Directory.current.absolute;
  for (var i = 0; i < 8; i++) {
    if (Directory('${current.path}/rmf_maps').existsSync()) return current;
    if (current.parent.path == current.path) break;
    current = current.parent;
  }
  return null;
}

String _value(String yaml, String key, {String fallback = ''}) {
  final match = RegExp(
    '^$key:\\s*["\']?([^"\'\\n]+)',
    multiLine: true,
  ).firstMatch(yaml);
  return match?.group(1)?.trim() ?? fallback;
}

/// [mapName] 의 배포 산출물이 디스크에 있는가.
///
/// **배포 여부는 디스크의 사실이지 앱의 기억이 아니다.** 앱은 배포에 성공한
/// 순간을 `_isDeployed` 로 들고 있는데, 그것은 이 세션에서 방금 배포했다는
/// 뜻일 뿐이다. 앱을 다시 켜거나, 배포가 실제로는 다 됐는데 확인 단계에서
/// 실패로 끝나거나, 맵과 상관없는 편집 하나로도 그 기억은 사라진다. 그때마다
/// 멀쩡히 배포된 맵을 두고 `먼저 맵을 배포하세요` 가 뜬다.
///
/// 배포가 만드는 것 둘만 본다 — 건물 맵과 주행 그래프. RMF 가 읽는 것이
/// 그 둘이고, 나머지(실행 스크립트·로봇 디렉터리)는 내보내기가 만드는 것이라
/// 여기서 볼 것이 아니다.
///
/// 목록을 훑지 않고 경로를 곧바로 본다. 새 작업을 누를 때마다 `rmf_maps` 를
/// 통째로 훑으면 메시와 텍스처까지 다 걸어야 한다.
bool deployedMapExists(String mapName) {
  if (mapName.trim().isEmpty) return false;
  final root = _findProjectRoot();
  if (root == null) return false;
  final directory = '${root.path}/rmf_maps/${safeMapDirectoryName(mapName)}';
  return File('$directory/$mapName.building.yaml').existsSync() &&
      File('$directory/nav_graphs/0.yaml').existsSync();
}

Future<List<DeployedMapSummary>> listDeployedMaps() async {
  final root = _findProjectRoot();
  if (root == null) return const [];
  final mapsRoot = Directory('${root.path}/rmf_maps');
  final results = <DeployedMapSummary>[];
  await for (final entity in mapsRoot.list(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.building.yaml')) continue;
    if (entity.path.contains('/.backups/') || entity.path.contains('/.')) {
      continue;
    }
    final yaml = await entity.readAsString();
    final name = _value(
      yaml,
      'name',
      fallback: entity.uri.pathSegments.last.replaceFirst('.building.yaml', ''),
    );
    final navGraph = File('${entity.parent.path}/nav_graphs/0.yaml');
    results.add(
      DeployedMapSummary(
        id: entity.path,
        name: name,
        yamlPath: entity.path,
        hasNavGraph: await navGraph.exists(),
      ),
    );
  }
  await for (final entity in mapsRoot.list(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.rmfproject')) continue;
    if (entity.path.contains('/.backups/') || entity.path.contains('/.')) {
      continue;
    }
    final data =
        jsonDecode(await entity.readAsString()) as Map<String, dynamic>;
    if (data['format'] != 'robosapiens-map-project') continue;
    final drawing = data['drawing'] as Map<String, dynamic>?;
    final drawingName = drawing?['name'] as String? ?? '';
    final savedMapName = (data['mapName'] as String?)?.trim();
    final name = savedMapName?.isNotEmpty == true
        ? savedMapName!
        : drawingName.contains('.')
        ? drawingName.substring(0, drawingName.lastIndexOf('.'))
        : entity.uri.pathSegments.last.replaceFirst('.rmfproject', '');
    final existing = results.indexWhere((map) => map.name == name);
    if (existing >= 0 && results[existing].hasNavGraph) continue;
    if (existing >= 0) results.removeAt(existing);
    results.add(
      DeployedMapSummary(
        id: entity.path,
        name: name,
        yamlPath: entity.path,
        hasNavGraph: false,
      ),
    );
  }
  results.sort((a, b) {
    if (a.hasNavGraph != b.hasNavGraph) return a.hasNavGraph ? -1 : 1;
    return a.name.compareTo(b.name);
  });
  return results;
}

Size _pngSize(Uint8List bytes) {
  if (bytes.length < 24 ||
      bytes[0] != 0x89 ||
      bytes[1] != 0x50 ||
      bytes[2] != 0x4E ||
      bytes[3] != 0x47) {
    throw const FormatException('현재 배포 맵 로더는 PNG 도면을 지원합니다.');
  }
  final data = ByteData.sublistView(bytes);
  return Size(
    data.getUint32(16, Endian.big).toDouble(),
    data.getUint32(20, Endian.big).toDouble(),
  );
}

Future<DeployedMapData> loadDeployedMap(DeployedMapSummary summary) async {
  if (summary.yamlPath.endsWith('.rmfproject')) {
    final data =
        jsonDecode(await File(summary.yamlPath).readAsString())
            as Map<String, dynamic>;
    final drawing = data['drawing'] as Map<String, dynamic>;
    final imageBytes = base64Decode(drawing['bytes'] as String);
    Offset decodePoint(dynamic value) {
      final point = value as List<dynamic>;
      return Offset((point[0] as num).toDouble(), (point[1] as num).toDouble());
    }

    final lanes = <(Offset, Offset)>[
      for (final value in data['recommendedLanes'] as List<dynamic>)
        (decodePoint((value as List<dynamic>)[0]), decodePoint(value[1])),
    ];
    // 일방통행 레인을 놓치면 로봇이 거슬러 올라간다.
    final directions = <(Offset, Offset), String>{};
    for (final value
        in (data['laneDirections'] as List<dynamic>?) ?? const []) {
      final entry = value as Map<String, dynamic>;
      directions[(decodePoint(entry['start']), decodePoint(entry['end']))] =
          entry['direction'] as String? ?? '양방향';
    }
    final waypoints = <Offset>[];
    final names = <Offset, String>{};
    final categories = <Offset, String>{};
    final dockHeadings = <Offset, double>{};
    for (final value in data['waypoints'] as List<dynamic>) {
      final waypoint = value as Map<String, dynamic>;
      final point = decodePoint(waypoint['point']);
      waypoints.add(point);
      names[point] = waypoint['name'] as String? ?? '';
      final category = (waypoint['category'] as String? ?? '').trim();
      if (category.isNotEmpty) categories[point] = category;
      // 이 자리에서 로봇이 볼 방향. 없는 프로젝트가 대부분이라 없으면 넘어간다.
      if (waypoint['dockHeading'] case final num heading) {
        dockHeadings[point] = heading.toDouble();
      }
    }
    return DeployedMapData(
      summary: summary,
      imageName: drawing['name'] as String,
      imageBytes: imageBytes,
      imageSize: Size(
        (drawing['pixelWidth'] as num).toDouble(),
        (drawing['pixelHeight'] as num).toDouble(),
      ),
      lanes: lanes,
      waypoints: waypoints,
      waypointNames: names,
      waypointCategories: categories,
      waypointDockHeadings: dockHeadings,
      laneDirections: directions,
    );
  }
  final yamlFile = File(summary.yamlPath);
  final yaml = await yamlFile.readAsString();
  final drawingMatch = RegExp(
    r'''drawing:\s*\n\s*filename:\s*["']?([^"'\n]+)''',
  ).firstMatch(yaml);
  if (drawingMatch == null) {
    throw const FormatException('drawing.filename이 없습니다.');
  }
  final imageName = drawingMatch.group(1)!.trim();
  final imageFile = File('${yamlFile.parent.path}/$imageName');
  if (!await imageFile.exists()) {
    throw FileSystemException('도면 이미지를 찾을 수 없습니다.', imageFile.path);
  }
  final imageBytes = await imageFile.readAsBytes();

  final vertices = <Offset>[];
  final names = <int, String>{};
  final equipmentIndices = <int>{};
  final dockHeadingByIndex = <int, double>{};
  var inVertices = false;
  for (final line in const LineSplitter().convert(yaml)) {
    if (line.startsWith('    vertices:')) {
      inVertices = true;
      continue;
    }
    if (inVertices && line.startsWith('    walls:')) break;
    if (!inVertices) continue;
    final match = RegExp(
      r'^\s*-\s*\[\s*(-?[0-9.]+),\s*(-?[0-9.]+),\s*[^,]+,\s*"([^"]*)"',
    ).firstMatch(line);
    if (match == null) continue;
    vertices.add(
      Offset(double.parse(match.group(1)!), double.parse(match.group(2)!)),
    );
    final index = vertices.length - 1;
    names[index] = match.group(3)!;
    if (line.contains('robosapiens_equipment: [4, true]')) {
      equipmentIndices.add(index);
    }
    // 이 자리에 설 방향. traffic_editor 형식이라 `[3, 값]` 으로 적힌다(3=실수).
    // RMF 는 모르는 이름의 정점 속성을 그냥 지나치므로 넣어도 안전하다 —
    // `parse_graph.cpp` 는 아는 이름만 골라 읽는다.
    final heading = RegExp(
      r'robosapiens_dock_heading:\s*\[\s*\d+\s*,\s*(-?[0-9.]+)\s*\]',
    ).firstMatch(line);
    if (heading != null) {
      final degrees = double.tryParse(heading.group(1)!);
      if (degrees != null) dockHeadingByIndex[index] = degrees;
    }
  }

  final laneIndices = <(int, int, bool)>[];
  var inLanes = false;
  for (final line in const LineSplitter().convert(yaml)) {
    if (line.startsWith('    lanes:')) {
      inLanes = true;
      continue;
    }
    if (inLanes && line.startsWith('    measurements:')) break;
    if (!inLanes) continue;
    final match = RegExp(r'^\s*-\s*\[\s*(\d+),\s*(\d+),').firstMatch(line);
    if (match != null) {
      // Open-RMF 는 일방통행을 bidirectional: [4, false] 로 적고, 진행 방향은
      // 앞의 두 정점 순서로 나타낸다. 이 값을 읽지 않으면 로봇이 일방통행
      // 레인을 거슬러 올라간다.
      final bidirectional = !RegExp(
        r'bidirectional:\s*\[\s*\d+\s*,\s*false\s*\]',
      ).hasMatch(line);
      laneIndices.add((
        int.parse(match.group(1)!),
        int.parse(match.group(2)!),
        bidirectional,
      ));
    }
  }
  final lanes = <(Offset, Offset)>[];
  final directions = <(Offset, Offset), String>{};
  final waypointSet = <Offset>{};
  for (final lane in laneIndices) {
    if (lane.$1 >= vertices.length || lane.$2 >= vertices.length) continue;
    final start = vertices[lane.$1];
    final end = vertices[lane.$2];
    lanes.add((start, end));
    directions[(start, end)] = lane.$3 ? '양방향' : '정방향';
    waypointSet.addAll([start, end]);
  }
  for (final index in equipmentIndices) {
    if (index < vertices.length) waypointSet.add(vertices[index]);
  }
  final waypointNames = <Offset, String>{};
  final waypointDockHeadings = <Offset, double>{};
  for (var i = 0; i < vertices.length; i++) {
    final name = names[i]?.trim() ?? '';
    if (name.isNotEmpty && waypointSet.contains(vertices[i])) {
      waypointNames[vertices[i]] = name;
    }
    if (dockHeadingByIndex[i] case final degrees?) {
      waypointDockHeadings[vertices[i]] = degrees;
    }
  }
  return DeployedMapData(
    summary: summary,
    imageName: imageName,
    imageBytes: imageBytes,
    imageSize: _pngSize(imageBytes),
    lanes: lanes,
    waypoints: waypointSet.toList(),
    waypointNames: waypointNames,
    waypointDockHeadings: waypointDockHeadings,
    laneDirections: directions,
  );
}
