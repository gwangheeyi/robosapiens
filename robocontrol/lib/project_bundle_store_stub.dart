/// 웹 빌드용 대체 구현. 브라우저에는 저장소 디렉터리가 없다.
library;

import 'project_bundle.dart';

export 'project_bundle.dart';

class StoredProjectBundle {
  const StoredProjectBundle({
    required this.fileName,
    required this.path,
    required this.modifiedAt,
    required this.size,
  });

  final String fileName;
  final String path;
  final DateTime modifiedAt;
  final int size;

  String get projectName =>
      fileName.replaceFirst(RegExp(r'\.rmfbundle$', caseSensitive: false), '');
}

String projectBundleDirectoryPath() => 'map_projects';

Future<List<StoredProjectBundle>> listProjectBundles() async => const [];

Future<String> writeProjectBundle(ProjectBundle bundle) async =>
    throw UnsupportedError('웹에서는 프로젝트 꾸러미를 내보낼 수 없습니다.');

Future<ProjectBundle> readProjectBundle(String fileName) async =>
    throw UnsupportedError('웹에서는 프로젝트 꾸러미를 가져올 수 없습니다.');
