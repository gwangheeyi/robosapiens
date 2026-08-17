/// 핑키에 카메라를 달지 않는다.
///
/// 라이다를 살리려고 월드에 `gz::sim::systems::Sensors` 를 넣은 뒤로, 벤더
/// xacro 의 1280×720@30Hz `always_on` 카메라가 매 프레임 렌더됐다.
/// 실측(2026-08-17, project1-ver2 월드) —
///
///     real_time_factor: 0.16   시뮬이 실시간의 16% 로 돈다
///     gz sim 서버 107% CPU     GUI 70% CPU
///
/// 그런데 그 그림을 받는 곳이 없다 — 브리지에도 없고 릴레이는 `/scan` 만
/// 구독한다. 아무도 안 보는 그림 때문에 시뮬이 1/6 속도로 돌았고, 그만큼
/// 백엔드가 뜨는 것도 팔이 궤적을 끝내는 것도 늦어졌다.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rmf_control_ui/rmf_project_config.dart';

const RmfProjectRobot _pinky = RmfProjectRobot(
  robotId: 'pinky_01',
  displayName: '핑키 1호',
  model: 'pinky',
  gzName: 'pinky_01',
  zones: [],
  kind: RmfRobotKind.mobile,
  dataSource: RobotDataSource.gazebo,
  spawnX: 1,
  spawnY: -1,
);

/// 벤더 xacro 를 펼치면 나오는 모양 그대로.
const String _vendorUrdf = '''
<robot name="pinky">
  <link name="base_footprint"/>
  <gazebo reference="front_camera_link">
    <sensor name="pinky_01/camera" type="camera">
      <camera>
        <horizontal_fov>1.1519</horizontal_fov>
        <image>
          <width>1280</width>
          <height>720</height>
        </image>
      </camera>
      <always_on>1</always_on>
      <update_rate>30</update_rate>
      <visualize>true</visualize>
      <topic>pinky_01/camera/image_raw</topic>
    </sensor>
  </gazebo>
  <gazebo reference="rplidar_link">
    <sensor name="pinky_01/gpu_lidar" type="gpu_lidar">
      <always_on>1</always_on>
      <update_rate>10</update_rate>
    </sensor>
  </gazebo>
</robot>
''';

void main() {
  test('생성된 스크립트가 카메라를 끈 채로 넘긴다', () {
    final script = buildRobotDescriptionScript(_pinky);
    expect(cameraEnabled, isFalse);
    expect(script, contains('CAM_ENABLED="\${CAM_ENABLED:-0}"'));
    // 되살릴 때 붙을 값도 함께 남겨 둔다.
    expect(script, contains('CAM_WIDTH="\${CAM_WIDTH:-640}"'));
    expect(script, contains('CAM_HEIGHT="\${CAM_HEIGHT:-360}"'));
    expect(script, contains('CAM_HZ="\${CAM_HZ:-5}"'));
    expect(script, contains('CAM_ALWAYS_ON="\${CAM_ALWAYS_ON:-0}"'));
    expect(script, contains(cameraTuningPython.trim().split('\n').first));
  });

  test('bash 가 읽을 수 있는 스크립트다', () {
    if (Process.runSync('which', ['bash']).exitCode != 0) {
      markTestSkipped('bash 가 없습니다');
      return;
    }
    final directory = Directory.systemTemp.createTempSync('camera_script');
    addTearDown(() => directory.deleteSync(recursive: true));
    final file = File('${directory.path}/robot_description.sh')
      ..writeAsStringSync(buildRobotDescriptionScript(_pinky));
    final result = Process.runSync('bash', ['-n', file.path]);
    expect(result.exitCode, 0, reason: '${result.stderr}');
  });

  test('설비 로봇에는 카메라 손질이 없다', () {
    const omx = RmfProjectRobot(
      robotId: 'omx_01',
      displayName: '픽업 설비',
      model: 'open_manipulator_x',
      gzName: 'omx_01',
      zones: [],
      kind: RmfRobotKind.workcell,
      dataSource: RobotDataSource.gazebo,
    );
    expect(buildRobotDescriptionScript(omx), isNot(contains('CAM_HZ')));
  });

  test('실제 URDF 를 넣으면 카메라가 통째로 빠진다', () {
    if (Process.runSync('which', ['python3']).exitCode != 0) {
      markTestSkipped('python3 가 없습니다');
      return;
    }
    final directory = Directory.systemTemp.createTempSync('camera_tuning');
    addTearDown(() => directory.deleteSync(recursive: true));
    final urdf = File('${directory.path}/robot.urdf')
      ..writeAsStringSync(_vendorUrdf);
    // 생성 스크립트가 쓰는 그 조각을 그대로 돌린다.
    final program = File('${directory.path}/tune.py')
      ..writeAsStringSync('''
import re
import sys

camera = sys.argv[1:6]
urdf = open(sys.argv[6], encoding="utf-8").read()

$cameraTuningPython

sys.stdout.write(urdf)
''');
    final result = Process.runSync('python3', [
      program.path,
      '0',
      '$cameraWidth',
      '$cameraHeight',
      '$cameraHz',
      '0',
      urdf.path,
    ]);
    expect(result.exitCode, 0, reason: '${result.stderr}');
    final stripped = result.stdout as String;

    // 카메라는 흔적도 없다. 센서도, 껍데기만 남은 <gazebo> 도.
    expect(stripped, isNot(contains('type="camera"')));
    expect(stripped, isNot(contains('camera/image_raw')));
    expect(stripped, isNot(contains('<horizontal_fov>')));
    expect(stripped, isNot(contains('front_camera_link')));
    // 라이다는 그대로 10Hz 로 돈다. 주행이 그것으로 위치를 잡는다.
    expect(stripped, contains('name="pinky_01/gpu_lidar"'));
    expect(stripped, contains('<update_rate>10</update_rate>'));
    expect(stripped, contains('<always_on>1</always_on>'));
    expect(stripped, contains('<link name="base_footprint"/>'));
  });

  test('CAM_ENABLED=1 로 되살리면 낮춘 값으로 붙는다', () {
    if (Process.runSync('which', ['python3']).exitCode != 0) {
      markTestSkipped('python3 가 없습니다');
      return;
    }
    final directory = Directory.systemTemp.createTempSync('camera_on');
    addTearDown(() => directory.deleteSync(recursive: true));
    final urdf = File('${directory.path}/robot.urdf')
      ..writeAsStringSync(_vendorUrdf);
    final program = File('${directory.path}/tune.py')
      ..writeAsStringSync('''
import re
import sys

camera = sys.argv[1:6]
urdf = open(sys.argv[6], encoding="utf-8").read()

$cameraTuningPython

sys.stdout.write(urdf)
''');
    final result = Process.runSync('python3', [
      program.path,
      '1',
      '$cameraWidth',
      '$cameraHeight',
      '$cameraHz',
      '0',
      urdf.path,
    ]);
    expect(result.exitCode, 0, reason: '${result.stderr}');
    final tuned = result.stdout as String;

    expect(tuned, contains('type="camera"'));
    expect(tuned, contains('<width>640</width>'));
    expect(tuned, contains('<height>360</height>'));
    expect(tuned, contains('<update_rate>5</update_rate>'));
    // 되살려도 보는 사람이 없으면 안 그린다.
    expect(tuned, contains('<always_on>0</always_on>'));
    expect(tuned, contains('<update_rate>10</update_rate>'));
  });

  test('카메라가 없는 URDF 는 조용히 지나가지 않고 말한다', () {
    if (Process.runSync('which', ['python3']).exitCode != 0) {
      markTestSkipped('python3 가 없습니다');
      return;
    }
    final directory = Directory.systemTemp.createTempSync('camera_tuning');
    addTearDown(() => directory.deleteSync(recursive: true));
    final urdf = File('${directory.path}/robot.urdf')
      ..writeAsStringSync('<robot name="x"><link name="base"/></robot>');
    final program = File('${directory.path}/tune.py')
      ..writeAsStringSync('''
import re
import sys

camera = sys.argv[1:6]
urdf = open(sys.argv[6], encoding="utf-8").read()

$cameraTuningPython
''');
    final result = Process.runSync('python3', [
      program.path,
      '0',
      '640',
      '360',
      '5',
      '0',
      urdf.path,
    ]);
    expect(result.exitCode, 0);
    expect(result.stderr, contains('카메라 sensor 를 못 찾았습니다'));
  });
}
