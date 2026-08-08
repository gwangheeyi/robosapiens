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
      dataSource: RobotDataSource.gazebo,
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
      dataSource: RobotDataSource.gazebo,
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
      final xml = buildRobotSpawnLaunchXml(robots.first);
      // push-ros-namespace 와 launch 인자를 함께 쓰면 노드가
      // /pinky_01/pinky_01/... 에 뜬다. 그러면 create 가 기다리는
      // robot_description 이 영영 오지 않아 로봇이 스폰되지 않는다.
      expect(xml, isNot(contains('push-ros-namespace')));
      expect(xml, contains('<arg name="namespace" value="pinky_01"/>'));
    });

    test('create 가 그 로봇의 robot_description 을 절대 이름으로 가리킨다', () {
      for (final robot in robots) {
        final xml = buildRobotSpawnLaunchXml(robot);
        expect(xml, contains('-topic /${robot.gzName}/robot_description'));
        // 상대 이름이면 루트의 /robot_description 을 기다린다.
        expect(xml, isNot(contains('-topic robot_description')));
      }
    });

    test('로봇마다 제 디렉터리에서 불러온다', () {
      // 로봇 하나가 디렉터리 하나다. 한 대를 빼거나 옮길 때 그 디렉터리만
      // 보면 된다.
      final xml = buildProjectBringupXml(
        mapName: 'gwanghee',
        robots: robots,
        mapDirectory: '/maps/gwanghee',
      );
      expect(robotDirectoryName(robots.first), 'robots/PK-01');
      expect(
        xml,
        contains(r'<include file="$(var map_dir)/robots/PK-01'
            '/spawn.launch.xml"/>'),
      );
      expect(
        xml,
        contains(r'<include file="$(var map_dir)/robots/PK-02'
            '/spawn.launch.xml"/>'),
      );
      // 로봇 설정이 이 파일에 다시 적히면 두 곳이 어긋날 수 있다.
      expect(xml, isNot(contains('upload_robot.launch.py')));
    });

    test('로봇 ID 에 이상한 글자가 있어도 디렉터리 밖으로 나가지 않는다', () {
      const sneaky = RmfProjectRobot(
        robotId: '../../etc/passwd',
        displayName: 'x',
        model: 'PINKY-GZ',
        gzName: 'pinky_x',
        zones: [],
      );
      expect(robotDirectoryName(sneaky), isNot(contains('..')));
      expect(robotDirectoryName(sneaky), startsWith('robots/'));
    });

    test('Gazebo 플러그인이 켜지도록 is_sim 을 넘긴다', () {
      // is_sim 이 빠지면 diff drive 도 LiDAR 도 없는 껍데기가 스폰된다.
      // 보이기는 하는데 cmd_vel 을 줘도 움직이지 않는다.
      expect(
        buildRobotSpawnLaunchXml(robots.first),
        contains('<arg name="is_sim" value="True"/>'),
      );
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
      expect(xml, contains('Gazebo 로 돌릴 로봇이 없다'));
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
      dataSource: RobotDataSource.gazebo,
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
      expect(yaml, contains('{} # 관제 대상 이동 로봇이 없다.'));
    });

    test('bringup 은 open_manipulator 쪽 설명을 쓴다', () {
      final xml = buildRobotSpawnLaunchXml(workcell);
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
      expect(
        buildRobotSpawnLaunchXml(robots.first),
        contains('-topic /pinky_01/robot_description'),
      );
    });

    test('그리퍼가 없는 모델에는 그리퍼 컨트롤러를 올리지 않는다', () {
      // omy_3m 에는 그리퍼가 없다. 없는 컨트롤러를 올리면 spawner 가 기다리다
      // 실패하고, 팔까지 함께 안 움직이는 것처럼 보인다.
      final xml = buildRobotSpawnLaunchXml(
        const RmfProjectRobot(
          robotId: 'OMY-01',
          displayName: '팔 1호',
          model: 'omy_3m',
          kind: RmfRobotKind.workcell,
          dataSource: RobotDataSource.gazebo,
          gzName: 'omy_01',
          zones: [],
          chargerWaypoint: 'OMX1',
        ),
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

  group('로봇별 디렉터리', () {
    const workcell = RmfProjectRobot(
      robotId: 'OMX-01',
      displayName: '매니퓰레이터 1호',
      model: 'open_manipulator_x',
      kind: RmfRobotKind.workcell,
      dataSource: RobotDataSource.gazebo,
      gzName: 'omx_01',
      zones: [],
      chargerWaypoint: 'OMX1',
      spawnX: 5,
      spawnY: 2,
    );

    test('등록 정보를 사람이 읽을 수 있게 남긴다', () {
      final yaml = buildRobotInfoYaml(robots.first);
      expect(yaml, contains('id: PK-01'));
      expect(yaml, contains('kind: mobile # 이동 로봇'));
      expect(yaml, contains('gz_name: pinky_01'));
      expect(yaml, contains('charger_waypoint: 충전1'));
      expect(yaml, contains('spawn_x: 12.500'));
    });

    test('설치 로봇은 충전이 아니라 설비 자리라고 적는다', () {
      final yaml = buildRobotInfoYaml(workcell);
      expect(yaml, contains('kind: workcell # 설치 로봇'));
      expect(yaml, contains('station_waypoint: OMX1'));
      expect(yaml, isNot(contains('charger_waypoint')));
    });

    test('한 대만 담긴 다리 설정을 남긴다', () {
      final yaml = buildRobotBridgeYaml(robots.first);
      expect(yaml, contains('/pinky_01/odom'));
      // 다른 로봇 것이 섞이면 이 디렉터리만 봐서는 알 수 없게 된다.
      expect(yaml, isNot(contains('pinky_02')));
      expect(yaml, contains('한 대의 토픽 목록'));
    });

    test('설명이 어디서 고치는지 알려 준다', () {
      final readme = buildRobotReadme(robots.first, 'gwanghee');
      expect(readme, contains('# PK-01 · 핑키 1호'));
      expect(readme, contains('`/pinky_01`'));
      // 여기 파일을 손으로 고치면 다음 저장 때 사라진다.
      expect(readme, contains('손으로 고치지 마세요'));
      expect(readme, contains('로봇 등록'));
    });

    test('설치 로봇 설명에는 올리는 컨트롤러가 적힌다', () {
      final readme = buildRobotReadme(workcell, 'gwanghee');
      expect(readme, contains('workcell'));
      expect(readme, contains('`arm_controller`'));
      expect(readme, contains('`gripper_controller`'));
    });

    test('로봇마다 디렉터리가 갈린다', () {
      final names = {
        for (final robot in [...robots, workcell]) robotDirectoryName(robot),
      };
      expect(names, {'robots/PK-01', 'robots/PK-02', 'robots/OMX-01'});
    });
  });

  group('값의 출처', () {
    const mock = RmfProjectRobot(
      robotId: 'MK-01',
      displayName: '연습용 1호',
      model: 'PINKY-GZ',
      gzName: 'mock_01',
      zones: ['ambient'],
      chargerWaypoint: '충전9',
      spawnX: 1,
      spawnY: 1,
    );
    const real = RmfProjectRobot(
      robotId: 'RP-01',
      displayName: '실물 1호',
      model: 'PINKY-GZ',
      dataSource: RobotDataSource.real,
      gzName: 'real_01',
      zones: ['ambient'],
      chargerWaypoint: '충전8',
      spawnX: 2,
      spawnY: 2,
    );
    // 이동 로봇 둘은 Gazebo, 여기에 Mock 하나와 실물 하나를 더한다.
    const mixed = [...robots, mock, real];

    test('기본값은 Mock 이다', () {
      // 등록만 하고 아무것도 안 고른 로봇을 실행에 밀어 넣으면 안 된다.
      expect(mock.dataSource, RobotDataSource.mock);
      expect(mock.isManagedByRmf, isFalse);
      expect(mock.runsInGazebo, isFalse);
    });

    test('Mock 은 fleet adapter 에 넣지 않는다', () {
      // 앱이 제 안에서 굴리는 것이라 실제로는 없다. 넣으면 fleet adapter 가
      // 오지 않을 로봇의 상태를 계속 기다린다.
      final yaml = buildFleetAdapterYaml(
        fleet: const RmfFleetSettings(),
        robots: mixed,
        mapName: 'gwanghee',
      );
      expect(yaml, contains('    PK-01:'));
      expect(yaml, contains('    RP-01:'), reason: '실물은 관제 대상이다');
      expect(yaml, isNot(contains('    MK-01:')));
      expect(yaml, contains('# 앱 Mock 로봇은 플릿에 넣지 않는다'));
      expect(yaml, contains('#   MK-01 · 연습용 1호'));
    });

    test('Gazebo 로 돌릴 것만 시뮬레이터에 올린다', () {
      // 실물을 시뮬레이터에 또 띄우면 같은 이름이 두 번 뜬다.
      final xml = buildProjectBringupXml(
        mapName: 'gwanghee',
        robots: mixed,
        mapDirectory: '/maps/gwanghee',
      );
      expect(xml, contains('robots/PK-01/spawn.launch.xml'));
      expect(xml, contains('robots/PK-02/spawn.launch.xml'));
      expect(xml, isNot(contains('robots/MK-01/')));
      expect(xml, isNot(contains('robots/RP-01/')));
    });

    test('Gazebo 에 없는 로봇에는 다리를 놓지 않는다', () {
      // 오지 않을 토픽을 기다리는 다리가 조용히 남는다.
      final yaml = buildProjectGzBridgeYaml(
        mapName: 'gwanghee',
        robots: mixed,
      );
      expect(yaml, contains('/pinky_01/odom'));
      expect(yaml, isNot(contains('mock_01')));
      expect(yaml, isNot(contains('real_01')));
    });

    test('Gazebo 로 돌릴 것이 하나도 없으면 그렇다고 적는다', () {
      final xml = buildProjectBringupXml(
        mapName: 'gwanghee',
        robots: const [mock, real],
        mapDirectory: '/maps/gwanghee',
      );
      expect(xml, contains('Gazebo 로 돌릴 로봇이 없다'));
      expect(xml, contains('출처를 Gazebo 로 골라야'));
      expect(xml, contains('</launch>'));
    });

    test('로봇 디렉터리에 출처를 적는다', () {
      expect(
        buildRobotInfoYaml(mock),
        contains('data_source: mock # 앱 Mock 데이터'),
      );
      expect(
        buildRobotInfoYaml(real),
        contains('data_source: real # 실제 로봇'),
      );
    });

    test('bringup 이 부르지 않는 이유를 그 파일에 적는다', () {
      // 파일만 보고 왜 안 올라오는지 헤매지 않아야 한다.
      final xml = buildRobotSpawnLaunchXml(mock);
      expect(xml, contains('값의 출처: 앱 Mock 데이터'));
      expect(xml, contains('bringup 이 부르지 않는다'));
      // Gazebo 것은 부른다고 적는다.
      expect(
        buildRobotSpawnLaunchXml(robots.first),
        contains('bringup 이 이 파일을 include 한다'),
      );
    });

    test('설명이 어디에 들어가고 안 들어가는지 알려 준다', () {
      expect(
        buildRobotReadme(mock, 'gwanghee'),
        contains('fleet adapter 에도 Gazebo 에도 들어가지 않습니다'),
      );
      expect(
        buildRobotReadme(real, 'gwanghee'),
        contains('실물이 이미 있으므로 Gazebo 에는 올리지 않습니다'),
      );
      expect(
        buildRobotReadme(robots.first, 'gwanghee'),
        contains('Gazebo 에 올립니다'),
      );
    });

    test('출처가 JSON 을 오가도 유지된다', () {
      expect(
        RmfProjectRobot.fromJson(real.toJson()).dataSource,
        RobotDataSource.real,
      );
      // v10 이전 기록에는 출처가 없다. 전부 앱 Mock 으로 보고 있었다.
      expect(
        RmfProjectRobot.fromJson(const {
          'robotId': 'OLD-01',
          'model': 'PINKY-GZ',
          'gzName': 'old_01',
        }).dataSource,
        RobotDataSource.mock,
      );
    });
  });

  group('중지 스크립트', () {
    final script = buildProjectStopScript(
      mapName: 'gwanghee',
      mapDirectory: '/maps/gwanghee',
    );

    test('이 맵을 물고 남은 노드를 쓸어낸다', () {
      // ros2 launch 가 죽으면 자식이 init 으로 재부모화된다. 그룹도 잃고
      // `ros2 launch <경로>` 라는 이름도 잃어서 이름·PGID 로는 못 잡는다.
      // fleet_manager 가 그렇게 남아 `백엔드 중지` 를 눌러도 살아 있었다.
      expect(script, contains('sweep_map_dir'));
      expect(script, contains(r'/proc/$pid/cmdline'));
      expect(script, contains('이 맵을 물고 남은 노드'));
    });

    test('제 자신은 죽이지 않는다', () {
      // 스크립트 경로에도 맵 디렉터리가 들어 있다. 거르지 않으면 자기를 끊는다.
      expect(script, contains('stop_gwanghee.sh'));
      expect(script, contains(r'"$pid" == "$$"'));
      expect(script, contains(r'"$pid" == "$PPID"'));
    });

    test('응답이 없으면 강제 종료까지 올라간다', () {
      // rclpy 노드는 TERM 을 받고도 종료 중에 굳는 일이 있다. 거기서 멈추면
      // 노드가 살아남아 다음 실행에서 이름이 겹친다.
      expect(script, contains('for signal in INT TERM KILL'));
      expect(script, contains('응답이 없어 강제 종료합니다'));
    });

    test('좀비는 기다리지 않는다', () {
      // 이미 끝난 것을 두고 매 단계 3초씩 기다리면 중지가 괜히 느려진다.
      expect(script, contains(r'*Z*'));
    });

    test('다른 맵은 건드리지 않는다', () {
      expect(script, contains(r'MAP_DIR="${MAP_DIR:-/maps/gwanghee}"'));
      expect(script, isNot(contains('tinyRobot')));
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
