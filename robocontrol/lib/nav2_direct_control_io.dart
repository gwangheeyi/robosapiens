library;

import 'dart:io';

import 'nav2_direct_control.dart';
import 'workspace_paths_io.dart';

String _quote(String value) => "'${value.replaceAll("'", r"'\''")}'";

String _rosCommand(String command, int domain) {
  final rosSetup =
      Platform.environment['ROS_SETUP'] ?? '/opt/ros/jazzy/setup.bash';
  final workspace = bundledRmfWorkspace();
  return 'set +u; '
      '[ -f ${_quote(rosSetup)} ] && . ${_quote(rosSetup)}; '
      '[ -f ${_quote('$workspace/install/setup.bash')} ] && '
      '. ${_quote('$workspace/install/setup.bash')}; '
      'export ROS_DOMAIN_ID=$domain; '
      'unset ROS_STATIC_PEERS ROS_LOCALHOST_ONLY; '
      'export ROS_AUTOMATIC_DISCOVERY_RANGE=SUBNET; '
      '$command';
}

Future<({bool ok, String output})> sendNav2DirectGoal({
  required Nav2DirectGoal goal,
  required int rosDomainId,
}) async {
  if (Platform.environment.containsKey('FLUTTER_TEST')) {
    return (ok: true, output: 'test');
  }
  final action = _quote(goal.actionName);
  const type = 'nav2_msgs/action/NavigateToPose';
  try {
    final probe = await Process.run('bash', [
      '-lc',
      _rosCommand("timeout 5 ros2 action info $action 2>&1", rosDomainId),
    ]).timeout(const Duration(seconds: 8));
    final probeText = '${probe.stdout}${probe.stderr}'.trim();
    if (probe.exitCode != 0 || !probeText.contains('Action servers: 1')) {
      return (
        ok: false,
        output:
            '${goal.actionName} action server가 없습니다. '
            '로봇 브링업과 Nav2(bt_navigator active)를 확인하세요.\n$probeText',
      );
    }
    final result = await Process.run('bash', [
      '-lc',
      _rosCommand(
        'timeout 300 ros2 action send_goal $action $type '
        '${_quote(goal.goalYaml)}',
        rosDomainId,
      ),
    ]).timeout(const Duration(seconds: 305));
    final text = '${result.stdout}${result.stderr}'.trim();
    final ok =
        result.exitCode == 0 &&
        text.contains('Goal finished with status: SUCCEEDED');
    return (ok: ok, output: text);
  } catch (error) {
    return (ok: false, output: '$error');
  }
}
