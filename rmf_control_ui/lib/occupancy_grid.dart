/// Nav2 가 쓰는 점유격자 지도를 도면에서 만든다.
///
/// RMF 는 nav graph 만으로 길을 찾으므로 격자 지도가 필요 없다. 격자가 필요한
/// 것은 **로봇 쪽**이다 — AMCL 이 라이다로 제 위치를 잡고 Nav2 가 장애물을
/// 피하려면 격자가 있어야 한다.
///
/// 시뮬레이터에서는 SLAM 을 돌 이유가 없다. 정확한 도면이 이미 있고, 그 도면이
/// Gazebo 월드를 만든 원본이기 때문이다. 도면에서 바로 만들면
///
///   - 원점이 RMF 월드에 **계산으로 정확히** 맞는다. 맞추는 작업 자체가 없다
///   - 표류가 없다
///   - 맵을 고치면 다시 만들어진다
///
/// **격자는 시뮬레이터가 실제로 부딪히는 것과 같아야 한다.** 다르면 AMCL 이
/// 라이다와 지도를 맞추지 못한다. 그래서 building.yaml 에 나가는 것과 같은
/// 원본을 쓴다 — 바닥 다각형과 벽 선분, 그리고 RMF 가 벽에 주는 두께 0.1m.
///
/// 좌표계는 `docs/COORDINATE_FRAMES.md` 의 ② RMF 월드다. 미터, 원점은 도면
/// 그림의 왼쪽 위, y 는 위로 갈수록 커진다(건물 안은 음수).
library;

import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

/// RMF 월드 좌표 한 점(m).
typedef GridPoint = ({double x, double y});

/// 벽 한 장. 두 끝점을 잇는 선분이다.
typedef GridWall = (GridPoint, GridPoint);

/// RMF 가 벽에 주는 두께(m).
///
/// `rmf_building_map_tools` 의 `building_map/wall.py` 에 `wall_thickness = 0.1`
/// 로 박혀 있다. 생성된 `wall_1.obj` 를 재 봐도 정확히 0.1m 다.
const double rmfWallThickness = 0.1;

/// 도면에서 만든 점유격자.
class OccupancyGrid {
  const OccupancyGrid({
    required this.width,
    required this.height,
    required this.resolution,
    required this.originX,
    required this.originY,
    required this.cells,
  });

  /// 가로·세로 셀 수.
  final int width;
  final int height;

  /// 셀 한 칸이 몇 미터인가.
  final double resolution;

  /// **왼쪽 아래 셀의 바깥 모서리**가 RMF 월드로 어디인가.
  ///
  /// Nav2 의 `origin:` 이 바로 이 값이다. 이것이 틀리면 로봇이 `픽업1로 가라`는
  /// 명령을 받고 엉뚱한 데로 간다.
  final double originX;
  final double originY;

  /// 그림 한 장. 첫 줄이 **위**쪽이다(PGM 과 같다).
  final Uint8List cells;

  /// 벽. 검다.
  static const int occupied = 0;

  /// 다닐 수 있는 바닥. 희다.
  static const int free = 254;

  /// 모르는 곳. 회색.
  ///
  /// 205 는 `map_saver` 가 쓰는 값이라 SLAM 으로 뜬 지도와 그대로 비교된다.
  static const int unknown = 205;

  /// 이 값 위로 어두우면 벽으로 읽는다. `map_saver` 기본값.
  static const double occupiedThreshold = 0.65;

  /// 이 값 아래로 밝으면 바닥으로 읽는다. `map_saver` 기본값.
  ///
  /// 205 는 `(255-205)/255 = 0.196078…` 이라 이 문턱보다 아주 조금 크다. 그래서
  /// 바닥도 벽도 아닌 `모름` 으로 떨어진다. 두 값이 이렇게 맞물려 있으므로 한쪽만
  /// 바꾸면 회색이 바닥으로 읽힌다.
  static const double freeThreshold = 0.196;

  int at(int col, int row) => cells[row * width + col];

  int get freeCells => cells.where((cell) => cell == free).length;
  int get occupiedCells => cells.where((cell) => cell == occupied).length;
  int get unknownCells => cells.where((cell) => cell == unknown).length;

  /// 셀 한 칸의 **가운데**가 RMF 월드로 어디인가.
  GridPoint centerOf(int col, int row) => (
    x: originX + (col + .5) * resolution,
    y: originY + (height - 1 - row + .5) * resolution,
  );

  /// 이 격자가 덮는 범위(m).
  ({double minX, double maxX, double minY, double maxY}) get bounds => (
    minX: originX,
    maxX: originX + width * resolution,
    minY: originY,
    maxY: originY + height * resolution,
  );

  /// 회색 PGM(P5) 한 장. `map_server` 가 읽는 그림이다.
  Uint8List toPgm() {
    // P5 는 머리글이 아스키, 그림이 날바이트다. 주석(`#`)을 넣을 수 있지만
    // 넣지 않는다 — 어떤 도구는 첫 줄 뒤의 주석을 못 읽는다.
    final header = ascii.encode('P5\n$width $height\n255\n');
    final out = Uint8List(header.length + cells.length)
      ..setRange(0, header.length, header)
      ..setRange(header.length, header.length + cells.length, cells);
    return out;
  }

  /// `map_server` 가 읽는 설명 파일.
  String toYaml({required String imageName, String? note}) {
    final buffer = StringBuffer();
    if (note != null) {
      for (final line in note.trimRight().split('\n')) {
        buffer.writeln(line.isEmpty ? '#' : '# $line');
      }
    }
    buffer
      ..writeln('image: $imageName')
      ..writeln('mode: trinary')
      ..writeln('resolution: ${resolution.toStringAsFixed(6)}')
      // 왼쪽 아래 셀의 바깥 모서리. RMF 월드 좌표다.
      ..writeln(
        'origin: [${originX.toStringAsFixed(6)}, '
        '${originY.toStringAsFixed(6)}, 0.000000]',
      )
      ..writeln('negate: 0')
      ..writeln('occupied_thresh: $occupiedThreshold')
      ..writeln('free_thresh: $freeThreshold');
    return buffer.toString();
  }
}

/// 격자 한 칸을 몇 미터로 할까.
///
/// 두 가지를 함께 본다.
///
///   - **로봇 몸이 몇 칸에 걸치나** — 한 칸이 로봇만 하면 좁은 통로가 통째로
///     막힌 것으로 보인다. 몸 하나에 여섯 칸은 되게 한다.
///   - **바닥이 몇 칸인가** — 작은 아레나에서 0.05m 를 쓰면 방 전체가 마흔
///     칸밖에 안 되어 AMCL 이 맞출 무늬가 없다. 짧은 쪽이 120칸은 되게 한다.
///
/// 0.05m 는 ROS 관례이자 `pinky_navigation` 의 기존 지도와 같은 값이라 위쪽
/// 한계로 둔다. 아래는 0.01m — 그보다 잘면 파일만 커진다.
///
/// [floorShorterSide] 를 모르면(바닥이 아직 없으면) 로봇 몸만 본다.
double occupancyResolutionFor({
  required double robotWidth,
  double? floorShorterSide,
}) {
  final byRobot = robotWidth / 6;
  if (floorShorterSide == null || floorShorterSide <= 0) {
    return byRobot.clamp(.01, .05);
  }
  return math.min(byRobot, floorShorterSide / 120).clamp(.01, .05);
}

/// 바닥 다각형과 벽 선분에서 점유격자를 만든다.
///
/// [floorOutline] 안이 다닐 수 있는 곳, [walls] 근처가 벽, 나머지는 모르는 곳이
/// 된다. 좌표는 전부 RMF 월드(m)다.
///
/// [margin] 은 바닥 바깥으로 얼마나 더 담을지다. 벽 바깥까지 담아야 라이다가
/// 벽을 맞히고 costmap 이 벽 너머를 `모름` 으로 둔다.
///
/// 만들 것이 없으면(바닥도 벽도 없으면) null 을 돌려준다. 격자가 [maxCells] 보다
/// 커져도 null 이다 — 축척이 틀리면 셀이 수억 개가 되어 앱이 멈춘다.
OccupancyGrid? buildOccupancyGrid({
  required List<GridPoint> floorOutline,
  required List<GridWall> walls,
  required double resolution,
  double wallThickness = rmfWallThickness,
  double margin = .5,
  int maxCells = 25000000,
}) {
  if (resolution <= 0) return null;
  final all = <GridPoint>[
    ...floorOutline,
    for (final wall in walls) ...[wall.$1, wall.$2],
  ];
  if (all.isEmpty) return null;

  var minX = all.first.x;
  var maxX = all.first.x;
  var minY = all.first.y;
  var maxY = all.first.y;
  for (final point in all) {
    minX = math.min(minX, point.x);
    maxX = math.max(maxX, point.x);
    minY = math.min(minY, point.y);
    maxY = math.max(maxY, point.y);
  }
  // 벽은 선분 한가운데를 지나므로 두께의 절반이 바깥으로 나간다.
  final pad = margin + wallThickness / 2;
  minX -= pad;
  maxX += pad;
  minY -= pad;
  maxY += pad;

  final width = math.max(1, ((maxX - minX) / resolution).ceil());
  final height = math.max(1, ((maxY - minY) / resolution).ceil());
  if (width * height > maxCells) return null;

  final cells = Uint8List(width * height)
    ..fillRange(0, width * height, OccupancyGrid.unknown);
  final grid = OccupancyGrid(
    width: width,
    height: height,
    resolution: resolution,
    originX: minX,
    originY: minY,
    cells: cells,
  );

  // 바닥 안을 자유로 칠한다. 다각형이 3점보다 적으면 바닥이 없는 것이다.
  if (floorOutline.length >= 3) {
    for (var row = 0; row < height; row++) {
      for (var col = 0; col < width; col++) {
        final center = grid.centerOf(col, row);
        if (_insidePolygon(center, floorOutline)) {
          cells[row * width + col] = OccupancyGrid.free;
        }
      }
    }
  }

  // 벽을 덧칠한다. 바닥보다 나중에 칠해야 바닥 위의 벽이 지워지지 않는다.
  final half = wallThickness / 2;
  for (final wall in walls) {
    // 선분이 닿는 곳만 본다. 격자 전체를 벽마다 훑으면 벽 수에 비례해 느려진다.
    final loX = math.min(wall.$1.x, wall.$2.x) - half;
    final hiX = math.max(wall.$1.x, wall.$2.x) + half;
    final loY = math.min(wall.$1.y, wall.$2.y) - half;
    final hiY = math.max(wall.$1.y, wall.$2.y) + half;
    final colFrom = math.max(0, ((loX - minX) / resolution).floor());
    final colTo = math.min(width - 1, ((hiX - minX) / resolution).ceil());
    final rowFrom = math.max(
      0,
      height - 1 - ((hiY - minY) / resolution).ceil(),
    );
    final rowTo = math.min(
      height - 1,
      height - 1 - ((loY - minY) / resolution).floor(),
    );
    for (var row = rowFrom; row <= rowTo; row++) {
      for (var col = colFrom; col <= colTo; col++) {
        final center = grid.centerOf(col, row);
        if (_distanceToSegment(center, wall.$1, wall.$2) <= half) {
          cells[row * width + col] = OccupancyGrid.occupied;
        }
      }
    }
  }
  return grid;
}

/// 점이 다각형 안인가. 반직선을 쏴서 넘는 횟수를 센다.
bool _insidePolygon(GridPoint point, List<GridPoint> polygon) {
  var inside = false;
  for (var i = 0, j = polygon.length - 1; i < polygon.length; j = i++) {
    final a = polygon[i];
    final b = polygon[j];
    if ((a.y > point.y) != (b.y > point.y) &&
        point.x < (b.x - a.x) * (point.y - a.y) / (b.y - a.y) + a.x) {
      inside = !inside;
    }
  }
  return inside;
}

/// 점에서 선분까지의 거리.
double _distanceToSegment(GridPoint point, GridPoint start, GridPoint end) {
  final dx = end.x - start.x;
  final dy = end.y - start.y;
  final lengthSquared = dx * dx + dy * dy;
  if (lengthSquared <= 0) {
    return math.sqrt(
      math.pow(point.x - start.x, 2) + math.pow(point.y - start.y, 2),
    );
  }
  var t = ((point.x - start.x) * dx + (point.y - start.y) * dy) / lengthSquared;
  t = t.clamp(0.0, 1.0);
  final nearestX = start.x + t * dx;
  final nearestY = start.y + t * dy;
  return math.sqrt(
    math.pow(point.x - nearestX, 2) + math.pow(point.y - nearestY, 2),
  );
}
