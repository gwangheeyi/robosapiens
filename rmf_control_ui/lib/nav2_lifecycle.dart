/// Nav2 노드가 다 켜졌는지 보고, 안 켜졌으면 다시 켠다.
///
/// 백엔드를 띄운 뒤 **가장 자주 어긋나는 자리**다. 그런데 겉으로는 아무 문제가
/// 없어 보인다 — 프로세스는 다 살아 있고 노드 목록에도 다 나온다. 오류도 안
/// 난다. 다만 로봇이 안 움직일 뿐이고, 그때 사람은 라이다와 AMCL 을 의심한다.
///
/// 실제로 겪은 일이다. `lifecycle_manager` 가 `controller_server` 를 켜다가
/// 실패하자 **뒤의 노드는 시도조차 하지 않았다**:
///
///     [local_costmap]: Failed to activate local_costmap because transform
///       from pinky_03/base_footprint to pinky_03/odom did not become
///       available before timeout
///     [lifecycle_manager]: Failed to change state for node: controller_server
///     [lifecycle_manager]: Failed to bring up all requested nodes.
///       Aborting bringup.
///
/// 남은 상태는 `amcl` 만 active 고 나머지는 inactive 였다. 작업을 넣으면
/// 어댑터가 `Nav2 가 거절했습니다` 한 줄만 남기고 끝난다 — `bt_navigator` 가
/// inactive 라 `navigate_to_pose` action 자체가 없기 때문이다.
///
/// 까닭은 **순서**였다. PC 의 Nav2 가 로봇 브링업보다 먼저 떠서, costmap 이
/// 기다리던 `<로봇>/odom` TF 가 그때는 없었다. 로봇이 나중에 올라와 TF 가
/// 생겨도 `lifecycle_manager` 는 이미 포기한 뒤라 **다시 시도하지 않는다.**
///
/// 그래서 두 가지가 필요하다. 다 켜졌는지 **확인**하는 것과, 안 켜졌으면 다시
/// **켜는** 것이다. 사람이 `ros2 lifecycle get` 을 여덟 번 쳐서 알아낼 일이
/// 아니다.
///
/// 판정을 화면에서 떼어 둔 것은 [RobotLink] 와 같은 이유다 — 규칙은 눌러 보지
/// 않고도 확인할 수 있어야 한다.
library;

/// lifecycle 노드가 가질 수 있는 상태.
///
/// 이름은 `ros2 lifecycle get` 이 찍는 것을 그대로 쓴다. 문제를 찾을 때 사람이
/// 결국 그 명령을 치기 때문이다.
enum Nav2NodeState {
  /// 켜졌다. 명령을 받는다.
  active,

  /// 설정은 끝났는데 안 켜졌다. **명령을 안 받는다.**
  ///
  /// 겉보기에 가장 위험한 상태다. 노드 목록에 나오고 파라미터도 읽히지만,
  /// action server 가 없어 작업이 조용히 거절된다.
  inactive,

  /// 설정조차 안 됐다. `lifecycle_manager` 가 여기까지 오지도 못했다.
  unconfigured,

  /// 물어봤는데 답이 없다. 노드가 죽었거나 도메인이 다르다.
  unreachable,
}

/// 노드 하나의 상태.
class Nav2NodeStatus {
  const Nav2NodeStatus({required this.name, required this.state});

  /// 네임스페이스를 뺀 이름(`controller_server`).
  final String name;
  final Nav2NodeState state;

  bool get isActive => state == Nav2NodeState.active;
}

/// `ros2 lifecycle get` 의 출력에서 상태를 읽는다.
///
/// 출력은 `active [3]` 처럼 상태 이름과 번호가 함께 온다. 못 읽으면
/// [Nav2NodeState.unreachable] 이다 — **모르는 것을 active 로 보면 안 된다.**
/// 그러면 안 켜진 로봇에 작업을 넣고 왜 안 가는지 찾게 된다.
/// `inactive` 안에 `active` 가 들어 있다. 순서대로 `contains` 를 쓰면 안 켜진
/// 노드를 켜졌다고 읽어 **확인이 있으나 마나 해진다** — 낱말 경계로 가른다.
Nav2NodeState parseNav2NodeState(String output) {
  final text = output.toLowerCase();
  bool has(String word) =>
      RegExp('(^|[^a-z])$word([^a-z]|\$)').hasMatch(text);
  if (has('inactive')) return Nav2NodeState.inactive;
  if (has('unconfigured')) return Nav2NodeState.unconfigured;
  if (has('active')) return Nav2NodeState.active;
  return Nav2NodeState.unreachable;
}

/// 이동 로봇 하나가 띄우는 Nav2 노드들. 배포 launch 와 같은 차례다.
///
/// `amcl` 이 먼저다. costmap 을 쓰는 것보다 그것을 만드는 쪽이 먼저 서야 한다
/// (`buildRobotNav2LaunchXml` 의 주석과 같은 규칙).
const List<String> nav2ManagedNodes = [
  'amcl',
  'controller_server',
  'smoother_server',
  'planner_server',
  'behavior_server',
  'bt_navigator',
  'waypoint_follower',
  'velocity_smoother',
];

/// 작업을 내려면 반드시 active 여야 하는 노드.
///
/// 나머지가 꺼져 있어도 갈 수는 있지만, 이 셋이 없으면 `navigate_to_pose` 가
/// 아예 성립하지 않는다.
const Set<String> nav2EssentialNodes = {
  'amcl',
  'controller_server',
  'bt_navigator',
};

/// 로봇 한 대의 Nav2 전체 상태.
class Nav2FleetStatus {
  const Nav2FleetStatus({required this.robotId, required this.nodes});

  final String robotId;
  final List<Nav2NodeStatus> nodes;

  /// 다 켜졌는가.
  bool get allActive => nodes.isNotEmpty && nodes.every((node) => node.isActive);

  /// 작업을 낼 수 있는가. 꼭 필요한 것만 본다.
  bool get canNavigate =>
      nodes.isNotEmpty &&
      nodes
          .where((node) => nav2EssentialNodes.contains(node.name))
          .every((node) => node.isActive);

  /// 안 켜진 노드.
  List<Nav2NodeStatus> get notActive =>
      [for (final node in nodes) if (!node.isActive) node];

  /// 하나도 응답하지 않는가. Nav2 자체가 안 떠 있다는 뜻이다.
  bool get allUnreachable =>
      nodes.isNotEmpty &&
      nodes.every((node) => node.state == Nav2NodeState.unreachable);
}

/// 다시 켤 필요가 있는가.
///
/// 하나라도 응답하면 Nav2 는 떠 있는 것이고, 그중 안 켜진 것이 있으면 켤 수
/// 있다. 전부 응답이 없으면 Nav2 가 아예 없는 것이라 여기서 할 일이 아니다 —
/// 백엔드를 다시 띄워야 한다.
bool nav2NeedsRecovery(Nav2FleetStatus status) =>
    !status.allUnreachable && !status.allActive;

/// 사람에게 보여 줄 한 줄. 다 켜졌으면 null.
String? nav2StatusMessage(Nav2FleetStatus status) {
  if (status.allUnreachable) {
    return '${status.robotId} 의 Nav2 가 응답하지 않습니다. '
        '백엔드가 떠 있는지, ROS 도메인이 맞는지 확인해 주세요.';
  }
  if (status.allActive) return null;
  final stuck = status.notActive;
  final names = stuck.map((node) => node.name).join(', ');
  final blocksWork = !status.canNavigate;
  return '${status.robotId} 의 Nav2 가 다 안 켜졌습니다 — $names.\n\n'
      '${blocksWork ? '이대로는 작업을 내도 로봇이 안 움직입니다. ' : '갈 수는 있지만 일부 기능이 빠집니다. '}'
      'inactive 인 노드는 명령을 안 받는데 **오류를 내지 않습니다** — '
      '노드 목록에는 그대로 보입니다.';
}

/// 다시 켠 결과.
enum Nav2RecoveryOutcome {
  /// 다 켜졌다.
  recovered,

  /// 이미 다 켜져 있었다. 아무것도 안 했다.
  alreadyActive,

  /// 켜려 했는데 아직 안 켜진 것이 남았다.
  stillBlocked,

  /// Nav2 가 응답하지 않는다. 백엔드부터 봐야 한다.
  unreachable,
}

/// 켜기 전과 후를 보고 무슨 일이 있었는지 가른다.
Nav2RecoveryOutcome nav2RecoveryOutcome({
  required Nav2FleetStatus before,
  required Nav2FleetStatus after,
}) {
  if (before.allActive) return Nav2RecoveryOutcome.alreadyActive;
  if (after.allUnreachable) return Nav2RecoveryOutcome.unreachable;
  if (after.allActive) return Nav2RecoveryOutcome.recovered;
  return Nav2RecoveryOutcome.stillBlocked;
}

/// 켠 뒤에 남길 말.
String nav2RecoveryMessage({
  required Nav2RecoveryOutcome outcome,
  required Nav2FleetStatus after,
}) => switch (outcome) {
  Nav2RecoveryOutcome.alreadyActive =>
    '${after.robotId} 의 Nav2 는 이미 다 켜져 있습니다.',
  Nav2RecoveryOutcome.recovered =>
    '${after.robotId} 의 Nav2 를 다 켰습니다 — '
        '${after.nodes.length}개 노드가 active 입니다. 작업을 내실 수 있습니다.',
  Nav2RecoveryOutcome.stillBlocked =>
    '${after.robotId} 의 Nav2 를 다 켜지 못했습니다 — '
        '${after.notActive.map((node) => node.name).join(', ')}.\n\n'
        'costmap 이 로봇의 TF 를 못 찾는 것이 가장 흔한 까닭입니다. '
        '로봇 브링업이 떠서 `<로봇>/odom` 프레임이 나오는지 확인한 뒤 '
        '다시 눌러 주세요.',
  Nav2RecoveryOutcome.unreachable =>
    '${after.robotId} 의 Nav2 가 응답하지 않습니다. '
        '백엔드를 먼저 띄워 주세요.',
};
