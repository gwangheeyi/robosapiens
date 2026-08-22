library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'external_python_models.dart';

export 'external_python_models.dart';

String projectPolicyRunnerPath(String projectName) {
  var directory = Directory.current.absolute;
  for (var i = 0; i < 8; i++) {
    if (Directory('${directory.path}/rmf_maps').existsSync()) {
      return '${directory.path}/rmf_maps/$projectName/'
          '${projectName}_policy_runner.py';
    }
    if (directory.parent.path == directory.path) break;
    directory = directory.parent;
  }
  return 'rmf_maps/$projectName/${projectName}_policy_runner.py';
}

String _quote(String value) => "'${value.replaceAll("'", r"'\''")}'";

String _rosEnvironment(String command, int domain) {
  final setup =
      Platform.environment['ROS_SETUP'] ?? '/opt/ros/jazzy/setup.bash';
  return 'set +u; [ -f ${_quote(setup)} ] && . ${_quote(setup)}; '
      'export ROS_DOMAIN_ID=$domain; '
      'export FASTDDS_BUILTIN_TRANSPORTS=UDPv4; '
      'export ROS_AUTOMATIC_DISCOVERY_RANGE=SUBNET; '
      'unset ROS_STATIC_PEERS ROS_LOCALHOST_ONLY; $command';
}

Future<ExternalPythonResult> _run(
  String executable,
  List<String> arguments,
  Duration timeout, {
  String? workingDirectory,
  Map<String, String>? environment,
}) async {
  final started = DateTime.now();
  Process? process;
  try {
    process = await Process.start(
      executable,
      arguments,
      workingDirectory: workingDirectory,
      environment: environment,
      runInShell: false,
    );
    final stdoutFuture = process.stdout.transform(utf8.decoder).join();
    final stderrFuture = process.stderr.transform(utf8.decoder).join();
    final exitCode = await process.exitCode.timeout(
      timeout,
      onTimeout: () {
        process?.kill(ProcessSignal.sigint);
        Timer(const Duration(seconds: 2), () {
          process?.kill(ProcessSignal.sigterm);
        });
        return 124;
      },
    );
    final output = '${await stdoutFuture}${await stderrFuture}'.trim();
    return ExternalPythonResult(
      success: exitCode == 0,
      exitCode: exitCode,
      output: output,
      duration: DateTime.now().difference(started),
    );
  } catch (error) {
    process?.kill(ProcessSignal.sigterm);
    return ExternalPythonResult(
      success: false,
      exitCode: -1,
      output: '$error',
      duration: DateTime.now().difference(started),
    );
  }
}

Future<ExternalPythonResult> runExternalPython(
  ExternalPythonRequest request,
) async {
  final file = File(request.filePath);
  if (!file.existsSync()) {
    return const ExternalPythonResult(
      success: false,
      exitCode: 2,
      output: 'Python 파일이 없습니다.',
      duration: Duration.zero,
    );
  }
  return _run(
    Platform.environment['ROBOCONTROL_PYTHON'] ?? 'python3',
    [file.absolute.path, ...request.arguments],
    request.timeout,
    workingDirectory: file.parent.path,
  );
}

Future<ExternalPythonResult> runRobotArmPolicy(
  RobotArmPolicyRequest request,
) async {
  final runner = File(request.runnerPath);
  final policy = File(request.policyPath);
  if (!runner.existsSync() || !policy.existsSync()) {
    final missing = [
      if (!runner.existsSync()) runner.path,
      if (!policy.existsSync()) policy.path,
    ];
    return ExternalPythonResult(
      success: false,
      exitCode: 2,
      output: '필요한 파일이 없습니다:\n${missing.join('\n')}',
      duration: Duration.zero,
    );
  }

  // Nav2 성공 뒤에도 마지막 속도 명령이 남을 수 있다. Policy가 팔을 움직이는
  // 동안 Pinky가 움직이지 않도록 0 속도를 두 번 보낸다.
  if (request.pinkyNamespace.trim().isNotEmpty) {
    final ns = request.pinkyNamespace.replaceAll(RegExp(r'^/+|/+$'), '');
    final stop =
        "ros2 topic pub --once '/$ns/cmd_vel' "
        "geometry_msgs/msg/Twist '{}' >/dev/null 2>&1 || true";
    await _run('bash', [
      '-lc',
      _rosEnvironment('$stop; sleep 0.4; $stop', request.rosDomainId),
    ], const Duration(seconds: 5));
    ExternalPythonResult? odom;
    var stopped = false;
    for (var attempt = 0; attempt < 3 && !stopped; attempt++) {
      odom = await _run('bash', [
        '-lc',
        _rosEnvironment(
          "timeout 3 ros2 topic echo '/$ns/odom' "
          '--once --field twist.twist --csv',
          request.rosDomainId,
        ),
      ], const Duration(seconds: 5));
      stopped = odomTwistShowsStopped(odom.output);
      if (!stopped) {
        await _run('bash', [
          '-lc',
          _rosEnvironment(stop, request.rosDomainId),
        ], const Duration(seconds: 3));
        await Future<void>.delayed(const Duration(milliseconds: 300));
      }
    }
    if (!stopped) {
      return ExternalPythonResult(
        success: false,
        exitCode: 5,
        output:
            'Pinky 정지를 /$ns/odom에서 확인하지 못해 Policy를 실행하지 않았습니다.\n'
            '${odom?.output ?? ''}',
        duration: odom?.duration ?? Duration.zero,
      );
    }
  }

  final command = [
    'exec',
    _quote(Platform.environment['ROBOCONTROL_POLICY_PYTHON'] ?? 'python3'),
    _quote(runner.absolute.path),
    '--policy',
    _quote(policy.absolute.path),
    '--policy-id',
    _quote(request.policyId),
    '--namespace',
    _quote(request.armNamespace.replaceAll(RegExp(r'^/+|/+$'), '')),
    '--model',
    _quote(request.robotModel),
    '--seconds',
    request.runSeconds.toString(),
  ].join(' ');
  return _run(
    'bash',
    ['-lc', _rosEnvironment(command, request.rosDomainId)],
    Duration(seconds: request.runSeconds.ceil() + 30),
    workingDirectory: runner.parent.path,
  );
}
