/// 로봇에게 "너는 지금 여기에 있다" 고 알려 주는 규칙.
///
/// 실제로 겪은 일: pinky_01 을 브링업했는데 지도에 아무것도 안 그려졌다. AMCL 은
/// `map → odom` 을 스스로 못 찾으므로 처음 한 번은 사람이 자리를 알려 줘야 한다.
/// 배포할 때 `nav2_params.yaml` 에 박아 넣는 `initial_pose` 가 그 한 번인데,
/// 그것은 Nav2 를 **처음 띄울 때만** 듣는다. 로봇을 손으로 옮기면 다시 알려 줄
/// 방법이 앱에 없었다.
///
/// 그 길이 Gazebo 로봇에만 있었던 것이 문제였다. `resetGazeboRobotPose` 는
/// `gz service set_pose` 가 성공해야만 initialpose 를 보내는데, 실물 로봇에는
/// Gazebo 가 없어 첫 단계에서 끝났다 — 실물이 이 기능을 가장 많이 필요로 하는데도
/// 그랬다.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:rmf_control_ui/rmf_project_config.dart';
import 'package:rmf_control_ui/robot_initial_pose.dart';

void main() {
  RmfProjectRobot pinky({
    RobotDataSource dataSource = RobotDataSource.real,
    RmfRobotKind kind = RmfRobotKind.mobile,
    String? charger = '충전1',
  }) => RmfProjectRobot(
    robotId: 'pinky_03',
    displayName: 'PK-03',
    model: 'PINKY-GZ',
    gzName: 'pinky_03',
    zones: const ['ambient'],
    kind: kind,
    dataSource: dataSource,
    chargerWaypoint: charger,
  );

  group('AMCL 이 듣는 토픽', () {
    /// Nav2 를 네임스페이스로 띄우면 AMCL 도 그 아래로 들어간다. 루트로 보내면
    /// 아무도 안 듣는데 **오류도 안 난다** — 보낸 사람은 보냈다고 믿는다.
    test('로봇 네임스페이스 아래로 보낸다', () {
      expect(initialPoseTopic('pinky_03'), '/pinky_03/initialpose');
    });

    test('앞뒤 슬래시를 겹쳐 붙이지 않는다', () {
      expect(initialPoseTopic('/pinky_03'), '/pinky_03/initialpose');
      expect(initialPoseTopic('/pinky_03/'), '/pinky_03/initialpose');
    });

    test('네임스페이스가 없으면 루트다', () {
      expect(initialPoseTopic(''), '/initialpose');
      expect(initialPoseTopic('   '), '/initialpose');
    });
  });

  group('보낼 수 있는가', () {
    test('실물 이동 로봇이 자리를 골랐고 지도에 있으면 보낸다', () {
      final readiness = checkInitialPoseReadiness(
        robot: pinky(),
        worldKnown: true,
      );
      expect(readiness, InitialPoseReadiness.ready);
      expect(canSendInitialPose(readiness), isTrue);
      expect(initialPoseBlockedReason(readiness), isNull);
    });

    test('Gazebo 로봇에도 같은 길을 쓴다', () {
      expect(
        checkInitialPoseReadiness(
          robot: pinky(dataSource: RobotDataSource.gazebo),
          worldKnown: true,
        ),
        InitialPoseReadiness.ready,
      );
    });

    test('Mock 로봇은 보낼 상대가 없다', () {
      final readiness = checkInitialPoseReadiness(
        robot: pinky(dataSource: RobotDataSource.mock),
        worldKnown: true,
      );
      expect(readiness, InitialPoseReadiness.mockRobot);
      expect(canSendInitialPose(readiness), isFalse);
      expect(initialPoseBlockedReason(readiness), isNotNull);
    });

    test('설치 로봇은 AMCL 이 없다', () {
      expect(
        checkInitialPoseReadiness(
          robot: pinky(kind: RmfRobotKind.workcell),
          worldKnown: true,
        ),
        InitialPoseReadiness.notMobile,
      );
    });

    test('자리를 안 골랐으면 보낼 좌표가 없다', () {
      expect(
        checkInitialPoseReadiness(robot: pinky(charger: ''), worldKnown: true),
        InitialPoseReadiness.noStation,
      );
    });

    /// 여기서 0,0 을 보내면 로봇은 자기가 지도 원점에 있다고 믿는다. 그 상태로
    /// 경로를 짜면 벽을 뚫고 가려 든다. 모르면 안 보내는 것이 맞다.
    test('지도에서 자리를 못 찾으면 안 보낸다', () {
      final readiness = checkInitialPoseReadiness(
        robot: pinky(),
        worldKnown: false,
      );
      expect(readiness, InitialPoseReadiness.stationNotOnMap);
      expect(canSendInitialPose(readiness), isFalse);
    });

    test('못 보내는 까닭은 모두 사람이 읽을 말이 있다', () {
      for (final readiness in InitialPoseReadiness.values) {
        if (readiness == InitialPoseReadiness.ready) continue;
        expect(
          initialPoseBlockedReason(readiness),
          isNotNull,
          reason: '$readiness 에 까닭이 없다',
        );
      }
    });
  });

  /// 앱이 좌표를 보낸다고 로봇이 움직이지는 않는다. 사람이 이것을 "로봇을 그
  /// 자리로 보내는" 단추로 읽으면, 엉뚱한 곳에 있는 로봇에 좌표만 넣고 움직이기를
  /// 기다린다.
  group('보내기 전에 묻는다', () {
    final message = initialPoseConfirmMessage(
      robotLabel: 'pinky_03 · PK-03',
      stationName: '충전1',
      x: 1.869644,
      y: -1.622095,
      degrees: 180,
    );

    test('로봇이 안 움직인다고 먼저 밝힌다', () {
      expect(message, contains('움직이지 않습니다'));
    });

    test('어느 자리에 어느 방향으로 놓아야 하는지 적는다', () {
      expect(message, contains('충전1'));
      expect(message, contains('1.870'));
      expect(message, contains('-1.622'));
      // 라디안을 보여 주면 로봇을 어느 쪽으로 놓아야 할지 알 수 없다.
      expect(message, contains('180도'));
      expect(message, contains('도면 왼쪽'));
    });

    test('소수점 뒤가 0 이면 떼고 적는다', () {
      expect(
        initialPoseConfirmMessage(
          robotLabel: 'PK-03',
          stationName: '충전1',
          x: 0,
          y: 0,
          degrees: 90,
        ),
        contains('90도 (도면 위쪽)'),
      );
    });

    test('한 바퀴를 넘는 각도도 같은 쪽으로 읽는다', () {
      // 로봇 등록에 라디안으로 저장된 값이 도로 바뀌면서 360 을 넘길 수 있다.
      expect(
        initialPoseConfirmMessage(
          robotLabel: 'PK-03',
          stationName: '충전1',
          x: 0,
          y: 0,
          degrees: 540,
        ),
        contains('도면 왼쪽'),
      );
    });
  });

  /// 실패를 조용히 넘기면 사람은 보낸 줄 알고 다음 단계로 간다. 그때 로봇은
  /// 여전히 자기 자리를 모른다.
  group('보낸 뒤에 남기는 말', () {
    test('성공하면 무엇을 어디로 보냈는지 적는다', () {
      final sent = initialPoseSentMessage(
        robotLabel: 'PK-03',
        stationName: '충전1',
        topic: '/pinky_03/initialpose',
      );
      expect(sent, contains('충전1'));
      expect(sent, contains('/pinky_03/initialpose'));
    });

    test('실패하면 어디를 봐야 하는지 적는다', () {
      final failed = initialPoseFailedMessage(
        robotLabel: 'PK-03',
        topic: '/pinky_03/initialpose',
      );
      expect(failed, contains('못 보냈습니다'));
      expect(failed, contains('/pinky_03/initialpose'));
      // AMCL 이 안 떠 있으면 아무도 안 듣는다 — 가장 흔한 원인이다.
      expect(failed, contains('AMCL'));
    });
  });
}
