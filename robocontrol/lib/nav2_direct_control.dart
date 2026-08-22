library;

import 'dart:math' as math;

/// RMF 없이 Nav2의 NavigateToPose action으로 보내는 단일 목적지다.
class Nav2DirectGoal {
  const Nav2DirectGoal({
    required this.namespace,
    required this.x,
    required this.y,
    required this.yawDegrees,
  });

  final String namespace;
  final double x;
  final double y;
  final double yawDegrees;

  String get actionName {
    final clean = namespace.trim().replaceAll(RegExp(r'^/+|/+$'), '');
    return clean.isEmpty ? '/navigate_to_pose' : '/$clean/navigate_to_pose';
  }

  String get goalYaml {
    final halfYaw = yawDegrees * math.pi / 360.0;
    final z = math.sin(halfYaw);
    final w = math.cos(halfYaw);
    return '{pose: {header: {frame_id: map}, pose: {'
        'position: {x: $x, y: $y, z: 0.0}, '
        'orientation: {x: 0.0, y: 0.0, z: $z, w: $w}}}}';
  }
}

String? nav2DirectMoveBlocker({
  required bool isMobile,
  required String? mapName,
  required int waypointCount,
  required double? metersPerPixel,
}) {
  if (!isMobile) return '설비 로봇은 이동시킬 수 없습니다.';
  if (mapName == null || mapName.trim().isEmpty) {
    return '열린 지도가 없습니다. 먼저 운용할 지도를 불러오세요.';
  }
  if (waypointCount == 0) return '이름이 붙은 Waypoint가 없습니다.';
  if (metersPerPixel == null || metersPerPixel <= 0) {
    return '지도 축척이 없습니다. 축척을 먼저 설정하세요.';
  }
  return null;
}
