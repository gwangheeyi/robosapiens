/// `/clock` 을 내는 곳 세기.
///
/// **DDS 그래프가 아니라 프로세스를 센다.** 예전에는 `ros2 topic info /clock`
/// 으로 발행자 수를 물었는데, 그 답이 틀렸다. `--no-daemon` 은 그때그때 참가자를
/// 새로 만들어 DDS 를 훑어서, 탐색이 짧으면 멀쩡히 도는 발행자를 못 본다.
///
/// 실측(2026-08-15, 다리가 정확히 하나 도는 상태) —
///
///     spin-time 3 → 1 1 0 1 0 1 1 1     8번 중 2번이 0
///     spin-time 5 → 1 1 1 1 0 1         6번 중 1번이 0
///     spin-time 8 → 1 1 1 1 1 1
///
/// `0` 은 화면에서 `Gazebo 가 죽었다` 로 읽힌다. 그래서 확인표가 켜졌다 꺼졌다
/// 했다. 시간을 늘리면 확률만 낮아질 뿐 없어지지 않는다.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late String source;

  setUpAll(
    () => source = File('lib/rmf_runtime_service_io.dart').readAsStringSync(),
  );

  test('DDS 그래프에 묻지 않는다', () {
    final probe = source.indexOf('Future<int?> probeClockPublishers');
    final body = source.substring(probe, source.indexOf('\n}\n', probe));

    expect(body, isNot(contains('ros2 topic info')));
    expect(body, contains('pgrep'));
    expect(body, contains('ros_gz_bridge/parameter_bridge'));
  });

  test('왜 그렇게 했는지 실측을 남긴다', () {
    // 다음 사람이 "topic info 가 더 정확하지 않나" 하고 되돌리지 않도록.
    expect(source, contains('spin-time 3 → 1 1 0 1 0 1 1 1'));
  });

  test('검사를 띄운 셸 자신을 세지 않는다', () {
    // `pgrep -af` 는 그 글자를 명령줄에 담은 것을 전부 잡는다. 실측으로 다리가
    // 하나인데 2 가 나왔다 — 셸이 함께 걸린 것이다.
    final probe = source.indexOf('Future<int?> probeClockPublishers');
    final body = source.substring(probe, source.indexOf('\n}\n', probe));

    // 명령이 다리 실행 파일 자신인 줄만 센다.
    expect(
      body,
      contains(r"RegExp(r'^\d+\s+\S*ros_gz_bridge/parameter_bridge"),
    );
  });

  test('시계를 안 잇는 다리는 세지 않는다', () {
    // 한 프로젝트가 다리를 여럿 띄우더라도 `/clock` 을 내는 것만 문제다.
    final probe = source.indexOf('Future<int?> probeClockPublishers');
    final body = source.substring(probe, source.indexOf('\n}\n', probe));

    expect(body, contains('config_file:='));
    expect(body, contains("contains('/clock')"));
  });

  test('확인표가 이 값을 매번 다시 읽는다', () {
    // 늦게 갱신되면 남은 다리를 알아채는 것도 그만큼 늦는다. `pgrep` 한 번이라
    // 아낄 이유가 없다.
    final main = File('lib/main.dart').readAsStringSync();
    expect(main, isNot(contains('_readinessTick')));
    expect(
      main,
      contains('? await probeClockPublishers(rosDomainId: _rosDomainId)'),
    );
  });
}
