import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('시뮬레이션 작업 취소는 UI를 먼저 끝내고 최초 위치로 되돌린다', () {
    final source = File('lib/main.dart').readAsStringSync();
    final cancel = source.indexOf('Future<void> _cancelMockTask');
    final realRobotPath = source.indexOf('// RMF 를 먼저 세운다.', cancel);
    final immediate = source.substring(cancel, realRobotPath);

    expect(immediate, contains('immediateSimulation'));
    expect(immediate, contains('_MockTaskStatus.cancelled'));
    expect(immediate, contains('robot.position = initial'));
    expect(immediate, contains('resetGazeboRobotPose('));
    expect(immediate, contains('rosDomainId: _rosDomainId'));
    expect(immediate, contains('unawaited('));
    expect(immediate, contains('작업 최초 위치로 되돌렸습니다'));
  });

  test('Gazebo 복귀와 함께 AMCL initialpose도 갱신한다', () {
    final source = File('lib/gazebo_robot_reset_io.dart').readAsStringSync();

    // 토픽 이름은 `initialPoseTopic` 한 곳에서 만든다. 화면에 보여 주는 토픽과
    // 실제로 쏘는 토픽이 갈리지 않게 하려는 것이다.
    expect(source, contains('initialPoseTopic(namespace)'));
    expect(source, contains('PoseWithCovarianceStamped'));
    expect(source, contains(r"'ROS_DOMAIN_ID': '$rosDomainId'"));
    // Gazebo 를 못 옮겼으면 initialpose 도 안 보낸다. 모델은 옛 자리에 있는데
    // AMCL 만 새 자리로 옮기면 두 위치 체계가 갈린다.
    expect(source, contains('if (!moved) return false'));
    expect(source, contains('return publishInitialPose('));
  });

  /// 실물 로봇에는 Gazebo 가 없다. `resetGazeboRobotPose` 는 `set_pose` 가
  /// 성공해야만 initialpose 를 보내므로, 그 경로로는 실물에 영영 못 보낸다 —
  /// 실물이 이 기능을 가장 많이 필요로 하는데도 그랬다.
  test('initialpose 는 Gazebo 없이도 보낼 수 있다', () {
    final source = File('lib/gazebo_robot_reset_io.dart').readAsStringSync();
    final start = source.indexOf('Future<bool> publishInitialPose(');
    expect(start, greaterThanOrEqualTo(0));
    final body = source.substring(start);

    // 이 함수 안에서는 Gazebo 를 부르지 않는다.
    expect(body, isNot(contains('set_pose')));
    expect(body, isNot(contains("Process.run('gz'")));
    expect(body, contains('ros2 topic pub --once'));
  });

  test('두 판 모두 같은 이름의 함수를 내놓는다', () {
    // 조건부 import 로 갈리는 두 파일이 어긋나면, 웹에서만 컴파일이 깨진다.
    final stub = File('lib/gazebo_robot_reset_stub.dart').readAsStringSync();
    expect(stub, contains('Future<bool> publishInitialPose('));
    expect(stub, contains('required String namespace'));
  });

  test('상단 원위치는 모든 작업을 중지하고 작업맵과 Gazebo를 함께 되돌린다', () {
    final source = File('lib/main.dart').readAsStringSync();
    final start = source.indexOf('Future<void> _returnRobotsToSpawn()');
    final end = source.indexOf('Map<Offset, String> get _homeWaypoints', start);
    final method = source.substring(start, end);

    expect(method, contains('_MockTaskStatus.active'));
    expect(method, contains('_MockTaskStatus.queued'));
    expect(method, contains('_MockTaskStatus.cancelled'));
    expect(method, contains('buildCancelTaskRequest(taskId)'));
    expect(method, contains('..position = robot.spawnPosition'));
    expect(method, contains('resetGazeboRobotPose('));
    expect(method, contains('yaw: registered.spawnHeading'));
    expect(method, isNot(contains('_startQueuedOrderTasks()')));
  });
}
