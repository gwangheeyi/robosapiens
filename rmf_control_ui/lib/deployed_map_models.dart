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
  });
  final DeployedMapSummary summary;
  final String imageName;
  final Uint8List imageBytes;
  final Size imageSize;
  final List<(Offset, Offset)> lanes;
  final List<Offset> waypoints;
  final Map<Offset, String> waypointNames;
}
