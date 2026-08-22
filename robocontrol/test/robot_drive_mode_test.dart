/// 로봇이 장애물을 얼마나 피하는가.
///
/// 실험실에서는 벽이 스티로폼이고 로봇도 작다. 살짝 스쳐도 아무 일이 안 나는데,
/// Nav2 기본값은 사람이 다니는 복도를 전제로 잡혀 있어 **닿기 한참 전에 길을
/// 포기한다.** 핑키의 발자국은 한 변 0.12m 라 반지름이 0.06m 인데 기본
/// `inflation_radius` 는 0.15m 였다 — 벽에서 15cm 안쪽을 통째로 막힌 것으로
/// 본 셈이다.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:robocontrol/nav2_params.dart';
import 'package:robocontrol/rmf_project_config.dart';
import 'package:robocontrol/robot_drive_mode.dart';

void main() {
  group('두 모드', () {
    test('기본은 일반이다', () {
      const robot = RmfProjectRobot(
        robotId: 'pinky_02',
        displayName: 'PK-02',
        model: 'PINKY-GZ',
        gzName: 'pinky_02',
        zones: ['ambient'],
      );
      expect(robot.driveMode, RobotDriveMode.normal);
    });

    test('일반은 벤더 값 그대로다', () {
      expect(costmapForDriveMode(RobotDriveMode.normal), normalDriveCostmap);
      expect(normalDriveCostmap.inflationRadius, 0.15);
    });

    /// 0 으로 두면 장애물 바로 옆도 싸져서 planner 가 벽을 스치는 경로를
    /// 뽑는데, 그러면 제어 오차만큼 그대로 박는다. 한 칸(0.05m)은 남긴다.
    test('강제는 여유를 줄이되 0 으로 두지 않는다', () {
      final forced = costmapForDriveMode(RobotDriveMode.forced);
      expect(
        forced.inflationRadius,
        lessThan(normalDriveCostmap.inflationRadius),
      );
      expect(forced.inflationRadius, greaterThan(0));
      // 코스트맵 한 칸이 0.05m 다. 그보다 작게 두면 뜻이 없다.
      expect(forced.inflationRadius, greaterThanOrEqualTo(0.05));
    });

    /// 비용이 가파르게 떨어져야 장애물 바로 옆만 비싸고 그 밖은 평지가 된다.
    test('강제는 비용이 더 가파르다', () {
      expect(
        costmapForDriveMode(RobotDriveMode.forced).costScalingFactor,
        greaterThan(normalDriveCostmap.costScalingFactor),
      );
    });

    test('저장하고 되읽어도 남는다', () {
      const robot = RmfProjectRobot(
        robotId: 'pinky_02',
        displayName: 'PK-02',
        model: 'PINKY-GZ',
        gzName: 'pinky_02',
        zones: ['ambient'],
        driveMode: RobotDriveMode.forced,
      );
      expect(
        RmfProjectRobot.fromJson(robot.toJson()).driveMode,
        RobotDriveMode.forced,
      );
      // 자리나 좌표를 고쳐도 사라지면 안 된다.
      expect(robot.withStation('충전2').driveMode, RobotDriveMode.forced);
      expect(
        robot.withSpawn(spawnX: 1, spawnY: -1).driveMode,
        RobotDriveMode.forced,
      );
    });

    test('모르는 값은 일반으로 읽는다', () {
      expect(parseRobotDriveMode(null), RobotDriveMode.normal);
      expect(parseRobotDriveMode('아무거나'), RobotDriveMode.normal);
      expect(parseRobotDriveMode('forced'), RobotDriveMode.forced);
    });
  });

  group('nav2_params 에 반영된다', () {
    const source = '''
local_costmap:
  local_costmap:
    ros__parameters:
      footprint_padding: 0.03
      inflation_layer:
        cost_scaling_factor: 3.0
        inflation_radius: 0.15
      obstacle_layer:
        plugin: "nav2_costmap_2d::ObstacleLayer"
        enabled: True
        observation_sources: scan
      static_layer:
        plugin: "nav2_costmap_2d::StaticLayer"
      footprint: '[[0.06, 0.06], [0.06, -0.06], [-0.06, -0.06], [-0.06, 0.06]]'
controller_server:
  ros__parameters:
    FollowPath:
      inflation_cost_scaling_factor: 3.0
      use_collision_detection: true
    progress_checker:
      movement_time_allowance: 10.0
      required_movement_radius: 0.5
''';

    String yamlFor(RobotDriveMode mode) => rewriteNav2Params(
      source: source,
      namespace: 'pinky_02',
      driveMode: mode,
    ).yaml;

    test('일반은 벤더 값을 안 건드린다', () {
      final yaml = yamlFor(RobotDriveMode.normal);
      expect(yaml, contains('inflation_radius: 0.150'));
      expect(yaml, contains('cost_scaling_factor: 3.000'));
    });

    test('강제는 여유를 줄인다', () {
      final yaml = yamlFor(RobotDriveMode.forced);
      expect(yaml, contains('inflation_radius: 0.050'));
      expect(yaml, contains('cost_scaling_factor: 10.000'));
      expect(yaml, contains('inflation_cost_scaling_factor: 10.000'));
      expect(yaml, contains('footprint_padding: 0.000'));
      expect(yaml, contains('[[0.045, 0.045], [0.045, -0.045]'));
      expect(yaml, contains('movement_time_allowance: 20.000'));
      expect(yaml, contains('required_movement_radius: 0.050'));
    });

    test('일반 모드는 실측 footprint와 진행 판정을 유지한다', () {
      final yaml = yamlFor(RobotDriveMode.normal);
      expect(yaml, contains('[[0.06, 0.06], [0.06, -0.06]'));
      expect(yaml, contains('movement_time_allowance: 10.0'));
      expect(yaml, contains('required_movement_radius: 0.5'));
    });

    test('강제는 장애물과 충돌 예측을 끈다', () {
      final yaml = yamlFor(RobotDriveMode.forced);
      expect(yaml, contains('observation_sources: scan'));
      expect(yaml, contains('enabled: false'));
      expect(yaml, contains('use_collision_detection: false'));
    });

    test('무엇을 바꿨는지 남긴다', () {
      final result = rewriteNav2Params(
        source: source,
        namespace: 'pinky_02',
        driveMode: RobotDriveMode.forced,
      );
      expect(result.changes.where((line) => line.contains('강제')), isNotEmpty);
    });
  });

  /// 좁은 곳에서는 앞으로 들어갈 수 없는 자리가 있다 — 대기1 에서 −45도로 선
  /// 뒤 후진으로 픽업에 들어가는 식이다. 벤더 기본값은 후진을 막아 두어, 그런
  /// 자리에는 빙 돌거나 아예 길을 못 찾는다.
  group('후진', () {
    test('기본은 안 한다', () {
      const robot = RmfProjectRobot(
        robotId: 'pinky_02',
        displayName: 'PK-02',
        model: 'PINKY-GZ',
        gzName: 'pinky_02',
        zones: ['ambient'],
      );
      expect(robot.allowReversing, isFalse);
    });

    /// **둘은 서로 배타적이다.** `RegulatedPurePursuitController` 는 후진을
    /// 허용하면 `use_rotate_to_heading` 을 끄도록 되어 있다. 둘 다 켜면
    /// 컨트롤러가 파라미터를 거절해 노드가 안 뜬다.
    test('켜면 제자리 회전이 꺼진다', () {
      final on = reversingSettings(allowReversing: true);
      expect(on.allowReversing, isTrue);
      expect(on.useRotateToHeading, isFalse);
    });

    test('끄면 제자리 회전이 켜진다', () {
      final off = reversingSettings(allowReversing: false);
      expect(off.allowReversing, isFalse);
      expect(off.useRotateToHeading, isTrue);
    });

    test('둘이 함께 켜지는 조합은 안 나온다', () {
      for (final allow in [true, false]) {
        final settings = reversingSettings(allowReversing: allow);
        expect(
          settings.allowReversing && settings.useRotateToHeading,
          isFalse,
          reason: '노드가 안 뜨는 조합이다',
        );
      }
    });

    test('저장하고 되읽어도 남는다', () {
      const robot = RmfProjectRobot(
        robotId: 'pinky_02',
        displayName: 'PK-02',
        model: 'PINKY-GZ',
        gzName: 'pinky_02',
        zones: ['ambient'],
        allowReversing: true,
      );
      expect(RmfProjectRobot.fromJson(robot.toJson()).allowReversing, isTrue);
      expect(robot.withStation('충전2').allowReversing, isTrue);
    });

    group('nav2_params 에 반영된다', () {
      const source = """
controller_server:
  ros__parameters:
    FollowPath:
      allow_reversing: false
      use_rotate_to_heading: true
""";

      String yamlFor(bool allow) => rewriteNav2Params(
        source: source,
        namespace: 'pinky_02',
        allowReversing: allow,
      ).yaml;

      test('끄면 벤더 값 그대로다', () {
        final yaml = yamlFor(false);
        expect(yaml, contains('allow_reversing: false'));
        expect(yaml, contains('use_rotate_to_heading: true'));
      });

      test('켜면 두 값이 함께 바뀐다', () {
        final yaml = yamlFor(true);
        expect(yaml, contains('allow_reversing: true'));
        expect(yaml, contains('use_rotate_to_heading: false'));
      });
    });

    test('켜면 제자리 회전이 사라진다고 알린다', () {
      expect(reversingWarning(allowReversing: false), isNull);
      final warning = reversingWarning(allowReversing: true)!;
      expect(warning, contains('제자리 회전'));
      // 왜 함께 못 쓰는지까지 적는다.
      expect(warning, contains('노드가'));
    });
  });

  /// 어디에 써도 되는 모드가 아니다. 사람이 함께 다니는 곳에서 켜면 로봇이
  /// 사람 쪽으로 더 붙는다.
  group('강제 모드는 경고한다', () {
    test('일반에는 경고가 없다', () {
      expect(forcedDriveModeWarning(RobotDriveMode.normal), isNull);
    });

    test('어디에 쓰면 안 되는지 적는다', () {
      final warning = forcedDriveModeWarning(RobotDriveMode.forced)!;
      expect(warning, contains('사람'));
      expect(warning, contains('실험실'));
      expect(warning, contains('자동으로 멈추지 않습니다'));
    });

    test('두 모드 다 설명이 있다', () {
      for (final mode in RobotDriveMode.values) {
        expect(mode.label, isNotEmpty);
        expect(mode.summary, isNotEmpty);
      }
    });
  });
}
