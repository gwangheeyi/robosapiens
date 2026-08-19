/// 백엔드를 띄우기 전에 로봇 브링업이 먼저 서 있는지 보는 규칙.
///
/// 실제로 겪은 일이다. PC 의 Nav2 가 로봇보다 먼저 떠서 costmap 이 TF 를 못
/// 찾았고, `lifecycle_manager` 는 `controller_server` 에서 멈춰 뒤의 노드를
/// 시도조차 하지 않았다. `amcl` 만 active 로 남은 채 작업을 넣으니 어댑터가
/// `Nav2 가 거절했습니다` 만 11번 남겼는데, **화면에는 진행 중으로 보였다.**
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rmf_control_ui/bringup_precheck.dart';
import 'package:rmf_control_ui/rmf_project_config.dart';

void main() {
  RobotBringupState state(
    String id, {
    bool odom = true,
    bool scan = true,
  }) => RobotBringupState(
    robotId: id,
    displayName: id.toUpperCase(),
    hasOdom: odom,
    hasScan: scan,
  );

  RmfProjectRobot robot(
    String id, {
    RobotDataSource dataSource = RobotDataSource.real,
    RmfRobotKind kind = RmfRobotKind.mobile,
  }) => RmfProjectRobot(
    robotId: id,
    displayName: id.toUpperCase(),
    model: 'PINKY-GZ',
    gzName: id,
    zones: const ['ambient'],
    kind: kind,
    dataSource: dataSource,
    chargerWaypoint: '충전1',
  );

  group('누구를 보는가', () {
    /// Gazebo 로봇은 시뮬레이터가 띄우므로 백엔드보다 먼저 설 수가 없다.
    /// 그것까지 막으면 시뮬레이션 프로젝트를 아예 못 띄운다.
    test('실물 이동 로봇만 본다', () {
      final robots = [
        robot('pinky_01'),
        robot('gz_01', dataSource: RobotDataSource.gazebo),
        robot('mock_01', dataSource: RobotDataSource.mock),
        robot('omx_01', kind: RmfRobotKind.workcell),
      ];
      expect(
        robotsNeedingBringup(robots).map((r) => r.robotId),
        ['pinky_01'],
      );
    });

    test('실물이 없으면 볼 것이 없다', () {
      expect(
        checkBringupBeforeBackend(const []),
        BringupPrecheckResult.nothingToCheck,
      );
    });
  });

  group('띄워도 되는가', () {
    test('둘 다 오면 띄운다', () {
      expect(
        checkBringupBeforeBackend([state('pinky_02')]),
        BringupPrecheckResult.ready,
      );
      expect(bringupPrecheckMessage([state('pinky_02')]), isNull);
    });

    /// `odom` 이 없으면 costmap 이 기다리는 TF 가 없다 — 바로 그 실패다.
    test('odom 이 없으면 막는다', () {
      expect(
        checkBringupBeforeBackend([state('pinky_02', odom: false)]),
        BringupPrecheckResult.missingBringup,
      );
    });

    /// `scan` 이 없으면 AMCL 이 자리를 못 잡는다. 반쪽이라 결국 같은 곳에서
    /// 막힌다.
    test('scan 이 없어도 막는다', () {
      expect(
        checkBringupBeforeBackend([state('pinky_02', scan: false)]),
        BringupPrecheckResult.missingBringup,
      );
    });

    test('한 대만 빠져도 막는다', () {
      expect(
        checkBringupBeforeBackend([
          state('pinky_01'),
          state('pinky_02', odom: false),
        ]),
        BringupPrecheckResult.missingBringup,
      );
    });
  });

  /// 확인이 **띄우기보다 먼저**여야 한다. 뒤에 두면 이미 뜬 뒤라 아무 소용이
  /// 없고, 그때는 손으로 RESET·STARTUP 을 쳐서 되살려야 한다.
  group('띄우기 전에 본다', () {
    test('실행 스크립트보다 먼저 확인한다', () {
      final source = File('lib/main.dart').readAsStringSync();
      final start = source.indexOf(
        'Future<void> _startBackendForOpenProject()',
      );
      final body = source.substring(start, start + 1200);
      final check = body.indexOf('_bringupReadyForBackend()');
      final run = body.indexOf('_runProjectScript(');
      expect(check, greaterThanOrEqualTo(0), reason: '확인을 안 부른다');
      expect(run, greaterThan(check), reason: '확인이 실행보다 뒤에 있다');
    });

    /// 막았으면 정말 안 띄워야 한다. 알리기만 하고 그대로 진행하면 팝업이
    /// 잔소리가 된다.
    test('막으면 그 자리에서 멈춘다', () {
      final source = File('lib/main.dart').readAsStringSync();
      final start = source.indexOf(
        'Future<void> _startBackendForOpenProject()',
      );
      final body = source.substring(start, start + 1200);
      expect(body, contains('if (!await _bringupReadyForBackend()) return;'));
    });
  });

  group('막을 때 하는 말', () {
    final message = bringupPrecheckMessage([
      state('pinky_01'),
      state('pinky_02', odom: false, scan: false),
    ])!;

    test('빠진 로봇과 빠진 토픽을 짚는다', () {
      expect(message, contains('pinky_02'));
      expect(message, contains('odom'));
      expect(message, contains('scan'));
    });

    test('멀쩡한 로봇은 안 적는다', () {
      expect(message, isNot(contains('pinky_01')));
    });

    /// 이유만 적으면 화면을 보고도 다음 손이 안 나간다.
    test('무엇을 하라고까지 적는다', () {
      expect(message, contains('브링업 띄우기'));
      expect(message, contains('켤 때 자동 실행'));
    });

    /// 겉으로 정상처럼 보이는 것이 이 문제의 핵심이다.
    test('왜 그냥 띄우면 안 되는지 밝힌다', () {
      expect(message, contains('controller_server'));
      expect(message, contains('진행 중'));
    });
  });
}
