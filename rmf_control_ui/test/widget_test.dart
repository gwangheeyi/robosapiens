import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:rmf_control_ui/main.dart';

void main() {
  testWidgets('관제 맵 업로드 화면을 표시한다', (tester) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const RmfControlApp());

    expect(find.text('새 창고 맵 만들기'), findsOneWidget);
    expect(find.text('도면 올리기'), findsOneWidget);
    expect(find.text('창고 도면을 올려주세요'), findsOneWidget);
    expect(find.text('맵 생성 설정'), findsOneWidget);
  });
}
