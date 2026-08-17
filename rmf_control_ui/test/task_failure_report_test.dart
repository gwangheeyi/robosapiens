/// 작업이 실패했으면 화면도 실패라고 말하는지 지킨다.
///
/// 어댑터는 여섯 가지 소식을 낸다 —
///
///     navigate_start   navigate_done   navigate_failed
///     action_start     action_done     action_failed
///
/// 앱은 그중 넷만 받고 `*_failed` 둘은 조용히 버렸다. `_handleRmfProgress` 의
/// 마지막이 `if (event.event != 'navigate_done') return;` 이라, 실패 소식이
/// 거기 걸려 사라졌다.
///
/// 2026-08-17 에 실제로 그랬다 —
///
///     워크셀 요청이 3번 다시 부탁해도 계속 실패했습니다. 작업을 취소합니다
///     [pinky_01] 작업 [rmf_control_ui-c1255bac] 취소를 보냈습니다.
///     RMF: Executing go_to_place [대기3] → Goal succeeded
///     /fleet_states: task_id: ''          ← RMF 쪽은 이미 끝났다
///
/// 백엔드는 다 정리됐는데 **화면만 계속 `진행중`** 이었다. 로봇은 대기3 에
/// 서 있고, 사람은 무엇이 잘못됐는지 로그를 열기 전에는 알 수 없었다.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rmf_control_ui/rmf_task_models.dart';

void main() {
  group('실패 소식이 앱까지 온다', () {
    test('어댑터가 내는 그대로 읽힌다', () {
      final progress = RmfTaskProgress.parse(
        '{"robot": "pinky_01", "event": "action_failed", '
        '"category": "armLoad"}',
      );
      expect(progress, isNotNull);
      expect(progress!.event, 'action_failed');
      expect(progress.category, 'armLoad');
    });

    test('끝난 소식으로 친다', () {
      RmfTaskProgress of(String event) =>
          RmfTaskProgress(robotId: 'pinky_01', event: event);
      expect(of('action_failed').isFailure, isTrue);
      expect(of('navigate_failed').isFailure, isTrue);
      expect(of('action_failed').isFinish, isTrue);
      expect(of('navigate_failed').isFinish, isTrue);
      // 잘 끝난 것과는 가른다.
      expect(of('action_done').isFailure, isFalse);
      expect(of('action_done').isFinish, isTrue);
      expect(of('action_start').isFinish, isFalse);
    });
  });

  group('화면이 실패를 받아 넘긴다', () {
    late String source;
    setUpAll(() => source = File('lib/main.dart').readAsStringSync());

    String handler() {
      final start = source.indexOf(
        'void _handleRmfProgress(RmfTaskProgress event) {',
      );
      expect(start, greaterThanOrEqualTo(0));
      return source.substring(start, source.indexOf('\n  }\n', start));
    }

    test('실패 소식을 버리지 않는다', () {
      final body = handler();
      expect(body, contains("event.event == 'action_failed'"));
      expect(body, contains("event.event == 'navigate_failed'"));
      expect(body, contains('_failRobotTask('));
    });

    test('실패를 마지막 `navigate_done` 검사보다 먼저 잡는다', () {
      // 그 검사에 걸리면 조용히 사라진다. 순서가 곧 동작이다.
      final body = handler();
      final failure = body.indexOf("event.event == 'action_failed'");
      final guard = body.indexOf("if (event.event != 'navigate_done') return;");
      expect(failure, greaterThanOrEqualTo(0));
      expect(guard, greaterThan(failure));
    });

    test('무엇이 안 됐는지 사람에게 말한다', () {
      // 로그를 열기 전에는 알 수 없으면 안 된다.
      final body = handler();
      expect(body, contains('_showProcessingWarning('));
      expect(body, contains('설비가 끝내지 못했습니다'));
      expect(body, contains('목적지로 가지 못했습니다'));
    });

    test('RMF 가 계속 모는 로봇의 좌표를 앱이 뺏지 않는다', () {
      // 어댑터가 작업을 취소하면 RMF 는 그 로봇을 대기 자리로 보낸다. 그
      // 이동도 RMF 가 몬다. 여기서 `rmfDriven` 을 내리면 앱이 좌표를 직접
      // 옮기기 시작해 토픽으로 오는 진짜 위치와 싸운다 — 화면의 로봇이 두
      // 자리를 오간다.
      final body = handler();
      expect(body, contains('keepRmfDriven: true'));
    });
  });

  group('실패로 끝낼 때', () {
    late String source;
    setUpAll(() => source = File('lib/main.dart').readAsStringSync());

    String failBody() {
      final start = source.indexOf('  void _failRobotTask(');
      expect(start, greaterThanOrEqualTo(0));
      return source.substring(start, source.indexOf('\n  }\n', start));
    }

    test('RMF 가 모는 경우와 아닌 경우를 가른다', () {
      final body = failBody();
      expect(body, contains('bool keepRmfDriven = false'));
      expect(body, contains('rmfDriven = false'));
      // 켜져 있으면 내리지 않는다.
      final branch = body.indexOf('if (keepRmfDriven) {');
      expect(branch, greaterThanOrEqualTo(0));
      expect(body.indexOf('rmfDriven = false'), greaterThan(branch));
    });

    test('작업을 붙들고 있던 로봇을 풀어 준다', () {
      final body = failBody();
      for (final field in const [
        'activeTaskId = null',
        'rmfTaskId = null',
        'rmfGoalX = null',
        'rmfGoalY = null',
      ]) {
        expect(body, contains(field), reason: '$field 이 없습니다');
      }
    });

    test('못 끝낸 나머지 단계를 대기로 두지 않는다', () {
      // 대기로 두면 이력에서 이 작업이 어디까지 갔었는지 알 수 없다.
      final body = failBody();
      expect(body, contains('_TaskStepStatus.cancelled'));
      expect(body, contains('_TaskStepStatus.failed'));
    });

    test('이력에 남긴다', () {
      final body = failBody();
      expect(body, contains('_MockTaskStatus.failed'));
      expect(body, contains('completedAt = DateTime.now()'));
      expect(body, contains('_saveMockTasks()'));
    });
  });
}
