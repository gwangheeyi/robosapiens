import 'dart:typed_data';
import 'dart:ui';

class DeployedMapSummary {
  const DeployedMapSummary({
    required this.id,
    required this.name,
    required this.yamlPath,
    required this.hasNavGraph,
  });
  final String id;
  final String name;
  final String yamlPath;
  final bool hasNavGraph;
}

class DeployedMapData {
  const DeployedMapData({
    required this.summary,
    required this.imageName,
    required this.imageBytes,
    required this.imageSize,
    required this.lanes,
    required this.waypoints,
    required this.waypointNames,
    this.waypointCategories = const {},
    this.waypointDockHeadings = const {},
    this.laneDirections = const {},
  });
  final DeployedMapSummary summary;
  final String imageName;
  final Uint8List imageBytes;
  final Size imageSize;
  final List<(Offset, Offset)> lanes;
  final List<Offset> waypoints;
  final Map<Offset, String> waypointNames;

  /// Waypoint 하나마다의 분류(`충전` · `설비` · `대기` …).
  ///
  /// 이것이 없으면 로봇 화면에서 자리 목록이 비어 보인다. 맵을 편집기에서
  /// 열어 두지 않았을 뿐인데 "맵에 충전 Waypoint 가 없습니다" 로 보였고,
  /// 그대로 저장하면 이미 골라 둔 자리가 지워졌다.
  final Map<Offset, String> waypointCategories;

  /// 그 자리에 로봇이 **어느 쪽을 보고 서야 하는가** [도, RMF 기준].
  ///
  /// 0도가 +X(도면 오른쪽), 반시계가 양수다. 로봇 +X 가 앞이므로 이 각도가
  /// 곧 로봇의 코가 향할 쪽이다.
  ///
  /// 핑키는 수납함을 **뒤에** 달고 다닌다. 픽업 자리에서 팔이 수납함에 닿으려면
  /// 코가 팔 반대쪽을 봐야 한다 — 들어온 그대로 서면 수납함이 팔에서 가장 먼
  /// 자리에 온다.
  ///
  /// RMF 의 nav graph 에는 자리마다의 각도라는 개념이 없다. 대신 작업의
  /// `go_to_place` 에 `orientation` 을 실을 수 있고([place.json]), 그 값이
  /// 경로계획의 마지막 자세가 되어 Nav2 목표 자세까지 그대로 내려간다. 여기
  /// 담긴 값이 그 자리에 쓰인다.
  ///
  /// 비어 있으면 각도를 요구하지 않는다 — RMF 가 들어온 길 방향대로 세운다.
  final Map<Offset, double> waypointDockHeadings;

  /// 레인별 통행 방향(`양방향` | `정방향`). 빠진 레인은 양방향으로 본다.
  ///
  /// 이 값이 없으면 일방통행으로 그린 레인을 로봇이 거슬러 올라간다. 작업
  /// 순서대로 가다가 어떤 레인에서 되돌아오는 것처럼 보이는 원인이었다.
  final Map<(Offset, Offset), String> laneDirections;
}
