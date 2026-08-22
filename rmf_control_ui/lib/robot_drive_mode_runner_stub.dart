Future<({bool ok, String output})> applyRobotDriveMode({
  required String mapDirectory,
  required String robotDirectory,
  required String namespace,
  required String nav2Params,
}) async => (ok: false, output: '이 환경에서는 Nav2 주행 모드를 바꿀 수 없습니다.');
