/// WorkCell Policy 보관소.
///
/// 기본 정보(이름·버전·소속 프로젝트·붙인 설비)는 MySQL 의 `workcell_policies`
/// 에 담고, 학습 결과 ZIP 은 `<작업트리>/workcell_policies/<storage_key>/` 아래
/// 파일로 둔다. 수백 MB 를 DB 에 넣을 이유가 없고, git 에도 올리지 않는다.
///
/// 그래서 다른 자리에서 받은 저장소에는 **목록에는 있으나 파일이 없는** policy
/// 가 생긴다. 목록을 읽을 때마다 파일이 있는지 보고, 없으면 Hugging Face 에서
/// 다시 받을 수 있게 표시해 둔다.
///
/// 프로젝트는 이름으로만 적는다(FK 없음). Policy 는 프로젝트보다 오래 남는
/// 자산이라 프로젝트를 지워도 남아야 하고, 소속만 고쳐 다른 프로젝트로 옮길 수
/// 있어야 한다.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import 'workcell_policy.dart';

// ---------------------------------------------------------------------------
// MySQL
// ---------------------------------------------------------------------------

Map<String, String> _mysqlEnvironment() => {
  ...Platform.environment,
  'MYSQL_PWD': Platform.environment['ROBOSAPIENS_DB_PASSWORD'] ?? 'robosapiens',
};

List<String> _mysqlArguments() => [
  '--batch',
  '--raw',
  '--skip-column-names',
  '--default-character-set=utf8mb4',
  '--host=${Platform.environment['ROBOSAPIENS_DB_HOST'] ?? '127.0.0.1'}',
  '--port=${Platform.environment['ROBOSAPIENS_DB_PORT'] ?? '3306'}',
  '--user=${Platform.environment['ROBOSAPIENS_DB_USER'] ?? 'root'}',
  Platform.environment['ROBOSAPIENS_DB_NAME'] ?? 'robosapiens',
];

Future<String> _query(String sql) async {
  final process = await Process.start(
    'mysql',
    _mysqlArguments(),
    environment: _mysqlEnvironment(),
  );
  process.stdin.write(sql);
  await process.stdin.close();
  final outputFuture = process.stdout.transform(utf8.decoder).join();
  final errorFuture = process.stderr.transform(utf8.decoder).join();
  final exitCode = await process.exitCode;
  final output = await outputFuture;
  final error = await errorFuture;
  if (exitCode != 0) {
    throw StateError('Policy 저장소(MySQL) 작업 실패: ${error.trim()}');
  }
  return output.trim();
}

/// 값을 SQL 에 넣는 유일한 길. base64 로 감싸 따옴표 문제를 없앤다.
String _text(String? value) => value == null
    ? 'NULL'
    : "CONVERT(FROM_BASE64('${base64Encode(utf8.encode(value))}') USING utf8mb4)";

/// 비교에 쓰는 값. 컬럼 collation 에 맞춰야 illegal mix 로 죽지 않는다.
String _match(String value) => '(${_text(value)} COLLATE utf8mb4_unicode_ci)';

/// 컬럼 값을 개행 없는 base64 한 줄로 뽑는 SQL 조각.
String _toBase64(String expression) =>
    "REPLACE(REPLACE(TO_BASE64($expression), '\\n', ''), '\\r', '')";

String _decodeResult(String output) {
  if (output.isEmpty) return '';
  final line = output.split('\n').last.trim();
  if (line.isEmpty || line == 'NULL') return '';
  return utf8.decode(base64Decode(line));
}

/// 목록을 읽는 SELECT. [where] 는 `WHERE` 다음에 그대로 붙는다.
const String _rowJson = '''CAST(
  COALESCE(
    JSON_ARRAYAGG(
      JSON_OBJECT(
        'name', name,
        'version', version,
        'projectName', project_name,
        'objectType', object_type,
        'robotModel', robot_model,
        'archiveName', archive_name,
        'archiveBytes', archive_bytes,
        'storageKey', storage_key,
        'deployedWorkcells', deployed_workcells,
        'sourceRepository', source_repository,
        'sourceRevision', source_revision,
        'createdAt', DATE_FORMAT(created_at, '%Y-%m-%dT%H:%i:%s.%f')
      )
    ),
    JSON_ARRAY()
  ) AS CHAR
)''';

Future<List<WorkcellPolicy>> _select(String where) async {
  await _migrateLegacyPolicies();
  final output = await _query('''
SELECT ${_toBase64(_rowJson)} FROM workcell_policies WHERE $where;
''');
  final decoded = _decodeResult(output);
  if (decoded.isEmpty) return const [];
  final rows = jsonDecode(decoded) as List<dynamic>;
  final policies = [
    for (final row in rows.cast<Map<String, dynamic>>())
      _withArchiveState(WorkcellPolicy.fromJson(row)),
  ];
  // JSON_ARRAYAGG 는 순서를 보장하지 않는다. 최근 들여놓은 순으로 세운다.
  policies.sort((a, b) => b.createdAt.compareTo(a.createdAt));
  return policies;
}

/// 디스크에 ZIP 이 있는지 확인해 채운 사본.
WorkcellPolicy _withArchiveState(WorkcellPolicy policy) => policy.copyWith(
  archiveMissing: !File(policyArchivePath(policy)).existsSync(),
);

Future<void> _upsert(WorkcellPolicy policy) async {
  await _query('''
INSERT INTO workcell_policies (
  policy_id, name, version, project_name, object_type, robot_model,
  archive_name, archive_bytes, storage_key, deployed_workcells,
  source_repository, source_revision, created_at, updated_at
) VALUES (
  ${_text(policy.id)},
  ${_text(policy.name)},
  ${_text(policy.version)},
  ${_text(policy.projectName)},
  ${_text(policy.objectType)},
  ${_text(policy.robotModel)},
  ${_text(policy.archiveName)},
  ${policy.archiveBytes},
  ${_text(policy.storagePath)},
  CAST(${_text(jsonEncode(policy.deployedWorkcells))} AS JSON),
  ${_text(policy.sourceRepository)},
  ${_text(policy.sourceRevision)},
  COALESCE(
    STR_TO_DATE(${_text(policy.createdAt.toIso8601String())}, '%Y-%m-%dT%H:%i:%s.%f'),
    NOW(6)
  ),
  NOW(6)
)
ON DUPLICATE KEY UPDATE
  name = VALUES(name),
  version = VALUES(version),
  project_name = VALUES(project_name),
  object_type = VALUES(object_type),
  robot_model = VALUES(robot_model),
  archive_name = VALUES(archive_name),
  archive_bytes = VALUES(archive_bytes),
  storage_key = VALUES(storage_key),
  deployed_workcells = VALUES(deployed_workcells),
  source_repository = VALUES(source_repository),
  source_revision = VALUES(source_revision),
  updated_at = NOW(6);
''');
}

// ---------------------------------------------------------------------------
// 디스크
// ---------------------------------------------------------------------------

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

Directory _libraryRoot() =>
    Directory('${_workspaceRoot().path}/workcell_policies');

/// 이 policy 의 ZIP 이 놓인(또는 놓일) 자리.
String policyArchivePath(WorkcellPolicy policy) =>
    '${_libraryRoot().path}/${policy.storagePath}/policy.zip';

Future<void> _writeArchive(WorkcellPolicy policy, Uint8List bytes) async {
  final file = File(policyArchivePath(policy));
  await file.parent.create(recursive: true);
  await file.writeAsBytes(bytes, flush: true);
  await File(
    '${file.parent.path}/manifest.json',
  ).writeAsString(policy.globalManifest(), flush: true);
}

// ---------------------------------------------------------------------------
// 옛 파일 목록 옮기기
// ---------------------------------------------------------------------------

bool _legacyChecked = false;

/// 파일로 두던 목록(index.json / policy_bindings.json)을 DB 로 한 번 옮긴다.
///
/// 옮긴 뒤에는 표식을 남겨 다시 읽지 않는다. 그러지 않으면 DB 에서 지운 policy
/// 가 다음 실행에 되살아난다.
Future<void> _migrateLegacyPolicies() async {
  if (_legacyChecked) return;
  _legacyChecked = true;
  final Directory library;
  try {
    library = _libraryRoot();
  } catch (_) {
    // 작업트리를 못 찾는 자리(테스트 등)에서는 옮길 것도 없다.
    return;
  }
  final marker = File('${library.path}/.migrated_to_mysql');
  if (await marker.exists()) return;
  final index = File('${library.path}/index.json');
  if (!await index.exists()) return;

  final decoded = jsonDecode(await index.readAsString()) as List<dynamic>;
  final legacy = <String, WorkcellPolicy>{
    for (final item in decoded)
      if (WorkcellPolicy.fromJson(Map<String, dynamic>.from(item as Map))
          case final policy)
        policy.id: policy,
  };
  // 어느 프로젝트가 무엇을 쓰고 있었는지는 프로젝트 쪽 파일에 있다.
  final maps = Directory('${_workspaceRoot().path}/rmf_maps');
  if (await maps.exists()) {
    await for (final entity in maps.list()) {
      if (entity is! Directory) continue;
      final project = entity.path.split('/').last;
      if (project.startsWith('.')) continue;
      final bindings = File('${entity.path}/policy_bindings.json');
      if (!await bindings.exists()) continue;
      final rows = jsonDecode(await bindings.readAsString()) as List<dynamic>;
      for (final raw in rows.cast<Map<String, dynamic>>()) {
        final policy = legacy[raw['policyId']?.toString()];
        if (policy == null) continue;
        legacy[policy.id] = policy.copyWith(
          projectName: project,
          objectType: raw['objectType']?.toString() ?? policy.objectType,
          deployedWorkcells: [
            for (final value
                in raw['deployedWorkcells'] as List<dynamic>? ?? const [])
              value.toString(),
          ],
        );
      }
    }
  }
  // DB 에 이미 있는 것은 건드리지 않는다. 사람이 고친 쪽이 옳다.
  final existing = {for (final policy in await _select('1 = 1')) policy.id};
  for (final policy in legacy.values) {
    if (existing.contains(policy.id)) continue;
    await _upsert(policy);
  }
  await marker.writeAsString(
    '이 폴더의 index.json 은 MySQL workcell_policies 로 옮겼습니다.\n'
    '${DateTime.now().toIso8601String()}\n',
    flush: true,
  );
}

// ---------------------------------------------------------------------------
// 읽기
// ---------------------------------------------------------------------------

/// [projectName] 프로젝트가 가진 policy.
Future<List<WorkcellPolicy>> loadWorkcellPolicies(String projectName) =>
    _select('project_name = ${_match(projectName)}');

/// 프로젝트를 가리지 않은 전체 목록. 소속이 없는 공용도 함께 온다.
Future<List<WorkcellPolicy>> loadGlobalWorkcellPolicies() => _select('1 = 1');

/// 어느 프로젝트에도 매이지 않은 policy. 어느 프로젝트에서든 가져다 쓸 수 있다.
Future<List<WorkcellPolicy>> loadUnassignedWorkcellPolicies() =>
    _select('project_name IS NULL');

// ---------------------------------------------------------------------------
// 쓰기
// ---------------------------------------------------------------------------

/// 새 policy 를 들여놓는다. ZIP 은 디스크에, 기본 정보는 DB 에 담는다.
Future<void> saveWorkcellPolicy(
  String projectName,
  WorkcellPolicy policy,
  Uint8List archive,
) async {
  await _migrateLegacyPolicies();
  final existing = await _select('policy_id = ${_match(policy.id)}');
  if (existing.isNotEmpty) {
    throw StateError('같은 이름과 버전의 Policy 가 이미 있습니다: ${policy.id}');
  }
  final stored = policy.copyWith(
    projectName: projectName,
    archiveBytes: archive.length,
    archiveMissing: false,
  );
  await _writeArchive(stored, archive);
  await _upsert(stored);
}

/// 이 프로젝트에서 쓰도록 붙인다. 공용 policy 는 이 프로젝트 것이 된다.
Future<void> bindWorkcellPolicy(
  String projectName,
  WorkcellPolicy policy,
) async {
  final existing = await _select('policy_id = ${_match(policy.id)}');
  if (existing.isEmpty) {
    throw StateError('보관함에서 ${policy.id} 를 찾을 수 없습니다.');
  }
  await _upsert(policy.copyWith(projectName: projectName));
}

/// 이 프로젝트에서 뗀다. Policy 자체는 공용으로 남는다.
///
/// 프로젝트를 지워도 policy 가 사라지면 안 되므로 여기서도 지우지 않는다.
Future<void> deleteWorkcellPolicy(
  String projectName,
  WorkcellPolicy policy,
) async {
  await _upsert(
    policy.copyWith(clearProject: true, deployedWorkcells: const []),
  );
}

/// 이 policy 를 쓰고 있는 프로젝트. 없으면 빈 목록이다.
Future<List<String>> globalPolicyReferences(String policyId) async {
  final policies = await _select('policy_id = ${_match(policyId)}');
  return [
    for (final policy in policies)
      if ((policy.projectName ?? '').isNotEmpty) policy.projectName!,
  ];
}

/// 목록에서도 디스크에서도 없앤다. 되돌릴 수 없다.
Future<void> deleteGlobalWorkcellPolicy(WorkcellPolicy policy) async {
  final references = await globalPolicyReferences(policy.id);
  if (references.isNotEmpty) {
    throw StateError('사용 중인 프로젝트: ${references.join(', ')}');
  }
  await _query(
    'DELETE FROM workcell_policies WHERE policy_id = ${_match(policy.id)};',
  );
  final directory = Directory('${_libraryRoot().path}/${policy.storagePath}');
  if (await directory.exists()) await directory.delete(recursive: true);
}

/// 이름·버전·물품·모델·소속 프로젝트를 고친다. 학습 결과 자체는 건드리지 않는다.
///
/// 이름을 바꿔도 ZIP 이 놓인 자리([WorkcellPolicy.storageKey])는 그대로다.
/// 수백 MB 를 옮기지 않으려는 것이고, 파일이 없는 자리에서도 이름만 고칠 수
/// 있어야 하기 때문이다.
Future<WorkcellPolicy> updateWorkcellPolicy({
  required WorkcellPolicy original,
  required WorkcellPolicy edited,
}) async {
  final all = await _select('1 = 1');
  final error = validatePolicyEdit(
    original: original,
    edited: edited,
    others: [
      for (final policy in all)
        if (policy.id != original.id) policy,
    ],
  );
  if (error != null) throw StateError(error);
  final stored = edited.copyWith(
    // 자리는 처음 들여놓을 때 정한 것을 그대로 쓴다.
    archiveMissing: original.archiveMissing,
  );
  if (stored.id != original.id) {
    await _query(
      'DELETE FROM workcell_policies WHERE policy_id = ${_match(original.id)};',
    );
  }
  await _upsert(stored);
  // manifest 도 같이 고쳐 둔다. 파일만 보고도 무엇인지 알 수 있어야 한다.
  final manifest = File(
    '${_libraryRoot().path}/${stored.storagePath}/manifest.json',
  );
  if (await manifest.parent.exists()) {
    await manifest.writeAsString(stored.globalManifest(), flush: true);
  }
  return _withArchiveState(stored);
}

/// 사람이 고른 ZIP 으로 빈 자리를 채운다.
Future<WorkcellPolicy> restorePolicyArchive(
  WorkcellPolicy policy,
  Uint8List bytes,
) async {
  final error = validatePolicyArchive(policy.archiveName, bytes);
  if (error != null) throw StateError(error);
  final restored = policy.copyWith(
    archiveBytes: bytes.length,
    archiveMissing: false,
  );
  await _writeArchive(restored, bytes);
  await _upsert(restored);
  return restored;
}

/// 목록에는 있으나 파일이 없는 policy 를 Hugging Face 에서 다시 받는다.
///
/// 처음 받을 때 적어 둔 저장소와 revision 을 그대로 쓴다. 같은 이름의 policy 가
/// 자리마다 다른 내용이 되면 작업 결과를 믿을 수 없기 때문이다.
Future<WorkcellPolicy> downloadPolicyArchive(
  WorkcellPolicy policy, {
  void Function(PolicyInstallProgress progress)? onProgress,
  PolicyInstallCancelToken? cancelToken,
}) async {
  final repository = policy.sourceRepository;
  if (repository == null || repository.isEmpty) {
    throw StateError(
      '${policy.id} 는 Hugging Face 에서 온 것이 아닙니다. ZIP 을 다시 올려 주세요.',
    );
  }
  final downloaded = await downloadHuggingFacePolicy(
    repositoryUrl: repository,
    revision: policy.sourceRevision,
    onProgress: onProgress,
    cancelToken: cancelToken,
  );
  onProgress?.call(
    PolicyInstallProgress(
      phase: PolicyInstallPhase.save,
      fileName: policy.archiveName,
    ),
  );
  final restored = policy.copyWith(
    archiveBytes: downloaded.bytes.length,
    archiveMissing: false,
  );
  await _writeArchive(restored, downloaded.bytes);
  await _upsert(restored);
  return restored;
}

// ---------------------------------------------------------------------------
// Hugging Face
// ---------------------------------------------------------------------------

/// Hugging Face 에서 policy 를 받아 ZIP 하나로 묶는다.
///
/// **화면 isolate 에서 하지 않는다.** 받는 것은 기다리는 일이라 괜찮지만, 받은
/// 것을 ZIP 으로 묶는 것은 CPU 를 통째로 쓰는 일이다. 그동안 화면은 한 프레임도
/// 그리지 못하고, 데스크톱이 "앱이 응답하지 않습니다 — 중지할까요?" 를 띄운다.
///
/// 실측(2026-08-17, 190MB safetensors 한 개) —
///
///     기본 압축(BEST_SPEED)  9,471ms   결과 190MB
///     압축 없이 담기            534ms   결과 190MB
///
/// 학습 결과는 이미 빽빽해서 **눌러도 줄지 않는다.** 9.5초를 들여 같은 크기를
/// 만들 이유가 없으므로 압축은 끄고([zipPolicyFiles]), 그마저도 일꾼 isolate
/// 에서 한다. 진행률은 포트로 돌려받아 화면이 계속 움직인다.
Future<HuggingFacePolicyDownload> downloadHuggingFacePolicy({
  required String repositoryUrl,
  String? revision,
  void Function(PolicyInstallProgress progress)? onProgress,
  PolicyInstallCancelToken? cancelToken,
}) async {
  // 주소가 틀린 것은 일꾼을 띄우기 전에 안다.
  if (parseHuggingFaceRepository(repositoryUrl) == null) {
    throw const FormatException('올바른 Hugging Face 모델 주소를 입력하세요.');
  }
  final incoming = ReceivePort();
  final result = Completer<HuggingFacePolicyDownload>();
  SendPort? control;
  var cancelRequested = false;
  cancelToken?.whenCancelled.then((_) {
    cancelRequested = true;
    control?.send('cancel');
  });
  void finish(FutureOr<HuggingFacePolicyDownload> Function() value) {
    if (result.isCompleted) return;
    incoming.close();
    try {
      result.complete(value());
    } catch (error) {
      result.completeError(error);
    }
  }

  incoming.listen((message) {
    if (message is SendPort) {
      control = message;
      // 포트가 오기 전에 눌렀을 수 있다. 그때는 지금 알린다.
      if (cancelRequested) message.send('cancel');
      return;
    }
    if (message is PolicyInstallProgress) {
      onProgress?.call(message);
      return;
    }
    // 일꾼이 죽으면 `onExit` 이 null 을 보낸다. 그냥 두면 설치 팝업이 영영
    // 안 닫히고, 그것이야말로 화면이 멈춘 것처럼 보이는 일이다.
    if (message == null) {
      finish(() => throw StateError('Policy 내려받기 일꾼이 갑자기 끝났습니다.'));
      return;
    }
    if (message is! List) return;
    switch (message.firstOrNull) {
      case 'done':
        finish(
          () => HuggingFacePolicyDownload(
            repositoryId: message[1] as String,
            revision: message[2] as String,
            fileName: message[3] as String,
            // 옮겨 받는다. 190MB 를 다시 복사하지 않는다.
            bytes: (message[4] as TransferableTypedData)
                .materialize()
                .asUint8List(),
          ),
        );
      case 'error':
        finish(() => throw StateError(message[1] as String));
      case 'cancelled':
        finish(() => throw const PolicyInstallCancelled());
      default:
        // `onError` 로 올라온 잡히지 않은 오류다.
        finish(() => throw StateError('${message.firstOrNull}'));
    }
  });
  try {
    await Isolate.spawn(
      _downloadWorker,
      [incoming.sendPort, repositoryUrl, revision],
      onError: incoming.sendPort,
      onExit: incoming.sendPort,
    );
  } catch (error) {
    incoming.close();
    rethrow;
  }
  return result.future;
}

/// 일꾼 isolate. 받고 묶어서 결과만 돌려준다.
Future<void> _downloadWorker(List<Object?> message) async {
  final send = message[0] as SendPort;
  final control = ReceivePort();
  final cancelToken = PolicyInstallCancelToken();
  control.listen((value) {
    if (value == 'cancel') cancelToken.cancel();
  });
  send.send(control.sendPort);
  try {
    final downloaded = await _downloadHuggingFacePolicy(
      repositoryUrl: message[1] as String,
      revision: message[2] as String?,
      onProgress: send.send,
      cancelToken: cancelToken,
    );
    send.send(<Object?>[
      'done',
      downloaded.repositoryId,
      downloaded.revision,
      downloaded.fileName,
      TransferableTypedData.fromList([downloaded.bytes]),
    ]);
  } on PolicyInstallCancelled {
    send.send(const <Object?>['cancelled']);
  } catch (error) {
    send.send(<Object?>['error', '$error']);
  } finally {
    control.close();
  }
}

/// 받은 파일들을 ZIP 하나로 담는다. **누르지 않는다.**
///
/// 학습 결과는 이미 빽빽해서 눌러도 줄지 않는데, 누르는 데만 열 배 넘는 시간이
/// 든다(위 실측). ZIP 은 여기서 그저 여러 파일을 하나로 묶는 상자다.
Uint8List zipPolicyFiles(Archive archive) {
  for (final file in archive.files) {
    file.compress = false;
  }
  final zipped = ZipEncoder().encode(archive);
  if (zipped == null) {
    throw const FileSystemException('Policy ZIP 생성에 실패했습니다.');
  }
  return zipped is Uint8List ? zipped : Uint8List.fromList(zipped);
}

Future<HuggingFacePolicyDownload> _downloadHuggingFacePolicy({
  required String repositoryUrl,
  String? revision,
  void Function(PolicyInstallProgress progress)? onProgress,
  PolicyInstallCancelToken? cancelToken,
}) async {
  final repo = parseHuggingFaceRepository(repositoryUrl);
  if (repo == null) {
    throw const FormatException('올바른 Hugging Face 모델 주소를 입력하세요.');
  }
  onProgress?.call(
    const PolicyInstallProgress(phase: PolicyInstallPhase.metadata),
  );
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 20);
  try {
    // blobs=true 를 붙여야 siblings 에 파일 크기가 함께 온다. 크기를 알아야
    // 몇 %까지 왔는지 셀 수 있다. 다시 받는 것이라면 그때의 revision 을 박아
    // 같은 내용을 가져온다.
    final pinned = (revision ?? '').trim();
    final metadataUri = Uri.parse(
      pinned.isEmpty
          ? 'https://huggingface.co/api/models/$repo?blobs=true'
          : 'https://huggingface.co/api/models/$repo/revision/'
                '${Uri.encodeComponent(pinned)}?blobs=true',
    );
    final metadata =
        jsonDecode(
              utf8.decode(await _get(client, metadataUri, cancel: cancelToken)),
            )
            as Map<String, dynamic>;
    final resolved = pinned.isNotEmpty
        ? pinned
        : metadata['sha'] as String? ?? 'main';
    final siblings = metadata['siblings'] as List<dynamic>? ?? const [];
    final files = <String>[
      for (final item in siblings)
        if (item is Map && item['rfilename'] is String)
          item['rfilename'] as String,
    ].where(_includeHubFile).toList();
    final sizes = <String, int>{
      for (final item in siblings)
        if (item is Map && item['rfilename'] is String && item['size'] is num)
          item['rfilename'] as String: (item['size'] as num).toInt(),
    };
    if (!files.contains('config.json') ||
        !files.contains('model.safetensors')) {
      throw const FormatException(
        'LeRobot policy 필수 파일(config.json, model.safetensors)이 없습니다.',
      );
    }
    // 크기를 모르는 파일이 하나라도 있으면 바이트 비율이 어긋난다. 그때는 0으로
    // 두어 파일 개수로 세게 한다.
    final expected = files.every(sizes.containsKey)
        ? files.fold<int>(0, (sum, file) => sum + sizes[file]!)
        : 0;
    const limit = 1024 * 1024 * 1024;
    var total = 0;
    var completed = 0;
    final archive = Archive();
    for (final file in files) {
      cancelToken?.throwIfCancelled();
      void report(int received) => onProgress?.call(
        PolicyInstallProgress(
          phase: PolicyInstallPhase.download,
          receivedBytes: total + received,
          totalBytes: expected,
          fileName: file,
          completedFiles: completed,
          totalFiles: files.length,
        ),
      );

      report(0);
      final encoded = file.split('/').map(Uri.encodeComponent).join('/');
      final uri = Uri.parse(
        'https://huggingface.co/$repo/resolve/$resolved/$encoded',
      );
      final bytes = await _get(
        client,
        uri,
        limit: limit - total,
        cancel: cancelToken,
        onChunk: report,
      );
      total += bytes.length;
      completed += 1;
      if (total > limit) {
        throw const FileSystemException('Policy ZIP은 1GB 이하여야 합니다.');
      }
      archive.addFile(ArchiveFile(file, bytes.length, bytes));
    }
    cancelToken?.throwIfCancelled();
    onProgress?.call(
      PolicyInstallProgress(
        phase: PolicyInstallPhase.archive,
        receivedBytes: total,
        totalBytes: expected == 0 ? total : expected,
        completedFiles: files.length,
        totalFiles: files.length,
      ),
    );
    return HuggingFacePolicyDownload(
      repositoryId: repo,
      revision: resolved,
      fileName: '${repo.split('/').last}.zip',
      bytes: zipPolicyFiles(archive),
    );
  } finally {
    client.close(force: true);
  }
}

bool _includeHubFile(String file) =>
    file.isNotEmpty &&
    !file.startsWith('.') &&
    !file.split('/').contains('..') &&
    !file.toLowerCase().endsWith('.zip');

/// 진행률을 알리는 간격. 덩어리마다 알리면 화면이 초당 수천 번 다시 그려진다.
const int _progressReportBytes = 512 * 1024;

Future<Uint8List> _get(
  HttpClient client,
  Uri uri, {
  int? limit,
  void Function(int received)? onChunk,
  PolicyInstallCancelToken? cancel,
}) async {
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
  final builder = BytesBuilder(copy: false);
  var reported = 0;
  await for (final chunk in response) {
    if (cancel != null && cancel.isCancelled) {
      await response.drain<void>();
      throw const PolicyInstallCancelled();
    }
    if (limit != null && builder.length + chunk.length > limit) {
      throw const FileSystemException('Policy ZIP은 1GB 이하여야 합니다.');
    }
    builder.add(chunk);
    if (onChunk != null && builder.length - reported >= _progressReportBytes) {
      reported = builder.length;
      onChunk(reported);
    }
  }
  onChunk?.call(builder.length);
  return builder.takeBytes();
}
