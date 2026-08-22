/// 로봇이 마지막으로 간 자리를 찾는 규칙.
///
/// 앱을 다시 켜면 지도에 로봇이 없다. 그때 등록의 충전 자리에 놓으면 실제와
/// 어긋난다 — 로봇은 대기1 에 서 있는데 지도에는 충전1 에 그려지고, 그 상태에서
/// 다른 자리로 보내면 화면과 실제가 벌어진 채로 움직인다.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:robocontrol/robot_last_place.dart';

void main() {
  RobotTaskTrace trace(
    String robotId,
    List<String> places, {
    DateTime? at,
    bool completed = true,
  }) => RobotTaskTrace(
    robotId: robotId,
    finishedAt: at,
    destinations: places,
    completed: completed,
  );

  final t1 = DateTime(2026, 8, 19, 10);
  final t2 = DateTime(2026, 8, 19, 11);

  group('마지막으로 간 자리', () {
    test('끝난 작업의 마지막 목적지다', () {
      expect(
        lastVisitedPlace(
          robotId: 'pinky_02',
          tasks: [trace('pinky_02', ['충전1', '대기1'], at: t1)],
        ),
        '대기1',
      );
    });

    test('가장 나중에 끝난 작업을 본다', () {
      expect(
        lastVisitedPlace(
          robotId: 'pinky_02',
          tasks: [
            trace('pinky_02', ['대기1'], at: t1),
            trace('pinky_02', ['대기2'], at: t2),
          ],
        ),
        '대기2',
      );
    });

    test('다른 로봇의 작업은 안 본다', () {
      expect(
        lastVisitedPlace(
          robotId: 'pinky_02',
          tasks: [trace('pinky_01', ['대기1'], at: t1)],
        ),
        isNull,
      );
    });

    /// 중간에 멈춘 작업의 마지막 목적지는 **가지 않은 자리**다. 그것을 지금
    /// 자리로 보면 로봇이 실제로 있는 곳보다 앞서 그려진다.
    test('안 끝난 작업은 안 본다', () {
      expect(
        lastVisitedPlace(
          robotId: 'pinky_02',
          tasks: [trace('pinky_02', ['대기1'], at: t1, completed: false)],
        ),
        isNull,
      );
    });

    test('끝난 시각이 없으면 안 본다', () {
      expect(
        lastVisitedPlace(
          robotId: 'pinky_02',
          tasks: [trace('pinky_02', ['대기1'])],
        ),
        isNull,
      );
    });

    /// 이름 없는 단계(대기 등)가 뒤에 붙어도 실제로 간 자리를 찾아야 한다.
    test('빈 이름은 건너뛰고 뒤에서부터 찾는다', () {
      expect(
        lastVisitedPlace(
          robotId: 'pinky_02',
          tasks: [trace('pinky_02', ['충전1', '대기1', '', ''], at: t1)],
        ),
        '대기1',
      );
    });

    test('갈 자리가 하나도 없으면 모른다', () {
      expect(
        lastVisitedPlace(
          robotId: 'pinky_02',
          tasks: [trace('pinky_02', ['', ''], at: t1)],
        ),
        isNull,
      );
    });

    test('작업이 없으면 모른다', () {
      expect(
        lastVisitedPlace(robotId: 'pinky_02', tasks: const []),
        isNull,
      );
    });
  });

  group('어느 것을 믿는가', () {
    /// 짐작보다 실측이 낫다. 사람이 로봇을 옮겼어도 토픽은 그것을 안다.
    test('토픽이 오면 언제나 그것이 이긴다', () {
      final resolved = resolveRobotPlace(
        telemetryPlace: '대기2',
        lastPlace: '대기1',
        registeredPlace: '충전1',
      );
      expect(resolved.place, '대기2');
      expect(resolved.source, RobotPlaceSource.telemetry);
    });

    test('토픽이 없으면 마지막 작업 자리를 쓴다', () {
      final resolved = resolveRobotPlace(
        lastPlace: '대기1',
        registeredPlace: '충전1',
      );
      expect(resolved.place, '대기1');
      expect(resolved.source, RobotPlaceSource.lastTask);
    });

    test('그것도 없으면 등록된 자리로 떨어진다', () {
      final resolved = resolveRobotPlace(registeredPlace: '충전1');
      expect(resolved.place, '충전1');
      expect(resolved.source, RobotPlaceSource.registration);
    });

    test('아무것도 없으면 모른다', () {
      expect(resolveRobotPlace().place, isNull);
    });

    test('빈 문자열은 없는 것으로 다룬다', () {
      final resolved = resolveRobotPlace(
        telemetryPlace: '   ',
        lastPlace: '대기1',
      );
      expect(resolved.source, RobotPlaceSource.lastTask);
    });
  });

  /// **조용히 넘기면 안 된다.** 예전에는 자리를 못 찾으면 그냥 안 그렸다.
  /// 그래서 지도에 로봇이 없는 것이 "아직 안 왔다" 인지 "어디 있는지 모른다"
  /// 인지 구별되지 않았고, 사람은 기다리기만 했다.
  group('자리를 모르면 알린다', () {
    test('어느 로봇인지 짚는다', () {
      final message = unknownPlaceMessage([
        'pinky_01 · PK-01',
        'pinky_02 · PK-02',
      ])!;
      expect(message, contains('pinky_01'));
      expect(message, contains('pinky_02'));
    });

    /// 알리기만 하고 무엇을 하라는 말이 없으면 화면을 보고도 손이 안 나간다.
    test('어디서 고치는지 알려 준다', () {
      final message = unknownPlaceMessage(['pinky_02 · PK-02'])!;
      expect(message, contains('로봇 등록'));
      expect(message, contains('자리 Waypoint'));
    });

    test('알릴 것이 없으면 아무 말도 안 한다', () {
      expect(unknownPlaceMessage(const []), isNull);
    });

    /// 자리를 채우는 함수는 **토픽이 올 때마다** 돈다. 그때마다 창을 띄우면
    /// 화면을 덮어 아무 일도 못 하게 된다. 한 번만 알리고, 자리를 찾으면
    /// 잊는다 — 다시 잃으면 다시 알려야 한다.
    test('같은 로봇을 되풀이해 알리지 않는다', () {
      final source = File('lib/main.dart').readAsStringSync();
      final start = source.indexOf('void _placeLiveRobotsOnMap()');
      final body = source.substring(start, start + 3000);
      expect(body, contains('_warnedUnknownPlace'));
      // 이미 알린 것은 빼고, 새로 생긴 것만 알린다.
      expect(body, contains('_warnedUnknownPlace.add(label)'));
      // 자리를 찾은 로봇은 기억에서 지운다.
      expect(body, contains('_warnedUnknownPlace.removeWhere'));
    });
  });

  /// 짐작을 실측처럼 보여 주면 사람이 그것을 믿고 작업을 낸다.
  group('어디서 알았는지 밝힌다', () {
    test('모든 출처에 사람이 읽을 말이 있다', () {
      for (final source in RobotPlaceSource.values) {
        expect(robotPlaceSourceLabel(source), isNotEmpty);
      }
    });

    test('짐작은 짐작이라고 적는다', () {
      expect(
        robotPlaceSourceLabel(RobotPlaceSource.lastTask),
        contains('짐작'),
      );
    });
  });
}
