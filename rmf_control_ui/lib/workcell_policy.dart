library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

class WorkcellPolicy {
  const WorkcellPolicy({
    required this.name,
    required this.version,
    required this.objectType,
    required this.robotModel,
    required this.archiveName,
    required this.archiveBytes,
    required this.deployedWorkcells,
    required this.createdAt,
    this.sourceRepository,
    this.sourceRevision,
    this.projectName,
    this.storageKey = '',
    this.archiveMissing = false,
  });

  final String name;
  final String version;
  final String objectType;
  final String robotModel;
  final String archiveName;
  final int archiveBytes;
  final List<String> deployedWorkcells;
  final DateTime createdAt;
  final String? sourceRepository;
  final String? sourceRevision;

  /// 이 policy 를 가진 프로젝트. null 이면 어느 프로젝트에도 매이지 않은 공용.
  ///
  /// Policy 는 프로젝트보다 오래 남는 자산이다. 프로젝트를 지워도 policy 는
  /// 남고, 여기만 고쳐 다른 프로젝트로 옮길 수 있다.
  final String? projectName;

  /// ZIP 이 놓인 폴더 이름. 비어 있으면 이름과 버전에서 만든다.
  ///
  /// 이름을 바꿔도 이 값은 그대로 둔다. 수백 MB 를 옮기지 않으려는 것이다.
  final String storageKey;

  /// 디스크에 ZIP 이 없는 상태. 목록을 읽을 때 확인해 채운다.
  ///
  /// ZIP 은 git 에 올리지 않으므로 다른 자리에서 받은 저장소에는 기본 정보만
  /// 있고 파일이 없다. 이때 Hugging Face 에서 다시 받게 한다.
  final bool archiveMissing;

  String get id => '$name@$version';
  bool get isDeployed => deployedWorkcells.isNotEmpty;

  /// 실제 폴더 이름. [storageKey] 가 비었으면 이름과 버전에서 만든다.
  String get storagePath =>
      storageKey.isEmpty ? policyStorageKey(name, version) : storageKey;

  /// 다시 받아 올 곳을 아는가. 사람이 올린 ZIP 은 받아 올 데가 없다.
  bool get canDownload => (sourceRepository ?? '').isNotEmpty;

  WorkcellPolicy copyWith({
    String? name,
    String? version,
    String? objectType,
    String? robotModel,
    String? projectName,
    bool clearProject = false,
    List<String>? deployedWorkcells,
    String? archiveName,
    int? archiveBytes,
    bool? archiveMissing,
  }) => WorkcellPolicy(
    name: name ?? this.name,
    version: version ?? this.version,
    objectType: objectType ?? this.objectType,
    robotModel: robotModel ?? this.robotModel,
    archiveName: archiveName ?? this.archiveName,
    archiveBytes: archiveBytes ?? this.archiveBytes,
    deployedWorkcells: deployedWorkcells ?? this.deployedWorkcells,
    createdAt: createdAt,
    sourceRepository: sourceRepository,
    sourceRevision: sourceRevision,
    projectName: clearProject ? null : (projectName ?? this.projectName),
    // 이름을 바꿔도 파일이 놓인 자리는 그대로다.
    storageKey: storagePath,
    archiveMissing: archiveMissing ?? this.archiveMissing,
  );

  Map<String, Object?> toJson() => {
    'policyId': id,
    'name': name,
    'version': version,
    'objectType': objectType,
    'robotModel': robotModel,
    'archiveName': archiveName,
    'archiveBytes': archiveBytes,
    'deployedWorkcells': deployedWorkcells,
    'createdAt': createdAt.toIso8601String(),
    'sourceRepository': sourceRepository,
    'sourceRevision': sourceRevision,
    'projectName': projectName,
    'storageKey': storagePath,
  };

  String manifest(String projectName) => const JsonEncoder.withIndent(
    '  ',
  ).convert({...toJson(), 'project': projectName, 'policyId': id});

  String globalManifest() => const JsonEncoder.withIndent(
    '  ',
  ).convert({...toJson(), 'scope': 'global', 'policyId': id});

  static WorkcellPolicy fromJson(Map<String, dynamic> json) => WorkcellPolicy(
    name: json['name'] as String,
    version: json['version'] as String,
    objectType: json['objectType'] as String? ?? '',
    robotModel: json['robotModel'] as String? ?? '',
    archiveName: json['archiveName'] as String? ?? 'policy.zip',
    archiveBytes: (json['archiveBytes'] as num?)?.toInt() ?? 0,
    deployedWorkcells: [
      for (final value
          in json['deployedWorkcells'] as List<dynamic>? ?? const [])
        value.toString(),
    ],
    createdAt:
        DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
    sourceRepository: json['sourceRepository'] as String?,
    sourceRevision: json['sourceRevision'] as String?,
    projectName: json['projectName'] as String?,
    storageKey: json['storageKey'] as String? ?? '',
    archiveMissing: json['archiveMissing'] as bool? ?? false,
  );
}

/// 파일 이름에 쓸 수 있게 다듬는다. 이름에 공백이나 `/` 가 들어와도 안전하다.
String safePolicySegment(String value) =>
    value.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');

/// ZIP 을 둘 폴더 이름. 처음 들여놓을 때 한 번 정하고 그대로 쓴다.
String policyStorageKey(String name, String version) =>
    '${safePolicySegment(name)}/${safePolicySegment(version)}';

/// Policy 설치가 지금 어느 단계에 있는지.
enum PolicyInstallPhase {
  metadata('파일 목록 확인 중'),
  download('내려받는 중'),
  archive('ZIP으로 묶는 중'),
  save('저장·배포 중'),
  done('완료');

  const PolicyInstallPhase(this.label);

  final String label;
}

/// Policy 설치 진행률.
///
/// LeRobot policy 는 `model.safetensors` 하나가 수백 MB라 내려받는 데 몇 분씩
/// 걸린다. 도는 원만 보이면 받고 있는 것인지 멈춘 것인지 알 수 없어 몇 %까지
/// 왔는지 막대로 보여준다.
///
/// 단계마다 화면에서 차지하는 구간이 다르다. 시간을 거의 다 쓰는 것은
/// 내려받기라 [PolicyInstallPhase.download] 에 가장 넓은 구간을 준다. 그래야
/// 막대가 초반에 멈춘 듯 보이거나 끝에서 갑자기 튀지 않는다.
class PolicyInstallProgress {
  const PolicyInstallProgress({
    required this.phase,
    this.receivedBytes = 0,
    this.totalBytes = 0,
    this.fileName = '',
    this.completedFiles = 0,
    this.totalFiles = 0,
  });

  final PolicyInstallPhase phase;

  /// 지금까지 받은 바이트. 여러 파일을 합친 값이다.
  final int receivedBytes;

  /// 받아야 할 전체 바이트. Hugging Face 가 파일 크기를 알려주지 않으면 0이고,
  /// 그때는 파일 개수로 센다.
  final int totalBytes;

  final String fileName;
  final int completedFiles;
  final int totalFiles;

  /// 각 단계가 차지하는 구간 [시작, 끝].
  static const Map<PolicyInstallPhase, List<double>> _spans = {
    PolicyInstallPhase.metadata: [0, .03],
    PolicyInstallPhase.download: [.03, .85],
    PolicyInstallPhase.archive: [.85, .95],
    PolicyInstallPhase.save: [.95, 1],
    PolicyInstallPhase.done: [1, 1],
  };

  /// 단계 안에서의 진행률(0~1). 잴 수 없으면 0이다.
  double get _inner {
    if (phase != PolicyInstallPhase.download) return 0;
    if (totalBytes > 0) return (receivedBytes / totalBytes).clamp(0.0, 1.0);
    if (totalFiles > 0) return (completedFiles / totalFiles).clamp(0.0, 1.0);
    return 0;
  }

  /// 막대에 그대로 넣는 값(0~1).
  double get ratio {
    final span = _spans[phase]!;
    return (span[0] + (span[1] - span[0]) * _inner).clamp(0.0, 1.0);
  }

  int get percent => (ratio * 100).round();

  /// 막대 아래에 적는 한 줄. 지금 무엇을 받고 있는지 보여준다.
  String get detail {
    if (phase != PolicyInstallPhase.download) return fileName;
    final where = totalBytes > 0
        ? '${formatPolicyBytes(receivedBytes)} / ${formatPolicyBytes(totalBytes)}'
        : '$completedFiles/$totalFiles 파일';
    return fileName.isEmpty ? where : '$fileName · $where';
  }
}

/// 설치를 도중에 그만두게 하는 표. 1GB 를 받다가도 취소할 수 있어야 한다.
///
/// 내려받기는 화면과 다른 isolate 에서 돈다. 표를 세우는 쪽(화면)과 보는
/// 쪽(일꾼)이 갈려 있으므로, 세워진 순간을 알 수 있게 [whenCancelled] 를 둔다.
class PolicyInstallCancelToken {
  final Completer<void> _completer = Completer<void>();

  bool get isCancelled => _completer.isCompleted;

  /// 취소를 누른 순간 끝난다. 일꾼에게 그때 알린다.
  Future<void> get whenCancelled => _completer.future;

  void cancel() {
    if (!_completer.isCompleted) _completer.complete();
  }

  void throwIfCancelled() {
    if (isCancelled) throw const PolicyInstallCancelled();
  }
}

class PolicyInstallCancelled implements Exception {
  const PolicyInstallCancelled();

  @override
  String toString() => 'Policy 설치를 취소했습니다.';
}

/// 바이트를 사람이 읽는 크기로. 1MB 미만은 KB로 적어야 0.0MB 가 되지 않는다.
String formatPolicyBytes(int bytes) {
  if (bytes >= 1024 * 1024) {
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)}MB';
  }
  return '${(bytes / 1024).toStringAsFixed(0)}KB';
}

class HuggingFacePolicyDownload {
  const HuggingFacePolicyDownload({
    required this.repositoryId,
    required this.revision,
    required this.fileName,
    required this.bytes,
  });
  final String repositoryId;
  final String revision;
  final String fileName;
  final Uint8List bytes;
}

/// Hugging Face 모델 URL 또는 `owner/name`을 정규화한다.
String? parseHuggingFaceRepository(String value) {
  final input = value.trim();
  final direct = RegExp(
    r'^([A-Za-z0-9_.-]+)/([A-Za-z0-9_.-]+)$',
  ).firstMatch(input);
  if (direct != null) return '${direct.group(1)}/${direct.group(2)}';
  final uri = Uri.tryParse(input);
  if (uri == null || uri.scheme != 'https' || uri.host != 'huggingface.co') {
    return null;
  }
  final parts = uri.pathSegments.where((part) => part.isNotEmpty).toList();
  if (parts.length < 2 ||
      !RegExp(r'^[A-Za-z0-9_.-]+$').hasMatch(parts[0]) ||
      !RegExp(r'^[A-Za-z0-9_.-]+$').hasMatch(parts[1])) {
    return null;
  }
  return '${parts[0]}/${parts[1]}';
}

String? validatePolicyArchive(String fileName, Uint8List bytes) {
  if (!fileName.toLowerCase().endsWith('.zip')) return 'ZIP 파일만 올릴 수 있습니다.';
  if (bytes.length < 4 ||
      bytes[0] != 0x50 ||
      bytes[1] != 0x4b ||
      !({0x03, 0x05, 0x07}.contains(bytes[2]))) {
    return '올바른 ZIP 파일이 아닙니다.';
  }
  if (bytes.length > 1024 * 1024 * 1024) return 'Policy ZIP은 1GB 이하여야 합니다.';
  return null;
}

/// 기본 정보를 고칠 때 막아야 할 것. 문제가 없으면 null.
///
/// 고치는 것은 이름표뿐이고 학습 결과는 그대로다. 다만 `이름@버전` 이 작업에서
/// policy 를 가리키는 열쇠라 이미 있는 것과 겹치면 안 된다.
String? validatePolicyEdit({
  required WorkcellPolicy original,
  required WorkcellPolicy edited,
  required List<WorkcellPolicy> others,
}) {
  final nameError = validatePolicyName(edited.name);
  if (nameError != null) return nameError;
  if (edited.version.trim().isEmpty) return '버전을 입력하세요.';
  if (edited.robotModel.trim().isEmpty) return '호환 로봇팔 모델을 입력하세요.';
  if (edited.id != original.id && others.any((item) => item.id == edited.id)) {
    return '${edited.id} 는 이미 있습니다. 이름이나 버전을 다르게 하세요.';
  }
  return null;
}

String? validatePolicyName(String value) {
  if (value.trim().isEmpty) return 'Policy 이름을 입력하세요.';
  if (!RegExp(r'^[A-Za-z0-9][A-Za-z0-9_-]*$').hasMatch(value.trim())) {
    return '이름은 영문·숫자로 시작하고 영문·숫자·밑줄·하이픈만 사용할 수 있습니다.';
  }
  return null;
}

List<String> deployedPolicyIds(List<WorkcellPolicy> policies) => [
  for (final policy in policies)
    if (policy.isDeployed) policy.id,
];

/// 이 WorkCell 에 붙어 있는 policy.
///
/// Policy 는 프로젝트에 연결하는 것과 WorkCell 에 붙이는 것이 다르다. 프로젝트에
/// 들여놓기만 한 policy 는 어느 설비도 쓰지 않는다. 실제로 쓰려면 로봇 관리에서
/// 그 WorkCell 에 붙여야 하고, 작업의 픽업 단계는 그렇게 붙은 것 중에서 고른다.
List<WorkcellPolicy> policiesForWorkcell(
  List<WorkcellPolicy> policies,
  String robotId,
) => [
  for (final policy in policies)
    if (policy.deployedWorkcells.contains(robotId)) policy,
];

/// 이 WorkCell 에 더 붙일 수 있는 policy.
///
/// 로봇팔 모델이 다르면 학습한 관절이 달라 그대로 돌릴 수 없으므로 아예 내밀지
/// 않는다. 프로젝트 목록과 전역 보관함을 합쳐 넘기면 같은 policy 가 두 번 나오지
/// 않게 걸러 준다.
List<WorkcellPolicy> policyCandidatesForWorkcell({
  required List<WorkcellPolicy> policies,
  required String robotId,
  required String robotModel,
}) {
  final seen = <String>{};
  return [
    for (final policy in policies)
      if (policy.robotModel == robotModel &&
          !policy.deployedWorkcells.contains(robotId) &&
          seen.add(policy.id))
        policy,
  ];
}

/// 픽업 단계에서 고를 수 있는 policy.
///
/// 설비마다 붙여 둔 policy 가 다르다. 그 자리를 맡는 설비가 무엇인지 알면
/// 그 설비의 것만, 모르면 프로젝트에 붙어 있는 것을 모두 보여 준다.
class WorkcellPolicyChoices {
  const WorkcellPolicyChoices({
    required this.policyIds,
    this.workcellId,
    this.station,
    this.fallback = false,
  });

  final List<String> policyIds;

  /// 이 자리를 맡는 설비. 모르면 null 이고, 그때는 전체를 보여 준 것이다.
  final String? workcellId;

  final String? station;

  /// 붙여 둔 policy 가 없어 기본 동작을 내민 것인가.
  final bool fallback;

  /// 어느 설비의 것인지 좁혀서 고르고 있는가.
  bool get scoped => workcellId != null;

  /// 이 자리에서 쓸 수 없는 policy 를 고른 상태인가.
  bool rejects(String policyId) =>
      scoped && !fallback && !policyIds.contains(policyId);
}

/// [station] 자리에서 고를 수 있는 policy 를 추린다.
///
/// 붙여 둔 것이 하나도 없으면 [fallbackPolicyIds](생성된 워크셀 노드가 늘 갖는
/// 기본 동작)를 준다. 아무것도 못 고르게 하면 작업 자체를 만들 수 없기 때문이다.
WorkcellPolicyChoices policyChoicesForStation({
  required String? station,
  required Map<String, String> workcellsByStation,
  required List<WorkcellPolicy> policies,
  List<String> fallbackPolicyIds = const [],
}) {
  final workcell = station == null ? null : workcellsByStation[station];
  final scoped = workcell == null
      ? deployedPolicyIds(policies)
      : [
          for (final policy in policiesForWorkcell(policies, workcell))
            policy.id,
        ];
  return WorkcellPolicyChoices(
    policyIds: scoped.isEmpty ? fallbackPolicyIds : scoped,
    workcellId: workcell,
    station: station,
    fallback: scoped.isEmpty,
  );
}

/// policy 를 이 WorkCell 에 붙인 사본. 이미 붙어 있으면 물품 이름만 고친다.
WorkcellPolicy attachPolicyToWorkcell(
  WorkcellPolicy policy,
  String robotId, {
  String? objectType,
}) => policy.copyWith(
  objectType: objectType?.trim().isEmpty ?? true ? null : objectType!.trim(),
  deployedWorkcells: policy.deployedWorkcells.contains(robotId)
      ? policy.deployedWorkcells
      : [...policy.deployedWorkcells, robotId],
);

/// policy 를 이 WorkCell 에서 뗀 사본.
///
/// 프로젝트 연결은 그대로 둔다. 뗀 것은 다른 WorkCell 에 다시 붙일 수 있어야
/// 하고, 전역 보관함의 원본도 건드리지 않는다.
WorkcellPolicy detachPolicyFromWorkcell(
  WorkcellPolicy policy,
  String robotId,
) => policy.copyWith(
  deployedWorkcells: [
    for (final id in policy.deployedWorkcells)
      if (id != robotId) id,
  ],
);
