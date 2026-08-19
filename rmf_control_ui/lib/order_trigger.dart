/// 어떤 주문을 이 작업으로 받을 것인가.
///
/// 주문은 상품마다 보관 구획이 정해져 있다 — 상온·냉장·냉동. MySQL 의
/// `lots.zone` 이 그것이고, 주문 한 건에 여러 구획이 섞일 수 있다. 냉장 우유와
/// 상온 과자를 함께 시키면 그 주문의 구획은 `{chilled, ambient}` 다.
///
/// 작업은 자기가 받을 구획 조합을 미리 정해 둔다. 조합이 안 맞으면 그 작업은
/// 그 주문을 안 받는다 — 냉동칸에 못 들어가는 로봇에게 냉동 주문을 주면 그
/// 자리에서 멈춘다.
///
/// **조합을 낱개로 쪼개 두지 않는다.** `상온` 과 `냉장` 을 따로 두면 상온·냉장이
/// 섞인 주문을 어느 쪽이 받아야 하는지 알 수 없다. 그래서 섞인 조합도 하나의
/// 종류로 둔다.
///
/// 판정을 화면에서 떼어 둔 것은 [RobotLink] 와 같은 이유다 — 규칙은 눌러 보지
/// 않고도 확인할 수 있어야 한다.
library;

/// 보관 구획. MySQL `lots.zone` 의 값과 같아야 한다.
const String zoneAmbient = 'ambient';
const String zoneChilled = 'chilled';
const String zoneFrozen = 'frozen';

/// 주문 종류. 화면에 보이는 차례 그대로다.
///
/// 낱개(상온·냉장·냉동)를 먼저 두지 않고 **모든 주문**을 맨 앞에 둔다. 대부분의
/// 작업이 그것을 쓰고, 목록 맨 위가 가장 자주 고르는 것이라야 한다.
enum OrderTrigger {
  /// 구획을 안 가린다.
  any,

  frozen,
  chilled,
  ambient,

  /// 상온과 냉장이 **함께** 있는 주문.
  ambientChilled,

  /// 상온과 냉동이 함께 있는 주문.
  ambientFrozen,

  /// 냉장과 냉동이 함께 있는 주문.
  chilledFrozen,

  /// 자동으로 안 받는다. 사람이 눌러야 돈다.
  manual,
}

extension OrderTriggerInfo on OrderTrigger {
  String get label => switch (this) {
    OrderTrigger.any => '모든 주문',
    OrderTrigger.frozen => '냉동 주문',
    OrderTrigger.chilled => '냉장 주문',
    OrderTrigger.ambient => '상온 주문',
    OrderTrigger.ambientChilled => '상온·냉장 주문',
    OrderTrigger.ambientFrozen => '상온·냉동 주문',
    OrderTrigger.chilledFrozen => '냉장·냉동 주문',
    OrderTrigger.manual => '수동 실행',
  };

  /// 이 종류가 요구하는 구획. `모든 주문`·`수동 실행` 은 비어 있다.
  Set<String> get zones => switch (this) {
    OrderTrigger.any || OrderTrigger.manual => const {},
    OrderTrigger.frozen => const {zoneFrozen},
    OrderTrigger.chilled => const {zoneChilled},
    OrderTrigger.ambient => const {zoneAmbient},
    OrderTrigger.ambientChilled => const {zoneAmbient, zoneChilled},
    OrderTrigger.ambientFrozen => const {zoneAmbient, zoneFrozen},
    OrderTrigger.chilledFrozen => const {zoneChilled, zoneFrozen},
  };

  /// 사람이 고를 때 무엇을 뜻하는지.
  String get summary => switch (this) {
    OrderTrigger.any => '구획을 안 가리고 다 받습니다.',
    OrderTrigger.manual => '자동으로 안 받습니다. 사람이 눌러야 돕니다.',
    _ => '${zones.length == 1 ? '' : '이 구획들이 함께 있는 '}주문만 받습니다.',
  };
}

/// 저장된 값을 읽는다. 모르는 값은 수동으로 본다.
///
/// **모르는 값을 `모든 주문` 으로 보면 안 된다.** 그러면 저장이 깨졌을 때
/// 아무 주문이나 받아 로봇이 못 가는 구획으로 간다.
OrderTrigger parseOrderTrigger(String? value) {
  for (final trigger in OrderTrigger.values) {
    if (trigger.name == value) return trigger;
  }
  return OrderTrigger.manual;
}

/// 이 주문을 이 작업이 받는가.
///
/// [orderZones] 는 주문에 든 상품들의 구획이다 — MySQL 에서 `lots.zone` 을 모아
/// 온 것이다.
///
/// **정확히 같아야 한다.** 상온·냉장 주문을 `상온 주문` 작업이 받으면, 냉장
/// 상품을 실은 채로 냉장칸에 못 들어가는 경로를 탄다. 반대로 상온만 있는
/// 주문을 `상온·냉장` 작업이 받으면 쓸데없이 냉장칸을 도는 경로가 된다.
///
/// 구획을 모르는 주문(빈 목록)은 `모든 주문` 만 받는다. 무엇인지 모르는 것을
/// 특정 구획 작업에 넘기면 그 작업이 못 가는 데로 갈 수 있다.
bool orderTriggerMatches(OrderTrigger trigger, Set<String> orderZones) {
  if (trigger == OrderTrigger.manual) return false;
  if (trigger == OrderTrigger.any) return true;
  if (orderZones.isEmpty) return false;
  final wanted = trigger.zones;
  return wanted.length == orderZones.length &&
      wanted.every(orderZones.contains);
}

/// 이 구획 조합에 딱 맞는 종류. 없으면 null.
///
/// 주문을 보고 어느 종류인지 알려 줄 때 쓴다 — 사람이 작업을 만들 때 "이
/// 주문은 상온·냉동입니다" 라고 짚어 준다.
///
/// 셋이 다 섞인 주문은 딱 맞는 종류가 없다. 그런 주문은 `모든 주문` 작업이
/// 받는다 — 세 구획을 다 도는 작업을 따로 두는 것보다, 구획을 안 가리는
/// 작업에 맡기는 편이 낫다.
OrderTrigger? orderTriggerForZones(Set<String> zones) {
  if (zones.isEmpty) return null;
  for (final trigger in OrderTrigger.values) {
    if (trigger == OrderTrigger.any || trigger == OrderTrigger.manual) {
      continue;
    }
    if (orderTriggerMatches(trigger, zones)) return trigger;
  }
  return null;
}

/// 이 주문이 어떤 종류인지 사람에게 보여 줄 말.
String orderZonesLabel(Set<String> zones) {
  if (zones.isEmpty) return '구획을 모르는 주문';
  final trigger = orderTriggerForZones(zones);
  if (trigger != null) return trigger.label;
  // 셋이 다 섞였다. 딱 맞는 종류가 없으므로 있는 그대로 적는다.
  const names = {
    zoneAmbient: '상온',
    zoneChilled: '냉장',
    zoneFrozen: '냉동',
  };
  final parts = [
    for (final zone in [zoneAmbient, zoneChilled, zoneFrozen])
      if (zones.contains(zone)) names[zone]!,
  ];
  return '${parts.join('·')} 주문 — `모든 주문` 작업이 받습니다';
}
