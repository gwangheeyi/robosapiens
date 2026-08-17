/// Nav2 `map_server` 가 켜진 채로 있게 지킨다.
///
/// `map_server` 는 생명주기 노드다. `nav2_lifecycle_manager` 가 configure 로
/// 지도를 읽히고 activate 로 넘겨야 비로소 지도를 낸다.
///
/// **그 사이가 끊어진다.** 관리자가 부르는 `change_state` 의 응답 시한이 5초로
/// **코드에 박혀 있다** — 늘릴 파라미터가 없다. 실제로 확인했다:
///
///     $ ros2 param list /lifecycle_manager_map
///       attempt_respawn_reconnection · autostart · bond_respawn_max_duration
///       bond_timeout · node_names · ...          ← service_timeout 이 없다
///
/// 기계가 바쁘면 지도를 읽는 데 5초가 넘고, map_server 는 configure 를 제대로
/// 마쳤는데 응답만 늦게 간다. 관리자는 그것을 실패로 보고 **거기서 멈춘다.
/// 다시 시도하지 않는다.**
///
/// 2026-08-17 에 실제로 그랬다 —
///
///     [map_server.rclcpp] failed to send response to /map_server/change_state
///                         (timeout): client will not receive response
///     [pinky_01.amcl]     Waiting for map....                    (×20)
///     [global_costmap]    Invalid frame ID "map" ... does not exist
///     실행 스크립트        fleet 등록 확인이 3 회 연속 실패했습니다.
///                         어댑터를 재기동합니다.               ← 애먼 곳
///     화면                rmf-nav2 연결 실패
///
/// `map_server` 의 상태는 `inactive` 였다. 손으로 activate(전이 3)를 부르자
/// 곧바로 `/fleet_states` 에 pinky_01 이 (1.613, -1.088) 로 올라왔다.
///
/// **프로세스로는 못 잡는다.** 생명주기 노드라 꺼져 있어도 프로세스는 멀쩡히
/// 살아 있다. 이 저장소의 다른 검사들이 프로세스를 세는 것과 달리, 여기만은
/// 물어봐야 한다.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rmf_control_ui/readiness_check.dart';
import 'package:rmf_control_ui/rmf_project_config.dart';

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

String _runScript() => buildProjectRunScript(
  mapName: 'project1-ver2',
  mapDirectory: '/tmp/project1-ver2',
  robots: const [_pinky],
);

void main() {
  group('실행 스크립트가 지도 서버를 지킨다', () {
    test('상태를 묻고 스스로 켠다', () {
      final code = _runScript();
      expect(code, contains('/map_server/get_state'));
      expect(code, contains('/map_server/change_state'));
      // 전이 번호: 1=configure 3=activate
      expect(code, contains('map_server_transition 1'));
      expect(code, contains('map_server_transition 3'));
    });

    test('한 번 보고 마는 것이 아니라 켜질 때까지 본다', () {
      // 관리자가 다시 시도하지 않으므로 우리가 해야 한다.
      final code = _runScript();
      expect(code, contains('watch_map_server'));
      expect(code, contains('MAP_SERVER_WAIT'));
    });

    test('어댑터 감시자보다 먼저 뜬다', () {
      // 어댑터가 등록에 실패하는 첫 이유가 지도가 없어서다.
      final code = _runScript();
      final map = code.indexOf('watch_map_server &');
      final adapter = code.indexOf('watch_fleet_adapter &');
      expect(map, greaterThanOrEqualTo(0));
      expect(adapter, greaterThan(map));
    });

    test('지도가 없으면 어댑터를 다시 띄우지 않는다', () {
      // 지도가 없는 한 어댑터는 살아 있어도 등록할 수 없다. 30초마다 죽여
      // 봐야 같은 일이 되풀이될 뿐이고, 로그만 원인에서 멀어진다.
      final code = _runScript();
      final health = code.indexOf('fleet 등록 확인이');
      expect(health, greaterThanOrEqualTo(0));
      final before = code.substring(0, health);
      // 재기동을 알리기 **전에** 지도부터 확인하는 갈래가 있어야 한다.
      final guard = before.lastIndexOf('if ! ensure_map_server_active; then');
      expect(guard, greaterThanOrEqualTo(0));
      expect(code.substring(guard, health), contains('어댑터는 그대로 둡니다'));
    });

    test('왜 이런 장치가 필요한지 남긴다', () {
      // 다음 사람이 "관리자가 알아서 하지 않나" 하고 지우지 않도록.
      final code = _runScript();
      expect(code, contains('5초'));
      expect(code, contains('다시 시도하지 않는다'));
      expect(code, contains('Waiting for map'));
    });

    test('만들어진 스크립트를 bash 가 읽을 수 있다', () {
      final bash = Process.runSync('which', ['bash']);
      if (bash.exitCode != 0) {
        markTestSkipped('bash 가 없습니다');
        return;
      }
      final file = File('${Directory.systemTemp.path}/robosapiens_run_check.sh')
        ..writeAsStringSync(_runScript());
      addTearDown(() {
        if (file.existsSync()) file.deleteSync();
      });
      final result = Process.runSync('bash', ['-n', file.path]);
      expect(result.exitCode, 0, reason: '${result.stderr}');
    });
  });

  group('확인표가 원인을 짚는다', () {
    ReadinessReport report({
      required bool fleetReachable,
      String? mapServerState,
    }) => buildReadinessReport(
      waypointNames: const ['충전1', '픽업3'],
      robots: const [_pinky],
      exported: true,
      backendRunning: true,
      fleetReachable: fleetReachable,
      attachedRobots: fleetReachable ? const {'pinky_01'} : const {},
      mapServerState: mapServerState,
      backendUptime: const Duration(minutes: 5),
    );

    ReadinessCheck named(ReadinessReport value, String title) =>
        value.checks.firstWhere((check) => check.title == title);

    test('지도 서버가 멈춰 있으면 그것을 막힌 것으로 보여 준다', () {
      final check = named(
        report(fleetReachable: false, mapServerState: 'inactive'),
        'Nav2 지도 서버',
      );
      expect(check.state, ReadinessState.blocked);
      expect(check.detail, contains('inactive'));
    });

    test('그때 어댑터를 죽었다고 하지 않는다', () {
      // 어댑터는 멀쩡히 살아 있었다. 죽었다고 하면 멀쩡한 어댑터의 원인을
      // 찾느라 시간을 버린다 — 실제로 그렇게 버렸다.
      final check = named(
        report(fleetReachable: false, mapServerState: 'inactive'),
        'RMF↔Nav2 어댑터',
      );
      expect(check.state, ReadinessState.blocked);
      expect(check.detail, isNot(contains('어댑터가 죽었습니다')));
      expect(check.detail, contains('어댑터 탓이 아닙니다'));
      expect(check.detail, contains('지도 서버'));
    });

    test('지도는 켜졌는데 /fleet_states 가 없으면 그때는 어댑터다', () {
      final check = named(
        report(fleetReachable: false, mapServerState: 'active'),
        'RMF↔Nav2 어댑터',
      );
      expect(check.detail, contains('어댑터가 죽었습니다'));
    });

    test('지도 서버가 켜져 있으면 초록불이다', () {
      final check = named(
        report(fleetReachable: true, mapServerState: 'active'),
        'Nav2 지도 서버',
      );
      expect(check.state, ReadinessState.ready);
    });

    test('못 물었으면 멀쩡하다고도 죽었다고도 하지 않는다', () {
      // 뜨는 중일 수 있다. 모르는 것을 빨간불로 두면 30초만 기다리면 될 것을
      // 두고 사람을 뛰게 만든다.
      final check = named(
        report(fleetReachable: false, mapServerState: null),
        'Nav2 지도 서버',
      );
      expect(check.state, ReadinessState.unknown);
    });

    test('지도 서버 항목이 어댑터보다 앞에 온다', () {
      // 사슬 순서대로 보여야 어디서 끊겼는지 눈으로 따라갈 수 있다.
      final value = report(fleetReachable: false, mapServerState: 'inactive');
      final titles = value.checks.map((check) => check.title).toList();
      expect(
        titles.indexOf('Nav2 지도 서버'),
        lessThan(titles.indexOf('RMF↔Nav2 어댑터')),
      );
    });
  });

  group('상태를 묻는 쪽', () {
    test('프로세스가 아니라 서비스로 묻는다', () {
      // 생명주기 노드는 꺼져 있어도 프로세스가 살아 있다. 이 저장소의 다른
      // 검사들이 프로세스를 세는 것과 달리 여기만은 물어봐야 한다.
      final source = File('lib/rmf_runtime_service_io.dart').readAsStringSync();
      final probe = source.indexOf('Future<String?> probeMapServerState');
      expect(probe, greaterThanOrEqualTo(0));
      final body = source.substring(probe, source.indexOf('\n}\n', probe));
      expect(body, contains('/map_server/get_state'));
      expect(body, contains('lifecycle_msgs/srv/GetState'));
      // 도메인을 안 넘기면 아무것도 못 본다. 이 저장소가 세 번 겪은 함정이다.
      expect(body, contains('export ROS_DOMAIN_ID='));
    });
  });
}
