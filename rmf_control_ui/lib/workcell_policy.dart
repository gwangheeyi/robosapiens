library;

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

  String get id => '$name@$version';
  bool get isDeployed => deployedWorkcells.isNotEmpty;

  Map<String, Object?> toJson() => {
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
  };

  String manifest(String projectName) => const JsonEncoder.withIndent(
    '  ',
  ).convert({...toJson(), 'project': projectName, 'policyId': id});

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
  );
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
