/// 로봇 관리 화면의 백엔드 안내가 **없는 시뮬레이터를 들먹이지 않는지** 지킨다.
///
/// 실물 Pinky 만 쓰는 프로젝트(`SIM_BACKEND=none`)로 띄웠는데
/// `실제 로봇·Gazebo 모드로 새로 띄우기 전에 정리하세요` 가 떴다. Gazebo 는 띄운
/// 적도 없으니, 무엇을 정리해야 하는지 알 수 없는 말이 된다. 정리해야 하는 것은
/// 지금 떠 있는 그 노드들이다.
///
/// 앞서 고친 `gazeboRunningProjects()` 와 같은 부류다 — 앱이 어디서나 Gazebo 가
/// 있다고 가정한 자리들.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late String source;

  setUpAll(() => source = File('lib/main.dart').readAsStringSync());

  test('Gazebo 를 못 박아 두지 않는다', () {
    // 이 문구가 문자열 상수로 되살아나면 같은 혼동이 그대로 돌아온다.
    expect(source, isNot(contains('실제 로봇·Gazebo 모드로 새로 띄우기 전에')));
    expect(source, isNot(contains('프로젝트로 띄우면 Gazebo 와 함께 올라옵니다')));
  });

  test('시뮬레이터가 없으면 이름을 말하지 않는다', () {
    expect(source, contains('bool get _hasSimulator'));
    expect(source, contains('_simBackend != SimulationBackend.none'));
  });

  test('시뮬레이터가 있으면 그 이름을 쓴다', () {
    // Gazebo 든 Isaac Sim 든 고른 것을 그대로 적어야 한다.
    expect(source, contains(r"'실제 로봇·${_simBackend!.label} 모드로 새로 띄우기 전에 '"));
  });

  test('없을 때는 무엇을 정리하는지 밝힌다', () {
    // `정리하세요` 만 있으면 무엇을 정리할지 모른다.
    expect(source, contains('두 번 띄우면 schedule node 와 '));
  });

  test('프로젝트 설정을 읽어 온다', () {
    expect(source, contains('Future<void> _refreshSimBackend()'));
    expect(source, contains('loadProjectSimulationSettings(name)'));
    // 화면에 들어올 때와 프로젝트가 바뀔 때 둘 다 읽어야 한다.
    expect(source, contains('unawaited(_refreshSimBackend());'));
  });

  test('못 읽으면 이름을 말하지 않는다', () {
    // 틀린 이름을 적는 것보다 안 적는 편이 낫다. `_simBackend` 가 null 이면
    // `_hasSimulator` 가 false 라 시뮬레이터 없는 쪽 문구로 간다.
    expect(source, contains('_simBackend != null &&'));
  });
}
