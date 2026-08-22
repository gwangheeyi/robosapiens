/// 로봇에 SSH 로 들어가 브링업을 띄우는 규칙.
///
/// 실물 로봇은 앱이 도는 PC 가 아니라 제 안에서 하드웨어를 연다. 그래서
/// 지금까지는 사람이 로봇에 들어가 손으로 launch 를 쳤고, 그 자리에서 자주
/// 어긋났다 — **어긋나도 오류가 안 난다.**
///
/// 실제로 겪은 일이다. 네임스페이스 없이 띄운 라이다가 루트 `/scan` 으로
/// 발행했는데 Nav2 는 `/pinky_03/scan` 을 구독했다. 라이다는 10Hz 로 멀쩡히
/// 돌고 있었지만 지도에는 아무것도 안 그려졌고, 원인을 라이다와 AMCL 에서
/// 찾느라 한참을 썼다.
///
/// 그 명령은 등록값으로 전부 만들어낼 수 있다. 사람이 칠 이유가 없다.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rmf_control_ui/rmf_project_config.dart';
import 'package:rmf_control_ui/robot_ssh.dart';

void main() {
  const target = RobotSshTarget(
    host: '192.168.0.31',
    user: 'pinky',
    workspace: '~/pinky_pro',
  );

  RmfProjectRobot robotWith({
    RobotDataSource dataSource = RobotDataSource.real,
    RmfRobotKind kind = RmfRobotKind.mobile,
    int? domain,
    Map<String, dynamic>? ssh,
  }) => RmfProjectRobot(
    robotId: 'pinky_03',
    displayName: 'PK-03',
    model: 'PINKY-GZ',
    gzName: 'pinky_03',
    zones: const ['ambient'],
    kind: kind,
    dataSource: dataSource,
    chargerWaypoint: '충전1',
    rosDomainId: domain,
    ssh: ssh,
  );

  group('들어가는 길', () {
    test('계정이 있으면 user@host 다', () {
      expect(target.authority, 'pinky@192.168.0.31');
    });

    test('계정을 비우면 주소만 쓴다', () {
      expect(
        const RobotSshTarget(host: '192.168.0.31').authority,
        '192.168.0.31',
      );
    });

    test('JSON 을 오가도 값이 남는다', () {
      final back = RobotSshTarget.fromJson(target.toJson())!;
      expect(back.host, target.host);
      expect(back.user, target.user);
      expect(back.workspace, target.workspace);
      expect(back.port, target.port);
    });

    /// 주소가 없으면 SSH 를 안 쓴다는 뜻이다. 빈 값을 살려 두면 화면에는 단추가
    /// 있는데 눌러도 아무 데도 못 붙는다.
    test('주소가 없으면 길이 없는 것이다', () {
      expect(RobotSshTarget.fromJson(null), isNull);
      expect(RobotSshTarget.fromJson({'host': '   '}), isNull);
    });
  });

  group('띄울 수 있는가', () {
    test('주소를 적은 실물 이동 로봇이면 띄운다', () {
      final readiness = checkRobotSshReadiness(
        robot: robotWith(ssh: target.toJson()),
        target: target,
      );
      expect(readiness, RobotSshReadiness.ready);
      expect(canBringUpOverSsh(readiness), isTrue);
      expect(robotSshBlockedReason(readiness), isNull);
    });

    test('주소를 안 적었으면 못 띄운다', () {
      final readiness = checkRobotSshReadiness(
        robot: robotWith(),
        target: null,
      );
      expect(readiness, RobotSshReadiness.noHost);
      expect(canBringUpOverSsh(readiness), isFalse);
    });

    /// 시뮬레이터가 이미 올린다. 여기서 또 띄울 로봇이 없다.
    test('Gazebo 로봇은 쓰지 않는다', () {
      expect(
        checkRobotSshReadiness(
          robot: robotWith(dataSource: RobotDataSource.gazebo),
          target: target,
        ),
        RobotSshReadiness.simulated,
      );
    });

    test('Mock 로봇은 들어갈 곳이 없다', () {
      expect(
        checkRobotSshReadiness(
          robot: robotWith(dataSource: RobotDataSource.mock),
          target: target,
        ),
        RobotSshReadiness.mockRobot,
      );
    });

    test('설치 로봇은 이 브링업을 안 쓴다', () {
      expect(
        checkRobotSshReadiness(
          robot: robotWith(kind: RmfRobotKind.workcell),
          target: target,
        ),
        RobotSshReadiness.notMobile,
      );
    });

    test('못 띄우는 까닭은 모두 사람이 읽을 말이 있다', () {
      for (final readiness in RobotSshReadiness.values) {
        if (readiness == RobotSshReadiness.ready) continue;
        expect(robotSshBlockedReason(readiness), isNotNull);
      }
    });
  });

  /// 손으로 칠 때 어긋나던 것이 바로 이 두 가지다.
  group('브링업 명령', () {
    test('등록 이름으로 namespaced bringup을 띄운다', () {
      final command = buildRobotBringupCommand(
        robot: robotWith(),
        target: target,
        projectDomainId: 12,
      );
      expect(command, contains('bringup_robot_namespaced.launch.xml'));
      expect(command, contains('namespace:=pinky_03'));
    });

    test('프로젝트 도메인을 넣는다', () {
      expect(
        buildRobotBringupCommand(
          robot: robotWith(),
          target: target,
          projectDomainId: 12,
        ),
        contains('export ROS_DOMAIN_ID=12'),
      );
    });

    test('로봇이 제 도메인을 가지면 그것이 이긴다', () {
      expect(
        buildRobotBringupCommand(
          robot: robotWith(domain: 22),
          target: target,
          projectDomainId: 12,
        ),
        contains('export ROS_DOMAIN_ID=22'),
      );
    });

    test('로봇 안의 워크스페이스를 읽는다', () {
      expect(
        buildRobotBringupCommand(
          robot: robotWith(),
          target: const RobotSshTarget(
            host: 'h',
            workspace: '~/other_ws',
          ),
          projectDomainId: 12,
        ),
        contains('~/other_ws/install/setup.bash'),
      );
    });

    /// 같은 시리얼 포트를 두 프로세스가 잡을 수 없다. 이미 떠 있는데 또 띄우면
    /// 나중 것이 조용히 실패하고 토픽만 남는다 — 그 상태가 가장 헷갈린다.
    test('이미 떠 있으면 먼저 내리고 시리얼이 풀리기를 기다린다', () {
      final command = buildRobotBringupCommand(
        robot: robotWith(),
        target: target,
        projectDomainId: 12,
      );
      final kill = command.indexOf('kill');
      final sleep = command.indexOf('sleep');
      final launch = command.indexOf('ros2 launch');
      expect(kill, greaterThanOrEqualTo(0));
      expect(sleep, greaterThan(kill));
      expect(launch, greaterThan(sleep));
    });

    /// 실제로 겪은 버그다. `ssh` 가 실행하는 셸의 명령줄에는 죽일 패턴
    /// 문자열이 그대로 들어 있어서, `pkill -f '...pinky_02'` 가 **자기 셸을
    /// 죽였다.** 뒤의 `echo STARTED` 에 닿기도 전에 죽어 ssh 가 255 로 끝나고,
    /// 브링업은 멀쩡히 떠 있는데 앱은 "접속하지 못했습니다" 라고 말했다.
    test('죽이는 명령이 자기 자신을 죽이지 않는다', () {
      for (final command in [
        buildRobotBringupCommand(
          robot: robotWith(),
          target: target,
          projectDomainId: 12,
        ),
        buildRobotBringupStopCommand(robotWith()),
      ]) {
        // 맨 패턴을 그대로 쓰면 제 명령줄이 걸린다. 쪼개 쓰거나 제 PID 를
        // 빼야 한다.
        expect(
          command.contains("pkill -f 'bringup_robot_namespaced"),
          isFalse,
          reason: '제 셸까지 죽이는 패턴이다: $command',
        );
        expect(command, contains('[b]ringup_robot_namespaced'));
      }
    });

    /// **launch 이름만으로는 자식을 못 잡는다.** `ros2 launch` 가 띄우는
    /// 노드들의 명령줄에는 launch 파일 이름이 안 들어 있고 `__ns:=/<로봇>` 만
    /// 있다. 부모만 죽이면 자식이 고아로 남아 시리얼 포트를 계속 잡고, 그 뒤에
    /// 다시 띄우면 새 브링업이 조용히 실패해 두 벌이 뜬 것처럼 보인다.
    test('직접 실행된 bringup 프로세스를 잡는다', () {
      for (final command in [
        buildRobotBringupCommand(
          robot: robotWith(),
          target: target,
          projectDomainId: 12,
        ),
        buildRobotBringupStopCommand(robotWith()),
        buildRobotBringupProbeCommand(robotWith()),
      ]) {
        expect(command, contains('[_]_ns:=/pinky_03'));
      }
    });

    /// 네임스페이스 뒤에는 `--params-file ...` 이 더 붙는다. 끝(`\$`) 으로
    /// 묶으면 열 개 중 여덟 개를 놓친다(실측).
    test('네임스페이스를 끝으로 묶지 않는다', () {
      expect(
        buildRobotBringupStopCommand(robotWith()),
        isNot(contains(r"_ns:=/pinky_03$'")),
      );
    });

    /// `joint_state_publisher` 는 TERM 을 안 받고 버틴다(실측). 남으면 시리얼과
    /// 토픽을 계속 잡아 다시 띄울 때 조용히 실패한다.
    test('TERM 뒤에 KILL 로 마무리한다', () {
      final stop = buildRobotBringupStopCommand(robotWith());
      final term = stop.indexOf('-TERM');
      final kill = stop.indexOf('-KILL');
      expect(term, greaterThanOrEqualTo(0));
      expect(kill, greaterThan(term));
      expect(stop.indexOf('sleep'), greaterThan(term));
    });

    /// 확인 명령이 제 명령줄을 세면 **언제나** RUNNING 이 나온다. 브링업이
    /// 없는데도 있다고 답하는 것이라 확인이 있으나 마나 해진다.
    test('확인 명령도 자기 자신을 안 센다', () {
      expect(
        buildRobotBringupProbeCommand(robotWith()),
        contains('[b]ringup_robot_namespaced'),
      );
    });

    /// 앱을 닫았다고 로봇이 멈추면 안 된다.
    test('SSH 가 끊겨도 브링업은 남는다', () {
      final command = buildRobotBringupCommand(
        robot: robotWith(),
        target: target,
        projectDomainId: 12,
      );
      expect(command, contains('setsid'));
      expect(command, contains('nohup'));
    });

    /// 시리얼을 못 잡으면 로그에 그대로 찍힌다. 앱에서 바로 볼 수 있어야
    /// 로봇에 다시 들어갈 일이 없다.
    test('로그를 파일로 남기고 그것을 읽을 수 있다', () {
      expect(
        buildRobotBringupCommand(
          robot: robotWith(),
          target: target,
          projectDomainId: 12,
        ),
        contains('/tmp/pinky_03_bringup.log'),
      );
      expect(
        buildRobotBringupLogCommand(robotWith()),
        contains('/tmp/pinky_03_bringup.log'),
      );
    });

    /// 실제로 겪은 버그다. 명령을 `; ` 로 이어 붙이면서 `&` 뒤에도 `;` 가
    /// 붙어 bash 가 통째로 거절했다:
    ///
    ///     bash: -c: line 1: syntax error near unexpected token `;'
    ///
    /// 문자열을 눈으로 봐서는 못 잡는다. bash 에게 직접 물어본다.
    test('bash 가 읽을 수 있는 명령이다', () {
      for (final command in [
        buildRobotBringupCommand(
          robot: robotWith(),
          target: target,
          projectDomainId: 12,
        ),
        buildRobotBringupStopCommand(robotWith()),
        buildRobotBringupProbeCommand(robotWith()),
        buildRobotBringupLogCommand(robotWith()),
        buildRobotServiceInstallCommand(robotWith()),
        buildRobotServiceRemoveCommand(robotWith()),
        buildRobotServiceStatusCommand(robotWith()),
      ]) {
        final result = Process.runSync('bash', ['-n', '-c', command]);
        expect(
          result.exitCode,
          0,
          reason: '문법 오류: ${result.stderr}\n명령: $command',
        );
      }
    });

    test('내리는 명령은 직접 실행된 bringup을 고른다', () {
      final stop = buildRobotBringupStopCommand(robotWith());
      expect(stop, contains('pinky_03'));
      expect(
        buildRobotBringupProbeCommand(robotWith()),
        contains('pinky_03'),
      );
    });
  });

  /// SSH 는 실패하는 길이 여럿이라, 무엇을 봐야 하는지 갈라 주지 않으면 사람이
  /// 어디부터 볼지 모른다.
  group('결과에 붙는 말', () {
    String messageFor(RobotSshOutcome outcome) => robotSshOutcomeMessage(
      outcome: outcome,
      robotLabel: 'PK-03',
      authority: 'pinky@192.168.0.31',
      detail: '자세한 내용',
    );

    test('못 붙으면 키 등록을 알려 준다', () {
      final message = messageFor(RobotSshOutcome.unreachable);
      expect(message, contains('ssh-copy-id pinky@192.168.0.31'));
      expect(message, contains('비밀번호'));
    });

    test('붙었는데 실패하면 워크스페이스를 보라고 한다', () {
      expect(
        messageFor(RobotSshOutcome.commandFailed),
        contains('워크스페이스'),
      );
    });

    test('띄웠으면 값이 오기까지 기다리라고 한다', () {
      expect(messageFor(RobotSshOutcome.ok), contains('몇 초'));
    });
  });

  /// 로봇을 켤 때마다 브링업이 뜨게 해 두면, 사람이 단추 누르는 것을 잊어도
  /// 브링업이 먼저 서 있다. PC 의 Nav2 가 로봇보다 먼저 뜨면 costmap 이
  /// 기다리던 TF 가 없어 lifecycle 이 통째로 멈추는데, 그 순서가 뒤집힌다.
  group('켤 때 자동 실행', () {
    String unitFor({int? domain}) => buildRobotBringupService(
      robot: robotWith(domain: domain),
      target: target,
      projectDomainId: 12,
    );

    /// 사람이 로봇 안에서 손으로 쓰면 이 두 값을 거기에 또 적게 되고, 앱에서
    /// 바꿔도 그 파일은 그대로 남아 조용히 어긋난다.
    test('네임스페이스 없이 직접 실행하고 도메인을 등록값으로 박는다', () {
      final unit = unitFor();
      expect(unit, contains('bringup_robot_namespaced.launch.xml'));
      expect(unit, contains('namespace:=pinky_03'));
      expect(unit, contains('Environment=ROS_DOMAIN_ID=12'));
      expect(
        unit,
        contains('Environment=FASTDDS_BUILTIN_TRANSPORTS=UDPv4'),
      );
      expect(
        unit,
        contains('Environment=ROS_AUTOMATIC_DISCOVERY_RANGE=SUBNET'),
      );
    });

    test('로봇이 제 도메인을 가지면 그것이 이긴다', () {
      expect(unitFor(domain: 22), contains('Environment=ROS_DOMAIN_ID=22'));
    });

    /// 부팅 직후에는 시리얼 장치가 아직 안 올라와 있을 수 있다. 한 번 죽고
    /// 끝나면 로봇은 켜졌는데 토픽은 안 오는 상태로 남는다.
    test('실패하면 다시 띄운다', () {
      expect(unitFor(), contains('Restart=on-failure'));
    });

    /// 망 없이 뜨면 같은 도메인의 다른 노드를 못 보고, 나중에 망이 붙어도 그
    /// 상태가 그대로 간다.
    test('망이 올라온 뒤에 뜬다', () {
      expect(unitFor(), contains('After=network-online.target'));
    });

    test('부팅 때 뜨도록 걸린다', () {
      expect(unitFor(), contains('WantedBy=multi-user.target'));
      expect(
        buildRobotServiceInstallCommand(robotWith()),
        contains('systemctl enable'),
      );
    });

    test('서비스 이름이 로봇마다 갈린다', () {
      expect(robotBringupServiceName(robotWith()), contains('pinky_03'));
    });

    test('끄면 파일까지 지운다', () {
      final remove = buildRobotServiceRemoveCommand(robotWith());
      expect(remove, contains('disable --now'));
      expect(remove, contains('rm -f'));
    });

    group('상태를 읽는다', () {
      test('걸려 있고 도는 중', () {
        final status = parseRobotServiceStatus('enabled\nactive');
        expect(status.enabled, isTrue);
        expect(status.active, isTrue);
        expect(status.installed, isTrue);
      });

      /// `inactive` 안에 `active` 가 들어 있다. 낱말 경계로 안 가르면 안 도는
      /// 서비스를 돈다고 읽는다.
      test('inactive 를 active 로 잘못 읽지 않는다', () {
        final status = parseRobotServiceStatus('enabled\ninactive');
        expect(status.enabled, isTrue);
        expect(status.active, isFalse);
      });

      test('disabled 를 enabled 로 잘못 읽지 않는다', () {
        final status = parseRobotServiceStatus('disabled\ninactive');
        expect(status.enabled, isFalse);
        expect(status.installed, isFalse);
      });

      test('사람이 읽을 말이 붙는다', () {
        expect(
          robotServiceStatusLabel(
            parseRobotServiceStatus('enabled\nactive'),
          ),
          contains('자동 실행'),
        );
        expect(
          robotServiceStatusLabel(
            parseRobotServiceStatus('disabled\ninactive'),
          ),
          '자동 실행 안 함',
        );
      });
    });
  });

  group('등록에 함께 저장된다', () {
    test('JSON 을 오가도 남는다', () {
      final robot = robotWith(ssh: target.toJson());
      final back = RmfProjectRobot.fromJson(robot.toJson());
      expect(RobotSshTarget.fromJson(back.ssh)?.host, '192.168.0.31');
    });

    /// 자리나 좌표를 고칠 때 조용히 사라지면, 다음에 브링업을 띄우려 할 때
    /// 주소가 없다고 나온다.
    test('좌표를 다시 넣어도 남는다', () {
      final robot = robotWith(ssh: target.toJson());
      final moved = robot.withSpawn(spawnX: 1, spawnY: -1);
      expect(RobotSshTarget.fromJson(moved.ssh)?.host, '192.168.0.31');
    });

    test('자리를 바꿔도 남는다', () {
      final robot = robotWith(ssh: target.toJson());
      expect(
        RobotSshTarget.fromJson(robot.withStation('충전2').ssh)?.host,
        '192.168.0.31',
      );
    });
  });
}
