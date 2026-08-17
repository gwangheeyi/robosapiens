/// 팔이 무엇으로 움직이는지 지킨다.
///
/// 붙여 둔 policy 가 있으면 **그 policy 로** 움직인다(Gazebo 든 실물이든 같은
/// 러너다). 없으면 관절 몇 개를 움직이는 시험 동작만 하고, 그 동작이 끝난 것을
/// 확인한 뒤 RMF 에 성공을 알린다 — 그래야 다음 단계로 넘어간다.
///
/// 추론기(torch·lerobot)가 없는 자리에서도 작업이 멈추면 안 된다. 러너가 0 이
/// 아닌 코드로 끝나면 시험 동작으로 대신한다.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rmf_control_ui/rmf_project_config.dart';
import 'package:rmf_control_ui/workcell_pairing.dart';
import 'package:rmf_control_ui/workcell_policy.dart';

const RmfProjectRobot _omx = RmfProjectRobot(
  robotId: 'omx_01',
  displayName: 'OMX-01',
  model: 'open_manipulator_x',
  gzName: 'omx_01',
  zones: [],
  kind: RmfRobotKind.workcell,
  dataSource: RobotDataSource.gazebo,
  spawnX: 1,
  spawnY: -1,
);

WorkcellPolicy _policy(String name, List<String> workcells) => WorkcellPolicy(
  name: name,
  version: '1.0.0',
  objectType: '캔',
  robotModel: 'open_manipulator_x',
  archiveName: '$name.zip',
  archiveBytes: 100,
  deployedWorkcells: workcells,
  createdAt: DateTime(2026),
  projectName: 'project1',
);

String _script({
  List<WorkcellPolicy> policies = const [],
  Map<String, String> archives = const {},
  String runner = '/maps/project1/project1_policy_runner.py',
}) => buildWorkcellScript(
  mapName: 'project1',
  pairing: pairWorkcells(
    robots: const [_omx],
    stations: const [
      WorkcellStation(name: '픽업3', x: 1, y: -1, isDispenser: true),
    ],
  ),
  policies: policies,
  policyArchives: archives,
  policyRunnerPath: runner,
);

void main() {
  group('워크셀 노드', () {
    test('붙인 policy 와 그 학습 결과 자리를 함께 싣는다', () {
      final code = _script(
        policies: [
          _policy('can_pick', const ['omx_01']),
        ],
        archives: const {
          'can_pick@1.0.0': '/work/workcell_policies/can_pick/1_0_0/policy.zip',
        },
      );
      expect(code, contains("'can_pick@1.0.0'"));
      expect(
        code,
        contains(
          "'can_pick@1.0.0': "
          "'/work/workcell_policies/can_pick/1_0_0/policy.zip',",
        ),
      );
      expect(
        code,
        contains("POLICY_RUNNER = '/maps/project1/project1_policy_runner.py'"),
      );
    });

    test('남의 팔에 붙인 policy 는 이 팔의 목록에 없다', () {
      final code = _script(
        policies: [
          _policy('can_pick', const ['omx_01']),
          _policy('box_pick', const ['omx_02']),
        ],
      );
      // WORKCELLS 항목에는 이 팔에 붙인 것만 온다.
      expect(code, contains("['can_pick@1.0.0']"));
      expect(code, isNot(contains("'box_pick@1.0.0']")));
    });

    test('policy 가 있으면 러너로, 없으면 시험 동작으로 간다', () {
      final code = _script();
      // 사다리의 첫 칸이 학습 policy 다.
      expect(
        code,
        contains('if is_deployed and archive is not None and runner_ready:'),
      );
      // 학습 결과가 이 자리에 없으면 그 까닭을 적고 시험 동작으로 간다.
      expect(code, contains('학습 결과 파일이 없어'));
      expect(code, contains("cell.test_trajectory('붙인 policy 가 없어')"));
      // 시험 동작도 액션 결과로 끝을 확인하고서야 성공을 알린다.
      expect(code, contains("job.stage = 'settling'"));
      expect(code, contains('self.succeed(cell, job)'));
    });

    test('추론이 안 되면 작업을 세우지 않고 시험 동작으로 잇는다', () {
      final code = _script();
      expect(code, contains('def fall_back_to_test(self, cell, job, reason):'));
      expect(code, contains('self.fall_back_to_test(cell, job,'));
      // 시험 동작으로 갈아탄 뒤에도 팔의 액션 결과를 기다린다.
      expect(code, contains('future.add_done_callback('));
    });

    test('이 팔에 붙지 않은 policy 는 조용히 바꾸지 않고 실패로 답한다', () {
      final code = _script();
      expect(code, contains('에 붙지 않은 policy 입니다'));
      expect(code, contains('DispenserResult.FAILED'));
    });

    test('추론이 늦으면 끊고, 로봇이 자리를 뜨면 세운다', () {
      final code = _script();
      expect(code, contains('POLICY_TIMEOUT'));
      expect(code, contains('def watch_policy(self, cell, job):'));
      expect(code, contains('def stop_runner(self, job):'));
      expect(code, contains('적재 중에 로봇이 자리를 떴습니다'));
    });
  });

  group('policy 러너', () {
    final runner = buildPolicyRunnerScript(mapName: 'project1');

    test('Gazebo 와 실물이 같은 러너를 쓴다', () {
      // 다른 것은 네임스페이스뿐이다.
      expect(runner, contains("f'/{args.namespace}/joint_states'"));
      expect(
        runner,
        contains("f'/{args.namespace}/arm_controller/joint_trajectory'"),
      );
      expect(runner, contains('--namespace'));
    });

    test('추론기가 없으면 2로 끝내 시험 동작에 넘긴다', () {
      expect(runner, contains('sys.exit(2)'));
      expect(runner, contains('torch 가 없습니다'));
      expect(runner, contains('lerobot 이 없습니다'));
      // 관절 상태가 안 오면 팔이 없는 것이다.
      expect(runner, contains('sys.exit(3)'));
    });

    test('policy 가 이미지를 요구할 때만 카메라를 본다', () {
      expect(runner, contains('def image_features(directory):'));
      expect(runner, contains("f'/{args.namespace}/camera/image_raw'"));
    });

    test('끝나면 시작 자세로 돌아가고 0으로 끝난다', () {
      expect(runner, contains('HOME_SECONDS'));
      expect(runner, contains('return 0'));
    });
  });

  group('만들어진 파일을 파이썬이 읽을 수 있는가', () {
    test('py_compile 이 통과한다', () {
      if (Process.runSync('which', ['python3']).exitCode != 0) {
        markTestSkipped('python3 가 없습니다');
        return;
      }
      final directory = Directory.systemTemp.createTempSync('policy_py');
      addTearDown(() => directory.deleteSync(recursive: true));
      final files = {
        'workcell.py': _script(
          policies: [
            _policy('can_pick', const ['omx_01']),
          ],
          archives: const {'can_pick@1.0.0': '/work/can_pick/policy.zip'},
        ),
        'policy_runner.py': buildPolicyRunnerScript(mapName: 'project1'),
      };
      for (final entry in files.entries) {
        final file = File('${directory.path}/${entry.key}')
          ..writeAsStringSync(entry.value);
        final result = Process.runSync('python3', [
          '-m',
          'py_compile',
          file.path,
        ]);
        expect(result.exitCode, 0, reason: '${entry.key}: ${result.stderr}');
      }
    });
  });
}
