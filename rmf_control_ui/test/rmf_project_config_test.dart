import 'package:flutter_test/flutter_test.dart';
import 'package:rmf_control_ui/rmf_project_config.dart';

/// 프로젝트마다 새로 만들어지는 Open-RMF 설정 파일의 내용을 확인한다.
///
/// 지금까지는 전역 fleet.yaml 하나와 office 데모의 tinyRobot_config.yaml 을
/// 빌려 썼다. 맵이 바뀌면 spawn 좌표도 charger 이름도 어긋난다.
void main() {
  const robots = [
    RmfProjectRobot(
      robotId: 'PK-01',
      displayName: '핑키 1호',
      model: 'PINKY-GZ-C',
      gzName: 'pinky_01',
      zones: ['ambient', 'chilled', 'frozen'],
      chargerWaypoint: '충전1',
      spawnX: 12.5,
      spawnY: 3.25,
    ),
    RmfProjectRobot(
      robotId: 'PK-02',
      displayName: '핑키 2호',
      model: 'PINKY-GZ',
      gzName: 'pinky_02',
      zones: ['ambient'],
      chargerWaypoint: '충전2',
      spawnX: 20,
      spawnY: 8.5,
      spawnHeading: 3.14159,
    ),
  ];

  group('fleet adapter 설정', () {
    test('로봇마다 charger Waypoint 이름이 들어간다', () {
      final yaml = buildFleetAdapterYaml(
        fleet: const RmfFleetSettings(fleetName: 'gwanghee_pinky'),
        robots: robots,
        mapName: 'gwanghee',
      );
      expect(yaml, contains('name: "gwanghee_pinky"'));
      expect(yaml, contains('    PK-01:'));
      expect(yaml, contains('        charger: "충전1"'));
      expect(yaml, contains('    PK-02:'));
      expect(yaml, contains('        charger: "충전2"'));
    });

    test('프로필 반경을 맵의 로봇 안전 기준에서 가져온다', () {
      // 폭 0.2m · 위치 오차 0.05m 인 작은 로봇.
      // footprint = 0.1, vicinity = 0.15 이어야 한다. 사용자가 이미 넣은 값을
      // 다시 묻지 않는 것이 핵심이다 — 두 곳에 적으면 어긋난다.
      final fleet = const RmfFleetSettings().withRobotSafety(
        widthMeters: .2,
        localizationMarginMeters: .05,
      );
      final yaml = buildFleetAdapterYaml(
        fleet: fleet,
        robots: robots,
        mapName: 'gwanghee',
      );
      expect(yaml, contains('footprint: 0.100'));
      expect(yaml, contains('vicinity: 0.150'));
    });

    test('로봇이 없어도 유효한 YAML 을 만든다', () {
      final yaml = buildFleetAdapterYaml(
        fleet: const RmfFleetSettings(),
        robots: const [],
        mapName: 'gwanghee',
      );
      expect(yaml, contains('  robots:'));
      expect(yaml, contains('{}'), reason: '빈 매핑이라도 있어야 파싱된다');
    });

    test('fleet_manager 접속 정보가 들어간다', () {
      final yaml = buildFleetAdapterYaml(
        fleet: const RmfFleetSettings(),
        robots: robots,
        mapName: 'gwanghee',
      );
      expect(yaml, contains('fleet_manager:'));
      expect(yaml, contains('  ip: "127.0.0.1"'));
      expect(yaml, contains('  port: 22011'));
    });
  });

  group('Gazebo spawn 목록', () {
    test('맵 Waypoint 좌표가 spawn 위치로 들어간다', () {
      final yaml = buildFleetSimYaml(robots: robots, mapName: 'gwanghee');
      expect(yaml, contains('  - id: PK-01'));
      expect(yaml, contains('    gz_name: pinky_01'));
      expect(yaml, contains('    zones: [ambient, chilled, frozen]'));
      expect(yaml, contains('    spawn_x: 12.500'));
      expect(yaml, contains('    spawn_y: 3.250'));
      expect(yaml, contains('    spawn_heading: 3.142'));
    });

    test('로봇이 없으면 빈 목록으로 둔다', () {
      final yaml = buildFleetSimYaml(robots: const [], mapName: 'gwanghee');
      expect(yaml, contains('robots:'));
      expect(yaml, contains('[]'));
    });
  });

  group('설정 저장·복원', () {
    test('플릿 설정이 JSON 을 오가도 값이 유지된다', () {
      final original = const RmfFleetSettings(
        fleetName: 'gwanghee_pinky',
      ).withRobotSafety(widthMeters: .2, localizationMarginMeters: .05);
      final restored = RmfFleetSettings.fromJson(original.toJson());
      expect(restored.fleetName, 'gwanghee_pinky');
      expect(restored.footprintRadius, .1);
      expect(restored.vicinityRadius, closeTo(.15, .0001));
      expect(restored.fleetManagerPort, 22011);
    });

    test('로봇이 JSON 을 오가도 값이 유지된다', () {
      final restored = RmfProjectRobot.fromJson(robots.first.toJson());
      expect(restored.robotId, 'PK-01');
      expect(restored.gzName, 'pinky_01');
      expect(restored.zones, ['ambient', 'chilled', 'frozen']);
      expect(restored.chargerWaypoint, '충전1');
      expect(restored.spawnX, 12.5);
    });

    test('빠진 항목은 기본값으로 채운다', () {
      final restored = RmfFleetSettings.fromJson(const {});
      expect(restored.fleetName, 'pinky');
      expect(restored.linearVelocity, .5);
    });
  });

  group('Gazebo bringup', () {
    test('네임스페이스를 두 번 걸지 않는다', () {
      final xml = buildProjectBringupXml(
        mapName: 'gwanghee',
        robots: robots,
        mapDirectory: '/maps/gwanghee',
      );
      // push-ros-namespace 와 launch 인자를 함께 쓰면 노드가
      // /pinky_01/pinky_01/... 에 뜬다. 그러면 create 가 기다리는
      // robot_description 이 영영 오지 않아 로봇이 스폰되지 않는다.
      expect(xml, isNot(contains('push-ros-namespace')));
      expect(xml, contains('<arg name="namespace" value="pinky_01"/>'));
    });

    test('create 가 그 로봇의 robot_description 을 절대 이름으로 가리킨다', () {
      final xml = buildProjectBringupXml(
        mapName: 'gwanghee',
        robots: robots,
        mapDirectory: '/maps/gwanghee',
      );
      expect(xml, contains('-topic /pinky_01/robot_description'));
      expect(xml, contains('-topic /pinky_02/robot_description'));
      // 상대 이름이면 루트의 /robot_description 을 기다린다.
      expect(xml, isNot(contains('-topic robot_description')));
    });

    test('Gazebo 플러그인이 켜지도록 is_sim 을 넘긴다', () {
      // is_sim 이 빠지면 diff drive 도 LiDAR 도 없는 껍데기가 스폰된다.
      // 보이기는 하는데 cmd_vel 을 줘도 움직이지 않는다.
      final xml = buildProjectBringupXml(
        mapName: 'gwanghee',
        robots: robots,
        mapDirectory: '/maps/gwanghee',
      );
      expect(xml, contains('<arg name="is_sim" value="True"/>'));
    });

    test('다리는 이 프로젝트 설정으로 한 번만 띄운다', () {
      final xml = buildProjectBringupXml(
        mapName: 'gwanghee',
        robots: robots,
        mapDirectory: '/maps/gwanghee',
      );
      expect(
        'parameter_bridge'.allMatches(xml).length,
        1,
        reason: '로봇마다 띄우면 같은 토픽을 여러 번 다리 놓는다',
      );
      expect(
        xml,
        contains(
          r'<arg name="bridge_params" default="$(var map_dir)'
          '/gwanghee_gz_bridge.yaml"/>',
        ),
      );
      expect(xml, contains('<arg name="map_dir" default="/maps/gwanghee"/>'));
      // 벤더 설정은 이름이 상대 경로라 로봇이 여러 대면 겹친다.
      expect(xml, isNot(contains('pinky_gz_sim)/params/pinky_bridge.yaml')));
    });

    test('로봇이 없어도 유효한 launch 를 만든다', () {
      final xml = buildProjectBringupXml(
        mapName: 'gwanghee',
        robots: const [],
        mapDirectory: '/maps/gwanghee',
      );
      expect(xml, contains('</launch>'));
      expect(xml, contains('등록된 로봇이 없다'));
    });
  });

  group('Gazebo 다리 설정', () {
    test('로봇마다 토픽 이름이 갈린다', () {
      final yaml = buildProjectGzBridgeYaml(
        mapName: 'gwanghee',
        robots: robots,
      );
      for (final topic in ['odom', 'cmd_vel', 'scan', 'joint_states']) {
        expect(yaml, contains('ros_topic_name: "/pinky_01/$topic"'));
        expect(yaml, contains('ros_topic_name: "/pinky_02/$topic"'));
      }
      // 상대 이름이 하나라도 남으면 두 로봇이 같은 토픽을 쓴다.
      expect(yaml, isNot(contains('ros_topic_name: "odom"')));
      expect(yaml, isNot(contains('ros_topic_name: "cmd_vel"')));
    });

    test('양쪽 이름이 같아야 다리가 이어진다', () {
      final yaml = buildProjectGzBridgeYaml(
        mapName: 'gwanghee',
        robots: robots,
      );
      final ros = RegExp(r'ros_topic_name: "([^"]+)"')
          .allMatches(yaml)
          .map((m) => m.group(1))
          .toList();
      final gz = RegExp(r'gz_topic_name: "([^"]+)"')
          .allMatches(yaml)
          .map((m) => m.group(1))
          .toList();
      expect(ros, isNotEmpty);
      expect(gz, ros);
    });

    test('clock 과 tf 는 로봇별로 나누지 않는다', () {
      final yaml = buildProjectGzBridgeYaml(
        mapName: 'gwanghee',
        robots: robots,
      );
      // 월드에 하나뿐인 것을 로봇 수만큼 다리 놓으면 시간이 중복 발행된다.
      expect('ros_topic_name: "/clock"'.allMatches(yaml).length, 1);
      expect('ros_topic_name: "/tf"'.allMatches(yaml).length, 1);
    });

    test('cmd_vel 만 ROS 에서 Gazebo 로 간다', () {
      final yaml = buildProjectGzBridgeYaml(
        mapName: 'gwanghee',
        robots: robots,
      );
      final lines = yaml.split('\n');
      for (var i = 0; i < lines.length; i++) {
        if (!lines[i].contains('direction: ROS_TO_GZ')) continue;
        expect(lines[i - 4], contains('cmd_vel'));
      }
      expect('ROS_TO_GZ'.allMatches(yaml).length, robots.length);
    });
  });

  group('설치 로봇', () {
    const workcell = RmfProjectRobot(
      robotId: 'OMX-01',
      displayName: '매니퓰레이터 1호',
      model: 'open_manipulator_x',
      kind: RmfRobotKind.workcell,
      gzName: 'omx_01',
      zones: [],
      chargerWaypoint: 'OMX1',
      spawnX: 5,
      spawnY: 2,
    );
    const mixed = [...robots, workcell];

    test('플릿에 넣지 않는다', () {
      final yaml = buildFleetAdapterYaml(
        fleet: const RmfFleetSettings(),
        robots: mixed,
        mapName: 'gwanghee',
      );
      // 넣으면 fleet adapter 가 배차 대상으로 보고 갈 수 없는 곳으로 보낸다.
      expect(yaml, contains('    PK-01:'));
      expect(yaml, contains('    PK-02:'));
      expect(yaml, isNot(contains('    OMX-01:')));
      // 그래도 어떤 설비가 있는지는 주석으로 남긴다.
      expect(yaml, contains('# 설치 로봇은 플릿에 넣지 않는다'));
      expect(yaml, contains('#   OMX-01 · 매니퓰레이터 1호'));
    });

    test('이동 로봇이 하나도 없으면 빈 플릿이 된다', () {
      final yaml = buildFleetAdapterYaml(
        fleet: const RmfFleetSettings(),
        robots: const [workcell],
        mapName: 'gwanghee',
      );
      expect(yaml, contains('{} # 등록된 이동 로봇이 없다.'));
    });

    test('bringup 은 open_manipulator 쪽 설명을 쓴다', () {
      final xml = buildProjectBringupXml(
        mapName: 'gwanghee',
        robots: mixed,
        mapDirectory: '/maps/gwanghee',
      );
      // pinky_description 의 xacro 로는 팔이 나오지 않는다.
      expect(
        xml,
        contains(
          r'$(find-pkg-share open_manipulator_description)'
          '/urdf/open_manipulator_x/open_manipulator_x.urdf.xacro',
        ),
      );
      expect(xml, contains('args="-name omx_01 -topic robot_description'));
      // 팔은 바퀴가 아니라 컨트롤러가 움직인다.
      expect(xml, contains('args="arm_controller"'));
      expect(xml, contains('args="gripper_controller"'));
      expect(xml, contains('args="joint_state_broadcaster"'));
      // 이동 로봇 쪽은 그대로다.
      expect(xml, contains('-topic /pinky_01/robot_description'));
    });

    test('그리퍼가 없는 모델에는 그리퍼 컨트롤러를 올리지 않는다', () {
      // omy_3m 에는 그리퍼가 없다. 없는 컨트롤러를 올리면 spawner 가 기다리다
      // 실패하고, 팔까지 함께 안 움직이는 것처럼 보인다.
      final xml = buildProjectBringupXml(
        mapName: 'gwanghee',
        robots: const [
          RmfProjectRobot(
            robotId: 'OMY-01',
            displayName: '팔 1호',
            model: 'omy_3m',
            kind: RmfRobotKind.workcell,
            gzName: 'omy_01',
            zones: [],
            chargerWaypoint: 'OMX1',
          ),
        ],
        mapDirectory: '/maps/gwanghee',
      );
      expect(xml, contains('args="arm_controller"'));
      expect(xml, contains('args="joint_state_broadcaster"'));
      expect(xml, isNot(contains('args="gripper_controller"')));
    });

    test('고를 수 있는 모델은 모두 컨트롤러가 정의되어 있다', () {
      // 고를 수 있는데 띄우면 죽는 항목은 없느니만 못하다.
      for (final model in openManipulatorModels) {
        expect(
          openManipulatorControllers[model],
          isNotEmpty,
          reason: '$model 의 컨트롤러가 비어 있다',
        );
      }
    });

    test('메시를 찾도록 두 설명 패키지를 모두 경로에 넣는다', () {
      final xml = buildProjectBringupXml(
        mapName: 'gwanghee',
        robots: mixed,
        mapDirectory: '/maps/gwanghee',
      );
      expect(xml, contains(r'$(find-pkg-share pinky_description)/../'));
      expect(
        xml,
        contains(r'$(find-pkg-share open_manipulator_description)/../'),
      );
    });

    test('다리는 관절 상태만 잇는다', () {
      final yaml = buildProjectGzBridgeYaml(mapName: 'gwanghee', robots: mixed);
      expect(yaml, contains('ros_topic_name: "/omx_01/joint_states"'));
      // 바퀴도 LiDAR 도 없다. 있지도 않은 토픽에 다리를 놓으면 조용히 놀고 있다.
      expect(yaml, isNot(contains('/omx_01/odom')));
      expect(yaml, isNot(contains('/omx_01/cmd_vel')));
      expect(yaml, isNot(contains('/omx_01/scan')));
      // 이동 로봇은 그대로 다 잇는다.
      expect(yaml, contains('ros_topic_name: "/pinky_01/odom"'));
    });

    test('종류가 JSON 을 오가도 유지된다', () {
      final restored = RmfProjectRobot.fromJson(workcell.toJson());
      expect(restored.kind, RmfRobotKind.workcell);
      expect(restored.isMobile, isFalse);
      expect(restored.chargerWaypoint, 'OMX1');
    });

    test('종류가 없는 옛 기록은 이동 로봇으로 읽는다', () {
      // v8 이전에 저장된 로봇에는 kind 가 없다. 전부 이동 로봇이었다.
      final restored = RmfProjectRobot.fromJson(const {
        'robotId': 'PK-09',
        'model': 'PINKY-GZ',
        'gzName': 'pinky_09',
      });
      expect(restored.kind, RmfRobotKind.mobile);
    });
  });

  group('프로젝트 launch', () {
    test('경로가 전부 이 프로젝트 것으로 박힌다', () {
      final xml = buildProjectLaunchXml(
        mapName: 'gwanghee',
        fleetName: 'gwanghee_pinky',
        mapDirectory: '/home/gyi/robosapiens/rmf_maps/gwanghee',
        buildingYamlName: 'gwanghee.building.yaml',
      );
      // 맵마다 building.yaml 도 nav graph 도 플릿 설정도 다르다. 하나라도
      // 데모 것을 가리키면 지난번처럼 tinyRobot 설정으로 돌아간다.
      expect(
        xml,
        contains(
          '<arg name="map_dir" default='
          '"/home/gyi/robosapiens/rmf_maps/gwanghee"/>',
        ),
      );
      expect(
        xml,
        contains(
          r'<arg name="config_file" value="$(var map_dir)'
          '/gwanghee.building.yaml"/>',
        ),
      );
      expect(
        xml,
        contains(
          r'<arg name="config_file" value="$(var map_dir)'
          '/gwanghee_pinky_config.yaml"/>',
        ),
      );
      expect(
        xml,
        contains(
          r'<arg name="nav_graph_file" value="$(var map_dir)'
          '/nav_graphs/0.yaml"/>',
        ),
      );
      expect(xml, isNot(contains('tinyRobot')));
      expect(xml, isNot(contains('office')));
    });

    test('RMF core 와 fleet adapter 를 함께 띄운다', () {
      final xml = buildProjectLaunchXml(
        mapName: 'gwanghee',
        fleetName: 'gwanghee_pinky',
        mapDirectory: '/maps/gwanghee',
        buildingYamlName: 'gwanghee.building.yaml',
      );
      // core 가 먼저 떠야 fleet adapter 가 붙는다. 지난 실패가 그것이었다.
      expect(xml, contains('rmf_demos)/common.launch.xml'));
      expect(xml, contains('rmf_demos_fleet_adapter'));
      expect(
        xml.indexOf('common.launch.xml'),
        lessThan(xml.indexOf('rmf_demos_fleet_adapter')),
      );
    });

    test('rmf-web 주소를 넘긴다', () {
      final xml = buildProjectLaunchXml(
        mapName: 'gwanghee',
        fleetName: 'f',
        mapDirectory: '/maps/gwanghee',
        buildingYamlName: 'b.yaml',
      );
      expect(xml, contains('ws://127.0.0.1:8000/_internal'));
    });
  });
}
