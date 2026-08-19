/// Nav2 lifecycle 상태를 실제로 물어보고, 안 켜졌으면 켠다.
///
/// 규칙은 `nav2_lifecycle.dart` 에 있다. 여기서는 `ros2` 를 부르는 일만 한다.
library;

import 'dart:io';

import 'nav2_lifecycle.dart';
import 'workspace_paths_io.dart';

/// ROS 환경을 읽어 들인 뒤 [command] 를 실행하는 셸 한 줄.
///
/// 앱은 보통 ROS 를 source 하지 않은 셸에서 뜬다(`ros2_inspect_io.dart` 와 같은
/// 방식이다).
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

/// 위젯 테스트에서는 프로세스를 띄우지 않는다.
bool get _inTest => Platform.environment.containsKey('FLUTTER_TEST');

Future<ProcessResult?> _run(
  String command,
  int rosDomainId, {
  Duration timeout = const Duration(seconds: 20),
}) async {
  if (_inTest) return null;
  try {
    return await Process.run('bash', [
      '-lc',
      _withRosEnvironment(command, rosDomainId),
    ]).timeout(timeout);
  } catch (_) {
    // 시간이 넘거나 셸이 없으면 "모른다" 로 다룬다. 여기서 예외를 올리면
    // 화면이 통째로 멈춘다.
    return null;
  }
}

/// 이 로봇의 Nav2 노드 상태를 전부 읽는다.
///
/// 노드마다 `ros2 lifecycle get` 을 한 번씩 부른다. 응답이 없으면
/// [Nav2NodeState.unreachable] 이다 — **모르는 것을 active 로 보면 안 된다.**
///
/// 조회 시간을 넉넉히 준다. 라즈베리파이가 바쁘면 응답이 늦는데, 그것을
/// "죽었다" 로 읽으면 멀쩡한 노드를 다시 켜려 든다.
Future<Nav2FleetStatus> readNav2Status({
  required String robotId,
  required String namespace,
  required int rosDomainId,
}) async {
  final nodes = <Nav2NodeStatus>[];
  for (final name in nav2ManagedNodes) {
    final result = await _run(
      'ros2 lifecycle get /$namespace/$name',
      rosDomainId,
    );
    nodes.add(
      Nav2NodeStatus(
        name: name,
        state: result == null || result.exitCode != 0
            ? Nav2NodeState.unreachable
            : parseNav2NodeState('${result.stdout}'),
      ),
    );
  }
  return Nav2FleetStatus(robotId: robotId, nodes: nodes);
}

/// 안 켜진 Nav2 노드를 켠다.
///
/// 먼저 `lifecycle_manager` 에게 맡긴다(STARTUP). 그것이 관리자가 제 순서를
/// 지키며 켜는 길이라 가장 안전하다. 그런데 관리자는 **이미 포기한 상태**일 수
/// 있고, 그때는 STARTUP 이 `amcl` 에서 막힌다 — 이미 active 인 노드에는
/// configure 전이가 없기 때문이다:
///
///     [amcl]: No transition matching 1 found for current state active
///     [lifecycle_manager]: Failed to change state for node: amcl
///
/// 그래서 그 뒤에 노드를 하나씩 직접 켠다. 이미 active 인 것은 그냥 실패하고
/// 넘어가므로 해가 없다.
///
/// 켜는 차례는 [nav2ManagedNodes] 를 따른다. costmap 을 쓰는 것보다 그것을
/// 만드는 쪽이 먼저 서야 한다.
Future<void> activateNav2Nodes({
  required String namespace,
  required int rosDomainId,
}) async {
  // ① 한 번 내렸다가(RESET) 올린다(STARTUP).
  //
  // **STARTUP 만 부르면 실패한다.** 이미 active 인 노드에 configure 를 걸어서
  // 첫 노드부터 걸리고, 나머지는 시도조차 안 한다:
  //
  //     Configuring amcl
  //     Failed to change state for node: amcl   ← 이미 active 라 전이가 없다
  //     Failed to bring up all requested nodes. Aborting bringup.
  //
  // amcl 만 active 로 남는 것이 바로 우리가 고치려는 상태라, RESET 없이는
  // 그 상태에서 영영 못 벗어난다.
  //
  // command 는 `0=STARTUP · 1=RESET · 2=PAUSE · 3=RESUME` 이다.
  await _run(
    'ros2 service call /$namespace/lifecycle_manager_navigation/manage_nodes '
    'nav2_msgs/srv/ManageLifecycleNodes "{command: 1}"',
    rosDomainId,
    timeout: const Duration(seconds: 60),
  );
  await _run(
    'ros2 service call /$namespace/lifecycle_manager_navigation/manage_nodes '
    'nav2_msgs/srv/ManageLifecycleNodes "{command: 0}"',
    rosDomainId,
    timeout: const Duration(seconds: 90),
  );
  // ② 남은 것을 하나씩 켠다. 이미 active 면 실패하고 넘어간다.
  for (final name in nav2ManagedNodes) {
    await _run(
      'ros2 lifecycle set /$namespace/$name activate',
      rosDomainId,
      timeout: const Duration(seconds: 30),
    );
  }
}

/// 확인하고, 안 켜졌으면 켜고, 다시 확인한다.
///
/// 백엔드를 띄운 뒤 이것 하나만 부르면 된다. 사람이 `ros2 lifecycle get` 을
/// 여덟 번 쳐서 알아낼 일이 아니다.
Future<({Nav2FleetStatus status, Nav2RecoveryOutcome outcome})>
ensureNav2Active({
  required String robotId,
  required String namespace,
  required int rosDomainId,
}) async {
  final before = await readNav2Status(
    robotId: robotId,
    namespace: namespace,
    rosDomainId: rosDomainId,
  );
  if (!nav2NeedsRecovery(before)) {
    return (
      status: before,
      outcome: nav2RecoveryOutcome(before: before, after: before),
    );
  }
  await activateNav2Nodes(namespace: namespace, rosDomainId: rosDomainId);
  final after = await readNav2Status(
    robotId: robotId,
    namespace: namespace,
    rosDomainId: rosDomainId,
  );
  return (
    status: after,
    outcome: nav2RecoveryOutcome(before: before, after: after),
  );
}
