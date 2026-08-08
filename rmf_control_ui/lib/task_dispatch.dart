/// 대기 중인 작업을 어떤 순서로 내보낼지 정한다.
library;

/// 먼저 만들어진 작업이 먼저 나가도록 세운다.
///
/// 화면의 작업 목록은 새 작업이 위로 오도록 앞에 끼워 넣는다(`insert(0, …)`).
/// 그 순서를 그대로 배차에 쓰면 나중에 들어온 주문이 먼저 처리되고 기다리던
/// 주문이 뒤로 밀린다. 목록을 보여 주는 순서와 일을 내보내는 순서는 별개다.
///
/// 생성 시각이 같으면 넘겨받은 순서를 지킨다. `List.sort` 는 안정 정렬이 아니라
/// 같은 시각끼리 뒤바뀔 수 있으므로 원래 자리를 함께 견준다.
List<T> dispatchOrder<T>(
  Iterable<T> tasks,
  DateTime Function(T task) createdAt,
) {
  final indexed = tasks.toList().asMap().entries.toList()
    ..sort((a, b) {
      final byTime = createdAt(a.value).compareTo(createdAt(b.value));
      return byTime != 0 ? byTime : a.key.compareTo(b.key);
    });
  return [for (final entry in indexed) entry.value];
}
