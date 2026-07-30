import 'dart:math' as math;

class RmfAffineImage {
  const RmfAffineImage({
    required this.url,
    required this.xOffset,
    required this.yOffset,
    required this.scale,
  });

  final String url;
  final double xOffset;
  final double yOffset;
  final double scale;

  factory RmfAffineImage.fromJson(Map<String, dynamic> json) => RmfAffineImage(
    url: json['data'] as String? ?? '',
    xOffset: _number(json['x_offset']),
    yOffset: _number(json['y_offset']),
    scale: _number(json['scale'], fallback: 1),
  );
}

class RmfGraphVertex {
  const RmfGraphVertex({required this.x, required this.y, required this.name});

  final double x;
  final double y;
  final String name;

  factory RmfGraphVertex.fromJson(Map<String, dynamic> json) => RmfGraphVertex(
    x: _number(json['x']),
    y: _number(json['y']),
    name: json['name'] as String? ?? '',
  );
}

class RmfGraphEdge {
  const RmfGraphEdge({required this.from, required this.to});

  final int from;
  final int to;

  factory RmfGraphEdge.fromJson(Map<String, dynamic> json) => RmfGraphEdge(
    from: (json['v1_idx'] as num?)?.toInt() ?? 0,
    to: (json['v2_idx'] as num?)?.toInt() ?? 0,
  );
}

class RmfLevel {
  const RmfLevel({
    required this.name,
    required this.image,
    required this.vertices,
    required this.edges,
  });

  final String name;
  final RmfAffineImage? image;
  final List<RmfGraphVertex> vertices;
  final List<RmfGraphEdge> edges;

  factory RmfLevel.fromJson(Map<String, dynamic> json) {
    final images = _maps(json['images']);
    final graphs = _maps(json['nav_graphs']);
    final vertices = <RmfGraphVertex>[];
    final edges = <RmfGraphEdge>[];
    for (final graph in graphs) {
      final offset = vertices.length;
      vertices.addAll(_maps(graph['vertices']).map(RmfGraphVertex.fromJson));
      edges.addAll(
        _maps(graph['edges'])
            .map(RmfGraphEdge.fromJson)
            .map(
              (edge) =>
                  RmfGraphEdge(from: edge.from + offset, to: edge.to + offset),
            ),
      );
    }
    return RmfLevel(
      name: json['name'] as String? ?? 'unknown',
      image: images.isEmpty ? null : RmfAffineImage.fromJson(images.first),
      vertices: vertices,
      edges: edges,
    );
  }
}

class RmfBuildingMap {
  const RmfBuildingMap({required this.name, required this.levels});

  final String name;
  final List<RmfLevel> levels;

  factory RmfBuildingMap.fromJson(Map<String, dynamic> json) => RmfBuildingMap(
    name: json['name'] as String? ?? 'Open-RMF',
    levels: _maps(json['levels']).map(RmfLevel.fromJson).toList(),
  );
}

class RmfRobot {
  const RmfRobot({
    required this.fleet,
    required this.name,
    required this.status,
    required this.level,
    required this.x,
    required this.y,
    required this.yaw,
    required this.battery,
    required this.taskId,
    required this.issueCount,
  });

  final String fleet;
  final String name;
  final String status;
  final String level;
  final double x;
  final double y;
  final double yaw;
  final double battery;
  final String? taskId;
  final int issueCount;

  bool get isWorking => status == 'working';

  static List<RmfRobot> fromFleetList(List<dynamic> json) {
    final result = <RmfRobot>[];
    for (final rawFleet in json.whereType<Map>()) {
      final fleet = Map<String, dynamic>.from(rawFleet);
      final fleetName = fleet['name'] as String? ?? 'unknown';
      final robots = fleet['robots'];
      if (robots is! Map) continue;
      for (final entry in robots.entries) {
        if (entry.value is! Map) continue;
        final state = Map<String, dynamic>.from(entry.value as Map);
        final location = state['location'] is Map
            ? Map<String, dynamic>.from(state['location'] as Map)
            : const <String, dynamic>{};
        result.add(
          RmfRobot(
            fleet: fleetName,
            name: state['name'] as String? ?? entry.key.toString(),
            status: state['status'] as String? ?? 'uninitialized',
            level: location['map'] as String? ?? '',
            x: _number(location['x']),
            y: _number(location['y']),
            yaw: _number(location['yaw']),
            battery: _number(state['battery']).clamp(0, 1),
            taskId: _nullableText(state['task_id']),
            issueCount: state['issues'] is List
                ? (state['issues'] as List).length
                : 0,
          ),
        );
      }
    }
    return result;
  }
}

class RmfTask {
  const RmfTask({
    required this.id,
    required this.category,
    required this.status,
    required this.fleet,
    required this.robot,
    required this.requestedAt,
  });

  final String id;
  final String category;
  final String status;
  final String? fleet;
  final String? robot;
  final DateTime? requestedAt;

  factory RmfTask.fromJson(Map<String, dynamic> json) {
    final booking = json['booking'] is Map
        ? Map<String, dynamic>.from(json['booking'] as Map)
        : const <String, dynamic>{};
    final assigned = json['assigned_to'] is Map
        ? Map<String, dynamic>.from(json['assigned_to'] as Map)
        : const <String, dynamic>{};
    final millis = booking['unix_millis_request_time'] as num?;
    return RmfTask(
      id: booking['id'] as String? ?? '-',
      category: _rootText(json['category']) ?? 'unknown',
      status: json['status'] as String? ?? 'uninitialized',
      fleet: _nullableText(assigned['group']),
      robot: _nullableText(assigned['name']),
      requestedAt: millis == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(millis.toInt()),
    );
  }
}

double _number(Object? value, {double fallback = 0}) =>
    value is num && value.isFinite ? value.toDouble() : fallback;

List<Map<String, dynamic>> _maps(Object? value) => value is List
    ? value.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
    : const [];

String? _nullableText(Object? value) {
  final text = value?.toString().trim() ?? '';
  return text.isEmpty ? null : text;
}

String? _rootText(Object? value) {
  if (value is String) return _nullableText(value);
  if (value is Map) return _nullableText(value['root']);
  return null;
}

double normalizeAngle(double angle) {
  var result = angle;
  while (result > math.pi) {
    result -= math.pi * 2;
  }
  while (result < -math.pi) {
    result += math.pi * 2;
  }
  return result;
}
