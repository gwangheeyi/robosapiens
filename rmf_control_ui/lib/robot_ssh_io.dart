/// SSH 를 실제로 돌린다. 규칙은 `robot_ssh.dart` 에 있다.
library;

import 'dart:io';

import 'rmf_project_config.dart';
import 'robot_ssh.dart';

/// 위젯 테스트에서는 프로세스를 띄우지 않는다.
bool get _inTest => Platform.environment.containsKey('FLUTTER_TEST');

/// 비밀번호를 묻지 않게 하는 옵션.
///
/// 앱에는 사람이 비밀번호를 칠 자리가 없다. 물어보는 상태로 두면 ssh 가 입력을
/// 기다리며 멈추고, 화면은 영영 `띄우는 중` 으로 남는다. 그럴 바에는 **빨리
/// 실패하고** 키를 등록하라고 말하는 편이 낫다.
///
/// `StrictHostKeyChecking=accept-new` 는 처음 보는 로봇의 키를 자동으로 받는다.
/// 묻는 순간 역시 멈추기 때문이다. 사내망의 로봇을 전제로 한 선택이다.
List<String> _sshOptions(RobotSshTarget target) => [
  '-o',
  'BatchMode=yes',
  '-o',
  'StrictHostKeyChecking=accept-new',
  '-o',
  'ConnectTimeout=8',
  '-p',
  '${target.port}',
];

/// 로봇에서 명령 하나를 돌린다.
Future<({RobotSshOutcome outcome, String output})> runOnRobot({
  required RobotSshTarget target,
  required String command,
  Duration timeout = const Duration(seconds: 30),
}) async {
  if (_inTest) return (outcome: RobotSshOutcome.ok, output: '');
  try {
    final result = await Process.run('ssh', [
      ..._sshOptions(target),
      target.authority,
      command,
    ]).timeout(timeout);
    final out = '${result.stdout}${result.stderr}'.trim();
    if (result.exitCode == 0) return (outcome: RobotSshOutcome.ok, output: out);
    // ssh 자체가 못 붙으면 255 로 끝난다. 그 안쪽 명령이 실패한 것과 다르다 —
    // 볼 곳이 다르므로 갈라 준다.
    return (
      outcome: result.exitCode == 255
          ? RobotSshOutcome.unreachable
          : RobotSshOutcome.commandFailed,
      output: out,
    );
  } on ProcessException catch (error) {
    return (
      outcome: RobotSshOutcome.unreachable,
      output: 'ssh 를 실행하지 못했습니다: ${error.message}',
    );
  } catch (error) {
    return (
      outcome: RobotSshOutcome.unreachable,
      output: '$error',
    );
  }
}

/// 로봇의 브링업을 띄운다.
Future<({RobotSshOutcome outcome, String output})> startRobotBringup({
  required RmfProjectRobot robot,
  required RobotSshTarget target,
  required int projectDomainId,
}) => runOnRobot(
  target: target,
  command: buildRobotBringupCommand(
    robot: robot,
    target: target,
    projectDomainId: projectDomainId,
  ),
  // 이전 브링업을 죽이고 시리얼이 풀리기를 기다리는 시간이 들어 있다.
  timeout: const Duration(seconds: 45),
);

/// 로봇을 켜자마자 브링업이 뜨게 한다.
///
/// 유닛 파일은 표준 입력으로 넘긴다. 명령줄에 넣으면 줄바꿈과 따옴표가 셸을
/// 빠져나간다.
///
/// `sudo` 를 쓴다. 비밀번호를 물으면 [_sshOptions] 의 `BatchMode` 때문에 바로
/// 실패하는데, 그 편이 낫다 — 물어보는 채로 두면 앱이 영영 기다린다. 실패하면
/// NOPASSWD 를 안내한다.
Future<({RobotSshOutcome outcome, String output})> installRobotBringupService({
  required RmfProjectRobot robot,
  required RobotSshTarget target,
  required int projectDomainId,
}) async {
  if (_inTest) return (outcome: RobotSshOutcome.ok, output: 'INSTALLED');
  final unit = buildRobotBringupService(
    robot: robot,
    target: target,
    projectDomainId: projectDomainId,
  );
  try {
    final process = await Process.start('ssh', [
      ..._sshOptions(target),
      target.authority,
      buildRobotServiceInstallCommand(robot),
    ]);
    process.stdin.write(unit);
    await process.stdin.close();
    final out = await process.stdout.transform(const SystemEncoding().decoder).join();
    final err = await process.stderr.transform(const SystemEncoding().decoder).join();
    final code = await process.exitCode.timeout(const Duration(seconds: 60));
    final text = '$out$err'.trim();
    if (code == 0) return (outcome: RobotSshOutcome.ok, output: text);
    return (
      outcome: code == 255
          ? RobotSshOutcome.unreachable
          : RobotSshOutcome.commandFailed,
      output: text,
    );
  } catch (error) {
    return (outcome: RobotSshOutcome.unreachable, output: '$error');
  }
}

/// 자동 실행을 끈다.
Future<({RobotSshOutcome outcome, String output})> removeRobotBringupService({
  required RmfProjectRobot robot,
  required RobotSshTarget target,
}) => runOnRobot(
  target: target,
  command: buildRobotServiceRemoveCommand(robot),
);

/// 자동 실행이 걸려 있는지 본다.
Future<RobotServiceStatus> readRobotServiceStatus({
  required RmfProjectRobot robot,
  required RobotSshTarget target,
}) async {
  final result = await runOnRobot(
    target: target,
    command: buildRobotServiceStatusCommand(robot),
    timeout: const Duration(seconds: 15),
  );
  // 못 붙었으면 "안 걸려 있다" 가 아니라 **모른다** 다. 여기서 걸려 있다고
  // 답하면 설치가 안 된 로봇을 설치됐다고 보게 된다.
  if (result.outcome != RobotSshOutcome.ok) {
    return const RobotServiceStatus(enabled: false, active: false);
  }
  return parseRobotServiceStatus(result.output);
}

/// 로봇의 브링업을 내린다.
Future<({RobotSshOutcome outcome, String output})> stopRobotBringup({
  required RmfProjectRobot robot,
  required RobotSshTarget target,
}) => runOnRobot(
  target: target,
  command: buildRobotBringupStopCommand(robot),
);

/// 브링업이 떠 있는가.
Future<bool> isRobotBringupRunning({
  required RmfProjectRobot robot,
  required RobotSshTarget target,
}) async {
  final result = await runOnRobot(
    target: target,
    command: buildRobotBringupProbeCommand(robot),
    timeout: const Duration(seconds: 15),
  );
  return result.outcome == RobotSshOutcome.ok &&
      result.output.contains('RUNNING');
}

/// 브링업 로그의 마지막 부분을 읽는다.
///
/// 시리얼을 못 잡으면 여기에 그대로 찍힌다 — 앱에서 바로 볼 수 있어야 로봇에
/// 다시 들어갈 일이 없다.
Future<String> readRobotBringupLog({
  required RmfProjectRobot robot,
  required RobotSshTarget target,
  int lines = 40,
}) async {
  final result = await runOnRobot(
    target: target,
    command: buildRobotBringupLogCommand(robot, lines: lines),
    timeout: const Duration(seconds: 15),
  );
  return result.output;
}
