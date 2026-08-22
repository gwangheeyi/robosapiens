/// 로봇에 SSH 로 들어가 브링업을 띄운다.
///
/// 실물 로봇은 앱이 도는 PC 가 아니라 제 안에서 하드웨어를 연다 — 라이다는
/// `/dev/ttyAMA0`, 모터는 `/dev/ttyAMA4` 다. 그래서 지금까지는 사람이 로봇에
/// 들어가 손으로 launch 를 쳤고, 그 자리에서 자주 어긋났다.
///
/// **어긋나면 오류가 안 난다.** 네임스페이스를 빠뜨리면 토픽이 루트로 나가고,
/// 도메인이 다르면 아무것도 안 보인다. 둘 다 조용해서, 라이다나 AMCL 을
/// 의심하며 한참을 헤매게 된다. 실제로 로봇이 `/scan` 으로 발행하는데 Nav2 는
/// `/pinky_03/scan` 을 구독해서, 라이다가 10Hz 로 멀쩡히 도는데도 지도에
/// 아무것도 안 그려진 일이 있었다.
///
/// 그 명령은 로봇 등록에 있는 값으로 **전부 만들어낼 수 있다.** 사람이 칠 이유가
/// 없다.
///
/// 판정을 화면에서 떼어 둔 것은 [RobotLink] 와 같은 이유다 — 규칙은 눌러 보지
/// 않고도 확인할 수 있어야 한다.
library;

import 'rmf_project_config.dart';

/// 로봇에 들어가는 길. 등록에 함께 저장한다.
class RobotSshTarget {
  const RobotSshTarget({
    required this.host,
    this.user = '',
    this.port = 22,
    this.workspace = '~/pinky_pro',
  });

  /// 로봇의 주소. IP 나 호스트 이름.
  final String host;

  /// 로그인 계정. 비우면 지금 PC 의 계정으로 붙는다.
  final String user;

  final int port;

  /// 로봇 안의 ROS 워크스페이스. `install/setup.bash` 가 그 아래 있어야 한다.
  final String workspace;

  bool get isConfigured => host.trim().isNotEmpty;

  /// `user@host` 또는 `host`.
  String get authority {
    final trimmedHost = host.trim();
    final trimmedUser = user.trim();
    return trimmedUser.isEmpty
        ? trimmedHost
        : '$trimmedUser@$trimmedHost';
  }

  Map<String, dynamic> toJson() => {
    'host': host,
    'user': user,
    'port': port,
    'workspace': workspace,
  };

  static RobotSshTarget? fromJson(Map<String, dynamic>? data) {
    if (data == null) return null;
    final host = (data['host'] as String? ?? '').trim();
    if (host.isEmpty) return null;
    return RobotSshTarget(
      host: host,
      user: data['user'] as String? ?? '',
      port: (data['port'] as num?)?.toInt() ?? 22,
      workspace: data['workspace'] as String? ?? '~/pinky_pro',
    );
  }
}

/// SSH 로 브링업을 띄울 수 있는가. 못 하면 왜 못 하는가.
enum RobotSshReadiness {
  ready,

  /// Mock 로봇이다. 앱 안에만 있어서 들어갈 곳이 없다.
  mockRobot,

  /// Gazebo 로 도는 로봇이다. 시뮬레이터가 이미 올린다.
  simulated,

  /// 설치 로봇(팔)이다. 이 브링업은 이동 로봇의 것이다.
  notMobile,

  /// 로봇 주소를 안 적었다.
  noHost,
}

/// SSH 로 띄울 수 있는지 본다.
RobotSshReadiness checkRobotSshReadiness({
  required RmfProjectRobot robot,
  required RobotSshTarget? target,
}) {
  if (!robot.dataSource.usesTopics) return RobotSshReadiness.mockRobot;
  if (robot.runsInGazebo) return RobotSshReadiness.simulated;
  if (!robot.isMobile) return RobotSshReadiness.notMobile;
  if (target == null || !target.isConfigured) return RobotSshReadiness.noHost;
  return RobotSshReadiness.ready;
}

bool canBringUpOverSsh(RobotSshReadiness readiness) =>
    readiness == RobotSshReadiness.ready;

/// 못 하는 까닭. 할 수 있으면 null.
String? robotSshBlockedReason(RobotSshReadiness readiness) =>
    switch (readiness) {
      RobotSshReadiness.ready => null,
      RobotSshReadiness.mockRobot =>
        'Mock 로봇은 앱 안에서만 움직입니다. 들어갈 로봇이 없습니다.',
      RobotSshReadiness.simulated =>
        'Gazebo 로 도는 로봇입니다. 시뮬레이터가 이미 올립니다.',
      RobotSshReadiness.notMobile =>
        '설치 로봇은 이 브링업을 쓰지 않습니다.',
      RobotSshReadiness.noHost =>
        '로봇 주소를 안 적었습니다. 로봇 등록에서 SSH 주소를 넣어 주세요.',
    };

/// 로봇 안에서 돌릴 브링업 명령.
///
/// 네임스페이스와 도메인을 **등록에서 그대로 가져온다.** 사람이 칠 일이 없으니
/// 오타로 어긋날 일도 없다.
///
/// `setsid` 로 띄우고 로그를 파일로 돌린다. SSH 연결이 끊겨도 브링업은 계속
/// 돌아야 한다 — 앱을 닫았다고 로봇이 멈추면 안 된다.
String buildRobotBringupCommand({
  required RmfProjectRobot robot,
  required RobotSshTarget target,
  required int projectDomainId,
}) {
  final domain = robot.rosDomainId ?? projectDomainId;
  final namespace = robot.gzName;
  final workspace = target.workspace.trim().isEmpty
      ? '~/pinky_pro'
      : target.workspace.trim();
  final log = '/tmp/${robot.gzName}_bringup.log';
  // `&` 뒤에는 `;` 를 붙이지 않는다. `&` 자체가 명령을 끝내는 구분자라
  // `... & ; echo` 는 bash 문법 오류다:
  //
  //     bash: -c: line 1: syntax error near unexpected token `;'
  //
  // 그래서 앞부분만 `;` 로 잇고, 띄우는 줄과 그 뒤는 손으로 붙인다.
  final prepare = [
    'export ROS_DOMAIN_ID=$domain',
    'source /opt/ros/jazzy/setup.bash',
    '[ -f $workspace/install/setup.bash ] && source $workspace/install/setup.bash',
    // 이미 떠 있으면 두 벌이 뜬다. 같은 시리얼 포트를 두 프로세스가 잡을 수
    // 없어서, 나중 것이 조용히 실패하고 토픽만 남는다.
    _killBringup(robot),
    'sleep 2',
  ].join('; ');
  return '$prepare; '
      'setsid nohup ros2 launch pinky_bringup '
      'bringup_robot_namespaced.launch.xml '
      'namespace:=$namespace > $log 2>&1 & '
      'echo STARTED';
}

/// 이 로봇의 브링업만 골라 죽이는 명령.
///
/// **자기 자신을 죽이지 않아야 한다.** `ssh` 가 실행하는 셸의 명령줄에는 이
/// 패턴 문자열이 그대로 들어 있어서, `pkill -f '...pinky_02'` 를 그대로 쓰면
/// 그 셸도 함께 걸린다. 그러면 뒤의 `echo STARTED` 에 닿기도 전에 죽고 ssh 가
/// 255 로 끝난다 — 브링업은 멀쩡히 떠 있는데 앱은 "접속하지 못했습니다" 라고
/// 말한다. 실제로 그 일이 있었다.
///
/// 두 가지로 막는다.
///
/// **① `pgrep` 으로 먼저 고르고 제 PID 는 뺀다.** `$$` 는 지금 셸이고
/// `$PPID` 는 그 부모다. 둘 다 빼야 ssh 가 띄운 셸 사슬이 안 걸린다.
///
/// **② 패턴을 쪼개 쓴다.** `[b]ringup` 은 정규식으로는 `bringup` 과 같지만
/// 명령줄 문자열로는 다르다 — 제 명령줄을 제가 못 찾게 된다. 예전부터 쓰던
/// 방법이고, ① 만으로 놓치는 자식 셸까지 함께 막는다.
/// 먼저 TERM 으로 곱게 내리고, 2초 뒤에도 남아 있으면 KILL 한다.
///
/// `joint_state_publisher` 는 TERM 을 안 받고 버틴다(실측 — 9개 중 이것만 둘이
/// 살아남았다). 남으면 시리얼과 토픽을 계속 잡고 있어서, 다시 띄울 때 새
/// 브링업이 조용히 실패한다.
String _killBringup(RmfProjectRobot robot) {
  final pids = _bringupPids(robot);
  String loop(String signal) =>
      'for pid in $pids; do '
      '[ "\$pid" = "\$\$" ] || [ "\$pid" = "\$PPID" ] || '
      'kill $signal "\$pid" 2>/dev/null; '
      'done';
  return '${loop('-TERM')}; sleep 2; ${loop('-KILL')}; true';
}

/// 이 로봇의 브링업에 딸린 PID 를 모으는 조각.
///
/// `ros2 run` 중인 짧은 구간과 실행 파일로 교체된 뒤를 모두 찾는다. 한 SSH
/// 대상은 한 로봇이므로 네임스페이스로 구분하지 않는다. 패턴을 쪼개 쓰는
/// 까닭은 [_killBringup] 에 적었다.
String _bringupPids(RmfProjectRobot robot) =>
    "\$(pgrep -f '[b]ringup_robot_namespaced.*${robot.gzName}'; "
    "pgrep -f '[_]_ns:=/${robot.gzName}([^A-Za-z0-9_]|\$)')";

/// 로봇 안에서 이 로봇의 자동 실행을 맡을 systemd 서비스 이름.
String robotBringupServiceName(RmfProjectRobot robot) =>
    'robosapiens-bringup-${robot.gzName}';

/// 로봇을 켜자마자 브링업이 뜨게 하는 systemd 유닛.
///
/// **앱이 만든다.** 사람이 로봇 안에서 손으로 쓰면 `namespace` 와
/// `ROS_DOMAIN_ID` 를 거기에 또 적게 되고, 앱에서 도메인을 바꿔도 그 파일은
/// 그대로 남아 조용히 어긋난다 — 어긋나도 오류가 안 나는 것이 이 두 값의
/// 성질이다. 등록값으로 만들어 두면 배포할 때마다 같이 따라온다.
///
/// `Restart=on-failure` 를 둔다. 부팅 직후에는 시리얼 장치가 아직 안 올라와
/// 브링업이 실패할 수 있는데, 그때 한 번 죽고 끝나면 로봇은 켜졌는데 토픽은
/// 안 오는 상태로 남는다.
///
/// `After=network-online.target` 은 DDS 가 망을 찾기 전에 뜨는 것을 막는다.
/// 망 없이 뜨면 같은 도메인의 다른 노드를 못 보고, 나중에 망이 붙어도 그
/// 상태가 그대로 간다.
String buildRobotBringupService({
  required RmfProjectRobot robot,
  required RobotSshTarget target,
  required int projectDomainId,
}) {
  final domain = robot.rosDomainId ?? projectDomainId;
  final namespace = robot.gzName;
  final workspace = target.workspace.trim().isEmpty
      ? '~/pinky_pro'
      : target.workspace.trim();
  final user = target.user.trim();
  return '''
[Unit]
# ${robot.robotId} · ${robot.displayName} 브링업.
# rmf_control_ui 가 로봇 등록에서 만들었다. 손으로 고치면 다음 설치 때
# 덮어써진다 — 고치려면 앱의 로봇 등록에서 고친다.
Description=Robosapiens bringup for ${robot.gzName}
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
${user.isEmpty ? '' : 'User=$user\n'}Environment=ROS_DOMAIN_ID=$domain
Environment=FASTDDS_BUILTIN_TRANSPORTS=UDPv4
Environment=ROS_AUTOMATIC_DISCOVERY_RANGE=SUBNET
ExecStart=/bin/bash -lc 'source /opt/ros/jazzy/setup.bash; [ -f $workspace/install/setup.bash ] && source $workspace/install/setup.bash; exec ros2 launch pinky_bringup bringup_robot_namespaced.launch.xml namespace:=$namespace'
# 부팅 직후에는 시리얼 장치가 아직 안 올라와 있을 수 있다. 한 번 죽고 끝나면
# 로봇은 켜졌는데 토픽은 안 오는 상태로 남는다.
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
''';
}

/// 유닛을 로봇에 올리고 부팅 때 뜨게 한다.
///
/// 파일은 표준 입력으로 넘긴다. 명령줄에 넣으면 줄바꿈과 따옴표가 셸을
/// 빠져나간다.
String buildRobotServiceInstallCommand(RmfProjectRobot robot) {
  final name = robotBringupServiceName(robot);
  return 'cat > /tmp/$name.service && '
      'sudo install -m 644 /tmp/$name.service /etc/systemd/system/$name.service && '
      'sudo systemctl daemon-reload && '
      'sudo systemctl enable $name && '
      'sudo systemctl restart $name && '
      'echo INSTALLED';
}

/// 자동 실행을 끈다. 지금 떠 있는 것도 내린다.
String buildRobotServiceRemoveCommand(RmfProjectRobot robot) {
  final name = robotBringupServiceName(robot);
  return 'sudo systemctl disable --now $name; '
      'sudo rm -f /etc/systemd/system/$name.service; '
      'sudo systemctl daemon-reload; '
      'echo REMOVED';
}

/// 자동 실행이 걸려 있는지, 지금 도는지 본다.
String buildRobotServiceStatusCommand(RmfProjectRobot robot) {
  final name = robotBringupServiceName(robot);
  return 'systemctl is-enabled $name 2>/dev/null || echo disabled; '
      'systemctl is-active $name 2>/dev/null || echo inactive';
}

/// 자동 실행 상태.
class RobotServiceStatus {
  const RobotServiceStatus({required this.enabled, required this.active});

  /// 부팅 때 뜨게 되어 있는가.
  final bool enabled;

  /// 지금 도는가.
  final bool active;

  bool get installed => enabled || active;
}

/// [buildRobotServiceStatusCommand] 의 출력을 읽는다.
///
/// 두 줄이 온다 — `enabled`/`disabled` 와 `active`/`inactive`. `inactive` 안에
/// `active` 가 들어 있으므로 낱말 경계로 가른다. 안 그러면 안 도는 서비스를
/// 돈다고 읽는다.
RobotServiceStatus parseRobotServiceStatus(String output) {
  final lines = output
      .split('\n')
      .map((line) => line.trim().toLowerCase())
      .where((line) => line.isNotEmpty)
      .toList();
  bool has(String word) => lines.any(
    (line) => RegExp('(^|[^a-z])$word([^a-z]|\$)').hasMatch(line),
  );
  return RobotServiceStatus(
    enabled: has('enabled') && !has('disabled'),
    active: has('active') && !has('inactive'),
  );
}

/// 자동 실행 상태를 사람이 읽을 한 줄로.
String robotServiceStatusLabel(RobotServiceStatus status) {
  if (status.enabled && status.active) return '켤 때 자동 실행 · 지금 도는 중';
  if (status.enabled) return '켤 때 자동 실행 · 지금은 멈춤';
  if (status.active) return '지금 도는 중 · 켤 때는 안 뜸';
  return '자동 실행 안 함';
}

/// 로봇의 브링업을 내리는 명령.
String buildRobotBringupStopCommand(RmfProjectRobot robot) =>
    '${_killBringup(robot)}; echo STOPPED';

/// 브링업이 떠 있는지 보는 명령. 떠 있으면 `RUNNING` 을 찍는다.
///
/// 여기서도 제 명령줄이 걸리면 **언제나** `RUNNING` 이 나온다 — 브링업이
/// 없는데도 있다고 답하는 것이라, 확인이 있으나 마나 해진다. 죽일 때와 같은
/// 방법으로 제 것을 뺀다.
/// 부모 `ros2 launch` 가 죽고 자식 노드만 고아로 남는 일이 있다. 그때도
/// 시리얼 포트는 잡혀 있으므로 **떠 있는 것으로 봐야 한다** — 안 그러면
/// "안 떠 있다" 고 답한 뒤 다시 띄우려다 포트를 못 열어 조용히 실패한다.
String buildRobotBringupProbeCommand(RmfProjectRobot robot) =>
    '[ -n "${_bringupPids(robot)}" ] && echo RUNNING || echo STOPPED';

/// 브링업 로그의 마지막 부분을 읽는 명령.
///
/// 시리얼을 못 잡으면 여기에 그대로 찍힌다 — `Failed to open serial port`.
String buildRobotBringupLogCommand(RmfProjectRobot robot, {int lines = 40}) =>
    'tail -n $lines /tmp/${robot.gzName}_bringup.log 2>/dev/null '
    "|| echo '로그가 아직 없습니다.'";

/// SSH 를 돌린 결과.
enum RobotSshOutcome {
  /// 됐다.
  ok,

  /// 로봇에 못 붙었다. 주소·계정·키를 봐야 한다.
  unreachable,

  /// 붙었는데 명령이 실패했다.
  commandFailed,
}

/// 결과에 붙일 말.
///
/// SSH 는 실패하는 길이 여럿이라, 무엇을 봐야 하는지 갈라 주지 않으면 사람이
/// 어디부터 볼지 모른다.
String robotSshOutcomeMessage({
  required RobotSshOutcome outcome,
  required String robotLabel,
  required String authority,
  required String detail,
}) => switch (outcome) {
  RobotSshOutcome.ok =>
    '$robotLabel 의 브링업을 띄웠습니다 ($authority).\n\n'
        '라이다와 모터가 값을 내기까지 몇 초 걸립니다. '
        '`로봇 상태 확인` 으로 토픽이 오는지 보세요.',
  RobotSshOutcome.unreachable =>
    '$robotLabel 에 접속하지 못했습니다 ($authority).\n\n'
        '$detail\n\n'
        '· 로봇이 켜져 있고 같은 망에 있는지\n'
        '· 주소와 계정이 맞는지\n'
        '· SSH 키가 등록됐는지 — 비밀번호를 묻는 상태면 앱이 붙을 수 없습니다.\n'
        '  `ssh-copy-id $authority` 를 한 번 해 두세요.',
  RobotSshOutcome.commandFailed =>
    '$robotLabel 에 붙었지만 브링업을 못 띄웠습니다 ($authority).\n\n'
        '$detail\n\n'
        '워크스페이스 경로가 맞는지, `pinky_bringup` 이 빌드돼 있는지 '
        '확인해 주세요.',
};
