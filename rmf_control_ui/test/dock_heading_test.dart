/// 픽업 자리에서 **완전히 돌고 나서** 팔이 움직이는지 지킨다.
///
/// 핑키는 수납함을 뒤에 달고 다닌다. 픽업 자리에 들어온 그대로 서면 수납함이
/// 팔에서 가장 먼 자리에 온다. 그래서 자리마다 로봇이 볼 방향을 정해 두고,
/// 그 각도까지 맞을 때까지 도착으로 치지 않는다.
///
/// 사슬은 이렇다. 한 마디라도 끊기면 로봇이 엉뚱한 자세로 서고, 팔은 허공을
/// 집는다 —
///
///     맵 관리 `적재 방향`
///       → 프로젝트 JSON `dockHeading`
///       → building.yaml `robosapiens_dock_heading`
///       → 작업 JSON `go_to_place` 의 `orientation` (rad)
///       → RMF 경로계획의 마지막 자세 (`FleetUpdateHandle.cpp` 가 읽는다)
///       → Nav2 `NavigateToPose` 목표 자세
///       → `yaw_goal_tolerance` 안에 들어와야 SUCCEEDED
///       → 어댑터 `execution.finished()`
///       → 그제서야 `perform_action` 이 시작된다
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rmf_control_ui/deploy_preflight.dart';
import 'package:rmf_control_ui/nav2_params.dart';
import 'package:rmf_control_ui/rmf_task_request.dart';
import 'package:rmf_control_ui/waypoint_table.dart';

void main() {
  group('작업 JSON', () {
    Map<String, Object?> firstActivity(RmfTaskConversion converted) =>
        converted.activities.first.toJson();

    test('각도를 정한 자리는 orientation 을 싣는다', () {
      final converted = convertTaskSteps([
        const RmfTaskStepInput(kind: 'navigate', placeName: '픽업3'),
      ], dockHeadingDegrees: (place) => place == '픽업3' ? 180.0 : null);
      final activity = firstActivity(converted);
      expect(activity['category'], 'go_to_place');
      final description = activity['description'] as Map<String, Object?>;
      expect(description['waypoint'], '픽업3');
      // RMF 는 라디안만 쓴다. 180도를 그대로 보내면 로봇이 몇 바퀴를 돈다.
      expect(description['orientation'] as double, closeTo(3.14159, 0.0001));
    });

    test('각도를 안 정한 자리는 이름만 보낸다', () {
      // `orientation: null` 을 실으면 RMF 스키마가 숫자만 받으므로 단계
      // 하나가 아니라 **작업 전체**가 거절된다.
      final converted = convertTaskSteps([
        const RmfTaskStepInput(kind: 'navigate', placeName: '대기1'),
      ], dockHeadingDegrees: (_) => null);
      expect(firstActivity(converted)['description'], '대기1');
    });

    test('조회 함수를 안 주면 예전 그대로다', () {
      final converted = convertTaskSteps([
        const RmfTaskStepInput(kind: 'navigate', placeName: '픽업1'),
      ]);
      expect(firstActivity(converted)['description'], '픽업1');
    });

    test('홈 복귀도 채워진 자리 이름으로 각도를 찾는다', () {
      // 홈 복귀는 목적지가 비어 있으면 `homePlaceName` 으로 채워진다. 채우기
      // 전에 각도를 찾으면 홈의 각도를 영영 못 쓴다.
      final asked = <String>[];
      final converted = convertTaskSteps(
        [const RmfTaskStepInput(kind: 'returnHome')],
        homePlaceName: '드랍오프2',
        dockHeadingDegrees: (place) {
          asked.add(place);
          return place == '드랍오프2' ? -90.0 : null;
        },
      );
      expect(asked, ['드랍오프2']);
      final description =
          firstActivity(converted)['description'] as Map<String, Object?>;
      expect(description['waypoint'], '드랍오프2');
      expect(description['orientation'] as double, closeTo(-1.5708, 0.0001));
    });

    test('0도는 각도를 안 정한 것과 다르다', () {
      // 0도는 "도면 오른쪽을 보라" 는 뜻이다. 없는 것으로 뭉뚱그리면 그 자리만
      // 조용히 아무 자세로 선다.
      final converted = convertTaskSteps([
        const RmfTaskStepInput(kind: 'navigate', placeName: '픽업1'),
      ], dockHeadingDegrees: (_) => 0.0);
      final description =
          firstActivity(converted)['description'] as Map<String, Object?>;
      expect(description['orientation'], 0.0);
    });

    test('보내는 JSON 이 RMF 의 place 스키마와 같은 모양이다', () {
      // `place.json` 은 `{"waypoint": …, "orientation": …}` 만 받는다.
      final request = buildRmfTaskRequest(
        fleetName: 'pinky_fleet',
        robotId: 'pinky_01',
        activities: convertTaskSteps([
          const RmfTaskStepInput(kind: 'navigate', placeName: '픽업3'),
        ], dockHeadingDegrees: (_) => 180.0).activities,
      );
      final text = jsonEncode(request.decoded);
      expect(text, contains('"waypoint":"픽업3"'));
      expect(text, contains('"orientation"'));
    });
  });

  group('Nav2 도착 각도', () {
    test('약 5도로 조인다', () {
      // 수납함이 로봇 중심에서 30cm 뒤에 있다. 벤더 값 0.25rad(14도)면
      // 수납함이 옆으로 7cm 어긋나 팔이 헛집는다.
      expect(dockYawTolerance, closeTo(0.087, 0.001));
      expect(dockYawTolerance * 30, lessThan(3.0)); // cm
    });

    test('벤더 파일의 yaw_goal_tolerance 를 실제로 바꾼다', () {
      final rewrite = rewriteNav2Params(
        source: '''
controller_server:
  ros__parameters:
    general_goal_checker:
      plugin: "nav2_controller::SimpleGoalChecker"
      yaw_goal_tolerance: 0.25                   # 약 14도
''',
        namespace: 'pinky_01',
      );
      expect(rewrite.yaml, contains('yaw_goal_tolerance: 0.087'));
      // 왜 바꿨는지 남는 주석은 살린다.
      expect(rewrite.yaml, contains('# 약 14도'));
      expect(
        rewrite.changes.any((change) => change.contains('yaw_goal_tolerance')),
        isTrue,
      );
    });

    test('바퀴가 안 도는 구간까지 조이지는 않는다', () {
      // 너무 조이면 차동 구동이 목표 주변에서 좌우로 떤다.
      expect(dockYawTolerance, greaterThan(0.05));
    });
  });

  group('맵에 적어 두는 각도', () {
    late String source;
    setUpAll(() => source = File('lib/main.dart').readAsStringSync());

    test('building.yaml 에 traffic_editor 형식으로 적는다', () {
      // `[3, 값]` 의 3 이 실수다. RMF 는 모르는 이름의 정점 속성을 그냥
      // 지나치므로(`parse_graph.cpp` 는 아는 이름만 읽는다) 넣어도 안전하다.
      expect(source, contains('robosapiens_dock_heading: [3, '));
    });

    test('프로젝트 JSON 에 담고 되읽는다', () {
      expect(source, contains("'dockHeading': ?_waypointDockHeadings[point]"));
      expect(
        source,
        contains("waypoint['dockHeading'] case final num heading"),
      );
    });

    test('Waypoint 를 옮겨도 각도가 따라간다', () {
      // 안 옮기면 Waypoint 를 조금 끌었을 뿐인데 각도가 조용히 사라진다.
      expect(source, contains('_waypointDockHeadings[updated] = dockHeading'));
    });

    test('되돌리기가 각도까지 되돌린다', () {
      expect(
        source,
        contains('waypointDockHeadings: {..._waypointDockHeadings}'),
      );
      expect(source, contains('..addAll(snapshot.waypointDockHeadings)'));
    });

    test('배포 맵에서도 각도를 되찾는다', () {
      // 프로젝트를 편집기에 안 열어도 작업을 보낼 수 있어야 한다.
      final loader = File(
        'lib/deployed_map_service_io.dart',
      ).readAsStringSync();
      expect(loader, contains('robosapiens_dock_heading'));
      expect(loader, contains("waypoint['dockHeading']"));
      expect(loader, contains('waypointDockHeadings'));
    });

    test('배포 맵을 불러왔으면 편집기 값이 몰래 섞이지 않는다', () {
      // 화면에서 고친 각도로 작업을 보냈는데 로봇이 든 nav graph 에는 그 자리가
      // 없으면, 어디가 어긋났는지 찾는 데 시간을 버린다.
      final start = source.indexOf(
        'double? _dockHeadingDegreesFor(String place)',
      );
      expect(start, greaterThanOrEqualTo(0));
      final body = source.substring(start, source.indexOf('\n  }', start));
      final deployedBranch = body.indexOf('if (deployed != null)');
      final fallback = body.indexOf(
        'for (final entry in _waypointDockHeadings',
      );
      expect(deployedBranch, greaterThanOrEqualTo(0));
      // 배포 맵 갈래 안에서 먼저 return 하고 끝나야 한다.
      expect(
        body.substring(deployedBranch, fallback),
        contains('return null;'),
      );
    });
  });

  /// 각도가 **말없이** 사라지는 것을 막는다.
  ///
  /// 픽업3 에 180 도를 넣었다고 기억하는데 저장된 프로젝트에도 배포된
  /// building.yaml 에도 각도가 없던 일이 있었다. 저장·불러오기 왕복은 멀쩡했다
  /// — 카테고리를 바꾸는 순간 각도가 아무 말 없이 지워진 것이다. 사람의 기억과
  /// 앱의 상태가 갈릴 수 있는 값이라 두 곳에서 잡는다.
  group('사라지는 각도를 밝힌다', () {
    /// 대기도 방향을 쓰게 되었으므로 픽업 → 대기 는 각도가 안 사라진다.
    /// 방향을 안 쓰는 자리(주차·홈·설비)로 바꿀 때만 사라진다.
    test('방향을 안 쓰는 자리로 바꾸면 무슨 값이 사라지는지 적는다', () {
      final message = dockHeadingDropMessage(
        previousCategory: '픽업',
        newCategory: '주차',
        waypointName: '픽업3',
        dockHeadingDegrees: 180,
      );
      expect(message, isNotNull);
      expect(message, contains('픽업3'));
      // 사라진 각도를 숫자로 적어야 손으로 다시 넣을 수 있다.
      expect(message, contains('180'));
      expect(message, contains('주차'));
    });

    /// 대기 자리에서 -45도로 선 뒤 후진으로 픽업에 들어가는 식으로 쓴다.
    /// 그 각도가 카테고리를 오갈 때 사라지면 안 된다.
    test('픽업에서 대기로는 각도가 그대로라 알리지 않는다', () {
      expect(
        dockHeadingDropMessage(
          previousCategory: '픽업',
          newCategory: '대기',
          waypointName: '픽업3',
          dockHeadingDegrees: 180,
        ),
        isNull,
      );
    });

    test('소수점 뒤가 0 이면 떼고 적는다', () {
      expect(
        dockHeadingDropMessage(
          previousCategory: '드랍오프',
          newCategory: '설비',
          waypointName: '드랍오프1',
          dockHeadingDegrees: 90,
        ),
        contains('90도'),
      );
      expect(
        dockHeadingDropMessage(
          previousCategory: '드랍오프',
          newCategory: '설비',
          waypointName: '드랍오프1',
          dockHeadingDegrees: 45.5,
        ),
        contains('45.5도'),
      );
    });

    test('픽업에서 드랍오프로는 각도가 그대로라 알리지 않는다', () {
      expect(
        dockHeadingDropMessage(
          previousCategory: '픽업',
          newCategory: '드랍오프',
          waypointName: '픽업3',
          dockHeadingDegrees: 180,
        ),
        isNull,
      );
    });

    test('정해 둔 각도가 없으면 사라질 것도 없다', () {
      expect(
        dockHeadingDropMessage(
          previousCategory: '픽업',
          newCategory: '대기',
          waypointName: '픽업3',
          dockHeadingDegrees: null,
        ),
        isNull,
      );
    });

    test('표와 대화상자 두 곳 다 알린다', () {
      final source = File('lib/main.dart').readAsStringSync();
      // 지우기 **전에** 읽어야 한다. 지운 뒤에는 물어볼 곳이 없다.
      expect(
        'dockHeadingDropMessage('.allMatches(source).length,
        2,
        reason: '_setWaypointCategory 와 _editWaypoint 둘 다에서 봐야 한다',
      );
      expect(source, contains('_showDockHeadingDropped(dropped)'));
    });
  });

  group('배포 전 점검', () {
    DockHeadingCheck check(String name, String category, double? degrees) =>
        DockHeadingCheck(name: name, category: category, degrees: degrees);

    test('각도를 안 정한 픽업·드랍오프를 이름으로 짚는다', () {
      final message = missingDockHeadingMessage([
        check('픽업3', '픽업', null),
        check('드랍오프1', '드랍오프', 90),
        check('픽업1', '픽업', 0),
      ]);
      expect(message, isNotNull);
      expect(message, contains('픽업3'));
      // 정해 둔 자리는 안 짚는다. 0 도는 "안 정했다" 가 아니라 오른쪽이다.
      expect(message, isNot(contains('드랍오프1')));
      expect(message, isNot(contains('픽업1')));
      // 무엇이 안 나가는지와 그 결과를 적는다.
      expect(message, contains('robosapiens_dock_heading'));
      expect(message, contains('적재 방향 (도)'));
    });

    test('방향을 안 쓰는 자리는 따지지 않는다', () {
      expect(
        missingDockHeadingMessage([
          check('설비3', '설비', null),
          check('', '대기', null),
        ]),
        isNull,
      );
    });

    /// 충전 단자는 로봇 한쪽에만 있다. 방향이 없으면 도착은 했는데 접점이 안
    /// 맞고, 그것은 배포하고 로봇을 세워 본 뒤에야 안다.
    test('각도 없는 충전 자리도 배포 전에 알린다', () {
      final message = missingDockHeadingMessage([check('충전1', '충전', null)]);
      expect(message, isNotNull);
      expect(message, contains('충전1'));
    });

    test('각도를 정해 둔 충전 자리는 안 따진다', () {
      expect(
        missingDockHeadingMessage([check('충전1', '충전', 180)]),
        isNull,
      );
    });

    test('다 정해 놓았으면 아무 말도 안 한다', () {
      expect(
        missingDockHeadingMessage([
          check('픽업3', '픽업', 180),
          check('드랍오프1', '드랍오프', -90),
        ]),
        isNull,
      );
    });

    test('저장보다 먼저 묻는다', () {
      // 여기서 취소하고 각도를 넣으러 가는 사람이, 각도 없는 상태가 프로젝트에
      // 이미 덮어써진 채로 돌아가면 안 된다.
      final source = File('lib/main.dart').readAsStringSync();
      final ask = source.indexOf('_dockHeadingsOkBeforeDeploy()) return;');
      final save = source.indexOf('_saveBeforeDeploy()) return;');
      expect(ask, greaterThanOrEqualTo(0));
      expect(save, greaterThan(ask));
    });

    test('배포 점검은 편집기 값을 본다', () {
      // _dockHeadingDegreesFor 는 배포한 맵을 먼저 보므로 여기서 쓰면 아직 안
      // 나간 각도를 이미 나간 것으로 읽는다.
      final source = File('lib/main.dart').readAsStringSync();
      final start = source.indexOf('get _dockHeadingChecks');
      expect(start, greaterThanOrEqualTo(0));
      final body = source.substring(start, source.indexOf('\n  ];', start));
      expect(body, contains('_waypointDockHeadings[point]'));
      expect(body, isNot(contains('_dockHeadingDegreesFor')));
    });
  });
}
