class Nav2ProjectRunResult {
  const Nav2ProjectRunResult({required this.success, required this.message});
  final bool success;
  final String message;
}

Future<Nav2ProjectRunResult> startNav2Project({
  required String mapName,
  required String mapDirectory,
  required int rosDomainId,
}) async => const Nav2ProjectRunResult(
  success: false,
  message: '이 플랫폼에서는 Nav2를 실행할 수 없습니다.',
);
