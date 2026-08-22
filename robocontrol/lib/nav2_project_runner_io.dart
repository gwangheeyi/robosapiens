library;

import 'dart:io';

class Nav2ProjectRunResult {
  const Nav2ProjectRunResult({required this.success, required this.message});
  final bool success;
  final String message;
}

String _quote(String value) => "'${value.replaceAll("'", r"'\''")}'";

Future<Nav2ProjectRunResult> startNav2Project({
  required String mapName,
  required String mapDirectory,
  required int rosDomainId,
}) async {
  final launch = File('$mapDirectory/${mapName}_nav2.launch.xml');
  if (!launch.existsSync()) {
    return Nav2ProjectRunResult(
      success: false,
      message: '${launch.path}가 없습니다. 먼저 프로젝트를 저장·내보내세요.',
    );
  }
  final setup =
      Platform.environment['ROS_SETUP'] ?? '/opt/ros/jazzy/setup.bash';
  final log = '$mapDirectory/${mapName}_robocontrol.log';
  final lock = '$mapDirectory/.$mapName.nav2.lock';

  // 프로젝트 전체 실행, Nav2 단독 실행, 재시작이 모두 같은 잠금을 쓴다.
  // 화면의 연속 클릭만 막아서는 앱 재실행이나 다른 터미널과 경합할 수 있으므로
  // 실제 ros2 launch 프로세스가 살아 있는 동안 커널 잠금을 잡아 둔다.
  // 잠금 도입 전에 터미널에서 직접 띄운 기존 프로세스도 중복으로 세지 않는다.
  final processProbe = await Process.run('pgrep', [
    '-f',
    'ros2 launch ${launch.path}',
  ]);
  final lockProbe = await Process.run('flock', ['-n', lock, 'true']);
  if (processProbe.exitCode == 0 || lockProbe.exitCode != 0) {
    return Nav2ProjectRunResult(
      success: true,
      message: '$mapName Nav2가 이미 실행 중입니다. 새로 띄우지 않았습니다.\n로그: $log',
    );
  }
  final command =
      'set +u; . ${_quote(setup)}; '
      'export ROS_DOMAIN_ID=$rosDomainId; '
      'export FASTDDS_BUILTIN_TRANSPORTS=UDPv4; '
      'export ROS_AUTOMATIC_DISCOVERY_RANGE=SUBNET; '
      'unset ROS_STATIC_PEERS ROS_LOCALHOST_ONLY; '
      'exec 8>${_quote(lock)}; '
      'if ! flock -n 8; then '
      'echo "Nav2가 이미 실행 중이므로 중복 실행하지 않습니다."; exit 0; fi; '
      'exec ros2 launch ${_quote(launch.path)}';
  try {
    await Process.start('bash', [
      '-lc',
      'setsid bash -lc ${_quote(command)} >>${_quote(log)} 2>&1',
    ], mode: ProcessStartMode.detached);
    await Future<void>.delayed(const Duration(seconds: 2));
    return Nav2ProjectRunResult(
      success: true,
      message: '$mapName Nav2를 시작했습니다.\n로그: $log',
    );
  } catch (error) {
    return Nav2ProjectRunResult(success: false, message: '$error');
  }
}
