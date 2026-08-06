import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'deployed_map_models.dart';

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
    final name = drawingName.contains('.')
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
    final waypoints = <Offset>[];
    final names = <Offset, String>{};
    for (final value in data['waypoints'] as List<dynamic>) {
      final waypoint = value as Map<String, dynamic>;
      final point = decodePoint(waypoint['point']);
      waypoints.add(point);
      names[point] = waypoint['name'] as String? ?? '';
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
    names[vertices.length - 1] = match.group(3)!;
  }

  final laneIndices = <(int, int)>[];
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
      laneIndices.add((int.parse(match.group(1)!), int.parse(match.group(2)!)));
    }
  }
  final lanes = <(Offset, Offset)>[];
  final waypointSet = <Offset>{};
  for (final lane in laneIndices) {
    if (lane.$1 >= vertices.length || lane.$2 >= vertices.length) continue;
    final start = vertices[lane.$1];
    final end = vertices[lane.$2];
    lanes.add((start, end));
    waypointSet.addAll([start, end]);
  }
  final waypointNames = <Offset, String>{};
  for (var i = 0; i < vertices.length; i++) {
    final name = names[i]?.trim() ?? '';
    if (name.isNotEmpty && waypointSet.contains(vertices[i])) {
      waypointNames[vertices[i]] = name;
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
  );
}
