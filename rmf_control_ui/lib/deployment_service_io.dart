import 'dart:io';
import 'dart:typed_data';

class MapDeploymentResult {
  const MapDeploymentResult({required this.success, required this.output});
  final bool success;
  final String output;
}

Directory? _findProjectRoot() {
  final configuredRoot = Platform.environment['RMF_ROOT'];
  if (configuredRoot != null && configuredRoot.isNotEmpty) {
    final directory = Directory(configuredRoot).absolute;
    if (File('${directory.path}/openrmf/scripts/deploy_map.sh').existsSync() &&
        Directory('${directory.path}/rmf_maps').existsSync()) {
      return directory;
    }
  }
  var directory = Directory.current.absolute;
  for (var i = 0; i < 8; i++) {
    if (File('${directory.path}/openrmf/scripts/deploy_map.sh').existsSync() &&
        Directory('${directory.path}/rmf_maps').existsSync()) {
      return directory;
    }
    final parent = directory.parent;
    if (parent.path == directory.path) break;
    directory = parent;
  }
  return null;
}

Future<MapDeploymentResult> deployMapProject({
  required String mapName,
  required String yaml,
  required String imageName,
  required Uint8List imageBytes,
}) async {
  final root = _findProjectRoot();
  if (root == null) {
    return const MapDeploymentResult(
      success: false,
      output: '프로젝트 루트(openrmf/scripts 및 rmf_maps)를 찾을 수 없습니다.',
    );
  }
  final temporary = await Directory.systemTemp.createTemp('robosapiens-map-');
  try {
    final yamlFile = File('${temporary.path}/$mapName.building.yaml');
    final imageFile = File('${temporary.path}/$imageName');
    await yamlFile.writeAsString(yaml, flush: true);
    await imageFile.writeAsBytes(imageBytes, flush: true);
    final result = await Process.run(
      'bash',
      [
        '${root.path}/openrmf/scripts/deploy_map.sh',
        yamlFile.path,
        imageFile.path,
        mapName,
      ],
      workingDirectory: root.path,
      runInShell: false,
    );
    final output = [result.stdout, result.stderr]
        .map((value) => value.toString().trim())
        .where((value) => value.isNotEmpty)
        .join('\n');
    return MapDeploymentResult(success: result.exitCode == 0, output: output);
  } catch (error) {
    return MapDeploymentResult(success: false, output: error.toString());
  } finally {
    try {
      await temporary.delete(recursive: true);
    } on FileSystemException {
      // The operating system may still be releasing a subprocess handle.
    }
  }
}
