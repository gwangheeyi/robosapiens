/// 웹에서는 프로세스를 띄울 수 없다.
library;

import 'robot_nudge.dart';

Future<({bool ok, String output})> nudgeRobot({
  required String namespace,
  required NudgeKind kind,
  required double meters,
  required double degrees,
  required int rosDomainId,
}) async => (ok: false, output: '이 판에서는 미세조종을 쓸 수 없습니다.');
