/// 등록된 로봇이 설 자리가 지도와 맞는지 살핀다.
///
/// 좌표는 눈에 안 보이는 값이라 틀려도 티가 잘 안 난다. 실제로 겪은 일: 홈1에
/// 올린 핑키가 화면에서는 지도 원점에 있었고 Gazebo 에서는 건물 밖 허공에서
/// 끝없이 떨어지고 있었다. **바퀴는 허공에서도 돌기 때문에 odom 은 멀쩡해
/// 보였다.** 옆에 있던 설치 로봇은 월드에 고정이라 떨어지지도 않아 증상조차
/// 없었다 — 좌표는 똑같이 틀렸는데도.
///
/// 그래서 사람이 눌러서 확인할 수 있어야 한다. 자세한 좌표계 설명은
/// `docs/COORDINATE_FRAMES.md` 에 있다.
library;

import 'rmf_project_config.dart';

/// 자리 한 곳을 살핀 결과.
enum SpawnIssue {
  /// 저장된 자리가 바닥 안이고 지도와도 같다.
  ok,

  /// 저장된 자리가 바닥 밖이다. 이대로 올리면 이동 로봇은 끝없이 떨어진다.
  outsideFloor,

  /// 바닥 안이긴 한데 지도가 말하는 자리와 다르다. 자리 Waypoint 를 옮겼거나
  /// 예전 판이 저장해 둔 값이다.
  stale,

  /// 설 자리(Waypoint)를 못 찾았다. 이름이 바뀌었거나 지워졌다.
  noStation,

  /// 좌표가 아예 없다. 아직 자리를 안 정했다.
  noCoordinate,
}

extension SpawnIssueLabel on SpawnIssue {
  String get label => switch (this) {
    SpawnIssue.ok => '맞습니다',
    SpawnIssue.outsideFloor => '바닥 밖',
    SpawnIssue.stale => '지도와 다름',
    SpawnIssue.noStation => '자리 없음',
    SpawnIssue.noCoordinate => '좌표 없음',
  };

  /// 무엇이 잘못됐고 어떻게 하면 되는지.
  String get detail => switch (this) {
    SpawnIssue.ok => '저장된 자리가 지도와 같고 바닥 안입니다.',
    SpawnIssue.outsideFloor =>
      '저장된 자리에 바닥이 없습니다. 이대로 올리면 이동 로봇은 '
          '허공에서 끝없이 떨어집니다. 설치 로봇은 고정이라 떨어지지는 않지만 '
          '자리는 어긋납니다.',
    SpawnIssue.stale =>
      '자리 Waypoint 를 옮겼거나 예전 판이 저장해 둔 값입니다. '
          '지도 기준으로 다시 맞추면 됩니다.',
    SpawnIssue.noStation =>
      '이 로봇이 선다고 적힌 Waypoint 를 지도에서 못 찾았습니다. '
          '이름이 바뀌었거나 지워졌습니다. 로봇 등록에서 자리를 다시 골라 주세요.',
    SpawnIssue.noCoordinate =>
      '아직 설 자리를 안 정했습니다. 로봇 등록에서 자리를 골라 주세요.',
  };

  /// 지도 기준으로 다시 맞추면 풀리는가.
  bool get fixableByRefit =>
      this == SpawnIssue.outsideFloor ||
      this == SpawnIssue.stale ||
      this == SpawnIssue.noCoordinate;
}

/// 로봇 한 대의 자리를 살핀 결과.
class SpawnCheck {
  const SpawnCheck({
    required this.robot,
    required this.issue,
    this.stored,
    this.fromMap,
    this.storedInsideFloor = false,
  });

  final RmfProjectRobot robot;
  final SpawnIssue issue;

  /// 지금 등록에 저장된 자리(m). 없으면 null.
  final ({double x, double y})? stored;

  /// 지금 지도에서 다시 계산한 자리(m). 자리 Waypoint 를 못 찾으면 null.
  final ({double x, double y})? fromMap;

  final bool storedInsideFloor;

  bool get isOk => issue == SpawnIssue.ok;

  /// `다시 맞추기` 로 고쳐질 로봇인가.
  bool get willChange => fromMap != null && issue.fixableByRefit;
}

/// 등록된 로봇 전부의 자리를 살핀다.
///
/// [pixelOf] 는 로봇이 선다고 적힌 Waypoint 의 지도 픽셀. 못 찾으면 null.
/// [insideFloor] 는 그 지도 픽셀이 바닥 안인지. [metersPerPixel] 이 없으면
/// 미터로 옮길 수 없으므로 아무것도 판정하지 않는다.
List<SpawnCheck> checkRobotSpawns({
  required List<RmfProjectRobot> robots,
  required ({double dx, double dy})? Function(RmfProjectRobot robot) pixelOf,
  required bool Function(double dx, double dy) insideFloor,
  required double? metersPerPixel,
}) {
  if (metersPerPixel == null || metersPerPixel <= 0) return const [];
  final result = <SpawnCheck>[];
  for (final robot in robots) {
    final pixel = pixelOf(robot);
    final fromMap = pixel == null
        ? null
        : rmfWorldFromPixel(pixel.dx, pixel.dy, metersPerPixel);
    final stored = robot.spawnX == null || robot.spawnY == null
        ? null
        : (x: robot.spawnX!, y: robot.spawnY!);

    if (stored == null) {
      result.add(
        SpawnCheck(
          robot: robot,
          issue: fromMap == null
              ? SpawnIssue.noStation
              : SpawnIssue.noCoordinate,
          fromMap: fromMap,
        ),
      );
      continue;
    }

    // 저장된 자리를 지도 픽셀로 되돌려서 바닥 안인지 본다. 지도에서 다시
    // 계산한 값이 아니라 **지금 저장된 값**을 봐야 한다. 그래야 실행에 실제로
    // 나가는 좌표가 맞는지 알 수 있다.
    final storedPixel = pixelFromRmfWorld(stored.x, stored.y, metersPerPixel);
    final storedInside = insideFloor(storedPixel.dx, storedPixel.dy);

    final SpawnIssue issue;
    if (!storedInside) {
      issue = SpawnIssue.outsideFloor;
    } else if (fromMap == null) {
      issue = SpawnIssue.noStation;
    } else if ((fromMap.x - stored.x).abs() < 1e-6 &&
        (fromMap.y - stored.y).abs() < 1e-6) {
      issue = SpawnIssue.ok;
    } else {
      issue = SpawnIssue.stale;
    }

    result.add(
      SpawnCheck(
        robot: robot,
        issue: issue,
        stored: stored,
        fromMap: fromMap,
        storedInsideFloor: storedInside,
      ),
    );
  }
  return result;
}

/// 사람에게 한 줄로 알릴 요약.
String spawnCheckSummary(List<SpawnCheck> checks) {
  if (checks.isEmpty) return '살펴볼 로봇이 없습니다.';
  final outside = checks
      .where((check) => check.issue == SpawnIssue.outsideFloor)
      .length;
  final stale = checks.where((check) => check.issue == SpawnIssue.stale).length;
  final missing = checks
      .where(
        (check) =>
            check.issue == SpawnIssue.noStation ||
            check.issue == SpawnIssue.noCoordinate,
      )
      .length;
  if (outside == 0 && stale == 0 && missing == 0) {
    return '${checks.length}대 모두 자리가 맞습니다.';
  }
  return [
    if (outside > 0) '$outside대가 바닥 밖에 있습니다',
    if (stale > 0) '$stale대가 지도와 다릅니다',
    if (missing > 0) '$missing대는 자리가 없습니다',
  ].join(' · ');
}
