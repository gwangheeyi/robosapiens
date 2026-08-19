/// 로봇이 지금 서 있는 자리를 Waypoint 로 만든다.
///
/// 도면 위에서 눈으로 찍는 것은 1픽셀 아래로 못 내려가고, 그 1픽셀이 실제로는
/// 몇 밀리미터인지 화면만 봐서는 모른다. 좁은 자리일수록 그 오차가 그대로
/// 남는다 — 팔과 핑키가 부딪힌 자리도 도면에서는 떨어져 보였는데 미터로 재면
/// 0.34m 였다.
///
/// 로봇을 실제로 그 자리에 세워 보면 그런 일이 없다. 밀어 넣어 보고, 팔이
/// 닿는지 보고, 그 자리를 그대로 찍는다. **좌표는 로봇이 말해 준다.**
///
/// 방향도 함께 받는다. 수동으로 자리를 맞췄다면 방향도 맞춘 것이고, 그 각도가
/// 다음 동작을 가른다 — 대기1 에서 −45도로 선 뒤 후진으로 픽업에 들어가는
/// 식이다.
///
/// 판정을 화면에서 떼어 둔 것은 [RobotLink] 와 같은 이유다 — 규칙은 눌러 보지
/// 않고도 확인할 수 있어야 한다.
library;

import 'waypoint_table.dart';

/// 자리를 찍을 수 있는가. 못 찍으면 왜 못 찍는가.
enum WaypointCaptureReadiness {
  ready,

  /// 로봇이 제 자리를 안 알려 준다.
  ///
  /// 토픽이 안 오거나 AMCL 이 아직 자리를 못 잡았다. 그 상태에서 찍으면
  /// **엉뚱한 자리**가 지도에 박힌다 — 나중에 그 자리로 로봇을 보내면 어디로
  /// 갈지 알 수 없다.
  noPose,

  /// 축척을 아직 안 재었다. 미터를 픽셀로 옮길 수 없다.
  noScale,

  /// 그 자리에 이미 Waypoint 가 있다.
  tooClose,
}

/// 이미 있는 Waypoint 로 보는 거리 [m].
///
/// 이보다 가까우면 새로 찍지 않는다. 겹쳐 두면 RMF 가 어느 쪽으로 보낼지
/// 애매해지고, 도착 반경(0.1m)끼리 겹쳐 어느 자리에 섰는지 구별이 안 된다.
const double waypointCaptureMinGapMeters = 0.15;

/// 자리를 찍을 수 있는지 본다.
///
/// [poseKnown] 은 로봇이 제 위치를 알려 주는가다. [scaleKnown] 은 축척을
/// 재었는가다. [nearestGapMeters] 는 가장 가까운 Waypoint 까지의 거리 [m] 이고,
/// 하나도 없으면 null 이다.
WaypointCaptureReadiness checkWaypointCapture({
  required bool poseKnown,
  required bool scaleKnown,
  double? nearestGapMeters,
}) {
  if (!poseKnown) return WaypointCaptureReadiness.noPose;
  if (!scaleKnown) return WaypointCaptureReadiness.noScale;
  if (nearestGapMeters != null &&
      nearestGapMeters < waypointCaptureMinGapMeters) {
    return WaypointCaptureReadiness.tooClose;
  }
  return WaypointCaptureReadiness.ready;
}

bool canCaptureWaypoint(WaypointCaptureReadiness readiness) =>
    readiness == WaypointCaptureReadiness.ready;

/// 못 찍는 까닭. 찍을 수 있으면 null.
String? waypointCaptureBlockedReason(WaypointCaptureReadiness readiness) =>
    switch (readiness) {
      WaypointCaptureReadiness.ready => null,
      WaypointCaptureReadiness.noPose =>
        '로봇이 제 자리를 안 알려 줍니다. 브링업과 Nav2 가 떠서 '
            'AMCL 이 위치를 낼 때까지 기다려 주세요 — 모르는 채로 찍으면 '
            '엉뚱한 자리가 지도에 박힙니다.',
      WaypointCaptureReadiness.noScale =>
        '도면 축척을 아직 안 재었습니다. 맵 관리에서 거리를 재 주세요 — '
            '미터를 픽셀로 옮길 수 없습니다.',
      WaypointCaptureReadiness.tooClose =>
        '그 자리에 이미 Waypoint 가 있습니다 '
            '(${(waypointCaptureMinGapMeters * 100).toStringAsFixed(0)}cm 안). '
            '겹쳐 두면 RMF 가 어느 쪽으로 보낼지 애매해집니다 — 기존 자리를 '
            '옮기거나 이름을 고쳐 쓰세요.',
    };

/// 찍은 자리에 붙일 이름을 짓는다.
///
/// 같은 카테고리의 다음 번호를 준다. 이름이 곧 RMF 의 `target_guid` 라
/// 겹치면 안 되는데, 사람이 세어서 붙이면 언젠가 겹친다.
///
/// [existingNames] 는 지금 지도에 있는 이름 전부다.
String nextWaypointName({
  required String category,
  required Iterable<String> existingNames,
}) {
  final prefix = category.trim().isEmpty ? '지점' : category.trim();
  var highest = 0;
  final pattern = RegExp('^${RegExp.escape(prefix)}([0-9]+)\$');
  for (final name in existingNames) {
    final match = pattern.firstMatch(name.trim());
    if (match == null) continue;
    final number = int.tryParse(match.group(1)!);
    if (number != null && number > highest) highest = number;
  }
  return '$prefix${highest + 1}';
}

/// 찍은 자리에 방향을 넣을 것인가.
///
/// 방향을 쓰는 카테고리일 때만 넣는다. 안 쓰는 자리에 각도를 남겨 두면,
/// 나중에 카테고리를 바꿨을 때 잊어버린 옛 각도가 되살아난다
/// ([waypointUsesDockHeading] 와 같은 규칙이다).
double? captureHeadingFor({
  required String category,
  required double? robotHeadingDegrees,
}) {
  if (robotHeadingDegrees == null) return null;
  if (!waypointUsesDockHeading(category)) return null;
  return robotHeadingDegrees;
}

/// 찍고 나서 사람에게 남길 말.
///
/// 무엇이 어디에 생겼는지 그대로 적는다. 지도를 안 보고 있었으면 눌렀는지도
/// 모른 채 지나간다.
String waypointCapturedMessage({
  required String name,
  required String category,
  required double xMeters,
  required double yMeters,
  double? headingDegrees,
}) {
  final place =
      '${xMeters.toStringAsFixed(3)}, ${yMeters.toStringAsFixed(3)} m';
  final facing = headingDegrees == null
      ? ''
      : ' · 방향 ${_degrees(headingDegrees)}도';
  return '$category `$name` 을 로봇 자리에 만들었습니다 ($place$facing).\n'
      '맵 관리에서 레인을 잇거나 이름을 고칠 수 있습니다.';
}

String _degrees(double value) {
  final text = value.toStringAsFixed(1);
  return text.endsWith('.0') ? text.substring(0, text.length - 2) : text;
}
