/// 배포가 남긴 Building Map Server 를 백엔드로 착각하지 않게 지킨다.
///
/// `deploy_map.sh` 는 배포를 마치고 `building_map_server` 하나를 **일부러 띄운
/// 채로** 끝난다 — 배포한 지도를 바로 볼 수 있게 하려는 것이다.
///
///     nohup ros2 run rmf_building_map_tools building_map_server \
///       "$TARGET_DIR/$MAP_NAME.building.yaml" ... &
///     echo $! >"$RUNTIME_DIR/building_map_server.pid"
///
/// 그 명령줄에 **맵 디렉터리 경로가 들어 있다.** 그런데 앱은 맵 디렉터리를 물고
/// 있는 프로세스를 세어 백엔드가 도는지 판단한다. 그래서 배포만 하고 아무것도
/// 안 띄웠는데 백엔드가 돈다고 답했다.
///
/// 실측(2026-08-17, 백엔드는 내려간 상태에서 지도 서버 하나만 띄움) —
///
///     $ pgrep -af .../rmf_maps/project1-ver2 | grep -cv stop_
///     2      ← ros2 run 껍데기와 building_map_server
///
/// 그 결과 —
///
///     앱          "백엔드 실행 중"      (Gazebo·RMF·Nav2·어댑터가 다 없는데)
///     확인표       뒤 단계가 `모른다` 가 아니라 `막힘`
///     화면         rmf-nav2 연결 실패
///     백엔드 돌리기 이미 실행 중이라 거절
///
/// 그리고 백엔드를 띄우면 launch 가 **같은 파일로 제 것을 하나 더** 띄운다.
/// `/building_map_server` 라는 같은 이름의 노드가 둘이 되고 `/get_building_map`
/// 을 두 곳이 답한다.
library;

import 'dart:io';

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

String _run() => buildProjectRunScript(
  mapName: 'project1-ver2',
  mapDirectory: '/tmp/project1-ver2',
  robots: const [_pinky],
);

String _stop() => buildProjectStopScript(
  mapName: 'project1-ver2',
  mapDirectory: '/tmp/project1-ver2',
);

void main() {
  group('배포가 끝나면 지도 서버를 내린다', () {
    late String deploy;
    setUpAll(
      () =>
          deploy = File('../openrmf/scripts/deploy_map.sh').readAsStringSync(),
    );

    test('내리는 자리가 있다', () {
      expect(deploy, contains('stop_deploy_map_server()'));
    });

    test('성공이든 실패든 내린다', () {
      // 확인(6단계)에 실패해 빠져나갈 때도 남으면 안 된다. 그래서 trap 이다.
      final cleanup = deploy.indexOf('cleanup() {');
      expect(cleanup, greaterThanOrEqualTo(0));
      final body = deploy.substring(cleanup, deploy.indexOf('\n}', cleanup));
      expect(body, contains('stop_deploy_map_server'));
      expect(deploy, contains('trap cleanup EXIT'));
    });

    test('자식을 먼저 죽인다', () {
      // `ros2 run` 은 껍데기이고 실제 노드는 그 자식이다. 껍데기만 죽이면
      // 노드가 고아로 살아남는다 — 실측으로 확인했다(2026-08-17).
      final start = deploy.indexOf('stop_deploy_map_server() {');
      final body = deploy.substring(start, deploy.indexOf('\n}', start));
      final children = body.indexOf('pkill -P "\$pid"');
      final wrapper = body.indexOf('kill "\$pid"');
      expect(children, greaterThanOrEqualTo(0));
      expect(wrapper, greaterThan(children));
    });

    test('정말 내려갔는지 확인하고 안 되면 강제로 끊는다', () {
      final start = deploy.indexOf('stop_deploy_map_server() {');
      final body = deploy.substring(start, deploy.indexOf('\n}', start));
      expect(body, contains('kill -9 "\$pid"'));
      expect(body, contains('rm -f "\$pid_file"'));
    });

    test('이름으로 훑지 않는다 — 백엔드 것까지 죽는다', () {
      // 배포 중에 백엔드가 떠 있을 수 있다(6단계가 그 경우를 따로 알려 준다).
      // 이름으로 pkill 하면 그쪽 지도 서버까지 죽여 로봇이 길을 잃는다.
      final start = deploy.indexOf('stop_deploy_map_server() {');
      final body = deploy.substring(start, deploy.indexOf('\n}', start));
      expect(body, isNot(contains('pkill -f')));
      expect(body, isNot(contains('pkill -u')));
    });

    test('없어진 이유를 사람에게 밝힌다', () {
      // 배포 직후에 그 서버를 찾다가 "왜 없지" 하지 않도록.
      expect(deploy, contains('배포용 Building Map Server 를 내립니다'));
    });

    test('확인은 내리기 **전에** 한다', () {
      // 지도를 제대로 읽혔는지 보려면 서버가 떠 있어야 한다.
      final check = deploy.indexOf("grep -qx '/get_building_map'");
      final tell = deploy.indexOf('배포용 Building Map Server 를 내립니다');
      expect(check, greaterThanOrEqualTo(0));
      expect(tell, greaterThan(check));
    });
  });

  group('백엔드가 도는지 셀 때', () {
    late String source;
    setUpAll(
      () => source = File('lib/rmf_runtime_service_io.dart').readAsStringSync(),
    );

    test('배포가 남긴 지도 서버는 안 센다', () {
      final start = source.indexOf(
        'Future<List<String>> runningBackendProjects()',
      );
      expect(start, greaterThanOrEqualTo(0));
      final body = source.substring(start, source.indexOf('\n}\n', start));
      expect(body, contains("grep -cv 'building_map_server'"));
      // 중지 스크립트도 예전부터 빼 왔다. 둘 다 빠져야 한다.
      expect(body, contains("grep -v 'stop_'"));
    });

    test('왜 빼는지 실측을 남긴다', () {
      // 다음 사람이 "지도 서버도 백엔드 아닌가" 하고 되돌리지 않도록.
      expect(source, contains('grep -cv stop_'));
      expect(source, contains('지도 서버 하나는 백엔드가 아니다'));
    });

    test('빼도 진짜 백엔드는 놓치지 않는다', () {
      // 백엔드는 지도 서버 말고도 맵 디렉터리를 물고 있는 것이 여럿이다.
      // 실행 스크립트 자신, 로그 수집기, launch, Gazebo 월드 …
      final run = _run();
      expect(run, contains('run_project1-ver2.sh'));
      expect(run, contains('project1-ver2.world'));
      expect(run, contains('project1-ver2_bringup.launch.xml'));
    });
  });

  group('실행 스크립트', () {
    test('배포가 남긴 지도 서버를 먼저 내린다', () {
      // 안 내리면 launch 가 띄우는 것과 이름이 겹친다.
      final run = _run();
      expect(run, contains('openrmf/.runtime/building_map_server.pid'));
      expect(run, contains('배포가 띄워 둔 Building Map Server'));
    });

    test('pid 파일이 없어도 남은 것을 찾는다', () {
      // 앱이 아닌 곳에서 띄웠거나 파일을 지웠을 수 있다.
      final run = _run();
      expect(
        run,
        contains('/rmf_building_map_tools/building_map_server \$MAP_DIR/'),
      );
    });

    test('내리는 것이 launch 보다 먼저다', () {
      final run = _run();
      final kill = run.indexOf('배포가 띄워 둔 Building Map Server');
      final launch = run.indexOf('project1-ver2.launch.xml');
      expect(kill, greaterThanOrEqualTo(0));
      expect(launch, greaterThan(kill));
    });

    test('죽은 pid 파일에 걸려 넘어지지 않는다', () {
      // 배포한 서버가 이미 죽었으면 파일만 남는다. 그때도 그냥 지나가야 한다.
      final run = _run();
      expect(run, contains('kill -0 "\$stale" 2>/dev/null'));
      expect(run, contains('rm -f "\$DEPLOY_MAP_SERVER_PID"'));
    });
  });

  group('정지 스크립트', () {
    test('배포가 남긴 것도 함께 내린다', () {
      // 그것은 이 프로젝트의 프로세스 그룹 밖이라 그룹 끊기로는 안 죽는다.
      // 남으면 화면에서 백엔드가 영영 안 내려간 것처럼 보인다.
      final stop = _stop();
      expect(stop, contains('openrmf/.runtime/building_map_server.pid'));
      expect(
        stop,
        contains('/rmf_building_map_tools/building_map_server \$MAP_DIR/'),
      );
    });
  });

  group('만들어진 스크립트를 bash 가 읽는다', () {
    for (final entry in {'실행': _run, '정지': _stop}.entries) {
      test('${entry.key} 스크립트', () {
        final bash = Process.runSync('which', ['bash']);
        if (bash.exitCode != 0) {
          markTestSkipped('bash 가 없습니다');
          return;
        }
        final file = File(
          '${Directory.systemTemp.path}/robosapiens_${entry.key}_check.sh',
        )..writeAsStringSync(entry.value());
        addTearDown(() {
          if (file.existsSync()) file.deleteSync();
        });
        final result = Process.runSync('bash', ['-n', file.path]);
        expect(result.exitCode, 0, reason: '${result.stderr}');
      });
    }
  });
}
