/// 웹에서는 프로세스를 띄울 수 없다. 확인할 수단이 없으므로 "모른다" 로 둔다.
///
/// 모르는 것을 active 로 보면 안 된다 — 그러면 안 켜진 로봇에 작업을 넣고 왜
/// 안 가는지 찾게 된다.
library;

import 'nav2_lifecycle.dart';

Nav2FleetStatus _unknown(String robotId) => Nav2FleetStatus(
  robotId: robotId,
  nodes: [
    for (final name in nav2ManagedNodes)
      Nav2NodeStatus(name: name, state: Nav2NodeState.unreachable),
  ],
);

Future<Nav2FleetStatus> readNav2Status({
  required String robotId,
  required String namespace,
  required int rosDomainId,
}) async => _unknown(robotId);

Future<void> activateNav2Nodes({
  required String namespace,
  required int rosDomainId,
}) async {}

Future<({Nav2FleetStatus status, Nav2RecoveryOutcome outcome})>
ensureNav2Active({
  required String robotId,
  required String namespace,
  required int rosDomainId,
}) async => (
  status: _unknown(robotId),
  outcome: Nav2RecoveryOutcome.unreachable,
);
