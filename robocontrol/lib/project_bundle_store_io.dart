/// 프로젝트 꾸러미를 저장소 안 한 곳에 두고 읽는다.
///
/// **git 에 올라가는 자리여야 한다.** 그것이 이 파일이 있는 이유다 —
/// `robocontrol/project/` 는 `.gitignore` 에 걸려 있어서, 거기 아무리 잘
/// 저장해도 다른 기계로 넘어가지 않았다.
///
/// 폴더를 사용자가 고르게 하지 않는다. 같은 이름의 꾸러미가 여러 곳에 흩어지면
/// 어느 것이 최신인지 아무도 모른다.
library;

import 'dart:convert';
import 'dart:io';

import 'project_bundle.dart';

export 'project_bundle.dart';

String? debugProjectBundleRootOverride;

/// 저장소 뿌리. `db/schema.sql` 이 있는 자리를 뿌리로 본다 —
/// `database_migration_io.dart` 가 쓰는 기준과 같게 둔다.
Directory projectBundleRoot() {
  final override = debugProjectBundleRootOverride;
  if (override != null && override.isNotEmpty) {
    return Directory(override).absolute;
  }
  final configured = Platform.environment['RMF_ROOT'];
  if (configured != null && configured.isNotEmpty) {
    final root = Directory(configured).absolute;
    if (File('${root.path}/db/schema.sql').existsSync()) return root;
  }
  var directory = Directory.current.absolute;
  for (var i = 0; i < 8; i++) {
    if (File('${directory.path}/db/schema.sql').existsSync()) return directory;
    if (directory.parent.path == directory.path) break;
    directory = directory.parent;
  }
  throw StateError(
    'db/schema.sql 이 있는 저장소 뿌리를 찾지 못했습니다. '
    '앱을 저장소 안에서 실행하거나 RMF_ROOT 를 정해 주세요.',
  );
}

Directory projectBundleDirectory() =>
    Directory('${projectBundleRoot().path}/map_projects');

/// 꾸러미가 놓이는 자리. 사람에게 보여 줄 때 쓴다 — 어디를 봐야 하는지
/// 모르면 `pull 했는데 목록이 비어 있다` 에서 더 나아갈 수 없다.
String projectBundleDirectoryPath() => projectBundleDirectory().path;

/// 꾸러미 파일 하나.
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

Future<List<StoredProjectBundle>> listProjectBundles() async {
  final directory = projectBundleDirectory();
  if (!directory.existsSync()) return const [];
  final bundles = <StoredProjectBundle>[];
  await for (final entity in directory.list()) {
    if (entity is! File) continue;
    if (!entity.path.toLowerCase().endsWith('.rmfbundle')) continue;
    final stat = await entity.stat();
    bundles.add(
      StoredProjectBundle(
        fileName: entity.uri.pathSegments.last,
        path: entity.path,
        modifiedAt: stat.modified,
        size: stat.size,
      ),
    );
  }
  bundles.sort((a, b) => a.projectName.compareTo(b.projectName));
  return bundles;
}

/// 꾸러미를 쓴다. 쓴 자리를 돌려준다.
///
/// 줄을 나눠 쓴다. 한 줄짜리 JSON 은 `git diff` 가 통째로 바뀐 것으로만 보여
/// 줘서, 무엇을 고쳐 올리는지 커밋에서 알 수 없다.
Future<String> writeProjectBundle(ProjectBundle bundle) async {
  final directory = projectBundleDirectory();
  await directory.create(recursive: true);
  final target = File(
    '${directory.path}/${projectBundleFileName(bundle.mapName)}',
  );
  final temporary = File('${target.path}.tmp');
  // 쓰다 만 파일을 남기지 않는다. 반쯤 쓰인 JSON 을 커밋하면 받는 쪽에서
  // 파싱만 실패하고 무엇이 잘못됐는지는 안 보인다.
  await temporary.writeAsString(
    '${const JsonEncoder.withIndent('  ').convert(bundle.toJson())}\n',
    flush: true,
  );
  await temporary.rename(target.path);
  return target.path;
}

Future<ProjectBundle> readProjectBundle(String fileName) async {
  final file = File('${projectBundleDirectory().path}/$fileName');
  if (!file.existsSync()) {
    throw StateError('${file.path} 가 없습니다.');
  }
  final data = jsonDecode(await file.readAsString());
  if (data is! Map<String, dynamic>) {
    throw const FormatException('꾸러미 파일이 JSON 객체가 아닙니다.');
  }
  return ProjectBundle.parse(data);
}
