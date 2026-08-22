import 'package:flutter_test/flutter_test.dart';
import 'package:robocontrol/rmf_project_config.dart';
import 'package:robocontrol/workcell_pairing.dart';
import 'package:robocontrol/workcell_policy.dart';

/// 팔마다 배운 것이 다르다.
///
/// 픽업 요청은 자리 이름(`target_guid`)으로 나가고 그 자리를 맡는 설비 하나가
/// 답한다. 그러므로 작업에서 고를 수 있는 policy 도 **그 설비에 붙인 것**이라야
/// 한다. 프로젝트에 등록했다고 모든 팔이 쓰는 것이 아니다.
void main() {
  const omx1 = RmfProjectRobot(
    robotId: 'OMX_01',
    displayName: '매니퓰레이터 1호',
    model: 'open_manipulator_x',
    gzName: 'omx_01',
    zones: [],
    kind: RmfRobotKind.workcell,
    dataSource: RobotDataSource.gazebo,
    spawnX: 1,
    spawnY: 1,
  );
  const omx2 = RmfProjectRobot(
    robotId: 'OMX_02',
    displayName: '매니퓰레이터 2호',
    model: 'open_manipulator_x',
    gzName: 'omx_02',
    zones: [],
    kind: RmfRobotKind.workcell,
    dataSource: RobotDataSource.gazebo,
    spawnX: 4,
    spawnY: 1,
  );

  final pairing = pairWorkcells(
    robots: const [omx1, omx2],
    stations: const [
      WorkcellStation(name: '픽업1', x: 1.2, y: 1, isDispenser: true),
      WorkcellStation(name: '픽업2', x: 4.2, y: 1, isDispenser: true),
      WorkcellStation(name: '드랍오프2', x: 3.8, y: 1, isDispenser: false),
    ],
  );

  WorkcellPolicy make(String name, List<String> workcells) => WorkcellPolicy(
    name: name,
    version: '1.0.0',
    objectType: '캔',
    robotModel: 'open_manipulator_x',
    archiveName: '$name.zip',
    archiveBytes: 100,
    deployedWorkcells: workcells,
    createdAt: DateTime(2026),
    projectName: 'warehouse',
  );

  final policies = [
    make('can_pick', const ['OMX_01']),
    make('cup_pick', const ['OMX_01', 'OMX_02']),
    make('box_pick', const ['OMX_02']),
    make('idle_pick', const []),
  ];

  test('자리마다 맡는 설비를 짚는다', () {
    expect(workcellsByStation(pairing), {
      '픽업1': 'OMX_01',
      '픽업2': 'OMX_02',
      '드랍오프2': 'OMX_02',
    });
  });

  test('그 자리를 맡는 팔에 붙인 policy 만 고를 수 있다', () {
    final first = policyChoicesForStation(
      station: '픽업1',
      workcellsByStation: workcellsByStation(pairing),
      policies: policies,
      fallbackPolicyIds: const ['policy_1'],
    );
    expect(first.workcellId, 'OMX_01');
    expect(first.policyIds, ['can_pick@1.0.0', 'cup_pick@1.0.0']);
    expect(first.fallback, isFalse);

    final second = policyChoicesForStation(
      station: '픽업2',
      workcellsByStation: workcellsByStation(pairing),
      policies: policies,
      fallbackPolicyIds: const ['policy_1'],
    );
    // 같은 프로젝트에 있어도 OMX_02 에 붙이지 않은 can_pick 은 안 나온다.
    expect(second.policyIds, ['cup_pick@1.0.0', 'box_pick@1.0.0']);
    expect(second.rejects('can_pick@1.0.0'), isTrue);
    expect(second.rejects('box_pick@1.0.0'), isFalse);
  });

  test('붙인 것이 없는 팔은 기본 동작을 쓴다', () {
    final choices = policyChoicesForStation(
      station: '픽업1',
      workcellsByStation: const {'픽업1': 'OMX_09'},
      policies: policies,
      fallbackPolicyIds: const ['policy_1', 'policy_2'],
    );
    expect(choices.workcellId, 'OMX_09');
    expect(choices.fallback, isTrue);
    expect(choices.policyIds, ['policy_1', 'policy_2']);
    // 기본 동작뿐일 때는 무엇을 골라도 막지 않는다.
    expect(choices.rejects('policy_1'), isFalse);
  });

  test('자리를 모르면 프로젝트에 붙어 있는 것을 모두 보여 준다', () {
    final choices = policyChoicesForStation(
      station: null,
      workcellsByStation: workcellsByStation(pairing),
      policies: policies,
      fallbackPolicyIds: const ['policy_1'],
    );
    expect(choices.scoped, isFalse);
    expect(choices.policyIds, [
      'can_pick@1.0.0',
      'cup_pick@1.0.0',
      'box_pick@1.0.0',
    ]);
    // 어느 설비의 것인지 모르니 막지도 않는다.
    expect(choices.rejects('idle_pick@1.0.0'), isFalse);
  });
}
