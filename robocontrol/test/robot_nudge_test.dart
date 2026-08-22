/// 로봇을 몇 cm 만 밀거나 조금 돌리는 규칙.
///
/// 작업으로 보내면 도착 반경(0.1m) 안에만 들면 끝난다. 충전 단자를 맞추거나
/// 도킹 위치가 몇 cm 모자랄 때는 그보다 작은 조정이 필요하다.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:robocontrol/rmf_project_config.dart';
import 'package:robocontrol/robot_nudge.dart';

void main() {
  RmfProjectRobot robotWith({
    RobotDataSource dataSource = RobotDataSource.real,
    RmfRobotKind kind = RmfRobotKind.mobile,
  }) => RmfProjectRobot(
    robotId: 'pinky_02',
    displayName: 'PK-02',
    model: 'PINKY-GZ',
    gzName: 'pinky_02',
    zones: const ['ambient'],
    kind: kind,
    dataSource: dataSource,
    chargerWaypoint: '충전1',
  );

  group('움직일 수 있는가', () {
    test('Nav2 가 준비된 실물 이동 로봇이면 움직인다', () {
      final readiness = checkNudgeReadiness(
        robot: robotWith(),
        nav2Ready: true,
        hasActiveTask: false,
      );
      expect(readiness, NudgeReadiness.ready);
      expect(canNudge(readiness), isTrue);
      expect(nudgeBlockedReason(readiness), isNull);
    });

    /// action server 가 없으면 목표를 보내도 아무도 안 받는다. 오류도 안 난다.
    test('Nav2 가 없으면 못 움직인다', () {
      final readiness = checkNudgeReadiness(
        robot: robotWith(),
        nav2Ready: false,
        hasActiveTask: false,
      );
      expect(readiness, NudgeReadiness.nav2NotReady);
      expect(canNudge(readiness), isFalse);
    });

    /// RMF 가 로봇을 몰고 있는데 옆에서 밀면 두 명령이 서로 당긴다.
    test('작업 중이면 막는다', () {
      expect(
        checkNudgeReadiness(
          robot: robotWith(),
          nav2Ready: true,
          hasActiveTask: true,
        ),
        NudgeReadiness.busy,
      );
    });

    test('Mock 과 설치 로봇은 쓰지 않는다', () {
      expect(
        checkNudgeReadiness(
          robot: robotWith(dataSource: RobotDataSource.mock),
          nav2Ready: true,
          hasActiveTask: false,
        ),
        NudgeReadiness.mockRobot,
      );
      expect(
        checkNudgeReadiness(
          robot: robotWith(kind: RmfRobotKind.workcell),
          nav2Ready: true,
          hasActiveTask: false,
        ),
        NudgeReadiness.notMobile,
      );
    });

    test('못 움직이는 까닭은 모두 사람이 읽을 말이 있다', () {
      for (final readiness in NudgeReadiness.values) {
        if (readiness == NudgeReadiness.ready) continue;
        expect(nudgeBlockedReason(readiness), isNotNull);
      }
    });
  });

  group('사람이 친 값을 읽는다', () {
    test('cm 를 m 로 바꾼다', () {
      expect(parseNudgeCentimeters('5').meters, closeTo(0.05, 1e-9));
      expect(parseNudgeCentimeters('12.5').meters, closeTo(0.125, 1e-9));
    });

    /// 오타가 조용히 0 이 되면 안 된다.
    test('못 읽는 글자는 잘못이라고 말한다', () {
      expect(parseNudgeCentimeters('오').error, isNotNull);
      expect(parseNudgeCentimeters('5 0').error, isNotNull);
    });

    test('빈 칸은 아직 안 넣은 것이다', () {
      final empty = parseNudgeCentimeters('');
      expect(empty.error, isNull);
      expect(empty.meters, isNull);
    });

    test('0 이하는 막는다', () {
      expect(parseNudgeCentimeters('0').error, isNotNull);
      expect(parseNudgeCentimeters('-5').error, isNotNull);
    });

    /// 크게 주면 작업으로 보내는 것과 다를 바 없는데, 그쪽은 경로와 교통
    /// 관리를 거친다. 여기는 그런 것이 없다.
    test('한 번에 갈 수 있는 거리를 넘으면 막는다', () {
      expect(parseNudgeCentimeters('51').error, isNotNull);
      expect(parseNudgeCentimeters('50').error, isNull);
    });

    test('각도도 같은 규칙이다', () {
      expect(parseNudgeDegrees('15').degrees, 15);
      expect(parseNudgeDegrees('91').error, isNotNull);
      expect(parseNudgeDegrees('0').error, isNotNull);
      expect(parseNudgeDegrees('가').error, isNotNull);
    });
  });

  group('Nav2 에 보내는 목표', () {
    /// 뒤로 가는 것은 `backup` 이 맡는다. `drive_on_heading` 에 음수를 주면
    /// Nav2 가 거절한다 — 그쪽은 앞으로만 간다.
    test('앞뒤로 다른 action 을 쓴다', () {
      expect(
        nudgeActionName('pinky_02', NudgeKind.forward),
        '/pinky_02/drive_on_heading',
      );
      expect(
        nudgeActionName('pinky_02', NudgeKind.backward),
        '/pinky_02/backup',
      );
      expect(nudgeActionName('pinky_02', NudgeKind.turnLeft), '/pinky_02/spin');
    });

    test('네임스페이스를 겹쳐 붙이지 않는다', () {
      expect(
        nudgeActionName('/pinky_02/', NudgeKind.forward),
        '/pinky_02/drive_on_heading',
      );
    });

    /// **거리는 언제나 양수다.** `backup` 도 양수를 받아 뒤로 간다 — 방향은
    /// action 이 정하지 값이 정하지 않는다.
    test('뒤로 갈 때도 거리는 양수다', () {
      final goal = nudgeGoalYaml(
        kind: NudgeKind.backward,
        meters: 0.05,
        degrees: 0,
      );
      expect(goal, contains('x: 0.050'));
      expect(goal, isNot(contains('-0.05')));
    });

    test('회전은 부호로 방향을 정한다 — 반시계가 +', () {
      final left = nudgeGoalYaml(
        kind: NudgeKind.turnLeft,
        meters: 0,
        degrees: 90,
      );
      final right = nudgeGoalYaml(
        kind: NudgeKind.turnRight,
        meters: 0,
        degrees: 90,
      );
      expect(left, contains('target_yaw: 1.5708'));
      expect(right, contains('target_yaw: -1.5708'));
    });

    /// 거리에 견줘 짧게 주면 다 가기도 전에 시간이 끝나 실패로 답한다 —
    /// 로봇은 도중에 멈춰 있는데 화면은 실패라고만 말한다.
    test('시간 제한을 넉넉히 준다', () {
      final near = nudgeGoalYaml(
        kind: NudgeKind.forward,
        meters: 0.05,
        degrees: 0,
      );
      final far = nudgeGoalYaml(
        kind: NudgeKind.forward,
        meters: 0.5,
        degrees: 0,
      );
      int secondsOf(String goal) => int.parse(
        RegExp(r'sec: (\d+)').firstMatch(goal)!.group(1)!,
      );
      // 0.5m 를 0.05m/s 로 가면 10초다. 그보다 넉넉해야 한다.
      expect(secondsOf(far), greaterThan(10));
      // 짧은 거리에도 바닥이 있다.
      expect(secondsOf(near), greaterThanOrEqualTo(10));
      expect(secondsOf(far), greaterThan(secondsOf(near)));
    });

    test('형식 이름이 action 과 짝이 맞는다', () {
      expect(
        nudgeActionType(NudgeKind.forward),
        'nav2_msgs/action/DriveOnHeading',
      );
      expect(nudgeActionType(NudgeKind.backward), 'nav2_msgs/action/BackUp');
      expect(nudgeActionType(NudgeKind.turnRight), 'nav2_msgs/action/Spin');
    });
  });

  group('사람에게 보이는 말', () {
    test('무엇을 시켰는지 그대로 적는다', () {
      expect(
        nudgeLabel(kind: NudgeKind.forward, meters: 0.05, degrees: 0),
        '앞으로 5cm',
      );
      expect(
        nudgeLabel(kind: NudgeKind.backward, meters: 0.125, degrees: 0),
        '뒤로 12.5cm',
      );
      expect(
        nudgeLabel(kind: NudgeKind.turnLeft, meters: 0, degrees: 15),
        '왼쪽으로 15도',
      );
    });

    test('실패하면 어디를 볼지 적는다', () {
      final message = nudgeFailedMessage(
        robotLabel: 'PK-02',
        what: '앞으로 5cm',
        detail: '응답 없음',
      );
      expect(message, contains('behavior_server'));
      expect(message, contains('costmap'));
      expect(message, contains('map → odom'));
    });
  });
}
