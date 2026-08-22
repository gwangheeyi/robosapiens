/// Nav2 가 다 켜졌는지 보는 규칙.
///
/// 실제로 겪은 일이다. 백엔드를 띄웠는데 로봇이 안 움직였다. 프로세스는 다 살아
/// 있고 노드 목록에도 다 나왔다. 오류도 없었다. 그래서 라이다와 AMCL 을 며칠
/// 의심했는데, 정작 원인은 `controller_server` 가 `inactive` 였던 것이다.
///
///     [local_costmap]: Failed to activate local_costmap because transform
///       from pinky_03/base_footprint to pinky_03/odom did not become available
///     [lifecycle_manager]: Failed to bring up all requested nodes.
///       Aborting bringup.
///
/// 까닭은 순서였다. PC 의 Nav2 가 로봇 브링업보다 먼저 떠서, costmap 이 기다리던
/// TF 가 그때는 없었다. 로봇이 나중에 올라와도 관리자는 이미 포기한 뒤라 다시
/// 시도하지 않는다.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:robocontrol/nav2_lifecycle.dart';

void main() {
  Nav2FleetStatus statusOf(Map<String, Nav2NodeState> states) =>
      Nav2FleetStatus(
        robotId: 'pinky_03',
        nodes: [
          for (final name in nav2ManagedNodes)
            Nav2NodeStatus(
              name: name,
              state: states[name] ?? Nav2NodeState.active,
            ),
        ],
      );

  group('lifecycle get 출력을 읽는다', () {
    test('상태 이름을 그대로 읽는다', () {
      expect(parseNav2NodeState('active [3]'), Nav2NodeState.active);
      expect(parseNav2NodeState('inactive [2]'), Nav2NodeState.inactive);
      expect(
        parseNav2NodeState('unconfigured [1]'),
        Nav2NodeState.unconfigured,
      );
    });

    /// `inactive` 안에 `active` 가 들어 있다. 단순 포함 검사로 짜면 안 켜진
    /// 노드를 켜졌다고 읽는다 — 그러면 확인이 있으나 마나 하다.
    test('inactive 를 active 로 잘못 읽지 않는다', () {
      expect(parseNav2NodeState('inactive [2]'), isNot(Nav2NodeState.active));
    });

    /// 모르는 것을 active 로 보면 안 된다. 그러면 안 켜진 로봇에 작업을 넣고
    /// 왜 안 가는지 찾게 된다.
    test('못 읽으면 모른다로 둔다', () {
      expect(parseNav2NodeState(''), Nav2NodeState.unreachable);
      expect(
        parseNav2NodeState('Node not found'),
        Nav2NodeState.unreachable,
      );
    });
  });

  group('작업을 낼 수 있는가', () {
    test('다 켜졌으면 낼 수 있다', () {
      final status = statusOf({});
      expect(status.allActive, isTrue);
      expect(status.canNavigate, isTrue);
      expect(nav2NeedsRecovery(status), isFalse);
      expect(nav2StatusMessage(status), isNull);
    });

    /// 이번에 실제로 겪은 상태다. `bt_navigator` 가 inactive 라
    /// `navigate_to_pose` action 이 아예 없어서, 어댑터가 `Nav2 가 거절했습니다`
    /// 한 줄만 남기고 끝났다.
    test('amcl 만 켜진 상태를 잡아낸다', () {
      final status = statusOf({
        for (final name in nav2ManagedNodes)
          if (name != 'amcl') name: Nav2NodeState.inactive,
      });
      expect(status.allActive, isFalse);
      expect(status.canNavigate, isFalse);
      expect(nav2NeedsRecovery(status), isTrue);
      final message = nav2StatusMessage(status)!;
      expect(message, contains('controller_server'));
      expect(message, contains('bt_navigator'));
      // 왜 겉으로 멀쩡해 보이는지 적어야 한다.
      expect(message, contains('오류'));
    });

    test('꼭 필요한 것이 다 켜지면 갈 수는 있다', () {
      final status = statusOf({'waypoint_follower': Nav2NodeState.inactive});
      expect(status.allActive, isFalse);
      expect(status.canNavigate, isTrue);
      // 그래도 알리기는 한다.
      expect(nav2StatusMessage(status), isNotNull);
    });

    test('안 켜진 것만 골라낸다', () {
      final status = statusOf({'planner_server': Nav2NodeState.inactive});
      expect(status.notActive.map((node) => node.name), ['planner_server']);
    });
  });

  group('Nav2 자체가 없을 때', () {
    final gone = Nav2FleetStatus(
      robotId: 'pinky_03',
      nodes: [
        for (final name in nav2ManagedNodes)
          Nav2NodeStatus(name: name, state: Nav2NodeState.unreachable),
      ],
    );

    /// 다시 켜 봐야 소용없다. 백엔드부터 띄워야 한다.
    test('다시 켜려 들지 않는다', () {
      expect(gone.allUnreachable, isTrue);
      expect(nav2NeedsRecovery(gone), isFalse);
    });

    test('백엔드를 보라고 한다', () {
      expect(nav2StatusMessage(gone), contains('백엔드'));
    });
  });

  group('다시 켠 결과', () {
    final stuck = statusOf({'controller_server': Nav2NodeState.inactive});
    final allOn = statusOf({});
    final gone = Nav2FleetStatus(
      robotId: 'pinky_03',
      nodes: [
        for (final name in nav2ManagedNodes)
          Nav2NodeStatus(name: name, state: Nav2NodeState.unreachable),
      ],
    );

    test('켜졌으면 켜졌다고 한다', () {
      final outcome = nav2RecoveryOutcome(before: stuck, after: allOn);
      expect(outcome, Nav2RecoveryOutcome.recovered);
      expect(
        nav2RecoveryMessage(outcome: outcome, after: allOn),
        contains('작업을 내실 수 있습니다'),
      );
    });

    test('이미 켜져 있었으면 아무 일도 안 한 것이다', () {
      expect(
        nav2RecoveryOutcome(before: allOn, after: allOn),
        Nav2RecoveryOutcome.alreadyActive,
      );
    });

    /// 못 켰으면 무엇을 봐야 하는지까지 적는다. 이번 원인이 TF 였다.
    test('못 켰으면 어디를 볼지 적는다', () {
      final outcome = nav2RecoveryOutcome(before: stuck, after: stuck);
      expect(outcome, Nav2RecoveryOutcome.stillBlocked);
      final message = nav2RecoveryMessage(outcome: outcome, after: stuck);
      expect(message, contains('controller_server'));
      expect(message, contains('odom'));
      expect(message, contains('브링업'));
    });

    test('응답이 없으면 백엔드를 보라고 한다', () {
      final outcome = nav2RecoveryOutcome(before: stuck, after: gone);
      expect(outcome, Nav2RecoveryOutcome.unreachable);
      expect(
        nav2RecoveryMessage(outcome: outcome, after: gone),
        contains('백엔드'),
      );
    });
  });

  /// STARTUP 만 부르면 실패한다. 이미 active 인 노드에 configure 를 걸어서 첫
  /// 노드부터 걸리고, 나머지는 시도조차 안 한다:
  ///
  ///     Configuring amcl
  ///     Failed to change state for node: amcl   ← 이미 active 라 전이가 없다
  ///     Failed to bring up all requested nodes. Aborting bringup.
  ///
  /// amcl 만 active 로 남는 것이 바로 고치려는 상태라, RESET 없이는 거기서
  /// 영영 못 벗어난다.
  group('되살리는 순서', () {
    final source = File('lib/nav2_lifecycle_io.dart').readAsStringSync();
    final body = source.substring(
      source.indexOf('Future<void> activateNav2Nodes('),
    );

    test('RESET 을 STARTUP 보다 먼저 부른다', () {
      final reset = body.indexOf('{command: 1}');
      final startup = body.indexOf('{command: 0}');
      expect(reset, greaterThanOrEqualTo(0), reason: 'RESET 을 안 부른다');
      expect(startup, greaterThan(reset), reason: 'STARTUP 이 RESET 보다 먼저다');
    });

    /// 관리자가 통째로 실패하면 노드를 하나씩 켜서라도 살린다.
    test('그래도 안 되면 하나씩 켠다', () {
      expect(body, contains('lifecycle set'));
      expect(body, contains('activate'));
    });
  });

  group('관리하는 노드 목록', () {
    test('배포 launch 와 같은 차례다 — amcl 이 먼저다', () {
      expect(nav2ManagedNodes.first, 'amcl');
      expect(nav2ManagedNodes, contains('controller_server'));
      expect(nav2ManagedNodes, contains('bt_navigator'));
      expect(nav2ManagedNodes, contains('velocity_smoother'));
    });

    test('꼭 필요한 노드는 관리 목록 안에 있다', () {
      for (final name in nav2EssentialNodes) {
        expect(nav2ManagedNodes, contains(name));
      }
    });
  });
}
