import 'nav2_direct_control.dart';

Future<({bool ok, String output})> sendNav2DirectGoal({
  required Nav2DirectGoal goal,
  required int rosDomainId,
}) async => (ok: false, output: '이 플랫폼에서는 ROS 2 action을 실행할 수 없습니다.');
