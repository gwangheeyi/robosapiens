/// 로봇을 등록할 때 자리 Waypoint 를 반드시 고르게 하는 규칙.
///
/// 자리를 안 고르면 spawn 좌표가 없고, 좌표 없는 로봇은 지도 원점(0,0)에
/// 놓인다. project1 에서 이동 로봇과 설치 로봇이 둘 다 원점에 놓이자, 메시
/// 충돌 도형끼리 파고들어 Gazebo 가 스폰 4초 만에 죽었다:
///
///   ODE INTERNAL ERROR 1: assertion ... failed in UpdateArbitraryContactInNode()
///     [collision_trimesh_trimesh.cpp:285]
///   [ERROR] [gazebo-1]: process has died ... exit code 134
///
/// 그 맵에는 `충전1` 도 `설비1` 도 있었다. 고를 자리가 없어서가 아니라 고르지
/// 않아서 생긴 일이다. 그래서 고를 수 있을 때는 반드시 고르게 한다.
///
/// 판정을 화면에서 떼어 둔 것은 [RobotLink] 와 같은 이유다 — 규칙은 눌러 보지
/// 않고도 확인할 수 있어야 한다.
library;

import 'rmf_project_config.dart';

/// 자리를 안 고른 로봇을 어떻게 다룰지.
enum StationRequirement {
  /// 자리가 필요 없다. Mock 로봇은 Gazebo 에도 RMF 플릿에도 들어가지 않는다.
  notNeeded,

  /// 골랐다.
  satisfied,

  /// 골라야 하는데 안 골랐다. 고를 자리가 있으므로 저장을 막는다.
  missing,

  /// 골라야 하는데 고를 자리가 하나도 없다.
  ///
  /// 맵을 아직 안 불러왔거나, 맵에 그 카테고리 Waypoint 가 없다. 여기서 막으면
  /// 맵을 그리기 전에는 로봇을 한 대도 등록할 수 없다. 대신 무엇이 빠졌는지
  /// 알리고 저장은 시킨다 — 자리 이름만 나중에 채우면 좌표는 맵을 열 때 따라
  /// 붙는다.
  unavailable,
}

/// 이 등록에 자리가 필요한지, 필요하다면 채워졌는지 본다.
///
/// [usesTopics] 는 이 로봇의 값이 토픽에서 오는가다. Gazebo·실물이면 참이고
/// 앱 Mock 이면 거짓이다.
/// [station] 은 지금 고른 자리 이름, [stationsAvailable] 은 고를 자리가 하나라도
/// 있는가다.
StationRequirement checkStationRequirement({
  required bool usesTopics,
  required String? station,
  required bool stationsAvailable,
}) {
  if (!usesTopics) return StationRequirement.notNeeded;
  if ((station ?? '').trim().isNotEmpty) return StationRequirement.satisfied;
  return stationsAvailable
      ? StationRequirement.missing
      : StationRequirement.unavailable;
}

/// 저장을 시킬 수 있는가.
bool canSaveRobot(StationRequirement requirement) =>
    requirement != StationRequirement.missing;

/// 이 자리를 이미 쓰고 있는 다른 로봇. 없으면 null.
///
/// 자리 하나에 두 대를 묶으면 **둘의 spawn 좌표가 같아진다.** 그 좌표가 파일에
/// 그대로 박히므로(`spawn.launch.xml` 의 `-x -y`), Gazebo 에서는 메시 충돌
/// 도형끼리 파고들어 시뮬레이터가 죽는다 — 자리를 아예 안 고른 로봇 둘로
/// 겪었던 것과 같은 사고다([robotsMissingStation] 의 주석).
///
/// 실물이면 Gazebo 는 안 죽지만 대신 더 조용히 어긋난다. 두 로봇의 AMCL 초기
/// 자세가 같은 자리로 나가서, 실제로는 떨어져 있는 두 대가 서로 자기가 그
/// 자리에 있다고 믿는다. 그 상태로 경로를 짜면 둘 다 엉뚱한 데로 간다.
///
/// [robotId] 는 지금 고치는 로봇이다. 자기 자신은 겹침으로 세지 않는다 —
/// 등록을 열어 다른 것만 고치고 저장할 때 제 자리에 걸리면 안 된다.
///
/// 설비 로봇도 같다. 팔 둘을 같은 자리에 두면 한 자리에 겹쳐 선다.
RmfProjectRobot? robotHoldingStation({
  required List<RmfProjectRobot> robots,
  required String? station,
  required String robotId,
}) {
  final wanted = (station ?? '').trim();
  if (wanted.isEmpty) return null;
  final me = robotId.trim();
  for (final robot in robots) {
    if (robot.robotId.trim() == me) continue;
    if ((robot.chargerWaypoint ?? '').trim() == wanted) return robot;
  }
  return null;
}

/// 자리가 겹친다고 알릴 말. 안 겹치면 null.
///
/// 막지는 않는다. 자리를 옮기는 도중에 잠깐 겹치는 일이 있고, 그때 저장을
/// 막으면 두 로봇의 자리를 서로 바꾸는 것이 불가능해진다. 대신 무슨 일이
/// 벌어지는지 그 자리에서 밝힌다.
String? stationConflictMessage({
  required RmfProjectRobot? holder,
  required String station,
}) {
  if (holder == null) return null;
  return '$station 은(는) 이미 ${holder.robotId} · ${holder.displayName} 의 '
      '자리입니다.\n\n'
      '한 자리에 두 대를 두면 둘의 시작 좌표가 같아집니다 — Gazebo 로봇이면 '
      '메시가 파고들어 시뮬레이터가 죽고, 실물이면 두 대의 AMCL 이 같은 자리를 '
      '제 자리로 믿습니다.\n\n'
      '다른 자리를 고르거나, 맵에 자리를 하나 더 그려 주세요.';
}

/// 배포를 막아야 할 만큼 자리가 겹치는가. 겹치는 자리 이름 → 그 자리를 쓰는 로봇들.
///
/// 등록 창은 막지 않는다(자리를 서로 바꾸는 중일 수 있다). 배포는 다르다 —
/// 여기까지 왔으면 좌표가 파일에 박히는 순간이다.
Map<String, List<RmfProjectRobot>> robotsSharingStation(
  List<RmfProjectRobot> robots,
) {
  final byStation = <String, List<RmfProjectRobot>>{};
  for (final robot in robots) {
    if (!robot.dataSource.usesTopics) continue;
    final station = (robot.chargerWaypoint ?? '').trim();
    if (station.isEmpty) continue;
    byStation.putIfAbsent(station, () => []).add(robot);
  }
  byStation.removeWhere((_, holders) => holders.length < 2);
  return byStation;
}

/// 사람에게 보여 줄 한 줄. 필요 없으면 null.
///
/// 흐린 단추만 두면 사람이 다른 칸을 뒤진다. 무엇이 빠졌고 그것이 어디에 쓰이는지
/// 그 자리에서 밝힌다.
String? stationRequirementMessage(
  StationRequirement requirement,
  String category,
) => switch (requirement) {
  StationRequirement.notNeeded => null,
  StationRequirement.satisfied => null,
  StationRequirement.missing =>
    '자리를 골라야 저장할 수 있습니다. 이 자리는 RMF 충전 복귀 지점이며, '
        '새 로봇의 Gazebo Spawn · AMCL 초기 자세 기본값으로 사용됩니다. '
        '등록 후에는 별도의 시작 Waypoint를 선택할 수 있습니다.',
  StationRequirement.unavailable =>
    '맵에 $category 카테고리 Waypoint 가 없어 자리를 고를 수 없습니다. '
        '지금 저장하면 이 로봇은 지도 원점(0,0)에 놓입니다 — 맵을 불러온 뒤 '
        '자리를 정해 주세요.',
};

/// 배포를 막아야 하는 로봇들.
///
/// 등록 창은 "고를 자리가 하나도 없을 때"는 막지 않는다. 맵을 그리기 전에도
/// 로봇 목록은 짤 수 있어야 하기 때문이다. 그래서 자리 없는 로봇이 프로젝트에
/// 남을 수 있다.
///
/// 배포는 다르다. 여기까지 왔으면 맵은 이미 있고, 산출물이 만들어지는 순간
/// 좌표가 파일에 박힌다 — `spawn.launch.xml` 의 `-x -y`, `nav2_params.yaml` 의
/// AMCL 초기 자세, fleet 설정의 `charger`. 자리가 없으면 그 자리에 0 이
/// 들어가고, 두 대만 그래도 Gazebo 가 죽는다. 그러니 파일을 만들기 전에 막는다.
///
/// 예전에 자리 없이 저장된 로봇도 여기서 함께 걸린다.
///
/// Mock 로봇은 세지 않는다. 산출물에 올릴 것이 없다.
List<RmfProjectRobot> robotsMissingStation(List<RmfProjectRobot> robots) => [
  for (final robot in robots)
    if (robot.dataSource.usesTopics &&
        (robot.chargerWaypoint ?? '').trim().isEmpty)
      robot,
];

/// 배포를 막는 이유. 막을 것이 없으면 null.
String? deployBlockedMessage(List<RmfProjectRobot> robots) {
  final missing = robotsMissingStation(robots);
  if (missing.isNotEmpty) {
    final lines = [
      for (final robot in missing)
        '  · ${robot.robotId} · ${robot.displayName} — '
            '${robot.kind.waypointCategory} Waypoint 미지정',
    ];
    return '자리를 안 고른 로봇이 있어 내보내지 않았습니다.\n\n'
        '${lines.join('\n')}\n\n'
        '자리가 없으면 spawn 좌표가 0,0 이 됩니다. 두 대가 원점에 겹치면 '
        '메시끼리 파고들어 Gazebo 가 뜨자마자 죽습니다 — 그런데 RMF 와 Nav2 는 '
        '그대로 남아 토픽 이름만 보이고 값은 하나도 안 옵니다.\n\n'
        '로봇 등록에서 자리 Waypoint 를 고른 뒤 다시 내보내세요.';
  }
  // 자리를 골랐어도 **같은 자리**면 결과가 같다. 두 대의 spawn 좌표가 한 점이
  // 되어 원점에 겹친 것과 똑같이 부딪힌다. 등록 창은 이것을 막지 않는다 —
  // 자리를 서로 바꾸는 중일 수 있기 때문이다. 파일을 만들기 전에 여기서 막는다.
  final shared = robotsSharingStation(robots);
  if (shared.isEmpty) return null;
  final lines = [
    for (final entry in shared.entries)
      '  · ${entry.key} — '
          '${entry.value.map((robot) => robot.robotId).join(', ')}',
  ];
  return '한 자리에 두 대 넘게 묶인 로봇이 있어 내보내지 않았습니다.\n\n'
      '${lines.join('\n')}\n\n'
      '두 대의 시작 좌표가 같아집니다. Gazebo 로봇이면 메시가 파고들어 '
      '시뮬레이터가 뜨자마자 죽고, 실물이면 두 대의 AMCL 이 같은 자리를 제 '
      '자리로 믿어 둘 다 엉뚱한 곳으로 갑니다.\n\n'
      '맵에 자리를 하나 더 그리거나, 로봇 등록에서 다른 자리를 골라 주세요.';
}
