/// 방금 확인한 백엔드 상태를 잠깐 기억해 두는 규칙.
///
/// 확인 한 번이 `ros2 node list --no-daemon --spin-time 3` 이라 3초가 넘는다.
/// 데몬 캐시가 죽은 노드를 한참 살아 있다고 답해서 일부러 캐시를 끈 것인데,
/// 그 값이 화면에 들어올 때마다 새로 붙어 작업 관리에서 로봇 관리로 돌아올
/// 때마다 3초를 기다리게 됐다.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:rmf_control_ui/rmf_runtime_models.dart';

void main() {
  const running = RmfRuntimeStatus(
    available: true,
    nodes: ['/map_server'],
    message: '',
  );
  final base = DateTime(2026, 8, 19, 17);

  test('넣기 전에는 쓸 값이 없다', () {
    expect(RmfRuntimeCache().valueAt(base), isNull);
  });

  test('넣은 값을 곧바로 다시 쓴다', () {
    final cache = RmfRuntimeCache()..store(running, base);
    expect(cache.valueAt(base.add(const Duration(seconds: 2))), running);
  });

  /// 길게 두면 다른 창에서 백엔드를 내렸는데 화면은 계속 떠 있다고 말한다.
  test('오래되면 버린다', () {
    final cache = RmfRuntimeCache(lifetime: const Duration(seconds: 15))
      ..store(running, base);
    expect(cache.valueAt(base.add(const Duration(seconds: 14))), running);
    expect(cache.valueAt(base.add(const Duration(seconds: 16))), isNull);
  });

  /// 백엔드를 띄우거나 내리는 순간 기억해 둔 값은 거짓이 된다.
  test('버리라고 하면 버린다', () {
    final cache = RmfRuntimeCache()
      ..store(running, base)
      ..invalidate();
    expect(cache.valueAt(base), isNull);
  });
}
