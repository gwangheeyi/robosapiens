/// ROS 에 물어보는 명령을 **시한과 함께** 돌린다.
///
/// `Process.run(...).timeout(...)` 은 기다리기를 그만둘 뿐 **프로세스는 그대로
/// 둔다.** `ros2 service call` 은 상대가 없으면 영원히 기다리므로, 검사를 한 번
/// 할 때마다 매달린 프로세스가 하나씩 쌓인다.
///
/// 실측(2026-08-17) — 앱의 프로세스 그룹(PGID 131477)에
/// `ros2 service call /map_server/get_state` 다섯 개가 30분 넘게 남아 있었다.
/// 같은 ROS 도메인에 붙어 있으니 공짜도 아니고, 사람이 `pkill` 로 치워야 했다.
///
/// 그래서 coreutils 의 `timeout` 을 앞에 세운다. `timeout` 은 자식을 **제
/// 프로세스 그룹에** 두고 시한이 되면 그 무리를 통째로 끊으므로, `bash -lc` 가
/// 띄운 `ros2`(파이썬)까지 함께 죽는다. Dart 쪽 시한은 그것마저 안 될 때를 위한
/// 뒷받침이다.
library;

import 'dart:io';

/// 셸 명령 하나를 돌리고, 시한을 넘기면 프로세스까지 끊는다.
///
/// 못 돌렸거나 시한을 넘겼으면 null 이다. 부른 쪽은 "모른다" 로 다루면 된다 —
/// 답이 없는 것과 답이 늦는 것을 같은 자리에서 가려낼 방법이 없기 때문이다.
Future<ProcessResult?> runRosProbe(
  String command, {
  Duration timeout = const Duration(seconds: 15),
}) async {
  final seconds = timeout.inSeconds.clamp(1, 600);
  try {
    return await Process.run('timeout', [
      // 먼저 곱게 끊고, 그래도 안 죽으면 2초 뒤에 확실히 끊는다.
      '--signal=TERM',
      '--kill-after=2',
      '$seconds',
      'bash',
      '-lc',
      command,
    ]).timeout(timeout + const Duration(seconds: 5));
  } catch (_) {
    return null;
  }
}
