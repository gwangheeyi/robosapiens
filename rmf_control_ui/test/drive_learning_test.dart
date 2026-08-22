import 'package:flutter_test/flutter_test.dart';
import 'package:rmf_control_ui/drive_learning_models.dart';

DriveLearningSample sample(double error, {double velocity = .15}) =>
    DriveLearningSample(
      mapName: 'map',
      taskId: 'task',
      taskName: 'delivery',
      robotId: 'pinky_01',
      waypointName: 'pickup',
      driveMode: 'normal',
      startedAt: DateTime(2026),
      finishedAt: DateTime(2026, 1, 1, 0, 0, 10),
      linearVelocity: velocity,
      linearAcceleration: .5,
      angularVelocity: .7,
      angularAcceleration: 1,
      goalTolerance: .1,
      goalX: 1,
      goalY: 2,
      actualX: 1 + error,
      actualY: 2,
      positionError: error,
      success: true,
    );

void main() {
  test('한 번뿐인 설정은 추천하지 않는다', () {
    expect(recommendDriveSettings([sample(.01)]), isNull);
  });
  test('반복 결과의 평균 오차가 작은 설정을 추천한다', () {
    final result = recommendDriveSettings([
      sample(.08, velocity: .2),
      sample(.06, velocity: .2),
      sample(.02),
      sample(.03),
    ]);
    expect(result?.linearVelocity, .15);
    expect(result?.meanPositionError, closeTo(.025, 1e-9));
    expect(result?.samples, 2);
  });
  test('각도 오차를 최단 방향으로 계산한다', () {
    expect(angularError(3.13, -3.13), lessThan(.03));
  });
}
