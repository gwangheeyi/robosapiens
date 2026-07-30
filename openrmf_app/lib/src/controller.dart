import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

import 'models.dart';
import 'rmf_api.dart';

class RmfController extends ChangeNotifier {
  RmfController({required String apiUrl, required String apiToken})
    : _api = RmfApi(baseUrl: apiUrl, token: apiToken);

  final RmfApi _api;
  Timer? _timer;
  bool _refreshing = false;

  RmfBuildingMap? building;
  List<RmfRobot> robots = const [];
  List<RmfTask> tasks = const [];
  Uint8List? mapBytes;
  ui.Image? decodedMap;
  String? error;
  DateTime? lastUpdated;
  String? selectedRobot;
  int selectedLevel = 0;

  String get apiUrl => _api.baseUri.toString();
  bool get connected => error == null && lastUpdated != null;
  RmfLevel? get level {
    final levels = building?.levels ?? const <RmfLevel>[];
    if (levels.isEmpty) return null;
    return levels[selectedLevel.clamp(0, levels.length - 1)];
  }

  Iterable<RmfRobot> get visibleRobots =>
      robots.where((robot) => robot.level == level?.name);

  void start() {
    refresh();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => refresh());
  }

  Future<void> refresh() async {
    if (_refreshing) return;
    _refreshing = true;
    try {
      await _api.checkConnection();
      final results = await Future.wait([
        _api.getBuildingMap(),
        _api.getRobots(),
        _api.getTasks(),
      ]);
      final nextBuilding = results[0] as RmfBuildingMap;
      final nextImage = nextBuilding.levels.isEmpty
          ? null
          : nextBuilding
                .levels[selectedLevel.clamp(0, nextBuilding.levels.length - 1)]
                .image;
      final imageChanged =
          nextImage?.url.isNotEmpty == true &&
          nextImage?.url != level?.image?.url;
      building = nextBuilding;
      robots = results[1] as List<RmfRobot>;
      tasks = results[2] as List<RmfTask>;
      if ((mapBytes == null || imageChanged) && nextImage != null) {
        await _loadMap(nextImage.url);
      }
      error = null;
      lastUpdated = DateTime.now();
    } catch (exception) {
      error = exception.toString();
    } finally {
      _refreshing = false;
      notifyListeners();
    }
  }

  Future<void> _loadMap(String url) async {
    final bytes = await _api.getBytes(url);
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    codec.dispose();
    final image = frame.image;
    decodedMap?.dispose();
    mapBytes = bytes;
    decodedMap = image;
  }

  void selectRobot(String? robot) {
    selectedRobot = robot;
    notifyListeners();
  }

  Future<void> selectLevel(int index) async {
    if (index == selectedLevel) return;
    selectedLevel = index;
    mapBytes = null;
    decodedMap?.dispose();
    decodedMap = null;
    notifyListeners();
    await refresh();
  }

  @override
  void dispose() {
    _timer?.cancel();
    decodedMap?.dispose();
    _api.close();
    super.dispose();
  }
}
