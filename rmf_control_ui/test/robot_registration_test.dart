import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rmf_control_ui/main.dart';

/// `static const _menuXxx = N;` 에서 N 을 읽는다.
int _menuSlot(String source, String name) {
  final match = RegExp('static const $name = (\\d+);').firstMatch(source);
  if (match == null) throw StateError('$name 선언이 없다');
  return int.parse(match.group(1)!);
}

/// 상단 제목 목록을 차례대로 읽는다. 자리 번호로 바로 찾을 수 있게 한다.
List<String> _menuTitles(String source) {
  final start = source.indexOf('title: const [');
  final end = source.indexOf('][_selectedMenu]', start);
  return RegExp("'([^']+)'")
      .allMatches(source.substring(start, end))
      .map((m) => m.group(1)!)
      .toList();
}

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
    // 값이 어디서 오는지도 등록할 때 정한다.
    expect(find.text('값의 출처'), findsOneWidget);

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

  testWidgets('백엔드가 없으면 띄우는 버튼을 보여 준다', (tester) async {
    await openRobotMenu(tester);
    // 확인이 끝날 때까지 기다린다.
    await tester.pump(const Duration(seconds: 13));
    await tester.pumpAndSettle();

    // 내리는 버튼만 있고 띄우는 버튼이 없으면, 없다는 것만 알려주고 어떻게
    // 하라는 말은 없는 셈이 된다.
    expect(find.text('백엔드 띄우기'), findsOneWidget);
    expect(find.text('백엔드 중지'), findsNothing);

    // 프로젝트가 없으면 띄울 수 없다. 왜인지 툴팁으로 알린다.
    final start = tester.widget<FilledButton>(
      find.ancestor(
        of: find.text('백엔드 띄우기'),
        matching: find.byType(FilledButton),
      ),
    );
    expect(start.onPressed, isNull);
    expect(
      tester
          .widget<Tooltip>(
            find.ancestor(
              of: find.text('백엔드 띄우기'),
              matching: find.byType(Tooltip),
            ),
          )
          .message,
      contains('맵 프로젝트'),
    );
  });

  testWidgets('출처는 로봇마다 정하고 화면 전체 설정은 없다', (tester) async {
    await openRobotMenu(tester);
    // 예전에는 화면 위에 `로봇 실행 방식` 하나가 있었다. 그러면 실물 두 대에
    // Gazebo 한 대 같은 구성을 담을 수 없다.
    expect(find.text('로봇 실행 방식'), findsNothing);

    await tester.tap(find.text('로봇 등록'));
    await tester.pumpAndSettle();
    expect(find.text('값의 출처'), findsOneWidget);
    // 등록만 하고 아무것도 안 고른 로봇을 실행에 밀어 넣으면 안 되므로
    // 기본값은 앱 Mock 이다.
    expect(find.text('앱 Mock 데이터'), findsWidgets);
    expect(find.textContaining('fleet adapter 에도 Gazebo 에도'), findsOneWidget);

    await tester.tap(find.text('저장'));
    await tester.pumpAndSettle();
    // 등록 카드와 위쪽 요약 모두 출처를 드러낸다.
    expect(find.textContaining('앱 Mock 데이터'), findsWidgets);
    expect(find.textContaining('앱 Mock 1'), findsOneWidget);
  });

  testWidgets('자리 맞추기가 로봇 메뉴에 있다', (tester) async {
    await openRobotMenu(tester);

    // 좌표를 맞추는 과정이 눈에 안 보이는 곳에서만 일어나면, 로봇이 건물 밖
    // 허공에 떨어져 있어도 사람이 알 길이 없다.
    expect(find.text('자리 맞추기'), findsOneWidget);
  });

  testWidgets('축척이 없으면 무엇을 먼저 해야 하는지 알린다', (tester) async {
    await openRobotMenu(tester);

    await tester.tap(find.text('자리 맞추기'));
    await tester.pumpAndSettle();

    // 지도도 로봇도 없는 상태다. 빈 창만 띄우면 왜 아무것도 없는지 모른다.
    expect(find.textContaining('맵 관리에서 길이 기준'), findsOneWidget);
    expect(find.textContaining('축척(길이 기준)을 재고 로봇을 등록하면'), findsOneWidget);
    // 맞출 것이 없을 때 버튼을 눌리게 두면 눌러도 아무 일이 없다.
    expect(
      tester
          .widget<FilledButton>(
            find.ancestor(
              of: find.text('맞출 것이 없습니다'),
              matching: find.byType(FilledButton),
            ),
          )
          .onPressed,
      isNull,
    );
  });

  group('메뉴 차례', () {
    // 일하는 차례대로 둔다 — 맵을 만들고 → 로봇을 등록하고 → 설정을 내보내고
    // → 백엔드를 띄우고 → 로봇을 올리고 → 작업을 시킨다.
    test('사이드바가 설정 파일을 작업보다 앞에 둔다', () {
      final source = File('lib/main.dart').readAsStringSync();
      final menu = source.substring(
        source.indexOf("(Icons.grid_view_rounded, '대시보드')"),
        source.indexOf("(Icons.analytics_outlined, '운영 분석')"),
      );
      expect(menu.indexOf('맵 관리'), lessThan(menu.indexOf('로봇')));
      expect(menu.indexOf('로봇'), lessThan(menu.indexOf('설정 파일')));
      expect(menu.indexOf('설정 파일'), lessThan(menu.indexOf('작업')));
    });

    test('제목 차례가 사이드바와 같다', () {
      // 어긋나면 설정 파일을 눌렀는데 제목만 작업이라고 나온다.
      final source = File('lib/main.dart').readAsStringSync();
      final titles = source.substring(
        source.indexOf("title: const ["),
        source.indexOf("][_selectedMenu]"),
      );
      expect(titles.indexOf('설정 파일'), lessThan(titles.indexOf('작업')));
    });

    test('메뉴 자리마다 이름이 있다', () {
      // 예전에는 화면 번호가 날숫자로 흩어져 있어, 메뉴를 가운데 하나 끼울 때
      // 뒤의 숫자를 전부 밀어야 했다. 한 군데만 놓치면 설정 파일을 눌렀는데
      // 작업이 열린다. 이름을 붙여 그 실수를 없앤다.
      final source = File('lib/main.dart').readAsStringSync();
      expect(source, isNot(contains('_selectedMenu == 0')));
      expect(source, contains('static const _menuDashboard = 0;'));
      expect(source, contains('static const _menuGrid = 2;'));
    });

    test('화면 번호가 제목 차례와 맞는다', () {
      // 번호와 제목이 어긋나 설정 파일을 눌렀는데 작업이 열린 적이 있다.
      final source = File('lib/main.dart').readAsStringSync();
      final titles = _menuTitles(source);
      // 자리 이름 → 그 자리에 떠야 하는 제목과 화면 위젯.
      const expected = {
        '_menuDashboard': ('대시보드', '_MainDashboard'),
        '_menuGrid': ('그리드맵', '_GridMapPage'),
        '_menuRobots': ('로봇', '_RobotManagementPage'),
        '_menuFiles': ('설정 파일', '_ProjectFilesPage'),
        '_menuTasks': ('작업', '_TaskManagementPage'),
        '_menuLog': ('로그 분석', '_ProjectLogPage'),
        '_menuAnalytics': ('운영 분석', '_OperationsAnalyticsPage'),
      };
      for (final entry in expected.entries) {
        final slot = _menuSlot(source, entry.key);
        expect(
          titles[slot],
          entry.value.$1,
          reason: '${entry.key}($slot) 자리의 제목이 어긋났다',
        );
        final branch = source.indexOf('_selectedMenu == ${entry.key}');
        expect(branch, greaterThan(-1), reason: '${entry.key} 분기가 없다');
        expect(
          source.substring(branch, branch + 90),
          contains(entry.value.$2),
          reason: '${entry.key} 자리에 다른 화면이 붙었다',
        );
      }
    });

    test('넘치는 번호로도 터지지 않는다', () {
      // 폴백이 메뉴보다 짧은 목록을 인덱스로 훑어, 메뉴를 하나 늘리면 범위
      // 넘침으로 터졌다.
      final source = File('lib/main.dart').readAsStringSync();
      expect(source, contains('_ComingSoonPage(title:'));
      expect(
        source.substring(source.indexOf('_ComingSoonPage(title:')),
        isNot(startsWith('_ComingSoonPage(title: const [')),
      );
    });
  });

  group('그리드맵 메뉴', () {
    test('맵 관리 바로 뒤에 온다', () {
      // 도면에서 파생되는 산출물이라 맵 다음이 제자리다.
      final source = File('lib/main.dart').readAsStringSync();
      final menu = source.substring(
        source.indexOf("(Icons.grid_view_rounded, '대시보드')"),
        source.indexOf("(Icons.analytics_outlined, '운영 분석')"),
      );
      expect(menu.indexOf('맵 관리'), lessThan(menu.indexOf('그리드맵')));
      expect(menu.indexOf('그리드맵'), lessThan(menu.indexOf('로봇')));
    });

    testWidgets('왼쪽 메뉴에서 바로 열린다', (tester) async {
      // 맵 관리 패널 안에도 같은 단추가 있지만, 도면을 고친 뒤 지도만 다시
      // 굽는 일이 잦아 찾아 들어가지 않아도 되게 꺼내 두었다.
      tester.view.physicalSize = const Size(1600, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(const RmfControlApp());
      await tester.pumpAndSettle();

      expect(find.text('그리드맵'), findsOneWidget);
      await tester.tap(find.text('그리드맵'));
      await tester.pumpAndSettle();

      expect(find.text('그리드맵 작성'), findsOneWidget);
      // 아무것도 없는 상태에서는 무엇이 모자란지 적어 준다.
      expect(find.text('아직 만들 수 없습니다'), findsOneWidget);
      expect(find.textContaining('도면을 올리세요'), findsOneWidget);
      final button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, '그리드맵 만들기'),
      );
      expect(
        button.onPressed,
        isNull,
        reason: '준비가 안 된 채로 누르면 실패 팝업만 뜬다',
      );
    });

    test('못 만들 때는 흐린 단추만 두지 않고 이유를 적는다', () {
      // 흐린 단추만 있으면 왜 안 되는지 알 수 없어, 사람이 배포를 처음부터
      // 다시 돌린다.
      final source = File('lib/main.dart').readAsStringSync();
      final page = source.substring(source.indexOf('class _GridMapPage'));
      expect(page, contains('아직 만들 수 없습니다'));
      expect(page, contains('도면을 올리세요'));
      expect(page, contains('Measurement 로 축척을 잡으세요'));
      expect(page, contains('Floor 자동 생성을 하세요'));
    });
  });

  group('로그 분석 메뉴', () {
    test('작업 바로 뒤에 온다', () {
      final source = File('lib/main.dart').readAsStringSync();
      final menu = source.substring(
        source.indexOf("(Icons.grid_view_rounded, '대시보드')"),
        source.indexOf("(Icons.analytics_outlined, '운영 분석')"),
      );
      expect(menu.indexOf('작업'), lessThan(menu.indexOf('로그 분석')));
    });

    test('작업 다음 자리다', () {
      final source = File('lib/main.dart').readAsStringSync();
      expect(
        _menuSlot(source, '_menuLog'),
        _menuSlot(source, '_menuTasks') + 1,
      );
    });
  });

  group('로그 고르기', () {
    test('여러 줄을 끌어 고를 수 있다', () {
      // 줄마다 SelectableText 를 두면 그 줄 안에서만 골라진다. 여러 줄을
      // 끌려면 SelectionArea 로 감싸고 안은 보통 Text 여야 한다.
      final source = File('lib/main.dart').readAsStringSync();
      final page = source.substring(source.indexOf('class _ProjectLogPageState'));
      expect(page, contains('SelectionArea('));
      expect(page, isNot(contains('child: SelectableText(\n                                    line.text')));
    });

    test('화면 밖 줄도 선택에 들어간다', () {
      // ListView.builder 는 화면 밖 줄을 만들지 않아 스크롤한 부분이 선택에서
      // 빠진다. 50줄뿐이니 통째로 둔다.
      final source = File('lib/main.dart').readAsStringSync();
      final page = source.substring(source.indexOf('class _ProjectLogPageState'));
      // 주석에는 남아 있으므로 실제로 쓰는지를 본다.
      expect(page, isNot(contains('child: ListView.builder(')));
      expect(page, contains('for (final line in tail.lines)'));
    });
  });
}
