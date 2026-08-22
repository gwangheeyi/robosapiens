/// Nav2 목표를 취소하고 로봇에 0 속도를 실제로 보낸다.
library;

import 'dart:io';

import 'robot_stop.dart';
import 'workspace_paths_io.dart';

bool get _inTest => Platform.environment.containsKey('FLUTTER_TEST');

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

/// 모든 Nav2 동작을 취소하고 0 속도를 여러 번 보낸다.
///
/// action 취소만으로도 controller_server가 0을 발행하지만, action server가
/// 응답하지 않는 고장 상황에서도 모터에 정지 명령이 닿도록 `cmd_vel`을 직접
/// 덮는다. 한 번만 보내면 직전 속도 명령과 경합할 수 있어 10Hz로 1초간 보낸다.
Future<({bool ok, String output})> stopRobotMotion({
  required String namespace,
  required int rosDomainId,
}) async {
  if (_inTest) return (ok: true, output: '');
  final cancelCommands = <String>[
    for (final action in robotMotionActions)
      "timeout 2 ros2 service call '${robotTopic(namespace, '$action/_action/cancel_goal')}' "
          "action_msgs/srv/CancelGoal "
          "'{goal_info: {goal_id: {uuid: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]}, stamp: {sec: 0, nanosec: 0}}}' "
          '>/dev/null 2>&1',
  ];
  // 서비스가 없는 action도 있다. 하나씩 기다리면 5개의 timeout이 누적되어 정작
  // 중요한 0 속도를 보내기 전에 바깥 제한 시간이 끝난다. 모두 동시에 취소하고
  // 최장 2초만 기다린다.
  final cancelAll =
      '${cancelCommands.map((command) => '($command) &').join(' ')} '
      'wait || true';
  final zeroVelocity =
      // `--once`의 기본값은 구독자 1개를 찾을 때까지 기다리는 것이다. 무선 DDS
      // discovery가 늦으면 정지 값은 하나도 못 보내고 timeout 난다. 기다리지
      // 않고 3초 동안 계속 발행하면 discovery가 붙는 즉시 0 속도가 전달된다.
      "timeout 5 ros2 topic pub -r 10 --times 30 -w 0 "
      "'${robotTopic(namespace, 'cmd_vel')}' "
      "geometry_msgs/msg/Twist '{linear: {x: 0.0, y: 0.0, z: 0.0}, angular: {x: 0.0, y: 0.0, z: 0.0}}' "
      '>/dev/null 2>&1';
  try {
    final result = await Process.run('bash', [
      '-lc',
      _withRosEnvironment('$cancelAll; $zeroVelocity', rosDomainId),
    // ROS 환경 로딩과 DDS discovery 자체가 이 PC에서 4~5초 걸린다. 내부 명령은
    // 각각 짧게 제한하되, 바깥에서는 정지 발행이 끝날 시간을 충분히 준다.
    ]).timeout(const Duration(seconds: 20));
    final output = '${result.stdout}${result.stderr}'.trim();
    return (ok: result.exitCode == 0, output: output);
  } catch (error) {
    return (ok: false, output: '$error');
  }
}
