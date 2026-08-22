/// 로봇이 지금 서 있는 자리를 Waypoint 로 만드는 규칙.
///
/// 도면 위에서 눈으로 찍는 것은 1픽셀 아래로 못 내려가고, 그 1픽셀이 실제로는
/// 몇 밀리미터인지 화면만 봐서는 모른다. 팔과 핑키가 부딪힌 자리도 도면에서는
/// 떨어져 보였는데 미터로 재면 0.34m 였다.
///
/// 로봇을 실제로 밀어 넣어 보고 그 자리를 그대로 찍으면 그런 일이 없다.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:robocontrol/waypoint_capture.dart';

void main() {
  group('찍을 수 있는가', () {
    test('자리를 알고 축척을 재었으면 찍는다', () {
      final readiness = checkWaypointCapture(
        poseKnown: true,
        scaleKnown: true,
      );
      expect(readiness, WaypointCaptureReadiness.ready);
      expect(canCaptureWaypoint(readiness), isTrue);
      expect(waypointCaptureBlockedReason(readiness), isNull);
    });

    /// 모르는 채로 찍으면 **엉뚱한 자리**가 지도에 박힌다. 나중에 그 자리로
    /// 로봇을 보내면 어디로 갈지 알 수 없다.
    test('로봇이 제 자리를 모르면 못 찍는다', () {
      expect(
        checkWaypointCapture(poseKnown: false, scaleKnown: true),
        WaypointCaptureReadiness.noPose,
      );
    });

    test('축척을 안 재었으면 못 찍는다', () {
      expect(
        checkWaypointCapture(poseKnown: true, scaleKnown: false),
        WaypointCaptureReadiness.noScale,
      );
    });

    /// 겹쳐 두면 RMF 가 어느 쪽으로 보낼지 애매해지고, 도착 반경(0.1m)끼리
    /// 겹쳐 어느 자리에 섰는지 구별이 안 된다.
    test('이미 있는 자리에는 겹쳐 안 찍는다', () {
      expect(
        checkWaypointCapture(
          poseKnown: true,
          scaleKnown: true,
          nearestGapMeters: 0.10,
        ),
        WaypointCaptureReadiness.tooClose,
      );
    });

    test('충분히 떨어져 있으면 찍는다', () {
      expect(
        checkWaypointCapture(
          poseKnown: true,
          scaleKnown: true,
          nearestGapMeters: 0.5,
        ),
        WaypointCaptureReadiness.ready,
      );
    });

    test('가까운 자리가 하나도 없으면 따질 것이 없다', () {
      expect(
        checkWaypointCapture(
          poseKnown: true,
          scaleKnown: true,
          nearestGapMeters: null,
        ),
        WaypointCaptureReadiness.ready,
      );
    });

    test('못 찍는 까닭은 모두 사람이 읽을 말이 있다', () {
      for (final readiness in WaypointCaptureReadiness.values) {
        if (readiness == WaypointCaptureReadiness.ready) continue;
        expect(waypointCaptureBlockedReason(readiness), isNotNull);
      }
    });
  });

  /// 이름이 곧 RMF 의 `target_guid` 라 겹치면 안 되는데, 사람이 세어서 붙이면
  /// 언젠가 겹친다.
  group('이름을 짓는다', () {
    test('그 카테고리의 다음 번호를 준다', () {
      expect(
        nextWaypointName(
          category: '대기',
          existingNames: ['대기1', '대기2', '충전1'],
        ),
        '대기3',
      );
    });

    test('없으면 1번부터다', () {
      expect(
        nextWaypointName(category: '픽업', existingNames: ['대기1']),
        '픽업1',
      );
    });

    /// 중간이 비어 있어도 가장 큰 번호 다음을 준다. 빈자리를 메우면 예전에
    /// 지운 이름을 되살리는 셈이라, 옛 작업이 엉뚱한 자리를 가리킨다.
    test('빈 번호를 메우지 않는다', () {
      expect(
        nextWaypointName(category: '대기', existingNames: ['대기1', '대기5']),
        '대기6',
      );
    });

    test('다른 카테고리 번호는 안 센다', () {
      expect(
        nextWaypointName(category: '충전', existingNames: ['대기9']),
        '충전1',
      );
    });
  });

  group('방향', () {
    /// 수동으로 자리를 맞췄다면 방향도 맞춘 것이고, 그 각도가 다음 동작을
    /// 가른다 — 대기1 에서 −45도로 선 뒤 후진으로 픽업에 들어가는 식이다.
    test('방향을 쓰는 자리에는 로봇이 보는 쪽을 넣는다', () {
      expect(
        captureHeadingFor(category: '대기', robotHeadingDegrees: -45),
        -45,
      );
      expect(
        captureHeadingFor(category: '충전', robotHeadingDegrees: 180),
        180,
      );
    });

    /// 안 쓰는 자리에 각도를 남겨 두면, 나중에 카테고리를 바꿨을 때 잊어버린
    /// 옛 각도가 되살아난다.
    test('안 쓰는 자리에는 안 넣는다', () {
      expect(
        captureHeadingFor(category: '주차', robotHeadingDegrees: -45),
        isNull,
      );
      expect(
        captureHeadingFor(category: '설비', robotHeadingDegrees: -45),
        isNull,
      );
    });

    test('로봇이 방향을 모르면 안 넣는다', () {
      expect(
        captureHeadingFor(category: '대기', robotHeadingDegrees: null),
        isNull,
      );
    });
  });

  /// 지도를 안 보고 있었으면 눌렀는지도 모른 채 지나간다.
  group('찍고 나서 남기는 말', () {
    test('무엇이 어디에 생겼는지 적는다', () {
      final message = waypointCapturedMessage(
        name: '대기3',
        category: '대기',
        xMeters: 1.069,
        yMeters: -1.623,
        headingDegrees: -45,
      );
      expect(message, contains('대기3'));
      expect(message, contains('1.069'));
      expect(message, contains('-1.623'));
      expect(message, contains('-45도'));
    });

    test('방향이 없으면 각도를 안 적는다', () {
      expect(
        waypointCapturedMessage(
          name: '주차1',
          category: '주차',
          xMeters: 1,
          yMeters: -1,
        ),
        isNot(contains('방향')),
      );
    });

    /// 찍고 끝이 아니라 그 다음에 무엇을 할 수 있는지 알려 준다.
    test('다음에 무엇을 할 수 있는지 적는다', () {
      expect(
        waypointCapturedMessage(
          name: '대기3',
          category: '대기',
          xMeters: 1,
          yMeters: -1,
        ),
        contains('레인'),
      );
    });
  });
}
