import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'deployment_service.dart';
import 'deployed_map_service.dart';

void main() => runApp(const RmfControlApp());

class RmfControlApp extends StatelessWidget {
  const RmfControlApp({super.key});

  @override
  Widget build(BuildContext context) {
    const navy = Color(0xFF111827);
    const blue = Color(0xFF2563EB);
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'RoboSapiens Control',
      theme: ThemeData(
        useMaterial3: true,
        fontFamily: 'sans-serif',
        scaffoldBackgroundColor: const Color(0xFFF5F7FA),
        colorScheme: ColorScheme.fromSeed(
          seedColor: blue,
          brightness: Brightness.light,
          surface: Colors.white,
        ),
        textTheme: const TextTheme(
          headlineMedium: TextStyle(
            color: navy,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.8,
          ),
          titleMedium: TextStyle(color: navy, fontWeight: FontWeight.w700),
          bodyMedium: TextStyle(color: Color(0xFF64748B)),
        ),
      ),
      home: const ControlDashboard(),
    );
  }
}

enum MapStage { upload, measurement, walls, floor, lanes, stations, deploy }

class _MapMeasurement {
  const _MapMeasurement({
    required this.start,
    required this.end,
    required this.length,
    required this.unit,
  });

  final Offset start;
  final Offset end;
  final double length;
  final String unit;
}

class UploadedDrawing {
  const UploadedDrawing({
    required this.name,
    required this.extension,
    required this.size,
    this.bytes,
    this.pixelWidth,
    this.pixelHeight,
  });

  final String name;
  final String extension;
  final int size;
  final Uint8List? bytes;
  final int? pixelWidth;
  final int? pixelHeight;

  bool get isImage => ['png', 'jpg', 'jpeg'].contains(extension);
  String get readableSize => size < 1024 * 1024
      ? '${(size / 1024).toStringAsFixed(1)} KB'
      : '${(size / 1024 / 1024).toStringAsFixed(1)} MB';
}

class _EditorSnapshot {
  const _EditorSnapshot({
    required this.drawing,
    required this.stage,
    required this.measurement,
    required this.wallMask,
    required this.floorMask,
    required this.previousWallMask,
    required this.wallsDetected,
    required this.floorGenerated,
    required this.manualWalls,
    required this.wallVertexOverrides,
    required this.frozenAutoWalls,
    required this.recommendedLanes,
    required this.laneDirections,
    required this.laneWaypoints,
    required this.waypointTypes,
    required this.waypointNames,
    required this.activeLaneEndpoint,
  });

  final UploadedDrawing? drawing;
  final MapStage stage;
  final _MapMeasurement? measurement;
  final _WallMask? wallMask;
  final _WallMask? floorMask;
  final _WallMask? previousWallMask;
  final bool wallsDetected;
  final bool floorGenerated;
  final List<(Offset, Offset)> manualWalls;
  final Map<Offset, Offset> wallVertexOverrides;
  final List<(Offset, Offset)> frozenAutoWalls;
  final List<(Offset, Offset)> recommendedLanes;
  final Map<(Offset, Offset), String> laneDirections;
  final List<Offset> laneWaypoints;
  final Map<Offset, String> waypointTypes;
  final Map<Offset, String> waypointNames;
  final Offset? activeLaneEndpoint;
}

class _LaneRecommendation {
  const _LaneRecommendation({
    required this.title,
    required this.description,
    required this.start,
    required this.end,
  });

  final String title;
  final String description;
  final Offset start;
  final Offset end;
}

enum _RobotKind { mockMobile, pinky, omxManipulator, mockHumanoid }

extension on _RobotKind {
  String get label => switch (this) {
    _RobotKind.mockMobile => 'Mock 주행로봇',
    _RobotKind.pinky => 'Pinky',
    _RobotKind.omxManipulator => 'OMX Manipulator',
    _RobotKind.mockHumanoid => 'Mock 휴머노이드',
  };

  bool get isMobile => this != _RobotKind.omxManipulator;
  bool get canCarry =>
      this == _RobotKind.mockMobile || this == _RobotKind.pinky;
}

class _MockRobot {
  _MockRobot({
    required this.id,
    required this.position,
    required this.color,
    required this.kind,
  });

  final String id;
  Offset position;
  final Color color;
  final _RobotKind kind;
  Offset? previousWaypoint;
  Offset? targetWaypoint;
  bool moving = false;
  double battery = 100;
  final List<Offset> assignedRoute = [];
  String? activeTaskId;
}

enum _MockTaskStatus { queued, active, completed, cancelled, failed }

enum _TaskStepType { navigate, armLoad, wait }

enum _TaskStepStatus { pending, active, completed, failed, cancelled }

class _MockTaskStep {
  _MockTaskStep({
    required this.type,
    this.destination,
    this.destinationName,
    this.durationSeconds = 0,
  });

  final _TaskStepType type;
  final Offset? destination;
  final String? destinationName;
  final double durationSeconds;
  _TaskStepStatus status = _TaskStepStatus.pending;
  double remainingSeconds = 0;
  String? failureReason;

  String get label => switch (type) {
    _TaskStepType.navigate => 'Pinky 이동 · $destinationName',
    _TaskStepType.armLoad => 'OMX-AI 픽업/적재',
    _TaskStepType.wait => '대기 · ${durationSeconds.toStringAsFixed(0)}초',
  };
}

class _MockTask {
  _MockTask({
    required this.id,
    required this.name,
    required this.description,
    required this.type,
    required this.robotId,
    required this.steps,
  });

  final String id;
  final String name;
  final String description;
  final String type;
  final String robotId;
  final List<_MockTaskStep> steps;
  int currentStepIndex = 0;
  _MockTaskStatus status = _MockTaskStatus.queued;
  final DateTime createdAt = DateTime.now();
  DateTime? completedAt;

  _MockTaskStep? get currentStep =>
      currentStepIndex < steps.length ? steps[currentStepIndex] : null;
}

class _TaskStepDraft {
  _TaskStepDraft(this.type, {this.destination});

  _TaskStepType type;
  Offset? destination;
  double durationSeconds = 3;
}

class _TaskEditorResult {
  const _TaskEditorResult({
    required this.name,
    required this.description,
    required this.robotId,
    required this.steps,
  });

  final String name;
  final String description;
  final String robotId;
  final List<_TaskStepDraft> steps;
}

class ControlDashboard extends StatefulWidget {
  const ControlDashboard({super.key});

  @override
  State<ControlDashboard> createState() => _ControlDashboardState();
}

class _ControlDashboardState extends State<ControlDashboard> {
  final TransformationController _mapTransform = TransformationController();
  UploadedDrawing? _drawing;
  MapStage _stage = MapStage.upload;
  bool _isPicking = false;
  bool _isDeployed = false;
  bool _isDetectingWalls = false;
  bool _isGeneratingFloor = false;
  bool _wallsDetected = false;
  bool _floorGenerated = false;
  _WallMask? _wallMask;
  _WallMask? _floorMask;
  _WallMask? _previousWallMask;
  Color _wallColor = const Color(0xFF2563EB);
  Color _floorColor = const Color(0xFF22C55E);
  bool _isWallEraseMode = false;
  bool _isMeasurementMode = false;
  _MapMeasurement? _measurement;
  bool _isMeasurementSelected = false;
  bool _showDrawingInfo = true;
  bool _isWallConnectMode = false;
  Offset? _pendingWallVertex;
  final List<(Offset, Offset)> _manualWalls = [];
  bool _isWallEndpointEditMode = false;
  final Map<Offset, Offset> _wallVertexOverrides = {};
  List<(Offset, Offset)> _frozenAutoWalls = [];
  List<(Offset, Offset)> _recommendedLanes = [];
  final Map<(Offset, Offset), String> _laneDirections = {};
  final List<Offset> _laneWaypoints = [];
  final Map<Offset, String> _waypointTypes = {};
  final Map<Offset, String> _waypointNames = {};
  Offset? _activeLaneEndpoint;
  bool _isWaypointMode = false;
  int _vertexLabelRevision = 0;
  bool _showVertexLabels = true;
  final List<_EditorSnapshot> _undoHistory = [];
  String? _processingWarning;
  int _selectedMenu = 0;
  final List<_MockRobot> _mockRobots = [];
  final List<_MockTask> _mockTasks = [];
  Timer? _mockRobotTimer;
  DeployedMapData? _robotDeployedMap;

  void _showProcessingWarning(String operation, Object error) {
    if (!mounted) return;
    final message = [
      '[$operation] 맵 처리 중 문제가 발생했습니다.',
      '원인: $error',
      '도면과 설정값을 확인한 뒤 다시 시도해 주세요.',
    ].join('\n');
    setState(() => _processingWarning = message);
  }

  void _clearProcessingWarning() {
    if (_processingWarning != null) {
      setState(() => _processingWarning = null);
    }
  }

  List<String> _validateMap() {
    final warnings = <String>[];
    if (_measurement == null) {
      warnings.add('기준 길이(Measurement)가 없어 실제 축척을 계산할 수 없습니다.');
    }
    if (_floorOutline().length < 3) {
      warnings.add('Floor 경계를 구성할 정점이 3개보다 적습니다.');
    }
    if (_recommendedLanes.isEmpty) {
      warnings.add('Lane이 하나도 없습니다.');
    } else {
      final zeroLengthLaneCount = _recommendedLanes
          .where((lane) => (lane.$1 - lane.$2).distance <= .01)
          .length;
      if (zeroLengthLaneCount > 0) {
        warnings.add('시작점과 끝점이 같은 Lane이 $zeroLengthLaneCount개 있습니다.');
      }
      final adjacency = <Offset, Set<Offset>>{};
      for (final lane in _recommendedLanes) {
        adjacency.putIfAbsent(lane.$1, () => <Offset>{}).add(lane.$2);
        adjacency.putIfAbsent(lane.$2, () => <Offset>{}).add(lane.$1);
      }
      final visited = <Offset>{};
      final queue = <Offset>[adjacency.keys.first];
      while (queue.isNotEmpty) {
        final point = queue.removeLast();
        if (!visited.add(point)) continue;
        queue.addAll(
          adjacency[point]!.where((next) => !visited.contains(next)),
        );
      }
      final disconnected = adjacency.keys.where(
        (point) => !visited.contains(point),
      );
      if (disconnected.isNotEmpty) {
        final names = disconnected
            .map((point) => _waypointNames[point])
            .whereType<String>()
            .where((name) => name.isNotEmpty)
            .toList();
        warnings.add(
          'Lane 네트워크가 분리되어 접근할 수 없는 Waypoint가 있습니다'
          '${names.isEmpty ? '' : ': ${names.join(', ')}'}.',
        );
      }
    }
    final names = _waypointNames.values
        .map((name) => name.trim())
        .where((name) => name.isNotEmpty);
    final seenNames = <String>{};
    final duplicateNames = <String>{};
    for (final name in names) {
      if (!seenNames.add(name)) duplicateNames.add(name);
    }
    if (duplicateNames.isNotEmpty) {
      warnings.add('중복된 Waypoint 이름이 있습니다: ${duplicateNames.join(', ')}.');
    }
    return warnings;
  }

  Future<void> _showValidationDialog() async {
    if (_drawing == null) return;
    final warnings = _validateMap();
    final report = [
      'YAML 오류 검증 결과',
      '파일: $_yamlFileName',
      '',
      if (warnings.isEmpty)
        '검증된 문제점이 없습니다.'
      else ...[
        'Warning ${warnings.length}건',
        for (var i = 0; i < warnings.length; i++) '${i + 1}. ${warnings[i]}',
      ],
    ].join('\n');
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: Icon(
          warnings.isEmpty
              ? Icons.verified_outlined
              : Icons.warning_amber_rounded,
          color: warnings.isEmpty
              ? const Color(0xFF15803D)
              : const Color(0xFFD97706),
          size: 36,
        ),
        title: const Text('YAML 오류 검증'),
        content: SizedBox(
          width: 560,
          child: Container(
            constraints: const BoxConstraints(maxHeight: 420),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: warnings.isEmpty
                  ? const Color(0xFFF0FDF4)
                  : const Color(0xFFFFFBEB),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: warnings.isEmpty
                    ? const Color(0xFF86EFAC)
                    : const Color(0xFFFCD34D),
              ),
            ),
            child: SingleChildScrollView(child: SelectableText(report)),
          ),
        ),
        actions: [
          TextButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: report));
              if (!dialogContext.mounted) return;
              ScaffoldMessenger.of(
                dialogContext,
              ).showSnackBar(const SnackBar(content: Text('검증 결과를 복사했습니다.')));
            },
            icon: const Icon(Icons.copy_outlined, size: 18),
            label: const Text('결과 복사'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('확인'),
          ),
        ],
      ),
    );
  }

  String _waypointLabel(Offset point) {
    final name = (_waypointNames[point] ?? '').trim();
    if (name.isNotEmpty) return name;
    final index = _laneWaypoints.indexOf(point);
    return index < 0 ? 'Waypoint' : 'Waypoint ${index + 1}';
  }

  bool _hasLane(Offset start, Offset end) => _recommendedLanes.any(
    (lane) =>
        ((lane.$1 - start).distance <= .01 &&
            (lane.$2 - end).distance <= .01) ||
        ((lane.$1 - end).distance <= .01 && (lane.$2 - start).distance <= .01),
  );

  bool _segmentsCross(Offset a, Offset b, Offset c, Offset d) {
    double side(Offset p, Offset q, Offset r) =>
        (q.dx - p.dx) * (r.dy - p.dy) - (q.dy - p.dy) * (r.dx - p.dx);
    final abC = side(a, b, c);
    final abD = side(a, b, d);
    final cdA = side(c, d, a);
    final cdB = side(c, d, b);
    return abC * abD < 0 && cdA * cdB < 0;
  }

  bool _crossesWall(Offset start, Offset end) => _visibleWallSegments().any(
    (wall) => _segmentsCross(start, end, wall.$1, wall.$2),
  );

  List<_LaneRecommendation> _buildLaneRecommendations() {
    if (_recommendedLanes.isEmpty) return const [];
    final adjacency = <Offset, Set<Offset>>{};
    for (final lane in _recommendedLanes) {
      adjacency.putIfAbsent(lane.$1, () => <Offset>{}).add(lane.$2);
      adjacency.putIfAbsent(lane.$2, () => <Offset>{}).add(lane.$1);
    }
    final components = <Set<Offset>>[];
    final unvisited = adjacency.keys.toSet();
    while (unvisited.isNotEmpty) {
      final component = <Offset>{};
      final queue = <Offset>[unvisited.first];
      while (queue.isNotEmpty) {
        final point = queue.removeLast();
        if (!component.add(point)) continue;
        unvisited.remove(point);
        queue.addAll(
          adjacency[point]!.where((next) => !component.contains(next)),
        );
      }
      components.add(component);
    }

    final recommendations = <_LaneRecommendation>[];
    components.sort((a, b) => b.length.compareTo(a.length));
    final mainComponent = components.first;
    for (final component in components.skip(1)) {
      Offset? bestStart;
      Offset? bestEnd;
      var bestDistance = double.infinity;
      for (final start in mainComponent) {
        for (final end in component) {
          final distance = (start - end).distance;
          if (distance < bestDistance && !_crossesWall(start, end)) {
            bestDistance = distance;
            bestStart = start;
            bestEnd = end;
          }
        }
      }
      if (bestStart != null && bestEnd != null) {
        recommendations.add(
          _LaneRecommendation(
            title: '분리된 구역 연결',
            description:
                '${_waypointLabel(bestStart)} ↔ ${_waypointLabel(bestEnd)}를 연결하면 접근 불가능한 구역이 해소됩니다.',
            start: bestStart,
            end: bestEnd,
          ),
        );
      }
    }

    for (final entry in adjacency.entries) {
      if (recommendations.length >= 8) break;
      if (entry.value.length != 1) continue;
      final category = _waypointTypes[entry.key] ?? '일반';
      if (category == '충전' || category == '대기') continue;
      Offset? nearest;
      var nearestDistance = double.infinity;
      for (final candidate in adjacency.keys) {
        if (candidate == entry.key || entry.value.contains(candidate)) continue;
        if (_hasLane(entry.key, candidate)) continue;
        if (_crossesWall(entry.key, candidate)) continue;
        final distance = (entry.key - candidate).distance;
        if (distance < nearestDistance) {
          nearest = candidate;
          nearestDistance = distance;
        }
      }
      if (nearest == null) continue;
      final duplicate = recommendations.any(
        (item) =>
            (item.start == entry.key && item.end == nearest) ||
            (item.start == nearest && item.end == entry.key),
      );
      if (duplicate) continue;
      recommendations.add(
        _LaneRecommendation(
          title: '막다른 경로에 우회로 추가',
          description:
              '${_waypointLabel(entry.key)} ↔ ${_waypointLabel(nearest)}를 연결하면 단일 경로 의존도를 줄일 수 있습니다.',
          start: entry.key,
          end: nearest,
        ),
      );
    }
    return recommendations;
  }

  Future<void> _showLaneRecommendationsDialog() async {
    final recommendations = _buildLaneRecommendations();
    if (!mounted) return;
    if (recommendations.isEmpty) {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          icon: const Icon(
            Icons.route_outlined,
            color: Color(0xFF15803D),
            size: 36,
          ),
          title: const Text('경로 추천'),
          content: const Text('현재 Lane 구성에서 바로 적용할 추가 경로를 찾지 못했습니다.'),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('확인'),
            ),
          ],
        ),
      );
      return;
    }

    final selected = <int>{};
    final directions = <int, String>{
      for (var i = 0; i < recommendations.length; i++) i: '양방향',
    };
    final result =
        await showDialog<({Set<int> selected, Map<int, String> directions})>(
          context: context,
          builder: (dialogContext) => StatefulBuilder(
            builder: (context, setDialogState) => AlertDialog(
              icon: const Icon(
                Icons.auto_awesome_outlined,
                color: Color(0xFF2563EB),
                size: 36,
              ),
              title: const Text('효율적인 경로 추천'),
              content: SizedBox(
                width: 650,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('적용할 추천을 선택하고 각 Lane의 이동 방향을 수정할 수 있습니다.'),
                    const SizedBox(height: 14),
                    Flexible(
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: recommendations.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final item = recommendations[index];
                          return CheckboxListTile(
                            value: selected.contains(index),
                            onChanged: (checked) => setDialogState(() {
                              checked == true
                                  ? selected.add(index)
                                  : selected.remove(index);
                            }),
                            title: Text(item.title),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const SizedBox(height: 4),
                                Text(item.description),
                                const SizedBox(height: 8),
                                DropdownButton<String>(
                                  value: directions[index],
                                  items: const [
                                    DropdownMenuItem(
                                      value: '양방향',
                                      child: Text('양방향'),
                                    ),
                                    DropdownMenuItem(
                                      value: '정방향',
                                      child: Text('정방향'),
                                    ),
                                    DropdownMenuItem(
                                      value: '역방향',
                                      child: Text('역방향'),
                                    ),
                                  ],
                                  onChanged: (value) {
                                    if (value != null) {
                                      setDialogState(
                                        () => directions[index] = value,
                                      );
                                    }
                                  },
                                ),
                              ],
                            ),
                            controlAffinity: ListTileControlAffinity.leading,
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('취소'),
                ),
                FilledButton.icon(
                  onPressed: selected.isEmpty
                      ? null
                      : () => Navigator.pop(dialogContext, (
                          selected: {...selected},
                          directions: {...directions},
                        )),
                  icon: const Icon(Icons.auto_fix_high, size: 18),
                  label: Text('선택 적용 (${selected.length})'),
                ),
              ],
            ),
          ),
        );
    if (result == null || !mounted) return;
    _recordUndo();
    setState(() {
      for (final index in result.selected) {
        final recommendation = recommendations[index];
        if (_hasLane(recommendation.start, recommendation.end)) continue;
        final lane = (recommendation.start, recommendation.end);
        _recommendedLanes.add(lane);
        _laneDirections[lane] = result.directions[index] ?? '양방향';
      }
      _stage = MapStage.lanes;
      _isDeployed = false;
      _vertexLabelRevision++;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('추천 Lane ${result.selected.length}개를 적용했습니다.')),
    );
  }

  bool _showMapValidationWarnings() {
    final warnings = _validateMap();
    if (warnings.isEmpty) return false;
    setState(() {
      _processingWarning = [
        '[맵 검증] 배포 전에 확인이 필요합니다.',
        for (var i = 0; i < warnings.length; i++) '${i + 1}. ${warnings[i]}',
      ].join('\n');
    });
    return true;
  }

  _EditorSnapshot _captureSnapshot() => _EditorSnapshot(
    drawing: _drawing,
    stage: _stage,
    measurement: _measurement,
    wallMask: _wallMask,
    floorMask: _floorMask,
    previousWallMask: _previousWallMask,
    wallsDetected: _wallsDetected,
    floorGenerated: _floorGenerated,
    manualWalls: [..._manualWalls],
    wallVertexOverrides: {..._wallVertexOverrides},
    frozenAutoWalls: [..._frozenAutoWalls],
    recommendedLanes: [..._recommendedLanes],
    laneDirections: {..._laneDirections},
    laneWaypoints: [..._laneWaypoints],
    waypointTypes: {..._waypointTypes},
    waypointNames: {..._waypointNames},
    activeLaneEndpoint: _activeLaneEndpoint,
  );

  void _recordUndo() {
    _undoHistory.add(_captureSnapshot());
    if (_undoHistory.length > 10) _undoHistory.removeAt(0);
  }

  void _undo() {
    if (_undoHistory.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('되돌릴 작업이 없습니다.')));
      return;
    }
    final snapshot = _undoHistory.removeLast();
    setState(() {
      _drawing = snapshot.drawing;
      _stage = snapshot.stage;
      _measurement = snapshot.measurement;
      _wallMask = snapshot.wallMask;
      _floorMask = snapshot.floorMask;
      _previousWallMask = snapshot.previousWallMask;
      _wallsDetected = snapshot.wallsDetected;
      _floorGenerated = snapshot.floorGenerated;
      _manualWalls
        ..clear()
        ..addAll(snapshot.manualWalls);
      _wallVertexOverrides
        ..clear()
        ..addAll(snapshot.wallVertexOverrides);
      _frozenAutoWalls = [...snapshot.frozenAutoWalls];
      _recommendedLanes = [...snapshot.recommendedLanes];
      _laneDirections
        ..clear()
        ..addAll(snapshot.laneDirections);
      _laneWaypoints
        ..clear()
        ..addAll(snapshot.laneWaypoints);
      _waypointTypes
        ..clear()
        ..addAll(snapshot.waypointTypes);
      _waypointNames
        ..clear()
        ..addAll(snapshot.waypointNames);
      _activeLaneEndpoint = snapshot.activeLaneEndpoint;
      _isWaypointMode = false;
      _isMeasurementMode = false;
      _isWallEraseMode = false;
      _isWallConnectMode = false;
      _isWallEndpointEditMode = false;
      _pendingWallVertex = null;
      _isDeployed = false;
      _vertexLabelRevision++;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('이전 작업으로 되돌렸습니다. (${_undoHistory.length}단계 남음)')),
    );
  }

  Future<void> _pickDrawing() async {
    if (_isPicking) return;
    setState(() => _isPicking = true);
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['png', 'jpg', 'jpeg', 'pdf', 'dxf', 'dwg'],
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;
      final file = result.files.single;
      final extension = (file.extension ?? '').toLowerCase();
      int? pixelWidth;
      int? pixelHeight;
      if (['png', 'jpg', 'jpeg'].contains(extension) && file.bytes != null) {
        final codec = await ui.instantiateImageCodec(file.bytes!);
        final frame = await codec.getNextFrame();
        pixelWidth = frame.image.width;
        pixelHeight = frame.image.height;
        frame.image.dispose();
        codec.dispose();
      }
      if (!mounted) return;
      _fitMapToScreen();
      _recordUndo();
      setState(() {
        _drawing = UploadedDrawing(
          name: file.name,
          extension: extension,
          size: file.size,
          bytes: file.bytes,
          pixelWidth: pixelWidth,
          pixelHeight: pixelHeight,
        );
        _stage = MapStage.upload;
        _isDeployed = false;
        _wallMask = null;
        _floorMask = null;
        _wallsDetected = false;
        _floorGenerated = false;
        _previousWallMask = null;
        _isWallEraseMode = false;
        _isMeasurementMode = false;
        _measurement = null;
        _isMeasurementSelected = false;
        _showDrawingInfo = true;
        _isWallConnectMode = false;
        _pendingWallVertex = null;
        _manualWalls.clear();
        _isWallEndpointEditMode = false;
        _wallVertexOverrides.clear();
        _frozenAutoWalls = [];
        _recommendedLanes = [];
        _laneDirections.clear();
        _laneWaypoints.clear();
        _waypointTypes.clear();
        _waypointNames.clear();
        _activeLaneEndpoint = null;
        _isWaypointMode = false;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('${file.name} 도면을 불러왔습니다.')));
    } catch (error) {
      if (!mounted) return;
      _showProcessingWarning('도면 불러오기', error);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('파일을 불러오지 못했습니다: $error')));
    } finally {
      if (mounted) setState(() => _isPicking = false);
    }
  }

  void _removeDrawing() {
    if (_drawing == null) return;
    _recordUndo();
    _fitMapToScreen();
    setState(() {
      _drawing = null;
      _stage = MapStage.upload;
      _isDeployed = false;
      _wallMask = null;
      _floorMask = null;
      _wallsDetected = false;
      _floorGenerated = false;
      _previousWallMask = null;
      _isWallEraseMode = false;
      _isMeasurementMode = false;
      _measurement = null;
      _isMeasurementSelected = false;
      _showDrawingInfo = false;
      _isWallConnectMode = false;
      _pendingWallVertex = null;
      _manualWalls.clear();
      _isWallEndpointEditMode = false;
      _wallVertexOverrides.clear();
      _frozenAutoWalls = [];
      _recommendedLanes = [];
      _laneDirections.clear();
      _laneWaypoints.clear();
      _waypointTypes.clear();
      _waypointNames.clear();
      _activeLaneEndpoint = null;
      _isWaypointMode = false;
    });
  }

  void _zoomMap(double factor) {
    final current = _mapTransform.value.getMaxScaleOnAxis();
    final next = (current * factor).clamp(.4, 5.0);
    _mapTransform.value = Matrix4.diagonal3Values(next, next, 1);
  }

  void _fitMapToScreen() {
    _mapTransform.value = Matrix4.identity();
  }

  Future<void> _renumberVertices() async {
    final count = _visibleMapVertices().length;
    setState(() {
      _pendingWallVertex = null;
      _isMeasurementSelected = false;
      _showVertexLabels = false;
    });
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    setState(() {
      _vertexLabelRevision++;
      _showVertexLabels = true;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('정점 $count개를 왼쪽 시작 시계방향으로 재넘버링했습니다.')),
    );
  }

  void _toggleWaypointMode() {
    if (_drawing == null) return;
    if (!_floorGenerated) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Floor를 먼저 생성해주세요.')));
      return;
    }
    setState(() {
      _isWaypointMode = !_isWaypointMode;
      if (!_isWaypointMode) _activeLaneEndpoint = null;
      _isWallEraseMode = false;
      _isMeasurementMode = false;
      _isWallConnectMode = false;
      _isWallEndpointEditMode = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _isWaypointMode
              ? '도면을 눌러 Waypoint를 순서대로 입력하세요.'
              : 'Waypoint 입력을 완료했습니다.',
        ),
      ),
    );
  }

  void _finishCurrentLane() {
    if (!_isWaypointMode || _activeLaneEndpoint == null) return;
    setState(() => _activeLaneEndpoint = null);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('현재 레인을 종료했습니다. 새 시작점을 선택하세요.')),
    );
  }

  Offset? _firstCrossedWaypoint(Offset start, Offset end, double tolerance) {
    final lane = end - start;
    final lengthSquared = lane.distanceSquared;
    if (lengthSquared <= .01) return null;
    Offset? crossed;
    var firstT = 1.0;
    for (final waypoint in _laneWaypoints) {
      if ((waypoint - start).distance <= tolerance) continue;
      final relative = waypoint - start;
      final t = (relative.dx * lane.dx + relative.dy * lane.dy) / lengthSquared;
      if (t <= .02 || t >= .98 || t >= firstT) continue;
      final nearest = start + lane * t;
      if ((waypoint - nearest).distance <= tolerance) {
        crossed = waypoint;
        firstT = t;
      }
    }
    return crossed;
  }

  Future<String?> _chooseWaypointAction(Offset waypoint) => showDialog<String>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(
        (_waypointNames[waypoint] ?? '').trim().isEmpty
            ? 'Waypoint 선택'
            : _waypointNames[waypoint]!,
      ),
      content: Text(
        '카테고리: ${_waypointTypes[waypoint] ?? '일반'}\n'
        '이 Waypoint에서 수행할 작업을 선택하세요.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('취소'),
        ),
        TextButton.icon(
          onPressed: () => Navigator.pop(dialogContext, 'delete'),
          icon: const Icon(Icons.delete_outline),
          label: const Text('Waypoint 삭제'),
          style: TextButton.styleFrom(foregroundColor: const Color(0xFFDC2626)),
        ),
        FilledButton.icon(
          onPressed: () => Navigator.pop(dialogContext, 'connect'),
          icon: const Icon(Icons.route, size: 18),
          label: const Text('레인 시작점으로 사용'),
        ),
      ],
    ),
  );

  void _deleteWaypoint(Offset waypoint) {
    _recordUndo();
    var removedLane = false;
    setState(() {
      for (var i = _recommendedLanes.length - 1; i >= 0; i--) {
        final lane = _recommendedLanes[i];
        if ((lane.$1 - waypoint).distance <= .01 ||
            (lane.$2 - waypoint).distance <= .01) {
          _laneDirections.remove(lane);
          _recommendedLanes.removeAt(i);
          removedLane = true;
          break;
        }
      }
      _laneWaypoints.removeWhere((point) => (point - waypoint).distance <= .01);
      _waypointTypes.remove(waypoint);
      _waypointNames.remove(waypoint);
      if (_activeLaneEndpoint != null &&
          (_activeLaneEndpoint! - waypoint).distance <= .01) {
        _activeLaneEndpoint = null;
      }
      _isDeployed = false;
      _vertexLabelRevision++;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          removedLane ? 'Waypoint와 마지막 연결 레인을 삭제했습니다.' : 'Waypoint를 삭제했습니다.',
        ),
      ),
    );
  }

  String _nextWaypointName(String category) {
    if (category == '일반') return ' ';
    var maxNumber = 0;
    final pattern = RegExp('^${RegExp.escape(category)}([0-9]+)\$');
    for (final entry in _waypointTypes.entries) {
      if (entry.value != category) continue;
      final name = _waypointNames[entry.key] ?? '';
      final match = pattern.firstMatch(name);
      final number = match == null ? null : int.tryParse(match.group(1)!);
      if (number != null) maxNumber = math.max(maxNumber, number);
    }
    return '$category${maxNumber + 1}';
  }

  Future<void> _editWaypoint(Offset waypoint) async {
    final nameController = TextEditingController(
      text: _waypointNames[waypoint] ?? '',
    );
    var selectedType = _waypointTypes[waypoint] == '드롭오프'
        ? '드랍오프'
        : _waypointTypes[waypoint] ?? '일반';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Waypoint 수정'),
          content: SizedBox(
            width: 360,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  autofocus: true,
                  decoration: InputDecoration(
                    labelText: 'Waypoint 이름',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (_) => setDialogState(() {}),
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<String>(
                  initialValue: selectedType,
                  decoration: const InputDecoration(
                    labelText: 'Waypoint 카테고리',
                    border: OutlineInputBorder(),
                  ),
                  items: const ['일반', '대기', '충전', '픽업', '드랍오프']
                      .map(
                        (type) =>
                            DropdownMenuItem(value: type, child: Text(type)),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value != null) {
                      setDialogState(() => selectedType = value);
                    }
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('취소'),
            ),
            FilledButton(
              onPressed:
                  selectedType != '일반' && nameController.text.trim().isEmpty
                  ? null
                  : () => Navigator.pop(dialogContext, true),
              child: const Text('저장'),
            ),
          ],
        ),
      ),
    );
    final name = selectedType == '일반' ? ' ' : nameController.text.trim();
    await Future<void>.delayed(const Duration(milliseconds: 350));
    nameController.dispose();
    if (confirmed != true || !mounted || name.isEmpty) return;
    _recordUndo();
    setState(() {
      _waypointNames[waypoint] = name;
      _waypointTypes[waypoint] = selectedType;
      _isDeployed = false;
    });
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Waypoint 정보를 수정했습니다.')));
  }

  Future<void> _selectLaneForDeletion((Offset, Offset) lane) async {
    var selectedDirection = _laneDirections[lane] ?? '양방향';
    final result = await showDialog<(String, String)>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          icon: const Icon(Icons.route_outlined, color: Color(0xFF2563EB)),
          title: const Text('레인 설정'),
          content: SizedBox(
            width: 390,
            child: DropdownButtonFormField<String>(
              initialValue: selectedDirection,
              decoration: const InputDecoration(
                labelText: '이동 방향',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(
                  value: '정방향',
                  child: Text('단방향 · 정방향 (시작 → 끝)'),
                ),
                DropdownMenuItem(value: '양방향', child: Text('양방향 (시작 ↔ 끝)')),
                DropdownMenuItem(
                  value: '역방향',
                  child: Text('단방향 · 역방향 (끝 → 시작)'),
                ),
              ],
              onChanged: (value) {
                if (value != null) {
                  setDialogState(() => selectedDirection = value);
                }
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('취소'),
            ),
            TextButton.icon(
              onPressed: () =>
                  Navigator.pop(dialogContext, ('delete', selectedDirection)),
              icon: const Icon(Icons.delete_outline),
              label: const Text('레인 삭제'),
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFFDC2626),
              ),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.pop(dialogContext, ('save', selectedDirection)),
              child: const Text('방향 저장'),
            ),
          ],
        ),
      ),
    );
    if (result == null || !mounted) return;
    final index = _recommendedLanes.indexWhere(
      (candidate) =>
          (candidate.$1 - lane.$1).distance <= .01 &&
          (candidate.$2 - lane.$2).distance <= .01,
    );
    if (index < 0) return;
    _recordUndo();
    setState(() {
      if (result.$1 == 'delete') {
        final removed = _recommendedLanes.removeAt(index);
        _laneDirections.remove(removed);
      } else {
        _laneDirections[_recommendedLanes[index]] = result.$2;
      }
      _isDeployed = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          result.$1 == 'delete' ? '선택한 레인을 삭제했습니다.' : '${result.$2}으로 설정했습니다.',
        ),
      ),
    );
  }

  Future<void> _addLaneWaypoint(Offset point) async {
    final drawing = _drawing;
    final snapTolerance =
        drawing?.pixelWidth != null && drawing?.pixelHeight != null
        ? math.min(drawing!.pixelWidth!, drawing.pixelHeight!) * .02
        : 16.0;
    Offset? snappedWaypoint;
    var nearestDistance = snapTolerance;
    for (final waypoint in _laneWaypoints) {
      final distance = (waypoint - point).distance;
      if (distance <= nearestDistance) {
        snappedWaypoint = waypoint;
        nearestDistance = distance;
      }
    }
    if (snappedWaypoint != null) {
      final snapped = snappedWaypoint;
      final action = await _chooseWaypointAction(snapped);
      if (!mounted || action == null) return;
      if (action == 'delete') {
        _deleteWaypoint(snapped);
        return;
      }
      final start = _activeLaneEndpoint;
      if (start != null && (start - snapped).distance <= .01) return;
      final crossed = start == null
          ? null
          : _firstCrossedWaypoint(start, snapped, snapTolerance);
      final laneStart = crossed ?? start;
      _recordUndo();
      setState(() {
        if (laneStart != null) {
          final lane = (laneStart, snapped);
          _recommendedLanes.add(lane);
          _laneDirections[lane] = '양방향';
        }
        _activeLaneEndpoint = snapped;
        _stage = MapStage.lanes;
        _isDeployed = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            crossed != null
                ? '중간 Waypoint를 통과하여 해당 지점부터 레인을 연결했습니다.'
                : start == null
                ? '기존 Waypoint에 스냅했습니다. 새 레인의 시작점입니다.'
                : '기존 Waypoint에 스냅하여 레인을 연결했습니다.',
          ),
        ),
      );
      return;
    }
    final floorPoint = _floorCoordinate(point);
    final activeEndpoint = _activeLaneEndpoint;
    final crossedWaypoint = activeEndpoint == null
        ? null
        : _firstCrossedWaypoint(activeEndpoint, point, snapTolerance);
    var selectedType = '일반';
    final nameController = TextEditingController(
      text: _nextWaypointName(selectedType),
    );
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Waypoint 추가'),
          content: SizedBox(
            width: 360,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '좌표  X ${floorPoint.dx.toStringAsFixed(1)}  ·  Y ${floorPoint.dy.toStringAsFixed(1)}',
                  style: const TextStyle(
                    color: Color(0xFF475569),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 18),
                TextField(
                  controller: nameController,
                  readOnly: true,
                  decoration: InputDecoration(
                    labelText: '자동 이름',
                    hintText: selectedType == '일반' ? '(공백)' : null,
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<String>(
                  initialValue: selectedType,
                  decoration: const InputDecoration(
                    labelText: 'Waypoint 카테고리',
                    border: OutlineInputBorder(),
                  ),
                  items: const ['일반', '대기', '충전', '픽업', '드랍오프']
                      .map(
                        (type) =>
                            DropdownMenuItem(value: type, child: Text(type)),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value != null) {
                      setDialogState(() {
                        selectedType = value;
                        nameController.text = _nextWaypointName(value);
                      });
                    }
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('취소'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('추가'),
            ),
          ],
        ),
      ),
    );
    final waypointName = selectedType == '일반'
        ? ' '
        : nameController.text.trim();
    nameController.dispose();
    if (confirmed != true || !mounted) return;
    _recordUndo();
    setState(() {
      final laneStart = crossedWaypoint ?? _activeLaneEndpoint;
      if (laneStart != null) {
        final lane = (laneStart, point);
        _recommendedLanes.add(lane);
        _laneDirections[lane] = '양방향';
      }
      _laneWaypoints.add(point);
      _waypointTypes[point] = selectedType;
      _waypointNames[point] = waypointName;
      _activeLaneEndpoint = point;
      _stage = MapStage.lanes;
      _isDeployed = false;
      _vertexLabelRevision++;
    });
    if (crossedWaypoint != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('통과한 Waypoint부터 새 레인을 시작했습니다.')),
      );
    }
  }

  Offset _floorCoordinate(Offset point) {
    final floorPoints = _floorMask?.points;
    if (floorPoints == null || floorPoints.isEmpty) return point;
    final bounds = _pointsBounds(floorPoints);
    return Offset(point.dx - bounds.left, bounds.bottom - point.dy);
  }

  List<Offset> _outgoingWaypoints(Offset point) {
    final result = <Offset>[];
    final loadedMap = _robotDeployedMap;
    final lanes = loadedMap?.lanes ?? _recommendedLanes;
    for (final lane in lanes) {
      final direction = loadedMap == null
          ? _laneDirections[lane] ?? '양방향'
          : '양방향';
      if ((lane.$1 - point).distance <= .01 && direction != '역방향') {
        result.add(lane.$2);
      }
      if ((lane.$2 - point).distance <= .01 && direction != '정방향') {
        result.add(lane.$1);
      }
    }
    return result;
  }

  List<Offset>? _shortestRobotPath(Offset start, Offset destination) {
    final points = <Offset>{start, destination};
    final edges = <Offset, List<(Offset, double)>>{};
    final loadedMap = _robotDeployedMap;
    final lanes = loadedMap?.lanes ?? _recommendedLanes;
    for (final lane in lanes) {
      points.addAll([lane.$1, lane.$2]);
      final direction = loadedMap == null
          ? _laneDirections[lane] ?? '양방향'
          : '양방향';
      final distance = (lane.$1 - lane.$2).distance;
      if (direction != '역방향') {
        edges.putIfAbsent(lane.$1, () => []).add((lane.$2, distance));
      }
      if (direction != '정방향') {
        edges.putIfAbsent(lane.$2, () => []).add((lane.$1, distance));
      }
    }
    final distances = {for (final point in points) point: double.infinity};
    final previous = <Offset, Offset>{};
    final unvisited = points.toSet();
    distances[start] = 0;
    while (unvisited.isNotEmpty) {
      Offset? current;
      var best = double.infinity;
      for (final point in unvisited) {
        final distance = distances[point]!;
        if (distance < best) {
          best = distance;
          current = point;
        }
      }
      if (current == null || best == double.infinity) break;
      unvisited.remove(current);
      if (current == destination) break;
      for (final edge in edges[current] ?? const []) {
        final candidate = best + edge.$2;
        if (candidate < distances[edge.$1]!) {
          distances[edge.$1] = candidate;
          previous[edge.$1] = current;
        }
      }
    }
    if (start != destination && !previous.containsKey(destination)) return null;
    final path = <Offset>[destination];
    while (path.last != start) {
      final parent = previous[path.last];
      if (parent == null) return null;
      path.add(parent);
    }
    return path.reversed.toList();
  }

  void _finishRobotTask(_MockRobot robot) {
    final taskId = robot.activeTaskId;
    if (taskId == null) return;
    final task = _mockTasks.where((item) => item.id == taskId).firstOrNull;
    if (task != null && task.status == _MockTaskStatus.active) {
      task.status = _MockTaskStatus.completed;
      task.completedAt = DateTime.now();
    }
    robot.activeTaskId = null;
    robot.moving = false;
  }

  void _failRobotTask(_MockRobot robot, _MockTask task, String reason) {
    final step = task.currentStep;
    if (step != null) {
      step.status = _TaskStepStatus.failed;
      step.failureReason = reason;
    }
    task.status = _MockTaskStatus.failed;
    task.completedAt = DateTime.now();
    robot
      ..activeTaskId = null
      ..moving = false
      ..targetWaypoint = null
      ..assignedRoute.clear();
  }

  void _startTaskStep(_MockRobot robot, _MockTask task) {
    final step = task.currentStep;
    if (step == null) {
      _finishRobotTask(robot);
      return;
    }
    step.status = _TaskStepStatus.active;
    step.remainingSeconds = step.durationSeconds;
    if (step.type != _TaskStepType.navigate) {
      robot.moving = true;
      return;
    }
    final waypoints = _robotDeployedMap?.waypoints ?? _laneWaypoints;
    final destination = step.destination;
    if (destination == null || waypoints.isEmpty) {
      _failRobotTask(robot, task, '이동 목적지가 없습니다.');
      return;
    }
    final start =
        robot.targetWaypoint ??
        waypoints.reduce(
          (a, b) =>
              (a - robot.position).distance <= (b - robot.position).distance
              ? a
              : b,
        );
    final path = _shortestRobotPath(start, destination);
    if (path == null) {
      _failRobotTask(robot, task, '${step.destinationName}까지 Lane 경로가 없습니다.');
      return;
    }
    robot
      ..targetWaypoint = null
      ..assignedRoute.clear()
      ..assignedRoute.addAll(path.skip(1))
      ..moving = true;
  }

  void _completeCurrentTaskStep(_MockRobot robot, _MockTask task) {
    task.currentStep?.status = _TaskStepStatus.completed;
    task.currentStepIndex++;
    if (task.currentStep == null) {
      _finishRobotTask(robot);
    } else {
      _startTaskStep(robot, task);
    }
  }

  void _startMockRobotTimer() {
    _mockRobotTimer ??= Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (!mounted || _mockRobots.isEmpty) return;
      final baseSpeed = math.max(
        18.0,
        math.min(
              _drawing?.pixelWidth?.toDouble() ?? 1200,
              _drawing?.pixelHeight?.toDouble() ?? 800,
            ) /
            18,
      );
      var changed = false;
      for (final robot in _mockRobots) {
        if (!robot.moving) continue;
        final task = robot.activeTaskId == null
            ? null
            : _mockTasks
                  .where((item) => item.id == robot.activeTaskId)
                  .firstOrNull;
        final activeStep = task?.currentStep;
        if (task != null &&
            activeStep != null &&
            activeStep.type != _TaskStepType.navigate) {
          activeStep.remainingSeconds = math.max(
            0,
            activeStep.remainingSeconds - .1,
          );
          if (activeStep.remainingSeconds <= 0) {
            _completeCurrentTaskStep(robot, task);
          }
          changed = true;
          continue;
        }
        var target = robot.targetWaypoint;
        if (target == null) {
          if (robot.assignedRoute.isNotEmpty) {
            target = robot.assignedRoute.removeAt(0);
          } else if (task != null) {
            _completeCurrentTaskStep(robot, task);
            changed = true;
            continue;
          } else {
            final options = _outgoingWaypoints(robot.position);
            if (options.isEmpty) continue;
            target = options.firstWhere(
              (candidate) => candidate != robot.previousWaypoint,
              orElse: () => options.first,
            );
          }
          robot.previousWaypoint = robot.position;
          robot.targetWaypoint = target;
        }
        final delta = target - robot.position;
        final step = baseSpeed * .1;
        if (delta.distance <= step) {
          final arrived = target;
          robot.position = arrived;
          robot.targetWaypoint = null;
        } else {
          robot.position += delta / delta.distance * step;
        }
        robot.battery = math.max(0, robot.battery - .003);
        changed = true;
      }
      if (changed) setState(() {});
    });
  }

  Future<void> _spawnMockRobot() async {
    final runtimeWaypoints = _robotDeployedMap?.waypoints ?? _laneWaypoints;
    final runtimeNames = _robotDeployedMap?.waypointNames ?? _waypointNames;
    if (runtimeWaypoints.isEmpty) {
      _showProcessingWarning('Mock 로봇 Spawn', '먼저 Lane과 Waypoint를 만들어 주세요.');
      return;
    }
    var kind = _RobotKind.mockMobile;
    final controller = TextEditingController(
      text: 'mock-${_mockRobots.length + 1}',
    );
    var start = runtimeWaypoints.first;
    final result = await showDialog<(String, Offset, _RobotKind)>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          icon: const Icon(Icons.smart_toy_outlined, size: 36),
          title: const Text('로봇 Spawn'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<_RobotKind>(
                  initialValue: kind,
                  decoration: const InputDecoration(
                    labelText: '로봇 유형',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    for (final value in _RobotKind.values)
                      DropdownMenuItem(value: value, child: Text(value.label)),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    setDialogState(() {
                      kind = value;
                      final prefix = switch (value) {
                        _RobotKind.mockMobile => 'mock',
                        _RobotKind.pinky => 'pinky',
                        _RobotKind.omxManipulator => 'omx',
                        _RobotKind.mockHumanoid => 'humanoid',
                      };
                      controller.text = '$prefix-${_mockRobots.length + 1}';
                    });
                  },
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: controller,
                  decoration: const InputDecoration(
                    labelText: '로봇 이름',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<Offset>(
                  initialValue: start,
                  decoration: InputDecoration(
                    labelText: kind.isMobile ? '시작 Waypoint' : '고정 설치 Waypoint',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    for (final point in runtimeWaypoints)
                      DropdownMenuItem(
                        value: point,
                        child: Text(
                          (runtimeNames[point] ?? '').trim().isEmpty
                              ? 'Waypoint ${runtimeWaypoints.indexOf(point) + 1}'
                              : runtimeNames[point]!,
                        ),
                      ),
                  ],
                  onChanged: (value) {
                    if (value != null) setDialogState(() => start = value);
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('취소'),
            ),
            FilledButton.icon(
              onPressed: () {
                final name = controller.text.trim();
                if (name.isNotEmpty) {
                  Navigator.pop(dialogContext, (name, start, kind));
                }
              },
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Spawn'),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    if (result == null || !mounted) return;
    if (_mockRobots.any((robot) => robot.id == result.$1)) {
      _showProcessingWarning(
        'Mock 로봇 Spawn',
        '같은 이름의 로봇이 이미 있습니다: ${result.$1}',
      );
      return;
    }
    const colors = [
      Color(0xFFDC2626),
      Color(0xFF7C3AED),
      Color(0xFF0891B2),
      Color(0xFFEA580C),
      Color(0xFF16A34A),
    ];
    setState(() {
      _mockRobots.add(
        _MockRobot(
          id: result.$1,
          position: result.$2,
          color: colors[_mockRobots.length % colors.length],
          kind: result.$3,
        ),
      );
    });
    _startMockRobotTimer();
  }

  void _toggleMockRobot(_MockRobot robot) {
    if (!robot.kind.isMobile) return;
    setState(() => robot.moving = !robot.moving);
  }

  void _removeMockRobot(_MockRobot robot) {
    setState(() {
      for (final task in _mockTasks.where(
        (task) =>
            task.robotId == robot.id &&
            (task.status == _MockTaskStatus.active ||
                task.status == _MockTaskStatus.queued),
      )) {
        task.status = _MockTaskStatus.failed;
      }
      _mockRobots.remove(robot);
    });
  }

  Future<void> _createMockTask() async {
    final waypoints = _robotDeployedMap?.waypoints ?? _laneWaypoints;
    final names = _robotDeployedMap?.waypointNames ?? _waypointNames;
    final taskRobots = _mockRobots
        .where((robot) => robot.kind.canCarry)
        .toList();
    if (taskRobots.isEmpty || waypoints.isEmpty) {
      final action = await showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          icon: const Icon(
            Icons.info_outline,
            color: Color(0xFF2563EB),
            size: 36,
          ),
          title: const Text('작업 준비가 필요합니다'),
          content: Text(
            waypoints.isEmpty
                ? '작업을 생성하려면 먼저 배포된 맵을 불러와야 합니다.\n'
                      '그 다음 로봇 메뉴에서 시작 Waypoint를 선택해 로봇을 Spawn하세요.'
                : '운영 맵은 준비되었습니다. 로봇 메뉴에서 Pinky 또는 Mock 주행로봇을 Spawn한 뒤 작업을 생성하세요.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('닫기'),
            ),
            if (waypoints.isEmpty)
              OutlinedButton.icon(
                onPressed: () => Navigator.pop(dialogContext, 'map'),
                icon: const Icon(Icons.folder_open_outlined, size: 18),
                label: const Text('배포 맵 불러오기'),
              ),
            FilledButton.icon(
              onPressed: () => Navigator.pop(dialogContext, 'robots'),
              icon: const Icon(Icons.smart_toy_outlined, size: 18),
              label: const Text('로봇 메뉴'),
            ),
          ],
        ),
      );
      if (action == 'map') await _loadMapForRobots();
      if (action == 'robots' && mounted) setState(() => _selectedMenu = 2);
      return;
    }
    final result = await showDialog<_TaskEditorResult>(
      context: context,
      builder: (_) => _SequentialTaskEditorDialog(
        initialName: '연속 작업 ${_mockTasks.length + 1}',
        robots: taskRobots,
        waypoints: waypoints,
        waypointNames: names,
      ),
    );
    if (result == null || !mounted) return;
    final available = taskRobots
        .where((robot) => robot.activeTaskId == null)
        .toList();
    final robot = result.robotId == '__auto__'
        ? (available..sort((a, b) => b.battery.compareTo(a.battery)))
              .firstOrNull
        : taskRobots.where((item) => item.id == result.robotId).firstOrNull;
    if (robot == null || robot.activeTaskId != null) {
      _showProcessingWarning('작업 생성', '현재 작업을 수행할 수 있는 로봇이 없습니다.');
      return;
    }
    final steps = result.steps.map((draft) {
      final destination = draft.destination;
      final destinationName = destination == null
          ? null
          : (names[destination] ?? '').trim().isEmpty
          ? 'Waypoint ${waypoints.indexOf(destination) + 1}'
          : names[destination]!;
      return _MockTaskStep(
        type: draft.type,
        destination: destination,
        destinationName: destinationName,
        durationSeconds: draft.type == _TaskStepType.armLoad
            ? 9.6
            : draft.durationSeconds,
      );
    }).toList();
    final task = _MockTask(
      id: 'TASK-${(_mockTasks.length + 1).toString().padLeft(3, '0')}',
      name: result.name,
      description: result.description,
      type: '연속 작업',
      robotId: robot.id,
      steps: steps,
    );
    setState(() {
      task.status = _MockTaskStatus.active;
      _mockTasks.insert(0, task);
      robot.activeTaskId = task.id;
      _startTaskStep(robot, task);
    });
    _startMockRobotTimer();
  }

  void _cancelMockTask(_MockTask task) {
    if (task.status != _MockTaskStatus.active &&
        task.status != _MockTaskStatus.queued) {
      return;
    }
    setState(() {
      task.status = _MockTaskStatus.cancelled;
      task.completedAt = DateTime.now();
      for (final step in task.steps.where(
        (step) =>
            step.status == _TaskStepStatus.pending ||
            step.status == _TaskStepStatus.active,
      )) {
        step.status = _TaskStepStatus.cancelled;
      }
      final robot = _mockRobots
          .where((item) => item.id == task.robotId)
          .firstOrNull;
      if (robot?.activeTaskId == task.id) {
        robot!
          ..activeTaskId = null
          ..targetWaypoint = null
          ..moving = false
          ..assignedRoute.clear();
      }
    });
  }

  Future<void> _loadMapForRobots() async {
    try {
      final mapsFuture = listDeployedMaps();
      final selected = await showDialog<DeployedMapSummary>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          icon: const Icon(Icons.map_outlined, size: 36),
          title: const Text('배포된 맵 불러오기'),
          content: SizedBox(
            width: 560,
            height: 380,
            child: FutureBuilder<List<DeployedMapSummary>>(
              future: mapsFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 14),
                        Text('프로젝트의 배포 맵을 검색하고 있습니다…'),
                      ],
                    ),
                  );
                }
                if (snapshot.hasError) {
                  return Center(
                    child: SelectableText(
                      '맵 목록을 읽지 못했습니다.\n${snapshot.error}',
                      textAlign: TextAlign.center,
                    ),
                  );
                }
                final maps = snapshot.data ?? const [];
                if (maps.isEmpty) {
                  return const Center(
                    child: Text(
                      'rmf_maps에서 building.yaml 또는 rmfproject를 찾지 못했습니다.',
                      textAlign: TextAlign.center,
                    ),
                  );
                }
                return ListView.separated(
                  itemCount: maps.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final map = maps[index];
                    final isProject = map.yamlPath.endsWith('.rmfproject');
                    return ListTile(
                      leading: Icon(
                        isProject
                            ? Icons.edit_document
                            : map.hasNavGraph
                            ? Icons.check_circle_outline
                            : Icons.warning_amber_outlined,
                        color: isProject
                            ? const Color(0xFF2563EB)
                            : map.hasNavGraph
                            ? const Color(0xFF15803D)
                            : const Color(0xFFD97706),
                      ),
                      title: Text(map.name),
                      subtitle: Text(
                        '${isProject
                            ? '저장된 RMF 프로젝트'
                            : map.hasNavGraph
                            ? 'nav graph 확인됨'
                            : 'nav graph 없음'}\n${map.yamlPath}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      onTap: () => Navigator.pop(dialogContext, map),
                    );
                  },
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('취소'),
            ),
          ],
        ),
      );
      if (selected == null) return;
      final loaded = await loadDeployedMap(selected);
      if (!mounted) return;
      setState(() {
        _robotDeployedMap = loaded;
        _mockRobots.clear();
        _mockTasks.clear();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${loaded.summary.name} 배포 맵을 불러왔습니다.')),
      );
    } catch (error) {
      _showProcessingWarning('배포 맵 불러오기', error);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          icon: const Icon(Icons.error_outline, color: Color(0xFFDC2626)),
          title: const Text('배포 맵을 불러오지 못했습니다'),
          content: SelectableText('$error'),
          actions: [
            TextButton.icon(
              onPressed: () =>
                  Clipboard.setData(ClipboardData(text: error.toString())),
              icon: const Icon(Icons.copy_outlined, size: 18),
              label: const Text('오류 복사'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('확인'),
            ),
          ],
        ),
      );
    }
  }

  UploadedDrawing? get _robotRuntimeDrawing {
    final loaded = _robotDeployedMap;
    if (loaded == null) return _drawing;
    return UploadedDrawing(
      name: loaded.imageName,
      extension: loaded.imageName.split('.').last.toLowerCase(),
      size: loaded.imageBytes.length,
      bytes: loaded.imageBytes,
      pixelWidth: loaded.imageSize.width.round(),
      pixelHeight: loaded.imageSize.height.round(),
    );
  }

  @override
  void dispose() {
    _mockRobotTimer?.cancel();
    _mapTransform.dispose();
    super.dispose();
  }

  void _toggleMeasurementMode() {
    if (_drawing?.isImage != true) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('이미지 도면에서 기준 길이를 선택할 수 있습니다.')),
      );
      return;
    }
    setState(() {
      _isMeasurementMode = !_isMeasurementMode;
      _isWallEraseMode = false;
      _isMeasurementSelected = false;
    });
  }

  void _selectMeasurement() {
    if (_measurement == null) return;
    setState(() => _isMeasurementSelected = true);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Measurement 선을 선택했습니다. 휴지통으로 제거할 수 있습니다.')),
    );
  }

  void _removeMeasurement() {
    if (_measurement == null) return;
    _recordUndo();
    setState(() {
      _measurement = null;
      _isMeasurementSelected = false;
      _isMeasurementMode = false;
      _stage = MapStage.upload;
      _isDeployed = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Measurement를 제거했습니다. 새 기준선을 선택할 수 있습니다.'),
        action: SnackBarAction(
          label: '새로 측정',
          textColor: Colors.white,
          onPressed: _toggleMeasurementMode,
        ),
      ),
    );
  }

  Future<void> _askMeasurement(Offset start, Offset end) async {
    final controller = TextEditingController(
      text: _measurement?.length.toString() ?? '',
    );
    var unit = _measurement?.unit ?? 'm';
    final result = await showDialog<(double, String)>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          icon: const Icon(
            Icons.straighten,
            color: Color(0xFF2563EB),
            size: 34,
          ),
          title: Row(
            children: [
              const Expanded(child: Text('가로나 세로의 실제 길이는?')),
              IconButton(
                onPressed: () => Navigator.pop(dialogContext),
                icon: const Icon(Icons.close),
                tooltip: '닫기',
              ),
            ],
          ),
          content: SizedBox(
            width: 390,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '선택한 기준선의 실제 길이와 단위를 입력하세요.',
                  style: TextStyle(color: Color(0xFF64748B)),
                ),
                const SizedBox(height: 20),
                const Text(
                  '길이 단위',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'm', label: Text('미터 (m)')),
                    ButtonSegment(value: 'ft', label: Text('피트 (ft)')),
                  ],
                  selected: {unit},
                  onSelectionChanged: (value) =>
                      setDialogState(() => unit = value.first),
                ),
                const SizedBox(height: 18),
                TextField(
                  controller: controller,
                  autofocus: true,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: '실제 길이',
                    hintText: unit == 'm' ? '예: 12.5' : '예: 40',
                    suffixText: unit,
                    border: const OutlineInputBorder(),
                  ),
                  onSubmitted: (_) {
                    final value = double.tryParse(controller.text.trim());
                    if (value != null && value > 0) {
                      Navigator.pop(dialogContext, (value, unit));
                    }
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('다시 선택'),
            ),
            FilledButton(
              onPressed: () {
                final value = double.tryParse(controller.text.trim());
                if (value == null || value <= 0) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('0보다 큰 실제 길이를 입력해주세요.')),
                  );
                  return;
                }
                Navigator.pop(dialogContext, (value, unit));
              },
              child: const Text('Measurement 저장'),
            ),
          ],
        ),
      ),
    );
    // showDialog completes when pop starts, while the route can still be
    // rebuilding during its reverse animation. Disposing immediately causes
    // "TextEditingController was used after being disposed" on registration.
    await Future<void>.delayed(const Duration(milliseconds: 350));
    controller.dispose();
    if (result == null || !mounted) return;
    _recordUndo();
    setState(() {
      _measurement = _MapMeasurement(
        start: start,
        end: end,
        length: result.$1,
        unit: result.$2,
      );
      _isMeasurementMode = false;
      _isMeasurementSelected = false;
      _stage = MapStage.measurement;
      _isDeployed = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('기준 길이 ${result.$1} ${result.$2}를 저장했습니다.')),
    );
  }

  void _eraseWalls(Rect imageArea) {
    final mask = _wallMask;
    if (mask == null) return;
    final remaining = mask.points
        .where((point) => !imageArea.contains(point))
        .toList();
    final removed = mask.points.length - remaining.length;
    if (removed == 0) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('선택한 영역에 제거할 벽이 없습니다.')));
      return;
    }
    _recordUndo();
    setState(() {
      _previousWallMask = mask;
      _wallMask = _WallMask(
        width: mask.width,
        height: mask.height,
        sampleSize: mask.sampleSize,
        points: remaining,
      );
      _isDeployed = false;
    });
    setState(() => _frozenAutoWalls = _wallSegments());
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('선택 영역에서 벽 후보 $removed개를 제거했습니다.')));
  }

  void _undoWallErase() {
    final previous = _previousWallMask;
    if (previous == null) return;
    _recordUndo();
    setState(() {
      _wallMask = previous;
      _previousWallMask = null;
    });
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('마지막 벽 제거 작업을 되돌렸습니다.')));
  }

  void _toggleWallConnectMode() {
    setState(() {
      _isWallConnectMode = !_isWallConnectMode;
      _pendingWallVertex = null;
      _isWallEraseMode = false;
      _isMeasurementMode = false;
      _isWallEndpointEditMode = false;
    });
  }

  void _toggleWallEndpointEditMode() {
    setState(() {
      _isWallEndpointEditMode = !_isWallEndpointEditMode;
      _isWallConnectMode = false;
      _pendingWallVertex = null;
      _isWallEraseMode = false;
      _isMeasurementMode = false;
    });
  }

  void _moveWallEndpoint(Offset original, Offset updated) {
    _recordUndo();
    setState(() {
      Offset? source;
      for (final entry in _wallVertexOverrides.entries) {
        if ((entry.value - original).distance <= .01) {
          source = entry.key;
          break;
        }
      }
      _wallVertexOverrides[source ?? original] = updated;
      _isWallEndpointEditMode = false;
      _isDeployed = false;
    });
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Wall의 마지막 정점 위치를 수정했습니다.')));
  }

  Offset _overriddenVertex(Offset point) =>
      _wallVertexOverrides[point] ?? point;

  List<(Offset, Offset)> _applyWallVertexOverrides(
    List<(Offset, Offset)> walls,
  ) => [
    for (final wall in walls)
      (_overriddenVertex(wall.$1), _overriddenVertex(wall.$2)),
  ];

  double get _floorVertexSnapTolerance {
    final sampleTolerance = (_wallMask?.sampleSize ?? 2) * 9;
    final width = _drawing?.pixelWidth?.toDouble() ?? 0;
    final height = _drawing?.pixelHeight?.toDouble() ?? 0;
    final imageTolerance = width > 0 && height > 0
        ? math.min(width, height) * .025
        : 0.0;
    return math.max(sampleTolerance, imageTolerance);
  }

  void _selectWallConnectionVertex(Offset vertex) {
    final first = _pendingWallVertex;
    if (first == null) {
      setState(() => _pendingWallVertex = vertex);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('연결할 두 번째 정점을 선택하세요.')));
      return;
    }
    if ((first - vertex).distance <= .01) return;
    final alreadyExists = _manualWalls.any(
      (wall) =>
          ((wall.$1 - first).distance <= .01 &&
              (wall.$2 - vertex).distance <= .01) ||
          ((wall.$2 - first).distance <= .01 &&
              (wall.$1 - vertex).distance <= .01),
    );
    if (!alreadyExists) _recordUndo();
    setState(() {
      if (!alreadyExists) _manualWalls.add((first, vertex));
      _pendingWallVertex = null;
      _isWallConnectMode = false;
      _isDeployed = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          alreadyExists ? '이미 연결된 Wall입니다.' : '두 정점을 Wall로 연결했습니다.',
        ),
      ),
    );
  }

  Future<void> _detectWalls() async {
    final drawing = _drawing;
    if (drawing == null || _isDetectingWalls) return;
    if (_wallsDetected) {
      _recordUndo();
      setState(() {
        _wallMask = null;
        _previousWallMask = null;
        _wallsDetected = false;
        _isWallEraseMode = false;
        _isWallConnectMode = false;
        _pendingWallVertex = null;
        _manualWalls.clear();
        _frozenAutoWalls = [];
        _isWallEndpointEditMode = false;
        _wallVertexOverrides.clear();
        _isDeployed = false;
        _stage = _floorGenerated
            ? MapStage.floor
            : _measurement != null
            ? MapStage.measurement
            : MapStage.upload;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('자동 인식된 벽을 제거했습니다.')));
      return;
    }
    if (!drawing.isImage || drawing.bytes == null) {
      _showProcessingWarning(
        '벽 자동 인식',
        'PDF와 CAD 도면은 직접 처리할 수 없습니다. PNG 또는 JPG로 변환해 주세요.',
      );
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('PDF와 CAD 도면은 이미지 변환 후 벽을 인식할 수 있습니다.')),
      );
      return;
    }

    setState(() {
      _isDetectingWalls = true;
      _isDeployed = false;
    });
    try {
      final codec = await ui.instantiateImageCodec(drawing.bytes!);
      final frame = await codec.getNextFrame();
      final image = frame.image;
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (data == null) throw StateError('이미지 픽셀을 읽을 수 없습니다.');

      final pixels = data.buffer.asUint8List();
      final width = image.width;
      final height = image.height;
      final stride = math.sqrt(width * height / 45000).ceil().clamp(2, 16);
      final points = <Offset>[];
      for (var y = 0; y < height; y += stride) {
        for (var x = 0; x < width; x += stride) {
          final index = (y * width + x) * 4;
          final red = pixels[index];
          final green = pixels[index + 1];
          final blue = pixels[index + 2];
          final alpha = pixels[index + 3];
          final luminance = red * .2126 + green * .7152 + blue * .0722;
          if (alpha > 80 && luminance < 105) {
            points.add(Offset(x.toDouble(), y.toDouble()));
          }
        }
      }
      image.dispose();
      codec.dispose();
      if (!mounted) return;
      _recordUndo();
      setState(() {
        _wallMask = _WallMask(
          width: width,
          height: height,
          sampleSize: stride.toDouble(),
          points: points,
        );
        _previousWallMask = null;
        _isWallEraseMode = false;
        _wallsDetected = true;
        _stage = MapStage.walls;
      });
      setState(() => _frozenAutoWalls = _wallSegments());
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('벽 후보 ${points.length}개 영역을 도면 위에 표시했습니다.')),
      );
    } catch (error) {
      if (!mounted) return;
      _showProcessingWarning('벽 자동 인식', error);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('벽 자동 인식에 실패했습니다: $error')));
    } finally {
      if (mounted) setState(() => _isDetectingWalls = false);
    }
  }

  Future<void> _generateFloor() async {
    final drawing = _drawing;
    if (drawing == null || _isGeneratingFloor) return;
    if (!drawing.isImage || drawing.bytes == null) {
      _showProcessingWarning(
        'Floor 생성',
        'PDF와 CAD 도면은 직접 처리할 수 없습니다. PNG 또는 JPG로 변환해 주세요.',
      );
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('PDF와 CAD 도면은 이미지 변환 후 Floor를 생성할 수 있습니다.'),
        ),
      );
      return;
    }

    setState(() {
      _isGeneratingFloor = true;
      _isDeployed = false;
    });
    try {
      final codec = await ui.instantiateImageCodec(drawing.bytes!);
      final frame = await codec.getNextFrame();
      final image = frame.image;
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (data == null) throw StateError('이미지 픽셀을 읽을 수 없습니다.');
      final pixels = data.buffer.asUint8List();
      final width = image.width;
      final height = image.height;
      final stride = math.sqrt(width * height / 32000).ceil().clamp(3, 18);
      final wallPoints = _wallMask?.points;
      final bounds = wallPoints == null || wallPoints.isEmpty
          ? Rect.fromLTWH(width * .04, height * .04, width * .92, height * .92)
          : _pointsBounds(wallPoints)
                .inflate(stride * 2)
                .intersect(
                  Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
                );
      final points = <Offset>[];
      for (var y = 0; y < height; y += stride) {
        for (var x = 0; x < width; x += stride) {
          final point = Offset(x.toDouble(), y.toDouble());
          if (!bounds.contains(point)) continue;
          final index = (y * width + x) * 4;
          final red = pixels[index];
          final green = pixels[index + 1];
          final blue = pixels[index + 2];
          final alpha = pixels[index + 3];
          final luminance = red * .2126 + green * .7152 + blue * .0722;
          if (alpha > 80 && luminance > 150) points.add(point);
        }
      }
      image.dispose();
      codec.dispose();
      if (!mounted) return;
      _recordUndo();
      setState(() {
        _floorMask = _WallMask(
          width: width,
          height: height,
          sampleSize: stride.toDouble(),
          points: points,
        );
        _floorGenerated = true;
        _stage = MapStage.floor;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('선택한 색상으로 Floor 영역을 생성했습니다.')),
      );
    } catch (error) {
      if (!mounted) return;
      _showProcessingWarning('Floor 생성', error);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Floor 생성에 실패했습니다: $error')));
    } finally {
      if (mounted) setState(() => _isGeneratingFloor = false);
    }
  }

  Rect _pointsBounds(List<Offset> points) {
    var left = points.first.dx;
    var top = points.first.dy;
    var right = left;
    var bottom = top;
    for (final point in points.skip(1)) {
      left = math.min(left, point.dx);
      top = math.min(top, point.dy);
      right = math.max(right, point.dx);
      bottom = math.max(bottom, point.dy);
    }
    return Rect.fromLTRB(left, top, right, bottom);
  }

  String get _mapName {
    final name = _drawing?.name.split('.').first.trim() ?? 'warehouse';
    return name.isEmpty ? 'warehouse' : name;
  }

  String get _yamlFileName {
    final safeName = _mapName.replaceAll(RegExp(r'[^a-zA-Z0-9가-힣_-]'), '_');
    return '$safeName.building.yaml';
  }

  String get _deploymentMapName =>
      _mapName.replaceAll(RegExp(r'[^a-zA-Z0-9가-힣_-]'), '_');

  String _yamlEscape(String value) =>
      value.replaceAll(r'\', r'\\').replaceAll('"', r'\"');

  List<double> _encodeOffset(Offset point) => [point.dx, point.dy];

  Offset _decodeOffset(dynamic value) {
    final values = value as List<dynamic>;
    return Offset((values[0] as num).toDouble(), (values[1] as num).toDouble());
  }

  Map<String, dynamic>? _encodeMask(_WallMask? mask) => mask == null
      ? null
      : {
          'width': mask.width,
          'height': mask.height,
          'sampleSize': mask.sampleSize,
          'points': mask.points.map(_encodeOffset).toList(),
        };

  _WallMask? _decodeMask(dynamic value) {
    if (value == null) return null;
    final data = value as Map<String, dynamic>;
    return _WallMask(
      width: data['width'] as int,
      height: data['height'] as int,
      sampleSize: (data['sampleSize'] as num).toDouble(),
      points: (data['points'] as List<dynamic>).map(_decodeOffset).toList(),
    );
  }

  List<List<List<double>>> _encodeLines(List<(Offset, Offset)> lines) => [
    for (final line in lines) [_encodeOffset(line.$1), _encodeOffset(line.$2)],
  ];

  List<(Offset, Offset)> _decodeLines(dynamic value) => [
    for (final line in value as List<dynamic>)
      (_decodeOffset((line as List<dynamic>)[0]), _decodeOffset(line[1])),
  ];

  Map<String, dynamic> _buildProjectData() {
    final drawing = _drawing;
    return {
      'format': 'robosapiens-map-project',
      'version': 1,
      'drawing': drawing == null
          ? null
          : {
              'name': drawing.name,
              'extension': drawing.extension,
              'size': drawing.size,
              'bytes': drawing.bytes == null
                  ? null
                  : base64Encode(drawing.bytes!),
              'pixelWidth': drawing.pixelWidth,
              'pixelHeight': drawing.pixelHeight,
            },
      'stage': _stage.index,
      'measurement': _measurement == null
          ? null
          : {
              'start': _encodeOffset(_measurement!.start),
              'end': _encodeOffset(_measurement!.end),
              'length': _measurement!.length,
              'unit': _measurement!.unit,
            },
      'wallMask': _encodeMask(_wallMask),
      'floorMask': _encodeMask(_floorMask),
      'previousWallMask': _encodeMask(_previousWallMask),
      'wallsDetected': _wallsDetected,
      'floorGenerated': _floorGenerated,
      'wallColor': _wallColor.toARGB32(),
      'floorColor': _floorColor.toARGB32(),
      'manualWalls': _encodeLines(_manualWalls),
      'wallVertexOverrides': [
        for (final entry in _wallVertexOverrides.entries)
          {'from': _encodeOffset(entry.key), 'to': _encodeOffset(entry.value)},
      ],
      'frozenAutoWalls': _encodeLines(_frozenAutoWalls),
      'recommendedLanes': _encodeLines(_recommendedLanes),
      'laneDirections': [
        for (final lane in _recommendedLanes)
          {
            'start': _encodeOffset(lane.$1),
            'end': _encodeOffset(lane.$2),
            'direction': _laneDirections[lane] ?? '양방향',
          },
      ],
      'waypoints': [
        for (final point in _laneWaypoints)
          {
            'point': _encodeOffset(point),
            'name': _waypointNames[point] ?? '',
            'category': _waypointTypes[point] ?? '일반',
          },
      ],
      'activeLaneEndpoint': _activeLaneEndpoint == null
          ? null
          : _encodeOffset(_activeLaneEndpoint!),
    };
  }

  Future<void> _saveProject() async {
    if (_drawing == null) return;
    try {
      final fileName =
          '${_mapName.replaceAll(RegExp(r'[^a-zA-Z0-9가-힣_-]'), '_')}.rmfproject';
      final bytes = Uint8List.fromList(
        utf8.encode(jsonEncode(_buildProjectData())),
      );
      final path = await FilePicker.platform.saveFile(
        dialogTitle: '맵 작업 프로젝트 저장',
        fileName: fileName,
        type: FileType.custom,
        allowedExtensions: const ['rmfproject'],
        bytes: bytes,
      );
      if (!mounted || path == null) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('$fileName 작업을 저장했습니다.')));
    } catch (error) {
      if (!mounted) return;
      _showProcessingWarning('작업 저장', error);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('작업을 저장하지 못했습니다: $error')));
    }
  }

  Future<void> _loadProject() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['rmfproject'],
        withData: true,
      );
      if (result == null || result.files.single.bytes == null) return;
      final data =
          jsonDecode(utf8.decode(result.files.single.bytes!))
              as Map<String, dynamic>;
      if (data['format'] != 'robosapiens-map-project' || data['version'] != 1) {
        throw const FormatException('지원하지 않는 프로젝트 파일입니다.');
      }
      final drawingData = data['drawing'] as Map<String, dynamic>?;
      final measurementData = data['measurement'] as Map<String, dynamic>?;
      final waypointData = data['waypoints'] as List<dynamic>;
      final loadedWaypoints = <Offset>[];
      final loadedNames = <Offset, String>{};
      final loadedTypes = <Offset, String>{};
      for (final item in waypointData) {
        final waypoint = item as Map<String, dynamic>;
        final point = _decodeOffset(waypoint['point']);
        loadedWaypoints.add(point);
        loadedNames[point] = waypoint['name'] as String? ?? '';
        final category = waypoint['category'] as String? ?? '일반';
        loadedTypes[point] = category == '드롭오프' ? '드랍오프' : category;
      }
      final loadedOverrides = <Offset, Offset>{};
      for (final item in data['wallVertexOverrides'] as List<dynamic>) {
        final entry = item as Map<String, dynamic>;
        loadedOverrides[_decodeOffset(entry['from'])] = _decodeOffset(
          entry['to'],
        );
      }
      final loadedLanes = _decodeLines(data['recommendedLanes']);
      final loadedDirections = <(Offset, Offset), String>{};
      for (final item
          in (data['laneDirections'] as List<dynamic>?) ?? const []) {
        final entry = item as Map<String, dynamic>;
        loadedDirections[(
              _decodeOffset(entry['start']),
              _decodeOffset(entry['end']),
            )] =
            entry['direction'] as String? ?? '양방향';
      }
      for (final lane in loadedLanes) {
        loadedDirections.putIfAbsent(lane, () => '양방향');
      }
      if (!mounted) return;
      _recordUndo();
      _fitMapToScreen();
      setState(() {
        _drawing = drawingData == null
            ? null
            : UploadedDrawing(
                name: drawingData['name'] as String,
                extension: drawingData['extension'] as String,
                size: drawingData['size'] as int,
                bytes: drawingData['bytes'] == null
                    ? null
                    : base64Decode(drawingData['bytes'] as String),
                pixelWidth: drawingData['pixelWidth'] as int?,
                pixelHeight: drawingData['pixelHeight'] as int?,
              );
        _stage =
            MapStage.values[(data['stage'] as int).clamp(
              0,
              MapStage.values.length - 1,
            )];
        _measurement = measurementData == null
            ? null
            : _MapMeasurement(
                start: _decodeOffset(measurementData['start']),
                end: _decodeOffset(measurementData['end']),
                length: (measurementData['length'] as num).toDouble(),
                unit: measurementData['unit'] as String,
              );
        _wallMask = _decodeMask(data['wallMask']);
        _floorMask = _decodeMask(data['floorMask']);
        _previousWallMask = _decodeMask(data['previousWallMask']);
        _wallsDetected = data['wallsDetected'] as bool;
        _floorGenerated = data['floorGenerated'] as bool;
        _wallColor = Color(data['wallColor'] as int);
        _floorColor = Color(data['floorColor'] as int);
        _manualWalls
          ..clear()
          ..addAll(_decodeLines(data['manualWalls']));
        _wallVertexOverrides
          ..clear()
          ..addAll(loadedOverrides);
        _frozenAutoWalls = _decodeLines(data['frozenAutoWalls']);
        _recommendedLanes = loadedLanes;
        _laneDirections
          ..clear()
          ..addAll(loadedDirections);
        _laneWaypoints
          ..clear()
          ..addAll(loadedWaypoints);
        _waypointNames
          ..clear()
          ..addAll(loadedNames);
        _waypointTypes
          ..clear()
          ..addAll(loadedTypes);
        _activeLaneEndpoint = data['activeLaneEndpoint'] == null
            ? null
            : _decodeOffset(data['activeLaneEndpoint']);
        _isWaypointMode = false;
        _isMeasurementMode = false;
        _isWallEraseMode = false;
        _isWallConnectMode = false;
        _isWallEndpointEditMode = false;
        _pendingWallVertex = null;
        _isDeployed = false;
        _vertexLabelRevision++;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${result.files.single.name} 작업을 불러왔습니다.')),
      );
    } catch (error) {
      if (!mounted) return;
      _showProcessingWarning('작업 불러오기', error);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('작업을 불러오지 못했습니다: $error')));
    }
  }

  List<Offset> _floorOutline() {
    // A generated Floor must not introduce a second set of vertices beside
    // an existing Wall outline. Reuse the structural Wall vertices so Floor
    // generation cannot move, duplicate, or renumber the Wall geometry.
    final wallVertices = _uniqueVertices([
      for (final wall in _visibleWallSegments()) ...[wall.$1, wall.$2],
    ]);
    if (wallVertices.length >= 3) return _convexHull(wallVertices);

    final points = _floorMask?.points;
    if (points == null || points.length < 3) return const [];
    final step = math.max(1, points.length ~/ 6000);
    return _convexHull([
      for (var i = 0; i < points.length; i += step) points[i],
    ]);
  }

  List<Offset> _convexHull(Iterable<Offset> points) {
    final sorted = _uniqueVertices(points)
      ..sort((a, b) {
        final x = a.dx.compareTo(b.dx);
        return x != 0 ? x : a.dy.compareTo(b.dy);
      });
    if (sorted.length < 3) return sorted;
    double cross(Offset origin, Offset a, Offset b) =>
        (a.dx - origin.dx) * (b.dy - origin.dy) -
        (a.dy - origin.dy) * (b.dx - origin.dx);
    final lower = <Offset>[];
    for (final point in sorted) {
      while (lower.length >= 2 &&
          cross(lower[lower.length - 2], lower.last, point) <= 0) {
        lower.removeLast();
      }
      lower.add(point);
    }
    final upper = <Offset>[];
    for (final point in sorted.reversed) {
      while (upper.length >= 2 &&
          cross(upper[upper.length - 2], upper.last, point) <= 0) {
        upper.removeLast();
      }
      upper.add(point);
    }
    lower.removeLast();
    upper.removeLast();
    return [...lower, ...upper];
  }

  List<(Offset, Offset)> _wallSegments() {
    final mask = _wallMask;
    if (mask == null || mask.points.isEmpty) return const [];
    final stride = mask.sampleSize;
    final rows = <int, Set<int>>{};
    final columns = <int, Set<int>>{};
    for (final point in mask.points) {
      final x = (point.dx / stride).round();
      final y = (point.dy / stride).round();
      rows.putIfAbsent(y, () => <int>{}).add(x);
      columns.putIfAbsent(x, () => <int>{}).add(y);
    }
    final candidates = <_AxisWall>[];
    final minimumLength = math.max(
      stride * 6,
      math.min(mask.width, mask.height) * .025,
    );
    void addRuns(Map<int, Set<int>> groups, bool horizontal) {
      final keys = groups.keys.toList()..sort();
      for (final key in keys) {
        final values = groups[key]!.toList()..sort();
        if (values.isEmpty) continue;
        var start = values.first;
        var previous = start;
        void finishRun() {
          final runLength = (previous - start) * stride;
          if (runLength < minimumLength) return;
          candidates.add(
            _AxisWall(
              horizontal: horizontal,
              axis: key * stride,
              start: start * stride,
              end: previous * stride,
            ),
          );
        }

        for (final value in values.skip(1)) {
          if (value > previous + 1) {
            finishRun();
            start = value;
          }
          previous = value;
        }
        finishRun();
      }
    }

    addRuns(rows, true);
    addRuns(columns, false);

    // Collapse the many parallel scan-lines produced by one thick wall into
    // one structural center-line.
    final merged = <_AxisWall>[];
    final thicknessTolerance = stride * 5;
    for (final candidate in candidates) {
      _AxisWall? match;
      for (final existing in merged) {
        if (existing.horizontal != candidate.horizontal ||
            (existing.axis - candidate.axis).abs() > thicknessTolerance) {
          continue;
        }
        final overlap =
            math.min(existing.end, candidate.end) -
            math.max(existing.start, candidate.start);
        if (overlap >= math.min(existing.length, candidate.length) * .55) {
          match = existing;
          break;
        }
      }
      if (match == null) {
        merged.add(candidate.copy());
      } else {
        match.absorb(candidate);
      }
    }

    // Join collinear fragments separated only by small raster gaps.
    merged.sort((a, b) {
      final direction = a.horizontal == b.horizontal
          ? 0
          : (a.horizontal ? -1 : 1);
      if (direction != 0) return direction;
      final axis = a.axis.compareTo(b.axis);
      return axis != 0 ? axis : a.start.compareTo(b.start);
    });
    final simplified = <_AxisWall>[];
    for (final segment in merged) {
      final previous = simplified.isEmpty ? null : simplified.last;
      if (previous != null &&
          previous.horizontal == segment.horizontal &&
          (previous.axis - segment.axis).abs() <= stride * 2 &&
          segment.start <= previous.end + stride * 5) {
        previous.absorb(segment);
      } else {
        simplified.add(segment.copy());
      }
    }

    simplified.removeWhere((wall) => wall.length < minimumLength);
    final floorPoints = _floorMask?.points;
    if (floorPoints != null && floorPoints.isNotEmpty) {
      for (final wall in simplified) {
        wall.chooseFloorBoundary(floorPoints, stride);
      }
    }
    simplified.sort((a, b) => b.length.compareTo(a.length));
    final result = [for (final wall in simplified.take(48)) wall.offsets];
    return _snapWallCorners(result, stride * 4);
  }

  List<(Offset, Offset)> _effectiveAutoWalls() =>
      _wallsDetected ? _frozenAutoWalls : const [];

  List<(Offset, Offset)> _snapWallCorners(
    List<(Offset, Offset)> walls,
    double tolerance,
  ) {
    final result = [...walls];
    bool horizontal((Offset, Offset) wall) =>
        (wall.$1.dy - wall.$2.dy).abs() <= .01;
    int nearestEndpoint((Offset, Offset) wall, Offset point) =>
        (wall.$1 - point).distance <= (wall.$2 - point).distance ? 0 : 1;
    double endpointDistance((Offset, Offset) wall, Offset point) =>
        math.min((wall.$1 - point).distance, (wall.$2 - point).distance);
    (Offset, Offset) replaceEndpoint(
      (Offset, Offset) wall,
      int endpoint,
      Offset point,
    ) => endpoint == 0 ? (point, wall.$2) : (wall.$1, point);

    for (var i = 0; i < result.length; i++) {
      for (var j = i + 1; j < result.length; j++) {
        if (horizontal(result[i]) == horizontal(result[j])) continue;
        final horizontalIndex = horizontal(result[i]) ? i : j;
        final verticalIndex = horizontal(result[i]) ? j : i;
        final horizontalWall = result[horizontalIndex];
        final verticalWall = result[verticalIndex];
        final intersection = Offset(verticalWall.$1.dx, horizontalWall.$1.dy);
        if (endpointDistance(horizontalWall, intersection) > tolerance ||
            endpointDistance(verticalWall, intersection) > tolerance) {
          continue;
        }
        result[horizontalIndex] = replaceEndpoint(
          horizontalWall,
          nearestEndpoint(horizontalWall, intersection),
          intersection,
        );
        result[verticalIndex] = replaceEndpoint(
          verticalWall,
          nearestEndpoint(verticalWall, intersection),
          intersection,
        );
      }
    }
    return result;
  }

  List<Offset> _uniqueVertices(Iterable<Offset> points) {
    final result = <Offset>[];
    for (final point in points) {
      if (!result.any((existing) => (existing - point).distance <= .01)) {
        result.add(point);
      }
    }
    return result;
  }

  List<Offset> _clockwiseFromLeft(Iterable<Offset> points) {
    final result = _uniqueVertices(points);
    if (result.length < 2) return result;
    final center = Offset(
      result.map((point) => point.dx).reduce((a, b) => a + b) / result.length,
      result.map((point) => point.dy).reduce((a, b) => a + b) / result.length,
    );
    final first = result.reduce((a, b) {
      if (a.dx != b.dx) return a.dx < b.dx ? a : b;
      return a.dy < b.dy ? a : b;
    });
    final startAngle = math.atan2(first.dy - center.dy, first.dx - center.dx);
    double order(Offset point) {
      final angle = math.atan2(point.dy - center.dy, point.dx - center.dx);
      return (angle - startAngle + math.pi * 2) % (math.pi * 2);
    }

    result.sort((a, b) {
      final angle = order(a).compareTo(order(b));
      if (angle != 0) return angle;
      return (a - center).distance.compareTo((b - center).distance);
    });
    return result;
  }

  List<Offset> _visibleMapVertices() {
    final measurement = _measurement;
    final vertices = <Offset>[
      if (measurement != null) measurement.start,
      if (measurement != null) measurement.end,
    ];
    final walls = _visibleWallSegments();
    final wallVertices = _clockwiseFromLeft([
      for (final wall in walls) ...[wall.$1, wall.$2],
    ]);
    vertices.addAll(wallVertices);

    final floorOnly = <Offset>[];
    for (final point in _floorOutline()) {
      final sharesWall = wallVertices.any(
        (wallVertex) =>
            (wallVertex - point).distance <= _floorVertexSnapTolerance,
      );
      if (!sharesWall) floorOnly.add(point);
    }
    vertices.addAll(_clockwiseFromLeft(floorOnly));
    vertices.addAll(
      _uniqueVertices([..._laneWaypoints]).where(
        (point) =>
            !vertices.any((existing) => (existing - point).distance <= .01),
      ),
    );
    return vertices;
  }

  List<(Offset, Offset)> _visibleWallSegments() {
    if (!_wallsDetected) return const [];
    final walls = _applyWallVertexOverrides(_effectiveAutoWalls());
    walls.addAll(_applyWallVertexOverrides(_manualWalls));
    return walls;
  }

  String _buildBuildingYaml() {
    final drawing = _drawing;
    final measurement = _measurement;
    final vertices = _visibleMapVertices();
    final measurementIndices = measurement == null ? <int>[] : <int>[0, 1];
    final floorOutline = _floorOutline();
    int vertexIndex(Offset point) {
      for (var i = 0; i < vertices.length; i++) {
        if ((vertices[i] - point).distance <= .01) return i;
      }
      vertices.add(point);
      return vertices.length - 1;
    }

    final floorSnapTolerance = _floorVertexSnapTolerance;
    int floorVertexIndex(Offset point) {
      final structuralStart = measurement == null ? 0 : 2;
      for (var i = structuralStart; i < vertices.length; i++) {
        if ((vertices[i] - point).distance <= floorSnapTolerance) return i;
      }
      return vertexIndex(point);
    }

    final floorIndices = [
      for (final point in floorOutline) floorVertexIndex(point),
    ];
    final wallIndices = <(int, int)>[];
    final wallKeys = <String>{};
    bool addWallIndex(int start, int end) {
      if (start == end) return false;
      final low = math.min(start, end);
      final high = math.max(start, end);
      final key = '$low:$high';
      if (!wallKeys.add(key)) return false;
      wallIndices.add((start, end));
      return true;
    }

    for (final wall in _visibleWallSegments()) {
      addWallIndex(vertexIndex(wall.$1), vertexIndex(wall.$2));
    }
    final laneIndices = <(int, int, String)>[
      for (final lane in _recommendedLanes)
        (
          vertexIndex(lane.$1),
          vertexIndex(lane.$2),
          _laneDirections[lane] ?? '양방향',
        ),
    ];
    final buffer = StringBuffer()
      ..writeln('coordinate_system: reference_image')
      ..writeln('graphs: {}')
      ..writeln('reference_level_name: L1')
      ..writeln('levels:')
      ..writeln('  L1:')
      ..writeln('    drawing:')
      ..writeln('      filename: "${_yamlEscape(drawing?.name ?? '')}"')
      ..writeln('    elevation: 0.0')
      ..writeln('    floors:');
    if (floorIndices.length < 3) {
      buffer.writeln('      []');
    } else {
      buffer
        ..writeln(
          '      - parameters: {ceiling_scale: [3, 1], ceiling_texture: [1, blue_linoleum], indoor: [2, 0], texture_name: [1, blue_linoleum], texture_rotation: [3, 0], texture_scale: [3, 1]}',
        )
        ..writeln('        vertices: [${floorIndices.join(', ')}]');
    }
    buffer
      ..writeln('    layers: {}')
      ..writeln('    lanes:');
    if (laneIndices.isEmpty) {
      buffer.writeln('      []');
    } else {
      for (final lane in laneIndices) {
        final reverse = lane.$3 == '역방향';
        final start = reverse ? lane.$2 : lane.$1;
        final end = reverse ? lane.$1 : lane.$2;
        final bidirectional = lane.$3 == '양방향';
        buffer.writeln(
          '      - [$start, $end, {bidirectional: [4, $bidirectional], graph_idx: [2, 0]}]',
        );
      }
    }
    buffer.writeln('    measurements:');
    if (measurement == null) {
      buffer.writeln('      []');
    } else {
      final meters = measurement.unit == 'ft'
          ? measurement.length * 0.3048
          : measurement.length;
      buffer.writeln(
        '      - [${measurementIndices[0]}, ${measurementIndices[1]}, {distance: [3, ${meters.toStringAsFixed(4)}]}]',
      );
    }
    buffer.writeln('    vertices:');
    if (vertices.isEmpty) {
      buffer.writeln('      []');
    } else {
      for (var i = 0; i < vertices.length; i++) {
        final point = vertices[i];
        final waypointType = _waypointTypes[point];
        final waypointName = _waypointNames[point];
        final name = measurement != null && i == measurementIndices.first
            ? 'measurement_start'
            : measurement != null && i == measurementIndices.last
            ? 'measurement_end'
            : waypointName ?? (waypointType != null ? 'waypoint_$i' : '');
        final trafficEditorProperty = switch (waypointType) {
          '충전' => 'is_charger',
          '대기' => 'is_parking_spot',
          '일반' => 'is_holding_point',
          _ => null,
        };
        final properties = trafficEditorProperty == null
            ? ''
            : ', {$trafficEditorProperty: [4, true]}';
        buffer.writeln(
          '      - [${point.dx.toStringAsFixed(3)}, ${point.dy.toStringAsFixed(3)}, 0.0, "${_yamlEscape(name)}"$properties]',
        );
      }
    }
    buffer.writeln('    walls:');
    if (wallIndices.isEmpty) {
      buffer.writeln('      []');
    } else {
      for (final wall in wallIndices) {
        buffer.writeln(
          '      - [${wall.$1}, ${wall.$2}, {alpha: [3, 1], texture_height: [3, 2.5], texture_name: [1, default], texture_scale: [3, 1], texture_width: [3, 1]}]',
        );
      }
    }
    buffer
      ..writeln('lifts: {}')
      ..writeln('name: "${_yamlEscape(_mapName)}"');
    return buffer.toString();
  }

  Future<void> _downloadBuildingYaml() async {
    if (_drawing == null) return;
    try {
      final yaml = _buildBuildingYaml();
      final path = await FilePicker.platform.saveFile(
        dialogTitle: 'Open-RMF 맵 저장',
        fileName: _yamlFileName,
        type: FileType.custom,
        allowedExtensions: const ['yaml'],
        bytes: Uint8List.fromList(utf8.encode(yaml)),
      );
      if (!mounted) return;
      if (path != null) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$_yamlFileName 파일을 저장했습니다.')));
      }
    } catch (error) {
      if (!mounted) return;
      _showProcessingWarning('YAML 저장', error);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('YAML 파일을 저장하지 못했습니다: $error')));
    }
  }

  Future<void> _copyBuildingYaml() async {
    if (_drawing == null) return;
    try {
      await Clipboard.setData(ClipboardData(text: _buildBuildingYaml()));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$_yamlFileName 내용을 클립보드에 복사했습니다.')),
      );
    } catch (error) {
      _showProcessingWarning('YAML 복사', error);
    }
  }

  Future<void> _deployMap() async {
    final drawing = _drawing;
    if (drawing == null) return;
    if (!drawing.isImage || drawing.bytes == null) {
      _showProcessingWarning(
        'Open-RMF 맵 배포',
        'PNG 또는 JPG 원본 이미지가 포함된 맵만 배포할 수 있습니다.',
      );
      return;
    }
    if (_showMapValidationWarnings()) return;

    final shouldDeploy = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(
          Icons.rocket_launch_outlined,
          color: Color(0xFF2563EB),
          size: 34,
        ),
        title: Row(
          children: [
            const Expanded(child: Text('맵을 배포할까요?')),
            IconButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              icon: const Icon(Icons.close),
              tooltip: '닫기',
            ),
          ],
        ),
        content: SizedBox(
          width: 390,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('다음 도면을 Open-RMF 운영 맵으로 배포합니다.'),
              const SizedBox(height: 18),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.map_outlined, color: Color(0xFF2563EB)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            drawing.name.split('.').first,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF1E293B),
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            '${drawing.extension.toUpperCase()} · ${drawing.readableSize}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFF64748B),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                '오류 검증 → YAML/이미지 저장 → nav graph/world 생성 → '
                'RMF 맵 설치 → Map Server/Fleet Adapter 재시작 → 지도 수신 확인',
                style: TextStyle(
                  fontSize: 12,
                  color: Color(0xFF64748B),
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('취소'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(dialogContext, true),
            icon: const Icon(Icons.rocket_launch, size: 17),
            label: const Text('배포하기'),
          ),
        ],
      ),
    );

    if (shouldDeploy != true || !mounted) return;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => const PopScope(
        canPop: false,
        child: AlertDialog(
          content: SizedBox(
            width: 430,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 20),
                Text(
                  'Open-RMF 맵을 배포하고 있습니다…',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                SizedBox(height: 8),
                Text('생성 및 서비스 재시작에는 시간이 걸릴 수 있습니다.'),
              ],
            ),
          ),
        ),
      ),
    );
    final result = await deployMapProject(
      mapName: _deploymentMapName,
      yaml: _buildBuildingYaml(),
      imageName: drawing.name,
      imageBytes: drawing.bytes!,
    );
    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pop();
    if (!result.success) {
      _showProcessingWarning('Open-RMF 맵 배포', result.output);
      await _showDeploymentResultDialog(success: false, output: result.output);
      return;
    }
    setState(() {
      _stage = MapStage.deploy;
      _isDeployed = true;
      _processingWarning = null;
    });
    await _showDeploymentResultDialog(success: true, output: result.output);
  }

  Future<void> _showDeploymentResultDialog({
    required bool success,
    required String output,
  }) => showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      icon: Icon(
        success ? Icons.check_circle_outline : Icons.error_outline,
        color: success ? const Color(0xFF15803D) : const Color(0xFFDC2626),
        size: 38,
      ),
      title: Text(success ? '맵 배포 완료' : '맵 배포 실패'),
      content: SizedBox(
        width: 620,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(success ? '새 지도 수신까지 확인했습니다.' : '아래 로그를 복사해 원인을 확인해 주세요.'),
            const SizedBox(height: 14),
            Container(
              constraints: const BoxConstraints(maxHeight: 360),
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              color: const Color(0xFF0F172A),
              child: SingleChildScrollView(
                child: SelectableText(
                  output,
                  style: const TextStyle(
                    color: Color(0xFFE2E8F0),
                    fontFamily: 'monospace',
                    fontSize: 12,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton.icon(
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: output));
            if (!dialogContext.mounted) return;
            ScaffoldMessenger.of(
              dialogContext,
            ).showSnackBar(const SnackBar(content: Text('배포 로그를 복사했습니다.')));
          },
          icon: const Icon(Icons.copy_outlined, size: 18),
          label: const Text('로그 복사'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('확인'),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyZ, control: true): _undo,
        const SingleActivator(LogicalKeyboardKey.escape): _finishCurrentLane,
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          body: Row(
            children: [
              _NavigationRail(
                selectedIndex: _selectedMenu,
                onSelected: (index) => setState(() => _selectedMenu = index),
              ),
              Expanded(
                child: Column(
                  children: [
                    _TopBar(
                      title: const [
                        '대시보드',
                        '맵 관리',
                        '로봇',
                        '작업',
                        '운영 분석',
                      ][_selectedMenu],
                    ),
                    Expanded(
                      child: _selectedMenu == 0
                          ? _MainDashboard(
                              drawing: _robotRuntimeDrawing,
                              mapName:
                                  _robotDeployedMap?.summary.name ?? _mapName,
                              mapReady:
                                  (_robotDeployedMap?.waypoints ??
                                          _laneWaypoints)
                                      .isNotEmpty,
                              deployed:
                                  _isDeployed || _robotDeployedMap != null,
                              lanes:
                                  _robotDeployedMap?.lanes ?? _recommendedLanes,
                              waypoints:
                                  _robotDeployedMap?.waypoints ??
                                  _laneWaypoints,
                              waypointNames:
                                  _robotDeployedMap?.waypointNames ??
                                  _waypointNames,
                              robots: _mockRobots,
                              tasks: _mockTasks,
                              warning: _processingWarning,
                              onOpenMap: () =>
                                  setState(() => _selectedMenu = 1),
                              onOpenRobots: () =>
                                  setState(() => _selectedMenu = 2),
                              onOpenTasks: () =>
                                  setState(() => _selectedMenu = 3),
                              onLoadMap: _loadMapForRobots,
                              onSpawn: _spawnMockRobot,
                              onCreateTask: _createMockTask,
                            )
                          : _selectedMenu == 1
                          ? SingleChildScrollView(
                              padding: const EdgeInsets.fromLTRB(
                                32,
                                30,
                                32,
                                40,
                              ),
                              child: Center(
                                child: ConstrainedBox(
                                  constraints: const BoxConstraints(
                                    maxWidth: 1767,
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      _PageHeading(
                                        onHelp: () => _showUsageGuide(
                                          context,
                                          _UsageGuideTopic.map,
                                        ),
                                        onUpload: _pickDrawing,
                                        exportEnabled: _drawing != null,
                                        onValidate: _showValidationDialog,
                                        onRecommend:
                                            _showLaneRecommendationsDialog,
                                        onDownload: _downloadBuildingYaml,
                                        onCopy: _copyBuildingYaml,
                                        onSaveProject: _saveProject,
                                        onLoadProject: _loadProject,
                                      ),
                                      const SizedBox(height: 24),
                                      _StageBar(activeStage: _stage),
                                      const SizedBox(height: 24),
                                      LayoutBuilder(
                                        builder: (context, constraints) {
                                          if (constraints.maxWidth < 980) {
                                            return Column(
                                              children: [
                                                _MapWorkspace(
                                                  drawing: _drawing,
                                                  transformController:
                                                      _mapTransform,
                                                  onZoomIn: () =>
                                                      _zoomMap(1.25),
                                                  onZoomOut: () => _zoomMap(.8),
                                                  onFitScreen: _fitMapToScreen,
                                                  onRenumberVertices:
                                                      _renumberVertices,
                                                  wallMask: _wallMask,
                                                  wallColor: _wallColor,
                                                  floorMask: _floorMask,
                                                  floorColor: _floorColor,
                                                  mapVertices: _showVertexLabels
                                                      ? _visibleMapVertices()
                                                      : const [],
                                                  vertexLabelRevision:
                                                      _vertexLabelRevision,
                                                  optimizedWalls:
                                                      _visibleWallSegments(),
                                                  recommendedLanes:
                                                      _recommendedLanes,
                                                  laneDirections:
                                                      _laneDirections,
                                                  laneWaypoints: _laneWaypoints,
                                                  waypointNames: _waypointNames,
                                                  waypointTypes: _waypointTypes,
                                                  activeLaneEndpoint:
                                                      _activeLaneEndpoint,
                                                  waypointMode: _isWaypointMode,
                                                  onAddWaypoint:
                                                      _addLaneWaypoint,
                                                  onEditWaypoint: _editWaypoint,
                                                  onSelectLane:
                                                      _selectLaneForDeletion,
                                                  isWallConnectMode:
                                                      _isWallConnectMode,
                                                  pendingWallVertex:
                                                      _pendingWallVertex,
                                                  onToggleWallConnect:
                                                      _toggleWallConnectMode,
                                                  onSelectWallVertex:
                                                      _selectWallConnectionVertex,
                                                  isWallEndpointEditMode:
                                                      _isWallEndpointEditMode,
                                                  onToggleWallEndpointEdit:
                                                      _toggleWallEndpointEditMode,
                                                  onMoveWallEndpoint:
                                                      _moveWallEndpoint,
                                                  measurement: _measurement,
                                                  showDrawingInfo:
                                                      _showDrawingInfo,
                                                  onCloseDrawingInfo: () =>
                                                      setState(
                                                        () => _showDrawingInfo =
                                                            false,
                                                      ),
                                                  isMeasurementSelected:
                                                      _isMeasurementSelected,
                                                  onSelectMeasurement:
                                                      _selectMeasurement,
                                                  onRemoveMeasurement:
                                                      _removeMeasurement,
                                                  isMeasurementMode:
                                                      _isMeasurementMode,
                                                  onMeasurementSelected:
                                                      _askMeasurement,
                                                  onCloseMeasurementMode: () =>
                                                      setState(
                                                        () =>
                                                            _isMeasurementMode =
                                                                false,
                                                      ),
                                                  isWallEraseMode:
                                                      _isWallEraseMode,
                                                  canUndoWallErase:
                                                      _previousWallMask != null,
                                                  onToggleWallErase: () =>
                                                      setState(
                                                        () => _isWallEraseMode =
                                                            !_isWallEraseMode,
                                                      ),
                                                  onEraseWalls: _eraseWalls,
                                                  onUndoWallErase:
                                                      _undoWallErase,
                                                  isPicking: _isPicking,
                                                  onPick: _pickDrawing,
                                                  onRemove: _removeDrawing,
                                                ),
                                                const SizedBox(height: 20),
                                                _SetupPanel(
                                                  drawing: _drawing,
                                                  stage: _stage,
                                                  measurement: _measurement,
                                                  isMeasurementMode:
                                                      _isMeasurementMode,
                                                  onToggleMeasurement:
                                                      _toggleMeasurementMode,
                                                  wallColor: _wallColor,
                                                  floorColor: _floorColor,
                                                  wallsDetected: _wallsDetected,
                                                  floorGenerated:
                                                      _floorGenerated,
                                                  isDetectingWalls:
                                                      _isDetectingWalls,
                                                  isGeneratingFloor:
                                                      _isGeneratingFloor,
                                                  onDetectWalls: _detectWalls,
                                                  onGenerateFloor:
                                                      _generateFloor,
                                                  lanesGenerated:
                                                      _laneWaypoints.isNotEmpty,
                                                  waypointMode: _isWaypointMode,
                                                  onToggleWaypoint:
                                                      _toggleWaypointMode,
                                                  onWallColorChanged: (color) =>
                                                      setState(
                                                        () =>
                                                            _wallColor = color,
                                                      ),
                                                  onFloorColorChanged:
                                                      (color) => setState(
                                                        () =>
                                                            _floorColor = color,
                                                      ),
                                                  isDeployed: _isDeployed,
                                                  onDeploy: _deployMap,
                                                  onStageChanged: (value) =>
                                                      setState(
                                                        () => _stage = value,
                                                      ),
                                                ),
                                              ],
                                            );
                                          }
                                          return Row(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Expanded(
                                                child: _MapWorkspace(
                                                  drawing: _drawing,
                                                  transformController:
                                                      _mapTransform,
                                                  onZoomIn: () =>
                                                      _zoomMap(1.25),
                                                  onZoomOut: () => _zoomMap(.8),
                                                  onFitScreen: _fitMapToScreen,
                                                  onRenumberVertices:
                                                      _renumberVertices,
                                                  wallMask: _wallMask,
                                                  wallColor: _wallColor,
                                                  floorMask: _floorMask,
                                                  floorColor: _floorColor,
                                                  mapVertices: _showVertexLabels
                                                      ? _visibleMapVertices()
                                                      : const [],
                                                  vertexLabelRevision:
                                                      _vertexLabelRevision,
                                                  optimizedWalls:
                                                      _visibleWallSegments(),
                                                  recommendedLanes:
                                                      _recommendedLanes,
                                                  laneDirections:
                                                      _laneDirections,
                                                  laneWaypoints: _laneWaypoints,
                                                  waypointNames: _waypointNames,
                                                  waypointTypes: _waypointTypes,
                                                  activeLaneEndpoint:
                                                      _activeLaneEndpoint,
                                                  waypointMode: _isWaypointMode,
                                                  onAddWaypoint:
                                                      _addLaneWaypoint,
                                                  onEditWaypoint: _editWaypoint,
                                                  onSelectLane:
                                                      _selectLaneForDeletion,
                                                  isWallConnectMode:
                                                      _isWallConnectMode,
                                                  pendingWallVertex:
                                                      _pendingWallVertex,
                                                  onToggleWallConnect:
                                                      _toggleWallConnectMode,
                                                  onSelectWallVertex:
                                                      _selectWallConnectionVertex,
                                                  isWallEndpointEditMode:
                                                      _isWallEndpointEditMode,
                                                  onToggleWallEndpointEdit:
                                                      _toggleWallEndpointEditMode,
                                                  onMoveWallEndpoint:
                                                      _moveWallEndpoint,
                                                  measurement: _measurement,
                                                  showDrawingInfo:
                                                      _showDrawingInfo,
                                                  onCloseDrawingInfo: () =>
                                                      setState(
                                                        () => _showDrawingInfo =
                                                            false,
                                                      ),
                                                  isMeasurementSelected:
                                                      _isMeasurementSelected,
                                                  onSelectMeasurement:
                                                      _selectMeasurement,
                                                  onRemoveMeasurement:
                                                      _removeMeasurement,
                                                  isMeasurementMode:
                                                      _isMeasurementMode,
                                                  onMeasurementSelected:
                                                      _askMeasurement,
                                                  onCloseMeasurementMode: () =>
                                                      setState(
                                                        () =>
                                                            _isMeasurementMode =
                                                                false,
                                                      ),
                                                  isWallEraseMode:
                                                      _isWallEraseMode,
                                                  canUndoWallErase:
                                                      _previousWallMask != null,
                                                  onToggleWallErase: () =>
                                                      setState(
                                                        () => _isWallEraseMode =
                                                            !_isWallEraseMode,
                                                      ),
                                                  onEraseWalls: _eraseWalls,
                                                  onUndoWallErase:
                                                      _undoWallErase,
                                                  isPicking: _isPicking,
                                                  onPick: _pickDrawing,
                                                  onRemove: _removeDrawing,
                                                ),
                                              ),
                                              const SizedBox(width: 20),
                                              SizedBox(
                                                width: 330,
                                                child: _SetupPanel(
                                                  drawing: _drawing,
                                                  stage: _stage,
                                                  measurement: _measurement,
                                                  isMeasurementMode:
                                                      _isMeasurementMode,
                                                  onToggleMeasurement:
                                                      _toggleMeasurementMode,
                                                  wallColor: _wallColor,
                                                  floorColor: _floorColor,
                                                  wallsDetected: _wallsDetected,
                                                  floorGenerated:
                                                      _floorGenerated,
                                                  isDetectingWalls:
                                                      _isDetectingWalls,
                                                  isGeneratingFloor:
                                                      _isGeneratingFloor,
                                                  onDetectWalls: _detectWalls,
                                                  onGenerateFloor:
                                                      _generateFloor,
                                                  lanesGenerated:
                                                      _laneWaypoints.isNotEmpty,
                                                  waypointMode: _isWaypointMode,
                                                  onToggleWaypoint:
                                                      _toggleWaypointMode,
                                                  onWallColorChanged: (color) =>
                                                      setState(
                                                        () =>
                                                            _wallColor = color,
                                                      ),
                                                  onFloorColorChanged:
                                                      (color) => setState(
                                                        () =>
                                                            _floorColor = color,
                                                      ),
                                                  isDeployed: _isDeployed,
                                                  onDeploy: _deployMap,
                                                  onStageChanged: (value) =>
                                                      setState(
                                                        () => _stage = value,
                                                      ),
                                                ),
                                              ),
                                            ],
                                          );
                                        },
                                      ),
                                      if (_processingWarning != null) ...[
                                        const SizedBox(height: 20),
                                        _ProcessingWarningPanel(
                                          message: _processingWarning!,
                                          onDismiss: _clearProcessingWarning,
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ),
                            )
                          : _selectedMenu == 2
                          ? _RobotManagementPage(
                              drawing: _robotRuntimeDrawing,
                              activeMapName:
                                  _robotDeployedMap?.summary.name ?? _mapName,
                              lanes:
                                  _robotDeployedMap?.lanes ?? _recommendedLanes,
                              waypoints:
                                  _robotDeployedMap?.waypoints ??
                                  _laneWaypoints,
                              waypointNames:
                                  _robotDeployedMap?.waypointNames ??
                                  _waypointNames,
                              robots: _mockRobots,
                              onLoadMap: _loadMapForRobots,
                              onSpawn: _spawnMockRobot,
                              onToggle: _toggleMockRobot,
                              onRemove: _removeMockRobot,
                            )
                          : _selectedMenu == 3
                          ? _TaskManagementPage(
                              tasks: _mockTasks,
                              robots: _mockRobots,
                              activeMapName:
                                  _robotDeployedMap?.summary.name ?? _mapName,
                              mapReady:
                                  (_robotDeployedMap?.waypoints ??
                                          _laneWaypoints)
                                      .isNotEmpty,
                              onLoadMap: _loadMapForRobots,
                              onOpenRobots: () =>
                                  setState(() => _selectedMenu = 2),
                              onCreate: _createMockTask,
                              onCancel: _cancelMockTask,
                            )
                          : _ComingSoonPage(
                              title: const [
                                '대시보드',
                                '맵 관리',
                                '로봇',
                                '작업',
                                '운영 분석',
                              ][_selectedMenu],
                            ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SequentialTaskEditorDialog extends StatefulWidget {
  const _SequentialTaskEditorDialog({
    required this.initialName,
    required this.robots,
    required this.waypoints,
    required this.waypointNames,
  });

  final String initialName;
  final List<_MockRobot> robots;
  final List<Offset> waypoints;
  final Map<Offset, String> waypointNames;

  @override
  State<_SequentialTaskEditorDialog> createState() =>
      _SequentialTaskEditorDialogState();
}

class _SequentialTaskEditorDialogState
    extends State<_SequentialTaskEditorDialog> {
  late final TextEditingController _name;
  final _description = TextEditingController();
  String _robotId = '__auto__';
  late final List<_TaskStepDraft> _steps;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.initialName);
    _steps = [
      _TaskStepDraft(
        _TaskStepType.navigate,
        destination: widget.waypoints.first,
      ),
      _TaskStepDraft(_TaskStepType.armLoad),
      _TaskStepDraft(
        _TaskStepType.navigate,
        destination: widget.waypoints.first,
      ),
    ];
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  String _waypointLabel(Offset point) {
    final name = widget.waypointNames[point]?.trim() ?? '';
    return name.isEmpty
        ? 'Waypoint ${widget.waypoints.indexOf(point) + 1}'
        : name;
  }

  bool get _valid =>
      _name.text.trim().isNotEmpty &&
      _steps.isNotEmpty &&
      _steps.every(
        (step) =>
            step.type != _TaskStepType.navigate || step.destination != null,
      );

  @override
  Widget build(BuildContext context) => AlertDialog(
    icon: const Icon(Icons.account_tree_outlined, size: 36),
    title: const Text('연속 작업 편집기'),
    content: SizedBox(
      width: 650,
      height: 560,
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _name,
                  decoration: const InputDecoration(
                    labelText: '작업 이름 *',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: _robotId,
                  decoration: const InputDecoration(
                    labelText: 'Pinky 배정',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    const DropdownMenuItem(
                      value: '__auto__',
                      child: Text('자동 배정'),
                    ),
                    for (final robot in widget.robots)
                      DropdownMenuItem(value: robot.id, child: Text(robot.id)),
                  ],
                  onChanged: (value) => setState(() => _robotId = value!),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _description,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: '상세 지시',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Expanded(
                child: Text(
                  '실행 단계',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              OutlinedButton.icon(
                onPressed: () => setState(
                  () => _steps.add(
                    _TaskStepDraft(
                      _TaskStepType.navigate,
                      destination: widget.waypoints.first,
                    ),
                  ),
                ),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('단계 추가'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ReorderableListView.builder(
              itemCount: _steps.length,
              onReorderItem: (oldIndex, newIndex) => setState(() {
                _steps.insert(newIndex, _steps.removeAt(oldIndex));
              }),
              itemBuilder: (context, index) {
                final step = _steps[index];
                return Card(
                  key: ObjectKey(step),
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Row(
                      children: [
                        CircleAvatar(radius: 15, child: Text('${index + 1}')),
                        const SizedBox(width: 10),
                        SizedBox(
                          width: 165,
                          child: DropdownButtonFormField<_TaskStepType>(
                            initialValue: step.type,
                            decoration: const InputDecoration(
                              labelText: '동작',
                              isDense: true,
                              border: OutlineInputBorder(),
                            ),
                            items: const [
                              DropdownMenuItem(
                                value: _TaskStepType.navigate,
                                child: Text('Pinky 이동'),
                              ),
                              DropdownMenuItem(
                                value: _TaskStepType.armLoad,
                                child: Text('OMX-AI 픽업'),
                              ),
                              DropdownMenuItem(
                                value: _TaskStepType.wait,
                                child: Text('대기'),
                              ),
                            ],
                            onChanged: (value) => setState(() {
                              step.type = value!;
                              if (value == _TaskStepType.navigate) {
                                step.destination ??= widget.waypoints.first;
                              }
                            }),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: step.type == _TaskStepType.navigate
                              ? DropdownButtonFormField<Offset>(
                                  initialValue: step.destination,
                                  decoration: const InputDecoration(
                                    labelText: '목적지 Waypoint',
                                    isDense: true,
                                    border: OutlineInputBorder(),
                                  ),
                                  items: [
                                    for (final point in widget.waypoints)
                                      DropdownMenuItem(
                                        value: point,
                                        child: Text(_waypointLabel(point)),
                                      ),
                                  ],
                                  onChanged: (value) =>
                                      setState(() => step.destination = value),
                                )
                              : step.type == _TaskStepType.wait
                              ? DropdownButtonFormField<double>(
                                  initialValue: step.durationSeconds,
                                  decoration: const InputDecoration(
                                    labelText: '대기 시간',
                                    isDense: true,
                                    border: OutlineInputBorder(),
                                  ),
                                  items: const [3, 5, 10, 30, 60]
                                      .map(
                                        (seconds) => DropdownMenuItem(
                                          value: seconds.toDouble(),
                                          child: Text('$seconds초'),
                                        ),
                                      )
                                      .toList(),
                                  onChanged: (value) => setState(
                                    () => step.durationSeconds = value!,
                                  ),
                                )
                              : const Text(
                                  '현재 위치에서 화물을 집어 Pinky 데크에 적재',
                                  style: TextStyle(color: Color(0xFF475569)),
                                ),
                        ),
                        IconButton(
                          tooltip: '단계 삭제',
                          onPressed: () => setState(() => _steps.remove(step)),
                          icon: const Icon(Icons.delete_outline),
                        ),
                        const Icon(Icons.drag_handle),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('취소'),
      ),
      FilledButton.icon(
        onPressed: !_valid
            ? null
            : () => Navigator.pop(
                context,
                _TaskEditorResult(
                  name: _name.text.trim(),
                  description: _description.text.trim(),
                  robotId: _robotId,
                  steps: _steps,
                ),
              ),
        icon: const Icon(Icons.play_arrow, size: 18),
        label: const Text('연속 작업 시작'),
      ),
    ],
  );
}

class _TaskManagementPage extends StatelessWidget {
  const _TaskManagementPage({
    required this.tasks,
    required this.robots,
    required this.activeMapName,
    required this.mapReady,
    required this.onLoadMap,
    required this.onOpenRobots,
    required this.onCreate,
    required this.onCancel,
  });

  final List<_MockTask> tasks;
  final List<_MockRobot> robots;
  final String activeMapName;
  final bool mapReady;
  final VoidCallback onLoadMap;
  final VoidCallback onOpenRobots;
  final VoidCallback onCreate;
  final ValueChanged<_MockTask> onCancel;

  String _statusLabel(_MockTaskStatus status) => switch (status) {
    _MockTaskStatus.queued => '대기',
    _MockTaskStatus.active => '진행 중',
    _MockTaskStatus.completed => '완료',
    _MockTaskStatus.cancelled => '취소',
    _MockTaskStatus.failed => '실패',
  };

  Color _statusColor(_MockTaskStatus status) => switch (status) {
    _MockTaskStatus.queued => const Color(0xFFD97706),
    _MockTaskStatus.active => const Color(0xFF2563EB),
    _MockTaskStatus.completed => const Color(0xFF15803D),
    _MockTaskStatus.cancelled => const Color(0xFF64748B),
    _MockTaskStatus.failed => const Color(0xFFDC2626),
  };

  String _time(DateTime value) =>
      '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}:${value.second.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final active = tasks
        .where(
          (task) =>
              task.status == _MockTaskStatus.active ||
              task.status == _MockTaskStatus.queued,
        )
        .length;
    final completed = tasks
        .where((task) => task.status == _MockTaskStatus.completed)
        .length;
    return Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '작업 관리',
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 6),
                    const Text('Pinky 이동과 OMX-AI 픽업을 순서대로 편집하고 실행 상태를 확인합니다.'),
                  ],
                ),
              ),
              OutlinedButton.icon(
                onPressed: () =>
                    _showUsageGuide(context, _UsageGuideTopic.task),
                icon: const Icon(Icons.help_outline),
                label: const Text('사용법'),
              ),
              const SizedBox(width: 10),
              OutlinedButton.icon(
                onPressed: onLoadMap,
                icon: const Icon(Icons.folder_open_outlined),
                label: const Text('배포 맵 불러오기'),
              ),
              const SizedBox(width: 10),
              FilledButton.icon(
                onPressed: onCreate,
                icon: const Icon(Icons.add_task),
                label: const Text('새 작업'),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(13),
            decoration: BoxDecoration(
              color: mapReady && robots.any((robot) => robot.kind.canCarry)
                  ? const Color(0xFFF0FDF4)
                  : const Color(0xFFFFFBEB),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: mapReady && robots.any((robot) => robot.kind.canCarry)
                    ? const Color(0xFF86EFAC)
                    : const Color(0xFFFCD34D),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  mapReady && robots.any((robot) => robot.kind.canCarry)
                      ? Icons.check_circle_outline
                      : Icons.info_outline,
                  color: mapReady && robots.any((robot) => robot.kind.canCarry)
                      ? const Color(0xFF15803D)
                      : const Color(0xFFD97706),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    !mapReady
                        ? '1단계: 배포 맵을 불러오세요.'
                        : !robots.any((robot) => robot.kind.canCarry)
                        ? '현재 맵: $activeMapName · 2단계: Pinky 또는 Mock 주행로봇을 Spawn하세요.'
                        : '작업 준비 완료 · 맵: $activeMapName · 로봇 ${robots.length}대',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                if (!mapReady)
                  TextButton(onPressed: onLoadMap, child: const Text('맵 불러오기'))
                else if (!robots.any((robot) => robot.kind.canCarry))
                  TextButton(
                    onPressed: onOpenRobots,
                    child: const Text('로봇 메뉴로 이동'),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              _TaskSummaryCard(
                label: '전체 작업',
                value: tasks.length,
                color: const Color(0xFF334155),
              ),
              const SizedBox(width: 12),
              _TaskSummaryCard(
                label: '진행 중',
                value: active,
                color: const Color(0xFF2563EB),
              ),
              const SizedBox(width: 12),
              _TaskSummaryCard(
                label: '완료',
                value: completed,
                color: const Color(0xFF15803D),
              ),
              const SizedBox(width: 12),
              _TaskSummaryCard(
                label: '가용 로봇',
                value: robots
                    .where(
                      (robot) =>
                          robot.kind.canCarry && robot.activeTaskId == null,
                    )
                    .length,
                color: const Color(0xFF7C3AED),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: tasks.isEmpty
                  ? const Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.assignment_outlined,
                            size: 52,
                            color: Color(0xFF94A3B8),
                          ),
                          SizedBox(height: 12),
                          Text('생성된 작업이 없습니다.'),
                        ],
                      ),
                    )
                  : ListView.separated(
                      itemCount: tasks.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final task = tasks[index];
                        final color = _statusColor(task.status);
                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 9,
                          ),
                          leading: Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: color.withValues(alpha: .12),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(Icons.route_outlined, color: color),
                          ),
                          title: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  task.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                task.id,
                                style: const TextStyle(
                                  color: Color(0xFF64748B),
                                  fontSize: 12,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: color.withValues(alpha: .12),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  _statusLabel(task.status),
                                  style: TextStyle(
                                    color: color,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          subtitle: Padding(
                            padding: const EdgeInsets.only(top: 5),
                            child: Text(
                              '${task.type} · ${task.robotId} · ${task.currentStepIndex}/${task.steps.length}단계 완료 · 생성 ${_time(task.createdAt)}'
                              '\n${task.steps.map((step) => step.label).join(' → ')}'
                              '${task.description.isEmpty ? '' : '\n${task.description}'}',
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          trailing:
                              task.status == _MockTaskStatus.active ||
                                  task.status == _MockTaskStatus.queued
                              ? OutlinedButton.icon(
                                  onPressed: () => onCancel(task),
                                  icon: const Icon(
                                    Icons.cancel_outlined,
                                    size: 17,
                                  ),
                                  label: const Text('취소'),
                                )
                              : task.completedAt == null
                              ? null
                              : Text(
                                  _time(task.completedAt!),
                                  style: const TextStyle(
                                    color: Color(0xFF64748B),
                                  ),
                                ),
                        );
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TaskSummaryCard extends StatelessWidget {
  const _TaskSummaryCard({
    required this.label,
    required this.value,
    required this.color,
  });
  final String label;
  final int value;
  final Color color;

  @override
  Widget build(BuildContext context) => Expanded(
    child: Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          Container(
            width: 5,
            height: 34,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$value',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: color,
                ),
              ),
              Text(
                label,
                style: const TextStyle(color: Color(0xFF64748B), fontSize: 12),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

class _MainDashboard extends StatelessWidget {
  const _MainDashboard({
    required this.drawing,
    required this.mapName,
    required this.mapReady,
    required this.deployed,
    required this.lanes,
    required this.waypoints,
    required this.waypointNames,
    required this.robots,
    required this.tasks,
    required this.warning,
    required this.onOpenMap,
    required this.onOpenRobots,
    required this.onOpenTasks,
    required this.onLoadMap,
    required this.onSpawn,
    required this.onCreateTask,
  });

  final UploadedDrawing? drawing;
  final String mapName;
  final bool mapReady;
  final bool deployed;
  final List<(Offset, Offset)> lanes;
  final List<Offset> waypoints;
  final Map<Offset, String> waypointNames;
  final List<_MockRobot> robots;
  final List<_MockTask> tasks;
  final String? warning;
  final VoidCallback onOpenMap;
  final VoidCallback onOpenRobots;
  final VoidCallback onOpenTasks;
  final VoidCallback onLoadMap;
  final VoidCallback onSpawn;
  final VoidCallback onCreateTask;

  String _taskStatus(_MockTaskStatus status) => switch (status) {
    _MockTaskStatus.queued => '대기',
    _MockTaskStatus.active => '진행 중',
    _MockTaskStatus.completed => '완료',
    _MockTaskStatus.cancelled => '취소',
    _MockTaskStatus.failed => '실패',
  };

  String _clock(DateTime value) =>
      '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final moving = robots.where((robot) => robot.moving).length;
    final robotErrors = robots.where((robot) => robot.battery <= 10).length;
    final activeTasks = tasks
        .where(
          (task) =>
              task.status == _MockTaskStatus.active ||
              task.status == _MockTaskStatus.queued,
        )
        .length;
    final failedTasks = tasks
        .where((task) => task.status == _MockTaskStatus.failed)
        .length;
    final completedTasks = tasks
        .where((task) => task.status == _MockTaskStatus.completed)
        .length;
    final hasIssue = warning != null || failedTasks > 0 || robotErrors > 0;
    final arms = robots
        .where((robot) => robot.kind == _RobotKind.omxManipulator)
        .toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '운영 대시보드',
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 6),
                    const Text('맵, 로봇과 작업 상태를 한 화면에서 확인합니다.'),
                  ],
                ),
              ),
              OutlinedButton.icon(
                onPressed: onLoadMap,
                icon: const Icon(Icons.folder_open_outlined),
                label: const Text('운영 맵 불러오기'),
              ),
              const SizedBox(width: 10),
              OutlinedButton.icon(
                onPressed: onSpawn,
                icon: const Icon(Icons.add_circle_outline),
                label: const Text('로봇 Spawn'),
              ),
              const SizedBox(width: 10),
              FilledButton.icon(
                onPressed: onCreateTask,
                icon: const Icon(Icons.add_task),
                label: const Text('새 작업'),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: hasIssue
                  ? const Color(0xFFFFFBEB)
                  : const Color(0xFFF0FDF4),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: hasIssue
                    ? const Color(0xFFFCD34D)
                    : const Color(0xFF86EFAC),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  hasIssue ? Icons.warning_amber_rounded : Icons.check_circle,
                  color: hasIssue
                      ? const Color(0xFFD97706)
                      : const Color(0xFF15803D),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    hasIssue
                        ? '운영 주의 · Warning 또는 실패 작업을 확인하세요.'
                        : mapReady
                        ? '운영 준비 정상 · 현재 맵 $mapName'
                        : '운영 준비 필요 · 먼저 맵을 작성하거나 배포 맵을 불러오세요.',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                _DashboardStatusChip(
                  label: deployed ? '맵 배포됨' : '맵 미배포',
                  ok: deployed,
                ),
                const SizedBox(width: 8),
                _DashboardStatusChip(
                  label: mapReady ? 'Nav graph 준비' : 'Nav graph 없음',
                  ok: mapReady,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              final columns = width >= 1100
                  ? 4
                  : width >= 620
                  ? 2
                  : 1;
              final cardWidth = (width - (columns - 1) * 12) / columns;
              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  SizedBox(
                    width: cardWidth,
                    child: _DashboardMetricCard(
                      icon: Icons.smart_toy_outlined,
                      label: '등록 로봇',
                      value: '${robots.length}대',
                      detail: '이동 $moving · 정지 ${robots.length - moving}',
                      color: const Color(0xFF2563EB),
                      onTap: onOpenRobots,
                    ),
                  ),
                  SizedBox(
                    width: cardWidth,
                    child: _DashboardMetricCard(
                      icon: Icons.pending_actions_outlined,
                      label: '진행 작업',
                      value: '$activeTasks건',
                      detail: '완료 $completedTasks건',
                      color: const Color(0xFF7C3AED),
                      onTap: onOpenTasks,
                    ),
                  ),
                  SizedBox(
                    width: cardWidth,
                    child: _DashboardMetricCard(
                      icon: Icons.error_outline,
                      label: '확인 필요',
                      value: '${failedTasks + robotErrors}건',
                      detail: '실패 작업 $failedTasks · 저전압 $robotErrors',
                      color: const Color(0xFFDC2626),
                      onTap: onOpenTasks,
                    ),
                  ),
                  SizedBox(
                    width: cardWidth,
                    child: _DashboardMetricCard(
                      icon: Icons.precision_manufacturing_outlined,
                      label: 'OMX 스테이션',
                      value: '${arms.length}대',
                      detail: arms.isEmpty ? '등록 필요' : '고정 장비 등록됨',
                      color: const Color(0xFF0891B2),
                      onTap: onOpenRobots,
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 18),
          LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 1050;
              final map = _DashboardPanel(
                title: '실시간 운영 맵',
                icon: Icons.map_outlined,
                trailing: TextButton(
                  onPressed: onOpenRobots,
                  child: const Text('로봇 화면 열기'),
                ),
                child: SizedBox(
                  height: 430,
                  child: _RobotMapCard(
                    drawing: drawing,
                    lanes: lanes,
                    waypoints: waypoints,
                    waypointNames: waypointNames,
                    robots: robots,
                  ),
                ),
              );
              final side = Column(
                children: [
                  _DashboardPanel(
                    title: 'Warning',
                    icon: Icons.warning_amber_outlined,
                    child: warning == null && failedTasks == 0
                        ? const _DashboardEmpty(
                            icon: Icons.check_circle_outline,
                            text: '현재 확인할 Warning이 없습니다.',
                          )
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (warning != null)
                                SelectableText(
                                  warning!,
                                  style: const TextStyle(
                                    color: Color(0xFFB45309),
                                    height: 1.45,
                                  ),
                                ),
                              if (failedTasks > 0)
                                ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  leading: const Icon(
                                    Icons.error_outline,
                                    color: Color(0xFFDC2626),
                                  ),
                                  title: Text('실패 작업 $failedTasks건'),
                                  trailing: TextButton(
                                    onPressed: onOpenTasks,
                                    child: const Text('확인'),
                                  ),
                                ),
                            ],
                          ),
                  ),
                  const SizedBox(height: 14),
                  _DashboardPanel(
                    title: 'OMX 스테이션',
                    icon: Icons.precision_manufacturing_outlined,
                    child: arms.isEmpty
                        ? const _DashboardEmpty(
                            icon: Icons.add_location_alt_outlined,
                            text: 'OMX Manipulator를 설치 Waypoint에 Spawn하세요.',
                          )
                        : Column(
                            children: [
                              for (final arm in arms)
                                ListTile(
                                  dense: true,
                                  contentPadding: EdgeInsets.zero,
                                  leading: CircleAvatar(
                                    backgroundColor: arm.color,
                                    child: const Icon(
                                      Icons.precision_manufacturing,
                                      color: Colors.white,
                                      size: 18,
                                    ),
                                  ),
                                  title: Text(arm.id),
                                  subtitle: const Text('고정 설치 · 대기'),
                                ),
                            ],
                          ),
                  ),
                ],
              );
              if (compact) {
                return Column(
                  children: [map, const SizedBox(height: 14), side],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 2, child: map),
                  const SizedBox(width: 16),
                  Expanded(child: side),
                ],
              );
            },
          ),
          const SizedBox(height: 18),
          _DashboardPanel(
            title: '최근 작업 활동',
            icon: Icons.history,
            trailing: TextButton(
              onPressed: onOpenTasks,
              child: const Text('전체 작업 보기'),
            ),
            child: tasks.isEmpty
                ? const _DashboardEmpty(
                    icon: Icons.inbox_outlined,
                    text: '아직 생성된 작업이 없습니다.',
                  )
                : Column(
                    children: [
                      for (final task in tasks.take(5))
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(
                            task.status == _MockTaskStatus.failed
                                ? Icons.error_outline
                                : task.status == _MockTaskStatus.completed
                                ? Icons.check_circle_outline
                                : Icons.route_outlined,
                          ),
                          title: Text('${task.id} · ${task.name}'),
                          subtitle: Text(
                            '${task.robotId} · ${task.currentStepIndex}/${task.steps.length}단계',
                          ),
                          trailing: Text(
                            '${_taskStatus(task.status)} · ${_clock(task.createdAt)}',
                          ),
                        ),
                    ],
                  ),
          ),
          const SizedBox(height: 18),
          _DashboardPanel(
            title: '빠른 실행',
            icon: Icons.bolt_outlined,
            child: Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                OutlinedButton.icon(
                  onPressed: onOpenMap,
                  icon: const Icon(Icons.map_outlined),
                  label: const Text('맵 관리'),
                ),
                OutlinedButton.icon(
                  onPressed: onOpenRobots,
                  icon: const Icon(Icons.smart_toy_outlined),
                  label: const Text('로봇 관리'),
                ),
                OutlinedButton.icon(
                  onPressed: onOpenTasks,
                  icon: const Icon(Icons.assignment_outlined),
                  label: const Text('작업 관리'),
                ),
                OutlinedButton.icon(
                  onPressed: onLoadMap,
                  icon: const Icon(Icons.folder_open_outlined),
                  label: const Text('배포 맵 불러오기'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DashboardStatusChip extends StatelessWidget {
  const _DashboardStatusChip({required this.label, required this.ok});
  final String label;
  final bool ok;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: ok ? const Color(0xFFDCFCE7) : const Color(0xFFFFEDD5),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      label,
      style: TextStyle(
        color: ok ? const Color(0xFF15803D) : const Color(0xFFC2410C),
        fontSize: 12,
        fontWeight: FontWeight.w800,
      ),
    ),
  );
}

class _DashboardMetricCard extends StatelessWidget {
  const _DashboardMetricCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.detail,
    required this.color,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final String value;
  final String detail;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white,
    borderRadius: BorderRadius.circular(12),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          border: Border.all(color: const Color(0xFFE2E8F0)),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: color.withValues(alpha: .12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: const TextStyle(color: Color(0xFF64748B))),
                  Text(
                    value,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  Text(detail, style: const TextStyle(fontSize: 12)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Color(0xFF94A3B8)),
          ],
        ),
      ),
    ),
  );
}

class _DashboardPanel extends StatelessWidget {
  const _DashboardPanel({
    required this.title,
    required this.icon,
    required this.child,
    this.trailing,
  });
  final String title;
  final IconData icon;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      border: Border.all(color: const Color(0xFFE2E8F0)),
      borderRadius: BorderRadius.circular(14),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 20, color: const Color(0xFF334155)),
            const SizedBox(width: 8),
            Text(
              title,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            ),
            const Spacer(),
            trailing ?? const SizedBox.shrink(),
          ],
        ),
        const SizedBox(height: 12),
        child,
      ],
    ),
  );
}

class _DashboardEmpty extends StatelessWidget {
  const _DashboardEmpty({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 22),
    child: Center(
      child: Column(
        children: [
          Icon(icon, color: const Color(0xFF94A3B8), size: 32),
          const SizedBox(height: 8),
          Text(text, style: const TextStyle(color: Color(0xFF64748B))),
        ],
      ),
    ),
  );
}

class _ComingSoonPage extends StatelessWidget {
  const _ComingSoonPage({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) =>
      Center(child: Text('$title 화면은 준비 중입니다.'));
}

class _RobotManagementPage extends StatefulWidget {
  const _RobotManagementPage({
    required this.drawing,
    required this.activeMapName,
    required this.lanes,
    required this.waypoints,
    required this.waypointNames,
    required this.robots,
    required this.onLoadMap,
    required this.onSpawn,
    required this.onToggle,
    required this.onRemove,
  });

  final UploadedDrawing? drawing;
  final String activeMapName;
  final List<(Offset, Offset)> lanes;
  final List<Offset> waypoints;
  final Map<Offset, String> waypointNames;
  final List<_MockRobot> robots;
  final VoidCallback onLoadMap;
  final VoidCallback onSpawn;
  final ValueChanged<_MockRobot> onToggle;
  final ValueChanged<_MockRobot> onRemove;

  @override
  State<_RobotManagementPage> createState() => _RobotManagementPageState();
}

class _RobotManagementPageState extends State<_RobotManagementPage> {
  String _runtimeMode = '앱 Mock';

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(28),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '로봇 운영',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 6),
                  const Text('Gazebo나 RViz 창 없이 앱 지도에서 로봇을 확인할 수 있습니다.'),
                ],
              ),
            ),
            OutlinedButton.icon(
              onPressed: () => _showUsageGuide(context, _UsageGuideTopic.robot),
              icon: const Icon(Icons.help_outline),
              label: const Text('사용법'),
            ),
            const SizedBox(width: 10),
            SizedBox(
              width: 220,
              child: DropdownButtonFormField<String>(
                initialValue: _runtimeMode,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: '로봇 실행 방식',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                items: const [
                  DropdownMenuItem(value: '앱 Mock', child: Text('앱 Mock')),
                  DropdownMenuItem(
                    value: 'Headless Gazebo',
                    child: Text('Headless Gazebo'),
                  ),
                  DropdownMenuItem(value: '실제 로봇', child: Text('실제 로봇')),
                ],
                onChanged: (value) {
                  if (value != null) setState(() => _runtimeMode = value);
                },
              ),
            ),
            const SizedBox(width: 10),
            const Chip(
              avatar: Icon(Icons.visibility_off_outlined, size: 17),
              label: Text('Gazebo · RViz 끔'),
            ),
            const SizedBox(width: 12),
            OutlinedButton.icon(
              onPressed: widget.onLoadMap,
              icon: const Icon(Icons.folder_open_outlined),
              label: const Text('배포 맵 불러오기'),
            ),
            const SizedBox(width: 10),
            FilledButton.icon(
              onPressed: _runtimeMode == '앱 Mock' ? widget.onSpawn : null,
              icon: const Icon(Icons.add_circle_outline),
              label: const Text('로봇 Spawn'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            const Icon(Icons.map_outlined, size: 18, color: Color(0xFF2563EB)),
            const SizedBox(width: 7),
            Text(
              '현재 운영 맵: ${widget.activeMapName}',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (_runtimeMode != '앱 Mock')
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFEFF6FF),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '$_runtimeMode 모드는 외부 백엔드 연결용입니다. 이 화면의 Spawn은 앱 Mock 모드에서 사용하세요.',
              style: const TextStyle(color: Color(0xFF1D4ED8)),
            ),
          ),
        const SizedBox(height: 18),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final map = _RobotMapCard(
                drawing: widget.drawing,
                lanes: widget.lanes,
                waypoints: widget.waypoints,
                waypointNames: widget.waypointNames,
                robots: widget.robots,
              );
              final list = _RobotListCard(
                robots: widget.robots,
                onToggle: widget.onToggle,
                onRemove: widget.onRemove,
              );
              if (constraints.maxWidth < 960) {
                return Column(
                  children: [
                    Expanded(child: map),
                    const SizedBox(height: 14),
                    SizedBox(height: 230, child: list),
                  ],
                );
              }
              return Row(
                children: [
                  Expanded(child: map),
                  const SizedBox(width: 18),
                  SizedBox(width: 340, child: list),
                ],
              );
            },
          ),
        ),
      ],
    ),
  );
}

class _RobotMapCard extends StatelessWidget {
  const _RobotMapCard({
    required this.drawing,
    required this.lanes,
    required this.waypoints,
    required this.waypointNames,
    required this.robots,
  });

  final UploadedDrawing? drawing;
  final List<(Offset, Offset)> lanes;
  final List<Offset> waypoints;
  final Map<Offset, String> waypointNames;
  final List<_MockRobot> robots;

  @override
  Widget build(BuildContext context) {
    final current = drawing;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFE2E8F0)),
        borderRadius: BorderRadius.circular(14),
      ),
      child: current?.isImage == true && current!.bytes != null
          ? Stack(
              fit: StackFit.expand,
              children: [
                Padding(
                  padding: const EdgeInsets.all(18),
                  child: Image.memory(current.bytes!, fit: BoxFit.contain),
                ),
                Padding(
                  padding: const EdgeInsets.all(18),
                  child: CustomPaint(
                    painter: _RobotOperationsPainter(
                      sourceSize: Size(
                        current.pixelWidth!.toDouble(),
                        current.pixelHeight!.toDouble(),
                      ),
                      lanes: lanes,
                      waypoints: waypoints,
                      waypointNames: waypointNames,
                      robots: robots,
                    ),
                  ),
                ),
              ],
            )
          : const Center(child: Text('맵 관리에서 이미지 도면과 Lane을 먼저 작성하세요.')),
    );
  }
}

class _RobotListCard extends StatelessWidget {
  const _RobotListCard({
    required this.robots,
    required this.onToggle,
    required this.onRemove,
  });
  final List<_MockRobot> robots;
  final ValueChanged<_MockRobot> onToggle;
  final ValueChanged<_MockRobot> onRemove;

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: Colors.white,
      border: Border.all(color: const Color(0xFFE2E8F0)),
      borderRadius: BorderRadius.circular(14),
    ),
    child: Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              const Text(
                'Spawn 로봇',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              const Spacer(),
              Text('${robots.length}대'),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: robots.isEmpty
              ? const Center(child: Text('Spawn된 로봇이 없습니다.'))
              : ListView.separated(
                  itemCount: robots.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final robot = robots[index];
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: robot.color,
                        child: Icon(
                          switch (robot.kind) {
                            _RobotKind.mockMobile => Icons.smart_toy,
                            _RobotKind.pinky => Icons.agriculture,
                            _RobotKind.omxManipulator =>
                              Icons.precision_manufacturing,
                            _RobotKind.mockHumanoid => Icons.accessibility_new,
                          },
                          color: Colors.white,
                          size: 19,
                        ),
                      ),
                      title: Text(
                        robot.id,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      subtitle: Text(
                        '${robot.kind.label} · ${robot.activeTaskId ?? (robot.kind.isMobile ? (robot.moving ? '자율 이동' : '정지') : '고정 설치')}'
                        '${robot.kind.isMobile ? ' · 배터리 ${robot.battery.toStringAsFixed(1)}%' : ''}',
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (robot.kind.isMobile)
                            IconButton(
                              onPressed: () => onToggle(robot),
                              tooltip: robot.moving ? '정지' : '재개',
                              icon: Icon(
                                robot.moving
                                    ? Icons.pause_circle_outline
                                    : Icons.play_circle_outline,
                              ),
                            ),
                          IconButton(
                            onPressed: () => onRemove(robot),
                            tooltip: '삭제',
                            icon: const Icon(
                              Icons.delete_outline,
                              color: Color(0xFFDC2626),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    ),
  );
}

class _RobotOperationsPainter extends CustomPainter {
  const _RobotOperationsPainter({
    required this.sourceSize,
    required this.lanes,
    required this.waypoints,
    required this.waypointNames,
    required this.robots,
  });
  final Size sourceSize;
  final List<(Offset, Offset)> lanes;
  final List<Offset> waypoints;
  final Map<Offset, String> waypointNames;
  final List<_MockRobot> robots;

  @override
  void paint(Canvas canvas, Size size) {
    final fitted = applyBoxFit(BoxFit.contain, sourceSize, size).destination;
    final target = Alignment.center.inscribe(fitted, Offset.zero & size);
    Offset convert(Offset point) => Offset(
      target.left + point.dx * target.width / sourceSize.width,
      target.top + point.dy * target.height / sourceSize.height,
    );
    final lanePaint = Paint()
      ..color = const Color(0xAA0891B2)
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    for (final lane in lanes) {
      canvas.drawLine(convert(lane.$1), convert(lane.$2), lanePaint);
    }
    for (final waypoint in waypoints) {
      canvas.drawCircle(convert(waypoint), 5, Paint()..color = Colors.white);
      canvas.drawCircle(
        convert(waypoint),
        3,
        Paint()..color = const Color(0xFF0891B2),
      );
    }
    final waypointObstacles = [
      for (final waypoint in waypoints)
        Rect.fromCircle(center: convert(waypoint), radius: 9),
      for (final robot in robots)
        Rect.fromCircle(center: convert(robot.position), radius: 18),
    ];
    final occupiedLabels = <Rect>[];
    final canvasBounds = Offset.zero & size;
    for (final waypoint in waypoints) {
      final name = (waypointNames[waypoint] ?? '').trim();
      if (name.isEmpty) continue;
      final center = convert(waypoint);
      final label = TextPainter(
        text: TextSpan(
          text: name,
          style: const TextStyle(
            color: Color(0xFF0F172A),
            fontSize: 10,
            fontWeight: FontWeight.w700,
          ),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
        ellipsis: '…',
      )..layout(maxWidth: 140);
      final labelSize = Size(label.width + 10, label.height + 6);
      final candidates = [
        Rect.fromLTWH(
          center.dx + 11,
          center.dy - labelSize.height / 2,
          labelSize.width,
          labelSize.height,
        ),
        Rect.fromLTWH(
          center.dx - 11 - labelSize.width,
          center.dy - labelSize.height / 2,
          labelSize.width,
          labelSize.height,
        ),
        Rect.fromLTWH(
          center.dx - labelSize.width / 2,
          center.dy - 11 - labelSize.height,
          labelSize.width,
          labelSize.height,
        ),
        Rect.fromLTWH(
          center.dx - labelSize.width / 2,
          center.dy + 11,
          labelSize.width,
          labelSize.height,
        ),
      ];
      bool available(Rect candidate) =>
          canvasBounds.contains(candidate.topLeft) &&
          canvasBounds.contains(candidate.bottomRight) &&
          !occupiedLabels.any((rect) => rect.inflate(3).overlaps(candidate)) &&
          !waypointObstacles.any((rect) => rect.overlaps(candidate));
      int overlapCount(Rect candidate) =>
          occupiedLabels.where((rect) => rect.overlaps(candidate)).length +
          waypointObstacles.where((rect) => rect.overlaps(candidate)).length;
      final labelRect = candidates.firstWhere(
        available,
        orElse: () => candidates.reduce(
          (best, candidate) =>
              overlapCount(candidate) < overlapCount(best) ? candidate : best,
        ),
      );
      occupiedLabels.add(labelRect);
      canvas.drawRRect(
        RRect.fromRectAndRadius(labelRect, const Radius.circular(4)),
        Paint()..color = const Color(0xEFFFFFFF),
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(labelRect, const Radius.circular(4)),
        Paint()
          ..color = const Color(0x330F172A)
          ..style = PaintingStyle.stroke,
      );
      label.paint(canvas, Offset(labelRect.left + 5, labelRect.top + 3));
    }
    for (final robot in robots) {
      final center = convert(robot.position);
      canvas.drawCircle(center, 16, Paint()..color = const Color(0xCCFFFFFF));
      final robotPaint = Paint()
        ..color = robot.color
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round;
      switch (robot.kind) {
        case _RobotKind.omxManipulator:
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              Rect.fromCenter(center: center, width: 22, height: 22),
              const Radius.circular(4),
            ),
            robotPaint,
          );
          canvas.drawLine(
            center,
            center + const Offset(7, -8),
            Paint()
              ..color = Colors.white
              ..strokeWidth = 3,
          );
        case _RobotKind.mockHumanoid:
          canvas.drawCircle(center - const Offset(0, 7), 5, robotPaint);
          canvas.drawLine(
            center - const Offset(0, 1),
            center + const Offset(0, 8),
            robotPaint,
          );
          canvas.drawLine(
            center + const Offset(0, 2),
            center + const Offset(-7, 5),
            robotPaint,
          );
          canvas.drawLine(
            center + const Offset(0, 2),
            center + const Offset(7, 5),
            robotPaint,
          );
        case _RobotKind.pinky:
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              Rect.fromCenter(center: center, width: 25, height: 18),
              const Radius.circular(7),
            ),
            robotPaint,
          );
        case _RobotKind.mockMobile:
          canvas.drawCircle(center, 12, robotPaint);
      }
      final label = TextPainter(
        text: TextSpan(
          text: robot.id,
          style: const TextStyle(
            color: Color(0xFF0F172A),
            fontSize: 11,
            fontWeight: FontWeight.w800,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final rect = Rect.fromLTWH(
        center.dx + 16,
        center.dy - label.height / 2 - 3,
        label.width + 10,
        label.height + 6,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(5)),
        Paint()..color = const Color(0xEFFFFFFF),
      );
      label.paint(canvas, Offset(rect.left + 5, rect.top + 3));
    }
  }

  @override
  bool shouldRepaint(covariant _RobotOperationsPainter oldDelegate) => true;
}

class _ProcessingWarningPanel extends StatelessWidget {
  const _ProcessingWarningPanel({
    required this.message,
    required this.onDismiss,
  });

  final String message;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: const Color(0xFFFFFBEB),
      border: Border.all(color: const Color(0xFFF59E0B)),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.warning_amber_rounded, color: Color(0xFFB45309)),
        const SizedBox(width: 12),
        Expanded(
          child: SelectableText(
            message,
            style: const TextStyle(
              color: Color(0xFF78350F),
              height: 1.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(width: 12),
        TextButton.icon(
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: message));
            if (!context.mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Warning 메시지를 복사했습니다.')),
            );
          },
          icon: const Icon(Icons.copy_rounded, size: 18),
          label: const Text('복사'),
        ),
        IconButton(
          onPressed: onDismiss,
          icon: const Icon(Icons.close_rounded),
          tooltip: 'Warning 닫기',
          color: const Color(0xFF92400E),
        ),
      ],
    ),
  );
}

class _NavigationRail extends StatelessWidget {
  const _NavigationRail({
    required this.selectedIndex,
    required this.onSelected,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    const items = [
      (Icons.grid_view_rounded, '대시보드'),
      (Icons.map_outlined, '맵 관리'),
      (Icons.smart_toy_outlined, '로봇'),
      (Icons.assignment_outlined, '작업'),
      (Icons.analytics_outlined, '운영 분석'),
    ];
    return Container(
      width: 224,
      color: const Color(0xFF111827),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 10),
                child: Row(
                  children: [
                    _Logo(),
                    SizedBox(width: 12),
                    Expanded(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'ROBOSAPIENS',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.8,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 38),
              for (var i = 0; i < items.length; i++)
                InkWell(
                  onTap: () => onSelected(i),
                  borderRadius: BorderRadius.circular(9),
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 7),
                    child: _NavItem(
                      icon: items[i].$1,
                      label: items[i].$2,
                      selected: i == selectedIndex,
                    ),
                  ),
                ),
              const Spacer(),
              const Divider(color: Color(0xFF273449)),
              const SizedBox(height: 8),
              const _NavItem(icon: Icons.settings_outlined, label: '설정'),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF1B2638),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Row(
                  children: [
                    CircleAvatar(
                      radius: 17,
                      backgroundColor: Color(0xFF334155),
                      child: Icon(
                        Icons.person,
                        size: 20,
                        color: Colors.white70,
                      ),
                    ),
                    SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '관리자',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            'admin@robo.ai',
                            style: TextStyle(
                              color: Color(0xFF94A3B8),
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Logo extends StatelessWidget {
  const _Logo();
  @override
  Widget build(BuildContext context) => Container(
    width: 34,
    height: 34,
    decoration: BoxDecoration(
      color: const Color(0xFF2563EB),
      borderRadius: BorderRadius.circular(9),
    ),
    child: const Icon(
      Icons.precision_manufacturing,
      color: Colors.white,
      size: 21,
    ),
  );
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.label,
    this.selected = false,
  });
  final IconData icon;
  final String label;
  final bool selected;
  @override
  Widget build(BuildContext context) => Container(
    height: 46,
    padding: const EdgeInsets.symmetric(horizontal: 13),
    decoration: BoxDecoration(
      color: selected ? const Color(0xFF2563EB) : Colors.transparent,
      borderRadius: BorderRadius.circular(9),
    ),
    child: Row(
      children: [
        Icon(
          icon,
          color: selected ? Colors.white : const Color(0xFF94A3B8),
          size: 21,
        ),
        const SizedBox(width: 12),
        Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : const Color(0xFFCBD5E1),
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    ),
  );
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.title});
  final String title;
  @override
  Widget build(BuildContext context) => Container(
    height: 68,
    padding: const EdgeInsets.symmetric(horizontal: 30),
    decoration: const BoxDecoration(
      color: Colors.white,
      border: Border(bottom: BorderSide(color: Color(0xFFE5EAF0))),
    ),
    child: Row(
      children: [
        Text(
          title,
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            color: Color(0xFF334155),
          ),
        ),
        const Spacer(),
        const _StatusDot(),
        const SizedBox(width: 20),
        const Icon(Icons.notifications_none_rounded, color: Color(0xFF64748B)),
        const SizedBox(width: 18),
        const Icon(Icons.help_outline_rounded, color: Color(0xFF64748B)),
      ],
    ),
  );
}

class _StatusDot extends StatelessWidget {
  const _StatusDot();
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Container(
        width: 8,
        height: 8,
        decoration: const BoxDecoration(
          color: Color(0xFF22C55E),
          shape: BoxShape.circle,
        ),
      ),
      const SizedBox(width: 7),
      const Text(
        '시스템 정상',
        style: TextStyle(
          color: Color(0xFF64748B),
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
    ],
  );
}

enum _UsageGuideTopic { map, robot, task }

class _UsageGuideStep {
  const _UsageGuideStep({
    required this.title,
    required this.why,
    required this.actions,
    required this.doneWhen,
    this.caution,
  });

  final String title;
  final String why;
  final List<String> actions;
  final String doneWhen;
  final String? caution;
}

Future<void> _showUsageGuide(
  BuildContext context,
  _UsageGuideTopic topic,
) async {
  final (title, introduction, steps) = switch (topic) {
    _UsageGuideTopic.map => (
      '맵 관리 사용법',
      '맵은 단순한 배경 그림이 아닙니다. 로봇이 이동할 수 있는 공간, 정지할 위치와 '
          '이동 방향을 관제 시스템이 이해할 수 있는 데이터로 만드는 과정입니다. 아래 '
          '순서를 바꾸지 말고 도면부터 배포까지 진행하세요.',
      const [
        _UsageGuideStep(
          title: '도면 업로드와 축척 확인',
          why: '실제 거리와 이미지 픽셀의 관계가 틀리면 로봇 속도, 위치와 안전거리가 모두 틀어집니다.',
          actions: [
            '도면 업로드를 눌러 창고 PNG/JPG/PDF를 선택합니다.',
            '도면 방향과 잘린 영역이 없는지 확인합니다.',
            '측정 도구로 실제 길이를 아는 벽이나 통로를 지정하고 실제 길이를 입력합니다.',
          ],
          doneWhen: '화면의 측정값과 현장 도면의 실제 길이가 일치하면 완료입니다.',
          caution: '사진처럼 기울어진 이미지나 축척을 모르는 도면은 바로 Lane 작성에 사용하지 마세요.',
        ),
        _UsageGuideStep(
          title: 'Wall 검출과 Floor 생성',
          why: 'Wall은 진입하면 안 되는 경계이고 Floor는 이동 가능한 영역입니다. 이후 경로 검증의 기준이 됩니다.',
          actions: [
            'Wall 검출을 실행하고 누락된 벽이나 잘못 검출된 선을 확인합니다.',
            '지우기와 벽 연결 도구로 출입구를 막는 선이나 끊어진 외벽을 수정합니다.',
            'Floor 생성을 눌러 실제 이동 가능한 바닥 영역이 채워지는지 확인합니다.',
          ],
          doneWhen: '벽 바깥이나 선반 내부가 Floor로 잡히지 않고, 실제 통로가 연결되어 있으면 완료입니다.',
          caution: '출입문을 Wall로 막으면 Lane이 있어도 로봇이 통과할 수 없습니다.',
        ),
        _UsageGuideStep(
          title: 'Lane과 Waypoint 작성',
          why: 'Lane은 로봇이 주행할 중심선이고 Waypoint는 출발·도착·대기·충전·픽업 위치입니다.',
          actions: [
            'Lane 만들기를 켜고 통로 중앙에 Waypoint를 순서대로 놓습니다.',
            '교차로, 회전 전후, 픽업 위치와 하차 위치에는 별도 Waypoint를 만듭니다.',
            'Lane을 양방향·정방향·역방향 중 실제 운영 규칙에 맞게 지정합니다.',
            '대기, 충전, 픽업, 드랍오프 Waypoint에 알아보기 쉬운 이름을 부여합니다.',
          ],
          doneWhen: '모든 운영 위치가 Lane으로 연결되고 이름만 보고 목적을 알 수 있으면 완료입니다.',
          caution: 'Waypoint끼리 Lane 없이 가깝게 놓아도 연결된 것으로 처리되지 않습니다.',
        ),
        _UsageGuideStep(
          title: '오류 검증과 경로 추천 확인',
          why: '화면상으로 자연스러워 보여도 단방향 설정이나 끊어진 Lane 때문에 도달할 수 없는 지점이 생길 수 있습니다.',
          actions: [
            '오류 검증을 눌러 고립된 Waypoint, 이름과 Lane 문제를 확인합니다.',
            'Warning의 Waypoint를 찾아 실제로 왕복 가능한 경로가 있는지 확인합니다.',
            '경로 추천은 참고자료로 사용하고 벽, 회전 반경과 일방통행 규칙에 맞게 수정합니다.',
            '수정 후 오류 검증을 다시 실행합니다.',
          ],
          doneWhen: '설명 가능한 Warning만 남고 모든 필수 지점에 도달 가능하면 완료입니다.',
        ),
        _UsageGuideStep(
          title: '저장과 배포',
          why: '작업 저장은 편집을 보존하고, 배포는 RMF와 로봇이 사용할 운영 파일을 생성·설치하는 과정입니다.',
          actions: [
            '작업 저장으로 편집 가능한 프로젝트 파일을 먼저 보존합니다.',
            '배포를 실행해 building.yaml, 이미지, nav graph와 world를 생성합니다.',
            '배포 로그에서 Map Server와 Fleet Adapter 재시작 및 새 지도 수신을 확인합니다.',
            '로봇 메뉴에서 배포 맵을 다시 불러와 Waypoint와 Lane이 보이는지 확인합니다.',
          ],
          doneWhen: '배포 로그가 성공이고 로봇 메뉴에서 같은 맵을 불러올 수 있으면 완료입니다.',
          caution: '작업 저장과 배포는 다릅니다. 저장만 해서는 실제 관제 맵이 변경되지 않습니다.',
        ),
      ],
    ),
    _UsageGuideTopic.robot => (
      '로봇 운영 사용법',
      '로봇 화면은 운영 맵 위에 장비를 등록하고 현재 위치와 상태를 확인하는 곳입니다. '
          'Spawn은 출발 명령이 아니라 지정 Waypoint에 로봇을 배치하고 관제 대상으로 '
          '등록하는 동작입니다.',
      const [
        _UsageGuideStep(
          title: '배포 맵 불러오기',
          why:
              '로봇과 작업은 동일한 Waypoint 좌표계를 사용해야 합니다. 맵 없이 Spawn하면 위치와 경로를 해석할 수 없습니다.',
          actions: [
            '배포 맵 불러오기를 누릅니다.',
            'nav graph 확인됨 상태인 운영 맵을 선택합니다.',
            '도면, Lane, Waypoint 이름과 현재 운영 맵 이름을 확인합니다.',
          ],
          doneWhen: '로봇 화면에 도면과 Lane, 이름이 표시되면 완료입니다.',
          caution: '운영 중 맵을 교체하면 기존 로봇과 작업의 좌표가 맞지 않을 수 있으므로 다시 등록해야 합니다.',
        ),
        _UsageGuideStep(
          title: '실행 방식 선택',
          why: '앱 Mock, Headless Gazebo와 실제 로봇은 위치를 만드는 주체와 안전 책임이 다릅니다.',
          actions: [
            'UI 확인은 앱 Mock을 선택합니다.',
            '물리 시뮬레이션은 Headless Gazebo와 외부 백엔드를 사용합니다.',
            '실장비는 로컬 Linux Edge Agent와 Fleet Adapter 연결 상태를 먼저 확인합니다.',
          ],
          doneWhen: '시험 목적에 맞는 실행 방식과 백엔드가 준비되면 완료입니다.',
          caution:
              '현재 앱의 직접 Spawn은 Mock 표현입니다. 실제 장비는 전원을 켜고 Edge Agent로 등록해야 합니다.',
        ),
        _UsageGuideStep(
          title: '로봇 유형과 Spawn 위치 선택',
          why: '장비 종류에 따라 이동 가능 여부와 수행할 수 있는 작업이 다르기 때문입니다.',
          actions: [
            'Mock 주행로봇, Pinky, OMX Manipulator 또는 Mock 휴머노이드를 선택합니다.',
            '중복되지 않는 이름을 입력합니다.',
            '이동 로봇은 시작 Waypoint, OMX는 고정 설치 Waypoint를 선택합니다.',
            'Spawn 후 선택한 위치에서 정지 상태인지 확인합니다.',
          ],
          doneWhen: '지도와 목록에 올바른 유형·이름·위치로 표시되고 정지 상태이면 완료입니다.',
          caution: 'OMX Manipulator는 고정 장비이므로 Lane을 따라 이동하지 않습니다.',
        ),
        _UsageGuideStep(
          title: '상태 확인과 이동 시작',
          why: '등록 직후 예상하지 않은 이동을 방지하고 작업 전 장비 상태를 확인해야 합니다.',
          actions: [
            '목록에서 연결 상태, 정지 여부, 배터리와 활성 작업을 확인합니다.',
            '수동 확인이 필요할 때만 재개를 눌러 자율 이동을 시작합니다.',
            '업무 이동은 수동 재개보다 작업 메뉴에서 목적지를 배정해 시작합니다.',
            '이상 동작이 있으면 정지를 누르고 작업과 경로를 확인합니다.',
          ],
          doneWhen: '의도한 명령을 받은 로봇만 움직이고 나머지는 정지해 있으면 정상입니다.',
        ),
        _UsageGuideStep(
          title: '실장비 운영 전 확인',
          why: '화면의 아이콘이 정상이어도 실제 센서, 비상정지와 네트워크가 준비되지 않으면 안전하게 운행할 수 없습니다.',
          actions: [
            'Pinky의 비상정지, 라이다, odometry와 배터리를 확인합니다.',
            'OMX-AI의 원점 복귀, 그리퍼와 작업 범위를 확인합니다.',
            'Edge Agent 및 게이트웨이 연결과 연결 끊김 시 안전 정지를 시험합니다.',
            '저속 단일 로봇 시험 후 여러 로봇 작업을 시작합니다.',
          ],
          doneWhen: '통신 단절과 비상정지 시험까지 통과하면 실작업 준비 완료입니다.',
        ),
      ],
    ),
    _UsageGuideTopic.task => (
      '작업 관리 사용법',
      '작업은 단순 목적지 지정이 아니라 Pinky 이동, OMX-AI 적재와 하차를 정해진 '
          '순서로 실행하는 절차입니다. 앞 단계의 성공이 검증되어야 다음 단계가 시작됩니다.',
      const [
        _UsageGuideStep(
          title: '맵과 로봇 준비',
          why: '작업은 맵의 Waypoint와 실제 수행 로봇을 참조하므로 두 항목이 먼저 준비되어야 합니다.',
          actions: [
            '화면의 준비 안내에서 운영 맵이 선택되었는지 확인합니다.',
            'Pinky 또는 Mock 주행로봇이 Spawn되어 정지 중인지 확인합니다.',
            '실제 적재 작업이면 담당 OMX-AI와 픽업 스테이션의 연결 상태를 확인합니다.',
          ],
          doneWhen: '상단에 작업 준비 완료와 가용 로봇 수가 표시되면 완료입니다.',
        ),
        _UsageGuideStep(
          title: '연속 작업 생성',
          why:
              '이동과 팔 동작을 한 작업에 묶어야 잘못된 위치에서 팔이 움직이거나 적재 전에 로봇이 출발하는 일을 막을 수 있습니다.',
          actions: [
            '새 작업을 누르고 작업자가 구분할 수 있는 이름을 입력합니다.',
            '자동 배정 또는 특정 Pinky를 선택합니다.',
            '단계 추가로 Pinky 이동, OMX-AI 픽업과 대기를 구성합니다.',
            '카드를 끌어 실제 실행 순서대로 배치하고 필요 없는 단계는 삭제합니다.',
          ],
          doneWhen: '작업 이름, 수행 로봇과 모든 단계의 목적지가 지정되면 시작할 수 있습니다.',
        ),
        _UsageGuideStep(
          title: '권장 주문 작업 순서',
          why: '로봇 도착과 적재 성공을 각각 확인해야 상품 누락과 빈 차 출발을 방지할 수 있습니다.',
          actions: [
            '1단계: Pinky를 주문 온도에 맞는 픽업 Waypoint로 이동시킵니다.',
            '2단계: Pinky가 정지한 뒤 OMX-AI 픽업/적재를 실행합니다.',
            '3단계: 적재 성공 후 Pinky를 하차 Waypoint로 이동시킵니다.',
            '필요하면 작업자 확인이나 설비 동작을 위한 대기 단계를 추가합니다.',
          ],
          doneWhen: '픽업 이동 → 적재 → 하차 이동 순서가 명확하면 완료입니다.',
          caution: 'OMX-AI 성공 전에 하차 이동을 시작하도록 순서를 만들지 마세요.',
        ),
        _UsageGuideStep(
          title: '실행 상태와 오류 확인',
          why: '진행 중인 단계와 실패 위치를 알아야 재시도 여부와 현장 조치를 안전하게 결정할 수 있습니다.',
          actions: [
            '목록에서 완료 단계 수와 현재 활성 단계를 확인합니다.',
            '경로 없음은 맵의 Lane 연결과 방향을 먼저 확인합니다.',
            '적재 실패는 상품, 로봇 ID, 정지 위치, OMX 그리퍼 상태를 확인합니다.',
            '원인을 모르는 상태에서는 반복 시작하지 말고 작업을 취소한 뒤 현장을 확인합니다.',
          ],
          doneWhen: '모든 단계가 완료되고 로봇이 최종 Waypoint에서 정지하면 운반 단계가 완료된 것입니다.',
        ),
        _UsageGuideStep(
          title: '실제 주문 완료 판단',
          why: '로봇이 하차 지점에 도착한 것과 주문 상품이 실제 인계된 것은 서로 다른 사건입니다.',
          actions: [
            '작업자 확인, 자동 하차 설비 응답 또는 데크 센서로 상품 인수를 확인합니다.',
            '인수 완료 후 주문 상태와 재고 이력을 완료 처리합니다.',
            '취소·실패 작업은 적재된 상품과 예약 재고 상태를 반드시 대조합니다.',
          ],
          doneWhen: '상품 인수와 재고 반영까지 확인되어야 주문 전체가 완료입니다.',
          caution: '현재 앱 Mock 엔진의 완료 표시는 실제 상품 인수 증명이 아닙니다.',
        ),
      ],
    ),
  };

  await showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      icon: const Icon(Icons.menu_book_outlined, size: 38),
      title: Text(title),
      content: SizedBox(
        width: 780,
        height: 650,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFEFF6FF),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFBFDBFE)),
              ),
              child: Text(
                introduction,
                style: const TextStyle(height: 1.55, color: Color(0xFF1E3A8A)),
              ),
            ),
            const SizedBox(height: 14),
            Expanded(
              child: ListView.separated(
                itemCount: steps.length,
                separatorBuilder: (_, _) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final step = steps[index];
                  return Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            CircleAvatar(
                              radius: 15,
                              backgroundColor: const Color(0xFF2563EB),
                              foregroundColor: Colors.white,
                              child: Text('${index + 1}'),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                step.title,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Text(
                          '왜 필요한가: ${step.why}',
                          style: const TextStyle(height: 1.45),
                        ),
                        const SizedBox(height: 9),
                        for (
                          var actionIndex = 0;
                          actionIndex < step.actions.length;
                          actionIndex++
                        )
                          Padding(
                            padding: const EdgeInsets.only(bottom: 5),
                            child: Text(
                              '${actionIndex + 1}) ${step.actions[actionIndex]}',
                              style: const TextStyle(height: 1.4),
                            ),
                          ),
                        const SizedBox(height: 6),
                        Text(
                          '완료 기준: ${step.doneWhen}',
                          style: const TextStyle(
                            color: Color(0xFF15803D),
                            fontWeight: FontWeight.w700,
                            height: 1.4,
                          ),
                        ),
                        if (step.caution != null) ...[
                          const SizedBox(height: 7),
                          Text(
                            '주의: ${step.caution}',
                            style: const TextStyle(
                              color: Color(0xFFB45309),
                              fontWeight: FontWeight.w700,
                              height: 1.4,
                            ),
                          ),
                        ],
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton.icon(
          onPressed: () async {
            final plainText = StringBuffer('$title\n\n$introduction\n');
            for (var index = 0; index < steps.length; index++) {
              final step = steps[index];
              plainText
                ..writeln('\n${index + 1}. ${step.title}')
                ..writeln('왜 필요한가: ${step.why}');
              for (
                var actionIndex = 0;
                actionIndex < step.actions.length;
                actionIndex++
              ) {
                plainText.writeln(
                  '  ${actionIndex + 1}) ${step.actions[actionIndex]}',
                );
              }
              plainText.writeln('완료 기준: ${step.doneWhen}');
              if (step.caution != null) {
                plainText.writeln('주의: ${step.caution}');
              }
            }
            await Clipboard.setData(ClipboardData(text: plainText.toString()));
            if (!dialogContext.mounted) return;
            ScaffoldMessenger.of(
              dialogContext,
            ).showSnackBar(const SnackBar(content: Text('사용법 전체 내용을 복사했습니다.')));
          },
          icon: const Icon(Icons.copy_outlined),
          label: const Text('전체 복사'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('확인'),
        ),
      ],
    ),
  );
}

enum _ExportAction { download, copy }

class _PageHeading extends StatelessWidget {
  const _PageHeading({
    required this.onHelp,
    required this.onUpload,
    required this.exportEnabled,
    required this.onValidate,
    required this.onRecommend,
    required this.onDownload,
    required this.onCopy,
    required this.onSaveProject,
    required this.onLoadProject,
  });
  final VoidCallback onHelp;
  final VoidCallback onUpload;
  final bool exportEnabled;
  final VoidCallback onValidate;
  final VoidCallback onRecommend;
  final VoidCallback onDownload;
  final VoidCallback onCopy;
  final VoidCallback onSaveProject;
  final VoidCallback onLoadProject;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '새 창고 맵 만들기',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 7),
            const Text('도면을 불러오면 이동 경로와 로봇 운영 지점을 빠르게 설정할 수 있습니다.'),
          ],
        ),
      ),
      OutlinedButton.icon(
        onPressed: onHelp,
        icon: const Icon(Icons.help_outline, size: 18),
        label: const Text('사용법'),
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 16),
        ),
      ),
      const SizedBox(width: 8),
      OutlinedButton.icon(
        onPressed: onLoadProject,
        icon: const Icon(Icons.folder_open_outlined, size: 18),
        label: const Text('작업 불러오기'),
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 16),
        ),
      ),
      const SizedBox(width: 8),
      OutlinedButton.icon(
        onPressed: exportEnabled ? onSaveProject : null,
        icon: const Icon(Icons.save_outlined, size: 18),
        label: const Text('작업 저장'),
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 16),
        ),
      ),
      const SizedBox(width: 8),
      OutlinedButton.icon(
        onPressed: exportEnabled ? onValidate : null,
        icon: const Icon(Icons.fact_check_outlined, size: 18),
        label: const Text('오류 검증'),
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 16),
        ),
      ),
      const SizedBox(width: 8),
      OutlinedButton.icon(
        onPressed: exportEnabled ? onRecommend : null,
        icon: const Icon(Icons.auto_awesome_outlined, size: 18),
        label: const Text('경로 추천'),
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 16),
        ),
      ),
      const SizedBox(width: 8),
      PopupMenuButton<_ExportAction>(
        enabled: exportEnabled,
        onSelected: (action) {
          if (action == _ExportAction.download) {
            onDownload();
          } else {
            onCopy();
          }
        },
        itemBuilder: (context) => const [
          PopupMenuItem(
            value: _ExportAction.download,
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.download_outlined),
              title: Text('파일 다운로드'),
              subtitle: Text('.building.yaml로 저장'),
            ),
          ),
          PopupMenuItem(
            value: _ExportAction.copy,
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.content_copy_outlined),
              title: Text('YAML 복사'),
              subtitle: Text('클립보드에 내용 복사'),
            ),
          ),
        ],
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 17, vertical: 14),
          decoration: BoxDecoration(
            color: exportEnabled ? Colors.white : const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFCBD5E1)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.download_outlined,
                size: 19,
                color: exportEnabled
                    ? const Color(0xFF334155)
                    : const Color(0xFF94A3B8),
              ),
              const SizedBox(width: 8),
              Text(
                '맵 다운로드',
                style: TextStyle(
                  color: exportEnabled
                      ? const Color(0xFF334155)
                      : const Color(0xFF94A3B8),
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 5),
              const Icon(Icons.arrow_drop_down, size: 18),
            ],
          ),
        ),
      ),
      const SizedBox(width: 10),
      FilledButton.icon(
        onPressed: onUpload,
        icon: const Icon(Icons.upload_file_rounded, size: 19),
        label: const Text('도면 올리기'),
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 17),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
    ],
  );
}

class _StageBar extends StatelessWidget {
  const _StageBar({required this.activeStage});
  final MapStage activeStage;
  static const labels = [
    '도면 업로드',
    'Measurement',
    '벽 인식',
    'Floor 생성',
    'Lane 만들기',
    '위치 지정',
    '배포',
  ];
  @override
  Widget build(BuildContext context) {
    final active = MapStage.values.indexOf(activeStage);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: const Color(0xFFE5EAF0)),
      ),
      child: Row(
        children: [
          for (var i = 0; i < labels.length; i++) ...[
            _StageItem(
              index: i,
              label: labels[i],
              active: i == active,
              done: i < active,
            ),
            if (i < labels.length - 1)
              Expanded(
                child: Container(
                  height: 1,
                  color: i < active
                      ? const Color(0xFF2563EB)
                      : const Color(0xFFE2E8F0),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _StageItem extends StatelessWidget {
  const _StageItem({
    required this.index,
    required this.label,
    required this.active,
    required this.done,
  });
  final int index;
  final String label;
  final bool active;
  final bool done;
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 28,
        height: 28,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: active || done
              ? const Color(0xFF2563EB)
              : const Color(0xFFF1F5F9),
          shape: BoxShape.circle,
        ),
        child: done
            ? const Icon(Icons.check, size: 16, color: Colors.white)
            : Text(
                '${index + 1}',
                style: TextStyle(
                  color: active ? Colors.white : const Color(0xFF94A3B8),
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
      ),
      const SizedBox(width: 8),
      Text(
        label,
        style: TextStyle(
          color: active ? const Color(0xFF1E293B) : const Color(0xFF94A3B8),
          fontSize: 12,
          fontWeight: active ? FontWeight.w700 : FontWeight.w500,
        ),
      ),
    ],
  );
}

class _MapWorkspace extends StatelessWidget {
  const _MapWorkspace({
    required this.drawing,
    required this.transformController,
    required this.onZoomIn,
    required this.onZoomOut,
    required this.onFitScreen,
    required this.onRenumberVertices,
    required this.wallMask,
    required this.wallColor,
    required this.floorMask,
    required this.floorColor,
    required this.mapVertices,
    required this.vertexLabelRevision,
    required this.optimizedWalls,
    required this.recommendedLanes,
    required this.laneDirections,
    required this.laneWaypoints,
    required this.waypointNames,
    required this.waypointTypes,
    required this.activeLaneEndpoint,
    required this.waypointMode,
    required this.onAddWaypoint,
    required this.onEditWaypoint,
    required this.onSelectLane,
    required this.isWallConnectMode,
    required this.pendingWallVertex,
    required this.onToggleWallConnect,
    required this.onSelectWallVertex,
    required this.isWallEndpointEditMode,
    required this.onToggleWallEndpointEdit,
    required this.onMoveWallEndpoint,
    required this.measurement,
    required this.showDrawingInfo,
    required this.onCloseDrawingInfo,
    required this.isMeasurementSelected,
    required this.onSelectMeasurement,
    required this.onRemoveMeasurement,
    required this.isMeasurementMode,
    required this.onMeasurementSelected,
    required this.onCloseMeasurementMode,
    required this.isWallEraseMode,
    required this.canUndoWallErase,
    required this.onToggleWallErase,
    required this.onEraseWalls,
    required this.onUndoWallErase,
    required this.isPicking,
    required this.onPick,
    required this.onRemove,
  });
  final UploadedDrawing? drawing;
  final TransformationController transformController;
  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;
  final VoidCallback onFitScreen;
  final VoidCallback onRenumberVertices;
  final _WallMask? wallMask;
  final Color wallColor;
  final _WallMask? floorMask;
  final Color floorColor;
  final List<Offset> mapVertices;
  final int vertexLabelRevision;
  final List<(Offset, Offset)> optimizedWalls;
  final List<(Offset, Offset)> recommendedLanes;
  final Map<(Offset, Offset), String> laneDirections;
  final List<Offset> laneWaypoints;
  final Map<Offset, String> waypointNames;
  final Map<Offset, String> waypointTypes;
  final Offset? activeLaneEndpoint;
  final bool waypointMode;
  final ValueChanged<Offset> onAddWaypoint;
  final ValueChanged<Offset> onEditWaypoint;
  final ValueChanged<(Offset, Offset)> onSelectLane;
  final bool isWallConnectMode;
  final Offset? pendingWallVertex;
  final VoidCallback onToggleWallConnect;
  final ValueChanged<Offset> onSelectWallVertex;
  final bool isWallEndpointEditMode;
  final VoidCallback onToggleWallEndpointEdit;
  final void Function(Offset original, Offset updated) onMoveWallEndpoint;
  final _MapMeasurement? measurement;
  final bool showDrawingInfo;
  final VoidCallback onCloseDrawingInfo;
  final bool isMeasurementSelected;
  final VoidCallback onSelectMeasurement;
  final VoidCallback onRemoveMeasurement;
  final bool isMeasurementMode;
  final void Function(Offset start, Offset end) onMeasurementSelected;
  final VoidCallback onCloseMeasurementMode;
  final bool isWallEraseMode;
  final bool canUndoWallErase;
  final VoidCallback onToggleWallErase;
  final ValueChanged<Rect> onEraseWalls;
  final VoidCallback onUndoWallErase;
  final bool isPicking;
  final VoidCallback onPick;
  final VoidCallback onRemove;
  @override
  Widget build(BuildContext context) => Container(
    height: 936,
    clipBehavior: Clip.antiAlias,
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: const Color(0xFFE2E8F0)),
    ),
    child: Column(
      children: [
        Container(
          height: 58,
          padding: const EdgeInsets.symmetric(horizontal: 18),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: Color(0xFFE5EAF0))),
          ),
          child: Row(
            children: [
              const Text(
                '도면 작업 영역',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1E293B),
                ),
              ),
              const Spacer(),
              if (drawing != null) ...[
                if (measurement != null && isMeasurementSelected) ...[
                  IconButton(
                    onPressed: onRemoveMeasurement,
                    icon: const Icon(Icons.delete_outline),
                    color: const Color(0xFFEF4444),
                    tooltip: 'Measurement 제거',
                    style: IconButton.styleFrom(
                      backgroundColor: const Color(0xFFFEF2F2),
                    ),
                  ),
                  const SizedBox(width: 5),
                ],
                if (wallMask != null) ...[
                  IconButton(
                    onPressed: onToggleWallConnect,
                    icon: Icon(
                      Icons.add_link,
                      color: isWallConnectMode
                          ? const Color(0xFF2563EB)
                          : const Color(0xFF64748B),
                    ),
                    tooltip: isWallConnectMode ? '벽 연결 종료' : '끊어진 벽 연결',
                    style: IconButton.styleFrom(
                      backgroundColor: isWallConnectMode
                          ? const Color(0xFFEFF6FF)
                          : Colors.transparent,
                    ),
                  ),
                  IconButton(
                    onPressed: onToggleWallEndpointEdit,
                    icon: Icon(
                      Icons.open_with,
                      color: isWallEndpointEditMode
                          ? const Color(0xFF2563EB)
                          : const Color(0xFF64748B),
                    ),
                    tooltip: isWallEndpointEditMode ? '끝점 이동 종료' : '마지막 정점 이동',
                    style: IconButton.styleFrom(
                      backgroundColor: isWallEndpointEditMode
                          ? const Color(0xFFEFF6FF)
                          : Colors.transparent,
                    ),
                  ),
                  IconButton(
                    onPressed: onToggleWallErase,
                    icon: Icon(
                      Icons.cleaning_services_outlined,
                      color: isWallEraseMode
                          ? const Color(0xFF2563EB)
                          : const Color(0xFF64748B),
                    ),
                    tooltip: isWallEraseMode ? '벽 지우기 종료' : '잘못 인식된 벽 선택 제거',
                    style: IconButton.styleFrom(
                      backgroundColor: isWallEraseMode
                          ? const Color(0xFFEFF6FF)
                          : Colors.transparent,
                    ),
                  ),
                  IconButton(
                    onPressed: canUndoWallErase ? onUndoWallErase : null,
                    icon: const Icon(Icons.undo, size: 20),
                    tooltip: '벽 제거 실행 취소',
                  ),
                  const SizedBox(width: 5),
                ],
                _ToolButton(
                  icon: Icons.zoom_out,
                  tooltip: '축소',
                  onPressed: onZoomOut,
                ),
                _ToolButton(
                  icon: Icons.zoom_in,
                  tooltip: '확대',
                  onPressed: onZoomIn,
                ),
                _ToolButton(
                  icon: Icons.fit_screen,
                  tooltip: '화면 맞춤',
                  onPressed: onFitScreen,
                ),
                _ToolButton(
                  icon: Icons.format_list_numbered,
                  tooltip: '정점 재넘버링',
                  onPressed: onRenumberVertices,
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: onRemove,
                  icon: const Icon(
                    Icons.delete_outline,
                    color: Color(0xFFEF4444),
                  ),
                  tooltip: '도면 제거',
                ),
              ],
            ],
          ),
        ),
        Expanded(
          child: drawing == null
              ? _UploadEmpty(isPicking: isPicking, onPick: onPick)
              : _DrawingPreview(
                  drawing: drawing!,
                  transformController: transformController,
                  wallMask: wallMask,
                  wallColor: wallColor,
                  floorMask: floorMask,
                  floorColor: floorColor,
                  mapVertices: mapVertices,
                  vertexLabelRevision: vertexLabelRevision,
                  optimizedWalls: optimizedWalls,
                  recommendedLanes: recommendedLanes,
                  laneDirections: laneDirections,
                  laneWaypoints: laneWaypoints,
                  waypointNames: waypointNames,
                  waypointTypes: waypointTypes,
                  activeLaneEndpoint: activeLaneEndpoint,
                  waypointMode: waypointMode,
                  onAddWaypoint: onAddWaypoint,
                  onEditWaypoint: onEditWaypoint,
                  onSelectLane: onSelectLane,
                  wallConnectMode: isWallConnectMode,
                  pendingWallVertex: pendingWallVertex,
                  onSelectWallVertex: onSelectWallVertex,
                  wallEndpointEditMode: isWallEndpointEditMode,
                  onMoveWallEndpoint: onMoveWallEndpoint,
                  measurement: measurement,
                  showDrawingInfo: showDrawingInfo,
                  onCloseDrawingInfo: onCloseDrawingInfo,
                  measurementSelected: isMeasurementSelected,
                  onSelectMeasurement: onSelectMeasurement,
                  measurementMode: isMeasurementMode,
                  onMeasurementSelected: onMeasurementSelected,
                  onCloseMeasurementMode: onCloseMeasurementMode,
                  isWallEraseMode: isWallEraseMode,
                  onEraseWalls: onEraseWalls,
                ),
        ),
      ],
    ),
  );
}

class _ToolButton extends StatelessWidget {
  const _ToolButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  @override
  Widget build(BuildContext context) => IconButton(
    onPressed: onPressed,
    icon: Icon(icon, size: 20),
    tooltip: tooltip,
    color: const Color(0xFF64748B),
  );
}

class _UploadEmpty extends StatelessWidget {
  const _UploadEmpty({required this.isPicking, required this.onPick});
  final bool isPicking;
  final VoidCallback onPick;
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.all(22),
    decoration: BoxDecoration(
      color: const Color(0xFFF8FAFC),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: const Color(0xFFCBD5E1), width: 1.4),
    ),
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 430),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 76,
              height: 76,
              decoration: const BoxDecoration(
                color: Color(0xFFEFF6FF),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.cloud_upload_outlined,
                color: Color(0xFF2563EB),
                size: 36,
              ),
            ),
            const SizedBox(height: 22),
            const Text(
              '창고 도면을 올려주세요',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: Color(0xFF1E293B),
              ),
            ),
            const SizedBox(height: 9),
            const Text(
              '파일을 선택하면 맵 생성 준비를 시작합니다.\nPNG, JPG, PDF, DXF, DWG 형식을 지원합니다.',
              textAlign: TextAlign.center,
              style: TextStyle(height: 1.6, color: Color(0xFF64748B)),
            ),
            const SizedBox(height: 22),
            OutlinedButton.icon(
              onPressed: isPicking ? null : onPick,
              icon: isPicking
                  ? const SizedBox(
                      width: 17,
                      height: 17,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.folder_open_outlined),
              label: Text(isPicking ? '불러오는 중...' : '내 컴퓨터에서 선택'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 15,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(9),
                ),
              ),
            ),
            const SizedBox(height: 13),
            const Text(
              '최대 파일 크기 50MB',
              style: TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
            ),
          ],
        ),
      ),
    ),
  );
}

class _DrawingPreview extends StatelessWidget {
  const _DrawingPreview({
    required this.drawing,
    required this.transformController,
    required this.wallMask,
    required this.wallColor,
    required this.floorMask,
    required this.floorColor,
    required this.mapVertices,
    required this.vertexLabelRevision,
    required this.optimizedWalls,
    required this.recommendedLanes,
    required this.laneDirections,
    required this.laneWaypoints,
    required this.waypointNames,
    required this.waypointTypes,
    required this.activeLaneEndpoint,
    required this.waypointMode,
    required this.onAddWaypoint,
    required this.onEditWaypoint,
    required this.onSelectLane,
    required this.wallConnectMode,
    required this.pendingWallVertex,
    required this.onSelectWallVertex,
    required this.wallEndpointEditMode,
    required this.onMoveWallEndpoint,
    required this.measurement,
    required this.showDrawingInfo,
    required this.onCloseDrawingInfo,
    required this.measurementSelected,
    required this.onSelectMeasurement,
    required this.measurementMode,
    required this.onMeasurementSelected,
    required this.onCloseMeasurementMode,
    required this.isWallEraseMode,
    required this.onEraseWalls,
  });
  final UploadedDrawing drawing;
  final TransformationController transformController;
  final _WallMask? wallMask;
  final Color wallColor;
  final _WallMask? floorMask;
  final Color floorColor;
  final List<Offset> mapVertices;
  final int vertexLabelRevision;
  final List<(Offset, Offset)> optimizedWalls;
  final List<(Offset, Offset)> recommendedLanes;
  final Map<(Offset, Offset), String> laneDirections;
  final List<Offset> laneWaypoints;
  final Map<Offset, String> waypointNames;
  final Map<Offset, String> waypointTypes;
  final Offset? activeLaneEndpoint;
  final bool waypointMode;
  final ValueChanged<Offset> onAddWaypoint;
  final ValueChanged<Offset> onEditWaypoint;
  final ValueChanged<(Offset, Offset)> onSelectLane;
  final bool wallConnectMode;
  final Offset? pendingWallVertex;
  final ValueChanged<Offset> onSelectWallVertex;
  final bool wallEndpointEditMode;
  final void Function(Offset original, Offset updated) onMoveWallEndpoint;
  final _MapMeasurement? measurement;
  final bool showDrawingInfo;
  final VoidCallback onCloseDrawingInfo;
  final bool measurementSelected;
  final VoidCallback onSelectMeasurement;
  final bool measurementMode;
  final void Function(Offset start, Offset end) onMeasurementSelected;
  final VoidCallback onCloseMeasurementMode;
  final bool isWallEraseMode;
  final ValueChanged<Rect> onEraseWalls;
  @override
  Widget build(BuildContext context) => Stack(
    children: [
      Positioned.fill(
        child: Container(
          color: const Color(0xFFF1F5F9),
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 33.6),
          child: drawing.isImage && drawing.bytes != null
              ? InteractiveViewer(
                  transformationController: transformController,
                  minScale: 0.4,
                  maxScale: 5,
                  panEnabled:
                      !isWallEraseMode &&
                      !measurementMode &&
                      !wallConnectMode &&
                      !wallEndpointEditMode &&
                      !waypointMode,
                  scaleEnabled:
                      !isWallEraseMode &&
                      !measurementMode &&
                      !wallConnectMode &&
                      !wallEndpointEditMode &&
                      !waypointMode,
                  child: _WallEditorCanvas(
                    bytes: drawing.bytes!,
                    sourceSize: Size(
                      drawing.pixelWidth!.toDouble(),
                      drawing.pixelHeight!.toDouble(),
                    ),
                    mask: wallMask,
                    color: wallColor,
                    floorMask: floorMask,
                    floorColor: floorColor,
                    mapVertices: mapVertices,
                    vertexLabelRevision: vertexLabelRevision,
                    optimizedWalls: optimizedWalls,
                    recommendedLanes: recommendedLanes,
                    laneDirections: laneDirections,
                    laneWaypoints: laneWaypoints,
                    waypointNames: waypointNames,
                    waypointTypes: waypointTypes,
                    activeLaneEndpoint: activeLaneEndpoint,
                    waypointMode: waypointMode,
                    onAddWaypoint: onAddWaypoint,
                    onEditWaypoint: onEditWaypoint,
                    onSelectLane: onSelectLane,
                    wallConnectMode: wallConnectMode,
                    pendingWallVertex: pendingWallVertex,
                    onSelectWallVertex: onSelectWallVertex,
                    wallEndpointEditMode: wallEndpointEditMode,
                    onMoveWallEndpoint: onMoveWallEndpoint,
                    measurement: measurement,
                    measurementSelected: measurementSelected,
                    onSelectMeasurement: onSelectMeasurement,
                    measurementMode: measurementMode,
                    onMeasurementSelected: onMeasurementSelected,
                    onCloseMeasurementMode: onCloseMeasurementMode,
                    eraseMode: isWallEraseMode,
                    onErase: onEraseWalls,
                  ),
                )
              : _NonImagePreview(extension: drawing.extension),
        ),
      ),
      if (showDrawingInfo)
        Positioned(
          left: 16,
          bottom: 16,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: .94),
              borderRadius: BorderRadius.circular(9),
              boxShadow: const [
                BoxShadow(color: Color(0x18000000), blurRadius: 12),
              ],
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.description_outlined,
                  size: 18,
                  color: Color(0xFF2563EB),
                ),
                const SizedBox(width: 8),
                Text(
                  drawing.name,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF334155),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  drawing.readableSize,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF94A3B8),
                  ),
                ),
                const SizedBox(width: 6),
                InkWell(
                  onTap: onCloseDrawingInfo,
                  customBorder: const CircleBorder(),
                  child: const Padding(
                    padding: EdgeInsets.all(3),
                    child: Icon(
                      Icons.close,
                      size: 16,
                      color: Color(0xFF64748B),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
    ],
  );
}

class _WallEditorCanvas extends StatefulWidget {
  const _WallEditorCanvas({
    required this.bytes,
    required this.sourceSize,
    required this.mask,
    required this.color,
    required this.floorMask,
    required this.floorColor,
    required this.mapVertices,
    required this.vertexLabelRevision,
    required this.optimizedWalls,
    required this.recommendedLanes,
    required this.laneDirections,
    required this.laneWaypoints,
    required this.waypointNames,
    required this.waypointTypes,
    required this.activeLaneEndpoint,
    required this.waypointMode,
    required this.onAddWaypoint,
    required this.onEditWaypoint,
    required this.onSelectLane,
    required this.wallConnectMode,
    required this.pendingWallVertex,
    required this.onSelectWallVertex,
    required this.wallEndpointEditMode,
    required this.onMoveWallEndpoint,
    required this.measurement,
    required this.measurementSelected,
    required this.onSelectMeasurement,
    required this.measurementMode,
    required this.onMeasurementSelected,
    required this.onCloseMeasurementMode,
    required this.eraseMode,
    required this.onErase,
  });

  final Uint8List bytes;
  final Size sourceSize;
  final _WallMask? mask;
  final Color color;
  final _WallMask? floorMask;
  final Color floorColor;
  final List<Offset> mapVertices;
  final int vertexLabelRevision;
  final List<(Offset, Offset)> optimizedWalls;
  final List<(Offset, Offset)> recommendedLanes;
  final Map<(Offset, Offset), String> laneDirections;
  final List<Offset> laneWaypoints;
  final Map<Offset, String> waypointNames;
  final Map<Offset, String> waypointTypes;
  final Offset? activeLaneEndpoint;
  final bool waypointMode;
  final ValueChanged<Offset> onAddWaypoint;
  final ValueChanged<Offset> onEditWaypoint;
  final ValueChanged<(Offset, Offset)> onSelectLane;
  final bool wallConnectMode;
  final Offset? pendingWallVertex;
  final ValueChanged<Offset> onSelectWallVertex;
  final bool wallEndpointEditMode;
  final void Function(Offset original, Offset updated) onMoveWallEndpoint;
  final _MapMeasurement? measurement;
  final bool measurementSelected;
  final VoidCallback onSelectMeasurement;
  final bool measurementMode;
  final void Function(Offset start, Offset end) onMeasurementSelected;
  final VoidCallback onCloseMeasurementMode;
  final bool eraseMode;
  final ValueChanged<Rect> onErase;

  @override
  State<_WallEditorCanvas> createState() => _WallEditorCanvasState();
}

class _WallEditorCanvasState extends State<_WallEditorCanvas> {
  Offset? _start;
  Offset? _current;
  Offset _measurementBadgeOffset = const Offset(12, 12);
  Offset? _movingWallVertex;
  Offset? _movingWallScreenPoint;
  Offset? _waypointCursor;
  Offset? _hoveredWaypoint;
  Offset? _waypointHoverPosition;
  bool _movingWallHorizontally = true;

  Rect? get _selection => _start == null || _current == null
      ? null
      : Rect.fromPoints(_start!, _current!);

  (Offset, Offset) _measurementScreenPoints(Size canvasSize) {
    final measurement = widget.measurement!;
    final fitted = applyBoxFit(
      BoxFit.contain,
      widget.sourceSize,
      canvasSize,
    ).destination;
    final target = Alignment.center.inscribe(fitted, Offset.zero & canvasSize);
    Offset convert(Offset point) => Offset(
      target.left + point.dx * target.width / widget.sourceSize.width,
      target.top + point.dy * target.height / widget.sourceSize.height,
    );
    return (convert(measurement.start), convert(measurement.end));
  }

  void _trySelectMeasurement(Offset position, Size canvasSize) {
    if (widget.measurement == null) return;
    final points = _measurementScreenPoints(canvasSize);
    final line = points.$2 - points.$1;
    final lengthSquared = line.distanceSquared;
    if (lengthSquared == 0) return;
    final relative = position - points.$1;
    final t = ((relative.dx * line.dx + relative.dy * line.dy) / lengthSquared)
        .clamp(0.0, 1.0);
    final nearest = points.$1 + line * t;
    if ((position - nearest).distance <= 14) widget.onSelectMeasurement();
  }

  bool _tryEditWaypoint(Offset position, Size canvasSize) {
    final nearest = _findWaypointAt(position, canvasSize);
    if (nearest == null) return false;
    widget.onEditWaypoint(nearest);
    return true;
  }

  Offset? _findWaypointAt(Offset position, Size canvasSize) {
    Offset? nearest;
    var nearestDistance = 18.0;
    for (final waypoint in widget.laneWaypoints) {
      final distance =
          (_vertexToScreen(waypoint, canvasSize) - position).distance;
      if (distance <= nearestDistance) {
        nearest = waypoint;
        nearestDistance = distance;
      }
    }
    return nearest;
  }

  bool _trySelectLane(Offset position, Size canvasSize) {
    (Offset, Offset)? nearestLane;
    var nearestDistance = 12.0;
    for (final lane in widget.recommendedLanes) {
      final start = _vertexToScreen(lane.$1, canvasSize);
      final end = _vertexToScreen(lane.$2, canvasSize);
      final direction = end - start;
      if (direction.distanceSquared <= .01) continue;
      final relative = position - start;
      final t =
          ((relative.dx * direction.dx + relative.dy * direction.dy) /
                  direction.distanceSquared)
              .clamp(0.0, 1.0);
      final distance = (position - (start + direction * t)).distance;
      if (distance <= nearestDistance) {
        nearestLane = lane;
        nearestDistance = distance;
      }
    }
    if (nearestLane == null) return false;
    widget.onSelectLane(nearestLane);
    return true;
  }

  void _trySelectWallVertex(Offset position, Size canvasSize) {
    final fitted = applyBoxFit(
      BoxFit.contain,
      widget.sourceSize,
      canvasSize,
    ).destination;
    final target = Alignment.center.inscribe(fitted, Offset.zero & canvasSize);
    Offset convert(Offset point) => Offset(
      target.left + point.dx * target.width / widget.sourceSize.width,
      target.top + point.dy * target.height / widget.sourceSize.height,
    );
    Offset? nearest;
    var nearestDistance = 16.0;
    for (final vertex in widget.mapVertices) {
      final distance = (convert(vertex) - position).distance;
      if (distance < nearestDistance) {
        nearest = vertex;
        nearestDistance = distance;
      }
    }
    if (nearest != null) widget.onSelectWallVertex(nearest);
  }

  Rect _imageTarget(Size canvasSize) {
    final fitted = applyBoxFit(
      BoxFit.contain,
      widget.sourceSize,
      canvasSize,
    ).destination;
    return Alignment.center.inscribe(fitted, Offset.zero & canvasSize);
  }

  Offset _vertexToScreen(Offset point, Size canvasSize) {
    final target = _imageTarget(canvasSize);
    return Offset(
      target.left + point.dx * target.width / widget.sourceSize.width,
      target.top + point.dy * target.height / widget.sourceSize.height,
    );
  }

  Offset? _screenToImage(Offset position, Size canvasSize) {
    final target = _imageTarget(canvasSize);
    if (!target.contains(position)) return null;
    return Offset(
      (position.dx - target.left) * widget.sourceSize.width / target.width,
      (position.dy - target.top) * widget.sourceSize.height / target.height,
    );
  }

  Rect _floorBounds() {
    final points = widget.floorMask?.points;
    if (points == null || points.isEmpty) {
      return Offset.zero & widget.sourceSize;
    }
    var left = points.first.dx;
    var top = points.first.dy;
    var right = left;
    var bottom = top;
    for (final point in points.skip(1)) {
      left = math.min(left, point.dx);
      top = math.min(top, point.dy);
      right = math.max(right, point.dx);
      bottom = math.max(bottom, point.dy);
    }
    return Rect.fromLTRB(left, top, right, bottom);
  }

  Offset _imageToFloor(Offset point) {
    final bounds = _floorBounds();
    return Offset(point.dx - bounds.left, bounds.bottom - point.dy);
  }

  ({double left, double right, double top, double bottom}) _wallSpan(
    Offset point,
  ) {
    final floor = _floorBounds();
    var left = floor.left;
    var right = floor.right;
    var top = floor.top;
    var bottom = floor.bottom;
    for (final wall in widget.optimizedWalls) {
      final a = wall.$1;
      final b = wall.$2;
      final vertical = (a.dx - b.dx).abs() <= 2;
      final horizontal = (a.dy - b.dy).abs() <= 2;
      if (vertical &&
          point.dy >= math.min(a.dy, b.dy) - 2 &&
          point.dy <= math.max(a.dy, b.dy) + 2) {
        final x = (a.dx + b.dx) / 2;
        if (x <= point.dx && x > left) left = x;
        if (x >= point.dx && x < right) right = x;
      }
      if (horizontal &&
          point.dx >= math.min(a.dx, b.dx) - 2 &&
          point.dx <= math.max(a.dx, b.dx) + 2) {
        final y = (a.dy + b.dy) / 2;
        if (y <= point.dy && y > top) top = y;
        if (y >= point.dy && y < bottom) bottom = y;
      }
    }
    return (left: left, right: right, top: top, bottom: bottom);
  }

  void _addWaypointAt(Offset position, Size canvasSize) {
    final point = _screenToImage(position, canvasSize);
    if (point != null) widget.onAddWaypoint(point);
  }

  void _startEndpointMove(Offset position, Size canvasSize) {
    Offset? vertex;
    var distance = 16.0;
    for (final candidate in widget.mapVertices) {
      final candidateDistance =
          (_vertexToScreen(candidate, canvasSize) - position).distance;
      if (candidateDistance < distance) {
        vertex = candidate;
        distance = candidateDistance;
      }
    }
    if (vertex == null) return;
    final incident = widget.optimizedWalls
        .where(
          (wall) =>
              (wall.$1 - vertex!).distance <= .01 ||
              (wall.$2 - vertex).distance <= .01,
        )
        .toList();
    if (incident.length != 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('여러 Wall이 만나는 공유 정점은 이동할 수 없습니다.')),
      );
      return;
    }
    final wall = incident.single;
    setState(() {
      _movingWallVertex = vertex;
      _movingWallScreenPoint = _vertexToScreen(vertex!, canvasSize);
      _movingWallHorizontally = (wall.$1.dy - wall.$2.dy).abs() <= .01;
    });
  }

  void _updateEndpointMove(Offset position, Size canvasSize) {
    final original = _movingWallVertex;
    if (original == null) return;
    final start = _vertexToScreen(original, canvasSize);
    setState(() {
      _movingWallScreenPoint = _movingWallHorizontally
          ? Offset(position.dx, start.dy)
          : Offset(start.dx, position.dy);
    });
  }

  void _finishEndpointMove(Size canvasSize) {
    final original = _movingWallVertex;
    final screenPoint = _movingWallScreenPoint;
    if (original == null || screenPoint == null) return;
    final target = _imageTarget(canvasSize);
    final updated = Offset(
      ((screenPoint.dx - target.left) * widget.sourceSize.width / target.width)
          .clamp(0, widget.sourceSize.width),
      ((screenPoint.dy - target.top) * widget.sourceSize.height / target.height)
          .clamp(0, widget.sourceSize.height),
    );
    widget.onMoveWallEndpoint(original, updated);
    setState(() {
      _movingWallVertex = null;
      _movingWallScreenPoint = null;
    });
  }

  void _finishSelection(Size canvasSize) {
    final selection = _selection;
    final mask = widget.mask;
    if (selection == null || mask == null) return;
    final source = Size(mask.width.toDouble(), mask.height.toDouble());
    final fitted = applyBoxFit(BoxFit.contain, source, canvasSize).destination;
    final imageRect = Alignment.center.inscribe(
      fitted,
      Offset.zero & canvasSize,
    );
    final selectedImageArea = selection.intersect(imageRect);
    if (selectedImageArea.width < 3 || selectedImageArea.height < 3) {
      setState(() {
        _start = null;
        _current = null;
      });
      return;
    }

    final scale = source.width / imageRect.width;
    widget.onErase(
      Rect.fromLTRB(
        (selectedImageArea.left - imageRect.left) * scale,
        (selectedImageArea.top - imageRect.top) * scale,
        (selectedImageArea.right - imageRect.left) * scale,
        (selectedImageArea.bottom - imageRect.top) * scale,
      ),
    );
    setState(() {
      _start = null;
      _current = null;
    });
  }

  void _finishMeasurement(Size canvasSize) {
    final start = _start;
    final end = _current;
    if (start == null || end == null || (end - start).distance < 8) return;
    final source = widget.sourceSize;
    final fitted = applyBoxFit(BoxFit.contain, source, canvasSize).destination;
    final imageRect = Alignment.center.inscribe(
      fitted,
      Offset.zero & canvasSize,
    );
    Offset toImage(Offset point) => Offset(
      ((point.dx - imageRect.left) * source.width / imageRect.width).clamp(
        0,
        source.width,
      ),
      ((point.dy - imageRect.top) * source.height / imageRect.height).clamp(
        0,
        source.height,
      ),
    );
    widget.onMeasurementSelected(toImage(start), toImage(end));
    setState(() {
      _start = null;
      _current = null;
    });
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final size = Size(constraints.maxWidth, constraints.maxHeight);
      return Stack(
        fit: StackFit.expand,
        children: [
          Image.memory(
            widget.bytes,
            fit: BoxFit.contain,
            gaplessPlayback: true,
          ),
          if (widget.floorMask != null)
            IgnorePointer(
              child: CustomPaint(
                painter: _WallOverlayPainter(
                  mask: widget.floorMask!,
                  color: widget.floorColor,
                  opacity: .28,
                ),
              ),
            ),
          if (widget.optimizedWalls.isNotEmpty)
            IgnorePointer(
              child: CustomPaint(
                painter: _VectorWallPainter(
                  walls: widget.optimizedWalls,
                  sourceSize: widget.sourceSize,
                  color: widget.color,
                ),
              ),
            ),
          if (widget.measurement != null)
            IgnorePointer(
              child: CustomPaint(
                painter: _MeasurementPainter(
                  measurement: widget.measurement!,
                  sourceSize: widget.sourceSize,
                  selected: widget.measurementSelected,
                ),
              ),
            ),
          if (widget.laneWaypoints.isNotEmpty)
            IgnorePointer(
              child: CustomPaint(
                painter: _LanePainter(
                  lanes: widget.recommendedLanes,
                  directions: widget.laneDirections,
                  waypoints: widget.laneWaypoints,
                  waypointNames: widget.waypointNames,
                  activeEndpoint: widget.activeLaneEndpoint,
                  sourceSize: widget.sourceSize,
                ),
              ),
            ),
          if (widget.mapVertices.isNotEmpty)
            IgnorePointer(
              child: CustomPaint(
                key: ValueKey(widget.vertexLabelRevision),
                painter: _VertexLabelPainter(
                  vertices: widget.mapVertices,
                  sourceSize: widget.sourceSize,
                  revision: widget.vertexLabelRevision,
                ),
              ),
            ),
          if (widget.waypointMode)
            MouseRegion(
              cursor: SystemMouseCursors.precise,
              onHover: (event) => setState(() {
                _waypointCursor =
                    _screenToImage(event.localPosition, size) == null
                    ? null
                    : event.localPosition;
              }),
              onExit: (_) => setState(() => _waypointCursor = null),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapUp: (details) =>
                    _addWaypointAt(details.localPosition, size),
              ),
            ),
          if (widget.waypointMode && _waypointCursor != null)
            IgnorePointer(
              child: CustomPaint(
                painter: _WaypointWallDistancePainter(
                  point: _screenToImage(_waypointCursor!, size)!,
                  span: _wallSpan(_screenToImage(_waypointCursor!, size)!),
                  sourceSize: widget.sourceSize,
                  waypoints: widget.laneWaypoints,
                ),
              ),
            ),
          if (widget.waypointMode && _waypointCursor != null)
            Positioned(
              left: _waypointCursor!.dx + 250 <= size.width
                  ? _waypointCursor!.dx + 18
                  : math.max(0, _waypointCursor!.dx - 242),
              top: _waypointCursor!.dy + 126 <= size.height
                  ? _waypointCursor!.dy + 18
                  : math.max(0, _waypointCursor!.dy - 118),
              child: IgnorePointer(
                child: _WaypointCoordinateBadge(
                  point: _imageToFloor(_screenToImage(_waypointCursor!, size)!),
                  imagePoint: _screenToImage(_waypointCursor!, size)!,
                  span: _wallSpan(_screenToImage(_waypointCursor!, size)!),
                ),
              ),
            ),
          if (widget.wallConnectMode)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapUp: (details) =>
                  _trySelectWallVertex(details.localPosition, size),
              child: CustomPaint(
                painter: _PendingVertexPainter(
                  vertex: widget.pendingWallVertex,
                  sourceSize: widget.sourceSize,
                ),
              ),
            ),
          if (widget.wallEndpointEditMode)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onPanStart: (details) =>
                  _startEndpointMove(details.localPosition, size),
              onPanUpdate: (details) =>
                  _updateEndpointMove(details.localPosition, size),
              onPanEnd: (_) => _finishEndpointMove(size),
              child: CustomPaint(
                painter: _EndpointMovePainter(
                  original: _movingWallVertex == null
                      ? null
                      : _vertexToScreen(_movingWallVertex!, size),
                  current: _movingWallScreenPoint,
                ),
              ),
            ),
          if (!widget.measurementMode &&
              !widget.eraseMode &&
              !widget.waypointMode &&
              !widget.wallConnectMode &&
              !widget.wallEndpointEditMode)
            MouseRegion(
              cursor: _hoveredWaypoint == null
                  ? MouseCursor.defer
                  : SystemMouseCursors.click,
              onHover: (event) {
                final waypoint = _findWaypointAt(event.localPosition, size);
                if (waypoint != _hoveredWaypoint ||
                    event.localPosition != _waypointHoverPosition) {
                  setState(() {
                    _hoveredWaypoint = waypoint;
                    _waypointHoverPosition = waypoint == null
                        ? null
                        : event.localPosition;
                  });
                }
              },
              onExit: (_) => setState(() {
                _hoveredWaypoint = null;
                _waypointHoverPosition = null;
              }),
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTapUp: (details) {
                  if (_tryEditWaypoint(details.localPosition, size)) return;
                  if (_trySelectLane(details.localPosition, size)) return;
                  if (widget.measurement != null) {
                    _trySelectMeasurement(details.localPosition, size);
                  }
                },
              ),
            ),
          if (!widget.waypointMode &&
              _hoveredWaypoint != null &&
              _waypointHoverPosition != null)
            Positioned(
              left: _waypointHoverPosition!.dx + 210 <= size.width
                  ? _waypointHoverPosition!.dx + 16
                  : math.max(0, _waypointHoverPosition!.dx - 202),
              top: _waypointHoverPosition!.dy + 82 <= size.height
                  ? _waypointHoverPosition!.dy + 16
                  : math.max(0, _waypointHoverPosition!.dy - 76),
              child: IgnorePointer(
                child: _WaypointHoverBadge(
                  name: widget.waypointNames[_hoveredWaypoint!] ?? '',
                  category: widget.waypointTypes[_hoveredWaypoint!] ?? '일반',
                ),
              ),
            ),
          if ((widget.eraseMode && widget.mask != null) ||
              widget.measurementMode)
            MouseRegion(
              cursor: SystemMouseCursors.precise,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanStart: (details) => setState(() {
                  _start = details.localPosition;
                  _current = details.localPosition;
                }),
                onPanUpdate: (details) => setState(() {
                  final position = details.localPosition;
                  final start = _start;
                  if (widget.measurementMode && start != null) {
                    final delta = position - start;
                    _current = delta.dx.abs() >= delta.dy.abs()
                        ? Offset(position.dx, start.dy)
                        : Offset(start.dx, position.dy);
                  } else {
                    _current = position;
                  }
                }),
                onPanEnd: (_) => widget.measurementMode
                    ? _finishMeasurement(size)
                    : _finishSelection(size),
                onPanCancel: () => setState(() {
                  _start = null;
                  _current = null;
                }),
                child: CustomPaint(
                  painter: widget.measurementMode
                      ? _MeasurementDraftPainter(start: _start, end: _current)
                      : _WallSelectionPainter(selection: _selection),
                ),
              ),
            ),
          if (widget.measurementMode)
            Positioned(
              top: _measurementBadgeOffset.dy.clamp(
                0,
                math.max(0, size.height - 44),
              ),
              left: _measurementBadgeOffset.dx.clamp(
                0,
                math.max(0, size.width - 360),
              ),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanUpdate: (details) => setState(() {
                  _measurementBadgeOffset = Offset(
                    (_measurementBadgeOffset.dx + details.delta.dx).clamp(
                      0,
                      math.max(0, size.width - 360),
                    ),
                    (_measurementBadgeOffset.dy + details.delta.dy).clamp(
                      0,
                      math.max(0, size.height - 44),
                    ),
                  );
                }),
                child: _MeasurementModeBadge(
                  onClose: widget.onCloseMeasurementMode,
                ),
              ),
            ),
          if (widget.eraseMode)
            const Positioned(
              top: 12,
              left: 12,
              child: IgnorePointer(child: _EraseModeBadge()),
            ),
        ],
      );
    },
  );
}

class _EraseModeBadge extends StatelessWidget {
  const _EraseModeBadge();

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: const Color(0xEFFFFFFF),
      borderRadius: BorderRadius.circular(8),
      boxShadow: const [BoxShadow(color: Color(0x18000000), blurRadius: 8)],
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.select_all, size: 16, color: Color(0xFFEF4444)),
          SizedBox(width: 6),
          Text(
            '지울 글자 영역을 드래그하세요',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: Color(0xFF334155),
            ),
          ),
        ],
      ),
    ),
  );
}

class _WaypointCoordinateBadge extends StatelessWidget {
  const _WaypointCoordinateBadge({
    required this.point,
    required this.imagePoint,
    required this.span,
  });

  final Offset point;
  final Offset imagePoint;
  final ({double left, double right, double top, double bottom}) span;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: const Color(0xEFFFFFFF),
      borderRadius: BorderRadius.circular(7),
      border: Border.all(color: const Color(0xFFCBD5E1)),
      boxShadow: const [BoxShadow(color: Color(0x18000000), blurRadius: 8)],
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'X ${point.dx.toStringAsFixed(1)}  ·  Y ${point.dy.toStringAsFixed(1)}',
            style: const TextStyle(
              color: Color(0xFF0F172A),
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '← 왼쪽 ${(imagePoint.dx - span.left).toStringAsFixed(1)}   오른쪽 ${(span.right - imagePoint.dx).toStringAsFixed(1)} →',
            style: const TextStyle(
              color: Color(0xFF9A3412),
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            '↑ 위 ${(imagePoint.dy - span.top).toStringAsFixed(1)}   아래 ${(span.bottom - imagePoint.dy).toStringAsFixed(1)} ↓',
            style: const TextStyle(
              color: Color(0xFF9A3412),
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    ),
  );
}

class _WaypointHoverBadge extends StatelessWidget {
  const _WaypointHoverBadge({required this.name, required this.category});

  final String name;
  final String category;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: const Color(0xF7FFFFFF),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: const Color(0xFFCBD5E1)),
      boxShadow: const [BoxShadow(color: Color(0x22000000), blurRadius: 10)],
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            name.trim().isEmpty ? '(이름 없음)' : name,
            style: const TextStyle(
              color: Color(0xFF0F172A),
              fontSize: 13,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '카테고리 · $category',
            style: const TextStyle(
              color: Color(0xFF64748B),
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    ),
  );
}

class _WaypointWallDistancePainter extends CustomPainter {
  const _WaypointWallDistancePainter({
    required this.point,
    required this.span,
    required this.sourceSize,
    required this.waypoints,
  });

  final Offset point;
  final ({double left, double right, double top, double bottom}) span;
  final Size sourceSize;
  final List<Offset> waypoints;

  @override
  void paint(Canvas canvas, Size size) {
    final fitted = applyBoxFit(BoxFit.contain, sourceSize, size).destination;
    final target = Alignment.center.inscribe(fitted, Offset.zero & size);
    Offset convert(Offset value) => Offset(
      target.left + value.dx * target.width / sourceSize.width,
      target.top + value.dy * target.height / sourceSize.height,
    );

    final center = convert(point);
    final left = convert(Offset(span.left, point.dy));
    final right = convert(Offset(span.right, point.dy));
    final top = convert(Offset(point.dx, span.top));
    final bottom = convert(Offset(point.dx, span.bottom));
    final paint = Paint()
      ..color = const Color(0xFFEA580C)
      ..strokeWidth = 1.6
      ..style = PaintingStyle.stroke;

    void arrow(Offset start, Offset end) {
      canvas.drawLine(start, end, paint);
      final direction = (end - start) / (end - start).distance;
      final normal = Offset(-direction.dy, direction.dx);
      const head = 7.0;
      const wing = 4.0;
      canvas.drawLine(start, start + direction * head + normal * wing, paint);
      canvas.drawLine(start, start + direction * head - normal * wing, paint);
      canvas.drawLine(end, end - direction * head + normal * wing, paint);
      canvas.drawLine(end, end - direction * head - normal * wing, paint);
    }

    void label(String text, Offset position) {
      final painter = TextPainter(
        text: TextSpan(
          text: text,
          style: const TextStyle(
            color: Color(0xFF9A3412),
            fontSize: 11,
            fontWeight: FontWeight.w800,
            backgroundColor: Color(0xEFFFFFFF),
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      painter.paint(
        canvas,
        position - Offset(painter.width / 2, painter.height / 2),
      );
    }

    final sourceTolerance = 10 * sourceSize.width / target.width;
    final horizontalCrossings = waypoints
        .where(
          (waypoint) =>
              (waypoint.dy - point.dy).abs() <= sourceTolerance &&
              waypoint.dx > span.left &&
              waypoint.dx < span.right,
        )
        .toList();
    final verticalCrossings = waypoints
        .where(
          (waypoint) =>
              (waypoint.dx - point.dx).abs() <= sourceTolerance &&
              waypoint.dy > span.top &&
              waypoint.dy < span.bottom,
        )
        .toList();

    if (horizontalCrossings.isEmpty) {
      if ((center - left).distance > 14) {
        arrow(left, center);
        label(
          '좌 ${(point.dx - span.left).toStringAsFixed(1)}',
          Offset((left.dx + center.dx) / 2, center.dy - 12),
        );
      }
      if ((right - center).distance > 14) {
        arrow(center, right);
        label(
          '우 ${(span.right - point.dx).toStringAsFixed(1)}',
          Offset((center.dx + right.dx) / 2, center.dy - 12),
        );
      }
    } else {
      final stops = <double>[
        span.left,
        point.dx,
        ...horizontalCrossings.map((waypoint) => waypoint.dx),
        span.right,
      ]..sort();
      for (var i = 0; i < stops.length - 1; i++) {
        final start = Offset(stops[i], point.dy);
        final end = Offset(stops[i + 1], point.dy);
        final screenStart = convert(start);
        final screenEnd = convert(end);
        if ((screenEnd - screenStart).distance <= 14) continue;
        arrow(screenStart, screenEnd);
        label(
          '길이 ${(stops[i + 1] - stops[i]).toStringAsFixed(1)}',
          Offset((screenStart.dx + screenEnd.dx) / 2, center.dy - 12),
        );
      }
    }

    if (verticalCrossings.isEmpty) {
      if ((center - top).distance > 14) {
        arrow(top, center);
        label(
          '위 ${(point.dy - span.top).toStringAsFixed(1)}',
          Offset(center.dx + 30, (top.dy + center.dy) / 2),
        );
      }
      if ((bottom - center).distance > 14) {
        arrow(center, bottom);
        label(
          '아래 ${(span.bottom - point.dy).toStringAsFixed(1)}',
          Offset(center.dx + 34, (center.dy + bottom.dy) / 2),
        );
      }
    } else {
      final stops = <double>[
        span.top,
        point.dy,
        ...verticalCrossings.map((waypoint) => waypoint.dy),
        span.bottom,
      ]..sort();
      for (var i = 0; i < stops.length - 1; i++) {
        final start = Offset(point.dx, stops[i]);
        final end = Offset(point.dx, stops[i + 1]);
        final screenStart = convert(start);
        final screenEnd = convert(end);
        if ((screenEnd - screenStart).distance <= 14) continue;
        arrow(screenStart, screenEnd);
        label(
          '길이 ${(stops[i + 1] - stops[i]).toStringAsFixed(1)}',
          Offset(center.dx + 38, (screenStart.dy + screenEnd.dy) / 2),
        );
      }
    }
    for (final waypoint in {...horizontalCrossings, ...verticalCrossings}) {
      final screenPoint = convert(waypoint);
      canvas.drawCircle(
        screenPoint,
        5,
        Paint()..color = const Color(0xFF2563EB),
      );
      canvas.drawCircle(
        screenPoint,
        7,
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }
    canvas.drawCircle(center, 3, Paint()..color = const Color(0xFFEA580C));
  }

  @override
  bool shouldRepaint(covariant _WaypointWallDistancePainter oldDelegate) =>
      oldDelegate.point != point ||
      oldDelegate.span != span ||
      oldDelegate.sourceSize != sourceSize ||
      oldDelegate.waypoints != waypoints;
}

class _MeasurementModeBadge extends StatelessWidget {
  const _MeasurementModeBadge({required this.onClose});
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: const Color(0xEFFFFFFF),
      borderRadius: BorderRadius.circular(8),
      boxShadow: const [BoxShadow(color: Color(0x18000000), blurRadius: 8)],
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.drag_indicator, size: 17, color: Color(0xFF94A3B8)),
          SizedBox(width: 4),
          Icon(Icons.straighten, size: 16, color: Color(0xFF2563EB)),
          SizedBox(width: 6),
          const Text(
            '실제 길이를 아는 가로/세로 라인을 드래그하세요',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: Color(0xFF334155),
            ),
          ),
          const SizedBox(width: 8),
          const Text(
            '이동 가능',
            style: TextStyle(fontSize: 10, color: Color(0xFF94A3B8)),
          ),
          const SizedBox(width: 5),
          InkWell(
            onTap: onClose,
            customBorder: const CircleBorder(),
            child: const Padding(
              padding: EdgeInsets.all(3),
              child: Icon(Icons.close, size: 16, color: Color(0xFF64748B)),
            ),
          ),
        ],
      ),
    ),
  );
}

class _MeasurementDraftPainter extends CustomPainter {
  const _MeasurementDraftPainter({required this.start, required this.end});
  final Offset? start;
  final Offset? end;

  @override
  void paint(Canvas canvas, Size size) {
    if (start == null || end == null) return;
    final paint = Paint()
      ..color = const Color(0xFF2563EB)
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(start!, end!, paint);
    canvas.drawCircle(start!, 5, Paint()..color = Colors.white);
    canvas.drawCircle(start!, 5, paint..style = PaintingStyle.stroke);
    canvas.drawCircle(end!, 5, Paint()..color = Colors.white);
    canvas.drawCircle(end!, 5, paint);
  }

  @override
  bool shouldRepaint(covariant _MeasurementDraftPainter oldDelegate) =>
      oldDelegate.start != start || oldDelegate.end != end;
}

class _MeasurementPainter extends CustomPainter {
  const _MeasurementPainter({
    required this.measurement,
    required this.sourceSize,
    required this.selected,
  });
  final _MapMeasurement measurement;
  final Size sourceSize;
  final bool selected;

  @override
  void paint(Canvas canvas, Size size) {
    final fitted = applyBoxFit(BoxFit.contain, sourceSize, size).destination;
    final target = Alignment.center.inscribe(fitted, Offset.zero & size);
    Offset convert(Offset point) => Offset(
      target.left + point.dx * target.width / sourceSize.width,
      target.top + point.dy * target.height / sourceSize.height,
    );
    final start = convert(measurement.start);
    final end = convert(measurement.end);
    final paint = Paint()
      ..color = selected ? const Color(0xFFEF4444) : const Color(0xFF0EA5E9)
      ..strokeWidth = selected ? 4 : 3
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(start, end, paint);
    canvas.drawCircle(start, 5, Paint()..color = Colors.white);
    canvas.drawCircle(start, 5, paint..style = PaintingStyle.stroke);
    canvas.drawCircle(end, 5, Paint()..color = Colors.white);
    canvas.drawCircle(end, 5, paint);

    final label = TextPainter(
      text: TextSpan(
        text: '${measurement.length} ${measurement.unit}',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final center = Offset((start.dx + end.dx) / 2, (start.dy + end.dy) / 2);
    final labelRect = Rect.fromCenter(
      center: center,
      width: label.width + 16,
      height: label.height + 10,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(labelRect, const Radius.circular(6)),
      Paint()
        ..color = selected ? const Color(0xFFDC2626) : const Color(0xFF0284C7),
    );
    label.paint(canvas, Offset(labelRect.left + 8, labelRect.top + 5));
  }

  @override
  bool shouldRepaint(covariant _MeasurementPainter oldDelegate) =>
      oldDelegate.measurement != measurement ||
      oldDelegate.sourceSize != sourceSize ||
      oldDelegate.selected != selected;
}

class _LanePainter extends CustomPainter {
  const _LanePainter({
    required this.lanes,
    required this.directions,
    required this.waypoints,
    required this.waypointNames,
    required this.activeEndpoint,
    required this.sourceSize,
  });

  final List<(Offset, Offset)> lanes;
  final Map<(Offset, Offset), String> directions;
  final List<Offset> waypoints;
  final Map<Offset, String> waypointNames;
  final Offset? activeEndpoint;
  final Size sourceSize;

  @override
  void paint(Canvas canvas, Size size) {
    final fitted = applyBoxFit(BoxFit.contain, sourceSize, size).destination;
    final target = Alignment.center.inscribe(fitted, Offset.zero & size);
    Offset convert(Offset point) => Offset(
      target.left + point.dx * target.width / sourceSize.width,
      target.top + point.dy * target.height / sourceSize.height,
    );
    final paint = Paint()
      ..color = const Color(0xFF06B6D4)
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    void drawArrow(Offset from, Offset to, double fraction) {
      final direction = to - from;
      if (direction.distance <= 1) return;
      final unit = direction / direction.distance;
      final normal = Offset(-unit.dy, unit.dx);
      const arrowLength = 9.0;
      const arrowWidth = 5.0;
      final tip = Offset.lerp(from, to, fraction)!;
      final base = tip - unit * arrowLength;
      final path = Path()
        ..moveTo(tip.dx, tip.dy)
        ..lineTo(
          (base + normal * arrowWidth).dx,
          (base + normal * arrowWidth).dy,
        )
        ..lineTo(
          (base - normal * arrowWidth).dx,
          (base - normal * arrowWidth).dy,
        )
        ..close();
      canvas.drawPath(path, paint);
    }

    for (final lane in lanes) {
      final start = convert(lane.$1);
      final end = convert(lane.$2);
      canvas.drawLine(start, end, paint);
      final laneDirection = directions[lane] ?? '양방향';
      if (laneDirection == '정방향') {
        drawArrow(start, end, .62);
      } else if (laneDirection == '역방향') {
        drawArrow(end, start, .62);
      } else {
        drawArrow(start, end, .38);
        drawArrow(end, start, .38);
      }
    }
    for (var i = 0; i < waypoints.length; i++) {
      final point = convert(waypoints[i]);
      canvas.drawCircle(point, 12, Paint()..color = const Color(0xFFFFFFFF));
      canvas.drawCircle(point, 10, paint);
    }
    final waypointObstacles = [
      for (final waypoint in waypoints)
        Rect.fromCircle(center: convert(waypoint), radius: 14),
    ];
    final occupiedLabels = <Rect>[];
    for (final waypoint in waypoints) {
      final name = (waypointNames[waypoint] ?? '').trim();
      if (name.isEmpty) continue;
      final center = convert(waypoint);
      final label = TextPainter(
        text: TextSpan(
          text: name,
          style: const TextStyle(
            color: Color(0xFF0F172A),
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
        ellipsis: '…',
      )..layout(maxWidth: 160);
      final labelSize = Size(label.width + 12, label.height + 6);
      final candidates = <Rect>[
        Rect.fromLTWH(
          center.dx + 16,
          center.dy - labelSize.height / 2,
          labelSize.width,
          labelSize.height,
        ),
        Rect.fromLTWH(
          center.dx - 16 - labelSize.width,
          center.dy - labelSize.height / 2,
          labelSize.width,
          labelSize.height,
        ),
        Rect.fromLTWH(
          center.dx - labelSize.width / 2,
          center.dy - 16 - labelSize.height,
          labelSize.width,
          labelSize.height,
        ),
        Rect.fromLTWH(
          center.dx - labelSize.width / 2,
          center.dy + 16,
          labelSize.width,
          labelSize.height,
        ),
      ];
      final canvasBounds = Offset.zero & size;
      bool isAvailable(Rect candidate) =>
          canvasBounds.contains(candidate.topLeft) &&
          canvasBounds.contains(candidate.bottomRight) &&
          !occupiedLabels.any((rect) => rect.inflate(3).overlaps(candidate)) &&
          !waypointObstacles.any((rect) => rect.overlaps(candidate));
      final labelRect = candidates.firstWhere(
        isAvailable,
        orElse: () => candidates.reduce((best, candidate) {
          int overlapCount(Rect rect) =>
              occupiedLabels.where((used) => used.overlaps(rect)).length +
              waypointObstacles.where((point) => point.overlaps(rect)).length;
          return overlapCount(candidate) < overlapCount(best)
              ? candidate
              : best;
        }),
      );
      occupiedLabels.add(labelRect);
      canvas.drawRRect(
        RRect.fromRectAndRadius(labelRect, const Radius.circular(5)),
        Paint()..color = const Color(0xEFFFFFFF),
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(labelRect, const Radius.circular(5)),
        Paint()
          ..color = const Color(0x330F172A)
          ..style = PaintingStyle.stroke,
      );
      label.paint(canvas, Offset(labelRect.left + 6, labelRect.top + 3));
    }
    if (activeEndpoint != null) {
      final point = convert(activeEndpoint!);
      canvas.drawCircle(
        point,
        17,
        Paint()
          ..color = const Color(0xFFF59E0B)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4,
      );
      canvas.drawCircle(
        point,
        13,
        Paint()
          ..color = const Color(0x66FDE68A)
          ..style = PaintingStyle.fill,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _LanePainter oldDelegate) =>
      oldDelegate.lanes != lanes ||
      oldDelegate.directions != directions ||
      oldDelegate.waypoints != waypoints ||
      oldDelegate.waypointNames != waypointNames ||
      oldDelegate.activeEndpoint != activeEndpoint ||
      oldDelegate.sourceSize != sourceSize;
}

class _VertexLabelPainter extends CustomPainter {
  const _VertexLabelPainter({
    required this.vertices,
    required this.sourceSize,
    required this.revision,
  });

  final List<Offset> vertices;
  final Size sourceSize;
  final int revision;

  @override
  void paint(Canvas canvas, Size size) {
    final fitted = applyBoxFit(BoxFit.contain, sourceSize, size).destination;
    final target = Alignment.center.inscribe(fitted, Offset.zero & size);
    Offset convert(Offset point) => Offset(
      target.left + point.dx * target.width / sourceSize.width,
      target.top + point.dy * target.height / sourceSize.height,
    );

    for (var i = 0; i < vertices.length; i++) {
      final center = convert(vertices[i]);
      canvas.drawCircle(center, 7, Paint()..color = const Color(0xEFFFFFFF));
      canvas.drawCircle(
        center,
        7,
        Paint()
          ..color = const Color(0xFF0F172A)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
      final label = TextPainter(
        text: TextSpan(
          text: '$i',
          style: const TextStyle(
            color: Color(0xFF0F172A),
            fontSize: 8,
            fontWeight: FontWeight.w800,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      label.paint(canvas, center - Offset(label.width / 2, label.height / 2));
    }
  }

  @override
  bool shouldRepaint(covariant _VertexLabelPainter oldDelegate) =>
      oldDelegate.revision != revision ||
      oldDelegate.vertices != vertices ||
      oldDelegate.sourceSize != sourceSize;
}

class _PendingVertexPainter extends CustomPainter {
  const _PendingVertexPainter({required this.vertex, required this.sourceSize});
  final Offset? vertex;
  final Size sourceSize;

  @override
  void paint(Canvas canvas, Size size) {
    final point = vertex;
    if (point == null) return;
    final fitted = applyBoxFit(BoxFit.contain, sourceSize, size).destination;
    final target = Alignment.center.inscribe(fitted, Offset.zero & size);
    final center = Offset(
      target.left + point.dx * target.width / sourceSize.width,
      target.top + point.dy * target.height / sourceSize.height,
    );
    canvas.drawCircle(
      center,
      11,
      Paint()
        ..color = const Color(0xFFEF4444)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
  }

  @override
  bool shouldRepaint(covariant _PendingVertexPainter oldDelegate) =>
      oldDelegate.vertex != vertex || oldDelegate.sourceSize != sourceSize;
}

class _EndpointMovePainter extends CustomPainter {
  const _EndpointMovePainter({required this.original, required this.current});
  final Offset? original;
  final Offset? current;

  @override
  void paint(Canvas canvas, Size size) {
    if (original == null || current == null) return;
    canvas.drawLine(
      original!,
      current!,
      Paint()
        ..color = const Color(0xFFEF4444)
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawCircle(
      current!,
      9,
      Paint()
        ..color = const Color(0xFFEF4444)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
  }

  @override
  bool shouldRepaint(covariant _EndpointMovePainter oldDelegate) =>
      oldDelegate.original != original || oldDelegate.current != current;
}

class _WallSelectionPainter extends CustomPainter {
  const _WallSelectionPainter({required this.selection});
  final Rect? selection;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = selection;
    if (rect == null) return;
    canvas.drawRect(rect, Paint()..color = const Color(0x33EF4444));
    canvas.drawRect(
      rect,
      Paint()
        ..color = const Color(0xFFEF4444)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(covariant _WallSelectionPainter oldDelegate) =>
      oldDelegate.selection != selection;
}

class _NonImagePreview extends StatelessWidget {
  const _NonImagePreview({required this.extension});
  final String extension;
  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          extension == 'pdf'
              ? Icons.picture_as_pdf_outlined
              : Icons.architecture_outlined,
          size: 62,
          color: const Color(0xFF64748B),
        ),
        const SizedBox(height: 16),
        Text(
          '${extension.toUpperCase()} 도면을 불러왔습니다',
          style: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: Color(0xFF334155),
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          '서버 변환이 연결되면 이 영역에 도면 미리보기가 표시됩니다.',
          style: TextStyle(color: Color(0xFF64748B)),
        ),
      ],
    ),
  );
}

class _SetupPanel extends StatelessWidget {
  const _SetupPanel({
    required this.drawing,
    required this.stage,
    required this.measurement,
    required this.isMeasurementMode,
    required this.onToggleMeasurement,
    required this.wallColor,
    required this.floorColor,
    required this.wallsDetected,
    required this.floorGenerated,
    required this.isDetectingWalls,
    required this.isGeneratingFloor,
    required this.onDetectWalls,
    required this.onGenerateFloor,
    required this.lanesGenerated,
    required this.waypointMode,
    required this.onToggleWaypoint,
    required this.onWallColorChanged,
    required this.onFloorColorChanged,
    required this.isDeployed,
    required this.onDeploy,
    required this.onStageChanged,
  });
  final UploadedDrawing? drawing;
  final MapStage stage;
  final _MapMeasurement? measurement;
  final bool isMeasurementMode;
  final VoidCallback onToggleMeasurement;
  final Color wallColor;
  final Color floorColor;
  final bool wallsDetected;
  final bool floorGenerated;
  final bool isDetectingWalls;
  final bool isGeneratingFloor;
  final VoidCallback onDetectWalls;
  final VoidCallback onGenerateFloor;
  final bool lanesGenerated;
  final bool waypointMode;
  final VoidCallback onToggleWaypoint;
  final ValueChanged<Color> onWallColorChanged;
  final ValueChanged<Color> onFloorColorChanged;
  final bool isDeployed;
  final VoidCallback onDeploy;
  final ValueChanged<MapStage> onStageChanged;
  @override
  Widget build(BuildContext context) {
    final enabled = drawing != null;
    final calibrated = measurement != null;
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '맵 생성 설정',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              color: Color(0xFF1E293B),
            ),
          ),
          const SizedBox(height: 7),
          const Text(
            '도면 분석 후 필요한 항목을 확인하세요.',
            style: TextStyle(fontSize: 13, color: Color(0xFF64748B)),
          ),
          const SizedBox(height: 22),
          _InfoField(
            label: '맵 이름',
            value: drawing == null
                ? '도면을 먼저 올려주세요'
                : drawing!.name.split('.').first,
            enabled: enabled,
          ),
          const SizedBox(height: 17),
          const Text(
            '자동 생성 항목',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: Color(0xFF64748B),
            ),
          ),
          const SizedBox(height: 10),
          _SettingTile(
            icon: Icons.straighten_outlined,
            title: isMeasurementMode ? '라인을 선택해주세요' : 'Measurement',
            subtitle: measurement == null
                ? '가로 또는 세로의 실제 길이 설정'
                : '${measurement!.length} ${measurement!.unit} 기준 저장됨',
            enabled: enabled,
            checked: measurement != null,
            onTap: onToggleMeasurement,
          ),
          _SettingTile(
            icon: Icons.polyline_outlined,
            title: isDetectingWalls
                ? '벽을 인식하는 중...'
                : wallsDetected
                ? '벽 자동인식 제거하기'
                : '벽 자동 인식',
            subtitle: isDetectingWalls
                ? '이미지 픽셀을 분석하고 있습니다'
                : wallsDetected
                ? '누르면 인식된 벽을 모두 제거합니다'
                : '도면의 외곽선과 장애물 추출',
            enabled: enabled && calibrated,
            checked: wallsDetected,
            onTap: onDetectWalls,
          ),
          AnimatedOpacity(
            duration: const Duration(milliseconds: 180),
            opacity: enabled && calibrated ? 1 : .45,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(47, 0, 0, 10),
              child: Row(
                children: [
                  const Text(
                    '벽 색상',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF64748B),
                    ),
                  ),
                  const Spacer(),
                  for (final color in const [
                    Color(0xFF2563EB),
                    Color(0xFFEF4444),
                    Color(0xFFF97316),
                    Color(0xFF16A34A),
                    Color(0xFF9333EA),
                  ])
                    _WallColorButton(
                      color: color,
                      selected: wallColor == color,
                      onTap: enabled && calibrated
                          ? () => onWallColorChanged(color)
                          : null,
                    ),
                ],
              ),
            ),
          ),
          _SettingTile(
            icon: Icons.layers_outlined,
            title: isGeneratingFloor ? 'Floor를 생성하는 중...' : 'Floor 자동 생성',
            subtitle: isGeneratingFloor ? '주행 가능 영역을 분석하고 있습니다' : '주행 가능 영역 생성',
            enabled: enabled && calibrated,
            checked: floorGenerated,
            onTap: onGenerateFloor,
          ),
          AnimatedOpacity(
            duration: const Duration(milliseconds: 180),
            opacity: enabled && calibrated ? 1 : .45,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(47, 0, 0, 10),
              child: Row(
                children: [
                  const Text(
                    'Floor 색상',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF64748B),
                    ),
                  ),
                  const Spacer(),
                  for (final color in const [
                    Color(0xFF22C55E),
                    Color(0xFF38BDF8),
                    Color(0xFFFACC15),
                    Color(0xFFF97316),
                    Color(0xFFA855F7),
                  ])
                    _WallColorButton(
                      color: color,
                      selected: floorColor == color,
                      onTap: enabled && calibrated
                          ? () => onFloorColorChanged(color)
                          : null,
                    ),
                ],
              ),
            ),
          ),
          _SettingTile(
            icon: Icons.route_outlined,
            title: waypointMode ? 'Waypoint 입력 완료' : 'Waypoint 입력',
            subtitle: waypointMode ? '도면을 눌러 경로점을 추가하세요' : '경로점을 순서대로 직접 지정',
            enabled: enabled && floorGenerated,
            checked: lanesGenerated,
            onTap: onToggleWaypoint,
          ),
          _SettingTile(
            icon: Icons.pin_drop_outlined,
            title: '로봇·작업 위치',
            subtitle: 'Pinky와 OMX 위치 지정',
            enabled: enabled,
            checked: stage.index >= MapStage.stations.index,
            onTap: () => onStageChanged(MapStage.stations),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: enabled ? onDeploy : null,
              icon: Icon(
                isDeployed ? Icons.check_circle : Icons.rocket_launch_outlined,
                size: 18,
              ),
              label: Text(isDeployed ? '배포 완료' : '배포 준비 완료'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(9),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.lock_outline, size: 13, color: Color(0xFF94A3B8)),
              SizedBox(width: 5),
              Text(
                '원본 파일은 안전하게 보관됩니다',
                style: TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _InfoField extends StatelessWidget {
  const _InfoField({
    required this.label,
    required this.value,
    required this.enabled,
  });
  final String label;
  final String value;
  final bool enabled;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: Color(0xFF64748B),
        ),
      ),
      const SizedBox(height: 7),
      Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 13),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 13,
            color: enabled ? const Color(0xFF334155) : const Color(0xFF94A3B8),
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    ],
  );
}

class _WallColorButton extends StatelessWidget {
  const _WallColorButton({
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final Color color;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(left: 4),
    child: Tooltip(
      message: '벽 오버레이 색상',
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 22,
          height: 22,
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: selected ? color : Colors.transparent,
              width: 2,
            ),
          ),
          child: DecoratedBox(
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            child: selected
                ? const Icon(Icons.check, size: 12, color: Colors.white)
                : null,
          ),
        ),
      ),
    ),
  );
}

class _WallMask {
  const _WallMask({
    required this.width,
    required this.height,
    required this.sampleSize,
    required this.points,
  });

  final int width;
  final int height;
  final double sampleSize;
  final List<Offset> points;
}

class _AxisWall {
  _AxisWall({
    required this.horizontal,
    required this.axis,
    required this.start,
    required this.end,
  }) : minAxis = axis,
       maxAxis = axis;

  final bool horizontal;
  double axis;
  double minAxis;
  double maxAxis;
  double start;
  double end;
  int _samples = 1;

  double get length => end - start;
  (Offset, Offset) get offsets => horizontal
      ? (Offset(start, axis), Offset(end, axis))
      : (Offset(axis, start), Offset(axis, end));

  _AxisWall copy() =>
      _AxisWall(horizontal: horizontal, axis: axis, start: start, end: end)
        ..minAxis = minAxis
        ..maxAxis = maxAxis
        .._samples = _samples;

  void absorb(_AxisWall other) {
    axis =
        (axis * _samples + other.axis * other._samples) /
        (_samples + other._samples);
    _samples += other._samples;
    minAxis = math.min(minAxis, other.minAxis);
    maxAxis = math.max(maxAxis, other.maxAxis);
    start = math.min(start, other.start);
    end = math.max(end, other.end);
  }

  void chooseFloorBoundary(List<Offset> floorPoints, double sampleSize) {
    final searchBand = sampleSize * 10;
    var minusSide = 0;
    var plusSide = 0;
    for (final point in floorPoints) {
      final along = horizontal ? point.dx : point.dy;
      if (along < start - sampleSize || along > end + sampleSize) continue;
      final across = horizontal ? point.dy : point.dx;
      if (across < minAxis && minAxis - across <= searchBand) {
        minusSide++;
      } else if (across > maxAxis && across - maxAxis <= searchBand) {
        plusSide++;
      }
    }
    // Pick exactly one black-wall/white-floor interface. For walls with floor
    // on both sides, the more exposed side wins; ties use the upper/left edge
    // consistently so the opposite boundary is never duplicated.
    axis = plusSide > minusSide ? maxAxis : minAxis;
  }
}

class _WallOverlayPainter extends CustomPainter {
  const _WallOverlayPainter({
    required this.mask,
    required this.color,
    this.opacity = .72,
  });

  final _WallMask mask;
  final Color color;
  final double opacity;

  @override
  void paint(Canvas canvas, Size size) {
    final source = Size(mask.width.toDouble(), mask.height.toDouble());
    final fitted = applyBoxFit(BoxFit.contain, source, size).destination;
    final target = Alignment.center.inscribe(fitted, Offset.zero & size);
    final scale = target.width / source.width;

    canvas.save();
    canvas.clipRect(target);
    canvas.translate(target.left, target.top);
    canvas.scale(scale);
    canvas.drawPoints(
      ui.PointMode.points,
      mask.points,
      Paint()
        ..color = color.withValues(alpha: opacity)
        ..strokeWidth = mask.sampleSize * 1.55
        ..strokeCap = StrokeCap.square
        ..blendMode = BlendMode.srcOver,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _WallOverlayPainter oldDelegate) =>
      oldDelegate.mask != mask ||
      oldDelegate.color != color ||
      oldDelegate.opacity != opacity;
}

class _VectorWallPainter extends CustomPainter {
  const _VectorWallPainter({
    required this.walls,
    required this.sourceSize,
    required this.color,
  });

  final List<(Offset, Offset)> walls;
  final Size sourceSize;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final fitted = applyBoxFit(BoxFit.contain, sourceSize, size).destination;
    final target = Alignment.center.inscribe(fitted, Offset.zero & size);
    Offset convert(Offset point) => Offset(
      target.left + point.dx * target.width / sourceSize.width,
      target.top + point.dy * target.height / sourceSize.height,
    );
    final paint = Paint()
      ..color = color.withValues(alpha: .9)
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round;
    for (final wall in walls) {
      canvas.drawLine(convert(wall.$1), convert(wall.$2), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _VectorWallPainter oldDelegate) =>
      oldDelegate.walls != walls ||
      oldDelegate.sourceSize != sourceSize ||
      oldDelegate.color != color;
}

class _SettingTile extends StatelessWidget {
  const _SettingTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.enabled,
    required this.checked,
    required this.onTap,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final bool enabled;
  final bool checked;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: enabled ? onTap : null,
    borderRadius: BorderRadius.circular(9),
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: enabled
                  ? const Color(0xFFEFF6FF)
                  : const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              icon,
              size: 19,
              color: enabled
                  ? const Color(0xFF2563EB)
                  : const Color(0xFF94A3B8),
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: enabled
                        ? const Color(0xFF334155)
                        : const Color(0xFF94A3B8),
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF94A3B8),
                  ),
                ),
              ],
            ),
          ),
          Icon(
            checked ? Icons.check_circle : Icons.radio_button_unchecked,
            size: 20,
            color: checked ? const Color(0xFF22C55E) : const Color(0xFFCBD5E1),
          ),
        ],
      ),
    ),
  );
}
