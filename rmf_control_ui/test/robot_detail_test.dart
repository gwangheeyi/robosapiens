import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rmf_control_ui/main.dart';

/// 로봇을 누르면 그 로봇의 상세가 열린다.
///
/// 예전에는 상세가 작업에만 붙어 있었다. 로봇을 눌렀는데 작업 이야기가 나오면
/// 찾던 것이 아니다.
void main() {
  Future<void> registerRobot(WidgetTester tester, {bool workcell = false}) async {
    await tester.tap(find.text('로봇 등록'));
    await tester.pumpAndSettle();
    if (workcell) {
      await tester.tap(find.text('설치 로봇'));
      await tester.pumpAndSettle();
    }
    await tester.tap(find.text('저장'));
    await tester.pumpAndSettle();
  }

  Future<void> openRobotMenu(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1600, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const RmfControlApp());
    await tester.tap(find.text('로봇'));
    await tester.pumpAndSettle();
  }

  testWidgets('등록 카드를 누르면 그 로봇이 열린다', (tester) async {
    await openRobotMenu(tester);
    await registerRobot(tester);

    await tester.tap(find.textContaining('PK-01 · 핑키 1호').first);
    await tester.pumpAndSettle();

    // 제목이 그 로봇이다.
    expect(find.text('PK-01 · 핑키 1호'), findsWidgets);
    expect(find.text('등록 정보'), findsOneWidget);
    expect(find.text('지금 상태'), findsOneWidget);
    expect(find.text('맡은 작업'), findsOneWidget);
    // 등록에서 정한 것이 그대로 보인다.
    expect(find.text('이동 로봇'), findsWidgets);
    expect(find.text('PINKY-GZ'), findsWidgets);
  });

  testWidgets('설치 로봇은 주행 항목을 보여 주지 않는다', (tester) async {
    await openRobotMenu(tester);
    await registerRobot(tester, workcell: true);

    await tester.tap(find.textContaining('OMX-01').first);
    await tester.pumpAndSettle();

    expect(find.text('설치 로봇'), findsWidgets);
    expect(find.text('open_manipulator_x'), findsWidgets);
    // 한자리에 붙어 있으므로 배터리도 목표 지점도 없다.
    expect(find.text('배터리'), findsNothing);
    expect(find.text('목표 지점'), findsNothing);
    // 설비 자리라고 적는다.
    expect(find.text('설비 자리'), findsOneWidget);
  });

  testWidgets('값의 출처를 크게 보여 준다', (tester) async {
    await openRobotMenu(tester);
    await registerRobot(tester);
    await tester.tap(find.textContaining('PK-01 · 핑키 1호').first);
    await tester.pumpAndSettle();

    // 기본값은 앱 Mock 이다. 그것을 실물로 착각하는 것이 가장 위험하다.
    expect(find.text('앱 Mock 데이터'), findsWidgets);
    expect(find.textContaining('앱이 계산한 값입니다'), findsWidgets);
  });

  testWidgets('배치하지 않은 로봇도 열린다', (tester) async {
    await openRobotMenu(tester);
    await registerRobot(tester);
    await tester.tap(find.textContaining('PK-01 · 핑키 1호').first);
    await tester.pumpAndSettle();

    // 등록만 하고 아직 안 올렸어도 등록 정보는 볼 수 있어야 한다.
    expect(find.textContaining('지도에 배치되지 않았습니다'), findsOneWidget);
    expect(find.textContaining('맡은 작업이 없습니다'), findsOneWidget);
  });
}
