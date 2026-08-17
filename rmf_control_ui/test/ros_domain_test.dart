/// ROS 도메인을 맵이 정하고, 로봇이 그것을 가져가되 고칠 수 있는지 지킨다.
///
/// 도메인이 어긋나면 **아무 오류도 안 나면서** 아무것도 안 통한다. 실제로 앱은
/// 비대화형 셸로 배포 스크립트를 돌려 `~/.bashrc` 의 `export ROS_DOMAIN_ID=22`
/// 를 못 읽었고, 터미널의 시뮬레이터가 22번에 있는 동안 배포만 0번에서 혼자
/// 돌았다. 지도를 배포해도 시뮬레이터가 못 받았고, 화면에는 "배포가 오래
/// 걸린다" 로만 보였다.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rmf_control_ui/main.dart';
import 'package:rmf_control_ui/rmf_project_config.dart';

void main() {
  group('쓸 수 있는 도메인', () {
    test('0 부터 232 까지 받는다', () {
      expect(rosDomainIdError(0), isNull);
      expect(rosDomainIdError(22), isNull);
      expect(rosDomainIdError(maxRosDomainId), isNull);
      expect(rosDomainIdError(-1), isNotNull);
      expect(rosDomainIdError(maxRosDomainId + 1), isNotNull);
      expect(rosDomainIdError(null), isNotNull);
    });

    test('임시 포트와 겹칠 수 있는 번호는 알린다', () {
      expect(rosDomainIdWarning(22), isNull);
      expect(rosDomainIdWarning(safeMaxRosDomainId), isNull);
      expect(rosDomainIdWarning(safeMaxRosDomainId + 1), isNotNull);
    });
  });

  group('실행 스크립트', () {
    test('맵이 정한 도메인을 내보낸다', () {
      final script = buildProjectRunScript(
        mapName: 'gwanghee',
        mapDirectory: '/maps/gwanghee',
        rosDomainId: 22,
      );
      // 앱에서 띄우든 터미널에서 띄우든 같은 망을 써야 한다.
      expect(script, contains('export ROS_DOMAIN_ID="\${ROS_DOMAIN_ID:-22}"'));
      // 무엇으로 떴는지 로그만 봐도 알아야 한다.
      expect(script, contains(r'ROS_DOMAIN_ID: $ROS_DOMAIN_ID'));
    });

    test('환경 변수로 준 값이 이긴다', () {
      // 한 번만 다른 망에서 시험해 보는 길을 막지 않는다.
      final script = buildProjectRunScript(
        mapName: 'gwanghee',
        mapDirectory: '/maps/gwanghee',
      );
      expect(script, contains(r'${ROS_DOMAIN_ID:-0}'));
    });
  });

  group('로봇마다 따로', () {
    const base = RmfProjectRobot(
      robotId: 'PK-01',
      displayName: '핑키 1호',
      model: 'PINKY-GZ',
      gzName: 'pinky_01',
      zones: ['ambient'],
      dataSource: RobotDataSource.gazebo,
    );

    test('안 정한 로봇은 launch 를 건드리지 않는다', () {
      // 빈 값을 넣으면 스크립트가 내보낸 값을 덮어써서, 맵 기본값을 고쳐도
      // 이 로봇만 안 따라온다.
      expect(buildRobotSpawnLaunchXml(base), isNot(contains('ROS_DOMAIN_ID')));
      expect(
        buildRobotNav2LaunchXml(base, 'gwanghee'),
        isNot(contains('ROS_DOMAIN_ID')),
      );
    });

    test('정한 로봇은 제 도메인으로 뜬다', () {
      final robot = RmfProjectRobot(
        robotId: base.robotId,
        displayName: base.displayName,
        model: base.model,
        gzName: base.gzName,
        zones: base.zones,
        dataSource: base.dataSource,
        rosDomainId: 40,
      );
      // 노드가 도메인을 정하는 것은 환경 변수뿐이라 set_env 말고는 길이 없다.
      const expected = '<set_env name="ROS_DOMAIN_ID" value="40"/>';
      expect(buildRobotSpawnLaunchXml(robot), contains(expected));
      expect(buildRobotNav2LaunchXml(robot, 'gwanghee'), contains(expected));
      expect(buildRobotInfoYaml(robot), contains('ros_domain_id: 40'));
    });

    test('프로젝트에 남고 다시 읽힌다', () {
      final robot = RmfProjectRobot(
        robotId: base.robotId,
        displayName: base.displayName,
        model: base.model,
        gzName: base.gzName,
        zones: base.zones,
        rosDomainId: 40,
      );
      expect(RmfProjectRobot.fromJson(robot.toJson()).rosDomainId, 40);
      expect(RmfProjectRobot.fromJson(base.toJson()).rosDomainId, isNull);
      // 자리를 다시 계산해도 도메인은 그대로다.
      expect(robot.withSpawn(spawnX: 1, spawnY: 2).rosDomainId, 40);
    });
  });

  group('배포 스크립트', () {
    late final String script = File(
      '../openrmf/scripts/deploy_map.sh',
    ).readAsStringSync();

    test('어느 도메인에 띄웠는지 로그에 남긴다', () {
      expect(script, contains(r'echo "ROS_DOMAIN_ID: ${ROS_DOMAIN_ID:-0}"'));
    });

    test('기다림을 시계로 자른다', () {
      // `30번 × sleep 0.5` 는 15초로 보이지만, 노드가 수백 개면
      // `ros2 service list` 한 번이 3~5초라 실제로는 100초가 넘었다.
      expect(script, contains('MAP_READY_WAIT'));
      expect(script, contains('DEADLINE=\$((SECONDS + WAIT_SECS))'));
      // 확인 자체가 그 시계 안에서 돌아야 한다. (프로세스가 죽기를 기다리는
      // 다른 반복문은 그대로 둔다 — 그쪽은 횟수로 세는 것이 맞다.)
      // 단계 번호가 아니라 이름으로 찾는다. 번호는 단계가 늘거나 줄면 바뀐다.
      final ready = script.substring(script.indexOf('"새 지도 수신 확인"'));
      expect(ready, contains('while ((SECONDS < DEADLINE)); do'));
      expect(ready, isNot(contains('for _ in {1..30}; do')));
    });

    test('도메인이 비었으면 그것부터 짚는다', () {
      expect(script, contains('노드가 하나도 없습니다'));
      expect(script, contains('맵 관리 · [ROS 도메인] 단추'));
    });

    test('도메인을 바꾼 뒤 이전 ros2 daemon 캐시를 쓰지 않는다', () {
      expect(script, contains('ros2 service list --no-daemon'));
      expect(script, contains('ros2 node list --no-daemon'));
    });

    test('탐색에 1초만 주지 않는다', () {
      // `--no-daemon` 은 캐시가 없어 그때그때 DDS 를 훑는다. 1초로는 멀쩡히
      // 떠 있는 서버를 절반쯤 놓쳐서(실측 5번 중 2번), 지도는 다 올라갔는데
      // 배포만 실패로 끝난다.
      expect(script, isNot(contains('--no-daemon --spin-time 1')));
      expect(script, contains('ros2 service list --no-daemon --spin-time 3'));
      expect(script, contains('ros2 node list --no-daemon --spin-time 3'));
    });

    test('맵을 다시 배포해도 등록한 WorkCell policy를 보존한다', () {
      expect(script, contains(r'cp -a "$BACKUP_PATH/policies"'));
      expect(script, contains('WorkCell policy 보존'));
      expect(script, contains(r'cp -a "$BACKUP_PATH/policy_bindings.json"'));
      expect(script, contains('WorkCell policy 연결 보존'));
    });
  });

  group('죽은 노드를 살아 있다고 읽지 않는다', () {
    // ros2 데몬은 CLI 가 빠르라고 두는 캐시라 죽은 노드를 한참 들고 있다.
    // 실측 — 백엔드를 전부 내려 프로세스가 하나도 없는데 데몬은 12개가 넘게
    // 살아 있다고 했고, 같은 순간 `--no-daemon` 은 하나도 없다고 답했다.
    test('노드 목록을 데몬 캐시로 읽지 않는다', () {
      final source = File('lib/rmf_runtime_service_io.dart').readAsStringSync();
      expect(source, contains('ros2 node list --no-daemon --spin-time 3'));
      expect(source, isNot(contains("'ros2 node list'")));
    });

    test('떠 있는지는 프로세스로 판정한다', () {
      // 노드 목록은 아무리 정확히 읽어도 실제보다 늦다. 강제 종료된 노드는
      // DDS 에 떠난다고 알리지 못해 십수 초 더 남는다. 그래서 목록만 보고
      // 판정하면 멀쩡히 내려간 백엔드가 떠 있다고 읽힌다.
      final source = File('lib/main.dart').readAsStringSync();
      final refresh = source.indexOf('Future<void> _refreshRmfStatus(');
      final probe = source.indexOf('probeRmfRuntime(', refresh);
      final processes = source.indexOf('runningBackendProjects()', refresh);
      final ghost = source.indexOf('_ghostNodes = processesGone', refresh);

      expect(refresh, greaterThanOrEqualTo(0));
      // 프로세스를 **먼저** 본다. 노드부터 읽고 나중에 맞추면 그 사이에 화면이
      // 한 번 잘못된 상태로 그려진다.
      expect(processes, greaterThan(refresh));
      expect(processes, lessThan(probe));
      expect(ghost, greaterThan(processes));
    });
  });

  group('앱이 셸로 부르는 ros2', () {
    // 도메인을 안 넘기면 0번에서 돌고, 22번의 백엔드와 **아무 오류 없이**
    // 서로를 못 본다. 이 실수가 세 번 났다 —
    //
    //   텔레메트리 브리지  → 로봇 위치가 안 와서 `어댑터가 죽었습니다`
    //   probeRmfRuntime    → `떠 있는 백엔드가 없습니다`
    //   작업 다리          → 작업을 넣어도 로봇이 안 움직임
    //
    // 셋 다 증상이 원인에서 멀어서 엉뚱한 곳을 뒤지게 했다. 새로 넣는 곳도
    // 빠뜨리지 않도록 파일에서 직접 센다.
    final launchers = {
      'lib/rmf_runtime_service_io.dart',
      'lib/robot_telemetry_bridge_io.dart',
      'lib/rmf_task_bridge_io.dart',
    };

    for (final path in launchers) {
      test('$path 는 ros2 를 부르기 전에 도메인을 내보낸다', () {
        final source = File(path).readAsStringSync();
        // 앱이 셸로 내보내는 것은 전부 `_withRosEnvironment(...)` 를 지난다.
        // 그 괄호 안을 통째로 본다 — Dart 는 붙여 쓴 문자열을 이어 붙이므로
        // 한 줄씩 보면 `export` 와 `ros2` 가 따로 잡힌다.
        final calls = <String>[];
        for (final match in RegExp(
          r'_withRosEnvironment\(',
        ).allMatches(source)) {
          // 정의(`String _withRosEnvironment(String command)`)는 부르는 곳이
          // 아니다.
          if (source.substring(0, match.start).endsWith('String ')) continue;
          var depth = 1;
          var i = match.end;
          while (i < source.length && depth > 0) {
            if (source[i] == '(') depth++;
            if (source[i] == ')') depth--;
            i++;
          }
          calls.add(source.substring(match.end, i - 1));
        }

        expect(calls, isNotEmpty, reason: '$path 에서 부르는 자리를 못 찾았다');
        for (final call in calls) {
          expect(
            call,
            contains('ROS_DOMAIN_ID'),
            reason: '$path 의 다음 호출이 도메인을 안 넘긴다:\n$call',
          );
        }
      });
    }
  });

  group('맵 관리 화면', () {
    testWidgets('단추에 지금 도메인이 적혀 있다', (tester) async {
      // 어긋나면 오류 없이 아무것도 안 통하므로 늘 보여야 한다.
      tester.view.physicalSize = const Size(1600, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(const RmfControlApp());
      await tester.tap(find.text('맵 관리').first);
      await tester.pumpAndSettle();
      expect(find.text('ROS 도메인 0'), findsOneWidget);
    });

    testWidgets('넣은 도메인이 단추에 남는다', (tester) async {
      tester.view.physicalSize = const Size(1600, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(const RmfControlApp());
      await tester.tap(find.text('맵 관리').first);
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('ROS 도메인 '));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.ancestor(
          of: find.text('ROS_DOMAIN_ID'),
          matching: find.byType(TextField),
        ),
        '22',
      );
      await tester.tap(find.text('도메인 저장'));
      await tester.pumpAndSettle();

      expect(find.text('ROS 도메인 22'), findsOneWidget);
    });

    testWidgets('쓸 수 없는 번호는 막는다', (tester) async {
      tester.view.physicalSize = const Size(1600, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(const RmfControlApp());
      await tester.tap(find.text('맵 관리').first);
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('ROS 도메인 '));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.ancestor(
          of: find.text('ROS_DOMAIN_ID'),
          matching: find.byType(TextField),
        ),
        '999',
      );
      await tester.tap(find.text('도메인 저장'));
      await tester.pumpAndSettle();

      expect(find.textContaining('사이여야 합니다'), findsOneWidget);
    });
  });
}
