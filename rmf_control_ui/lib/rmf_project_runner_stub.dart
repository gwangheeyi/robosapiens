/// 웹 빌드용 대체 구현. 브라우저에서는 프로세스를 띄울 수 없다.
library;

class RmfRunResult {
  const RmfRunResult({required this.success, required this.message});
  final bool success;
  final String message;
}

String? get runningProjectName => null;

Future<RmfRunResult> startProject(String mapName) async => const RmfRunResult(
  success: false,
  message: '웹 빌드에서는 프로젝트를 띄울 수 없습니다. Linux 데스크톱 앱에서 실행하세요.',
);

Future<RmfRunResult> stopProject([String? mapName]) async =>
    const RmfRunResult(success: false, message: '웹 빌드에서는 중지할 것이 없습니다.');
