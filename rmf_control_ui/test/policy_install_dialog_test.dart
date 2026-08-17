import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rmf_control_ui/movable_dialog.dart';
import 'package:rmf_control_ui/workcell_policy.dart';
import 'package:rmf_control_ui/workcell_policy_page.dart';

/// Policy 설치는 수백 MB를 받는 일이라 몇 분씩 걸린다. 도는 원만 보이면 멈춘
/// 것인지 알 수 없으므로 몇 %인지 막대와 숫자로 보여야 한다.
void main() {
  Future<ValueNotifier<PolicyInstallProgress>> pumpDialog(
    WidgetTester tester, {
    VoidCallback? onCancel,
  }) async {
    final progress = ValueNotifier(
      const PolicyInstallProgress(phase: PolicyInstallPhase.metadata),
    );
    addTearDown(progress.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PolicyInstallDialog(
            title: 'Hugging Face에서 Policy 설치',
            progress: progress,
            onCancel: onCancel,
          ),
        ),
      ),
    );
    return progress;
  }

  double? barValue(WidgetTester tester) => tester
      .widget<LinearProgressIndicator>(find.byKey(PolicyInstallDialog.barKey))
      .value;

  testWidgets('내려받는 동안 퍼센트와 막대가 함께 오른다', (tester) async {
    final progress = await pumpDialog(tester);
    expect(find.text('파일 목록 확인 중 · 0%'), findsOneWidget);

    progress.value = const PolicyInstallProgress(
      phase: PolicyInstallPhase.download,
      receivedBytes: 200 * 1024 * 1024,
      totalBytes: 400 * 1024 * 1024,
      fileName: 'model.safetensors',
      completedFiles: 1,
      totalFiles: 3,
    );
    await tester.pump();

    expect(find.text('내려받는 중 · 44%'), findsOneWidget);
    expect(find.text('model.safetensors · 200.0MB / 400.0MB'), findsOneWidget);
    expect(barValue(tester), closeTo(.44, .01));

    progress.value = const PolicyInstallProgress(
      phase: PolicyInstallPhase.save,
      fileName: 'act_pick.zip',
    );
    await tester.pump();
    expect(find.text('저장·배포 중 · 95%'), findsOneWidget);
    expect(barValue(tester), closeTo(.95, .01));
  });

  testWidgets('취소할 수 있는 단계에서만 취소 단추가 있다', (tester) async {
    await pumpDialog(tester);
    expect(find.text('취소'), findsNothing);

    var cancelled = false;
    await pumpDialog(tester, onCancel: () => cancelled = true);
    await tester.tap(find.text('취소'));
    expect(cancelled, isTrue);
  });

  testWidgets('진행률 팝업도 끌어서 옮길 수 있다', (tester) async {
    final progress = ValueNotifier(
      const PolicyInstallProgress(phase: PolicyInstallPhase.download),
    );
    addTearDown(progress.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showMovableDialog<void>(
                context: context,
                barrierDismissible: false,
                builder: (_) =>
                    PolicyInstallDialog(title: '설치', progress: progress),
              ),
              child: const Text('열기'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('열기'));
    await tester.pumpAndSettle();

    final before = tester.getTopLeft(find.byKey(PolicyInstallDialog.barKey));
    await tester.drag(
      find.byKey(MovableDialog.handleKey),
      const Offset(120, 60),
    );
    await tester.pump();
    final after = tester.getTopLeft(find.byKey(PolicyInstallDialog.barKey));
    expect(after - before, const Offset(120, 60));
  });
}
