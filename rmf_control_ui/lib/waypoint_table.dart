/// Waypoint 하나가 가진 값들을 표 한 줄로 모은다.
///
/// 도면 위에서는 Waypoint 를 끌어서 옮긴다. 눈으로 맞추는 일이라 1픽셀 아래로는
/// 못 내려가고, 그 1픽셀이 실제로는 몇 밀리미터인지 화면만 봐서는 모른다.
/// 팔과 핑키가 부딪힌 자리도 그렇게 만들어졌다 — 도면에서는 떨어져 보였는데
/// 미터로 재면 0.34m 였다.
///
/// 그래서 값을 **숫자로** 고칠 자리를 따로 둔다. 여기서 하는 것은 한 줄에
/// 무엇을 적을지 고르는 일뿐이고, 화면도 상태도 밖에 있다 — 규칙은 눌러 보지
/// 않고도 확인할 수 있어야 한다([RobotLink] 와 같은 이유다).
library;

import 'dart:math' as math;
import 'dart:ui' show Offset;

/// Waypoint 카테고리와 traffic_editor 속성 이름의 짝.
///
/// building.yaml 내보내기와 화면이 **같은 표를 봐야 한다.** 따로 적어 두면
/// 한쪽만 고쳤을 때 화면은 `is_parking_spot` 이라고 하는데 실제로는 안 나가는
/// 일이 생긴다. 그때 사람은 화면을 믿는다.
const Map<String, String> waypointTrafficEditorProperty = {
  '충전': 'is_charger',
  '주차': 'is_parking_spot',
  '대기': 'is_holding_point',
};

/// 고를 수 있는 Waypoint 카테고리. 표의 드롭다운과 수정 창이 같은 것을 쓴다.
const List<String> waypointCategories = [
  '대기',
  '주차',
  '홈',
  '충전',
  '픽업',
  '드랍오프',
  '설비',
];

/// 물건을 주고받는 자리인가. 이 자리에만 적재 방향이 뜻을 갖는다.
bool waypointUsesDockHeading(String? category) =>
    category == '픽업' || category == '드랍오프';

/// 카테고리를 바꾸면서 정해 둔 적재 방향이 버려지는가. 안 버려지면 null.
///
/// 픽업·드랍오프가 아닌 자리에 각도를 남겨 두면, 나중에 다시 픽업으로 바꿨을
/// 때 잊어버린 옛 각도가 되살아난다. 그래서 지우는 것이 맞다 — 다만 **말없이**
/// 지우면 안 된다.
///
/// 실제로 픽업3 에 180 도를 넣었다고 기억하는데 저장된 프로젝트에도 배포된
/// building.yaml 에도 각도가 없던 일이 있었다. 지울 때 아무 말이 없으니 사람은
/// 넣은 줄로 남아 있고, 앱은 없는 상태로 간다. 여기서 무슨 값이 사라지는지
/// 돌려주고, 부르는 쪽이 그것을 사람에게 보인다.
String? dockHeadingDropMessage({
  required String? previousCategory,
  required String? newCategory,
  required String waypointName,
  required double? dockHeadingDegrees,
}) {
  if (dockHeadingDegrees == null) return null;
  if (!waypointUsesDockHeading(previousCategory)) return null;
  if (waypointUsesDockHeading(newCategory)) return null;
  final name = waypointName.trim();
  final where = name.isEmpty ? '이 자리' : name;
  return '$where 의 적재 방향 '
      '${_degreesLabel(dockHeadingDegrees)}도를 지웠습니다 — '
      '$newCategory 자리는 방향을 안 씁니다.';
}

/// 각도를 사람이 읽을 글자로. 소수점 뒤가 0 이면 떼어 낸다.
String _degreesLabel(double degrees) {
  final text = degrees.toStringAsFixed(1);
  return text.endsWith('.0') ? text.substring(0, text.length - 2) : text;
}

/// 이 자리에 세울 수 있는 로봇 종류. 로봇이 서는 자리가 아니면 null.
///
/// 참이면 이동 로봇, 거짓이면 설치 로봇이다
/// (`RmfRobotKind.waypointCategory` 의 반대 방향).
///
/// 픽업·드랍오프·대기는 로봇이 **가는** 자리지 서 있는 자리가 아니다. 거기에
/// 로봇을 묶으면 그 로봇의 spawn 좌표가 통행로 한가운데로 잡힌다.
bool? waypointRobotIsMobile(String? category) => switch (category) {
  '충전' => true,
  '설비' => false,
  _ => null,
};

/// 이 카테고리에 이름이 반드시 있어야 하는가.
///
/// 대기 지점은 이름 없이 둘 수 있다 — 시나리오 자동 배치가 이름 없는 대기
/// Waypoint 를 후보로 쓴다. 나머지는 이름이 곧 RMF 의 `target_guid` 라서,
/// 비면 그 자리로 보내는 작업이 RMF 안에서 영원히 멈춘다.
bool waypointNeedsName(String? category) => category != '대기';

/// 이 Waypoint 가 building.yaml 에 달고 나갈 속성. 사람이 읽을 형태다.
///
/// 카테고리를 바꾸면 무엇이 따라 바뀌는지 표에서 바로 보인다. `is_parking_spot`
/// 같은 이름을 그대로 적는 것은, 문제를 찾을 때 사람이 결국 그 이름으로
/// building.yaml 을 뒤지기 때문이다.
List<String> waypointVertexProperties({
  required String? category,
  required String name,
  required double? dockHeadingDegrees,
}) {
  final trimmed = name.trim();
  return [
    ?waypointTrafficEditorProperty[category],
    if (category == '픽업' && trimmed.isNotEmpty) 'pickup_dispenser: $trimmed',
    if (category == '드랍오프' && trimmed.isNotEmpty) 'dropoff_ingestor: $trimmed',
    if (category == '설비') 'robosapiens_equipment',
    if (dockHeadingDegrees != null && waypointUsesDockHeading(category))
      'robosapiens_dock_heading: ${dockHeadingDegrees.toStringAsFixed(3)}',
  ];
}

/// 이 자리에 등록된 로봇.
///
/// 등록의 자리 Waypoint 는 **이름으로** 가리킨다. 그래서 Waypoint 이름을 고치면
/// 그 짝이 끊어지고, 자리를 옮기면 등록의 spawn 좌표만 옛 자리에 남는다.
/// 둘 다 표에서 보여야 한다 — 안 보이면 배포하고 나서야 안다.
class WaypointRobotBinding {
  const WaypointRobotBinding({
    required this.robotId,
    required this.displayName,
    required this.isMobile,
    required this.spawnX,
    required this.spawnY,
  });

  final String robotId;
  final String displayName;

  /// 이동 로봇이면 참, 설치 로봇(팔)이면 거짓.
  final bool isMobile;

  /// 등록에 적힌 자리 [m]. 아직 안 정해졌으면 null.
  final double? spawnX;
  final double? spawnY;

  String get kindLabel => isMobile ? '이동' : '설치';
}

/// 표 한 줄.
class WaypointRow {
  const WaypointRow({
    required this.index,
    required this.point,
    required this.name,
    required this.category,
    required this.dockHeadingDegrees,
    required this.world,
    required this.properties,
    required this.laneCount,
    required this.robots,
  });

  /// `_laneWaypoints` 에서의 자리.
  ///
  /// 좌표가 아니라 이것으로 줄을 가린다. Waypoint 는 좌표 자체가 열쇠라서,
  /// 숫자를 고치는 순간 열쇠가 바뀐다 — 좌표로 줄을 가리면 고치는 도중에 줄이
  /// 사라졌다 다시 생긴 것처럼 보여 입력하던 칸이 초기화된다.
  final int index;

  /// 도면 픽셀 좌표.
  final Offset point;

  final String name;

  /// 카테고리. 아직 안 정했으면 null.
  final String? category;

  /// 적재 방향 [도]. 안 정했으면 null.
  final double? dockHeadingDegrees;

  /// RMF 월드 좌표 [m]. 축척을 아직 안 재었으면 null.
  final ({double x, double y})? world;

  /// building.yaml 에 나갈 속성.
  final List<String> properties;

  /// 이 자리에 붙어 있는 Lane 수.
  final int laneCount;

  /// 이 자리를 자기 자리로 등록한 로봇들.
  final List<WaypointRobotBinding> robots;

  /// 등록된 자리와 지금 Waypoint 가 벌어진 거리 [m]. 잴 수 없으면 null.
  ///
  /// 가장 많이 벌어진 로봇으로 본다. 하나라도 어긋나면 배포가 어긋난다.
  double? get spawnDriftMeters {
    final here = world;
    if (here == null) return null;
    double? worst;
    for (final robot in robots) {
      final x = robot.spawnX;
      final y = robot.spawnY;
      if (x == null || y == null) continue;
      final gap = math.sqrt(math.pow(here.x - x, 2) + math.pow(here.y - y, 2));
      if (worst == null || gap > worst) worst = gap;
    }
    return worst;
  }

  /// 이름이 비어 있어 RMF 에서 못 찾는 자리인가.
  bool get isMissingName => waypointNeedsName(category) && name.trim().isEmpty;
}

/// 상태를 표 줄로 옮긴다.
///
/// [metersPerPixel] 이 null 이면 미터 칸을 비워 둔다 — 축척을 안 재었으면
/// 픽셀만 아는 것이고, 모르는 값을 0 으로 적으면 사람이 그것을 믿는다.
List<WaypointRow> buildWaypointRows({
  required List<Offset> waypoints,
  required Map<Offset, String> categories,
  required Map<Offset, String> names,
  required Map<Offset, double> dockHeadings,
  required List<(Offset, Offset)> lanes,
  required List<WaypointRobotBinding> Function(String name) robotsAt,
  double? metersPerPixel,
}) {
  final rows = <WaypointRow>[];
  for (var index = 0; index < waypoints.length; index++) {
    final point = waypoints[index];
    final name = (names[point] ?? '').trim();
    final category = categories[point];
    final heading = dockHeadings[point];
    var laneCount = 0;
    for (final lane in lanes) {
      if ((lane.$1 - point).distance <= .01 ||
          (lane.$2 - point).distance <= .01) {
        laneCount++;
      }
    }
    rows.add(
      WaypointRow(
        index: index,
        point: point,
        name: name,
        category: category,
        dockHeadingDegrees: heading,
        world: metersPerPixel == null || metersPerPixel <= 0
            ? null
            : (x: point.dx * metersPerPixel, y: -point.dy * metersPerPixel),
        properties: waypointVertexProperties(
          category: category,
          name: name,
          dockHeadingDegrees: heading,
        ),
        laneCount: laneCount,
        robots: name.isEmpty ? const [] : robotsAt(name),
      ),
    );
  }
  return rows;
}

/// 표를 보여 줄 차례.
///
/// 카테고리끼리 모아 두면 고칠 것을 찾기 쉽다. 같은 카테고리 안에서는 이름
/// 순이고, 이름이 없는 것은 뒤로 보낸다 — 채워야 할 것이 눈에 띈다.
List<WaypointRow> sortWaypointRows(List<WaypointRow> rows) {
  const order = waypointCategories;
  final sorted = [...rows];
  sorted.sort((a, b) {
    final categoryRank = order
        .indexOf(a.category ?? '')
        .compareTo(order.indexOf(b.category ?? ''));
    if (categoryRank != 0) return categoryRank;
    if (a.name.isEmpty != b.name.isEmpty) return a.name.isEmpty ? 1 : -1;
    final byName = a.name.compareTo(b.name);
    if (byName != 0) return byName;
    return a.index.compareTo(b.index);
  });
  return sorted;
}

/// 사람이 친 숫자를 읽는다. 못 읽으면 null.
///
/// 빈 칸과 못 읽는 글자를 가른다. 빈 칸은 "안 정함" 이고 못 읽는 글자는
/// **잘못**이다 — 둘을 같이 다루면 오타가 조용히 값을 지운다.
({bool empty, double? value}) readNumberField(String text) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) return (empty: true, value: null);
  return (empty: false, value: double.tryParse(trimmed));
}
