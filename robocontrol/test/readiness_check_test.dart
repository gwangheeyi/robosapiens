/// 작업 준비 확인표의 판단을 지킨다.
///
/// 로봇이 RViz 에 뜨려면 다섯이 줄줄이 되어야 하는데, 하나만 끊겨도 화면은 그냥
/// 빈다. 오류는 어디에도 안 난다 — 어댑터가 SIGSEGV 로 죽었을 때 Gazebo·Nav2·
/// RMF core 는 멀쩡히 살아 있어 겉으로는 정상으로 보였다.
///
/// 가장 조심할 것은 **모른다와 안 됐다를 가르는 것**이다. 뭉뚱그리면 확인 못 한
/// 것이 고장으로 읽혀, 멀쩡한 로봇을 두고 원인을 찾게 된다.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:robocontrol/nav2_map_alignment.dart';
import 'package:robocontrol/readiness_check.dart';
import 'package:robocontrol/rmf_project_config.dart';

void main() {
  const pinky = RmfProjectRobot(
    robotId: 'PK_01',
    displayName: '핑키 1호',
    model: 'PINKY-GZ',
    gzName: 'pinky_01',
    zones: ['ambient'],
    chargerWaypoint: '충전1',
    dataSource: RobotDataSource.gazebo,
  );
  const pinky2 = RmfProjectRobot(
    robotId: 'PK_02',
    displayName: '핑키 2호',
    model: 'PINKY-GZ',
    gzName: 'pinky_02',
    zones: ['ambient'],
    chargerWaypoint: '충전2',
    dataSource: RobotDataSource.gazebo,
  );
  const arm = RmfProjectRobot(
    robotId: 'OMX_01',
    displayName: '매니퓰레이터',
    model: 'OPENMANIPULATOR-X',
    gzName: 'omx_01',
    kind: RmfRobotKind.workcell,
    zones: ['ambient'],
    dataSource: RobotDataSource.gazebo,
  );
  const mockRobot = RmfProjectRobot(
    robotId: 'MK_01',
    displayName: '가짜 로봇',
    model: 'MOCK',
    gzName: 'mock_01',
    zones: ['ambient'],
  );

  ReadinessReport report({
    List<String> waypoints = const ['충전1', '픽업1'],
    List<RmfProjectRobot> robots = const [pinky],
    bool exported = true,
    bool backendRunning = true,
    bool fleetReachable = true,
    Set<String> attached = const {'PK_01'},
    Nav2MapAlignment? alignment = const Nav2MapAlignment(
      covered: true,
      outsideWaypoints: [],
      marginMeters: 1,
    ),
    int? clockPublishers = 1,
    // 지도 서버는 켜져 있는 것이 정상이다. 여기가 꺼지면 AMCL 이 map TF 를
    // 못 내고 로봇이 RMF 에 못 붙는다 — 그 사슬은
    // `map_server_lifecycle_test.dart` 가 따로 지킨다.
    String? mapServerState = 'active',
    // 기본값은 기다려 주는 시간을 한참 지난 값이다. 대부분의 시험은 다 뜬
    // 뒤의 상태를 본다.
    Duration? backendUptime = const Duration(minutes: 5),
    // 대부분의 시험은 시뮬레이터로 도는 프로젝트를 본다.
    bool usesSimulator = true,
    // Nav2 노드는 다 켜진 것이 정상이다. 빈 목록이 "다 켜졌다" 이고, 아예
    // 없으면 "아직 안 물어봤다" 다.
    Map<String, List<String>> nav2Stuck = const {'PK_01': []},
  }) => buildReadinessReport(
    waypointNames: waypoints,
    robots: robots,
    exported: exported,
    backendRunning: backendRunning,
    fleetReachable: fleetReachable,
    attachedRobots: attached,
    alignment: alignment,
    clockPublishers: clockPublishers,
    mapServerState: mapServerState,
    backendUptime: backendUptime,
    usesSimulator: usesSimulator,
    nav2Stuck: nav2Stuck,
  );

  ReadinessCheck find(ReadinessReport r, String title) =>
      r.checks.firstWhere((check) => check.title == title);

  group('다 됐을 때', () {
    test('열 단계가 다 초록이다', () {
      // 아홉에서 열이 되었다. `Nav2 노드` 가 늘었다 — 노드가 있는 것과
      // `active` 인 것은 다른데, 여태 그것을 확인표에서 볼 수 없었다.
      final r = report();
      expect(r.isReady, isTrue);
      expect(r.checks, hasLength(10));
      expect(r.firstBlocked, isNull);
      expect(r.summary, contains('작업을 낼 수 있습니다'));
    });
  });

  group('모른다와 안 됐다를 가른다', () {
    test('백엔드가 없으면 어댑터는 모른다이지 고장이 아니다', () {
      // 빨간불로 보여 주면 멀쩡한 어댑터를 두고 원인을 찾게 된다.
      final r = report(backendRunning: false, fleetReachable: false);
      expect(find(r, 'Open-RMF 실행').state, ReadinessState.blocked);
      expect(find(r, 'RMF↔Nav2 어댑터').state, ReadinessState.unknown);
      expect(find(r, '로봇이 RMF 에 붙음').state, ReadinessState.unknown);
    });

    test('모르는 단계가 있으면 다 됐다고 하지 않는다', () {
      final r = report(backendRunning: false, fleetReachable: false);
      expect(r.isReady, isFalse);
    });

    test('백엔드는 떴는데 토픽이 없으면 어댑터가 죽은 것이다', () {
      // /fleet_states 를 내는 것은 fleet adapter 하나뿐이다.
      final r = report(fleetReachable: false, attached: const {});
      final adapter = find(r, 'RMF↔Nav2 어댑터');
      expect(adapter.state, ReadinessState.blocked);
      expect(adapter.detail, contains('/fleet_states'));
      // RViz 가 왜 비는지도 같이 짚어 준다.
      expect(adapter.detail, contains('RViz'));
    });

    test('막 띄운 백엔드는 아직 안 온 것이지 죽은 것이 아니다', () {
      // 어댑터는 Gazebo·RMF core 다음에 붙는다. 실측 32초.
      final r = report(
        fleetReachable: false,
        attached: const {},
        backendUptime: const Duration(seconds: 20),
      );
      final adapter = find(r, 'RMF↔Nav2 어댑터');
      expect(adapter.state, ReadinessState.unknown);
      expect(adapter.detail, contains('아직'));
      expect(adapter.detail, isNot(contains('죽었습니다')));
      // 모르는 단계가 있으면 다 됐다고 하지 않는다.
      expect(r.isReady, isFalse);
      // 그리고 빨간불이 아니므로 `여기부터 손대라` 로 짚지도 않는다.
      expect(r.firstBlocked, isNull);
    });

    test('기다려 주는 시간이 지나도 안 오면 그때는 죽은 것이다', () {
      final r = report(
        fleetReachable: false,
        attached: const {},
        backendUptime: adapterStartupGrace + const Duration(seconds: 1),
      );
      expect(find(r, 'RMF↔Nav2 어댑터').state, ReadinessState.blocked);
    });

    test('언제 떴는지 모르면 기다려 주지 않는다', () {
      // 기다려 주는 쪽으로 기울면 죽은 어댑터가 영영 `아직` 으로 남는다.
      final r = report(
        fleetReachable: false,
        attached: const {},
        backendUptime: null,
      );
      expect(find(r, 'RMF↔Nav2 어댑터').state, ReadinessState.blocked);
    });
  });

  group('막힌 단계', () {
    test('이름 있는 Waypoint 가 없으면 막는다', () {
      final r = report(waypoints: const ['', '   ']);
      final check = find(r, '지도와 Waypoint');
      expect(check.state, ReadinessState.blocked);
      // RMF 가 좌표가 아니라 이름을 본다는 것을 알려 준다.
      expect(check.detail, contains('이름'));
    });

    test('설비 로봇만 있으면 관제할 로봇이 없다', () {
      final r = report(robots: const [arm]);
      expect(find(r, '로봇 등록').state, ReadinessState.blocked);
    });

    test('Mock 로봇은 RMF 가 모른다', () {
      // 앱 안에서만 도는 로봇이다. 세면 등록된 줄 알고 기다리게 된다.
      final r = report(robots: const [mockRobot]);
      final check = find(r, '로봇 등록');
      expect(check.state, ReadinessState.blocked);
      expect(check.detail, contains('Mock'));
    });

    test('내보내기를 안 했으면 막는다', () {
      final r = report(exported: false);
      final check = find(r, 'RMF 설정 내보내기');
      expect(check.state, ReadinessState.blocked);
      // ros2 launch 가 파일을 읽는다는 것이 이 단계가 있는 이유다.
      expect(check.detail, contains('파일'));
    });

    test('안 붙은 로봇을 이름으로 짚어 준다', () {
      final r = report(
        robots: const [pinky, pinky2],
        attached: const {'PK_01'},
      );
      final check = find(r, '로봇이 RMF 에 붙음');
      expect(check.state, ReadinessState.blocked);
      expect(check.detail, contains('PK_02'));
      expect(check.detail, isNot(contains('PK_01')));
    });

    test('두 대 다 붙으면 통과한다', () {
      final r = report(
        robots: const [pinky, pinky2],
        attached: const {'PK_01', 'PK_02'},
        nav2Stuck: const {'PK_01': [], 'PK_02': []},
      );
      expect(find(r, '로봇이 RMF 에 붙음').state, ReadinessState.ready);
      expect(r.isReady, isTrue);
    });

    test('설비 로봇은 붙기를 기다리지 않는다', () {
      // 설비는 자리를 안 옮기므로 플릿에 붙을 일이 없다. 세면 영영 안 끝난다.
      final r = report(robots: const [pinky, arm], attached: const {'PK_01'});
      expect(find(r, '로봇이 RMF 에 붙음').state, ReadinessState.ready);
    });
  });

  group('지도 정합', () {
    test('그래프가 지도 밖이면 막는다', () {
      // 어긋나면 RMF 는 `픽업1` 로 보내는데 AMCL 은 로봇이 딴 데 있다고 여긴다.
      final r = report(
        alignment: const Nav2MapAlignment(
          covered: false,
          outsideWaypoints: ['대기5', '픽업2'],
          marginMeters: -.441,
        ),
      );
      final check = find(r, '지도 정합');
      expect(check.state, ReadinessState.blocked);
      expect(check.detail, contains('픽업2'));
      // 어떻게 고치는지까지 적는다.
      expect(check.detail, contains('SLAM'));
    });

    test('아직 못 봤으면 모른다이지 고장이 아니다', () {
      final r = report(alignment: null);
      expect(find(r, '지도 정합').state, ReadinessState.unknown);
      expect(r.isReady, isFalse);
    });

    test('내보내기 전에는 볼 수 없다', () {
      // 디스크에 지도도 그래프도 없다. 어긋났다고 말할 근거가 없다.
      final r = report(exported: false, alignment: null);
      expect(find(r, '지도 정합').state, ReadinessState.unknown);
    });
  });

  group('시뮬레이션 시계', () {
    test('하나면 통과한다', () {
      expect(find(report(), '시뮬레이션 시계').state, ReadinessState.ready);
    });

    test('둘이면 막고 정리하는 법을 알려 준다', () {
      // 이전 실행에서 남은 토픽 다리다. 시각이 앞뒤로 튀어 tf2 가 버퍼를
      // 비우고 AMCL 이 위치추정을 잃는다 — 로봇은 멀쩡한데 가만히 선다.
      final check = find(report(clockPublishers: 2), '시뮬레이션 시계');
      expect(check.state, ReadinessState.blocked);
      expect(check.detail, contains('2 곳'));
      expect(check.detail, contains('parameter_bridge'));
    });

    test('없으면 Gazebo 쪽을 짚는다', () {
      final check = find(report(clockPublishers: 0), '시뮬레이션 시계');
      expect(check.state, ReadinessState.blocked);
      expect(check.detail, contains('Gazebo'));
    });

    test('백엔드가 없으면 모른다', () {
      final r = report(
        backendRunning: false,
        fleetReachable: false,
        clockPublishers: null,
      );
      expect(find(r, '시뮬레이션 시계').state, ReadinessState.unknown);
    });
  });

  group('요약 한 줄', () {
    test('처음 막힌 단계를 짚는다', () {
      // 앞이 막히면 뒤는 대개 따라 막힌다. 여섯 줄을 다 읽으라고 하지 않는다.
      final r = report(
        waypoints: const [],
        exported: false,
        backendRunning: false,
        fleetReachable: false,
      );
      expect(r.firstBlocked!.title, '지도와 Waypoint');
      expect(r.summary, startsWith('지도와 Waypoint'));
    });

    test('무엇을 하면 되는지까지 담는다', () {
      // 이유만 있으면 화면을 보고도 다음 손이 안 나간다.
      final r = report(backendRunning: false, fleetReachable: false);
      expect(r.summary, contains('프로젝트 실행'));
    });
  });

  group('시뮬레이터 없이 돌 때', () {
    // 실물 Pinky 만 쓰는 프로젝트(`SIM_BACKEND=none`)다. 실행 스크립트가
    // `use_sim_time` 을 false 로 두어 모든 노드가 실제 시계를 쓴다 — `/clock` 을
    // 내는 곳이 아예 없다.

    test('시계 칸을 두지 않는다', () {
      // 두면 영영 안 채워지는 칸이 하나 남는다. 실물로 돌린 확인표가 그랬다:
      //   (모름) 시뮬레이션 시계 — 백엔드가 떠야 확인할 수 있습니다
      final r = report(usesSimulator: false, clockPublishers: null);
      expect(
        r.checks.where((check) => check.title == '시뮬레이션 시계'),
        isEmpty,
      );
      // 시계 칸만 빠진다. Nav2 노드 칸은 그대로 있다.
      expect(r.checks, hasLength(9));
    });

    test('시계 없이도 다 됐다고 말할 수 있다', () {
      // 이것이 핵심이다. 칸이 남아 있으면 `isReady` 가 영영 false 라, 다 됐는지를
      // 이 표로 알 수 없다.
      final r = report(usesSimulator: false, clockPublishers: null);
      expect(r.isReady, isTrue);
      expect(r.summary, '작업을 낼 수 있습니다.');
    });

    test('나머지 칸은 그대로 본다', () {
      // 시계만 빠진다. 지도 서버·어댑터·로봇 붙음은 실물에서도 그대로 봐야 한다.
      final r = report(usesSimulator: false, clockPublishers: null);
      expect(find(r, 'Nav2 지도 서버').isReady, isTrue);
      expect(find(r, '로봇이 RMF 에 붙음').isReady, isTrue);
    });

    test('막힌 것은 여전히 막혔다고 한다', () {
      final r = report(
        usesSimulator: false,
        clockPublishers: null,
        backendRunning: false,
        fleetReachable: false,
      );
      expect(r.isReady, isFalse);
      expect(find(r, 'Open-RMF 실행').isBlocked, isTrue);
    });
  });

  group('시뮬레이터로 돌 때는 시계를 계속 본다', () {
    test('두 시계를 잡아낸다', () {
      // 남은 `parameter_bridge` 를 잡는 것이 이 칸의 본래 목적이다. 기본값을
      // true 로 둔 까닭이기도 하다 — 모르는 채로 칸을 없애면 이것을 놓친다.
      final r = report(clockPublishers: 2);
      expect(find(r, '시뮬레이션 시계').isBlocked, isTrue);
      expect(find(r, '시뮬레이션 시계').detail, contains('parameter_bridge'));
    });

    test('안 넘기면 시계를 보는 쪽이 기본이다', () {
      // 대부분의 프로젝트가 시뮬레이터를 쓴다.
      final r = report(clockPublishers: 0);
      expect(find(r, '시뮬레이션 시계').isBlocked, isTrue);
    });
  });

  /// 노드가 있는 것과 `active` 인 것은 다르다. inactive 인 노드는 명령을 안
  /// 받는데 **오류를 내지 않는다** — 노드 목록에는 그대로 보인다.
  ///
  /// 실제로 `controller_server` 가 inactive 인 채로, 작업을 넣으면 어댑터가
  /// `Nav2 가 거절했습니다` 한 줄만 남기고 끝난 일이 있다. 그때 확인표는
  /// `/fleet_states 가 안 나옵니다` 로만 보여서, 어느 노드가 막혔는지는
  /// `ros2 lifecycle get` 을 여덟 번 쳐서 알아내야 했다.
  group('Nav2 노드', () {
    test('다 켜졌으면 한 줄로 둔다', () {
      final check = find(report(), 'Nav2 노드 (PK_01)');
      expect(check.state, ReadinessState.ready);
      // 다 켜져 있을 때 여덟 줄을 늘어놓으면 정작 막힌 칸이 묻힌다.
      expect(check.detail, contains('모두 active'));
    });

    test('막힌 노드 이름을 짚는다', () {
      final check = find(
        report(
          nav2Stuck: const {
            'PK_01': ['controller_server', 'bt_navigator'],
          },
        ),
        'Nav2 노드 (PK_01)',
      );
      expect(check.state, ReadinessState.blocked);
      expect(check.detail, contains('controller_server'));
      expect(check.detail, contains('bt_navigator'));
    });

    /// 겉으로 멀쩡해 보이는 까닭을 적어야 한다. 안 그러면 노드 목록에 다
    /// 나오는 것을 보고 확인표가 틀렸다고 여긴다.
    test('오류가 안 난다는 것을 밝힌다', () {
      final check = find(
        report(nav2Stuck: const {'PK_01': ['planner_server']}),
        'Nav2 노드 (PK_01)',
      );
      expect(check.detail, contains('오류'));
    });

    test('bt_navigator 가 막히면 작업이 거절된다고 적는다', () {
      final check = find(
        report(nav2Stuck: const {'PK_01': ['bt_navigator']}),
        'Nav2 노드 (PK_01)',
      );
      expect(check.detail, contains('navigate_to_pose'));
    });

    /// 모르는 것을 정상으로 보면 안 된다.
    test('아직 안 물어봤으면 모른다고 한다', () {
      final check = find(report(nav2Stuck: const {}), 'Nav2 노드 (PK_01)');
      expect(check.state, ReadinessState.unknown);
    });

    test('백엔드가 없으면 칸을 안 만든다', () {
      final r = report(backendRunning: false);
      expect(
        r.checks.where((check) => check.title.startsWith('Nav2 노드')),
        isEmpty,
      );
    });

    /// 로봇마다 한 줄이다. 한 대만 막혀도 어느 대인지 보여야 한다.
    test('로봇마다 따로 본다', () {
      final r = report(
        robots: const [pinky, pinky2],
        attached: const {'PK_01', 'PK_02'},
        nav2Stuck: const {
          'PK_01': [],
          'PK_02': ['controller_server'],
        },
      );
      expect(find(r, 'Nav2 노드 (PK_01)').state, ReadinessState.ready);
      expect(find(r, 'Nav2 노드 (PK_02)').state, ReadinessState.blocked);
    });
  });

}
