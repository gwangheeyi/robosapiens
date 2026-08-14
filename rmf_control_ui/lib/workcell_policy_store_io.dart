import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'workcell_policy.dart';

String _safe(String value) => value.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
Directory _workspaceRoot() {
  final configured = Platform.environment['RMF_ROOT'];
  if (configured != null && configured.isNotEmpty) {
    final directory = Directory(configured).absolute;
    if (Directory('${directory.path}/rmf_maps').existsSync()) return directory;
  }
  var directory = Directory.current.absolute;
  for (var i = 0; i < 8; i++) {
    if (Directory('${directory.path}/rmf_maps').existsSync()) return directory;
    if (directory.parent.path == directory.path) break;
    directory = directory.parent;
  }
  throw StateError('rmf_maps 디렉터리를 찾을 수 없습니다.');
}

Directory _root(String project) =>
    Directory('${_workspaceRoot().path}/rmf_maps/${_safe(project)}/policies');

Future<List<WorkcellPolicy>> loadWorkcellPolicies(String projectName) async {
  final index = File('${_root(projectName).path}/index.json');
  if (!await index.exists()) return [];
  final decoded = jsonDecode(await index.readAsString()) as List<dynamic>;
  return [
    for (final item in decoded)
      WorkcellPolicy.fromJson(Map<String, dynamic>.from(item as Map)),
  ];
}

Future<void> _writeIndex(
  String projectName,
  List<WorkcellPolicy> policies,
) async {
  final root = _root(projectName);
  await root.create(recursive: true);
  await File('${root.path}/index.json').writeAsString(
    const JsonEncoder.withIndent(
      '  ',
    ).convert([for (final policy in policies) policy.toJson()]),
    flush: true,
  );
}

Future<void> saveWorkcellPolicy(
  String projectName,
  WorkcellPolicy policy,
  Uint8List archive,
) async {
  final policies = await loadWorkcellPolicies(projectName);
  policies.removeWhere((item) => item.id == policy.id);
  policies.add(policy);
  final versionDir = Directory(
    '${_root(projectName).path}/${_safe(policy.name)}/${_safe(policy.version)}',
  );
  await versionDir.create(recursive: true);
  await File(
    '${versionDir.path}/policy.zip',
  ).writeAsBytes(archive, flush: true);
  await File(
    '${versionDir.path}/manifest.json',
  ).writeAsString(policy.manifest(projectName), flush: true);
  for (final workcell in policy.deployedWorkcells) {
    final target = Directory('${versionDir.path}/deploy/${_safe(workcell)}');
    await target.create(recursive: true);
    await File('${target.path}/policy.zip').writeAsBytes(archive, flush: true);
    await File(
      '${target.path}/manifest.json',
    ).writeAsString(policy.manifest(projectName), flush: true);
  }
  await _writeIndex(projectName, policies);
}

Future<void> deleteWorkcellPolicy(
  String projectName,
  WorkcellPolicy policy,
) async {
  final policies = await loadWorkcellPolicies(projectName)
    ..removeWhere((item) => item.id == policy.id);
  final directory = Directory(
    '${_root(projectName).path}/${_safe(policy.name)}/${_safe(policy.version)}',
  );
  if (await directory.exists()) await directory.delete(recursive: true);
  await _writeIndex(projectName, policies);
}

Future<HuggingFacePolicyDownload> downloadHuggingFacePolicy({
  required String repositoryId,
  required String revision,
  required String fileName,
}) async {
  final repo = repositoryId.trim();
  final rev = revision.trim().isEmpty ? 'main' : revision.trim();
  final file = fileName.trim();
  if (!RegExp(r'^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$').hasMatch(repo)) {
    throw const FormatException('Repository ID는 owner/name 형식이어야 합니다.');
  }
  if (file.isEmpty || file.startsWith('/') || file.split('/').contains('..')) {
    throw const FormatException('올바른 저장소 내 ZIP 파일 경로를 입력하세요.');
  }
  final encodedFile = file.split('/').map(Uri.encodeComponent).join('/');
  final uri = Uri.parse(
    'https://huggingface.co/$repo/resolve/${Uri.encodeComponent(rev)}/$encodedFile',
  );
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 20);
  try {
    final request = await client.getUrl(uri);
    final token =
        Platform.environment['HF_TOKEN'] ??
        Platform.environment['HUGGING_FACE_HUB_TOKEN'];
    if (token != null && token.isNotEmpty) {
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
    }
    request.headers.set(
      HttpHeaders.userAgentHeader,
      'robosapiens-workcell-policy/1.0',
    );
    final response = await request.close();
    if (response.statusCode != HttpStatus.ok) {
      await response.drain<void>();
      throw HttpException(
        response.statusCode == HttpStatus.unauthorized ||
                response.statusCode == HttpStatus.forbidden
            ? '접근 권한이 없습니다. 비공개 저장소라면 HF_TOKEN을 설정하세요.'
            : 'Hugging Face 다운로드 실패 (HTTP ${response.statusCode})',
        uri: uri,
      );
    }
    const limit = 1024 * 1024 * 1024;
    final builder = BytesBuilder(copy: false);
    await for (final chunk in response) {
      if (builder.length + chunk.length > limit) {
        throw const FileSystemException('Policy ZIP은 1GB 이하여야 합니다.');
      }
      builder.add(chunk);
    }
    return HuggingFacePolicyDownload(
      repositoryId: repo,
      revision: rev,
      fileName: file.split('/').last,
      bytes: builder.takeBytes(),
    );
  } finally {
    client.close(force: true);
  }
}
