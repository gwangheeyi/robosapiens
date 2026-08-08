/// 화면에 보이는 로봇 값이 어디서 오는가.
///
/// 앱이 계산한 값과 실제 로봇에서 온 값은 같은 자리에 같은 모양으로 보인다.
/// 어느 쪽인지 모르고 보면 Mock 주행을 실물 상태로 착각한다. 작업 상세에서
/// 이것을 크게 드러내기 위한 규칙을 여기 모아 둔다.
library;

import 'rmf_project_config.dart';

export 'rmf_project_config.dart' show RobotDataSource;

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
