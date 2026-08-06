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
    expect(find.text('오류 검증'), findsOneWidget);
    expect(find.text('경로 추천'), findsOneWidget);
    expect(find.text('창고 도면을 올려주세요'), findsOneWidget);
    expect(find.text('맵 생성 설정'), findsOneWidget);

    await tester.tap(find.text('로봇'));
    await tester.pumpAndSettle();

    expect(find.text('로봇 운영'), findsOneWidget);
    expect(find.text('로봇 Spawn'), findsOneWidget);
    expect(find.text('배포 맵 불러오기'), findsOneWidget);
    expect(find.text('Gazebo · RViz 끔'), findsOneWidget);

    await tester.tap(find.text('배포 맵 불러오기'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('배포된 맵 불러오기'), findsOneWidget);
    await tester.tap(find.text('취소'));
    await tester.pump(const Duration(milliseconds: 400));

    await tester.tap(find.text('작업'));
    await tester.pumpAndSettle();

    expect(find.text('작업 관리'), findsOneWidget);
    expect(find.text('새 작업'), findsOneWidget);
    expect(find.text('생성된 작업이 없습니다.'), findsOneWidget);
    expect(find.text('1단계: 배포 맵을 불러오세요.'), findsOneWidget);

    await tester.tap(find.text('새 작업'));
    await tester.pumpAndSettle();
    expect(find.text('작업 준비가 필요합니다'), findsOneWidget);
    expect(find.text('배포 맵 불러오기'), findsWidgets);
  });
}
