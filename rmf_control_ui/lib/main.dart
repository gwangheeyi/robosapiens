import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
  final List<Offset> _laneWaypoints = [];
  bool _isWaypointMode = false;
  int _vertexLabelRevision = 0;
  bool _showVertexLabels = true;

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
        _laneWaypoints.clear();
        _isWaypointMode = false;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('${file.name} 도면을 불러왔습니다.')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('파일을 불러오지 못했습니다: $error')));
    } finally {
      if (mounted) setState(() => _isPicking = false);
    }
  }

  void _removeDrawing() {
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
      _laneWaypoints.clear();
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

  void _addLaneWaypoint(Offset point) {
    setState(() {
      if (_laneWaypoints.isNotEmpty) {
        _recommendedLanes.add((_laneWaypoints.last, point));
      }
      _laneWaypoints.add(point);
      _stage = MapStage.lanes;
      _isDeployed = false;
      _vertexLabelRevision++;
    });
  }

  @override
  void dispose() {
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

  String _yamlEscape(String value) =>
      value.replaceAll(r'\', r'\\').replaceAll('"', r'\"');

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
    final laneIndices = <(int, int)>[
      for (final lane in _recommendedLanes)
        (vertexIndex(lane.$1), vertexIndex(lane.$2)),
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
        buffer.writeln(
          '      - [${lane.$1}, ${lane.$2}, {is_bidirectional: [4, true]}]',
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
        final name = measurement != null && i == measurementIndices.first
            ? 'measurement_start'
            : measurement != null && i == measurementIndices.last
            ? 'measurement_end'
            : '';
        buffer.writeln(
          '      - [${point.dx.toStringAsFixed(3)}, ${point.dy.toStringAsFixed(3)}, 0.0, "$name"]',
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('YAML 파일을 저장하지 못했습니다: $error')));
    }
  }

  Future<void> _copyBuildingYaml() async {
    if (_drawing == null) return;
    await Clipboard.setData(ClipboardData(text: _buildBuildingYaml()));
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('$_yamlFileName 내용을 클립보드에 복사했습니다.')));
  }

  Future<void> _deployMap() async {
    final drawing = _drawing;
    if (drawing == null) return;

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
                '벽, Floor, Lane과 로봇 작업 위치 설정이 함께 반영됩니다.',
                style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
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
    setState(() {
      _stage = MapStage.deploy;
      _isDeployed = true;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: const Color(0xFF15803D),
        content: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.white),
            const SizedBox(width: 10),
            Expanded(child: Text('${drawing.name} 맵 배포를 완료했습니다.')),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          const _NavigationRail(),
          Expanded(
            child: Column(
              children: [
                const _TopBar(),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(32, 30, 32, 40),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1440),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _PageHeading(
                              onUpload: _pickDrawing,
                              exportEnabled: _drawing != null,
                              onDownload: _downloadBuildingYaml,
                              onCopy: _copyBuildingYaml,
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
                                        transformController: _mapTransform,
                                        onZoomIn: () => _zoomMap(1.25),
                                        onZoomOut: () => _zoomMap(.8),
                                        onFitScreen: _fitMapToScreen,
                                        onRenumberVertices: _renumberVertices,
                                        wallMask: _wallMask,
                                        wallColor: _wallColor,
                                        floorMask: _floorMask,
                                        floorColor: _floorColor,
                                        mapVertices: _showVertexLabels
                                            ? _visibleMapVertices()
                                            : const [],
                                        vertexLabelRevision:
                                            _vertexLabelRevision,
                                        optimizedWalls: _visibleWallSegments(),
                                        recommendedLanes: _recommendedLanes,
                                        laneWaypoints: _laneWaypoints,
                                        waypointMode: _isWaypointMode,
                                        onAddWaypoint: _addLaneWaypoint,
                                        isWallConnectMode: _isWallConnectMode,
                                        pendingWallVertex: _pendingWallVertex,
                                        onToggleWallConnect:
                                            _toggleWallConnectMode,
                                        onSelectWallVertex:
                                            _selectWallConnectionVertex,
                                        isWallEndpointEditMode:
                                            _isWallEndpointEditMode,
                                        onToggleWallEndpointEdit:
                                            _toggleWallEndpointEditMode,
                                        onMoveWallEndpoint: _moveWallEndpoint,
                                        measurement: _measurement,
                                        showDrawingInfo: _showDrawingInfo,
                                        onCloseDrawingInfo: () => setState(
                                          () => _showDrawingInfo = false,
                                        ),
                                        isMeasurementSelected:
                                            _isMeasurementSelected,
                                        onSelectMeasurement: _selectMeasurement,
                                        onRemoveMeasurement: _removeMeasurement,
                                        isMeasurementMode: _isMeasurementMode,
                                        onMeasurementSelected: _askMeasurement,
                                        onCloseMeasurementMode: () => setState(
                                          () => _isMeasurementMode = false,
                                        ),
                                        isWallEraseMode: _isWallEraseMode,
                                        canUndoWallErase:
                                            _previousWallMask != null,
                                        onToggleWallErase: () => setState(
                                          () => _isWallEraseMode =
                                              !_isWallEraseMode,
                                        ),
                                        onEraseWalls: _eraseWalls,
                                        onUndoWallErase: _undoWallErase,
                                        isPicking: _isPicking,
                                        onPick: _pickDrawing,
                                        onRemove: _removeDrawing,
                                      ),
                                      const SizedBox(height: 20),
                                      _SetupPanel(
                                        drawing: _drawing,
                                        stage: _stage,
                                        measurement: _measurement,
                                        isMeasurementMode: _isMeasurementMode,
                                        onToggleMeasurement:
                                            _toggleMeasurementMode,
                                        wallColor: _wallColor,
                                        floorColor: _floorColor,
                                        wallsDetected: _wallsDetected,
                                        floorGenerated: _floorGenerated,
                                        isDetectingWalls: _isDetectingWalls,
                                        isGeneratingFloor: _isGeneratingFloor,
                                        onDetectWalls: _detectWalls,
                                        onGenerateFloor: _generateFloor,
                                        lanesGenerated:
                                            _laneWaypoints.isNotEmpty,
                                        waypointMode: _isWaypointMode,
                                        onToggleWaypoint: _toggleWaypointMode,
                                        onWallColorChanged: (color) =>
                                            setState(() => _wallColor = color),
                                        onFloorColorChanged: (color) =>
                                            setState(() => _floorColor = color),
                                        isDeployed: _isDeployed,
                                        onDeploy: _deployMap,
                                        onStageChanged: (value) =>
                                            setState(() => _stage = value),
                                      ),
                                    ],
                                  );
                                }
                                return Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      child: _MapWorkspace(
                                        drawing: _drawing,
                                        transformController: _mapTransform,
                                        onZoomIn: () => _zoomMap(1.25),
                                        onZoomOut: () => _zoomMap(.8),
                                        onFitScreen: _fitMapToScreen,
                                        onRenumberVertices: _renumberVertices,
                                        wallMask: _wallMask,
                                        wallColor: _wallColor,
                                        floorMask: _floorMask,
                                        floorColor: _floorColor,
                                        mapVertices: _showVertexLabels
                                            ? _visibleMapVertices()
                                            : const [],
                                        vertexLabelRevision:
                                            _vertexLabelRevision,
                                        optimizedWalls: _visibleWallSegments(),
                                        recommendedLanes: _recommendedLanes,
                                        laneWaypoints: _laneWaypoints,
                                        waypointMode: _isWaypointMode,
                                        onAddWaypoint: _addLaneWaypoint,
                                        isWallConnectMode: _isWallConnectMode,
                                        pendingWallVertex: _pendingWallVertex,
                                        onToggleWallConnect:
                                            _toggleWallConnectMode,
                                        onSelectWallVertex:
                                            _selectWallConnectionVertex,
                                        isWallEndpointEditMode:
                                            _isWallEndpointEditMode,
                                        onToggleWallEndpointEdit:
                                            _toggleWallEndpointEditMode,
                                        onMoveWallEndpoint: _moveWallEndpoint,
                                        measurement: _measurement,
                                        showDrawingInfo: _showDrawingInfo,
                                        onCloseDrawingInfo: () => setState(
                                          () => _showDrawingInfo = false,
                                        ),
                                        isMeasurementSelected:
                                            _isMeasurementSelected,
                                        onSelectMeasurement: _selectMeasurement,
                                        onRemoveMeasurement: _removeMeasurement,
                                        isMeasurementMode: _isMeasurementMode,
                                        onMeasurementSelected: _askMeasurement,
                                        onCloseMeasurementMode: () => setState(
                                          () => _isMeasurementMode = false,
                                        ),
                                        isWallEraseMode: _isWallEraseMode,
                                        canUndoWallErase:
                                            _previousWallMask != null,
                                        onToggleWallErase: () => setState(
                                          () => _isWallEraseMode =
                                              !_isWallEraseMode,
                                        ),
                                        onEraseWalls: _eraseWalls,
                                        onUndoWallErase: _undoWallErase,
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
                                        isMeasurementMode: _isMeasurementMode,
                                        onToggleMeasurement:
                                            _toggleMeasurementMode,
                                        wallColor: _wallColor,
                                        floorColor: _floorColor,
                                        wallsDetected: _wallsDetected,
                                        floorGenerated: _floorGenerated,
                                        isDetectingWalls: _isDetectingWalls,
                                        isGeneratingFloor: _isGeneratingFloor,
                                        onDetectWalls: _detectWalls,
                                        onGenerateFloor: _generateFloor,
                                        lanesGenerated:
                                            _laneWaypoints.isNotEmpty,
                                        waypointMode: _isWaypointMode,
                                        onToggleWaypoint: _toggleWaypointMode,
                                        onWallColorChanged: (color) =>
                                            setState(() => _wallColor = color),
                                        onFloorColorChanged: (color) =>
                                            setState(() => _floorColor = color),
                                        isDeployed: _isDeployed,
                                        onDeploy: _deployMap,
                                        onStageChanged: (value) =>
                                            setState(() => _stage = value),
                                      ),
                                    ),
                                  ],
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NavigationRail extends StatelessWidget {
  const _NavigationRail();

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
                Padding(
                  padding: const EdgeInsets.only(bottom: 7),
                  child: _NavItem(
                    icon: items[i].$1,
                    label: items[i].$2,
                    selected: i == 1,
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
  const _TopBar();
  @override
  Widget build(BuildContext context) => Container(
    height: 68,
    padding: const EdgeInsets.symmetric(horizontal: 30),
    decoration: const BoxDecoration(
      color: Colors.white,
      border: Border(bottom: BorderSide(color: Color(0xFFE5EAF0))),
    ),
    child: const Row(
      children: [
        Text(
          '맵 관리',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: Color(0xFF334155),
          ),
        ),
        Spacer(),
        _StatusDot(),
        SizedBox(width: 20),
        Icon(Icons.notifications_none_rounded, color: Color(0xFF64748B)),
        SizedBox(width: 18),
        Icon(Icons.help_outline_rounded, color: Color(0xFF64748B)),
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

enum _ExportAction { download, copy }

class _PageHeading extends StatelessWidget {
  const _PageHeading({
    required this.onUpload,
    required this.exportEnabled,
    required this.onDownload,
    required this.onCopy,
  });
  final VoidCallback onUpload;
  final bool exportEnabled;
  final VoidCallback onDownload;
  final VoidCallback onCopy;
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
    'Lane 추천',
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
    required this.laneWaypoints,
    required this.waypointMode,
    required this.onAddWaypoint,
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
  final List<Offset> laneWaypoints;
  final bool waypointMode;
  final ValueChanged<Offset> onAddWaypoint;
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
    height: 610,
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
                  laneWaypoints: laneWaypoints,
                  waypointMode: waypointMode,
                  onAddWaypoint: onAddWaypoint,
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
    required this.laneWaypoints,
    required this.waypointMode,
    required this.onAddWaypoint,
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
  final List<Offset> laneWaypoints;
  final bool waypointMode;
  final ValueChanged<Offset> onAddWaypoint;
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
          padding: const EdgeInsets.all(28),
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
                    laneWaypoints: laneWaypoints,
                    waypointMode: waypointMode,
                    onAddWaypoint: onAddWaypoint,
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
    required this.laneWaypoints,
    required this.waypointMode,
    required this.onAddWaypoint,
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
  final List<Offset> laneWaypoints;
  final bool waypointMode;
  final ValueChanged<Offset> onAddWaypoint;
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

  void _addWaypointAt(Offset position, Size canvasSize) {
    final target = _imageTarget(canvasSize);
    if (!target.contains(position)) return;
    widget.onAddWaypoint(
      Offset(
        (position.dx - target.left) * widget.sourceSize.width / target.width,
        (position.dy - target.top) * widget.sourceSize.height / target.height,
      ),
    );
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
                  waypoints: widget.laneWaypoints,
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
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapUp: (details) =>
                    _addWaypointAt(details.localPosition, size),
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
          if (widget.measurement != null &&
              !widget.measurementMode &&
              !widget.eraseMode &&
              !widget.waypointMode)
            GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTapUp: (details) =>
                  _trySelectMeasurement(details.localPosition, size),
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
    required this.waypoints,
    required this.sourceSize,
  });

  final List<(Offset, Offset)> lanes;
  final List<Offset> waypoints;
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
    for (final lane in lanes) {
      final start = convert(lane.$1);
      final end = convert(lane.$2);
      canvas.drawLine(start, end, paint);
      final direction = end - start;
      if (direction.distance <= 1) continue;
      final unit = direction / direction.distance;
      final normal = Offset(-unit.dy, unit.dx);
      const arrowLength = 9.0;
      const arrowWidth = 5.0;
      final tip = Offset.lerp(start, end, .62)!;
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
    for (var i = 0; i < waypoints.length; i++) {
      final point = convert(waypoints[i]);
      canvas.drawCircle(point, 6, Paint()..color = const Color(0xFFFFFFFF));
      canvas.drawCircle(point, 5, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _LanePainter oldDelegate) =>
      oldDelegate.lanes != lanes ||
      oldDelegate.waypoints != waypoints ||
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
