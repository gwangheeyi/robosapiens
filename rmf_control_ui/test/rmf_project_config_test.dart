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
}
