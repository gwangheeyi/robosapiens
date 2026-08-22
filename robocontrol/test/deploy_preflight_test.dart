/// 배포는 화면 상태만 내보내면 안 된다.
///
/// 실제로 그래서 픽업 자리가 되돌아갔다 — Waypoint 를 팔에서 떼어 놓고 배포했는데
/// 앱을 다시 열자 저장된 옛 자리가 화면으로 돌아왔고, 다음 배포에서 그 옛 자리가
/// 다시 나가 팔과 또 겹쳤다. 원장은 MySQL 이므로 배포에 들어가는 그 내용이
/// 원장에도 들어가야 한다.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:robocontrol/deploy_preflight.dart';
import 'package:robocontrol/rmf_project_config.dart';
import 'package:robocontrol/robot_spawn_check.dart';

void main() {
  test('열린 프로젝트가 있으면 배포 전에 저장한다', () {
    expect(deployPreflightFor('warehouse'), DeployPreflight.save);
  });

  test('열린 프로젝트가 없으면 남길 곳이 없다고 알린다', () {
    expect(deployPreflightFor(null), DeployPreflight.warnNoProject);
    expect(deployPreflightFor(''), DeployPreflight.warnNoProject);
    expect(deployPreflightFor('   '), DeployPreflight.warnNoProject);
  });

  test('경고에 무엇이 사라지는지와 무엇을 하면 되는지 적는다', () {
    final message = deployNoProjectMessage('office');
    expect(message, contains('office'));
    // 무엇이 사라지는지 이름으로 밝힌다.
    expect(message, contains('Waypoint 자리'));
    expect(message, contains('적재 방향'));
    expect(message, contains('프로젝트 저장'));
  });

  test('저장 실패 경고는 왜 그냥 넘기면 안 되는지까지 적는다', () {
    final message = deploySaveFailedMessage(
      'warehouse',
      StateError('MySQL 연결 실패'),
    );
    expect(message, contains('warehouse'));
    expect(message, contains('MySQL 연결 실패'));
    // 되돌아간 것처럼 보이는 그 증상을 그대로 적어 둔다.
    expect(message, contains('되돌아간 것처럼'));
  });

  group('Waypoint 를 옮긴 뒤 등록이 안 따라온 설비', () {
    SpawnCheck spawn({
      required bool mobile,
      required ({double x, double y}) stored,
      required ({double x, double y}) fromMap,
    }) => SpawnCheck(
      robot: RmfProjectRobot(
        robotId: mobile ? 'PK_01' : 'OMX_01',
        displayName: mobile ? '핑키 1호' : '픽업 설비',
        model: mobile ? 'pinky' : 'open_manipulator_x',
        gzName: mobile ? 'pk_01' : 'omx_01',
        zones: const [],
        kind: mobile ? RmfRobotKind.mobile : RmfRobotKind.workcell,
        dataSource: RobotDataSource.gazebo,
        chargerWaypoint: mobile ? '홈1' : '설비2',
        spawnX: stored.x,
        spawnY: stored.y,
      ),
      issue: SpawnIssue.ok,
      stored: stored,
      fromMap: fromMap,
    );

    test('설비가 어긋나면 이름과 숫자를 밝힌다', () {
      final message = staleWorkcellSpawnMessage([
        spawn(
          mobile: false,
          stored: (x: 1.20, y: -.35),
          fromMap: (x: .95, y: -.35),
        ),
      ])!;
      expect(message, contains('OMX_01 · 픽업 설비'));
      expect(message, contains('설비2'));
      expect(message, contains('1.20, -0.35'));
      expect(message, contains('0.95, -0.35'));
      expect(message, contains('0.25m 차이'));
      // 왜 다시 겹치는지까지 적는다.
      expect(message, contains('옛 자리'));
    });

    test('이동 로봇은 시작 자리가 달라도 정상이라 탓하지 않는다', () {
      expect(
        staleWorkcellSpawnMessage([
          spawn(mobile: true, stored: (x: 3, y: 3), fromMap: (x: 0, y: 0)),
        ]),
        isNull,
      );
    });

    test('눈에 안 띄는 차이로는 사람을 세우지 않는다', () {
      expect(
        staleWorkcellSpawnMessage([
          spawn(
            mobile: false,
            stored: (x: 1.00, y: 0),
            fromMap: (x: 1.03, y: 0),
          ),
        ]),
        isNull,
      );
      expect(staleWorkcellSpawnMessage(const []), isNull);
    });
  });
}
