/// 이미 떠 있는 Open-RMF 백엔드의 상태.
library;

/// `ros2 node list` 로 확인한 RMF 노드 현황.
class RmfRuntimeStatus {
  const RmfRuntimeStatus({
    required this.available,
    required this.nodes,
    required this.message,
  });

  /// ROS 환경을 찾아 조회에 성공했는지. false 면 [nodes] 는 비어 있고
  /// [message] 가 이유를 담는다 — 노드가 없는 것과 확인하지 못한 것은 다르다.
  final bool available;

  /// 떠 있는 RMF 관련 노드 이름.
  final List<String> nodes;

  /// 사용자에게 보여 줄 설명. 조회 실패 사유 또는 요약.
  final String message;

  bool get isRunning => nodes.isNotEmpty;

  static const RmfRuntimeStatus unknown = RmfRuntimeStatus(
    available: false,
    nodes: [],
    message: '아직 확인하지 않았습니다.',
  );
}

/// 백엔드 중지 스크립트 실행 결과.
class RmfStopResult {
  const RmfStopResult({required this.success, required this.output});
  final bool success;
  final String output;
}
