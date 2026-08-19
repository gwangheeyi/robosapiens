/// 로봇을 몇 cm 만 앞뒤로 밀거나 제자리에서 조금 돌린다.
///
/// 자리를 눈으로 맞추는 일에 쓴다 — 충전 단자가 살짝 어긋났거나, 도킹 위치가
/// 몇 cm 모자랄 때다. 작업을 내면 RMF 가 경로를 짜고 도착 반경 안에만 들면
/// 끝내므로, 그보다 작은 조정은 할 수 없다.
///
/// **Nav2 의 action 을 쓴다.** `cmd_vel` 을 직접 쏘아 시간으로 거리를 맞출 수도
/// 있지만, 그러면 바닥 마찰과 배터리 전압에 따라 실제로 간 거리가 달라진다.
/// 배터리가 6.5V 까지 내려간 로봇에서는 눈에 띄게 밀린다. action 은 오도메트리로
/// 거리를 재고 costmap 을 보므로, 앞에 뭐가 있으면 멈춘다.
///
/// 그 대가로 **Nav2 가 active 여야 한다.** 브링업만 떠 있으면 못 쓴다 — 그때는
/// 왜 못 쓰는지 알려 준다.
///
/// 판정을 화면에서 떼어 둔 것은 [RobotLink] 와 같은 이유다 — 규칙은 눌러 보지
/// 않고도 확인할 수 있어야 한다.
library;

import 'rmf_project_config.dart';

/// 한 번에 밀 수 있는 최대 거리 [m].
///
/// 미세조종은 눈으로 보며 맞추는 일이다. 크게 주면 작업으로 보내는 것과 다를
/// 바 없고, 그쪽은 경로와 교통 관리를 거친다 — 여기는 그런 것이 없으므로
/// **눈이 닿는 거리**로 묶는다.
const double nudgeMaxMeters = 0.5;

/// 한 번에 돌릴 수 있는 최대 각도 [도].
const double nudgeMaxDegrees = 90;

/// 미세조종 속도 [m/s]. 사람이 옆에서 보고 있는 상황이라 느리게 간다.
const double nudgeSpeed = 0.05;

/// 미세조종 회전 속도 [rad/s].
const double nudgeAngularSpeed = 0.3;

/// 무엇을 시킬 것인가.
enum NudgeKind {
  /// 코가 향한 쪽으로 민다.
  forward,

  /// 뒤로 뺀다.
  backward,

  /// 왼쪽으로 돈다(반시계).
  turnLeft,

  /// 오른쪽으로 돈다(시계).
  turnRight,
}

/// 미세조종을 할 수 있는가. 못 하면 왜 못 하는가.
enum NudgeReadiness {
  ready,

  /// Mock 로봇이다. 앱 안에만 있어서 보낼 상대가 없다.
  mockRobot,

  /// 설치 로봇이다. 스스로 움직이지 않는다.
  notMobile,

  /// Nav2 가 안 떠 있거나 다 안 켜졌다.
  ///
  /// action server 가 없으면 목표를 보내도 아무도 안 받는다. 오류도 안 난다 —
  /// 그냥 응답이 없다.
  nav2NotReady,

  /// 지금 작업 중이다.
  ///
  /// RMF 가 로봇을 몰고 있는데 옆에서 밀면, 두 명령이 서로 당긴다. RMF 는
  /// 제가 보낸 경로대로 가고 있다고 믿는 채로 어긋난다.
  busy,
}

/// 미세조종을 할 수 있는지 본다.
NudgeReadiness checkNudgeReadiness({
  required RmfProjectRobot robot,
  required bool nav2Ready,
  required bool hasActiveTask,
}) {
  if (!robot.dataSource.usesTopics) return NudgeReadiness.mockRobot;
  if (!robot.isMobile) return NudgeReadiness.notMobile;
  if (hasActiveTask) return NudgeReadiness.busy;
  if (!nav2Ready) return NudgeReadiness.nav2NotReady;
  return NudgeReadiness.ready;
}

bool canNudge(NudgeReadiness readiness) => readiness == NudgeReadiness.ready;

/// 못 하는 까닭. 할 수 있으면 null.
String? nudgeBlockedReason(NudgeReadiness readiness) => switch (readiness) {
  NudgeReadiness.ready => null,
  NudgeReadiness.mockRobot => 'Mock 로봇은 앱 안에서만 움직입니다.',
  NudgeReadiness.notMobile => '설치 로봇은 자리를 옮길 수 없습니다.',
  NudgeReadiness.nav2NotReady =>
    'Nav2 가 준비되지 않았습니다. 백엔드를 띄우고 노드가 모두 active 인지 '
        '확인해 주세요 — action server 가 없으면 보내도 아무 일이 안 '
        '일어납니다.',
  NudgeReadiness.busy =>
    '작업 중입니다. 옆에서 밀면 RMF 가 보낸 경로와 어긋납니다 — 작업을 '
        '멈춘 뒤에 조정해 주세요.',
};

/// 사람이 친 거리를 읽는다 [cm → m].
///
/// 빈 칸과 못 읽는 글자를 가른다. 빈 칸은 "아직 안 넣음" 이고 못 읽는 글자는
/// **잘못**이다 — 둘을 같이 다루면 오타가 조용히 0 이 된다.
({String? error, double? meters}) parseNudgeCentimeters(String text) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) return (error: null, meters: null);
  final value = double.tryParse(trimmed.replaceAll(',', '.'));
  if (value == null || !value.isFinite) {
    return (error: '숫자로 적어 주세요. 예: 5, 12.5', meters: null);
  }
  if (value <= 0) return (error: '0 보다 큰 값을 적어 주세요.', meters: null);
  final meters = value / 100;
  if (meters > nudgeMaxMeters) {
    return (
      error:
          '한 번에 ${(nudgeMaxMeters * 100).toStringAsFixed(0)}cm 까지만 '
          '움직입니다. 더 가려면 작업으로 보내세요.',
      meters: null,
    );
  }
  return (error: null, meters: meters);
}

/// 사람이 친 각도를 읽는다 [도].
({String? error, double? degrees}) parseNudgeDegrees(String text) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) return (error: null, degrees: null);
  final value = double.tryParse(trimmed.replaceAll(',', '.'));
  if (value == null || !value.isFinite) {
    return (error: '숫자로 적어 주세요. 예: 15, 90', degrees: null);
  }
  if (value <= 0) return (error: '0 보다 큰 값을 적어 주세요.', degrees: null);
  if (value > nudgeMaxDegrees) {
    return (
      error:
          '한 번에 ${nudgeMaxDegrees.toStringAsFixed(0)}도 까지만 '
          '돌립니다.',
      degrees: null,
    );
  }
  return (error: null, degrees: value);
}

/// 이 조정이 쓰는 Nav2 action 이름.
///
/// 뒤로 가는 것은 `backup` 이 맡는다. `drive_on_heading` 에 음수를 주면 Nav2 가
/// 거절한다 — 그쪽은 앞으로만 간다.
String nudgeActionName(String namespace, NudgeKind kind) {
  final ns = namespace.trim().replaceAll(RegExp(r'^/+|/+$'), '');
  final action = switch (kind) {
    NudgeKind.forward => 'drive_on_heading',
    NudgeKind.backward => 'backup',
    NudgeKind.turnLeft || NudgeKind.turnRight => 'spin',
  };
  return ns.isEmpty ? '/$action' : '/$ns/$action';
}

/// action 의 형식 이름.
String nudgeActionType(NudgeKind kind) => switch (kind) {
  NudgeKind.forward => 'nav2_msgs/action/DriveOnHeading',
  NudgeKind.backward => 'nav2_msgs/action/BackUp',
  NudgeKind.turnLeft || NudgeKind.turnRight => 'nav2_msgs/action/Spin',
};

/// action 에 넣을 목표.
///
/// **거리는 언제나 양수다.** `backup` 도 양수를 받아 뒤로 간다 — 방향은 action
/// 이 정하지 값이 정하지 않는다. 음수를 넣으면 Nav2 가 거절한다.
///
/// [timeAllowanceSeconds] 를 넉넉히 준다. 거리에 견줘 짧게 주면 다 가기도 전에
/// 시간이 끝나 실패로 답한다 — 로봇은 도중에 멈춰 있는데 화면은 실패라고만
/// 말한다.
String nudgeGoalYaml({
  required NudgeKind kind,
  required double meters,
  required double degrees,
}) {
  switch (kind) {
    case NudgeKind.forward:
    case NudgeKind.backward:
      final seconds = _timeAllowance(meters / nudgeSpeed);
      return '{target: {x: ${meters.toStringAsFixed(3)}, y: 0.0, z: 0.0}, '
          'speed: ${nudgeSpeed.toStringAsFixed(3)}, '
          'time_allowance: {sec: $seconds, nanosec: 0}}';
    case NudgeKind.turnLeft:
    case NudgeKind.turnRight:
      // Spin 은 부호로 방향을 정한다. 반시계가 +.
      final radians =
          degrees * 3.141592653589793 / 180 *
          (kind == NudgeKind.turnLeft ? 1 : -1);
      final seconds = _timeAllowance(radians.abs() / nudgeAngularSpeed);
      return '{target_yaw: ${radians.toStringAsFixed(4)}, '
          'time_allowance: {sec: $seconds, nanosec: 0}}';
  }
}

/// 걸릴 시간에 여유를 얹는다. 최소 10초.
int _timeAllowance(double estimatedSeconds) {
  final padded = estimatedSeconds * 3 + 5;
  return padded < 10 ? 10 : padded.ceil();
}

/// 무엇을 시켰는지 사람이 읽을 말.
String nudgeLabel({
  required NudgeKind kind,
  required double meters,
  required double degrees,
}) => switch (kind) {
  NudgeKind.forward => '앞으로 ${_cm(meters)}cm',
  NudgeKind.backward => '뒤로 ${_cm(meters)}cm',
  NudgeKind.turnLeft => '왼쪽으로 ${_deg(degrees)}도',
  NudgeKind.turnRight => '오른쪽으로 ${_deg(degrees)}도',
};

String _cm(double meters) => _trim(meters * 100);
String _deg(double degrees) => _trim(degrees);

String _trim(double value) {
  final text = value.toStringAsFixed(1);
  return text.endsWith('.0') ? text.substring(0, text.length - 2) : text;
}

/// 보낸 뒤에 남길 말.
String nudgeSentMessage({required String robotLabel, required String what}) =>
    '$robotLabel 을 $what 움직였습니다.';

/// 못 보냈을 때 남길 말.
///
/// action 이 거절하는 까닭이 여럿이라, 무엇을 봐야 하는지 갈라 주지 않으면
/// 어디부터 볼지 모른다.
String nudgeFailedMessage({
  required String robotLabel,
  required String what,
  required String detail,
}) =>
    '$robotLabel 을 $what 움직이지 못했습니다.\n\n'
    '$detail\n\n'
    '· Nav2 의 behavior_server 가 active 인지\n'
    '· 가려는 쪽에 벽이나 장애물이 있는지 — costmap 에 걸리면 멈춥니다\n'
    '· 로봇이 제 자리를 아는지 (map → odom TF)';
