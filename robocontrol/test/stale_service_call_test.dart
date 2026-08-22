/// 지난 실행이 남긴 `ros2 service call` 을 스크립트가 스스로 거둔다.
///
/// 그 명령은 상대가 없으면 **영원히 기다린다.** `timeout` 이 없던 판으로 띄운
/// 것이 남아 있으면 계속 매달린 채로 같은 도메인을 쓴다 — 실측(2026-08-17)
/// 세 개가 30분 넘게 남아 있었다.
///
/// 다만 `ros2 service call` 을 통째로 죽이면 안 된다. 사람이 터미널에서 다른
/// 서비스를 부르고 있을 수 있다. 우리가 부르는 그 서비스 이름만 골라야 한다.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:robocontrol/rmf_project_config.dart';
import 'package:robocontrol/ros_probe_io.dart';

/// Nav2 를 쓰는 이동 로봇이 있어야 지도 서버 감시 대목이 나온다.
const RmfProjectRobot _pinky = RmfProjectRobot(
  robotId: 'pinky_01',
  displayName: '핑키 1호',
  model: 'pinky',
  gzName: 'pinky_01',
  zones: [],
  kind: RmfRobotKind.mobile,
  dataSource: RobotDataSource.gazebo,
  spawnX: 1,
  spawnY: -1,
);

String get _runScript => buildProjectRunScript(
  mapName: 'demo',
  mapDirectory: '/maps/demo',
  robots: const [_pinky],
);

String get _stopScript =>
    buildProjectStopScript(mapName: 'demo', mapDirectory: '/maps/demo');

void main() {
  test('실행 스크립트가 지도 서버를 묻기 전에 거둔다', () {
    expect(_runScript, contains('sweep_stale_map_server_calls'));
    // 묻는 자리(watch_map_server)에서 먼저 부른다.
    final atWatch = _runScript.indexOf('watch_map_server() {');
    final atSweep = _runScript.indexOf(
      'sweep_stale_map_server_calls\n',
      atWatch,
    );
    expect(atSweep, greaterThan(atWatch));
  });

  test('중지 스크립트도 매달린 문의를 거둔다', () {
    expect(_stopScript, contains("ros2 service call /map_server/"));
    expect(_stopScript, contains('매달려 있던 지도 서버 문의를 정리했습니다'));
  });

  test('ros2 service call 을 통째로 죽이지 않는다', () {
    for (final script in [_runScript, _stopScript]) {
      // 우리가 부르는 서비스 경로까지 들어간 패턴만 쓴다.
      expect(script, isNot(contains("-f 'ros2 service call'")));
      expect(script, isNot(contains('pkill -f "ros2 service call"')));
      expect(script, contains("ros2 service call /map_server/"));
      // 남의 계정 것은 손대지 않는다.
      expect(script, contains(r'pgrep -u "$(id -u)" -f'));
    }
  });

  test('실행 중인 제 프로세스 그룹은 건드리지 않는다', () {
    // 우리 것은 `timeout` 이 거둔다. 여기서 죽이면 방금 띄운 폴링을 제가 끊는다.
    expect(_runScript, contains(r'ps -o pgid= -p $$'));
    expect(_runScript, contains(r'"$pgid" == "$mine"'));
  });

  test('bash 가 읽을 수 있는 스크립트다', () {
    if (Process.runSync('which', ['bash']).exitCode != 0) {
      markTestSkipped('bash 가 없습니다');
      return;
    }
    final directory = Directory.systemTemp.createTempSync('sweep_script');
    addTearDown(() => directory.deleteSync(recursive: true));
    for (final entry in {
      'run.sh': _runScript,
      'stop.sh': _stopScript,
    }.entries) {
      final file = File('${directory.path}/${entry.key}')
        ..writeAsStringSync(entry.value);
      final result = Process.runSync('bash', ['-n', file.path]);
      expect(result.exitCode, 0, reason: '${entry.key}: ${result.stderr}');
    }
  });

  test('띄우기 전에 지난 실행의 DDS 공유메모리를 치운다', () {
    // 실측(2026-08-17) — /dev/shm 에 fastrtps_* 484개(48MB)가 쌓이자
    // lifecycle_manager 가 `Waiting for service map_server/get_state...` 만
    // 되풀이했다. 노드는 살아 있는데 서비스가 안 보이는 상태다.
    expect(_runScript, contains('sweep_stale_dds_segments'));
    expect(_runScript, contains('fastrtps_*'));
    // 도는 것이 있으면 손대지 않는다. 산 참가자의 조각을 지우면 그 노드가
    // 통째로 먹통이 된다.
    expect(_runScript, contains('ROS 프로세스가 도는 중이라'));
    // 치우기는 시뮬레이터를 띄우기 **전에** 부른다.
    final atSweep = _runScript.indexOf('\nsweep_stale_dds_segments\n');
    final atStage = _runScript.indexOf('[1/3] 시뮬레이션 백엔드');
    expect(atSweep, greaterThan(0));
    expect(atSweep, lessThan(atStage));
  });

  test('탐색 캐시를 든 데몬도 함께 내린다', () {
    expect(_runScript, contains('ros2 daemon stop'));
  });

  test('앱의 검사는 시한을 넘기면 프로세스까지 끊는다', () async {
    // 이것이 진짜 원인이었다. `Process.run(...).timeout(...)` 은 기다리기만
    // 그만두고 프로세스는 그대로 둬서, 검사를 할 때마다 매달린 `ros2 service
    // call` 이 앱의 프로세스 그룹에 하나씩 쌓였다(실측 2026-08-17, 5개).
    final marker = 'robosapiens_probe_${DateTime.now().microsecondsSinceEpoch}';
    final started = DateTime.now();
    final result = await runRosProbe(
      'sleep 120 # $marker',
      timeout: const Duration(seconds: 2),
    );
    expect(result, isNotNull, reason: 'timeout 이 끊고 결과를 돌려준다');
    // 시한 안에 돌아온다. 120초를 기다리지 않는다.
    expect(DateTime.now().difference(started).inSeconds, lessThan(15));
    expect(result!.exitCode, isNot(0));

    // 그리고 남은 것이 없어야 한다.
    await Future<void>.delayed(const Duration(seconds: 1));
    final leftover = Process.runSync('pgrep', ['-f', marker]);
    addTearDown(() => Process.runSync('pkill', ['-f', marker]));
    expect(
      leftover.exitCode,
      isNot(0),
      reason: '매달린 프로세스가 남았습니다: ${leftover.stdout}',
    );
  });
}
