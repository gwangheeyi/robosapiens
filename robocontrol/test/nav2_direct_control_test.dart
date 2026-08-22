import 'package:flutter_test/flutter_test.dart';
import 'package:robocontrol/nav2_direct_control.dart';

void main() {
  test('builds namespaced NavigateToPose goal', () {
    const goal = Nav2DirectGoal(
      namespace: '/pinky_01/',
      x: 1.25,
      y: -2.5,
      yawDegrees: 90,
    );
    expect(goal.actionName, '/pinky_01/navigate_to_pose');
    expect(goal.goalYaml, contains('frame_id: map'));
    expect(goal.goalYaml, contains('x: 1.25'));
    expect(goal.goalYaml, contains('y: -2.5'));
  });

  test('requires map scale', () {
    expect(
      nav2DirectMoveBlocker(
        isMobile: true,
        mapName: 'PinkyTest',
        waypointCount: 2,
        metersPerPixel: null,
      ),
      contains('축척'),
    );
  });
}
