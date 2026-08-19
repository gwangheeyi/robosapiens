/// 백엔드를 띄우기 전에 로봇 브링업이 먼저 서 있는지 본다.
///
/// **순서가 뒤집히면 Nav2 가 반쯤 죽은 채로 뜬다.** Nav2 의 `local_costmap` 은
/// 활성화할 때 `<로봇>/base_footprint → <로봇>/odom` TF 를 잠깐 기다리는데,
/// 로봇이 없으면 그 시간이 지나고 이렇게 끝난다:
///
///     [local_costmap]: Failed to activate local_costmap because transform
///       from pinky_02/base_footprint to pinky_02/odom did not become available
///     [lifecycle_manager]: Failed to change state for node: controller_server
///     [lifecycle_manager]: Failed to bring up all requested nodes.
///       Aborting bringup.
///
/// **관리자는 여기서 멈추고 다시 시도하지 않는다.** 뒤늦게 로봇을 켜도 스스로
/// 살아나지 않는다. `amcl` 만 active 로 남고 나머지는 inactive 에 머무는데,
/// 그 상태에서 작업을 넣으면 어댑터가 `Nav2 가 거절했습니다` 만 남기고 끝난다 —
/// `bt_navigator` 가 inactive 라 `navigate_to_pose` action 자체가 없기 때문이다.
///
/// 그때 화면에는 작업이 **진행 중**으로 보인다. 로봇은 명령을 받은 적이 없는데
/// 사람은 기다린다. 실제로 그 일이 있었다.
///
/// 그래서 띄우기 전에 막는다. 나중에 고치는 것보다 안 어긋나게 하는 편이 낫다.
///
/// 판정을 화면에서 떼어 둔 것은 [RobotLink] 와 같은 이유다 — 규칙은 눌러 보지
/// 않고도 확인할 수 있어야 한다.
library;

import 'rmf_project_config.dart';

/// 로봇 하나가 브링업으로 내야 하는 토픽이 오고 있는가.
class RobotBringupState {
  const RobotBringupState({
    required this.robotId,
    required this.displayName,
    required this.hasOdom,
    required this.hasScan,
  });

  final String robotId;
  final String displayName;

  /// `<로봇>/odom` 이 오는가. costmap 이 기다리는 TF 를 이 노드가 낸다.
  final bool hasOdom;

  /// `<로봇>/scan` 이 오는가. AMCL 이 이것으로 자리를 잡는다.
  final bool hasScan;

  bool get ready => hasOdom && hasScan;

  /// 무엇이 빠졌는지.
  List<String> get missing => [
    if (!hasOdom) 'odom',
    if (!hasScan) 'scan',
  ];

  String get label => '$robotId · $displayName';
}

/// 백엔드를 띄워도 되는가.
enum BringupPrecheckResult {
  /// 다 서 있다.
  ready,

  /// 볼 로봇이 없다. Gazebo·Mock 만 있는 프로젝트다 — 막을 이유가 없다.
  nothingToCheck,

  /// 브링업이 안 뜬 실물 로봇이 있다.
  missingBringup,
}

/// 실물 이동 로봇만 본다.
///
/// Gazebo 로봇은 시뮬레이터가 띄우므로 백엔드보다 먼저 설 수 없고, Mock 은
/// 토픽 자체가 없다. 그것들까지 막으면 시뮬레이션 프로젝트를 아예 못 띄운다.
List<RmfProjectRobot> robotsNeedingBringup(List<RmfProjectRobot> robots) => [
  for (final robot in robots)
    if (robot.isMobile && robot.dataSource == RobotDataSource.real) robot,
];

/// 띄워도 되는지 본다.
BringupPrecheckResult checkBringupBeforeBackend(
  List<RobotBringupState> states,
) {
  if (states.isEmpty) return BringupPrecheckResult.nothingToCheck;
  return states.every((state) => state.ready)
      ? BringupPrecheckResult.ready
      : BringupPrecheckResult.missingBringup;
}

/// 막을 때 보여 줄 말. 막지 않으면 null.
///
/// **무엇을 하라고까지 적는다.** 이유만 적으면 화면을 보고도 다음 손이 안
/// 나간다.
String? bringupPrecheckMessage(List<RobotBringupState> states) {
  final notReady = [
    for (final state in states)
      if (!state.ready) state,
  ];
  if (notReady.isEmpty) return null;
  final lines = [
    for (final state in notReady)
      '  · ${state.label} — ${state.missing.join(' · ')} 이(가) 안 옵니다',
  ];
  return '로봇 브링업이 먼저 서 있어야 합니다.\n\n'
      '${lines.join('\n')}\n\n'
      '지금 띄우면 Nav2 의 costmap 이 로봇의 TF 를 못 찾아 '
      '`controller_server` 에서 멈추고, 그 뒤 노드는 시도조차 하지 않습니다. '
      '`amcl` 만 켜진 채로 남아서, 작업을 넣어도 로봇이 명령을 받지 못합니다 — '
      '화면에는 진행 중으로 보입니다.\n\n'
      '로봇 상세에서 `브링업 띄우기` 를 누르거나, 로봇에서 직접 올린 뒤 '
      '다시 시도해 주세요. `켤 때 자동 실행` 을 걸어 두면 로봇 전원만으로 '
      '이 단계가 끝납니다.';
}
