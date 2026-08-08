import 'package:flutter_test/flutter_test.dart';
import 'package:rmf_control_ui/rmf_project_config.dart';
import 'package:rmf_control_ui/robot_data_source.dart';

/// 작업 상세에 보이는 숫자가 어디서 온 것인지 가리는 규칙.
///
/// 앱이 계산한 값과 실물에서 온 값이 같은 자리에 같은 모양으로 보인다. 어느
/// 쪽인지 틀리게 알리면 Mock 주행을 실제 상태로 착각한다.
void main() {
  const pinky = RmfProjectRobot(
    robotId: 'PK-01',
    displayName: '핑키 1호',
    model: 'PINKY-GZ',
    gzName: 'pinky_01',
    zones: ['ambient'],
    chargerWaypoint: '충전1',
  );
  const omx = RmfProjectRobot(
    robotId: 'OMX-01',
    displayName: '매니퓰레이터 1호',
    model: 'open_manipulator_x',
    kind: RmfRobotKind.workcell,
    gzName: 'omx_01',
    zones: [],
    chargerWaypoint: 'OMX1',
  );

  group('출처 구분', () {
    test('Mock 만 토픽을 쓰지 않는다', () {
      expect(RobotDataSource.mock.usesTopics, isFalse);
      expect(RobotDataSource.gazebo.usesTopics, isTrue);
      expect(RobotDataSource.real.usesTopics, isTrue);
    });

    test('셋 다 서로 다른 이름을 가진다', () {
      final labels = RobotDataSource.values.map((s) => s.label).toSet();
      expect(labels.length, RobotDataSource.values.length);
    });
  });

  group('고른 방식과 실제 출처', () {
    test('구독이 없으면 무엇을 골랐든 값은 Mock 이다', () {
      // 이것이 핵심이다. Gazebo 를 골랐다는 이유로 Gazebo 값이라고 표시하면
      // 앱이 계산한 숫자를 실물로 착각하게 만든다.
      for (final selected in RobotDataSource.values) {
        expect(
          effectiveDataSource(selected: selected, topicsConnected: false),
          RobotDataSource.mock,
          reason: '$selected 를 골라도 구독이 없으면 Mock 이다',
        );
      }
    });

    test('구독이 붙으면 고른 방식이 그대로 출처가 된다', () {
      expect(
        effectiveDataSource(
          selected: RobotDataSource.gazebo,
          topicsConnected: true,
        ),
        RobotDataSource.gazebo,
      );
      expect(
        effectiveDataSource(
          selected: RobotDataSource.real,
          topicsConnected: true,
        ),
        RobotDataSource.real,
      );
    });

    test('어긋난 경우에만 경고한다', () {
      expect(
        dataSourceMismatch(
          selected: RobotDataSource.gazebo,
          topicsConnected: false,
        ),
        isTrue,
      );
      expect(
        dataSourceMismatch(
          selected: RobotDataSource.gazebo,
          topicsConnected: true,
        ),
        isFalse,
      );
      // Mock 을 골라 Mock 이 나오는 것은 어긋난 것이 아니다.
      expect(
        dataSourceMismatch(
          selected: RobotDataSource.mock,
          topicsConnected: false,
        ),
        isFalse,
      );
    });
  });

  group('토픽 이름', () {
    test('이동 로봇은 주행에 필요한 것을 모두 주고받는다', () {
      final topics = robotTopics(pinky);
      expect(topics.incoming, [
        '/pinky_01/odom',
        '/pinky_01/scan',
        '/pinky_01/joint_states',
      ]);
      expect(topics.outgoing, ['/pinky_01/cmd_vel']);
    });

    test('설치 로봇은 관절 상태만 온다', () {
      // 바퀴도 LiDAR 도 없다. 있지도 않은 토픽을 알려주면 없는 것을 찾게 된다.
      final topics = robotTopics(omx);
      expect(topics.incoming, ['/omx_01/joint_states']);
      expect(topics.outgoing, isEmpty);
    });

    test('등록 정보가 없으면 아무 이름도 지어내지 않는다', () {
      final topics = robotTopics(null);
      expect(topics.incoming, isEmpty);
      expect(topics.outgoing, isEmpty);
    });

    test('다리 설정에 실제로 있는 이름만 알려 준다', () {
      // 화면과 <맵이름>_gz_bridge.yaml 이 다르면, 있는 줄 알고 찾다가 못 찾는다.
      final bridge = buildProjectGzBridgeYaml(
        mapName: 'gwanghee',
        robots: const [pinky, omx],
      );
      for (final robot in const [pinky, omx]) {
        final topics = robotTopics(robot);
        for (final topic in [...topics.incoming, ...topics.outgoing]) {
          expect(
            bridge,
            contains('ros_topic_name: "$topic"'),
            reason: '$topic 이 다리 설정에 없다',
          );
        }
      }
    });
  });
}
