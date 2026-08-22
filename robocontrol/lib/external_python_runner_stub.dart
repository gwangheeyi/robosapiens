import 'external_python_models.dart';

export 'external_python_models.dart';

Future<ExternalPythonResult> runExternalPython(ExternalPythonRequest request) =>
    throw UnsupportedError('이 플랫폼에서는 Python을 실행할 수 없습니다.');

Future<ExternalPythonResult> runRobotArmPolicy(RobotArmPolicyRequest request) =>
    throw UnsupportedError('이 플랫폼에서는 Policy를 실행할 수 없습니다.');

String projectPolicyRunnerPath(String projectName) => '';
