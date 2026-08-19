/// 어떤 주문을 어느 작업이 받는가.
///
/// 주문 한 건에 여러 구획이 섞일 수 있다 — 냉장 우유와 상온 과자를 함께
/// 시키면 그 주문의 구획은 `{chilled, ambient}` 다. 낱개(상온·냉장·냉동)만
/// 두면 그런 주문을 어느 쪽이 받아야 하는지 알 수 없다.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:rmf_control_ui/order_trigger.dart';

void main() {
  group('종류와 차례', () {
    /// 화면에 보이는 차례다. `모든 주문` 이 맨 앞인 것은 대부분의 작업이
    /// 그것을 쓰기 때문이다 — 목록 맨 위가 가장 자주 고르는 것이라야 한다.
    test('여덟 가지가 정해진 차례로 있다', () {
      expect(
        OrderTrigger.values.map((t) => t.label).toList(),
        [
          '모든 주문',
          '냉동 주문',
          '냉장 주문',
          '상온 주문',
          '상온·냉장 주문',
          '상온·냉동 주문',
          '냉장·냉동 주문',
          '수동 실행',
        ],
      );
    });

    test('구획 조합이 이름과 맞는다', () {
      expect(OrderTrigger.frozen.zones, {'frozen'});
      expect(OrderTrigger.ambientChilled.zones, {'ambient', 'chilled'});
      expect(OrderTrigger.chilledFrozen.zones, {'chilled', 'frozen'});
      // 구획을 안 가리는 둘은 비어 있다.
      expect(OrderTrigger.any.zones, isEmpty);
      expect(OrderTrigger.manual.zones, isEmpty);
    });

    test('모두 사람이 읽을 설명이 있다', () {
      for (final trigger in OrderTrigger.values) {
        expect(trigger.label, isNotEmpty);
        expect(trigger.summary, isNotEmpty);
      }
    });
  });

  group('주문을 받는가', () {
    test('모든 주문은 구획을 안 가린다', () {
      expect(orderTriggerMatches(OrderTrigger.any, {'frozen'}), isTrue);
      expect(
        orderTriggerMatches(OrderTrigger.any, {'ambient', 'chilled'}),
        isTrue,
      );
    });

    test('수동은 자동으로 안 받는다', () {
      expect(orderTriggerMatches(OrderTrigger.manual, {'ambient'}), isFalse);
    });

    test('낱개는 그 구획만 받는다', () {
      expect(orderTriggerMatches(OrderTrigger.frozen, {'frozen'}), isTrue);
      expect(orderTriggerMatches(OrderTrigger.frozen, {'chilled'}), isFalse);
    });

    /// **정확히 같아야 한다.** 상온·냉장 주문을 `상온 주문` 작업이 받으면,
    /// 냉장 상품을 실은 채로 냉장칸에 못 들어가는 경로를 탄다.
    test('낱개 작업은 섞인 주문을 안 받는다', () {
      expect(
        orderTriggerMatches(OrderTrigger.ambient, {'ambient', 'chilled'}),
        isFalse,
      );
    });

    /// 반대로 상온만 있는 주문을 `상온·냉장` 작업이 받으면 쓸데없이 냉장칸을
    /// 도는 경로가 된다.
    test('조합 작업은 낱개 주문을 안 받는다', () {
      expect(
        orderTriggerMatches(OrderTrigger.ambientChilled, {'ambient'}),
        isFalse,
      );
    });

    test('조합이 정확히 맞으면 받는다', () {
      expect(
        orderTriggerMatches(OrderTrigger.ambientChilled, {
          'chilled',
          'ambient',
        }),
        isTrue,
        reason: '순서는 상관없다',
      );
    });

    /// 무엇인지 모르는 것을 특정 구획 작업에 넘기면 그 작업이 못 가는 데로
    /// 갈 수 있다.
    test('구획을 모르는 주문은 모든 주문만 받는다', () {
      expect(orderTriggerMatches(OrderTrigger.any, <String>{}), isTrue);
      expect(orderTriggerMatches(OrderTrigger.ambient, <String>{}), isFalse);
    });
  });

  group('주문을 보고 종류를 찾는다', () {
    test('낱개도 조합도 찾아낸다', () {
      expect(orderTriggerForZones({'frozen'}), OrderTrigger.frozen);
      expect(
        orderTriggerForZones({'ambient', 'frozen'}),
        OrderTrigger.ambientFrozen,
      );
    });

    /// 셋이 다 섞인 주문은 딱 맞는 종류가 없다. 세 구획을 다 도는 작업을 따로
    /// 두는 것보다, 구획을 안 가리는 작업에 맡기는 편이 낫다.
    test('셋이 다 섞이면 딱 맞는 종류가 없다', () {
      expect(
        orderTriggerForZones({'ambient', 'chilled', 'frozen'}),
        isNull,
      );
      expect(
        orderZonesLabel({'ambient', 'chilled', 'frozen'}),
        contains('모든 주문'),
      );
    });

    test('사람이 읽을 말로 바꾼다', () {
      expect(orderZonesLabel({'chilled'}), '냉장 주문');
      expect(orderZonesLabel({'ambient', 'frozen'}), '상온·냉동 주문');
      expect(orderZonesLabel(<String>{}), contains('모르는'));
    });
  });

  group('저장한 값을 읽는다', () {
    test('이름 그대로 되읽는다', () {
      for (final trigger in OrderTrigger.values) {
        expect(parseOrderTrigger(trigger.name), trigger);
      }
    });

    /// **모르는 값을 `모든 주문` 으로 보면 안 된다.** 그러면 저장이 깨졌을 때
    /// 아무 주문이나 받아 로봇이 못 가는 구획으로 간다.
    test('모르는 값은 수동으로 본다', () {
      expect(parseOrderTrigger(null), OrderTrigger.manual);
      expect(parseOrderTrigger('없는값'), OrderTrigger.manual);
      // 예전 판에 있던 이름이 사라져도 아무 주문이나 받지 않는다.
      expect(parseOrderTrigger(''), OrderTrigger.manual);
    });
  });
}
