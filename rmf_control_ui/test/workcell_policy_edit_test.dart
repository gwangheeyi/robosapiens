import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rmf_control_ui/workcell_policy.dart';
import 'package:rmf_control_ui/workcell_policy_page.dart';

/// Policy 는 프로젝트별로 가지되 프로젝트보다 오래 남는다.
///
/// 프로젝트를 지워도 policy 는 남아야 하므로 소속은 이름표일 뿐이고, 고치는
/// 것도 이름표뿐이다 — 학습 결과 ZIP 과 그 자리는 건드리지 않는다.
void main() {
  WorkcellPolicy make(
    String name, {
    String version = '1.0.0',
    String? project = 'warehouse',
    String? repository,
    bool missing = false,
    String storageKey = '',
  }) => WorkcellPolicy(
    name: name,
    version: version,
    objectType: '캔',
    robotModel: 'open_manipulator_x',
    archiveName: '$name.zip',
    archiveBytes: 2 * 1024 * 1024,
    deployedWorkcells: const [],
    createdAt: DateTime(2026),
    sourceRepository: repository,
    sourceRevision: repository == null ? null : 'abc123',
    projectName: project,
    storageKey: storageKey,
    archiveMissing: missing,
  );

  group('기본 정보', () {
    test('이름을 바꿔도 파일이 놓인 자리는 그대로다', () {
      final policy = make('can_pick');
      expect(policy.storagePath, 'can_pick/1_0_0');
      final renamed = policy.copyWith(name: 'cola_pick', version: '2.0.0');
      expect(renamed.id, 'cola_pick@2.0.0');
      // 수백 MB 를 옮기지 않는다. 자리는 처음 들여놓을 때 정한 것이다.
      expect(renamed.storagePath, 'can_pick/1_0_0');
    });

    test('소속 프로젝트를 바꾸거나 공용으로 되돌린다', () {
      final policy = make('can_pick');
      expect(policy.copyWith(projectName: 'factory').projectName, 'factory');
      final shared = policy.copyWith(clearProject: true);
      expect(shared.projectName, isNull);
      // 소속만 지웠을 뿐 policy 자체는 그대로 남는다.
      expect(shared.id, policy.id);
      expect(shared.archiveBytes, policy.archiveBytes);
    });

    test('이름이 겹치거나 빈 칸이 있으면 막는다', () {
      final policy = make('can_pick');
      final other = make('box_pick');
      String? check(WorkcellPolicy edited) =>
          validatePolicyEdit(original: policy, edited: edited, others: [other]);

      expect(check(policy.copyWith(objectType: '콜라')), isNull);
      expect(check(policy.copyWith(name: 'box_pick')), contains('이미 있습니다'));
      expect(check(policy.copyWith(version: ' ')), '버전을 입력하세요.');
      expect(check(policy.copyWith(robotModel: '')), '호환 로봇팔 모델을 입력하세요.');
      // 이름은 그대로 두고 버전만 바꾸면 겹치지 않는다.
      expect(check(policy.copyWith(version: '2.0.0')), isNull);
    });

    test('받아 올 곳을 아는 policy 만 다시 받을 수 있다', () {
      expect(make('can_pick', repository: '2usang/can').canDownload, isTrue);
      expect(make('can_pick').canDownload, isFalse);
    });
  });

  group('수정 팝업', () {
    /// 고친 결과를 담아 둘 곳. 팝업이 닫힌 뒤에 읽는다.
    final saved = <WorkcellPolicy>[];

    Future<void> pump(
      WidgetTester tester,
      WorkcellPolicy policy, {
      List<WorkcellPolicy> others = const [],
    }) async {
      saved.clear();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  final edited = await showDialog<WorkcellPolicy>(
                    context: context,
                    builder: (_) => PolicyEditDialog(
                      policy: policy,
                      projects: const ['warehouse', 'factory'],
                      others: others,
                    ),
                  );
                  if (edited != null) saved.add(edited);
                },
                child: const Text('열기'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('열기'));
      await tester.pumpAndSettle();
    }

    testWidgets('이름과 소속 프로젝트를 고쳐 돌려준다', (tester) async {
      final policy = make('can_pick');
      await pump(tester, policy);

      await tester.enterText(
        find.widgetWithText(TextField, 'can_pick'),
        'cola_pick',
      );
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('factory').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('저장'));
      await tester.pumpAndSettle();

      expect(find.text('저장'), findsNothing);
      expect(saved.single.id, 'cola_pick@1.0.0');
      expect(saved.single.projectName, 'factory');
      // 이름표만 고쳤다. 학습 결과가 놓인 자리는 그대로다.
      expect(saved.single.storagePath, policy.storagePath);
      expect(saved.single.archiveBytes, policy.archiveBytes);
    });

    testWidgets('공용으로 되돌릴 수 있다', (tester) async {
      await pump(tester, make('can_pick'));

      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('공용 (소속 없음)').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('저장'));
      await tester.pumpAndSettle();

      expect(saved.single.projectName, isNull);
    });

    testWidgets('이미 있는 이름이면 저장하지 않고 이유를 적는다', (tester) async {
      await pump(tester, make('can_pick'), others: [make('box_pick')]);

      await tester.enterText(
        find.widgetWithText(TextField, 'can_pick'),
        'box_pick',
      );
      await tester.tap(find.text('저장'));
      await tester.pumpAndSettle();

      expect(
        find.text('box_pick@1.0.0 는 이미 있습니다. 이름이나 버전을 다르게 하세요.'),
        findsOneWidget,
      );
      // 팝업은 그대로 열려 있다.
      expect(find.text('저장'), findsOneWidget);
    });

    testWidgets('학습 결과는 고치지 않는다고 밝힌다', (tester) async {
      await pump(tester, make('can_pick'));
      expect(find.textContaining('학습 결과(ZIP)는 고치지 않습니다'), findsOneWidget);
    });
  });

  group('목록 한 줄', () {
    Future<void> pumpTile(
      WidgetTester tester,
      WorkcellPolicy policy, {
      String? openProject = 'warehouse',
      VoidCallback? onDownload,
      VoidCallback? onRestore,
      VoidCallback? onClaim,
      VoidCallback? onRelease,
      VoidCallback? onDelete,
    }) => tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PolicyListTile(
            policy: policy,
            openProject: openProject,
            onEdit: () {},
            onDownload: onDownload,
            onRestore: onRestore,
            onClaim: onClaim,
            onRelease: onRelease,
            onDelete: onDelete,
          ),
        ),
      ),
    );

    testWidgets('파일이 없으면 그렇게 적고 받는 단추를 내민다', (tester) async {
      var downloaded = false;
      await pumpTile(
        tester,
        make('can_pick', repository: '2usang/can', missing: true),
        onDownload: () => downloaded = true,
      );

      expect(find.text('파일 없음'), findsOneWidget);
      expect(
        find.textContaining('ZIP 은 git 에 올리지 않으므로 다시 받아야'),
        findsOneWidget,
      );
      await tester.tap(find.text('Hugging Face에서 내려받기'));
      expect(downloaded, isTrue);
    });

    testWidgets('받아 올 곳을 모르면 ZIP 을 다시 올리라고 한다', (tester) async {
      await pumpTile(tester, make('can_pick', missing: true), onRestore: () {});

      expect(find.text('Hugging Face에서 내려받기'), findsNothing);
      expect(find.text('ZIP 다시 올리기'), findsOneWidget);
      expect(find.textContaining('받아 올 곳도 모릅니다'), findsOneWidget);
    });

    testWidgets('파일이 있으면 받는 단추가 없다', (tester) async {
      await pumpTile(tester, make('can_pick', repository: '2usang/can'));

      expect(find.text('파일 없음'), findsNothing);
      expect(find.text('Hugging Face에서 내려받기'), findsNothing);
      expect(find.text('ZIP 다시 올리기'), findsNothing);
      expect(find.text('수정'), findsOneWidget);
    });

    testWidgets('공용 policy 는 가져올 수 있고, 내 것은 뗄 수 있다', (tester) async {
      await pumpTile(tester, make('can_pick', project: null), onClaim: () {});
      expect(find.text('공용'), findsOneWidget);
      expect(find.text('warehouse 프로젝트로 가져오기'), findsOneWidget);
      expect(find.textContaining('프로젝트: 공용 (소속 없음)'), findsOneWidget);

      await pumpTile(tester, make('can_pick'), onRelease: () {});
      expect(find.text('프로젝트에서 떼기'), findsOneWidget);
      expect(find.textContaining('프로젝트: warehouse'), findsOneWidget);
    });
  });
}
