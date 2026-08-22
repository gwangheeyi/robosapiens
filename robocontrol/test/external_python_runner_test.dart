import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:robocontrol/external_python_runner.dart';
import 'package:robocontrol/external_python_models.dart';

void main() {
  test('외부 Python 인자를 따옴표 단위로 나눈다', () {
    expect(splitCommandArguments('--name "pickup one" --count 2'), [
      '--name',
      'pickup one',
      '--count',
      '2',
    ]);
  });

  test('policy 요청은 실행에 필요한 대상을 모두 가진다', () {
    const request = RobotArmPolicyRequest(
      runnerPath: '/maps/PinkyTest_policy_runner.py',
      policyPath: '/policies/pickup.zip',
      policyId: 'pickup@1',
      armNamespace: 'omx_01',
      pinkyNamespace: 'pinky_01',
      rosDomainId: 12,
    );
    expect(request.armNamespace, 'omx_01');
    expect(request.pinkyNamespace, 'pinky_01');
  });

  test('odom 속도로 실제 정지를 판정한다', () {
    expect(odomTwistShowsStopped('0.001,0,0,0,0,0.01'), isTrue);
    expect(odomTwistShowsStopped('0.02,0,0,0,0,0'), isFalse);
    expect(odomTwistShowsStopped('0,0,0,0,0,0.03'), isFalse);
    expect(odomTwistShowsStopped('WARNING: no data'), isFalse);
  });

  test('선택한 외부 Python 파일을 인자와 함께 실행한다', () async {
    final directory = await Directory.systemTemp.createTemp('robocontrol_py_');
    addTearDown(() => directory.delete(recursive: true));
    final script = File('${directory.path}/hello.py');
    await script.writeAsString('import sys\nprint("policy=" + sys.argv[1])\n');
    final result = await runExternalPython(
      ExternalPythonRequest(
        filePath: script.path,
        arguments: const ['pickup'],
        timeout: const Duration(seconds: 5),
      ),
    );
    expect(result.success, isTrue);
    expect(result.output, contains('policy=pickup'));
  });
}
