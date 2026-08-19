/// 미세조종 목표를 Nav2 에 실제로 보낸다. 규칙은 `robot_nudge.dart` 에 있다.
library;

import 'dart:io';

import 'robot_nudge.dart';
import 'workspace_paths_io.dart';

/// ROS 환경을 읽어 들인 뒤 [command] 를 실행하는 셸 한 줄.
String _withRosEnvironment(String command, int rosDomainId) {
  final rosSetup =
      Platform.environment['ROS_SETUP'] ?? '/opt/ros/jazzy/setup.bash';
  final workspace = bundledRmfWorkspace();
  return 'set +u; '
      '[ -f "$rosSetup" ] && . "$rosSetup"; '
      '[ -f "$workspace/install/setup.bash" ] && . "$workspace/install/setup.bash"; '
      'export ROS_DOMAIN_ID=$rosDomainId; '
      '$command';
}

bool get _inTest => Platform.environment.containsKey('FLUTTER_TEST');

/// 로봇을 조금 움직인다.
///
/// `--feedback` 없이 결과만 기다린다. `send_goal` 은 목표가 끝날 때까지 붙어
/// 있으므로, 시간 제한은 action 의 `time_allowance` 보다 넉넉해야 한다 — 앱이
/// 먼저 포기하면 로봇은 계속 가는데 화면은 실패라고 말한다.
Future<({bool ok, String output})> nudgeRobot({
  required String namespace,
  required NudgeKind kind,
  required double meters,
  required double degrees,
  required int rosDomainId,
}) async {
  if (_inTest) return (ok: true, output: '');
  final action = nudgeActionName(namespace, kind);
  final type = nudgeActionType(kind);
  final goal = nudgeGoalYaml(kind: kind, meters: meters, degrees: degrees);
  try {
    final result = await Process.run('bash', [
      '-lc',
      _withRosEnvironment(
        // 목표는 작은따옴표로 감싼다. 중괄호와 공백이 셸을 빠져나가면 안 된다.
        "ros2 action send_goal '$action' '$type' '$goal'",
        rosDomainId,
      ),
    ]).timeout(const Duration(seconds: 90));
    final text = '${result.stdout}${result.stderr}'.trim();
    // `send_goal` 은 거절당해도 0 으로 끝나는 일이 있다. 결과 문자열까지 본다.
    final accepted =
        result.exitCode == 0 &&
        text.contains('Goal finished with status: SUCCEEDED');
    return (ok: accepted, output: text);
  } catch (error) {
    return (ok: false, output: '$error');
  }
}
