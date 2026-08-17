import 'dart:typed_data';
import 'workcell_policy.dart';

Future<List<WorkcellPolicy>> loadWorkcellPolicies(String projectName) async =>
    [];
Future<List<WorkcellPolicy>> loadGlobalWorkcellPolicies() async => [];
Future<List<WorkcellPolicy>> loadUnassignedWorkcellPolicies() async => [];
Future<void> saveWorkcellPolicy(
  String projectName,
  WorkcellPolicy policy,
  Uint8List archive,
) async {}
Future<void> deleteWorkcellPolicy(
  String projectName,
  WorkcellPolicy policy,
) async {}
Future<void> bindWorkcellPolicy(
  String projectName,
  WorkcellPolicy policy,
) async {}
Future<List<String>> globalPolicyReferences(String policyId) async => [];
Future<void> deleteGlobalWorkcellPolicy(WorkcellPolicy policy) async {}
String policyArchivePath(WorkcellPolicy policy) => '';
Future<WorkcellPolicy> updateWorkcellPolicy({
  required WorkcellPolicy original,
  required WorkcellPolicy edited,
}) => throw UnsupportedError('이 플랫폼에서는 Policy 정보를 고칠 수 없습니다.');
Future<WorkcellPolicy> restorePolicyArchive(
  WorkcellPolicy policy,
  Uint8List bytes,
) => throw UnsupportedError('이 플랫폼에서는 Policy ZIP 을 저장할 수 없습니다.');
Future<WorkcellPolicy> downloadPolicyArchive(
  WorkcellPolicy policy, {
  void Function(PolicyInstallProgress progress)? onProgress,
  PolicyInstallCancelToken? cancelToken,
}) => throw UnsupportedError('이 플랫폼에서는 Hugging Face 다운로드를 지원하지 않습니다.');
Future<HuggingFacePolicyDownload> downloadHuggingFacePolicy({
  required String repositoryUrl,
  String? revision,
  void Function(PolicyInstallProgress progress)? onProgress,
  PolicyInstallCancelToken? cancelToken,
}) => throw UnsupportedError('이 플랫폼에서는 Hugging Face 다운로드를 지원하지 않습니다.');
