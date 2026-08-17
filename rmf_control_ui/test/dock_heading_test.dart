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
import 'package:rmf_control_ui/nav2_params.dart';
import 'package:rmf_control_ui/rmf_task_request.dart';

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
}
