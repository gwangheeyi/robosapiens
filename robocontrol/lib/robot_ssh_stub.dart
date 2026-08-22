/// 웹에서는 프로세스를 띄울 수 없다.
library;

import 'rmf_project_config.dart';
import 'robot_ssh.dart';

const _unavailable = (
  outcome: RobotSshOutcome.unreachable,
  output: '이 판에서는 SSH 를 쓸 수 없습니다.',
);

Future<({RobotSshOutcome outcome, String output})> runOnRobot({
  required RobotSshTarget target,
  required String command,
  Duration timeout = const Duration(seconds: 30),
}) async => _unavailable;

Future<({RobotSshOutcome outcome, String output})> startRobotBringup({
  required RmfProjectRobot robot,
  required RobotSshTarget target,
  required int projectDomainId,
}) async => _unavailable;

Future<({RobotSshOutcome outcome, String output})> stopRobotBringup({
  required RmfProjectRobot robot,
  required RobotSshTarget target,
}) async => _unavailable;

Future<bool> isRobotBringupRunning({
  required RmfProjectRobot robot,
  required RobotSshTarget target,
}) async => false;

Future<String> readRobotBringupLog({
  required RmfProjectRobot robot,
  required RobotSshTarget target,
  int lines = 40,
}) async => '이 판에서는 SSH 를 쓸 수 없습니다.';

Future<({RobotSshOutcome outcome, String output})> installRobotBringupService({
  required RmfProjectRobot robot,
  required RobotSshTarget target,
  required int projectDomainId,
}) async => _unavailable;

Future<({RobotSshOutcome outcome, String output})> removeRobotBringupService({
  required RmfProjectRobot robot,
  required RobotSshTarget target,
}) async => _unavailable;

Future<RobotServiceStatus> readRobotServiceStatus({
  required RmfProjectRobot robot,
  required RobotSshTarget target,
}) async => const RobotServiceStatus(enabled: false, active: false);
