
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rmf_control_ui/main.dart';

/// 로봇 안전 기준 입력 창의 계약을 확인한다.
///
/// 예전에는 값을 해석하지 못하면 `기준 저장`이 아무 일도 하지 않고 조용히
/// 무시했다. 버튼을 눌러도 창이 그대로 있으니 값이 저장되지 않는 것처럼
/// 보였다. 이제는 왜 안 되는지 칸마다 알려 주고, 저장되면 무엇이 적용됐는지
/// 되짚어 준다.
void main() {
  Future<void> openSafetyDialog(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const RmfControlApp());
    await tester.tap(find.text('맵 관리').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('로봇 안전 기준'));
    await tester.pumpAndSettle();
    expect(find.text('로봇 주행 안전 기준'), findsOneWidget);
  }

  Finder fieldByLabel(String label) =>
      find.ancestor(of: find.text(label), matching: find.byType(TextField));

  testWidgets('해석할 수 없는 값이면 이유를 칸에 표시하고 창을 닫지 않는다', (tester) async {
    await openSafetyDialog(tester);

    await tester.enterText(fieldByLabel('로봇 최대 폭 (m)'), '0.2m');
    await tester.enterText(fieldByLabel('최소 회전 반경 (m)'), '');
    await tester.tap(find.text('기준 저장'));
    await tester.pumpAndSettle();

    expect(find.text('숫자로 입력하세요. 예: 0.20'), findsOneWidget);
    expect(find.text('숫자로 입력하세요. 예: 0.15'), findsOneWidget);
    expect(
      find.text('로봇 주행 안전 기준'),
      findsOneWidget,
      reason: '고칠 기회를 주려면 창이 남아 있어야 한다',
    );
  });

  testWidgets('0 이하의 폭은 이유를 밝히고 거절한다', (tester) async {
    await openSafetyDialog(tester);

    await tester.enterText(fieldByLabel('로봇 최대 폭 (m)'), '0');
    await tester.tap(find.text('기준 저장'));
    await tester.pumpAndSettle();

    expect(find.text('0보다 커야 합니다.'), findsOneWidget);
    expect(find.text('로봇 주행 안전 기준'), findsOneWidget);
  });

  testWidgets('쉼표를 소수점으로 쓴 입력도 받는다', (tester) async {
    await openSafetyDialog(tester);

    await tester.enterText(fieldByLabel('로봇 최대 폭 (m)'), '0,2');
    await tester.enterText(fieldByLabel('최소 회전 반경 (m)'), '0,15');
    await tester.enterText(fieldByLabel('위치 오차·안전 여유 (m)'), '0,05');
    await tester.tap(find.text('기준 저장'));
    await tester.pumpAndSettle();

    expect(find.text('로봇 주행 안전 기준'), findsNothing, reason: '창이 닫혀야 한다');
    expect(
      find.textContaining('폭 0.20m · 회전 반경 0.15m · 여유 0.05m'),
      findsOneWidget,
    );
  });

  testWidgets('적용한 값과 어디에 보존되는지 알려 준다', (tester) async {
    await openSafetyDialog(tester);

    await tester.enterText(fieldByLabel('로봇 최대 폭 (m)'), '0.20');
    await tester.tap(find.text('기준 저장'));
    await tester.pumpAndSettle();

    expect(find.text('로봇 주행 안전 기준'), findsNothing);
    expect(find.textContaining('`프로젝트 저장`을 눌러야'), findsOneWidget);

    // 다시 열면 방금 넣은 값이 그대로 있어야 한다.
    await tester.tap(find.text('로봇 안전 기준'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(fieldByLabel('로봇 최대 폭 (m)')).controller!.text,
      '0.20',
    );
  });
}
