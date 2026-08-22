/// 도면 아래 Waypoint 좌표표가 맵 관리 화면에 실제로 붙어 있는가.
///
/// 값 고르기 규칙은 `waypoint_table_test.dart` 가 본다. 여기서 보는 것은
/// **화면에 있는가** 다 — 규칙이 아무리 맞아도 화면에 안 붙어 있으면 사람은
/// 여전히 도면을 끌어서 맞춘다.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:robocontrol/main.dart';

void main() {
  Future<void> openMapMenu(WidgetTester tester) async {
    // 화면을 길게 잡아 표까지 한 번에 담는다. 맵 화면에는 스크롤 되는 것이
    // 여럿이라 `scrollUntilVisible` 이 어느 것을 굴릴지 못 고른다.
    tester.view.physicalSize = const Size(1600, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const RmfControlApp());
    await tester.tap(find.text('맵 관리').first);
    await tester.pumpAndSettle();
  }

  testWidgets('맵 관리 화면에 Waypoint 좌표표가 있다', (tester) async {
    await openMapMenu(tester);

    final header = find.text('Waypoint 좌표표');
    expect(header, findsOneWidget);

    // 거리를 아직 안 재었으면 미터로는 못 고친다. 모르는 값을 0 으로 적으면
    // 사람이 그것을 믿는다.
    expect(find.text('축척 미측정 · 미터 잠김'), findsOneWidget);
  });

  testWidgets('접었다 펴면 무엇을 고칠 수 있는지 알려 준다', (tester) async {
    await openMapMenu(tester);

    final header = find.text('Waypoint 좌표표');

    // 기본은 접혀 있다. Waypoint 가 수십 개인 맵에서 늘 펼쳐 두면 도면이 화면
    // 위로 밀려 올라간다.
    expect(find.textContaining('아직 Waypoint 가 없습니다'), findsNothing);

    await tester.tap(header);
    await tester.pumpAndSettle();

    expect(find.textContaining('아직 Waypoint 가 없습니다'), findsOneWidget);
    expect(
      find.textContaining('거리를 아직 안 재어'),
      findsOneWidget,
      reason: '왜 미터 칸이 잠겼는지 그 자리에서 밝혀야 한다',
    );
  });
}
