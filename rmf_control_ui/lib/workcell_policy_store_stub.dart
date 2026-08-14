import 'dart:typed_data';
import 'workcell_policy.dart';

Future<List<WorkcellPolicy>> loadWorkcellPolicies(String projectName) async =>
    [];
Future<void> saveWorkcellPolicy(
  String projectName,
  WorkcellPolicy policy,
  Uint8List archive,
) async {}
Future<void> deleteWorkcellPolicy(
  String projectName,
  WorkcellPolicy policy,
) async {}
Future<HuggingFacePolicyDownload> downloadHuggingFacePolicy({
  required String repositoryId,
  required String revision,
  required String fileName,
}) => throw UnsupportedError('이 플랫폼에서는 Hugging Face 다운로드를 지원하지 않습니다.');
