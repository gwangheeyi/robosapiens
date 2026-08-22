/// 백엔드가 안 떴을 때의 진단이 **엉뚱한 곳을 짚지 않게** 한다.
///
/// 예전에는 로그에 컨트롤러 형식 이름이 보이기만 하면 문제라고 했다. 그 이름은
/// 정상으로 뜰 때도 찍힌다 —
///
///     Loading controller : 'gripper_controller' of type
///       'position_controllers/GripperActionController'
///     [Deprecated]: the `position_controllers/...` are replaced by ...
///
/// 그래서 실제로는 세 컨트롤러가 모두 `active` 인데도 "플러그인을 못 찾았다",
/// "형식이 잘못됐다" 가 떴고, **이미 깔려 있는** 패키지를 `apt install` 하라고
/// 시켰다(2026-08-17). 그날의 진짜 원인은 로그 아래쪽에 있던
/// `지도 서버를 90 초 안에 켜지 못했습니다` 였다.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:robocontrol/rmf_project_runner.dart';

/// 컨트롤러가 **정상으로** 올라올 때 나오는 로그.
const String _healthyLog = '''
[gazebo-1] [INFO] [omx_01.controller_manager]: Loading controller : 'arm_controller' of type 'joint_trajectory_controller/JointTrajectoryController'
[gazebo-1] [INFO] [omx_01.controller_manager]: Loading controller : 'gripper_controller' of type 'position_controllers/GripperActionController'
[gazebo-1] [WARN] [omx_01.gripper_controller]: [Deprecated]: the `position_controllers/GripperActionController` and `effort_controllers::GripperActionController` controllers are replaced by 'parallel_gripper_controllers/GripperActionController' controller
''';

/// 지도 서버에서 막혔을 때 실행 스크립트가 남기는 자국.
const String _mapServerLog = '''
지도 서버를 90 초 안에 켜지 못했습니다.
지도가 없으면 AMCL 이 map → <로봇>/odom 을 못 내고, 어댑터는 로봇의
위치를 몰라 플릿에 등록하지 못합니다.
RMF fleet state에 pinky_01 등록이 없습니다.
''';

/// 컨트롤러를 정말 못 올렸을 때.
const String _loaderFailedLog = '''
[gazebo-1] [ERROR] [omx_01.controller_manager]: Loader for controller 'arm_controller' (type 'joint_trajectory_controller/JointTrajectoryController') not available.
''';

Future<String> _diagnose(String log) async {
  final root = Directory.systemTemp.createTempSync('diagnose');
  addTearDown(() => root.deleteSync(recursive: true));
  // 진단기는 RMF_ROOT/rmf_maps/<맵>/<맵>.err.log 를 읽는다.
  final directory = Directory('${root.path}/rmf_maps/demo')
    ..createSync(recursive: true);
  File('${directory.path}/demo.err.log').writeAsStringSync(log);
  debugProjectRootOverride = root.path;
  addTearDown(() => debugProjectRootOverride = null);
  return diagnoseProjectBackendFailure('demo');
}

void main() {
  test('정상으로 올라온 컨트롤러를 문제라고 하지 않는다', () async {
    final report = await _diagnose(_healthyLog);
    expect(report, isNot(contains('플러그인을 찾지 못했습니다')));
    expect(report, isNot(contains('형식이')));
    // 있지도 않은 클래스 이름을 쓰라고 하지 않는다. `gripper_controllers`
    // 패키지가 내보내는 이름은 `position_controllers/GripperActionController` 다.
    expect(
      report,
      isNot(contains('gripper_controllers/GripperActionController')),
    );
    // 이미 깔린 패키지를 깔라고 시키지 않는다.
    expect(
      report,
      isNot(contains('apt install ros-jazzy-gripper-controllers')),
    );
  });

  test('진짜 못 올렸을 때는 짚어 준다', () async {
    final report = await _diagnose(_loaderFailedLog);
    expect(report, contains('arm_controller'));
  });

  test('지도 서버에서 막힌 것을 원인으로 말한다', () async {
    final report = await _diagnose(_mapServerLog);
    expect(report, contains('map_server'));
    // 왜 시간이 모자랐는지(시뮬 시각)와 무엇을 하면 되는지까지 적는다.
    expect(report, contains('시뮬'));
    expect(report, contains('MAP_SERVER_WAIT'));
    // 플릿 등록 실패는 그 결과라는 것도 함께 밝힌다.
    expect(report, contains('fleet adapter'));
  });

  test('노드는 살았는데 서비스가 안 보이면 탐색이 무너진 것으로 짚는다', () async {
    // 이번에 실제로 겪은 모양이다. map_server 프로세스는 멀쩡히 살아 있는데
    // lifecycle manager 가 그 서비스를 영영 못 찾았다.
    final report = await _diagnose(
      '[lifecycle_manager-2] [INFO] [lifecycle_manager_map]: '
      'Waiting for service map_server/get_state...\n',
    );
    expect(report, contains('DDS'));
    expect(report, contains('공유메모리'));
    // 무엇을 하면 되는지 명령까지 준다.
    expect(report, contains('/dev/shm/fastrtps_*'));
  });

  test('알려진 자국이 없으면 아는 척하지 않는다', () async {
    final report = await _diagnose('[gazebo-2] libEGL warning: dri2 screen\n');
    expect(report, contains('자동으로 특정하지 못했습니다'));
  });
}
