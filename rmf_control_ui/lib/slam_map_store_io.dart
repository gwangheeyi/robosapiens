/// SLAM 지도를 프로젝트의 `nav2_map/` 에 넣고 다시 읽는다.
///
/// 도면에서 만든 격자(`<맵>.yaml`)와 **나란히** 둔다. 덮어쓰지 않는다 — 두
/// 지도를 겹쳐 보며 원점을 맞춰야 하므로 둘 다 있어야 한다.
library;

import 'dart:io';
import 'dart:typed_data';

import 'occupancy_grid_export.dart' show occupancyGridDirectoryName;
import 'rmf_config_export.dart' show safeMapDirectoryName;
import 'slam_map.dart';

/// SLAM 지도를 넣거나 읽은 결과.
class SlamMapStoreResult {
  const SlamMapStoreResult({
    required this.success,
    required this.message,
    this.map,
    this.directory = '',
    this.written = const [],
  });

  final bool success;
  final String message;

  /// 읽어 들인 지도. 실패하면 null.
  final SlamMap? map;
  final String directory;
  final List<String> written;
}

Directory? _findProjectRoot() {
  final configured = Platform.environment['RMF_ROOT'];
  if (configured != null && configured.isNotEmpty) {
    final directory = Directory(configured).absolute;
    if (Directory('${directory.path}/rmf_maps').existsSync()) return directory;
  }
  var directory = Directory.current.absolute;
  for (var i = 0; i < 8; i++) {
    if (Directory('${directory.path}/rmf_maps').existsSync()) return directory;
    final parent = directory.parent;
    if (parent.path == directory.path) break;
    directory = parent;
  }
  return null;
}

String _mapDirectory(Directory root, String mapName) =>
    '${root.path}/rmf_maps/${safeMapDirectoryName(mapName)}/'
    '$occupancyGridDirectoryName';

/// 이 프로젝트에서 SLAM 지도가 쓰는 파일 이름. 도면 지도와 겹치지 않는다.
String slamYamlName(String mapName) =>
    '${safeMapDirectoryName(mapName)}_slam.yaml';
String slamImageName(String mapName) =>
    '${safeMapDirectoryName(mapName)}_slam.pgm';

/// [yamlPath] 와 그 옆의 `.pgm` 을 읽어 [SlamMap] 으로 만든다. 아직 안 옮긴다.
///
/// 먼저 읽어서 보여 주고, 사람이 원점을 확인한 뒤에 넣는다. 곧바로 넣으면
/// 못 읽는 파일이 프로젝트에 들어앉는다.
Future<SlamMapStoreResult> readSlamMapFrom(String yamlPath) async {
  final yamlFile = File(yamlPath);
  if (!await yamlFile.exists()) {
    return SlamMapStoreResult(
      success: false,
      message: 'yaml 파일이 없습니다: $yamlPath',
    );
  }
  try {
    final header = parseSlamMapYaml(await yamlFile.readAsString());
    // `image:` 는 yaml 옆에 있는 파일을 가리킨다.
    final imagePath =
        '${yamlFile.parent.path}/${header.imageName}';
    final imageFile = File(imagePath);
    if (!await imageFile.exists()) {
      return SlamMapStoreResult(
        success: false,
        message:
            'yaml 이 가리키는 그림이 없습니다: ${header.imageName}\n\n'
            '`map_saver` 는 `.yaml` 과 `.pgm` 을 함께 냅니다. 두 파일을 같은 '
            '디렉터리에 두고 다시 고르세요.',
      );
    }
    final pgm = parsePgm(await imageFile.readAsBytes());
    return SlamMapStoreResult(
      success: true,
      message: '읽었습니다.',
      map: SlamMap(
        imageName: header.imageName,
        width: pgm.width,
        height: pgm.height,
        resolution: header.resolution,
        originX: header.originX,
        originY: header.originY,
        originYaw: header.originYaw,
        cells: pgm.cells,
        occupiedThreshold: header.occupiedThreshold,
        freeThreshold: header.freeThreshold,
        negate: header.negate,
      ),
    );
  } on SlamMapParseError catch (error) {
    return SlamMapStoreResult(success: false, message: error.message);
  } catch (error) {
    return SlamMapStoreResult(
      success: false,
      message: 'SLAM 지도를 읽지 못했습니다: $error',
    );
  }
}

/// [map] 을 이 프로젝트의 `nav2_map/` 에 `<맵>_slam.{pgm,yaml}` 로 쓴다.
///
/// 그림 이름을 우리 규칙으로 갈아 끼운다. `map_saver` 가 낸 이름이 다른
/// 프로젝트의 것과 같을 수 있고, 그러면 어느 지도인지 알 수 없다.
Future<SlamMapStoreResult> writeSlamMap({
  required String mapName,
  required SlamMap map,
  String? note,
}) async {
  final root = _findProjectRoot();
  if (root == null) {
    return const SlamMapStoreResult(
      success: false,
      message:
          'rmf_maps 디렉터리를 찾을 수 없습니다. '
          'RMF_ROOT 환경 변수로 프로젝트 위치를 지정하세요.',
    );
  }
  final target = Directory(_mapDirectory(root, mapName));
  final image = slamImageName(mapName);
  final yaml = slamYamlName(mapName);
  try {
    await target.create(recursive: true);
    await File(
      '${target.path}/$image',
    ).writeAsBytes(_toPgm(map), flush: true);
    final stored = SlamMap(
      imageName: image,
      width: map.width,
      height: map.height,
      resolution: map.resolution,
      originX: map.originX,
      originY: map.originY,
      originYaw: map.originYaw,
      cells: map.cells,
      occupiedThreshold: map.occupiedThreshold,
      freeThreshold: map.freeThreshold,
      negate: map.negate,
    );
    await File(
      '${target.path}/$yaml',
    ).writeAsString(stored.toYaml(note: note), flush: true);
    return SlamMapStoreResult(
      success: true,
      message: 'SLAM 지도를 넣었습니다.',
      map: stored,
      directory: target.path,
      written: [image, yaml],
    );
  } catch (error) {
    return SlamMapStoreResult(
      success: false,
      message: 'SLAM 지도를 쓰지 못했습니다: $error',
    );
  }
}

/// 이 프로젝트에 이미 넣어 둔 SLAM 지도를 읽는다. 없으면 null.
Future<SlamMap?> loadStoredSlamMap(String mapName) async {
  final root = _findProjectRoot();
  if (root == null) return null;
  final path = '${_mapDirectory(root, mapName)}/${slamYamlName(mapName)}';
  if (!await File(path).exists()) return null;
  final result = await readSlamMapFrom(path);
  return result.map;
}

Uint8List _toPgm(SlamMap map) {
  final header = '''
P5
# rmf_control_ui 가 넣은 SLAM 지도. 원점은 이 파일 옆 yaml 에 있다.
${map.width} ${map.height}
255
''';
  final head = header.codeUnits;
  return Uint8List(head.length + map.cells.length)
    ..setRange(0, head.length, head)
    ..setRange(head.length, head.length + map.cells.length, map.cells);
}
