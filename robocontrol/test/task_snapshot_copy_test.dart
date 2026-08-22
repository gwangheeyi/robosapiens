/// 작업 화면의 `상황 복사` 를 지킨다.
///
/// 막힌 자리를 남에게 전할 때 화면을 눈으로 옮겨 적으면 준비 상태와 단계별
/// 상태가 빠진다 — 정작 원인은 대개 그 두 곳에 있다. 그래서 이 단추가 그 둘을
/// **반드시** 담는지를 본다. 단추가 눌리는지만 보면 빈 글을 복사해도 지나간다.
library;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:robocontrol/main.dart';

void main() {
  late List<String> copied;

  setUp(() {
    copied = [];
    TestDefaultBinaryMessengerBinding
        .instance
        .defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            copied.add((call.arguments as Map)['text'] as String);
          }
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding
        .instance
        .defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  Future<void> openTasks(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1600, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const RmfControlApp());
    await tester.tap(find.text('작업 관리').first);
    await tester.pumpAndSettle();
  }

  testWidgets('작업 화면에 상황 복사 단추가 있다', (tester) async {
    await openTasks(tester);
    expect(find.text('상황 복사'), findsOneWidget);
  });

  testWidgets('누르면 화면의 상황을 클립보드에 담는다', (tester) async {
    await openTasks(tester);
    await tester.tap(find.text('상황 복사'));
    await tester.pumpAndSettle();

    expect(copied, hasLength(1));
    final text = copied.single;

    // 언제 찍은 것인지 — 시각이 없으면 지난 화면과 구별이 안 된다.
    expect(text, contains('=== 작업 관리 · '));

    // 준비 확인표. 화면에 보이는 것을 그대로 담아야 한다.
    expect(text, contains('[준비 상태]'));
    expect(text, contains('Open-RMF 실행'));

    // 집계·로봇·작업 세 묶음.
    expect(text, contains('[집계] 전체 0'));
    expect(text, contains('Spawn 된 로봇이 없습니다.'));
    expect(text, contains('생성된 작업이 없습니다.'));
  });

  testWidgets('복사했다고 알려 준다', (tester) async {
    // 조용히 복사되면 눌렸는지 몰라 몇 번을 더 누르게 된다.
    await openTasks(tester);
    await tester.tap(find.text('상황 복사'));
    await tester.pump();
    expect(find.text('지금 화면의 상황을 복사했습니다.'), findsOneWidget);
  });
}
