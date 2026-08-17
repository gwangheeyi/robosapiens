import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:rmf_control_ui/workcell_policy.dart';

void main() {
  test('Hugging Face 주소와 repository ID를 정규화한다', () {
    expect(
      parseHuggingFaceRepository(
        'https://huggingface.co/2usang/act_trihouse-sandwich',
      ),
      '2usang/act_trihouse-sandwich',
    );
    expect(
      parseHuggingFaceRepository('2usang/act_trihouse-sandwich'),
      '2usang/act_trihouse-sandwich',
    );
    expect(parseHuggingFaceRepository('https://example.com/a/b'), isNull);
  });

  test('ZIP signature와 확장자를 검증한다', () {
    final zip = Uint8List.fromList([0x50, 0x4b, 0x03, 0x04]);
    expect(validatePolicyArchive('pick.zip', zip), isNull);
    expect(validatePolicyArchive('pick.bin', zip), isNotNull);
    expect(validatePolicyArchive('pick.zip', Uint8List(8)), isNotNull);
  });

  test('배포 완료된 policy만 작업 선택 목록에 넣는다', () {
    final deployed = WorkcellPolicy(
      name: 'can_pick',
      version: '2.1.0',
      objectType: '캔',
      robotModel: 'open_manipulator_x',
      archiveName: 'can.zip',
      archiveBytes: 100,
      deployedWorkcells: const ['OMX_01'],
      createdAt: DateTime(2026),
    );
    final waiting = WorkcellPolicy(
      name: 'box_pick',
      version: '1.0.0',
      objectType: '박스',
      robotModel: 'open_manipulator_x',
      archiveName: 'box.zip',
      archiveBytes: 100,
      deployedWorkcells: const [],
      createdAt: DateTime(2026),
    );
    expect(deployedPolicyIds([deployed, waiting]), ['can_pick@2.1.0']);
  });

  test('manifest에 고정된 policy 이름과 버전을 남긴다', () {
    final policy = WorkcellPolicy(
      name: 'can_pick',
      version: '2.1.0',
      objectType: '캔',
      robotModel: 'open_manipulator_x',
      archiveName: 'can.zip',
      archiveBytes: 100,
      deployedWorkcells: const ['OMX_01'],
      createdAt: DateTime(2026),
    );
    expect(policy.manifest('warehouse'), contains('can_pick@2.1.0'));
    final global = policy.copyWith(objectType: '', deployedWorkcells: const []);
    expect(global.id, policy.id);
    expect(global.isDeployed, isFalse);
    expect(global.globalManifest(), contains('"scope": "global"'));
  });

  test('내려받은 바이트로 설치 진행률을 센다', () {
    const start = PolicyInstallProgress(
      phase: PolicyInstallPhase.download,
      receivedBytes: 0,
      totalBytes: 400,
      fileName: 'model.safetensors',
      totalFiles: 2,
    );
    expect(start.percent, 3);
    const half = PolicyInstallProgress(
      phase: PolicyInstallPhase.download,
      receivedBytes: 200 * 1024 * 1024,
      totalBytes: 400 * 1024 * 1024,
      fileName: 'model.safetensors',
      totalFiles: 2,
    );
    expect(half.percent, 44);
    expect(half.detail, 'model.safetensors · 200.0MB / 400.0MB');
    // 단계가 넘어가도 막대가 뒤로 가지 않는다.
    expect(
      const PolicyInstallProgress(phase: PolicyInstallPhase.archive).percent,
      85,
    );
    expect(
      const PolicyInstallProgress(phase: PolicyInstallPhase.save).percent,
      95,
    );
    expect(
      const PolicyInstallProgress(phase: PolicyInstallPhase.done).percent,
      100,
    );
  });

  test('파일 크기를 모르면 파일 개수로 진행률을 센다', () {
    const progress = PolicyInstallProgress(
      phase: PolicyInstallPhase.download,
      receivedBytes: 1024,
      totalBytes: 0,
      completedFiles: 2,
      totalFiles: 4,
    );
    expect(progress.percent, 44);
    expect(progress.detail, '2/4 파일');
    expect(formatPolicyBytes(2 * 1024 * 1024), '2.0MB');
    expect(formatPolicyBytes(2048), '2KB');
  });

  test('WorkCell 에 붙이고 뗀다', () {
    final policy = WorkcellPolicy(
      name: 'can_pick',
      version: '2.1.0',
      objectType: '',
      robotModel: 'open_manipulator_x',
      archiveName: 'can.zip',
      archiveBytes: 100,
      deployedWorkcells: const [],
      createdAt: DateTime(2026),
    );

    final attached = attachPolicyToWorkcell(policy, 'OMX_01', objectType: '캔');
    expect(attached.deployedWorkcells, ['OMX_01']);
    expect(attached.objectType, '캔');
    // 두 번 붙여도 한 번만 들어간다. 다른 설비는 그대로 남는다.
    final both = attachPolicyToWorkcell(
      attachPolicyToWorkcell(attached, 'OMX_02'),
      'OMX_01',
    );
    expect(both.deployedWorkcells, ['OMX_01', 'OMX_02']);
    // 물품을 비워 두면 적어 둔 것을 지우지 않는다.
    expect(
      attachPolicyToWorkcell(both, 'OMX_01', objectType: '  ').objectType,
      '캔',
    );

    final detached = detachPolicyFromWorkcell(both, 'OMX_01');
    expect(detached.deployedWorkcells, ['OMX_02']);
    expect(detachPolicyFromWorkcell(detached, 'OMX_02').isDeployed, isFalse);
    // 뗀 것은 프로젝트 연결과 전역 원본을 건드리지 않는다.
    expect(detached.id, policy.id);
    expect(detached.archiveName, policy.archiveName);
  });

  test('설비에 붙은 것과 더 붙일 수 있는 것을 가른다', () {
    WorkcellPolicy make(String name, String model, List<String> workcells) =>
        WorkcellPolicy(
          name: name,
          version: '1.0.0',
          objectType: '캔',
          robotModel: model,
          archiveName: '$name.zip',
          archiveBytes: 100,
          deployedWorkcells: workcells,
          createdAt: DateTime(2026),
        );

    final mine = make('can_pick', 'open_manipulator_x', const ['OMX_01']);
    final other = make('box_pick', 'open_manipulator_x', const ['OMX_02']);
    final free = make('cup_pick', 'open_manipulator_x', const []);
    final otherModel = make('arm_pick', 'ur5e', const []);

    expect(
      policiesForWorkcell([
        mine,
        other,
        free,
        otherModel,
      ], 'OMX_01').map((policy) => policy.id),
      ['can_pick@1.0.0'],
    );
    expect(
      policyCandidatesForWorkcell(
        // 프로젝트 목록과 전역 보관함을 합치면 같은 것이 두 번 들어온다.
        policies: [mine, other, free, otherModel, free],
        robotId: 'OMX_01',
        robotModel: 'open_manipulator_x',
      ).map((policy) => policy.id),
      // 이미 붙은 can_pick 과 모델이 다른 arm_pick 은 빠진다.
      ['box_pick@1.0.0', 'cup_pick@1.0.0'],
    );
  });

  test('취소 표를 세우면 다음 단계에서 멈춘다', () {
    final token = PolicyInstallCancelToken();
    expect(token.isCancelled, isFalse);
    token.throwIfCancelled();
    token.cancel();
    expect(token.isCancelled, isTrue);
    expect(token.throwIfCancelled, throwsA(isA<PolicyInstallCancelled>()));
  });
}
