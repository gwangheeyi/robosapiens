/// 로봇을 즉시 정지시키는 명령의 이름과 결과 문구.
library;

/// Nav2에서 동시에 살아 있을 수 있는 이동 action들.
///
/// RMF 주행뿐 아니라 상세 화면의 미세조종도 함께 멈춰야 하므로 전부 취소한다.
const List<String> robotMotionActions = [
  'navigate_to_pose',
  'navigate_through_poses',
  'drive_on_heading',
  'backup',
  'spin',
];

String robotTopic(String namespace, String name) {
  final ns = namespace.trim().replaceAll(RegExp(r'^/+|/+$'), '');
  return ns.isEmpty ? '/$name' : '/$ns/$name';
}

String robotStoppedMessage(String label) => '$label 을 정지했습니다.';

String robotStopFailedMessage(String label, String detail) =>
    '$label 을 정지시키지 못했습니다.\n\n'
    '${detail.trim().isEmpty ? 'ROS 응답이 없습니다.' : detail.trim()}';
