/// 워크셀이 **시계가 아니라 토픽으로** 끝을 판정하는지 지킨다.
///
/// 예전에는 관절 궤적을 토픽에 던지고 4초 뒤에 성공을 알렸다. 던지고 끝이라
/// 팔이 받았는지, 움직였는지, 끝냈는지 아무도 묻지 않았다 — 팔이 느리든
/// 막혔든 구독자가 아예 없든 똑같이 성공이었고, 핑키는 빈 채로 떠났다.
///
/// 지금은 셋을 듣고 정한다 —
///
///     ① 로봇이 제자리에 제 자세로 섰나   /fleet_states
///     ② 팔이 궤적을 끝냈나               follow_joint_trajectory 액션 결과
///     ③ 팔이 정말 멈췄나                 <네임스페이스>/joint_states
///
/// 그리고 ①은 팔이 도는 **내내** 다시 본다.
///
/// 만들어진 노드를 실제로 띄워 확인한 결과(2026-08-17, 격리 도메인 99) —
///
///     로봇 소식이 없으면 팔이 안 움직인다        PASS
///     자세가 20도 틀리면 거절한다                PASS
///     자세가 3도 틀리면 통과한다                 PASS
///     팔이 3.0초 도는 동안 3.2초를 기다렸다      PASS
library;

import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:rmf_control_ui/nav2_params.dart';
import 'package:rmf_control_ui/rmf_project_config.dart';
import 'package:rmf_control_ui/workcell_pairing.dart';

const RmfProjectRobot _omx = RmfProjectRobot(
  robotId: 'omx_01',
  displayName: 'OMX-01',
  model: 'open_manipulator_x',
  gzName: 'omx_01',
  zones: [],
  kind: RmfRobotKind.workcell,
  dataSource: RobotDataSource.gazebo,
  spawnX: 1,
  spawnY: -1,
);

String _script({Map<String, double> dockHeadings = const {}}) =>
    buildWorkcellScript(
      mapName: 'project1',
      pairing: pairWorkcells(
        robots: const [_omx],
        stations: const [
          WorkcellStation(name: '픽업3', x: 1, y: -1, isDispenser: true),
        ],
      ),
      dockHeadings: dockHeadings,
    );

void main() {
  group('팔의 끝을 어떻게 아는가', () {
    test('토픽에 던지지 않고 액션으로 부른다', () {
      final code = _script();
      expect(
        code,
        contains('from control_msgs.action import FollowJointTrajectory'),
      );
      expect(code, contains('from rclpy.action import ActionClient'));
      expect(
        code,
        contains("f'/{namespace}/arm_controller/follow_joint_trajectory'"),
      );
      // 던지고 끝인 publisher 는 없어야 한다.
      expect(code, isNot(contains('arm_controller/joint_trajectory')));
      expect(code, isNot(contains('self.arm.publish(')));
    });

    test('액션 결과가 SUCCESSFUL 일 때만 성공을 낸다', () {
      final code = _script();
      expect(
        code,
        contains(
          'result.error_code != FollowJointTrajectory.Result.SUCCESSFUL',
        ),
      );
      // 성공은 액션이 끝난 뒤 정착까지 본 다음에만 낸다.
      final succeed = code.indexOf('def succeed(self, cell, job)');
      expect(succeed, greaterThanOrEqualTo(0));
      expect(
        code.substring(succeed, code.indexOf('\n    def ', succeed)),
        contains('DispenserResult.SUCCESS'),
      );
    });

    test('시계로 성공을 내지 않는다', () {
      final code = _script();
      // 예전에는 `create_timer(execution_seconds + ARM_SETTLE_SECONDS, finish)`
      // 타이머 **하나가 성공을 냈다.** 지금도 같은 이름의 상수가 있지만 뜻이
      // 다르다 — 그것은 판정이 아니라 액션이 끝난 뒤의 여유일 뿐이다.
      // 성공을 내는 타이머가 다시 생기지 않게 그 모양을 막는다.
      expect(code, isNot(contains('execution_seconds')));
      expect(code, isNot(contains('ARM_SETTLE_SECONDS, finish')));
      expect(code, isNot(contains('def finish():')));
      // 남은 타이머는 감시자 하나뿐이고, 그것은 성공이 아니라 **실패**를 낸다.
      expect(code, contains('self.create_timer(WATCHDOG_PERIOD, self.watch)'));
    });

    test('팔이 없으면 시작조차 안 한다', () {
      // 예전에는 액션 서버가 없어도 4초 뒤 성공이었다.
      final code = _script();
      expect(code, contains('if not cell.arm.server_is_ready():'));
      expect(code, contains('액션 서버가 안 보입니다'));
    });

    test('막히면 실패를 말한다. 조용히 두지 않는다', () {
      // 답을 안 하면 RMF 는 영원히 기다린다 — 오류도 안 난다.
      final code = _script();
      expect(code, contains('ARM_RESULT_TIMEOUT'));
      expect(code, contains('DispenserResult.FAILED'));
      expect(code, contains('cancel_goal_async()'));
    });

    test('관절이 멎었는지 한 번 더 본다', () {
      final code = _script();
      expect(code, contains("f'/{namespace}/joint_states'"));
      expect(code, contains('ARM_STILL_VELOCITY'));
    });

    test('관절 속도 확인에는 거부권이 없다', () {
      // 이 팔은 **멈춰 있어도** 속도가 안 떨어진다. 실측(2026-08-17, OMX in
      // Gazebo, 표본 148) — 최소 0.113 · 중앙 1.291 · 최대 1.443 rad/s,
      // 0.02 아래인 비율 0%. 그래서 픽업이 매번 실패했다.
      //
      //   [omx_01.arm_controller] Goal reached, success!
      //   [omx_01] 픽업3: 팔이 5초가 지나도 안 멎었습니다   ← 여기서 막힘
      final code = _script();
      final body = code.substring(
        code.indexOf('def watch_settle(self, cell, job):'),
        code.indexOf('def succeed(self, cell, job):'),
      );
      // 정착 단계는 실패를 낼 수 없다.
      expect(body, isNot(contains('self.fail(')));
      expect(body, contains('self.succeed(cell, job)'));
      expect(code, contains('액션 결과만 믿고'));
    });

    test('여유는 판정이 아니라 여유라고 밝힌다', () {
      final code = _script();
      expect(code, contains('ARM_SETTLE_SECONDS'));
      expect(code, contains('**판정이 아니라 여유다.**'));
    });

    test('실측을 남겨 문턱을 되올리지 못하게 한다', () {
      final code = _script();
      expect(code, contains('중앙 1.291'));
      expect(code, contains('문턱을 실측에 맞춰 올리지 마라'));
    });

    test('느린 시뮬에서 멀쩡한 궤적을 끊지 않는다', () {
      // 실측 RTF 0.101 — 시뮬 4초 궤적이 벽시계 55.5초였다. 샌드위치 재생은
      // 시뮬 35초라 같은 배율이면 350초가 넘는다.
      final code = _script();
      final match = RegExp(r'ARM_RESULT_TIMEOUT = ([0-9.]+)').firstMatch(code);
      expect(match, isNotNull);
      expect(double.parse(match!.group(1)!), greaterThanOrEqualTo(350));
      expect(code, contains('성능 예산이 아니라 멈춤 감지다'));
    });
  });

  group('로봇이 제자리에 제 자세로 섰나', () {
    test('/fleet_states 를 직접 듣는다', () {
      final code = _script();
      expect(code, contains('from rmf_fleet_msgs.msg import FleetState'));
      expect(
        code,
        contains(
          "self.create_subscription(\n            FleetState, '/fleet_states'",
        ),
      );
    });

    test('자리마다의 각도를 노드에 박아 넣는다', () {
      // 워크셀은 nav graph 를 안 읽는다. 배포할 때 적어 주지 않으면 어느 자리가
      // 어느 각도를 요구하는지 알 방법이 없다.
      final code = _script(dockHeadings: const {'픽업3': 180});
      expect(code, contains('DOCK_HEADINGS = {'));
      expect(code, contains("'픽업3': 3.141593,"));
      // 사람이 읽을 수 있게 도(度)도 남긴다.
      expect(code, contains('180.000도'));
    });

    test('각도를 안 정했으면 자세를 안 따진다', () {
      final code = _script();
      expect(code, contains('DOCK_HEADINGS = {\n\n}'));
      expect(code, contains('if job.required_yaw is None:'));
    });

    test('관문은 Nav2 요구보다 일부러 헐겁다', () {
      // 둘은 하는 일이 다르다. Nav2 쪽은 **요구**(그 각도까지 돌아라)이고,
      // 워크셀 쪽은 **관문**(잘못 선 로봇에 팔을 내보내지 마라)이다.
      //
      // 같은 값으로 묶으면 안 된다. 제자리 회전은 판정이 나는 순간 멈추므로
      // 실제로 멎는 자세는 문턱보다 조금 더 가는데, 얼마나 더 가는지는 아직
      // 안 쟀다. 묶어 두면 Nav2 가 놓아준 로봇을 워크셀이 매번 거절해 멀쩡한
      // 작업이 전부 실패한다.
      final code = _script();
      final match = RegExp(r'DOCK_YAW_TOLERANCE = ([0-9.]+)').firstMatch(code);
      expect(match, isNotNull);
      final gate = double.parse(match!.group(1)!);
      expect(gate, greaterThan(dockYawTolerance));
      // 잡으려는 것은 몇 도의 오차가 아니라 **안 돈 로봇**이다. 들어온 그대로
      // 선 로봇은 180도가 어긋난다.
      expect(gate, lessThan(math.pi / 4));
    });

    test('179도와 -179도를 358도 차이로 보지 않는다', () {
      final code = _script();
      expect(code, contains('def wrap_angle(radians):'));
      expect(code, contains('wrap_angle(pose[\'yaw\'] - job.required_yaw)'));
    });

    test('첫 소식 한 건으로 섰다고 하지 않는다', () {
      // 움직임은 두 소식 사이의 차이다. 0 으로 채우면 방금 처음 본 로봇이
      // 멈춰 있는 것으로 보여, 달려오는 중에 팔이 움직인다.
      final code = _script();
      expect(code, contains('speed = None'));
      expect(code, contains("if pose['speed'] is None:"));
      expect(code, contains('소식이 아직 한 건뿐입니다'));
    });

    test('마지막 몇 도를 도는 로봇을 바로 거절하지 않는다', () {
      // RMF 는 도착했다고 보고 우리를 부르는데, 그 순간 로봇이 아직 돌고 있을
      // 수 있다. 여기서 바로 거절하면 멀쩡한 작업이 실패한다.
      final code = _script();
      expect(code, contains('ROBOT_SETTLE_TIMEOUT'));
      expect(code, contains("job.stage == 'waiting_robot'"));
    });

    test('적재 중에 로봇이 자리를 뜨면 궤적을 취소한다', () {
      final code = _script();
      final watch = code.indexOf('def watch_arm(self, cell, job)');
      expect(watch, greaterThanOrEqualTo(0));
      final body = code.substring(watch, code.indexOf('\n    def ', watch));
      expect(body, contains('self.robot_left(job)'));
      expect(body, contains('cancel_goal_async()'));
      expect(body, contains('자리를 떴습니다'));
    });

    test('떨림으로 끊지 않는다 — 시작한 자리와 견준다', () {
      // 눈금 사이의 차이로 재면 도착 직후의 떨림이 그대로 중단 사유가 된다.
      // 실제로 그래서 멀쩡한 적재가 1초 만에 끊겼다 —
      //   [omx_01] 픽업3: 로봇이 제자리에 섰습니다. 팔을 움직입니다.
      //   1.0초 뒤
      //   [omx_01] 픽업3: 적재 중에 로봇이 흔들렸습니다 (0.6cm · 3.4도)
      final code = _script();
      expect(code, contains('self.anchor'));
      expect(
        code,
        contains('job.anchor = None if pose is None else dict(pose)'),
      );
      final left = code.indexOf('def robot_left(self, job)');
      expect(left, greaterThanOrEqualTo(0));
      final body = code.substring(left, code.indexOf('\n    def ', left));
      expect(body, contains("job.anchor['x']"));
      expect(body, contains('ARM_ABORT_METERS'));
      expect(body, contains('ARM_ABORT_RADIANS'));
      // 눈금 사이의 차이(`moved`/`turned`)는 여기서 쓰지 않는다.
      expect(body, isNot(contains("pose['moved']")));
    });

    test('움직임을 거리가 아니라 속도로 잰다', () {
      // `/fleet_states` 는 벽시계 10Hz 인데 로봇은 시뮬 시계로 움직인다.
      // 실측(2026-08-17) RTF 0.101 — 0.2m/s 로 달리는 로봇이 눈금당 0.002m
      // 밖에 안 움직인다. 거리로 재면 **달리는 로봇이 섰다고 나온다.**
      final code = _script();
      expect(code, contains('ROBOT_STILL_SPEED'));
      expect(code, contains('ROBOT_STILL_TURN_RATE'));
      expect(code, isNot(contains('ROBOT_STILL_METERS')));
      expect(code, isNot(contains('ROBOT_STILL_RADIANS')));
      // 시뮬 시계 시각으로 나눈다. 벽시계로 나누면 같은 함정에 다시 빠진다.
      expect(code, contains('location.t.sec'));
      expect(code, contains("span = stamp - previous['stamp']"));
    });

    test('문턱이 핑키 순항 속도보다 한참 아래다', () {
      final code = _script();
      final speed = RegExp(r'ROBOT_STILL_SPEED = ([0-9.]+)').firstMatch(code);
      expect(speed, isNotNull);
      expect(double.parse(speed!.group(1)!), lessThan(0.2));
    });

    test('같은 시뮬 시각이 겹쳐도 판단을 잃지 않는다', () {
      // 모른다고 하면 그때마다 처음부터 다시 기다리게 된다.
      final code = _script();
      expect(code, contains("speed = previous['speed']"));
    });

    test('로봇을 기다리는 시간이 느린 시뮬을 견딘다', () {
      final code = _script();
      final match = RegExp(
        r'ROBOT_SETTLE_TIMEOUT = ([0-9.]+)',
      ).firstMatch(code);
      expect(double.parse(match!.group(1)!), greaterThanOrEqualTo(60));
    });

    test('오래된 소식을 믿지 않는다', () {
      final code = _script();
      expect(code, contains('FLEET_STATE_MAX_AGE'));
    });
  });

  group('노드가 실제로 돌 수 있는 모양인가', () {
    test('쓰는 이름을 모두 들여온다', () {
      final code = _script();
      // `math.radians` 를 쓰면서 `import math` 가 없어 샌드위치 재생이
      // NameError 로 죽던 자리가 있었다.
      for (final name in const [
        'import math',
        'import time',
        'from sensor_msgs.msg import JointState',
        'from rmf_fleet_msgs.msg import FleetState',
      ]) {
        expect(code, contains(name), reason: '$name 이 없습니다');
      }
      expect(code, contains('math.radians('));
      expect(code, contains('time.monotonic()'));
    });

    test('시계는 시스템 시계다. 시뮬 시계에 매이지 않는다', () {
      // 기다린 시간을 노드 시계로 재면 `/clock` 이 어긋날 때 4초가 4초가
      // 아니게 된다. 걸린 시간은 전부 `time.monotonic()` 으로 잰다.
      final code = _script();
      final deadlines = RegExp(r'\.deadline = [^\n]*').allMatches(code);
      expect(deadlines, isNotEmpty);
      for (final match in deadlines) {
        expect(match.group(0), contains('time.monotonic()'));
      }
    });

    test('실패는 답할 요청을 인자로 받는다', () {
      // `cell.job` 에서 꺼내면, 아직 job 을 만들기 전에 걸린 실패(모르는
      // policy · 팔 없음)에서 답할 곳을 잃는다.
      final code = _script();
      expect(code, contains('def fail(self, cell, msg, dispenser, reason):'));
      expect(code, isNot(contains('self.fail(cell, dispenser,')));
    });
  });

  group('만들어진 파일을 파이썬이 읽을 수 있는가', () {
    test('py_compile 이 통과한다', () {
      final python = Process.runSync('which', ['python3']);
      if (python.exitCode != 0) {
        markTestSkipped('python3 가 없습니다');
        return;
      }
      final file = File(
        '${Directory.systemTemp.path}/robosapiens_workcell_check.py',
      )..writeAsStringSync(_script(dockHeadings: const {'픽업3': 180}));
      final result = Process.runSync('python3', [
        '-m',
        'py_compile',
        file.path,
      ]);
      addTearDown(() {
        if (file.existsSync()) file.deleteSync();
      });
      expect(result.exitCode, 0, reason: '${result.stderr}');
    });
  });
}
