import 'dart:typed_data';

class MapDeploymentResult {
  const MapDeploymentResult({required this.success, required this.output});
  final bool success;
  final String output;
}

Future<MapDeploymentResult> deployMapProject({
  required String mapName,
  required String yaml,
  required String imageName,
  required Uint8List imageBytes,
}) async => const MapDeploymentResult(
  success: false,
  output: '실제 맵 배포는 Linux 데스크톱 앱에서만 지원됩니다.',
);
