/// 로봇이 **다른 기계**에 있을 때 DDS 가 서로를 찾게 하는 값.
///
/// 앱은 `ros2` 를 자식 프로세스로 띄워 토픽을 읽는다. 그 자식이 로봇을 못 찾으면
/// 값이 안 오고, 앱은 그 로봇을 Mock 으로 떨어뜨린다 — `effectiveDataSource` 가
/// 값이 실제로 올 때만 `real` 로 표시하기 때문이다.
///
/// 실측(2026-08-17) — 실물 Pinky 를 붙이는 중에 이것 때문에 막혔다. 공유기가
/// 단말끼리의 멀티캐스트를 막아서 ping 은 되는데 DDS 탐색만 안 됐다. 로봇과 PC
/// 의 `ROS_DOMAIN_ID` · `ROS_AUTOMATIC_DISCOVERY_RANGE` · `RMW_IMPLEMENTATION` 이
/// 모두 같은데도 서로를 못 봤다:
///
///     로봇에서  ros2 topic info /pinky_01/odom  →  Publisher 1 · Subscription 0
///     PC 에서   ros2 topic info /pinky_01/odom  →  Publisher 0
///
/// `ROS_STATIC_PEERS` 로 상대를 지목하면 유니캐스트로 탐색해 바로 붙었다. 한쪽만
/// 걸어도 양방향이 된다 — 상대가 들어온 유니캐스트에서 주소를 배운다.
///
/// **자식에게 물려주지 않으면 앱만 못 본다.** 백엔드는 실행 스크립트가 띄우므로
/// 그쪽에 값을 주면 되지만, 앱이 제 손으로 띄우는 `ros2 topic echo` 는 이 함수를
/// 거쳐야 값을 받는다. 실제로 그래서 RViz(백엔드가 띄운 것)에는 로봇이 보이는데
/// 앱에서는 Mock 으로 보이는 상태가 됐다.
library;

import 'dart:io';

/// `ROS_STATIC_PEERS` 를 자식 셸에 물려주는 한 줄. 값이 없으면 빈 문자열.
///
/// 앱을 띄운 환경의 값을 그대로 넘긴다. 값이 없을 때 아무 것도 안 내보내는 것이
/// 중요하다 — 빈 값을 내보내면 rmw 가 빈 피어를 하나 읽고 경고를 낸다.
String rosStaticPeersExport() {
  final peers = Platform.environment['ROS_STATIC_PEERS']?.trim();
  if (peers == null || peers.isEmpty) return '';
  return 'export ROS_STATIC_PEERS=${_shellQuote(peers)}; ';
}

/// 셸에 넘길 문자열을 작은따옴표로 감싼다. 피어는 `;` 로 나누므로 반드시 감싼다.
String _shellQuote(String value) => "'${value.replaceAll("'", r"'\''")}'";
