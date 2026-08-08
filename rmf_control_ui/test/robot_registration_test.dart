import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rmf_control_ui/main.dart';

/// 로봇 메뉴에서 로봇을 등록하고, 등록한 로봇만 스폰되는지 확인한다.
///
/// 등록은 원래 맵 관리의 RMF 설정 창 안에만 있었다. 로봇을 다루러 온 사람이
/// 먼저 찾는 곳은 로봇 메뉴인데 거기에는 스폰 버튼만 있었고, 그 스폰은 등록과
/// 아무 관계 없이 이름만 받아 만들었다. 그래서 Gazebo 에 올라가는 로봇과 지도에
/// 보이는 로봇이 서로 달랐다.
void main() {
  Future<void> openRobotMenu(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1600, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const RmfControlApp());
    await tester.tap(find.text('로봇'));
    await tester.pumpAndSettle();
  }

  testWidgets('로봇 메뉴에 로봇 등록이 있다', (tester) async {
    await openRobotMenu(tester);

    expect(find.textContaining('로봇 등록 ·'), findsOneWidget);
    expect(find.text('로봇 등록'), findsOneWidget);
    expect(find.text('충전 Waypoint에서 만들기'), findsOneWidget);
    expect(find.textContaining('등록된 로봇이 없습니다'), findsOneWidget);
  });

  testWidgets('등록하기 전에는 Spawn 을 누를 수 없다', (tester) async {
    await openRobotMenu(tester);

    // 눌러도 아무 일이 없으면 왜 안 되는지 알 수 없다. 버튼을 잠그고
    // 툴팁으로 무엇을 먼저 해야 하는지 알린다.
    final spawn = tester.widget<FilledButton>(
      find.ancestor(
        of: find.text('로봇 Spawn'),
        matching: find.byType(FilledButton),
      ),
    );
    expect(spawn.onPressed, isNull);
    expect(
      tester
          .widget<Tooltip>(
            find.ancestor(
              of: find.text('로봇 Spawn'),
              matching: find.byType(Tooltip),
            ),
          )
          .message,
      contains('등록'),
    );
  });

  testWidgets('충전 Waypoint가 없으면 왜 만들 수 없는지 알린다', (tester) async {
    await openRobotMenu(tester);

    await tester.tap(find.text('충전 Waypoint에서 만들기'));
    await tester.pumpAndSettle();

    expect(find.textContaining('충전 카테고리 Waypoint가 없습니다'), findsOneWidget);
    expect(find.text('충전 Waypoint에서 만들기'), findsWidgets);
  });

  testWidgets('등록하면 목록에 나오고 Spawn 이 열린다', (tester) async {
    await openRobotMenu(tester);

    await tester.tap(find.text('로봇 등록'));
    await tester.pumpAndSettle();
    expect(find.text('이동 로봇'), findsOneWidget);
    expect(find.text('설치 로봇'), findsOneWidget);

    // 기본값이 채워져 있으므로 그대로 저장한다.
    await tester.tap(find.text('저장'));
    await tester.pumpAndSettle();

    expect(find.text('로봇 등록 · 1대'), findsOneWidget);
    expect(find.textContaining('PK-01 · 핑키 1호'), findsWidgets);
    // 아직 지도에 올리지는 않았다.
    expect(find.text('대기'), findsOneWidget);

    final spawn = tester.widget<FilledButton>(
      find.ancestor(
        of: find.text('로봇 Spawn'),
        matching: find.byType(FilledButton),
      ),
    );
    expect(spawn.onPressed, isNotNull);
  });

  testWidgets('등록은 됐지만 맵이 없으면 무엇이 없는지 팝업으로 알린다', (tester) async {
    await openRobotMenu(tester);
    await tester.tap(find.text('로봇 등록').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('저장'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('로봇 Spawn'));
    await tester.pumpAndSettle();

    // 예전에는 대시보드에만 표시되는 경고로 처리해서, 로봇 메뉴에서 누르면
    // 아무 일도 일어나지 않는 것처럼 보였다.
    expect(find.text('로봇 Spawn'), findsWidgets);
    expect(find.textContaining('올릴 Waypoint가 없습니다'), findsOneWidget);
    // 등록은 이미 했으므로 등록하라는 말이 아니어야 한다.
    expect(find.textContaining('등록된 로봇이 없습니다'), findsNothing);
  });

  testWidgets('등록을 지우면 무엇이 함께 사라지는지 알린다', (tester) async {
    await openRobotMenu(tester);
    await tester.tap(find.text('로봇 등록').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('저장'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('등록 해제').first);
    await tester.pumpAndSettle();

    expect(find.text('로봇 등록 해제'), findsOneWidget);
    expect(
      find.textContaining('Gazebo 에 올라오지 않고'),
      findsOneWidget,
      reason: '등록을 지우면 실행에서 빠진다는 것을 먼저 알려야 한다',
    );

    await tester.tap(find.text('등록 해제'));
    await tester.pumpAndSettle();
    expect(find.text('로봇 등록 · 0대'), findsOneWidget);
  });

  testWidgets('설치 로봇을 고르면 자리와 모델이 함께 바뀐다', (tester) async {
    await openRobotMenu(tester);
    await tester.tap(find.text('로봇 등록'));
    await tester.pumpAndSettle();

    // 이동 로봇일 때는 충전 Waypoint 에 서고 3온도 구획 자격이 있다.
    expect(find.text('충전 Waypoint'), findsOneWidget);
    expect(find.text('ambient'), findsOneWidget);

    await tester.tap(find.text('설치 로봇'));
    await tester.pumpAndSettle();

    // 설치 로봇은 설비 자리에 붙고 배차를 받지 않는다.
    expect(find.text('설비 Waypoint'), findsOneWidget);
    expect(find.text('충전 Waypoint'), findsNothing);
    expect(
      find.text('ambient'),
      findsNothing,
      reason: '배차 대상이 아니므로 구획 자격이 필요 없다',
    );
    expect(find.textContaining('fleet adapter 에 들어가지 않습니다'), findsOneWidget);
    // 모델은 open_manipulator_description 에 있는 것 중에서 고른다.
    expect(find.text('open_manipulator_x'), findsOneWidget);
  });

  testWidgets('설치 로봇은 등록되어도 이동 로봇과 구분된다', (tester) async {
    await openRobotMenu(tester);
    await tester.tap(find.text('로봇 등록'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('설치 로봇'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('저장'));
    await tester.pumpAndSettle();

    expect(find.text('로봇 등록 · 1대'), findsOneWidget);
    expect(find.textContaining('OMX-01'), findsWidgets);
    expect(find.textContaining('open_manipulator_x'), findsWidgets);
  });
}
