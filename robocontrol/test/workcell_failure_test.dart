/// 워크셀이 실패라고 답했을 때 어댑터가 **삼키지 않는지** 지킨다.
///
/// RMF 는 `perform_action` 이 끝나기를 기다린다. 끝났다고 말하는 것은 어댑터
/// 뿐이다. 어댑터가 아무 말도 안 하면 RMF 는 영원히 기다린다 — 오류도 안 나고
/// 팝업도 안 뜬다. 로봇이 그 자리에 선 채로 남을 뿐이다.
///
/// 2026-08-17 에 실제로 그랬다. 핑키가 픽업3 에 도착해 멈춰 있었고 로그는
/// 여기서 끊겨 있었다 —
///
///     [omx_01]  픽업3: 로봇이 제자리에 섰습니다. 팔을 움직입니다.
///     [omx_01]  픽업3: 적재 중에 로봇이 흔들렸습니다 (0.6cm · 3.4도)
///     [pinky_01] 워크셀 요청 실패 (status=2)
///     (끝. 이후 아무것도 없음)
///
/// 그때 어댑터의 코드는 이랬다 —
///
///     if result.status != DispenserResult.SUCCESS:
///         self.node.get_logger().error(...)
///         return                       ← RMF 에는 아무 말도 안 한다
///
/// **RMF 에 "이 동작이 실패했다" 고 말할 방법이 없다.** EasyFullControl 의
/// `CommandExecution` 에는 `finished()` 만 있고 `okay()` 는 읽기 전용이다
/// (RMF 가 우리에게 알리는 쪽이다) — 직접 확인했다:
///
///     okay(self: rmf_adapter.easy_full_control.CommandExecution) -> bool
///
/// `finished()` 를 부르면 성공한 척이 되어 빈 수납함으로 다음 자리에 간다.
/// 그래서 다시 부탁해 보고, 끝내 안 되면 **작업을 취소한다.**
///
/// 만들어진 어댑터를 실제로 띄워 확인했다(2026-08-17, 격리 도메인 99) —
///
///     워크셀에 부탁한 횟수: 4 (처음 1 + 다시 3)
///     성공한 척하지 않는다 (finished 안 부름)          PASS
///     끝내 안 되면 작업을 취소한다                     PASS
///     보낸 것: {"type": "cancel_task", "task_id": "task-XYZ"}
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:robocontrol/rmf_project_config.dart';

const RmfProjectRobot _pinky = RmfProjectRobot(
  robotId: 'pinky_01',
  displayName: 'PK-01',
  model: 'PINKY-GZ',
  gzName: 'pinky_01',
  zones: ['ambient'],
  dataSource: RobotDataSource.gazebo,
  spawnX: 1.6,
  spawnY: -1,
);

String _adapter() => buildNav2FleetAdapterScript(
  mapName: 'project1-ver2',
  fleetName: 'pinky',
  robots: const [_pinky],
);

/// 메서드 하나의 본문만 떼어 낸다.
String _body(String code, String signature) {
  final start = code.indexOf(signature);
  expect(start, greaterThanOrEqualTo(0), reason: '$signature 이 없습니다');
  final end = code.indexOf('\n    def ', start + signature.length);
  return code.substring(start, end < 0 ? code.length : end);
}

void main() {
  group('실패를 삼키지 않는다', () {
    test('오류만 적고 돌아가지 않는다', () {
      // 이 한 줄이 로봇을 픽업3 에 영원히 세워 두었다.
      final body = _body(_adapter(), 'def on_dispenser_result(self, result):');
      expect(
        body,
        isNot(
          contains(
            "f'[{self.name}] 워크셀 요청 실패 (status={result.status})')\n"
            '                return',
          ),
        ),
      );
      // 실패 갈래는 반드시 다시 부탁하거나 취소한다.
      expect(body, contains('self.retry_workcell_later()'));
      expect(body, contains('self.cancel_current_task()'));
    });

    test('한 번 실패했다고 작업을 접지 않는다', () {
      // 로봇이 도착 직후 자세를 다듬는 동안 걸리면 몇 초 뒤에는 된다.
      final code = _adapter();
      expect(code, contains('WORKCELL_RETRIES = 3'));
      expect(code, contains('WORKCELL_RETRY_SECONDS'));
      expect(code, contains('def send_workcell_request(self):'));
      // 다시 부탁할 때는 새 GUID 를 쓴다 — 워크셀이 같은 GUID 를 이미 끝난
      // 것으로 기억하고 그 답만 되풀이할 수 있다.
      final send = _body(code, 'def send_workcell_request(self):');
      expect(send, contains('uuid.uuid4()'));
    });

    test('성공한 척하지 않는다', () {
      // `finished()` 를 부르면 RMF 는 적재가 됐다고 믿는다. 빈 수납함으로
      // 다음 자리에 간다.
      final body = _body(_adapter(), 'def on_dispenser_result(self, result):');
      final success = body.indexOf('DispenserResult.SUCCESS');
      final finished = body.indexOf('execution.finished()');
      expect(finished, greaterThan(success));
      // 실패를 알리는 자리에는 finished 가 없다.
      final failure = body.indexOf('요청 실패');
      expect(body.indexOf('execution.finished()', failure), -1);
    });

    test('끝내 안 되면 작업을 취소한다', () {
      final code = _adapter();
      final cancel = _body(code, 'def cancel_current_task(self):');
      expect(cancel, contains("'type': 'cancel_task'"));
      expect(cancel, contains('self.task_api.publish(request)'));
      expect(code, contains('from rmf_task_msgs.msg import ApiRequest'));
    });

    test('취소에 쓸 작업 번호를 RMF 에게서 받아 둔다', () {
      // 우리가 붙인 번호가 아니라 RMF 가 준 것이라야 한다. 앱의 작업 번호를
      // 보내면 RMF 는 모르는 작업이라고 답한다.
      final code = _adapter();
      expect(code, contains('from rmf_fleet_msgs.msg import FleetState'));
      final onState = _body(code, 'def on_fleet_state(self, msg):');
      expect(onState, contains('robot.name == self.name'));
      expect(onState, contains('self.current_task_id = robot.task_id'));
    });

    test('작업 번호를 모르면 조용히 넘기지 않는다', () {
      // 그때도 로봇은 그 자리에 남는다. 사람이 알아야 치울 수 있다.
      final cancel = _body(_adapter(), 'def cancel_current_task(self):');
      expect(cancel, contains('취소할 작업 번호를 모릅니다'));
      expect(cancel, contains('화면에서 작업을 취소해 주세요'));
    });

    test('앱에도 실패를 알린다', () {
      final body = _body(_adapter(), 'def on_dispenser_result(self, result):');
      expect(body, contains("event='action_failed'"));
    });
  });

  group('락을 쥔 채로 밖을 부르지 않는다', () {
    test('알리는 일은 전부 락 밖에서 한다', () {
      // 여기서 부르는 것들이 다시 락을 잡는다. 안에서 부르면 멎는다.
      final body = _body(_adapter(), 'def on_dispenser_result(self, result):');
      final lockEnd = body.indexOf('# 락 밖에서 알린다');
      expect(lockEnd, greaterThanOrEqualTo(0));
      final inside = body.substring(0, lockEnd);
      for (final call in const [
        'self.retry_workcell_later()',
        'self.cancel_current_task()',
        'execution.finished()',
        'report(',
      ]) {
        expect(inside, isNot(contains(call)), reason: '$call 이 락 안에 있습니다');
      }
    });
  });

  group('왜 이렇게 했는지 남긴다', () {
    test('RMF 에 실패를 말할 수 없다는 것을 적어 둔다', () {
      // 다음 사람이 "그냥 실패라고 하면 되지 않나" 하고 찾아 헤매지 않도록.
      final code = _adapter();
      expect(code, contains('okay()'));
      expect(code, contains('읽기 전용'));
    });

    test('무슨 일이 있었는지 적어 둔다', () {
      final code = _adapter();
      expect(code, contains('영원히'));
    });
  });
}
