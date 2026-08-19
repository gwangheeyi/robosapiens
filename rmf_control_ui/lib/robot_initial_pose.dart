/// 로봇에게 "너는 지금 여기에 있다" 고 알려 주는 규칙.
///
/// AMCL 은 `map → odom` 을 스스로 못 찾는다. 파티클을 어디에 뿌릴지 처음 한 번은
/// 사람이 알려 줘야 하고, 그 뒤로는 라이다와 오도메트리로 따라간다. 배포할 때
/// `nav2_params.yaml` 의 `initial_pose` 에 자리 좌표를 박아 넣는 것이 그 한 번이다.
///
/// 그런데 그것은 **Nav2 를 처음 띄울 때만** 듣는다. 로봇을 손으로 들어 옮겼거나
/// 미끄러져 위치를 잃으면 다시 알려 줘야 하는데, 그러자고 배포를 다시 하고
/// Nav2 를 재시작할 수는 없다. 그래서 `/<네임스페이스>/initialpose` 로 같은
/// 값을 다시 보낸다.
///
/// Gazebo 로봇에는 이미 그 길이 있었다(`resetGazeboRobotPose`). 다만 거기서는
/// `gz service set_pose` 로 모델을 순간 이동시킨 **뒤에** initialpose 를 보내고,
/// 앞 단계가 실패하면 뒤도 안 보낸다. 실물 로봇에는 Gazebo 가 없으니 그 경로로는
/// 영영 못 보낸다 — 실물이 이 기능을 가장 많이 필요로 하는데도 그랬다.
///
/// 판정을 화면에서 떼어 둔 것은 [RobotLink] 와 같은 이유다 — 규칙은 눌러 보지
/// 않고도 확인할 수 있어야 한다.
library;

import 'rmf_project_config.dart';

/// AMCL 이 초기 위치를 듣는 토픽. 로봇의 네임스페이스 아래다.
///
/// Nav2 를 네임스페이스로 띄우면 AMCL 도 그 아래로 들어간다. 루트
/// `/initialpose` 로 보내면 아무도 안 듣는다 — 오류도 안 난다. 이름을 한 곳에서
/// 만들어 두면 화면에 보여 주는 토픽과 실제로 쏘는 토픽이 갈리지 않는다.
String initialPoseTopic(String namespace) {
  final trimmed = namespace.trim().replaceAll(RegExp(r'^/+|/+$'), '');
  return trimmed.isEmpty ? '/initialpose' : '/$trimmed/initialpose';
}

/// 초기 위치를 보낼 수 있는가. 못 보내면 왜 못 보내는가.
enum InitialPoseReadiness {
  /// 보낼 수 있다.
  ready,

  /// Mock 로봇이다. 앱 안에만 있어서 보낼 상대가 없다.
  mockRobot,

  /// 설치 로봇(팔)이다. 바퀴도 라이다도 없어 AMCL 자체가 없다.
  notMobile,

  /// 자리 Waypoint 를 안 골랐다. 보낼 좌표가 없다.
  noStation,

  /// 자리는 골랐는데 지도에서 그 자리를 못 찾았다.
  ///
  /// 지도를 아직 안 불러왔거나, 자리 이름을 고쳐서 짝이 끊어졌다. 여기서 0,0 을
  /// 보내면 로봇은 자기가 지도 원점에 있다고 믿고, 그 상태로 경로를 짜면 벽을
  /// 뚫고 가려 든다. 모르면 안 보내는 것이 맞다.
  stationNotOnMap,
}

/// 초기 위치를 보낼 수 있는지 본다.
///
/// [worldKnown] 은 자리 Waypoint 의 RMF 월드 좌표를 구했는가다. 축척을 안
/// 재었거나 그 이름의 Waypoint 가 지도에 없으면 거짓이다.
InitialPoseReadiness checkInitialPoseReadiness({
  required RmfProjectRobot robot,
  required bool worldKnown,
}) {
  if (!robot.dataSource.usesTopics) return InitialPoseReadiness.mockRobot;
  if (!robot.isMobile) return InitialPoseReadiness.notMobile;
  if ((robot.chargerWaypoint ?? '').trim().isEmpty) {
    return InitialPoseReadiness.noStation;
  }
  if (!worldKnown) return InitialPoseReadiness.stationNotOnMap;
  return InitialPoseReadiness.ready;
}

/// 단추를 누를 수 있는가.
bool canSendInitialPose(InitialPoseReadiness readiness) =>
    readiness == InitialPoseReadiness.ready;

/// 못 누르는 까닭. 누를 수 있으면 null.
///
/// 흐린 단추만 두면 사람이 다른 칸을 뒤진다. 무엇이 빠졌는지 그 자리에서
/// 밝힌다.
String? initialPoseBlockedReason(InitialPoseReadiness readiness) =>
    switch (readiness) {
      InitialPoseReadiness.ready => null,
      InitialPoseReadiness.mockRobot =>
        'Mock 로봇은 앱 안에서만 움직입니다. 보낼 상대가 없습니다.',
      InitialPoseReadiness.notMobile =>
        '설치 로봇은 스스로 움직이지 않아 AMCL 이 없습니다.',
      InitialPoseReadiness.noStation =>
        '자리 Waypoint 를 안 골랐습니다. 로봇 등록에서 자리를 고르면 '
            '그 좌표를 보냅니다.',
      InitialPoseReadiness.stationNotOnMap =>
        '지도에서 그 자리를 못 찾았습니다. 맵을 불러왔는지, 자리 이름이 '
            '지도의 Waypoint 이름과 같은지 확인해 주세요.',
    };

/// 보내기 전에 사람에게 확인받을 말.
///
/// **앱이 좌표를 보낸다고 로봇이 움직이지는 않는다.** 보내는 것은 "너는 지금
/// 여기에 있다" 는 말뿐이고, 로봇이 실제로 다른 자리에 있으면 그 거짓말을 믿은
/// 채로 경로를 짠다. 그래서 누르기 전에 로봇을 그 자리에 그 방향으로 놓아야
/// 한다 — 이 순서를 안 지키면 지도 위 로봇과 실제 로봇이 벌어진다.
///
/// [degrees] 는 사람이 읽을 도 단위다. 라디안을 보여 주면 로봇을 어느 쪽으로
/// 놓아야 할지 알 수 없다.
String initialPoseConfirmMessage({
  required String robotLabel,
  required String stationName,
  required double x,
  required double y,
  required double degrees,
}) =>
    '$robotLabel 을 $stationName 에 놓았습니까?\n\n'
    '  자리   x ${x.toStringAsFixed(3)} · y ${y.toStringAsFixed(3)}\n'
    '  방향   ${_degreesLabel(degrees)}도 (${_compass(degrees)})\n\n'
    '보내는 것은 좌표뿐입니다 — 로봇은 움직이지 않습니다. 실제 로봇이 이 자리에 '
    '이 방향으로 놓여 있어야 합니다. 어긋난 채로 보내면 로봇은 자기가 여기 '
    '있다고 믿고, 그 자리에서 벽을 뚫는 경로를 짭니다.';

/// 보낸 뒤에 남길 말. 무엇을 어디로 보냈는지 그대로 적는다.
String initialPoseSentMessage({
  required String robotLabel,
  required String stationName,
  required String topic,
}) =>
    '$robotLabel 의 초기 위치를 $stationName 으로 보냈습니다 ($topic). '
    'AMCL 이 이 자리에서 파티클을 다시 뿌립니다.';

/// 못 보냈을 때 남길 말.
///
/// 실패를 조용히 넘기면 사람은 보낸 줄 알고 다음 단계로 간다. 그때 로봇은
/// 여전히 자기 자리를 모른다.
String initialPoseFailedMessage({
  required String robotLabel,
  required String topic,
}) =>
    '$robotLabel 의 초기 위치를 못 보냈습니다 ($topic).\n\n'
    'ROS 도메인이 로봇과 같은지, 로봇의 Nav2 가 떠 있는지 확인해 주세요. '
    'AMCL 이 안 떠 있으면 이 토픽을 아무도 안 듣습니다.';

/// 각도를 사람이 읽을 글자로. 소수점 뒤가 0 이면 떼어 낸다.
String _degreesLabel(double degrees) {
  final text = degrees.toStringAsFixed(1);
  return text.endsWith('.0') ? text.substring(0, text.length - 2) : text;
}

/// 각도만 보고는 어느 쪽인지 잘 모른다. 도면 기준으로 풀어 준다.
///
/// `_dockHeadingHint` 와 같은 갈래를 쓴다. 두 곳이 다른 말을 하면 사람이 어느
/// 쪽을 믿어야 할지 모른다.
String _compass(double degrees) {
  final wrapped = ((degrees % 360) + 540) % 360 - 180;
  return switch (wrapped) {
    > -45 && <= 45 => '도면 오른쪽',
    > 45 && <= 135 => '도면 위쪽',
    > -135 && <= -45 => '도면 아래쪽',
    _ => '도면 왼쪽',
  };
}
