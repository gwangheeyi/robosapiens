import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'robot_initial_pose.dart' show initialPoseTopic;

/// Gazebo 모델을 작업 시작 위치로 즉시 되돌린다.
Future<bool> resetGazeboRobotPose({
  required String modelName,
  required double x,
  required double y,
  required double yaw,
  required int rosDomainId,
}) async {
  final half = yaw / 2;
  final request =
      'name: ${_gzString(modelName)} '
      'position { x: $x y: $y z: 0.1 } '
      'orientation { z: ${math.sin(half)} w: ${math.cos(half)} }';
  try {
    final result = await Process.run('gz', [
      'service',
      '-s',
      '/world/sim_world/set_pose',
      '--reqtype',
      'gz.msgs.Pose',
      '--reptype',
      'gz.msgs.Boolean',
      '--timeout',
      '2000',
      '--req',
      request,
    ]).timeout(const Duration(seconds: 3));
    final moved =
        result.exitCode == 0 && '${result.stdout}'.contains('data: true');
    if (!moved) return false;

    // 운영맵은 Gazebo 모델 좌표가 아니라 AMCL→RMF 위치를 그린다. Gazebo만
    // 순간 이동시키면 AMCL은 취소 전 위치를 계속 내고, 앱의 지도도 곧 그 값으로
    // 되돌아간다. 같은 좌표를 initialpose로 넣어 두 위치 체계를 함께 맞춘다.
    return publishInitialPose(
      namespace: modelName,
      x: x,
      y: y,
      yaw: yaw,
      rosDomainId: rosDomainId,
    );
  } catch (_) {
    return false;
  }
}

/// AMCL 에게 "너는 지금 여기에 있다" 고 알린다.
///
/// [resetGazeboRobotPose] 에서 떼어 냈다. 거기서는 `gz service set_pose` 가
/// **성공해야만** 여기까지 왔다. 실물 로봇에는 Gazebo 가 없으니 그 경로로는
/// 영영 못 보낸다 — 실물이 이 기능을 가장 많이 필요로 하는데도 그랬다.
///
/// 좌표는 RMF 월드 기준(`map` 프레임)이다. Gazebo 모델 좌표와 같은 값이라
/// 시뮬레이션에서도 그대로 쓴다.
///
/// **이것은 로봇을 움직이지 않는다.** 보내는 것은 "여기에 있다" 는 말뿐이고,
/// 로봇이 실제로 다른 자리에 있으면 그 거짓말을 믿은 채로 경로를 짠다. 부르는
/// 쪽이 사람에게 먼저 확인받아야 한다.
Future<bool> publishInitialPose({
  required String namespace,
  required double x,
  required double y,
  required double yaw,
  required int rosDomainId,
}) async {
  final half = yaw / 2;
  // 공분산은 자리를 얼마나 믿는가다. 사람이 로봇을 그 자리에 놓고 누르는
  // 것이므로 좁게 준다 — 넓게 주면 AMCL 이 파티클을 멀리까지 뿌려, 비슷하게
  // 생긴 옆 통로로 수렴해 버린다.
  final message =
      '{header: {frame_id: map}, pose: {pose: {'
      'position: {x: $x, y: $y, z: 0.0}, '
      'orientation: {z: ${math.sin(half)}, w: ${math.cos(half)}}'
      '}, covariance: [0.01, 0, 0, 0, 0, 0, '
      '0, 0.01, 0, 0, 0, 0, '
      '0, 0, 0, 0, 0, 0, '
      '0, 0, 0, 0, 0, 0, '
      '0, 0, 0, 0, 0, 0, '
      '0, 0, 0, 0, 0, 0.01]}}';
  final topic = initialPoseTopic(namespace);
  try {
    // 토픽 이름과 메시지를 인자로 넘긴다. 문자열에 박아 넣으면 이름에 든
    // 따옴표가 셸을 빠져나간다.
    final result = await Process.run(
      'bash',
      [
        '-c',
        'source /opt/ros/jazzy/setup.bash; '
            'exec ros2 topic pub --once "\$1" '
            'geometry_msgs/msg/PoseWithCovarianceStamped "\$2"',
        'publish-initial-pose',
        topic,
        message,
      ],
      environment: {...Platform.environment, 'ROS_DOMAIN_ID': '$rosDomainId'},
    ).timeout(const Duration(seconds: 5));
    return result.exitCode == 0;
  } catch (_) {
    return false;
  }
}

String _gzString(String value) => '"${value.replaceAll('"', r'\"')}"';
