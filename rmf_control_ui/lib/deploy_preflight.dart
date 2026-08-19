/// 배포하기 전에 프로젝트를 먼저 남긴다.
///
/// 배포는 오랫동안 **화면 상태만** 내보냈다. Waypoint 를 옮겨 배포해 놓고 앱을
/// 다시 열면 MySQL 에 남아 있던 옛 자리가 돌아왔고, 다음 배포에서 그 옛 자리가
/// 다시 나갔다. 사람 눈에는 고친 것이 조용히 되돌아가는 것으로 보인다 —
/// 실제로 픽업 자리를 팔에서 떼어 놓았는데 다음 배포에서 도로 겹쳤다.
///
/// 원장은 MySQL 이다. 그러니 배포에 들어가는 그 내용이 원장에도 그대로 들어가야
/// 한다. 여기서는 무엇을 할지만 정하고, 실제 저장은 화면 쪽이 한다.
library;

import 'dart:math' as math;

import 'robot_spawn_check.dart';
// 적재 방향을 쓰는 카테고리가 무엇인지는 표와 **같은 곳**을 봐야 한다. 여기에
// 따로 적어 두면 배포 점검이 표와 다른 말을 하게 된다.
import 'waypoint_table.dart' show waypointUsesDockHeading;

/// 배포 직전에 할 일.
enum DeployPreflight {
  /// 열린 프로젝트에 지금 화면을 저장하고 배포한다.
  save,

  /// 남길 곳이 없다. 배포는 할 수 있으나 그 사실을 알린다.
  warnNoProject,
}

DeployPreflight deployPreflightFor(String? openProject) =>
    (openProject ?? '').trim().isEmpty
    ? DeployPreflight.warnNoProject
    : DeployPreflight.save;

/// 열린 프로젝트가 없어 남길 곳이 없을 때의 경고.
String deployNoProjectMessage(String mapName) =>
    '열린 프로젝트가 없어 지금 화면 내용을 남길 곳이 없습니다.\n\n'
    '이대로 배포하면 `$mapName` 산출물은 만들어지지만, 앱을 다시 열면 '
    '지금 화면(Waypoint 자리·적재 방향·Lane)은 사라집니다. 다음 배포는 '
    '옛 내용으로 나갑니다.\n\n'
    '맵 관리에서 `프로젝트 저장` 을 먼저 하세요.';

/// 등록된 자리가 지도와 이만큼 넘게 벌어지면 어긋난 것으로 본다 [m].
///
/// Waypoint 를 끌면 화면은 곧바로 움직이지만 등록의 좌표는 그대로다. 5cm 는
/// 눈으로는 티가 안 나면서 팔 끝에서는 헛집기 시작하는 거리다.
const double staleSpawnToleranceMeters = .05;

/// 설비 로봇의 등록 좌표가 지금 지도와 어긋났는지. 멀쩡하면 null.
///
/// **설비 로봇만 본다.** 이동 로봇은 충전 자리와 시작 자리가 달라도 정상이라
/// 벌어졌다고 탓할 수 없다. 그러나 설비는 그 Waypoint 에 붙박여 있으므로,
/// 등록 좌표와 Waypoint 가 다르면 둘 중 하나는 거짓이다 — 그리고 배포에
/// 나가는 것은 등록 좌표다. Waypoint 를 옮겨 놓고 이것을 안 맞추면, 팔은
/// 옛 자리에 서고 핑키만 새 자리로 가서 다시 겹친다.
String? staleWorkcellSpawnMessage(
  List<SpawnCheck> checks, {
  double toleranceMeters = staleSpawnToleranceMeters,
}) {
  final lines = <String>[];
  for (final check in checks) {
    if (check.robot.isMobile) continue;
    final stored = check.stored;
    final fromMap = check.fromMap;
    if (stored == null || fromMap == null) continue;
    final gap = math.sqrt(
      math.pow(stored.x - fromMap.x, 2) + math.pow(stored.y - fromMap.y, 2),
    );
    if (gap <= toleranceMeters) continue;
    lines.add(
      '${check.robot.robotId} · ${check.robot.displayName}'
      ' (자리 ${check.robot.chargerWaypoint ?? '미지정'})\n'
      '  등록 ${_m(stored.x)}, ${_m(stored.y)}'
      '  →  지도 ${_m(fromMap.x)}, ${_m(fromMap.y)}'
      '  (${_m(gap)}m 차이)',
    );
  }
  if (lines.isEmpty) return null;
  return '다음 설비 로봇의 등록 자리가 지금 지도와 다릅니다.\n\n'
      '${lines.join('\n')}\n\n'
      'Waypoint 를 옮긴 뒤 등록이 따라오지 않았습니다. 이대로 배포하면 팔은 '
      '등록에 적힌 **옛 자리**에 서고 핑키만 새 자리로 갑니다 — 옮겨 놓은 '
      '자리가 다시 겹치는 것이 이 때문입니다.';
}

String _m(double value) => value.toStringAsFixed(2);

/// 배포 전에 볼 자리 하나의 적재 방향.
class DockHeadingCheck {
  const DockHeadingCheck({
    required this.name,
    required this.category,
    required this.degrees,
  });

  /// Waypoint 이름. 배포 산출물에서 이 자리를 가리키는 이름이다.
  final String name;

  /// Waypoint 카테고리(`픽업`·`드랍오프`·`대기` …).
  final String category;

  /// 정해 둔 적재 방향 [도]. 안 정했으면 null.
  final double? degrees;
}

/// 적재 방향을 안 정한 픽업·드랍오프·충전 자리. 다 정해 놓았으면 null.
///
/// 각도는 **안 정해도 된다** — 비워 두면 RMF 가 들어온 길 방향대로 세운다.
/// 그러나 그 자리에서 팔이 물건을 집는다면 로봇이 어느 쪽을 보고 서는지가
/// 결과를 가른다. 충전 자리도 같다 — 충전 단자는 로봇 한쪽에만 있어서, 방향이
/// 없으면 도착은 했는데 접점이 안 맞는 일이 생긴다. 그래서 막지는 않고
/// 알리기만 한다.
///
/// 실제로 픽업3 에 180 도를 넣었다고 기억하는데 저장된 프로젝트에도 배포된
/// building.yaml 에도 `robosapiens_dock_heading` 이 없던 일이 있었다. 각도는
/// 카테고리를 픽업·드랍오프 밖으로 바꾸는 순간 말없이 지워지므로, 사람은 넣은
/// 줄 알고 앱은 없는 상태로 갈린다. 배포는 그것을 알아챌 수 있는 마지막
/// 자리다 — 여기를 지나면 로봇이 그 자리에서 아무 방향으로나 선다.
String? missingDockHeadingMessage(List<DockHeadingCheck> checks) {
  final lines = <String>[];
  for (final check in checks) {
    if (!waypointUsesDockHeading(check.category)) continue;
    // 대기는 방향을 **쓸 수 있을** 뿐이지 있어야 하는 자리가 아니다. 대부분의
    // 대기 자리는 그냥 지나가며 서는 곳이라, 없다고 알리면 잔소리가 된다.
    // 픽업·드랍오프는 팔이 물건을 집어야 하고 충전은 단자가 한쪽에만 있어서,
    // 그 둘은 없으면 결과가 갈린다.
    if (check.category == '대기') continue;
    if (check.degrees != null) continue;
    final name = check.name.trim();
    lines.add('${name.isEmpty ? '(이름 없음)' : name} · ${check.category}');
  }
  if (lines.isEmpty) return null;
  return '다음 자리에 적재 방향이 없습니다.\n\n'
      '${lines.join('\n')}\n\n'
      '이대로 배포하면 building.yaml 에 `robosapiens_dock_heading` 이 안 '
      '들어가고, 로봇은 그 자리에서 들어온 길 방향 그대로 섭니다. 팔이 물건을 '
      '집는 자리라면 매번 다른 쪽을 보고 서게 되고, 충전 자리라면 충전 단자가 '
      '매번 다른 쪽을 봅니다.\n\n'
      '각도를 넣으려면 Waypoint 를 열어 `적재 방향 (도)` 에 적으세요. '
      '방향을 안 따져도 되는 자리면 그대로 배포하셔도 됩니다.';
}

/// 저장이 안 됐을 때의 경고. 왜 그냥 넘기면 안 되는지까지 적는다.
String deploySaveFailedMessage(String project, Object error) =>
    '`$project` 프로젝트를 저장하지 못했습니다.\n\n'
    '$error\n\n'
    '이대로 배포하면 배포 산출물과 저장된 프로젝트가 서로 달라집니다. '
    '앱을 다시 열면 저장된 옛 내용이 화면에 오고, 다음 배포에서 그 옛 내용이 '
    '다시 나갑니다 — 방금 고친 Waypoint 자리가 되돌아간 것처럼 보입니다.';
