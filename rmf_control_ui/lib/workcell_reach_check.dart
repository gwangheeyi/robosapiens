/// 로봇팔이 뻗는 자리와 핑키 본체가 부딪히는지 미리 본다.
///
/// 픽업은 **두 로봇이 같은 자리를 나눠 쓰는** 유일한 순간이다. 핑키가 자리에
/// 서고, 고정된 팔이 그 위로 뻗는다. 자리를 조금만 잘못 잡으면 팔이 수납함이
/// 아니라 본체를 친다 — 그때는 이미 부딪힌 뒤라 무를 수 없다.
///
/// 그래서 작업을 실행하기 **전에** 자리와 각도만 보고 판정한다. 여기서 하는
/// 것은 기하 계산뿐이고, 값은 전부 밖에서 받는다(등록의 spawn, 맵의 Waypoint,
/// 적재 방향, 플릿의 footprint).
library;

import 'dart:math' as math;

/// 핑키가 수납함을 달고 있는 자리. 로봇 중심에서 **뒤로** 이만큼 [m].
///
/// `nav2_params.dart` 의 도착 각도 계산이 쓰는 값과 같다 — 거기서는 이 30cm
/// 때문에 5도만 틀어져도 수납함이 2.6cm 옆으로 간다고 적어 두었다.
const double pinkyTrayOffsetMeters = .30;

/// 팔이 쓸어내는 자리 밖에 더 남겨야 하는 여유 [m].
///
/// **아직 안 잰 값이다.** 핑키가 Waypoint 한가운데 정확히 서지 않는 만큼에 손을
/// 얹은 어림이다. 실물로 재서 고칠 때는 이 상수 하나만 고치면 된다.
const double armBodyClearanceMeters = .05;

/// 모델별로 팔이 **실제로 쓸어내는** 최대 수평 반경 [m].
///
/// 닿는 거리([workcellArmReachMeters])와 다르다. 그쪽은 "저기까지 닿을 수
/// 있는가" 이고, 이것은 "가만히 둬도 저기를 지나가는가" 다. 부딪히는 것은
/// 뒤쪽이다.
///
/// 생성되는 workcell 노드의 `POLICY_MOTIONS` 는 IK 를 풀지 않는다. 수납함이
/// 어디 있든 **정해진 관절 각도** 로 움직이므로, 팔은 픽업 때마다 늘 같은
/// 반경을 쓸어낸다. 그 반경 안에 핑키 본체가 있으면 수납함이 아니라 본체를
/// 친다.
///
/// 값은 `POLICY_MOTIONS` 의 모든 자세를 URDF 링크 길이로 정기구학을 풀어
/// 가장 먼 것을 골랐다(omx_f 0.319m · open_manipulator_x 0.288m). policy 자세를
/// 고치면 이 값도 함께 고쳐야 한다.
const Map<String, double> workcellArmSweepMeters = {
  'open_manipulator_x': .29,
  'omx_f': .32,
};

/// 모르는 모델은 가장 크게 쓸어내는 팔로 본다. 작게 잡으면 부딪히는 자리를
/// 통과시킨다 — [defaultArmReachMeters] 와 안전한 방향이 반대다.
const double defaultArmSweepMeters = .32;

double armSweepOf(String model) =>
    workcellArmSweepMeters[model] ?? defaultArmSweepMeters;

/// 모델별로 팔이 닿는 거리 [m].
///
/// `workcellReachMeters`(짝짓기용 0.8m)와 다르다. 그쪽은 "이 설비가 저 자리를
/// 맡는가" 를 헐겁게 보는 값이고, 이것은 "정말 닿는가" 를 보는 값이다.
const Map<String, double> workcellArmReachMeters = {
  'open_manipulator_x': .38,
  'omx_f': .45,
};

/// 모르는 모델은 가장 짧은 팔로 본다. 넉넉히 잡으면 못 닿는 자리를 통과시킨다.
const double defaultArmReachMeters = .38;

double armReachOf(String model) =>
    workcellArmReachMeters[model] ?? defaultArmReachMeters;

/// 무엇이 위험한가.
enum WorkcellReachRisk {
  /// 자리와 각도가 다 맞다.
  ok,

  /// 본체가 팔 기둥에 너무 가깝다. 부딪힌다.
  bodyTooClose,

  /// 수납함이 팔 반대편에 온다. 팔이 본체 위로 넘어가야 한다.
  trayBehindBody,

  /// 수납함이 팔 작업 반경 밖이다. 헛집는다.
  trayOutOfReach,

  /// 적재 방향을 안 정해 어느 쪽을 볼지 모른다.
  unknownHeading,
}

/// 자리 하나를 본 결과.
class WorkcellReachCheck {
  const WorkcellReachCheck({
    required this.risk,
    required this.station,
    required this.workcellId,
    required this.bodyEdgeDistance,
    required this.centerDistance,
    required this.trayDistance,
    required this.reach,
    required this.sweep,
    required this.needed,
  });

  final WorkcellReachRisk risk;

  /// 픽업 자리 이름. 경고에 그대로 적는다 — 어느 Waypoint 를 고칠지 알아야 한다.
  final String station;

  final String workcellId;

  /// 팔 밑동에서 본체 **겉면**까지 [m].
  final double bodyEdgeDistance;

  /// 팔 밑동에서 본체 **중심**(로봇이 서는 자리)까지 [m].
  final double centerDistance;

  /// 팔 밑동에서 수납함까지 [m].
  final double trayDistance;

  /// 이 팔이 닿는 거리 [m].
  final double reach;

  /// 이 팔이 policy 동작에서 쓸어내는 반경 [m].
  final double sweep;

  /// 고치려면 얼마나 움직여야 하는가 [m]. 방향 문제면 0이다.
  final double needed;

  /// 부딪힐 수 있는가. 실행 전에 사람을 세워야 하는 것들이다.
  bool get isDanger =>
      risk == WorkcellReachRisk.bodyTooClose ||
      risk == WorkcellReachRisk.trayBehindBody;

  bool get isProblem => risk != WorkcellReachRisk.ok;

  String get title => switch (risk) {
    WorkcellReachRisk.ok => '이상 없음',
    WorkcellReachRisk.bodyTooClose => '핑키 본체와 로봇팔이 부딪힐 위험',
    WorkcellReachRisk.trayBehindBody => '팔이 핑키 본체 위로 넘어가야 함',
    WorkcellReachRisk.trayOutOfReach => '팔이 수납함에 닿지 않음',
    WorkcellReachRisk.unknownHeading => '적재 방향을 안 정함',
  };

  /// 무엇을 재서 그렇게 보았는가.
  String get detail => switch (risk) {
    WorkcellReachRisk.ok =>
      '$workcellId 에서 수납함까지 ${_m(trayDistance)}m '
          '(작업 반경 ${_m(reach)}m), 본체 겉까지 ${_m(bodyEdgeDistance)}m',
    WorkcellReachRisk.bodyTooClose =>
      '$workcellId 밑동에서 핑키 본체 겉까지 ${_m(bodyEdgeDistance)}m '
          '(본체 중심 ${_m(centerDistance)}m) 뿐인데, 팔은 policy 동작에서 '
          '${_m(sweep)}m 까지 쓸어냅니다 — 본체가 그 안에 들어갑니다',
    WorkcellReachRisk.trayBehindBody =>
      '수납함이 본체보다 멀리 옵니다 — 본체 중심 ${_m(centerDistance)}m, '
          '수납함 ${_m(trayDistance)}m',
    WorkcellReachRisk.trayOutOfReach =>
      '수납함까지 ${_m(trayDistance)}m 인데 $workcellId 은 ${_m(reach)}m 까지만 '
          '닿습니다',
    WorkcellReachRisk.unknownHeading =>
      '$station 에 적재 방향이 없습니다. 들어온 그대로 서면 수납함이 팔에서 '
          '가장 먼 자리에 옵니다',
  };

  /// 사람이 무엇을 하면 되는가.
  String get advice => switch (risk) {
    WorkcellReachRisk.ok => '',
    WorkcellReachRisk.bodyTooClose =>
      '맵 관리에서 $station Waypoint 를 $workcellId 에서 '
          '${_m(needed)}m 더 떨어뜨리세요.',
    WorkcellReachRisk.trayBehindBody =>
      '맵 관리에서 $station 의 적재 방향을 고치세요 — 핑키의 코가 $workcellId '
          '반대쪽을 봐야 수납함이 팔 쪽에 옵니다.',
    WorkcellReachRisk.trayOutOfReach =>
      '맵 관리에서 $station Waypoint 를 $workcellId 쪽으로 '
          '${_m(needed)}m 옮기세요.',
    WorkcellReachRisk.unknownHeading => '맵 관리에서 $station 의 적재 방향을 정하세요.',
  };

  static String _m(double value) => value.toStringAsFixed(2);
}

/// 자리 하나가 안전한지 본다.
///
/// 보는 것은 셋이고, 순서가 곧 위험한 차례다.
///
///   ① 본체가 팔이 쓸어내는 자리 안에 있는가 → 부딪힌다
///   ② 수납함이 팔 반대편에 오는가            → 팔이 본체 위로 넘어간다
///   ③ 수납함이 작업 반경 밖인가              → 헛집는다
WorkcellReachCheck checkWorkcellReach({
  required String workcellId,
  required String station,
  required double armX,
  required double armY,
  required double stationX,
  required double stationY,
  required double bodyRadius,
  required double reach,
  double? headingRadians,
  double sweep = defaultArmSweepMeters,
  double trayOffset = pinkyTrayOffsetMeters,
  double clearance = armBodyClearanceMeters,
}) {
  final centerDistance = _distance(armX, armY, stationX, stationY);
  final bodyEdge = centerDistance - bodyRadius;

  WorkcellReachCheck result(
    WorkcellReachRisk risk,
    double trayDistance,
    double needed,
  ) => WorkcellReachCheck(
    risk: risk,
    station: station,
    workcellId: workcellId,
    bodyEdgeDistance: bodyEdge,
    centerDistance: centerDistance,
    trayDistance: trayDistance,
    reach: reach,
    sweep: sweep,
    needed: needed,
  );

  // ① 각도를 몰라도 이것부터 본다. 본체가 팔이 지나가는 자리에 있으면 어느
  //    쪽을 보든 부딪힌다.
  //
  //    재는 것은 기둥 굵기가 아니라 **팔이 쓸어내는 반경** 이다. policy 동작은
  //    수납함을 겨냥하지 않고 정해진 관절 각도로만 움직이므로, 수납함이 아무리
  //    가까이 와도 팔은 늘 [sweep] 까지 나간다. 기둥만 보면 이 배치가 통과한다.
  final minBodyEdge = sweep + clearance;
  if (bodyEdge < minBodyEdge) {
    return result(
      WorkcellReachRisk.bodyTooClose,
      centerDistance,
      minBodyEdge - bodyEdge,
    );
  }
  if (headingRadians == null) {
    return result(WorkcellReachRisk.unknownHeading, centerDistance, 0);
  }

  // 수납함은 **뒤에** 달려 있다. 코가 보는 쪽의 반대다.
  final trayX = stationX - trayOffset * math.cos(headingRadians);
  final trayY = stationY - trayOffset * math.sin(headingRadians);
  final trayDistance = _distance(armX, armY, trayX, trayY);

  // ② 수납함이 본체보다 멀면 팔과 수납함 사이에 본체가 있다.
  if (trayDistance >= centerDistance) {
    return result(WorkcellReachRisk.trayBehindBody, trayDistance, 0);
  }
  // ③ 닿는가.
  if (trayDistance > reach) {
    return result(
      WorkcellReachRisk.trayOutOfReach,
      trayDistance,
      trayDistance - reach,
    );
  }
  return result(WorkcellReachRisk.ok, trayDistance, 0);
}

/// 여러 자리를 보고 사람에게 보일 글 하나로 만든다. 문제가 없으면 null.
///
/// 위험한 것을 먼저 적는다. 목록 끝에 파묻히면 못 본다.
String? workcellReachWarning(List<WorkcellReachCheck> checks) {
  final problems = [
    for (final check in checks)
      if (check.isProblem) check,
  ]..sort((a, b) => (b.isDanger ? 1 : 0) - (a.isDanger ? 1 : 0));
  if (problems.isEmpty) return null;
  return [
    for (final check in problems)
      '[${check.station}] ${check.title}\n'
          '  ${check.detail}\n'
          '  ${check.advice}',
  ].join('\n\n');
}

double _distance(double ax, double ay, double bx, double by) =>
    math.sqrt(math.pow(ax - bx, 2) + math.pow(ay - by, 2));
