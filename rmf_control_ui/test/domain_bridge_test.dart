/// 실물 Pinky 두 대를 도메인으로 갈라 관제 하나로 모으는 다리를 지킨다.
///
/// 로봇 workspace 에 namespace bringup 을 아직 못 넣은 동안, 두 대가 모두 루트
/// 이름(`/cmd_vel` · `/odom`)을 쓴다. 같은 도메인에 두면 **한 대에 보낸
/// `cmd_vel` 로 두 대가 같이 움직인다.** 오류는 안 난다 — 그래서 이 파일이
/// 지키는 것 대부분은 "겹치지 않는다" 쪽이다.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:rmf_control_ui/rmf_project_config.dart';

/// 실물 이동 로봇 하나.
RmfProjectRobot realPinky(String id, String ns, {int? domain}) =>
    RmfProjectRobot(
      robotId: id,
      displayName: id,
      model: 'PINKY',
      gzName: ns,
      zones: const ['ambient'],
      dataSource: RobotDataSource.real,
      rosDomainId: domain,
    );

/// `topics:` 아래에 적힌 토픽 이름들. YAML 파서 없이 훑는다.
List<String> topicKeys(String yaml) => [
  for (final line in yaml.split('\n'))
    if (line.startsWith('  "') && line.trimRight().endsWith('":'))
      line.trim().replaceAll('"', '').replaceAll(':', ''),
];

void main() {
  group('로봇 한 대의 다리', () {
    test('로봇 도메인에서 관제 도메인으로 옮기며 이름을 가른다', () {
      final yaml = buildRobotDomainBridgeYaml(
        mapName: 'gwanghee',
        projectDomainId: 52,
        robot: realPinky('PK-01', 'pinky_01', domain: 61),
      );

      expect(yaml, contains('"/odom":'));
      expect(yaml, contains('from_domain: 61'));
      expect(yaml, contains('to_domain: 52'));
      expect(yaml, contains('remap: "/pinky_01/odom"'));
    });

    test('cmd_vel 만 관제에서 로봇으로 간다', () {
      final yaml = buildRobotDomainBridgeYaml(
        mapName: 'gwanghee',
        projectDomainId: 52,
        robot: realPinky('PK-01', 'pinky_01', domain: 61),
      );

      // 방향을 뒤집으면 다리는 뜨는데 명령이 로봇에 영영 안 간다. 관제가 보는
      // 이름은 /pinky_01/cmd_vel 이고, 로봇이 듣는 이름은 루트 /cmd_vel 이다.
      final block = yaml.substring(yaml.indexOf('"/pinky_01/cmd_vel":'));
      expect(block, contains('from_domain: 52'));
      expect(block, contains('to_domain: 61'));
      expect(block, contains('remap: "/cmd_vel"'));
    });

    test('tf 는 옮기지 않는다', () {
      final yaml = buildRobotDomainBridgeYaml(
        mapName: 'gwanghee',
        projectDomainId: 52,
        robot: realPinky('PK-01', 'pinky_01', domain: 61),
      );

      // domain_bridge 는 토픽 이름만 바꾸고 메시지 안은 못 고친다. 루트 이름을
      // 쓰는 두 로봇의 /tf 는 프레임 이름까지 `odom → base_footprint` 로 같아,
      // 옮기면 관제에서 두 TF 나무가 한 이름으로 겹쳐 튄다.
      expect(yaml, isNot(contains('"/tf":')));
      expect(yaml, isNot(contains('tf2_msgs')));
    });

    test('로봇 도메인이 관제와 같으면 다리를 안 놓는다', () {
      final yaml = buildRobotDomainBridgeYaml(
        mapName: 'gwanghee',
        projectDomainId: 52,
        robot: realPinky('PK-01', 'pinky_01', domain: 52),
      );

      // 옮길 것이 없을 뿐 아니라, 이 로봇은 다른 로봇과 루트 토픽이 그대로
      // 겹친 상태다. 조용히 넘기지 말고 파일에 까닭을 남긴다.
      expect(yaml, contains('topics: {}'));
      expect(yaml, contains('관제와 같다'));
    });

    test('도메인을 안 정한 로봇은 다리를 안 놓는다', () {
      final yaml = buildRobotDomainBridgeYaml(
        mapName: 'gwanghee',
        projectDomainId: 52,
        robot: realPinky('PK-01', 'pinky_01'),
      );

      expect(yaml, contains('topics: {}'));
      expect(yaml, contains('비어 있다'));
    });
  });

  group('두 대를 함께 놓을 때', () {
    test('로봇마다 파일이 갈려서 루트 이름이 안 겹친다', () {
      // 한 파일에 모으면 `topics:` 의 열쇠가 토픽 이름이라 두 대의 "/odom" 이
      // 같은 열쇠로 겹치고, YAML 을 읽는 순간 뒤엣것이 앞엣것을 덮어쓴다.
      // 오류는 안 나고 한 대가 조용히 빠진다.
      final first = buildRobotDomainBridgeYaml(
        mapName: 'gwanghee',
        projectDomainId: 52,
        robot: realPinky('PK-01', 'pinky_01', domain: 61),
      );
      final second = buildRobotDomainBridgeYaml(
        mapName: 'gwanghee',
        projectDomainId: 52,
        robot: realPinky('PK-02', 'pinky_02', domain: 62),
      );

      // 파일 하나 안에서는 열쇠가 하나도 안 겹친다.
      for (final yaml in [first, second]) {
        final keys = topicKeys(yaml);
        expect(keys.toSet().length, keys.length);
      }
      // 그리고 두 대가 서로 다른 도메인에서 온다.
      expect(first, contains('from_domain: 61'));
      expect(second, contains('from_domain: 62'));
      expect(first, contains('remap: "/pinky_01/odom"'));
      expect(second, contains('remap: "/pinky_02/odom"'));
    });

    test('실물 이동 로봇만 다리를 놓는다', () {
      final robots = [
        realPinky('PK-01', 'pinky_01', domain: 61),
        const RmfProjectRobot(
          robotId: 'PK-09',
          displayName: 'Gazebo 핑키',
          model: 'PINKY-GZ',
          gzName: 'pinky_09',
          zones: ['ambient'],
          dataSource: RobotDataSource.gazebo,
          rosDomainId: 61,
        ),
        const RmfProjectRobot(
          robotId: 'RS-01',
          displayName: 'Mock',
          model: 'MOCK',
          gzName: 'mock_01',
          zones: ['ambient'],
          dataSource: RobotDataSource.mock,
        ),
      ];

      // Gazebo 는 같은 PC 의 한 도메인에 있고 Mock 은 ROS 를 아예 안 쓴다.
      // 넣으면 오지 않을 토픽을 기다리는 다리가 조용히 남는다.
      expect(domainBridgeRobots(robots).map((r) => r.robotId), ['PK-01']);
    });
  });

  group('실행 스크립트', () {
    test('로봇마다 다리를 하나씩 띄운다', () {
      final script = buildDomainBridgeScript(
        mapName: 'gwanghee',
        projectDomainId: 52,
        robots: [
          realPinky('PK-01', 'pinky_01', domain: 61),
          realPinky('PK-02', 'pinky_02', domain: 62),
        ],
      );

      expect(script, contains('gwanghee_domain_bridge_pinky_01.yaml'));
      expect(script, contains('gwanghee_domain_bridge_pinky_02.yaml'));
      // 하나가 죽어도 나머지는 살아야 해서 배경으로 띄우고 PID 를 남긴다.
      expect(script, contains('stop_bridges'));
    });

    test('도메인이 없는 로봇은 띄우지 않고 까닭을 알린다', () {
      final script = buildDomainBridgeScript(
        mapName: 'gwanghee',
        projectDomainId: 52,
        robots: [realPinky('PK-01', 'pinky_01')],
      );

      // 설정이 비어 있어 띄워도 아무것도 안 옮긴다. 조용히 넘기면 "다리는
      // 떴는데 값이 안 온다" 로 보인다.
      expect(script, isNot(contains('ros2 run domain_bridge')));
      expect(script, contains('건너뜁니다'));
    });
  });
}
