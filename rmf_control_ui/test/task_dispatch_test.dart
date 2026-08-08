import 'package:flutter_test/flutter_test.dart';
import 'package:rmf_control_ui/task_dispatch.dart';

/// 로봇이 모자라 대기가 쌓였을 때 어느 작업을 먼저 내보내는지 정한다.
///
/// 화면 목록은 새 작업이 위로 오도록 앞에 끼워 넣기 때문에, 그 순서를 그대로
/// 쓰면 나중에 들어온 주문이 먼저 처리된다. 실제로 그렇게 동작하고 있었다.
void main() {
  ({String id, DateTime at}) task(String id, int minute) =>
      (id: id, at: DateTime(2026, 8, 8, 10, minute));

  List<String> order(List<({String id, DateTime at})> tasks) => [
    for (final entry in dispatchOrder(tasks, (task) => task.at)) entry.id,
  ];

  test('먼저 만들어진 작업이 먼저 나간다', () {
    expect(order([task('A', 1), task('B', 2), task('C', 3)]), ['A', 'B', 'C']);
  });

  test('목록이 새 작업부터 담겨 있어도 생성 순서대로 나간다', () {
    // _mockTasks 는 insert(0, …) 로 쌓이므로 최신이 앞이다. 이 순서를 그대로
    // 배차하던 것이 이번 문제였다.
    expect(order([task('C', 3), task('B', 2), task('A', 1)]), ['A', 'B', 'C']);
  });

  test('생성 시각이 같으면 넘겨받은 순서를 지킨다', () {
    final same = [task('먼저', 5), task('나중', 5)];
    expect(order(same), ['먼저', '나중']);
    expect(order(same.reversed.toList()), ['나중', '먼저']);
  });

  test('빈 목록과 한 건은 그대로 둔다', () {
    expect(order([]), isEmpty);
    expect(order([task('혼자', 7)]), ['혼자']);
  });

  test('원본 목록은 건드리지 않는다', () {
    final original = [task('C', 3), task('A', 1)];
    final copy = [...original];
    dispatchOrder(original, (task) => task.at);
    expect(original, copy, reason: '화면 표시 순서가 배차 때문에 바뀌면 안 된다');
  });
}
