/// 팔이 뻗는 자리와 핑키 본체가 부딪히는지 실행 **전에** 본다.
///
/// 픽업은 두 로봇이 같은 자리를 나눠 쓰는 순간이다. 팔은 고정이고 핑키가 그 앞에
/// 서므로, 자리와 각도만 보고도 판정할 수 있다. 부딪힌 뒤에는 무를 수 없다.
library;

import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:rmf_control_ui/workcell_reach_check.dart';

void main() {
  /// 팔은 원점에 있고, 핑키는 x 축을 따라 [distance] 미터 앞에 선다.
  ///
  /// [facing] 은 핑키의 코가 보는 쪽이다. 수납함은 그 반대편(뒤)에 달려 있다.
  /// 팔이 원점에 있고 핑키가 +x 쪽에 서므로, **0 으로 서면**(코가 팔 반대쪽)
  /// 수납함이 팔 쪽으로 온다. `pi` 면 코가 팔을 보고 수납함이 등 뒤로 간다.
  ///
  /// [bodyRadius] 기본값은 핑키의 실제 값이다(`pinky_config.yaml` 의 footprint).
  WorkcellReachCheck check(
    double distance, {
    double? facing = 0,
    double bodyRadius = .10,
    double reach = .38,
    double sweep = defaultArmSweepMeters,
  }) => checkWorkcellReach(
    workcellId: 'OMX_01',
    station: '픽업3',
    armX: 0,
    armY: 0,
    stationX: distance,
    stationY: 0,
    bodyRadius: bodyRadius,
    reach: reach,
    sweep: sweep,
    headingRadians: facing,
  );

  test('제자리에 제 각도로 서면 통과한다', () {
    // 본체 중심 0.60m, 겉면 0.50m(쓸어내는 0.32m + 여유 0.05m 위),
    // 수납함 0.30m → 닿는다.
    final result = check(.60);
    expect(result.risk, WorkcellReachRisk.ok);
    expect(result.isProblem, isFalse);
    expect(result.trayDistance, closeTo(.30, .001));
    expect(result.bodyEdgeDistance, closeTo(.50, .001));
  });

  test('본체가 팔이 쓸어내는 자리 안에 있으면 부딪힌다고 한다', () {
    // 중심 0.40m, 몸 반경 0.10m → 겉면이 0.30m 뿐이다.
    // 팔은 policy 동작에서 0.32m 까지 쓸어내므로 본체가 그 안에 들어간다.
    final result = check(.40);
    expect(result.risk, WorkcellReachRisk.bodyTooClose);
    expect(result.isDanger, isTrue);
    expect(result.title, '핑키 본체와 로봇팔이 부딪힐 위험');
    // 얼마나 떨어뜨려야 하는지 숫자로 준다.
    expect(result.needed, closeTo(.07, .001));
    expect(result.advice, contains('0.07m 더 떨어뜨리세요'));
    expect(result.advice, contains('픽업3'));
    expect(result.advice, contains('OMX_01'));
    // 무엇을 재서 그렇게 보았는지 — 쓸어내는 반경까지 밝힌다.
    expect(result.detail, contains('0.32m 까지 쓸어냅니다'));
  });

  test('기둥은 비켜 서도 팔이 지나가는 자리면 부딪힌다', () {
    // 예전 판정은 팔 밑동 둘레 0.15m 만 봤다. 그 규칙으로는 겉면 0.24m 인
    // 이 배치가 통과했고, project1-ver2 의 설비3·픽업3 이 실제로 부딪혔다.
    //
    // 설비3 (1.160, -2.281) · 픽업3 (1.187, -1.940) · 적재 방향 90.3도.
    final result = checkWorkcellReach(
      workcellId: 'omx_01',
      station: '픽업3',
      armX: 1.160,
      armY: -2.281,
      stationX: 1.187,
      stationY: -1.940,
      bodyRadius: .10,
      reach: armReachOf('omx_f'),
      sweep: armSweepOf('omx_f'),
      headingRadians: 90.3 * math.pi / 180,
    );
    expect(result.centerDistance, closeTo(.342, .002));
    expect(result.bodyEdgeDistance, closeTo(.242, .002));
    expect(result.risk, WorkcellReachRisk.bodyTooClose);
    expect(result.isDanger, isTrue);
    // 0.32m + 0.05m 를 채우려면 0.13m 더 떨어져야 한다.
    expect(result.needed, closeTo(.128, .002));
  });

  test('각도가 반대면 팔이 본체 위로 넘어가야 한다고 한다', () {
    // 코가 팔을 보고 서면 수납함이 등 뒤, 곧 팔에서 가장 먼 자리에 온다.
    final result = check(.60, facing: math.pi);
    expect(result.risk, WorkcellReachRisk.trayBehindBody);
    expect(result.isDanger, isTrue);
    expect(result.trayDistance, closeTo(.90, .001));
    expect(result.advice, contains('적재 방향'));
    expect(result.detail, contains('본체 중심 0.60m'));
  });

  test('멀어서 못 닿으면 얼마나 당겨야 하는지 준다', () {
    // 중심 0.80m → 수납함 0.50m 인데 팔은 0.38m 까지만 닿는다.
    final result = check(.80);
    expect(result.risk, WorkcellReachRisk.trayOutOfReach);
    // 닿지 않는 것은 헛집는 것이지 부딪히는 것은 아니다.
    expect(result.isDanger, isFalse);
    expect(result.isProblem, isTrue);
    expect(result.needed, closeTo(.12, .001));
    expect(result.advice, contains('0.12m 옮기세요'));
  });

  test('각도를 안 정했으면 그렇다고 한다', () {
    final result = check(.60, facing: null);
    expect(result.risk, WorkcellReachRisk.unknownHeading);
    expect(result.detail, contains('들어온 그대로 서면'));
  });

  test('각도를 몰라도 본체가 붙어 있으면 부딪힘이 먼저다', () {
    // 어느 쪽을 보든 부딪힌다. 각도 타령보다 이것을 먼저 말해야 한다.
    expect(check(.40, facing: null).risk, WorkcellReachRisk.bodyTooClose);
  });

  test('긴 팔은 더 먼 자리도 닿는다', () {
    expect(armReachOf('open_manipulator_x'), .38);
    expect(armReachOf('omx_f'), .45);
    // 모르는 모델은 가장 짧은 팔로 본다 — 넉넉히 잡으면 못 닿는 자리를 통과시킨다.
    expect(armReachOf('무슨_팔'), defaultArmReachMeters);
    // 수납함이 0.44m 자리다. 짧은 팔은 못 닿고 긴 팔은 닿는다.
    expect(
      check(.74, reach: armReachOf('open_manipulator_x')).risk,
      WorkcellReachRisk.trayOutOfReach,
    );
    expect(check(.74, reach: armReachOf('omx_f')).risk, WorkcellReachRisk.ok);
  });

  test('쓸어내는 반경은 모르는 모델일수록 크게 본다', () {
    expect(armSweepOf('open_manipulator_x'), .29);
    expect(armSweepOf('omx_f'), .32);
    // 닿는 거리와 안전한 방향이 반대다. 작게 잡으면 부딪히는 자리가 통과한다.
    expect(armSweepOf('무슨_팔'), defaultArmSweepMeters);
    // 겉면 0.35m — 적게 쓸어내는 팔은 통과하고 많이 쓸어내는 팔은 걸린다.
    expect(check(.45, sweep: .29).risk, WorkcellReachRisk.ok);
    expect(check(.45, sweep: .32).risk, WorkcellReachRisk.bodyTooClose);
  });

  group('경고 글', () {
    test('문제가 없으면 아무 말도 하지 않는다', () {
      expect(workcellReachWarning([check(.60)]), isNull);
      expect(workcellReachWarning(const []), isNull);
    });

    test('위험한 것을 먼저 적는다', () {
      final warning = workcellReachWarning([
        check(.80), // 못 닿음
        check(.40), // 부딪힘
      ])!;
      expect(warning.indexOf('부딪힐 위험'), lessThan(warning.indexOf('닿지 않음')));
      // 어느 자리를 어떻게 고치라는 말이 함께 있어야 한다.
      expect(warning, contains('픽업3'));
      expect(warning, contains('Waypoint'));
    });
  });
}
