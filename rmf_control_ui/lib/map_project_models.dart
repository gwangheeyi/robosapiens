/// 맵 프로젝트 저장소가 주고받는 값. 지도 이름이 프로젝트 구분자다.
library;

/// 프로젝트 목록에 뿌릴 요약. 도면 바이트가 빠져 있어 가볍다.
class MapProjectSummary {
  const MapProjectSummary({
    required this.mapName,
    required this.drawingName,
    required this.waypointCount,
    required this.laneCount,
    required this.hasBuildingYaml,
    required this.updatedAt,
  });

  final String mapName;
  final String? drawingName;
  final int waypointCount;
  final int laneCount;

  /// 배포에 쓸 building.yaml 이 함께 저장돼 있는지. 맵이 아직 YAML 로 만들 수
  /// 있는 상태가 아니면 false 다.
  final bool hasBuildingYaml;
  final DateTime updatedAt;
}

/// 같은 이름의 프로젝트가 이미 있을 때 사용자가 고른 처리 방법.
enum MapProjectNameConflictChoice {
  /// 기존 프로젝트를 이 내용으로 덮어쓴다.
  overwrite,

  /// 다른 이름으로 새 프로젝트를 만든다.
  rename,

  /// 저장하지 않는다.
  cancel,
}

/// 프로젝트에 딸린 설정 파일 하나.
class MapProjectFile {
  const MapProjectFile({
    required this.fileName,
    required this.kind,
    required this.content,
    required this.generatedAt,
  });

  final String fileName;

  /// building | nav_graph | fleet_adapter | fleet_sim | launch
  final String kind;
  final String content;
  final DateTime generatedAt;
}
