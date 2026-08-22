/// 한 자리에 두 대를 묶으면 어떻게 되는가.
///
/// 자리를 아예 안 고른 로봇 둘로 이미 겪었다 — 둘 다 원점(0,0)에 놓여 메시
/// 충돌 도형끼리 파고들었고 Gazebo 가 스폰 4초 만에 죽었다. 자리를 **골랐어도
/// 같은 자리**면 결과가 같다. 좌표가 한 점이 되기 때문이다.
///
/// 실물이면 Gazebo 는 안 죽지만 대신 더 조용히 어긋난다. 두 대의 AMCL 초기
/// 자세가 같은 자리로 나가서, 실제로는 떨어져 있는 둘이 서로 자기가 그 자리에
/// 있다고 믿는다.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:robocontrol/rmf_project_config.dart';
import 'package:robocontrol/robot_station_rule.dart';

void main() {
  RmfProjectRobot robot(
    String id, {
    String? station,
    RobotDataSource dataSource = RobotDataSource.real,
  }) => RmfProjectRobot(
    robotId: id,
    displayName: id.toUpperCase(),
    model: 'PINKY-GZ',
    gzName: id,
    zones: const ['ambient'],
    dataSource: dataSource,
    chargerWaypoint: station,
  );

  group('등록 창에서 알린다', () {
    final fleet = [robot('pinky_01', station: '충전1')];

    test('이미 쓰는 자리를 고르면 누가 쓰는지 알려 준다', () {
      final holder = robotHoldingStation(
        robots: fleet,
        station: '충전1',
        robotId: 'pinky_02',
      );
      expect(holder?.robotId, 'pinky_01');
      final message = stationConflictMessage(holder: holder, station: '충전1');
      expect(message, contains('pinky_01'));
      expect(message, contains('충전1'));
    });

    test('빈 자리는 겹치지 않는다', () {
      expect(
        robotHoldingStation(
          robots: fleet,
          station: '충전2',
          robotId: 'pinky_02',
        ),
        isNull,
      );
    });

    /// 등록을 열어 다른 것만 고치고 저장할 때 제 자리에 걸리면 안 된다.
    test('자기 자신은 겹침으로 세지 않는다', () {
      expect(
        robotHoldingStation(
          robots: fleet,
          station: '충전1',
          robotId: 'pinky_01',
        ),
        isNull,
      );
    });

    test('자리를 안 골랐으면 따질 것이 없다', () {
      expect(
        robotHoldingStation(robots: fleet, station: null, robotId: 'pinky_02'),
        isNull,
      );
      expect(stationConflictMessage(holder: null, station: '충전1'), isNull);
    });
  });

  group('배포는 막는다', () {
    /// 등록 창은 막지 않는다 — 두 로봇의 자리를 서로 바꾸는 중일 수 있고,
    /// 그때 막으면 바꿀 방법이 없어진다. 배포는 좌표가 파일에 박히는 순간이다.
    test('같은 자리를 쓰는 두 대가 있으면 안 내보낸다', () {
      final message = deployBlockedMessage([
        robot('pinky_01', station: '충전1'),
        robot('pinky_02', station: '충전1'),
      ]);
      expect(message, isNotNull);
      expect(message, contains('충전1'));
      expect(message, contains('pinky_01'));
      expect(message, contains('pinky_02'));
    });

    test('자리가 갈리면 안 막는다', () {
      expect(
        deployBlockedMessage([
          robot('pinky_01', station: '충전1'),
          robot('pinky_02', station: '충전2'),
        ]),
        isNull,
      );
    });

    /// Mock 은 산출물에 올릴 것이 없다.
    test('Mock 로봇은 세지 않는다', () {
      expect(
        deployBlockedMessage([
          robot('pinky_01', station: '충전1'),
          robot('mock_01', station: '충전1', dataSource: RobotDataSource.mock),
        ]),
        isNull,
      );
    });

    /// 자리를 안 고른 쪽이 더 급하다. 그것부터 알린다.
    test('자리 미지정이 겹침보다 먼저 걸린다', () {
      final message = deployBlockedMessage([
        robot('pinky_01', station: '충전1'),
        robot('pinky_02', station: '충전1'),
        robot('pinky_03'),
      ]);
      expect(message, contains('자리를 안 고른'));
    });

    test('겹치는 자리와 그 로봇을 모아서 돌려준다', () {
      final shared = robotsSharingStation([
        robot('pinky_01', station: '충전1'),
        robot('pinky_02', station: '충전1'),
        robot('pinky_03', station: '충전2'),
      ]);
      expect(shared.keys, ['충전1']);
      expect(shared['충전1']!.map((r) => r.robotId), ['pinky_01', 'pinky_02']);
    });
  });
}
