/// RViz 설정에서 로봇을 눈으로 가르는 부분.
///
/// 라이다 점이 전부 같은 색이면 두 대가 같은 복도에 있을 때 어느 점이 누구
/// 것인지 알 수 없다. 벽을 넘겨다보는 로봇을 찾으려고 켜 놓는 화면인데
/// 정작 범인을 못 짚는다.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:rmf_control_ui/rmf_project_config.dart';

void main() {
  const pinkyOne = RmfProjectRobot(
    robotId: 'PK-01',
    displayName: '핑키 1호',
    model: 'PINKY-GZ',
    gzName: 'pinky_01',
    zones: ['ambient'],
    dataSource: RobotDataSource.gazebo,
    chargerWaypoint: '홈1',
  );
  const pinkyTwo = RmfProjectRobot(
    robotId: 'PK-02',
    displayName: '핑키 2호',
    model: 'PINKY-GZ',
    gzName: 'pinky_02',
    zones: ['ambient'],
    dataSource: RobotDataSource.gazebo,
    chargerWaypoint: '홈2',
  );

  /// 라이다 표시 블록에서 `Color:` 줄만 순서대로 뽑는다.
  List<String> lidarColors(String rviz) {
    final colors = <String>[];
    final lines = rviz.split('\n');
    for (var i = 0; i < lines.length; i++) {
      if (!lines[i].contains('Class: rviz_default_plugins/LaserScan')) continue;
      final color = lines
          .skip(i)
          .take(8)
          .firstWhere((line) => line.trim().startsWith('Color:'));
      colors.add(color.split('Color:')[1].trim());
    }
    return colors;
  }

  group('로봇별 라이다 색', () {
    test('두 대의 색이 서로 다르다', () {
      final rviz = buildProjectRvizConfig(
        mapName: 'gwanghee',
        robots: [pinkyOne, pinkyTwo],
      );
      final colors = lidarColors(rviz);
      expect(colors, hasLength(2));
      expect(colors[0], isNot(colors[1]), reason: '같은 색이면 구분이 안 됩니다');
    });

    test('첫 색은 원래 쓰던 주황 그대로다', () {
      // 한 대만 쓰던 사람에게 이유 없이 화면이 바뀌면 안 된다.
      final rviz = buildProjectRvizConfig(
        mapName: 'gwanghee',
        robots: [pinkyOne],
      );
      expect(lidarColors(rviz), ['255; 85; 0']);
    });

    test('색 이름을 표시 이름에도 적는다', () {
      // 왼쪽 목록의 로봇과 화면의 점을 이어 주는 것은 이 이름뿐이다.
      final rviz = buildProjectRvizConfig(
        mapName: 'gwanghee',
        robots: [pinkyOne, pinkyTwo],
      );
      expect(rviz, contains('Name: 라이다 PK-01 (주황)'));
      expect(rviz, contains('Name: 라이다 PK-02 (하늘)'));
    });

    test('팔레트 색은 전부 서로 다르다', () {
      final rgb = robotPalette.map((c) => c.rviz).toList();
      final labels = robotPalette.map((c) => c.label).toList();
      expect(rgb.toSet(), hasLength(rgb.length));
      expect(labels.toSet(), hasLength(labels.length));
    });

    test('로봇이 팔레트보다 많으면 처음부터 돈다', () {
      // 색이 모자라 터지느니 겹치는 편이 낫다.
      expect(robotColorFor(robotPalette.length), robotPalette.first);
      expect(robotColorFor(robotPalette.length + 1), robotPalette[1]);
    });

    test('배경·격자와 같은 색은 쓰지 않는다', () {
      // 48;48;48 배경과 130;130;130 격자에 묻히면 없는 것과 같다.
      for (final color in robotPalette) {
        expect(color.rviz, isNot('48; 48; 48'));
        expect(color.rviz, isNot('130; 130; 130'));
      }
    });

    test('두 표기가 같은 값에서 나온다', () {
      // 값을 손으로 두 번 적으면 언젠가 어긋난다. cmd_vel 이름이 그렇게 어긋나
      // Gazebo 에 속도가 한 번도 안 갔다.
      for (final color in robotPalette) {
        expect(color.rviz, '${color.r}; ${color.g}; ${color.b}');
        expect(color.launchList, '[${color.r}, ${color.g}, ${color.b}]');
      }
    });
  });

  group('로봇 표시 색', () {
    /// launch 가 넘기는 `<로봇>_color` 를 로봇 이름별로 모은다.
    Map<String, String> robotColorParams(String launch) {
      final params = <String, String>{};
      final matches = RegExp(
        r'<set_parameter name="([^"]+)_color"\s*\n?\s*value="([^"]+)"/>',
      ).allMatches(launch);
      for (final match in matches) {
        params[match.group(1)!] = match.group(2)!;
      }
      return params;
    }

    String launchFor(List<RmfProjectRobot> robots) => buildProjectLaunchXml(
      mapName: 'gwanghee',
      fleetName: 'gwanghee_pinky',
      mapDirectory: '/maps/gwanghee',
      buildingYamlName: 'gwanghee.building.yaml',
      robots: robots,
    );

    test('로봇마다 제 색을 fleet_states_visualizer 에 넘긴다', () {
      final params = robotColorParams(launchFor([pinkyOne, pinkyTwo]));
      expect(params, {
        'PK-01': '[255, 85, 0]',
        'PK-02': '[0, 170, 255]',
      });
    });

    test('로봇 색과 라이다 색이 같다', () {
      // 이것이 어긋나면 공과 점의 색이 달라 오히려 두 로봇으로 보인다.
      const robots = [pinkyOne, pinkyTwo];
      final params = robotColorParams(launchFor(robots));
      final scans = lidarColors(
        buildProjectRvizConfig(mapName: 'gwanghee', robots: robots),
      );
      expect(params.length, scans.length);
      var i = 0;
      for (final entry in params.entries) {
        final color = robotColorFor(i);
        expect(entry.value, color.launchList, reason: '${entry.key} 로봇 색');
        expect(scans[i], color.rviz, reason: '${entry.key} 라이다 색');
        i++;
      }
    });

    test('로봇이 없으면 색 파라미터도 없다', () {
      expect(robotColorParams(launchFor(const [])), isEmpty);
    });
  });
}
