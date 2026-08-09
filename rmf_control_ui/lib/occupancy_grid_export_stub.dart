/// 웹 빌드용 대체 구현. 브라우저에서는 파일을 쓸 수 없다.
library;

import 'occupancy_grid.dart';

class OccupancyGridExportResult {
  const OccupancyGridExportResult({
    required this.success,
    required this.directory,
    required this.written,
    required this.message,
  });
  final bool success;
  final String directory;
  final List<String> written;
  final String message;
}

const String occupancyGridDirectoryName = 'nav2_map';

Future<OccupancyGridExportResult> exportOccupancyGrid({
  required String mapName,
  required OccupancyGrid grid,
  String? note,
}) async => const OccupancyGridExportResult(
  success: false,
  directory: '',
  written: [],
  message: '이 환경에서는 지도를 파일로 쓸 수 없습니다.',
);

String buildOccupancyGridReadme(String mapName, OccupancyGrid grid) => '';
