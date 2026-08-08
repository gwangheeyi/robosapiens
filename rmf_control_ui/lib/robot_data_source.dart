/// 화면에 보이는 로봇 값이 어디서 오는가.
///
/// 앱이 계산한 값과 실제 로봇에서 온 값은 같은 자리에 같은 모양으로 보인다.
/// 어느 쪽인지 모르고 보면 Mock 주행을 실물 상태로 착각한다. 작업 상세에서
/// 이것을 크게 드러내기 위한 규칙을 여기 모아 둔다.
library;

import 'rmf_project_config.dart';

enum RobotDataSource {
  /// 앱이 100ms 마다 직접 계산한 값. ROS 는 아예 관여하지 않는다.
  mock,

  /// Gazebo 가 물리를 돌리고 그 결과가 ROS 토픽으로 온다.
  gazebo,

  /// 실물 로봇에서 온 ROS 토픽.
  real;

  String get label => switch (this) {
    RobotDataSource.mock => '앱 Mock 데이터',
    RobotDataSource.gazebo => 'Gazebo 시뮬레이션',
    RobotDataSource.real => '실제 로봇',
  };

  /// 로봇 화면의 `로봇 실행 방식` 에 쓰는 짧은 이름.
  String get shortLabel => switch (this) {
    RobotDataSource.mock => '앱 Mock',
    RobotDataSource.gazebo => 'Gazebo 시뮬레이션',
    RobotDataSource.real => '실제 로봇',
  };

  /// 이 값이 무엇인지 한 줄로.
  String get summary => switch (this) {
    RobotDataSource.mock => '앱이 계산한 값입니다. 실제 로봇도 Gazebo도 아닙니다.',
    RobotDataSource.gazebo => 'Gazebo가 물리를 돌리고 그 결과를 ROS 토픽으로 주고받습니다.',
    RobotDataSource.real => '실물 로봇이 보내는 ROS 토픽입니다.',
  };

  /// ROS 토픽을 주고받는가. Mock 은 앱 안에서만 돈다.
  bool get usesTopics => this != RobotDataSource.mock;
}

/// 고른 실행 방식과 실제로 값을 만들어 낸 곳은 다를 수 있다.
///
/// Gazebo 를 골라 놓아도 앱이 그 토픽을 구독하지 않으면 화면의 숫자는 여전히
/// 앱이 계산한 값이다. 그것을 Gazebo 라고 표시하면 이 표시가 거짓말이 된다.
RobotDataSource effectiveDataSource({
  required RobotDataSource selected,
  required bool topicsConnected,
}) => topicsConnected ? selected : RobotDataSource.mock;

/// 고른 방식과 실제 출처가 어긋나 있는가. 어긋나면 반드시 밝혀야 한다.
bool dataSourceMismatch({
  required RobotDataSource selected,
  required bool topicsConnected,
}) => selected != RobotDataSource.mock && !topicsConnected;

/// 이 로봇이 주고받는 ROS 토픽. 등록한 gz 이름이 네임스페이스가 된다.
///
/// `<맵이름>_gz_bridge.yaml` 이 다리를 놓는 이름과 같아야 한다. 여기서만
/// 다르게 적으면 화면에는 있는데 실제로는 없는 토픽을 알려주게 된다.
///
/// 설치 로봇은 바퀴도 LiDAR 도 없어 관절 상태만 오간다.
({List<String> incoming, List<String> outgoing}) robotTopics(
  RmfProjectRobot? robot,
) {
  if (robot == null) return (incoming: const [], outgoing: const []);
  final ns = '/${robot.gzName}';
  if (!robot.isMobile) {
    return (incoming: ['$ns/joint_states'], outgoing: const <String>[]);
  }
  return (
    incoming: ['$ns/odom', '$ns/scan', '$ns/joint_states'],
    outgoing: ['$ns/cmd_vel'],
  );
}
