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
    this.laneDirections = const {},
  });
  final DeployedMapSummary summary;
  final String imageName;
  final Uint8List imageBytes;
  final Size imageSize;
  final List<(Offset, Offset)> lanes;
  final List<Offset> waypoints;
  final Map<Offset, String> waypointNames;

  /// 레인별 통행 방향(`양방향` | `정방향`). 빠진 레인은 양방향으로 본다.
  ///
  /// 이 값이 없으면 일방통행으로 그린 레인을 로봇이 거슬러 올라간다. 작업
  /// 순서대로 가다가 어떤 레인에서 되돌아오는 것처럼 보이는 원인이었다.
  final Map<(Offset, Offset), String> laneDirections;
}
