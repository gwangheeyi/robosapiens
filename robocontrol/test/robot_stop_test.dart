import 'package:flutter_test/flutter_test.dart';
import 'package:robocontrol/robot_stop.dart';

void main() {
  test('로봇 namespace로 정지 토픽을 만든다', () {
    expect(robotTopic('pinky_02', 'cmd_vel'), '/pinky_02/cmd_vel');
    expect(robotTopic('/pinky_02/', 'cmd_vel'), '/pinky_02/cmd_vel');
  });

  test('Nav2의 모든 이동 종류를 취소한다', () {
    expect(robotMotionActions, contains('navigate_to_pose'));
    expect(robotMotionActions, contains('navigate_through_poses'));
    expect(robotMotionActions, contains('drive_on_heading'));
    expect(robotMotionActions, contains('backup'));
    expect(robotMotionActions, contains('spin'));
  });
}
