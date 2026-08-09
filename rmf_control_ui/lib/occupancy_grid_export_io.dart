/// 도면에서 만든 점유격자를 맵 디렉터리에 쓴다.
///
/// 이 파일은 `.world` 나 `nav_graphs/0.yaml` 과 같은 부류다 — 도면에서 파생되는
/// **산출물**이라 MySQL 에 원장을 두지 않는다. 도면이 바뀌면 다시 만들면 된다.
///
/// `rmf_maps/<맵>/nav2_map/` 아래에 둔다. 나중에 실물 건물에서 SLAM 으로 뜬
/// 지도를 같은 디렉터리에 나란히 놓고 비교할 수 있다.
library;

import 'dart:io';

import 'occupancy_grid.dart';
import 'rmf_config_export.dart' show safeMapDirectoryName;

class OccupancyGridExportResult {
  const OccupancyGridExportResult({
    required this.success,
    required this.directory,
    required this.written,
    required this.message,
  });

  final bool success;

  /// 실제로 쓴 디렉터리. 실패하면 빈 문자열.
  final String directory;
  final List<String> written;
  final String message;
}

Directory? _findProjectRoot() {
  final configuredRoot = Platform.environment['RMF_ROOT'];
  if (configuredRoot != null && configuredRoot.isNotEmpty) {
    final directory = Directory(configuredRoot).absolute;
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

/// SLAM 으로 뜬 지도와 나란히 두는 곳.
const String occupancyGridDirectoryName = 'nav2_map';

/// [grid] 를 `rmf_maps/<맵>/nav2_map/` 에 `.pgm` 과 `.yaml` 로 쓴다.
///
/// [note] 는 `.yaml` 맨 위에 주석으로 들어간다. 파일만 보고 이게 어디서 나온
/// 것인지 알 수 있어야 한다.
Future<OccupancyGridExportResult> exportOccupancyGrid({
  required String mapName,
  required OccupancyGrid grid,
  String? note,
}) async {
  final root = _findProjectRoot();
  if (root == null) {
    return const OccupancyGridExportResult(
      success: false,
      directory: '',
      written: [],
      message:
          'rmf_maps 디렉터리를 찾을 수 없습니다. '
          'RMF_ROOT 환경 변수로 프로젝트 위치를 지정하세요.',
    );
  }
  final safeName = safeMapDirectoryName(mapName);
  final target = Directory(
    '${root.path}/rmf_maps/$safeName/$occupancyGridDirectoryName',
  );
  try {
    await target.create(recursive: true);
    final image = '$safeName.pgm';
    await File('${target.path}/$image').writeAsBytes(grid.toPgm(), flush: true);
    await File(
      '${target.path}/$safeName.yaml',
    ).writeAsString(grid.toYaml(imageName: image, note: note), flush: true);
    await File(
      '${target.path}/README.md',
    ).writeAsString(buildOccupancyGridReadme(safeName, grid), flush: true);
    return OccupancyGridExportResult(
      success: true,
      directory: target.path,
      written: [image, '$safeName.yaml', 'README.md'],
      message:
          '${grid.width}×${grid.height} 격자(${grid.resolution}m/칸)를 '
          '${target.path} 에 썼습니다.',
    );
  } catch (error) {
    return OccupancyGridExportResult(
      success: false,
      directory: target.path,
      written: const [],
      message: '$error',
    );
  }
}

/// 이 디렉터리가 무엇이고 어떻게 쓰는지.
String buildOccupancyGridReadme(String mapName, OccupancyGrid grid) => '''
# $mapName · Nav2 지도

`rmf_control_ui` 가 **도면에서 만들었습니다.** 손으로 고쳐도 다음 내보내기 때
덮어써집니다.

## 무엇에 쓰나

RMF 는 nav graph 만으로 길을 찾으므로 이 지도가 필요 없습니다. 이 지도가 필요한
것은 **로봇 쪽**입니다 — AMCL 이 라이다로 제 위치를 잡고 Nav2 가 장애물을 피할 때
씁니다.

## 왜 SLAM 을 안 돌렸나

시뮬레이터에서는 돌 이유가 없습니다. 정확한 도면이 이미 있고, 그 도면이 Gazebo
월드를 만든 바로 그 원본이기 때문입니다. 도면에서 바로 만들면

- **원점이 RMF 월드에 계산으로 정확히 맞습니다.** 맞추는 작업 자체가 없습니다
- 표류가 없습니다
- 맵을 고치면 다시 만들어집니다

벽은 RMF 가 쓰는 두께 **0.1m** 로 그렸습니다(`building_map/wall.py` 의
`wall_thickness`). 그래서 Gazebo 에서 라이다가 보는 벽과 이 지도의 벽이 같습니다.
다르면 AMCL 이 못 붙습니다.

## 이 지도

| | |
|---|---|
| 크기 | ${grid.width} × ${grid.height} 칸 |
| 한 칸 | ${grid.resolution} m |
| 덮는 범위 | x ${grid.bounds.minX.toStringAsFixed(3)} ~ ${grid.bounds.maxX.toStringAsFixed(3)} m · y ${grid.bounds.minY.toStringAsFixed(3)} ~ ${grid.bounds.maxY.toStringAsFixed(3)} m |
| 원점 | ${grid.originX.toStringAsFixed(6)}, ${grid.originY.toStringAsFixed(6)} |
| 바닥 | ${grid.freeCells} 칸 |
| 벽 | ${grid.occupiedCells} 칸 |
| 모름 | ${grid.unknownCells} 칸 |

좌표는 **RMF 월드**입니다 — 원점은 도면 그림의 왼쪽 위, y 는 위로 갈수록 커져서
건물 안은 음수입니다. 자세한 것은 `rmf_control_ui/docs/COORDINATE_FRAMES.md`.

## 보기

```bash
# 그림으로 바로 보기
eog $mapName.pgm

# map_server 로 띄워서 RViz 에서 보기
ros2 run nav2_map_server map_server --ros-args \\
  -p yaml_filename:=\$PWD/$mapName.yaml
ros2 lifecycle set /map_server configure
ros2 lifecycle set /map_server activate
```

## 실물 건물에서 SLAM 으로 뜬 지도와 비교하기

진짜 핑키로 넘어가면 건물을 SLAM 으로 떠서 여기에 나란히 둡니다.

```bash
# 1. SLAM 으로 뜬다
ros2 launch pinky_navigation map_building.launch.xml

# 2. 이 디렉터리에 다른 이름으로 저장한다
ros2 run nav2_map_server map_saver_cli -f ${mapName}_slam
```

그 다음 **원점을 맞춰야 합니다.** SLAM 지도의 원점은 로봇이 SLAM 을 시작한
자리이고, RMF 의 원점은 도면 그림의 왼쪽 위입니다. `${mapName}_slam.yaml` 의
`origin:` 세 숫자를 고쳐서 이 파일(`$mapName.yaml`)과 같은 자리를 가리키게
합니다.

맞았는지는 두 그림을 겹쳐 보면 압니다. 벽이 어긋나면 아직 안 맞은 것입니다.
''';
