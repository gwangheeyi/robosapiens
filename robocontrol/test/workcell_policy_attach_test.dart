import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:robocontrol/workcell_policy.dart';
import 'package:robocontrol/workcell_policy_page.dart';

/// Policy 는 로봇 관리에서 그 설비에 붙인다.
///
/// Policy 관리 화면은 policy 쪽에서 보는 자리라 "이 설비가 무엇을 할 수 있는가"를
/// 보려면 policy 를 하나씩 열어 봐야 했다. 붙여 둔 것은 작업의 픽업 단계에서
/// 그 WorkCell 의 것으로 고를 수 있다.
void main() {
  WorkcellPolicy make(
    String name, {
    String model = 'open_manipulator_x',
    String objectType = '캔',
    List<String> workcells = const [],
  }) => WorkcellPolicy(
    name: name,
    version: '1.0.0',
    objectType: objectType,
    robotModel: model,
    archiveName: '$name.zip',
    archiveBytes: 2 * 1024 * 1024,
    deployedWorkcells: workcells,
    createdAt: DateTime(2026),
  );

  Future<List<WorkcellPolicy>> pump(
    WidgetTester tester,
    List<WorkcellPolicy> policies, {
    String model = 'open_manipulator_x',
  }) async {
    final saved = <WorkcellPolicy>[];
    var current = policies;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WorkcellPolicyAttachDialog(
            robotId: 'OMX_01',
            robotName: '픽업 설비',
            robotModel: model,
            policies: policies,
            onSave: (policy) async {
              saved.add(policy);
              // 저장한 뒤의 목록을 돌려주는 것이 실제 화면과 같다.
              current = [
                for (final item in current)
                  if (item.id == policy.id) policy else item,
              ];
              return current;
            },
          ),
        ),
      ),
    );
    return saved;
  }

  testWidgets('설비에 붙은 Policy 와 더 붙일 수 있는 것을 함께 보여 준다', (tester) async {
    await pump(tester, [
      make('can_pick', workcells: const ['OMX_01']),
      make('box_pick'),
      make('arm_pick', model: 'ur5e'),
    ]);

    expect(find.text('OMX_01 · 픽업 설비 Policy'), findsOneWidget);
    expect(find.text('모델 open_manipulator_x · 붙은 Policy 1개'), findsOneWidget);
    expect(find.text('can_pick@1.0.0'), findsOneWidget);
    // 모델이 다른 policy 는 애초에 내밀지 않는다.
    expect(find.text('arm_pick@1.0.0 · 캔'), findsNothing);
  });

  testWidgets('고른 Policy 를 이 설비에 붙인다', (tester) async {
    final saved = await pump(tester, [make('box_pick')]);

    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('box_pick@1.0.0 · 캔').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('이 WorkCell 에 붙이기'));
    await tester.pumpAndSettle();

    expect(saved.single.id, 'box_pick@1.0.0');
    expect(saved.single.deployedWorkcells, ['OMX_01']);
    expect(saved.single.objectType, '캔');
    // 붙은 뒤에는 붙은 목록으로 옮겨 간다.
    expect(find.text('모델 open_manipulator_x · 붙은 Policy 1개'), findsOneWidget);
  });

  testWidgets('물품을 적지 않은 Policy 는 붙이기 전에 물어본다', (tester) async {
    final saved = await pump(tester, [make('box_pick', objectType: '')]);

    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('box_pick@1.0.0').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('이 WorkCell 에 붙이기'));
    await tester.pumpAndSettle();

    expect(saved, isEmpty);
    expect(find.text('이 Policy 로 집을 물품을 적으세요.'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '컵');
    await tester.tap(find.text('이 WorkCell 에 붙이기'));
    await tester.pumpAndSettle();

    expect(saved.single.objectType, '컵');
    expect(saved.single.deployedWorkcells, ['OMX_01']);
  });

  testWidgets('붙은 Policy 를 떼면 프로젝트 연결은 남는다', (tester) async {
    final saved = await pump(tester, [
      make('can_pick', workcells: const ['OMX_01', 'OMX_02']),
    ]);

    await tester.tap(find.byIcon(Icons.link_off));
    await tester.pumpAndSettle();

    expect(saved.single.id, 'can_pick@1.0.0');
    expect(saved.single.deployedWorkcells, ['OMX_02']);
    expect(find.text('이 WorkCell 에 붙은 Policy 가 없습니다.'), findsOneWidget);
  });

  testWidgets('붙일 수 있는 Policy 가 없으면 어디서 등록하는지 알린다', (tester) async {
    await pump(tester, [make('arm_pick', model: 'ur5e')]);

    expect(
      find.text(
        'open_manipulator_x 모델에 붙일 수 있는 Policy 가 없습니다. Policy 관리에서 먼저 등록하세요.',
      ),
      findsOneWidget,
    );
  });
}
