/// 왼쪽 메뉴 · 상단 제목 · 화면 상수가 **같은 차례**인가.
///
/// 셋이 인덱스로 맞물려 있는데 코드는 세 군데에 흩어져 있다. 하나만 고치면
/// 엉뚱한 화면이 열리는데, 화면은 멀쩡히 그려져서 **오류가 안 난다.**
///
/// 실제로 겪은 일이다. 메뉴에서 `작업 관리` 를 위로 올렸더니 제목은 그대로라,
/// 작업 화면을 눌렀는데 Policy 화면이 열렸다. 위젯 시험이 `pumpAndSettle
/// timed out` 으로 죽어서야 알았다.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final source = File('lib/main.dart').readAsStringSync();

  /// 목록 하나에서 따옴표 안의 이름을 차례대로 뽑는다.
  List<String> namesIn(String start, String end) {
    final from = source.indexOf(start);
    expect(from, greaterThanOrEqualTo(0), reason: '$start 를 못 찾았다');
    final to = source.indexOf(end, from);
    expect(to, greaterThan(from), reason: '$end 를 못 찾았다');
    return RegExp("'([^']+)'")
        .allMatches(source.substring(from, to))
        .map((match) => match.group(1)!)
        .toList();
  }

  test('메뉴와 상단 제목이 같은 차례다', () {
    final menu = namesIn('const items = [', '];');
    final titles = namesIn('_TopBar(\n                      title: const [', '][');
    expect(menu, isNotEmpty);
    expect(titles, hasLength(menu.length));
    for (var i = 0; i < menu.length; i++) {
      // `로봇 모델` 과 `로봇 모델 관리` 처럼 제목이 더 긴 경우가 있다.
      expect(
        titles[i].startsWith(menu[i]),
        isTrue,
        reason: '$i 번째가 어긋났다 — 메뉴 `${menu[i]}` · 제목 `${titles[i]}`',
      );
    }
  });

  test('화면 상수가 메뉴 차례를 따른다', () {
    final menu = namesIn('const items = [', '];');
    int indexOfConst(String name) {
      final match = RegExp(
        'static const $name = ([0-9]+);',
      ).firstMatch(source);
      expect(match, isNotNull, reason: '$name 이 없다');
      return int.parse(match!.group(1)!);
    }

    // 이름이 다른 것만 짚어 둔다. 나머지는 위 시험이 차례를 지킨다.
    expect(menu[indexOfConst('_menuDashboard')], '대시보드');
    expect(menu[indexOfConst('_menuMap')], '맵 관리');
    expect(menu[indexOfConst('_menuGrid')], '그리드맵');
    expect(menu[indexOfConst('_menuRobots')], '로봇 관리');
    expect(menu[indexOfConst('_menuTasks')], '작업 관리');
    expect(menu[indexOfConst('_menuPolicies')], 'Policy 관리');
    expect(menu[indexOfConst('_menuRos2')], 'ROS2 확인');
    expect(menu[indexOfConst('_menuFiles')], '설정 파일');
  });

  /// 로봇을 띄우고 작업을 내고 다시 로봇 상태를 보는 일이 가장 잦다. 사이에
  /// 다른 것이 끼면 그때마다 눈이 건너뛰어야 한다.
  test('작업 관리가 로봇 관리 바로 밑이다', () {
    final menu = namesIn('const items = [', '];');
    expect(menu.indexOf('작업 관리'), menu.indexOf('로봇 관리') + 1);
  });
}
