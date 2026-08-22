/// 로봇마다 Nav2 를 띄우는 launch.
///
/// 네임스페이스를 두 번 걸면 `/pinky_01/pinky_01/amcl` 이 되어 파라미터가 하나도
/// 안 붙는다. 오류도 안 나고 조용히 기본값으로 돈다 —
/// `docs/MULTI_ROBOT_NAMESPACES.md` 함정 1 과 같은 사고다.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:rmf_control_ui/rmf_project_config.dart';

void main() {
  const pinky = RmfProjectRobot(
    robotId: 'PK-01',
    displayName: '핑키 1호',
    model: 'PINKY-GZ',
    gzName: 'pinky_01',
    zones: ['ambient'],
    dataSource: RobotDataSource.gazebo,
    chargerWaypoint: '홈1',
    spawnX: 1.7607,
    spawnY: -0.6376,
  );
  const pinkyTwo = RmfProjectRobot(
    robotId: 'PK-02',
    displayName: '핑키 2호',
    model: 'PINKY-GZ',
    gzName: 'pinky_02',
    zones: ['ambient'],
    dataSource: RobotDataSource.gazebo,
    chargerWaypoint: '홈2',
    spawnX: 0.5,
    spawnY: -1.5,
  );
  const omx = RmfProjectRobot(
    robotId: 'OMX-01',
    displayName: '매니퓰레이터 1호',
    model: 'open_manipulator_x',
    kind: RmfRobotKind.workcell,
    gzName: 'omx_01',
    zones: [],
    dataSource: RobotDataSource.gazebo,
    chargerWaypoint: 'OMX1',
  );
  const mockPinky = RmfProjectRobot(
    robotId: 'MK-01',
    displayName: '연습용',
    model: 'PINKY-GZ',
    gzName: 'mock_01',
    zones: ['ambient'],
    chargerWaypoint: '홈3',
  );

  group('로봇 한 대의 Nav2', () {
    final xml = buildRobotNav2LaunchXml(pinky, 'gwanghee');

    test('네임스페이스를 한 번만 건다', () {
      // 두 번 걸면 /pinky_01/pinky_01/amcl 이 되어 파라미터가 안 붙는다.
      expect(RegExp('push-ros-namespace').allMatches(xml).length, 1);
      expect(xml, contains('<push-ros-namespace namespace="pinky_01"/>'));
      // 노드에 이름을 또 걸면 두 겹이 된다.
      expect(xml, isNot(contains('name="pinky_01/amcl"')));
      expect(xml, isNot(contains('ns="pinky_01"')));
    });

    test('AMCL 과 Nav2 서버들을 띄운다', () {
      for (final node in [
        'nav2_amcl',
        'nav2_controller',
        'nav2_planner',
        'nav2_behaviors',
        'nav2_bt_navigator',
        'nav2_smoother',
        'nav2_waypoint_follower',
        'nav2_velocity_smoother',
      ]) {
        expect(xml, contains('pkg="$node"'), reason: '$node 가 없습니다');
      }
    });

    test('map_server 는 없다 — 월드에 하나뿐이다', () {
      expect(xml, isNot(contains('nav2_map_server')));
      expect(xml, contains('map_server 는 여기 없다'));
    });

    test('모든 노드가 이 로봇의 파라미터를 읽는다', () {
      final nodes = RegExp('<node pkg=').allMatches(xml).length;
      final params = RegExp(
        r'<param from="\$\(dirname\)/nav2_params.yaml"/>',
      ).allMatches(xml).length;
      // lifecycle_manager 만 파라미터 파일을 안 읽는다.
      expect(params, nodes - 1);
    });

    test('lifecycle_manager 가 띄운 노드를 전부 관리한다', () {
      final managed = RegExp(
        r'value="\[amcl, ([^\]]+)\]"',
      ).firstMatch(xml)!.group(1)!.split(', ');
      for (final node in managed) {
        expect(xml, contains('name="$node"'), reason: '$node 를 안 띄웁니다');
      }
      expect(managed, contains('controller_server'));
      expect(managed, contains('bt_navigator'));
    });

    test('velocity smoother의 최종 출력만 실제 cmd_vel로 보낸다', () {
      expect(
        RegExp(r'<remap from="cmd_vel" to="cmd_vel_nav"/>')
            .allMatches(xml)
            .length,
        3,
      );
      expect(
        xml,
        contains('<remap from="cmd_vel_smoothed" to="cmd_vel"/>'),
      );
    });

    test('Gazebo 다리가 smoother 가 실제로 쓰는 이름을 구독한다', () {
      // 이 둘이 어긋난 적이 있다. launch 는 smoother 출력을 cmd_vel 로
      // 리맵했는데 다리는 Nav2 기본 이름인 cmd_vel_smoothed 를 구독해서,
      // 속도 명령이 20Hz 로 발행되는데도 Gazebo 에 한 번도 닿지 않았다.
      // 로봇은 제자리에 서 있고 Nav2 는 Failed to make progress 만 반복했다.
      final smootherOutput = RegExp(
        r'<remap from="cmd_vel_smoothed" to="([^"]+)"/>',
      ).firstMatch(xml)!.group(1)!;
      final bridge = buildProjectGzBridgeYaml(
        mapName: 'gwanghee',
        robots: [pinky],
      );
      final rosToGz = RegExp(
        r'- ros_topic_name: "([^"]+)"\n'
        r'  gz_topic_name: "[^"]+"\n'
        r'  ros_type_name: "geometry_msgs/msg/Twist"',
      ).allMatches(bridge).map((m) => m.group(1)).toList();
      expect(rosToGz, ['/${pinky.gzName}/$smootherOutput']);
    });

    test('sim 시간을 쓴다 — Gazebo 와 시계를 맞춰야 한다', () {
      expect(xml, contains('name="use_sim_time"'));
    });

    test('lifecycle_manager 도 프로젝트 시계를 쓴다', () {
      // Nav2 노드와 lifecycle manager가 다른 시계를 쓰면 전이와 TF의 시간이
      // 어긋난다. 프로젝트가 Gazebo면 sim 시계, 실물이면 벽시계를 쓴다.
      final manager = xml.substring(xml.indexOf('nav2_lifecycle_manager'));
      expect(
        manager,
        contains('name="use_sim_time" value="\$(var use_sim_time)"'),
      );
    });

    /// 라즈베리파이에서 실제로 겪은 일이다. `controller_server` 는 costmap 을
    /// 만드느라 기동이 무거워 `get_state` 응답이 늦었고, 관리자는 그것을 실패로
    /// 보고 **뒤의 노드를 아예 시도하지 않았다**:
    ///
    ///     [lifecycle_manager]: Failed to change state for node:
    ///       controller_server. Exception: controller_server/get_state
    ///       service client: async_send_request failed.
    ///     [lifecycle_manager]: Failed to bring up all requested nodes.
    ///       Aborting bringup.
    ///
    /// 남은 상태는 `amcl` 만 active 고 나머지는 unconfigured 였다. 로봇 위치는
    /// 지도에 뜨는데 주행만 안 되니, 원인을 라이다와 AMCL 에서 찾게 된다 —
    /// 정작 그 둘은 멀쩡했다.
    test('느린 기계에서도 기다려 준다', () {
      final manager = xml.substring(xml.indexOf('nav2_lifecycle_manager'));
      expect(manager, contains('name="service_timeout"'));
      expect(manager, contains('name="bond_timeout"'));
    });

    test('기다리는 시간은 벤더 기본값보다 넉넉하다', () {
      final manager = xml.substring(xml.indexOf('nav2_lifecycle_manager'));
      final service = double.parse(
        RegExp(
          r'name="service_timeout" value="([0-9.]+)"',
        ).firstMatch(manager)!.group(1)!,
      );
      final bond = double.parse(
        RegExp(
          r'name="bond_timeout" value="([0-9.]+)"',
        ).firstMatch(manager)!.group(1)!,
      );
      // 벤더 bond_timeout 은 4초다. 기동 직후 바쁜 노드가 heartbeat 를 늦게
      // 보내는 것만으로 죽은 것으로 보면 안 된다.
      expect(bond, greaterThan(4));
      expect(service, greaterThanOrEqualTo(20));
    });

    /// ROS 는 이 둘을 double 로 선언한다. `value="30"` 으로 나가면 정수로 읽혀
    /// 형식이 안 맞고, 그러면 파라미터가 **조용히 무시된다.**
    test('소수점을 붙여 내보낸다 — 정수로 나가면 무시된다', () {
      final manager = xml.substring(xml.indexOf('nav2_lifecycle_manager'));
      expect(manager, contains(RegExp(r'name="service_timeout" value="\d+\.\d')));
      expect(manager, contains(RegExp(r'name="bond_timeout" value="\d+\.\d')));
    });

    test('파일 자리를 arg 로 돌려쓰지 않는다', () {
      // 같은 이름의 <arg> 를 여러 include 가 선언하면 launch 안에서 범위가
      // 겹쳐 먼저 읽은 값이 나머지에 쓰인다. 실제로 pinky_02 가 pinky_01 의
      // URDF 로 올라갔다.
      expect(xml, isNot(contains('robot_dir')));
      expect(xml, contains(r'$(dirname)/nav2_params.yaml'));
    });
  });

  group('프로젝트 전체의 Nav2', () {
    final xml = buildProjectNav2LaunchXml(
      mapName: 'gwanghee',
      robots: const [pinky, pinkyTwo, omx, mockPinky],
    );

    test('건물 지도는 하나만 띄운다', () {
      expect(RegExp('nav2_map_server').allMatches(xml).length, 1);
      expect(xml, contains('value="\$(var map_dir)/nav2_map/gwanghee.yaml"'));
    });

    /// 지도 파일을 읽는 데 5초가 넘어 `get_state` 응답이 늦는 일이 있었다.
    /// 그러면 map_server 가 inactive 로 남고, 증상은 세 단계 떨어진 곳에 뜬다 —
    /// 화면에는 "rmf-nav2 연결 실패" 만 보인다.
    test('map_server 도 느린 기계를 기다려 준다', () {
      final manager = xml.substring(xml.indexOf('lifecycle_manager_map'));
      expect(manager, contains('name="service_timeout"'));
      expect(manager, contains('name="bond_timeout"'));
    });

    test('이동 로봇마다 제 Nav2 를 붙인다', () {
      expect(xml, contains('robots/PK-01/nav2.launch.xml'));
      expect(xml, contains('robots/PK-02/nav2.launch.xml'));
    });

    test('설치 로봇은 Nav2 를 안 쓴다 — 한자리에 붙어 있다', () {
      expect(xml, isNot(contains('OMX-01')));
    });

    test('Mock 로봇도 안 쓴다 — 실제로는 없는 로봇이다', () {
      expect(xml, isNot(contains('MK-01')));
    });

    test('띄울 로봇이 없으면 그 사실을 적는다', () {
      final empty = buildProjectNav2LaunchXml(
        mapName: 'gwanghee',
        robots: const [omx, mockPinky],
      );
      expect(empty, contains('이동 로봇이 없다'));
      expect(empty, contains('nav2_map_server'));
    });

    test('RMF 와 Nav2 를 잇는 어댑터를 함께 띄운다', () {
      // 이것이 없으면 RMF 가 배차해도 로봇이 안 움직인다.
      // rmf_demos_fleet_adapter 는 slotcar 전용이라 우리 핑키에게는 상대가 없다.
      final withFleet = buildProjectNav2LaunchXml(
        mapName: 'gwanghee',
        robots: const [pinky],
        fleetName: 'gwanghee_pinky',
      );
      expect(withFleet, contains('gwanghee_nav2_adapter.py'));
      expect(withFleet, contains('gwanghee_pinky_config.yaml'));
      expect(withFleet, contains('nav_graphs/0.yaml'));
      // ROS 패키지에 든 노드가 아니라 우리가 만든 스크립트다.
      expect(withFleet, contains('<executable'));
      // 플릿 이름을 모르면 띄우지 않는다. 설정 파일 자리를 알 수 없다.
      expect(
        buildProjectNav2LaunchXml(mapName: 'gwanghee', robots: const [pinky]),
        isNot(contains('nav2_adapter')),
      );
    });

    test('손대지 못한 것을 파일 맨 위에 적는다', () {
      // 이 launch 가 안 뜰 때 사람이 제일 먼저 여는 파일이다.
      final warned = buildProjectNav2LaunchXml(
        mapName: 'gwanghee',
        robots: const [pinky],
        warnings: const ['벤더 파라미터를 찾지 못했습니다.'],
      );
      expect(warned, contains('확인이 필요한 것'));
      expect(warned, contains('· 벤더 파라미터를 찾지 못했습니다.'));
      // 주석 안에 있어야 launch 가 읽을 수 있다.
      expect(
        warned.indexOf('벤더 파라미터를 찾지 못했습니다.'),
        lessThan(warned.indexOf('-->')),
      );
    });
  });

  /// 실물 로봇도 Nav2 가 몰아야 한다.
  ///
  /// 예전에는 이 자리가 `runsInGazebo` 여서, 로봇의 출처를 `실제 로봇` 으로
  /// 바꾸는 순간 Nav2 도 어댑터도 통째로 안 만들어졌다. **그런데 플릿 설정에는
  /// 그대로 들어갔다.** RMF 는 로봇을 아는데 그 로봇을 모는 것이 하나도 없고,
  /// 오류는 한 줄도 안 났다 — 2026-08-17 에 실제로 그랬다. 백엔드는 9개 중
  /// 7개가 떴고, 빠진 둘이 로봇을 모는 부분 전부였다.
  group('실물 이동 로봇', () {
    const realPinky = RmfProjectRobot(
      robotId: 'pinky_01',
      displayName: 'PK-01',
      model: 'PINKY-GZ',
      gzName: 'pinky_01',
      zones: ['ambient'],
      dataSource: RobotDataSource.real,
      chargerWaypoint: '충전2',
      spawnX: 1.613,
      spawnY: -1.088,
    );

    test('Nav2 를 붙인다 — 아래가 실물이든 Gazebo 든 위쪽은 같다', () {
      final xml = buildProjectNav2LaunchXml(
        mapName: 'gwanghee',
        robots: const [realPinky],
        fleetName: 'gwanghee_pinky',
      );
      expect(xml, contains('robots/pinky_01/nav2.launch.xml'));
      expect(xml, isNot(contains('이동 로봇이 없다')));
    });

    test('어댑터 매핑에 들어간다', () {
      // 여기 없으면 어댑터가 `네임스페이스를 모릅니다. 건너뜁니다` 만 남기고
      // 그 로봇을 통째로 지나친다.
      final script = buildNav2FleetAdapterScript(
        mapName: 'gwanghee',
        fleetName: 'gwanghee_pinky',
        robots: const [realPinky],
      );
      expect(script, contains("'pinky_01': 'pinky_01',"));
    });

    test('어댑터·워크셀·센서릴레이가 함께 살아난다', () {
      // 셋이 한 `if` 안에 있다. 이동 로봇이 하나도 안 잡히면 픽업 자리에
      // 답하는 워크셀 노드까지 같이 사라져, 작업이 그 자리에서 영원히 멈춘다.
      final xml = buildProjectNav2LaunchXml(
        mapName: 'gwanghee',
        robots: const [realPinky, omx],
        fleetName: 'gwanghee_pinky',
      );
      expect(xml, contains('gwanghee_nav2_adapter.py'));
      expect(xml, contains('gwanghee_workcell.py'));
      expect(xml, contains('gwanghee_sensor_relay.py'));
    });

    test('실행 전 점검이 이 로봇을 본다', () {
      final script = buildProjectRunScript(
        mapName: 'gwanghee',
        mapDirectory: '/maps/gwanghee',
        robots: const [realPinky],
      );
      expect(script, contains('EXPECTED_FLEET_ROBOTS="pinky_01"'));
    });
  });

  /// 실물이 섞이면 **벽시계로 통일한다.**
  ///
  /// 실물의 odom·scan·tf 는 벽시계로 찍혀 온다. 그 위의 AMCL 과 어댑터가 sim
  /// 시계를 보면 TF lookup 이 전부 어긋나는데 오류는 안 나고 로봇만 안 움직인다.
  group('시계', () {
    const realPinky = RmfProjectRobot(
      robotId: 'pinky_01',
      displayName: 'PK-01',
      model: 'PINKY-GZ',
      gzName: 'pinky_01',
      zones: ['ambient'],
      dataSource: RobotDataSource.real,
      chargerWaypoint: '충전2',
    );

    test('실물 이동 로봇이 있으면 벽시계다', () {
      expect(projectUsesSimTime(const [realPinky]), isFalse);
      // Gazebo 설비가 함께 있어도 마찬가지다. 시뮬레이터는 제 안에서만
      // sim 시계를 쓰고, 워크셀 노드는 애초에 벽시계로 돈다.
      expect(projectUsesSimTime(const [realPinky, omx]), isFalse);
    });

    test('전부 Gazebo 면 예전 그대로 sim 시계다', () {
      expect(projectUsesSimTime(const [pinky, omx]), isTrue);
      expect(projectUsesSimTime(const [mockPinky]), isTrue);
    });

    test('프로젝트 Nav2 launch 가 그 값을 기본으로 쓴다', () {
      expect(
        buildProjectNav2LaunchXml(
          mapName: 'gwanghee',
          robots: const [realPinky],
        ),
        contains('<arg name="use_sim_time" default="false"/>'),
      );
      expect(
        buildProjectNav2LaunchXml(mapName: 'gwanghee', robots: const [pinky]),
        contains('<arg name="use_sim_time" default="true"/>'),
      );
    });

    test('어댑터의 -s 가 실물에서는 빠진다', () {
      // 예전에는 명령줄에 박혀 있어 끌 방법이 없었다.
      final real = buildProjectNav2LaunchXml(
        mapName: 'gwanghee',
        robots: const [realPinky],
        fleetName: 'gwanghee_pinky',
      );
      final adapter = real.substring(real.indexOf('nav2_adapter.py'));
      expect(
        adapter.substring(0, adapter.indexOf('/>')),
        isNot(contains(' -s')),
      );

      final sim = buildProjectNav2LaunchXml(
        mapName: 'gwanghee',
        robots: const [pinky],
        fleetName: 'gwanghee_pinky',
      );
      final simAdapter = sim.substring(sim.indexOf('nav2_adapter.py'));
      expect(
        simAdapter.substring(0, simAdapter.indexOf('/>')),
        contains(' -s'),
      );
    });

    test('RMF core 도 같은 시계로 뜬다', () {
      // 어댑터와 core 가 다른 시계를 보면 예약 시각이 서로 안 맞는다.
      String core(List<RmfProjectRobot> robots) => buildProjectLaunchXml(
        mapName: 'gwanghee',
        fleetName: 'gwanghee_pinky',
        mapDirectory: '/maps/gwanghee',
        buildingYamlName: 'gwanghee.building.yaml',
        robots: robots,
        useSimTime: projectUsesSimTime(robots),
      );
      expect(
        core(const [realPinky]),
        contains('<arg name="use_sim_time" default="false"/>'),
      );
      expect(
        core(const [pinky]),
        contains('<arg name="use_sim_time" default="true"/>'),
      );
    });

    test('로봇 한 대 파일은 제 출처를 기본으로 쓴다', () {
      // 이 파일만 따로 돌려 볼 때 쓰이는 값이다.
      expect(
        buildRobotNav2LaunchXml(realPinky, 'gwanghee'),
        contains('<arg name="use_sim_time" default="false"/>'),
      );
      expect(
        buildRobotNav2LaunchXml(pinky, 'gwanghee'),
        contains('<arg name="use_sim_time" default="true"/>'),
      );
    });
  });
}
