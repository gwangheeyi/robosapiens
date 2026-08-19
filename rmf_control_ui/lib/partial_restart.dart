/// 바꾼 것에 딸린 것만 다시 띄운다.
///
/// Waypoint 를 하나 옮기고 전체를 다시 띄우면 1~2분이 걸린다. Gazebo 가 다시
/// 서고, 로봇이 다시 스폰되고, Nav2 가 처음부터 lifecycle 을 밟는다 — 정작
/// 바뀐 것은 nav graph 하나인데.
///
/// **파일을 붙들고 있는 프로세스만 다시 띄우면 된다.** 무엇이 무엇을 읽는지는
/// 정해져 있다:
///
///     PinkyTest.building.yaml  →  building_map_server   (기동 시 1회)
///     nav_graphs/0.yaml        →  fleet_adapter          (기동 시 1회, -n 인자)
///     nav2_params.yaml         →  로봇 Nav2 노드들        (기동 시 1회)
///
/// 셋 다 **기동할 때 한 번** 읽고 그 뒤로는 메모리에 든 것을 쓴다. 다시 읽는
/// 서비스가 없으므로 그 프로세스를 다시 띄우는 수밖에 없다.
///
/// 무중단은 안 된다. `rmf_fleet_adapter` 에 nav graph 재적재 기능이 없고,
/// `rmf_traffic_schedule` 은 waypoint 를 **인덱스**로 관리해서 그래프가 바뀌면
/// 옛 인덱스로 계산한다 — 억지로 맞춰도 엉뚱한 자리로 보낸다. 그건 상류를
/// 고쳐야 하는 일이라 여기서 할 수 없다.
///
/// 판정을 화면에서 떼어 둔 것은 [RobotLink] 와 같은 이유다 — 규칙은 눌러 보지
/// 않고도 확인할 수 있어야 한다.
library;

/// 무엇을 바꿨는가.
enum ProjectChange {
  /// Waypoint · 레인 · 이름 — 지도 자체가 바뀌었다.
  map,

  /// 로봇 설정 — 주행 모드 · 후진 · 도착 반경 같은 것.
  robotParams,

  /// 작업만 새로 만들었다.
  taskOnly,
}

/// 이 변경에 무엇을 다시 띄워야 하는가.
enum RestartScope {
  /// 아무것도 안 띄워도 된다.
  none,

  /// RMF 계층만. Gazebo·Nav2·로봇 브링업은 그대로 둔다.
  rmfLayer,

  /// 그 로봇의 Nav2 만. RMF·브링업은 그대로 둔다.
  robotNav2,
}

/// 바꾼 것에 딸린 범위.
RestartScope restartScopeFor(ProjectChange change) => switch (change) {
  // nav graph 를 fleet_adapter 가 기동 시 읽고, schedule 이 인덱스로 관리한다.
  ProjectChange.map => RestartScope.rmfLayer,
  // nav2_params.yaml 은 그 로봇의 Nav2 노드만 읽는다.
  ProjectChange.robotParams => RestartScope.robotNav2,
  // 작업은 파일이 아니라 `/task_api_requests` 토픽으로 나간다. 다시 띄울 것이
  // 없다 — 만들자마자 바로 실행된다.
  ProjectChange.taskOnly => RestartScope.none,
};

/// 이 범위에서 다시 띄우는 것들. 사람에게 보여 줄 이름이다.
List<String> restartTargets(RestartScope scope) => switch (scope) {
  RestartScope.none => const [],
  RestartScope.rmfLayer => const [
    'building_map_server',
    'rmf_traffic_schedule',
    'fleet_adapter',
    'nav2_adapter',
  ],
  RestartScope.robotNav2 => const ['그 로봇의 Nav2 노드'],
};

/// 이 범위에서 **건드리지 않는** 것들.
///
/// 무엇이 살아남는지 밝혀야 한다. 안 그러면 사람이 로봇 브링업까지 다시
/// 띄워야 하는 줄 알고 로봇에 들어간다.
List<String> restartUntouched(RestartScope scope) => switch (scope) {
  RestartScope.none => const [],
  RestartScope.rmfLayer => const ['Gazebo', '로봇 Nav2', '로봇 브링업'],
  RestartScope.robotNav2 => const ['Gazebo', 'RMF core', '로봇 브링업'],
};

/// 얼마나 걸리는지 어림. 전체를 다시 띄우는 것과 견주기 위한 것이다.
Duration restartEstimate(RestartScope scope) => switch (scope) {
  RestartScope.none => Duration.zero,
  RestartScope.rmfLayer => const Duration(seconds: 20),
  RestartScope.robotNav2 => const Duration(seconds: 12),
};

/// 무엇을 하겠다는 말. 할 것이 없으면 null.
String? restartPlanMessage({
  required ProjectChange change,
  required String detail,
}) {
  final scope = restartScopeFor(change);
  if (scope == RestartScope.none) return null;
  final targets = restartTargets(scope);
  final untouched = restartUntouched(scope);
  return '$detail\n\n'
      '다시 띄울 것 — ${targets.join(' · ')}\n'
      '그대로 두는 것 — ${untouched.join(' · ')}\n\n'
      '${restartEstimate(scope).inSeconds}초쯤 걸립니다. '
      '전체를 다시 띄우는 것보다 빠릅니다.';
}

/// 작업만 바꿨을 때 하는 말.
///
/// **다시 띄울 것이 없다는 것을 밝힌다.** 아무 말도 안 하면 사람이 버릇처럼
/// 백엔드를 다시 띄운다.
const String taskOnlyNoRestartMessage =
    '작업은 파일이 아니라 토픽으로 나갑니다. 다시 띄울 것이 없습니다 — '
    '만들자마자 바로 실행됩니다.';
