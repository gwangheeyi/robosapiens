/// 어댑터의 도착 소식을 우리 단계에 맞추는 규칙.
///
/// 2026-08-17 13:16~13:19 에 실제로 겪은 일이다. 작업은 넷이었다.
///
///     대기3 → 픽업3 → 적재 → 대기3
///
/// 로그(`project1-ver2.log`)를 보면 로봇은 넷을 다 했다 — 픽업3 에 닿았고,
/// 워크셀이 `동작 완료` 를 냈고, 대기3 으로 돌아왔다. 그런데 화면은 `적재 안 됨 ·
/// 진행중` 이었고, MySQL 에 남은 것도 `currentStepIndex: 1` 이었다.
///
/// 까닭은 첫 소식을 놓친 것이었다. 앱이 작업을 넘긴 **뒤에** 진행 토픽에 붙는
/// 바람에 첫 `navigate_start` 가 사라졌고, 목적지를 모르니 첫 도착도 버려졌다.
/// 그 뒤로는 지금 단계가 늘 대기3 에 멈춰 있어서 픽업3 도착도, 적재 완료도
/// 전부 "안 맞는 소식" 이 되어 버려졌다.
///
/// 아래 좌표는 그 맵에서 그대로 가져왔다(축척 2.1100m / 1823.895px).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:robocontrol/rmf_progress_match.dart';

void main() {
  // project1-ver2 의 nav graph 값.
  const wait3 = ProgressStep(
    kind: ProgressStepKind.movement,
    x: 1.1854543865190408,
    y: -1.0916426902747959,
  );
  const wait4 = ProgressStep(
    kind: ProgressStepKind.movement,
    x: 1.1846490297103089,
    y: -1.6023192741953786,
  );
  const pickup3 = ProgressStep(
    kind: ProgressStepKind.movement,
    x: 1.1865916474087188,
    y: -1.9400854325179644,
  );
  const armLoad = ProgressStep(kind: ProgressStepKind.armLoad);
  const task = [wait3, pickup3, armLoad, wait3];

  int? navigateTo(ProgressStep goal, {required int from}) =>
      matchedProgressStep(
        steps: task,
        currentIndex: from,
        isArmLoad: false,
        goalX: goal.x,
        goalY: goal.y,
      );

  group('이동 도착', () {
    test('지금 단계의 목적지면 그 단계다', () {
      expect(navigateTo(wait3, from: 0), 0);
    });

    test('RMF 가 끼워 넣은 중간 Waypoint 는 넘기지 않는다', () {
      // 대기4 는 우리 작업에 없다. RMF 가 Lane 을 따라 스스로 들른 자리다.
      expect(navigateTo(wait4, from: 0), isNull);
    });

    test('목적지를 모르면 아무것도 넘기지 않는다', () {
      expect(
        matchedProgressStep(steps: task, currentIndex: 0, isArmLoad: false),
        isNull,
      );
    });

    test('앞 단계를 놓쳤으면 따라잡는다', () {
      // 대기3 도착을 놓친 채 픽업3 에 닿았다. 둘 다 끝난 것으로 본다.
      expect(navigateTo(pickup3, from: 0), 1);
    });

    test('적재 단계는 이동 소식으로 뛰어넘지 않는다', () {
      // 픽업3 에 서 있는데 마지막 대기3 도착이 왔다고 해서 적재를 완료로
      // 적으면, 아무도 안 본 적재가 끝난 것이 된다.
      expect(navigateTo(wait3, from: 1), isNull);
    });

    test('적재를 끝낸 뒤의 대기3 은 마지막 단계다', () {
      expect(navigateTo(wait3, from: 3), 3);
    });

    test('같은 자리가 두 번 나와도 가까운 쪽을 짚는다', () {
      // 대기3 은 0 과 3 에 있다. 0 에 서 있으면 0 이지 3 이 아니다.
      expect(navigateTo(wait3, from: 0), 0);
    });
  });

  group('적재 완료', () {
    test('지금 단계가 적재면 그 단계다', () {
      expect(
        matchedProgressStep(steps: task, currentIndex: 2, isArmLoad: true),
        2,
      );
    });

    test('앞 단계에 멈춰 있어도 버리지 않는다', () {
      // 이것이 그날의 증상이었다. 지금 단계가 0(대기3)인 채로 적재 완료가
      // 왔고, 예전에는 여기서 버려서 화면이 영영 `적재 안 됨` 이었다.
      expect(
        matchedProgressStep(steps: task, currentIndex: 0, isArmLoad: true),
        2,
      );
    });

    test('이미 지난 적재는 다시 짚지 않는다', () {
      expect(
        matchedProgressStep(steps: task, currentIndex: 3, isArmLoad: true),
        isNull,
      );
    });

    test('적재가 없는 작업이면 아무것도 넘기지 않는다', () {
      expect(
        matchedProgressStep(
          steps: const [wait3, wait4],
          currentIndex: 0,
          isArmLoad: true,
        ),
        isNull,
      );
    });
  });

  group('그날의 소식을 순서대로 흘려 본다', () {
    test('첫 도착을 놓쳐도 작업이 끝까지 간다', () {
      var current = 0;
      void feed(ProgressStep? goal, {bool armLoad = false}) {
        final matched = matchedProgressStep(
          steps: task,
          currentIndex: current,
          isArmLoad: armLoad,
          goalX: goal?.x,
          goalY: goal?.y,
        );
        if (matched != null) current = matched + 1;
      }

      // 13:16:28 대기3 도착 — navigate_start 를 놓쳐 목적지를 모른다.
      feed(null);
      expect(current, 0);
      // 13:17:02 대기4 도착 — RMF 가 끼워 넣은 자리다.
      feed(wait4);
      expect(current, 0);
      // 13:17:38 픽업3 도착 — 여기서 대기3 까지 함께 따라잡는다.
      feed(pickup3);
      expect(current, 2);
      // 13:18:42 워크셀 적재 완료.
      feed(null, armLoad: true);
      expect(current, 3);
      // 13:18:54 대기4 도착 — 또 중간 자리.
      feed(wait4);
      expect(current, 3);
      // 13:19:10 대기3 도착 — 마지막 단계.
      feed(wait3);
      expect(current, task.length);
    });
  });
}
