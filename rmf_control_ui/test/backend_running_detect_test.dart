/// 시뮬레이터 없는 프로젝트에서도 백엔드가 떠 있는 것을 알아보는지 지킨다.
///
/// 예전에는 어디서든 `gazeboRunningProjects()` 를 불렀다. 그것은 `gz sim` 하나만
/// 센다. 실물 로봇만 쓰는 프로젝트(`SIM_BACKEND=none`)에는 Gazebo 가 없으니 늘
/// 빈 목록이 나왔고, RMF core·Nav2·fleet adapter 가 전부 떠 있는데도
/// `Open-RMF 실행 — 떠 있지 않습니다` 로 보였다.
///
/// 화면만 틀린 것이 아니었다. `robotMoveBlocker` 가 같은 값으로 **보내기를
/// 막는다** — 그래서 실제로 로봇을 못 보냈다.
///
/// 실측(2026-08-17) — 실물 Pinky 한 대로 `project1-ver2` 를 띄운 상태:
///
///     ros2 node list  →  38개 (RMF core·Nav2·fleet adapter 다 있음)
///     pgrep -af "gz sim"  →  없음
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late String source;
  late String main;

  setUpAll(() {
    source = File('lib/rmf_runtime_service_io.dart').readAsStringSync();
    main = File('lib/main.dart').readAsStringSync();
  });

  String bodyOf(String text, String signature) {
    final start = text.indexOf(signature);
    expect(start, greaterThanOrEqualTo(0), reason: '$signature 가 없습니다');
    return text.substring(start, text.indexOf('\n}\n', start));
  }

  group('RMF core 를 세는 쪽', () {
    test('Gazebo 가 아니라 프로젝트 launch 를 센다', () {
      final body = bodyOf(source, 'Future<List<String>> rmfCoreRunningProjects()');
      expect(body, contains('launch.xml'));
      // Gazebo 를 다시 물으면 원래 문제로 돌아간다.
      expect(body, isNot(contains('gz sim')));
    });

    test('중지 스크립트와 pgrep 자신은 안 센다', () {
      // `pgrep -af` 는 그 글자를 명령줄에 담은 것을 전부 잡는다 — 이 검사를
      // 띄운 셸 자신까지.
      final body = bodyOf(source, 'Future<List<String>> rmfCoreRunningProjects()');
      expect(body, contains("!line.contains('stop_')"));
      expect(body, contains("!line.contains('pgrep')"));
    });

    test('맵 이름이 아니라 디렉터리 경로로 가린다', () {
      // 이름만 보면 `gwanghee` 가 `gwanghee2` 의 launch 에도 걸린다.
      final body = bodyOf(source, 'Future<List<String>> rmfCoreRunningProjects()');
      expect(body, contains(r"line.contains('${entry.path}/')"));
    });

    test('배포만 한 상태를 백엔드로 보지 않는 까닭을 남긴다', () {
      // 맵 디렉터리를 물고 있는 것을 전부 세면 배포가 남긴 `building_map_server`
      // 와 `ros2 run` 껍데기가 걸린다. 배포는 launch 를 띄우지 않는다.
      expect(source, contains('배포는 launch 를 띄우지 않으므로'));
    });
  });

  group('무엇을 셀지 고르는 쪽', () {
    test('Gazebo 프로젝트는 예전대로 gz sim 을 본다', () {
      // 물리가 죽고 RMF·Nav2 만 남은 상태를 초록으로 보여 준 적이 있다.
      final body = bodyOf(source, 'Future<List<String>> backendRunningProjects(');
      expect(body, contains('usesGazebo'));
      expect(body, contains('gazeboRunningProjects()'));
      expect(body, contains('rmfCoreRunningProjects()'));
    });

    test('웹 대체 구현에도 같은 이름이 있다', () {
      final stub = File('lib/rmf_runtime_service_stub.dart').readAsStringSync();
      expect(stub, contains('rmfCoreRunningProjects'));
      expect(stub, contains('backendRunningProjects'));
    });
  });

  group('앱이 부르는 쪽', () {
    test('확인표는 프로젝트 설정에 맞게 묻는다', () {
      // 여기가 `gazeboRunningProjects()` 로 남아 있으면 확인표가 다시 거짓말한다.
      final body = bodyOf(main, 'Future<void> _refreshReadiness()');
      expect(body, contains('_probeBackendRunning('));
      expect(body, isNot(contains('gazeboRunningProjects()')));
      // 설정은 한 번만 읽어서 두 가지를 가른다 — 무엇을 셀지, 시계 칸을 둘지.
      expect(body, contains('_projectSimBackend('));
      expect(body, contains('simBackend != SimulationBackend.none'));
    });

    test('설정을 못 읽으면 Gazebo 로 본다', () {
      // 대부분의 프로젝트가 그것이다. 모른다고 안 떠 있다고 하면 멀쩡한 백엔드를
      // 두고 원인을 찾게 된다.
      final body = bodyOf(
        main,
        'Future<SimulationBackend> _projectSimBackend(String mapName)',
      );
      expect(body, contains('return SimulationBackend.gazebo;'));
    });

    test('실행 직후에는 방금 고른 값을 쓴다', () {
      // 디스크에 아직 안 내려갔을 수 있다.
      final body = bodyOf(main, 'Future<void> _startBackendFromDetail()');
      expect(body, contains('usesGazebo: windows.backend == SimulationBackend.gazebo'));
    });

    test('gazeboRunningProjects 를 직접 부르는 곳이 남지 않았다', () {
      // 한 곳만 남아도 그 화면에서 같은 거짓말이 되살아난다.
      expect(main, isNot(contains('await gazeboRunningProjects()')));
    });
  });
}
