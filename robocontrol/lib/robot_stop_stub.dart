/// 웹에서는 ROS 프로세스를 띄울 수 없다.
library;

Future<({bool ok, String output})> stopRobotMotion({
  required String namespace,
  required int rosDomainId,
}) async => (ok: false, output: '이 판에서는 로봇 정지를 보낼 수 없습니다.');
