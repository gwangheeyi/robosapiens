/// 도면 아래 Waypoint 표에 무엇을 적을지.
///
/// 표는 값을 **숫자로** 고치는 자리다. 그러니 표가 보여 주는 값이 배포에 나가는
/// 그 값이어야 한다 — 다르면 사람은 화면을 믿고, 화면이 틀린 것을 배포한다.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:rmf_control_ui/waypoint_table.dart';

void main() {
  List<WaypointRow> rowsFor({
    required List<Offset> waypoints,
    Map<Offset, String> categories = const {},
    Map<Offset, String> names = const {},
    Map<Offset, double> dockHeadings = const {},
    List<(Offset, Offset)> lanes = const [],
    List<WaypointRobotBinding> Function(String name)? robotsAt,
    double? metersPerPixel,
  }) => buildWaypointRows(
    waypoints: waypoints,
    categories: categories,
    names: names,
    dockHeadings: dockHeadings,
    lanes: lanes,
    robotsAt: robotsAt ?? (_) => const [],
    metersPerPixel: metersPerPixel,
  );

  group('좌표', () {
    test('픽셀을 RMF 월드 좌표로 옮긴다 — 건물 안은 y 가 음수다', () {
      // 화면에 좋아 보이라고 y 부호를 뒤집으면 안 된다. 그 값을 그대로 spawn
      // 좌표로 넣은 사고가 실제로 났다 — 로봇이 건물 밖 허공에서 떨어졌다.
      final row = rowsFor(
        waypoints: [const Offset(1002.398, 1971.968)],
        metersPerPixel: 0.00115686,
      ).single;
      expect(row.world!.x, closeTo(1.160, .001));
      expect(row.world!.y, closeTo(-2.281, .001));
    });

    test('축척을 안 재었으면 미터를 비워 둔다', () {
      // 모르는 값을 0 으로 적으면 사람이 그것을 믿는다.
      final row = rowsFor(waypoints: [const Offset(100, 200)]).single;
      expect(row.world, isNull);
      expect(row.point, const Offset(100, 200));
    });
  });

  group('building.yaml 속성', () {
    test('카테고리가 속성 이름을 정한다', () {
      expect(
        waypointVertexProperties(
          category: '주차',
          name: '주차1',
          dockHeadingDegrees: null,
        ),
        ['is_parking_spot'],
      );
      expect(
        waypointVertexProperties(
          category: '충전',
          name: '충전2',
          dockHeadingDegrees: null,
        ),
        ['is_charger'],
      );
      expect(
        waypointVertexProperties(
          category: '대기',
          name: '',
          dockHeadingDegrees: null,
        ),
        ['is_holding_point'],
      );
      expect(
        waypointVertexProperties(
          category: '설비',
          name: '설비3',
          dockHeadingDegrees: null,
        ),
        ['robosapiens_equipment'],
      );
    });

    test('픽업·드랍오프는 이름이 곧 RMF 의 target_guid 다', () {
      expect(
        waypointVertexProperties(
          category: '픽업',
          name: '픽업3',
          dockHeadingDegrees: null,
        ),
        ['pickup_dispenser: 픽업3'],
      );
      expect(
        waypointVertexProperties(
          category: '드랍오프',
          name: '드랍오프2',
          dockHeadingDegrees: null,
        ),
        ['dropoff_ingestor: 드랍오프2'],
      );
      // 이름이 없으면 붙일 것이 없다. 빈 이름으로 내보내면 그 자리로 보내는
      // 작업이 RMF 안에서 영원히 멈춘다.
      expect(
        waypointVertexProperties(
          category: '픽업',
          name: '  ',
          dockHeadingDegrees: null,
        ),
        isEmpty,
      );
    });

    test('적재 방향은 물건을 주고받는 자리에만 붙는다', () {
      expect(
        waypointVertexProperties(
          category: '픽업',
          name: '픽업3',
          dockHeadingDegrees: 90.3,
        ),
        ['pickup_dispenser: 픽업3', 'robosapiens_dock_heading: 90.300'],
      );
      // 지나가기만 하는 자리에는 뜻이 없다.
      expect(
        waypointVertexProperties(
          category: '대기',
          name: '대기1',
          dockHeadingDegrees: 90.3,
        ),
        ['is_holding_point'],
      );
      expect(waypointUsesDockHeading('픽업'), isTrue);
      expect(waypointUsesDockHeading('드랍오프'), isTrue);
      expect(waypointUsesDockHeading('설비'), isFalse);
      expect(waypointUsesDockHeading(null), isFalse);
    });
  });

  group('이름', () {
    test('대기 지점만 이름 없이 둘 수 있다', () {
      expect(waypointNeedsName('대기'), isFalse);
      for (final category in ['주차', '홈', '충전', '픽업', '드랍오프', '설비']) {
        expect(waypointNeedsName(category), isTrue, reason: category);
      }
    });

    test('이름이 있어야 하는데 비면 그 줄을 표시한다', () {
      final rows = rowsFor(
        waypoints: [const Offset(10, 10), const Offset(20, 20)],
        categories: {const Offset(10, 10): '픽업', const Offset(20, 20): '대기'},
      );
      expect(rows[0].isMissingName, isTrue);
      expect(rows[1].isMissingName, isFalse);
    });
  });

  test('붙어 있는 Lane 수를 센다', () {
    const hub = Offset(10, 10);
    final rows = rowsFor(
      waypoints: [hub, const Offset(50, 50)],
      lanes: [
        (hub, const Offset(50, 50)),
        (const Offset(90, 90), hub),
        (const Offset(90, 90), const Offset(120, 120)),
      ],
    );
    expect(rows[0].laneCount, 2);
    expect(rows[1].laneCount, 1);
  });

  group('이 자리의 로봇', () {
    const omx = WaypointRobotBinding(
      robotId: 'omx_01',
      displayName: 'OMX-01',
      isMobile: false,
      spawnX: 1.160,
      spawnY: -2.281,
    );

    test('등록은 자리를 이름으로 가리킨다', () {
      final rows = rowsFor(
        waypoints: [const Offset(1002.398, 1971.968)],
        categories: {const Offset(1002.398, 1971.968): '설비'},
        names: {const Offset(1002.398, 1971.968): '설비3'},
        metersPerPixel: 0.00115686,
        robotsAt: (name) => name == '설비3' ? const [omx] : const [],
      );
      expect(rows.single.robots.single.robotId, 'omx_01');
      expect(rows.single.robots.single.kindLabel, '설치');
    });

    test('이동 로봇은 충전 자리에, 설치 로봇은 설비 자리에만 선다', () {
      // 아무 자리에나 묶을 수 있게 두면 핑키의 충전 자리가 통행로 한가운데로
      // 잡힌다. 픽업·드랍오프는 로봇이 가는 자리지 서 있는 자리가 아니다.
      expect(waypointRobotIsMobile('충전'), isTrue);
      expect(waypointRobotIsMobile('설비'), isFalse);
      for (final category in ['픽업', '드랍오프', '대기', '주차', '홈', null]) {
        expect(waypointRobotIsMobile(category), isNull, reason: '$category');
      }
    });

    test('이름이 없으면 짝지을 것이 없다', () {
      final rows = rowsFor(
        waypoints: [const Offset(10, 10)],
        robotsAt: (_) => const [omx],
      );
      expect(rows.single.robots, isEmpty);
    });

    test('자리를 옮기면 등록에 남은 옛 좌표와 벌어진 만큼을 알린다', () {
      // Waypoint 를 끌어 옮겨도 등록의 좌표는 따라오지 않는다. 그대로 배포하면
      // 팔은 옛 자리에 서고 핑키만 새 자리로 간다.
      final rows = rowsFor(
        // 설비3 을 0.10m 쯤(약 86px) 위로 옮긴 자리.
        waypoints: [const Offset(1002.398, 1885.5)],
        names: {const Offset(1002.398, 1885.5): '설비3'},
        metersPerPixel: 0.00115686,
        robotsAt: (name) => name == '설비3' ? const [omx] : const [],
      );
      expect(rows.single.spawnDriftMeters, closeTo(.100, .002));
    });

    test('축척이 없으면 얼마나 벌어졌는지 말하지 않는다', () {
      final rows = rowsFor(
        waypoints: [const Offset(10, 10)],
        names: {const Offset(10, 10): '설비3'},
        robotsAt: (_) => const [omx],
      );
      expect(rows.single.spawnDriftMeters, isNull);
    });
  });

  test('카테고리끼리 모으고 이름 없는 것은 뒤로 보낸다', () {
    final rows = sortWaypointRows(
      rowsFor(
        waypoints: [
          const Offset(10, 10),
          const Offset(20, 20),
          const Offset(30, 30),
          const Offset(40, 40),
        ],
        categories: {
          const Offset(10, 10): '픽업',
          const Offset(20, 20): '대기',
          const Offset(30, 30): '대기',
          const Offset(40, 40): '충전',
        },
        names: {
          const Offset(10, 10): '픽업3',
          const Offset(20, 20): '대기1',
          const Offset(40, 40): '충전2',
        },
      ),
    );
    // 순서는 waypointCategories 를 따른다: 대기 → 충전 → 픽업.
    expect(rows.map((row) => row.category), ['대기', '대기', '충전', '픽업']);
    // 같은 카테고리 안에서는 이름 없는 것이 뒤다.
    expect(rows[0].name, '대기1');
    expect(rows[1].name, isEmpty);
    // 자리(index)는 좌표가 아니라 `_laneWaypoints` 의 순서 그대로다.
    expect(rows.map((row) => row.index), [1, 2, 3, 0]);
  });

  group('숫자 칸 읽기', () {
    test('빈 칸과 오타를 가른다', () {
      // 빈 칸은 "안 정함" 이고 오타는 잘못이다. 같이 다루면 오타가 조용히
      // 값을 지운다.
      expect(readNumberField('  '), (empty: true, value: null));
      expect(readNumberField('1.2ㅁ'), (empty: false, value: null));
      expect(readNumberField(' -2.281 '), (empty: false, value: -2.281));
      expect(readNumberField('0'), (empty: false, value: 0.0));
    });
  });
}
