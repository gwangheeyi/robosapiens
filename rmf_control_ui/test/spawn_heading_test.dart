/// 로봇을 세워 둘 방향.
///
/// 이 값이 Gazebo `create -Y` 와 AMCL 의 처음 자세로 그대로 들어간다. 나가는
/// 길과 어긋나면 Nav2 컨트롤러가 **출발 전에 제자리에서 그만큼 돌고 나서**
/// 간다(`use_rotate_to_heading: true`, `allow_reversing: false`).
///
/// 실측 — 충전2 에 0도(동쪽)로 세워 둔 핑키는 대기3(−179.5도) 으로 갈 때 거의
/// 180도를 제자리에서 돌았다. 그래서 등록할 때 방향을 넣을 수 있어야 한다.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rmf_control_ui/rmf_project_config.dart';

void main() {
  late String source;

  setUpAll(() => source = File('lib/main.dart').readAsStringSync());

  group('등록 창', () {
    test('세워 둘 방향을 넣는 칸이 있다', () {
      expect(source, contains("labelText: '세워 둘 방향 (도)'"));
      // 0도가 어느 쪽인지 밝힌다. 안 밝히면 화면의 위쪽으로 오해한다.
      expect(source, contains('0도가 오른쪽(+X)'));
    });

    test('넣은 값을 저장한다', () {
      final editor = source.indexOf('Future<RmfProjectRobot?> _editFleetRobot');
      final end = source.indexOf('Future<void> _registerFleetRobot', editor);
      final body = source.substring(editor, end);

      expect(body, contains('spawnHeading: headingRadians'));
      // 예전에는 기존 값을 그대로 넘기기만 해서 영영 0 이었다.
      expect(body, isNot(contains('spawnHeading: existing?.spawnHeading')));
    });

    test('숫자가 아니면 조용히 0 으로 바꾸지 않고 막는다', () {
      // 45 라고 치려다 어긋난 값이 0도로 저장되면, 로봇이 왜 엉뚱한 데를 보고
      // 서 있는지 알 수 없다.
      //
      // 줄바꿈과 들여쓰기까지 적어 두면 안 된다. 포매터가 그 줄을 다시 접는
      // 순간, 고칠 것이 없는데 시험만 깨진다. 그런 실패는 사람이 곧 무시하게
      // 되고 그러면 진짜 깨졌을 때도 안 본다. 붙는 값과 그 문구만 본다.
      expect(source, contains('headingError ='));
      expect(source, contains("'숫자로 적어 주세요"));
      // 못 읽은 값을 0 으로 눕히지 않는다.
      expect(source, isNot(contains('headingError = null;\n      heading = 0')));
    });

    test('나가는 길 방향을 눌러서 넣을 수 있다', () {
      expect(source, contains("'나가는 길 방향:'"));
      expect(source, contains('_stationExitHeadings('));
    });
  });

  group('한꺼번에 만들기', () {
    test('이동 로봇은 나가는 길을 보고 세운다', () {
      expect(source, contains('spawnHeading: heading,'));
      // 설치 로봇은 길을 안 따라가므로 방향을 맞출 이유가 없다.
      expect(
        source,
        contains(
          'kind == RmfRobotKind.mobile\n'
          '            ? _stationExitHeadings(',
        ),
      );
    });
  });

  group('저장되는 값', () {
    test('robot.yaml 에 라디안으로 들어간다', () {
      const robot = RmfProjectRobot(
        robotId: 'pinky_01',
        displayName: 'PK-01',
        model: 'PINKY-GZ',
        gzName: 'pinky_01',
        zones: ['ambient'],
        chargerWaypoint: '충전2',
        spawnX: 1.613,
        spawnY: -1.088,
        // −179.5도.
        spawnHeading: -3.132,
      );
      final yaml = buildRobotInfoYaml(robot);
      expect(yaml, contains('spawn_heading: -3.132'));
    });

    test('spawn.launch.xml 의 -Y 로 들어간다', () {
      const robot = RmfProjectRobot(
        robotId: 'pinky_01',
        displayName: 'PK-01',
        model: 'PINKY-GZ',
        gzName: 'pinky_01',
        zones: ['ambient'],
        chargerWaypoint: '충전2',
        spawnX: 1.613,
        spawnY: -1.088,
        spawnHeading: 1.571,
      );
      final launch = buildRobotSpawnLaunchXml(robot);
      expect(launch, contains('-Y 1.571'));
    });
  });
}
