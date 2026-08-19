/// 로봇이 마지막으로 간 자리를 찾는다.
///
/// 앱을 다시 켜면 지도에 로봇이 없다 — 지도에 올린 로봇(`_mockRobots`)은 앱
/// 안에만 있기 때문이다. 그때 어디에 그릴지 정해야 하는데, 등록의 충전 자리에
/// 놓으면 **실제와 어긋난다.** 로봇은 대기1 에 서 있는데 지도에는 충전1 에
/// 그려지고, 그 상태에서 다른 자리로 보내면 화면과 실제가 벌어진 채로 움직인다.
///
/// 토픽이 오면 그것이 가장 정확하다(AMCL 이 제 위치를 말해 준다). 그런데 앱을
/// 켠 직후나 백엔드를 다시 띄우는 동안에는 토픽이 아직 없다. 그 사이를
/// **마지막 작업의 마지막 목적지**로 메운다 — 작업이 끝났다면 로봇은 거기 있다.
///
/// 어디까지나 **짐작**이다. 토픽이 오는 순간 그쪽이 이긴다. 사람이 로봇을 손으로
/// 옮겼으면 이 짐작은 틀리고, 그때는 `이 자리를 초기 위치로 보내기` 로 바로잡는다.
///
/// 판정을 화면에서 떼어 둔 것은 [RobotLink] 와 같은 이유다 — 규칙은 눌러 보지
/// 않고도 확인할 수 있어야 한다.
library;

/// 자리를 어디서 알아냈는가.
///
/// 화면이 이것을 밝혀야 한다. 짐작을 실측처럼 보여 주면 사람이 그것을 믿고
/// 작업을 낸다.
enum RobotPlaceSource {
  /// 토픽에서 왔다. 가장 정확하다.
  telemetry,

  /// 마지막으로 끝낸 작업의 목적지다. 짐작이다.
  lastTask,

  /// 등록된 자리다. 아직 아무 일도 안 한 로봇이다.
  registration,
}

/// 마지막으로 간 자리를 찾는 데 필요한 작업 한 건.
///
/// 화면의 작업 모델을 그대로 받지 않는다 — 그러면 이 규칙이 화면에 묶여
/// 눌러 보지 않고는 확인할 수 없게 된다.
class RobotTaskTrace {
  const RobotTaskTrace({
    required this.robotId,
    required this.finishedAt,
    required this.destinations,
    this.completed = true,
  });

  final String robotId;

  /// 끝난 시각. 안 끝났으면 null.
  final DateTime? finishedAt;

  /// 이 작업이 거친 자리 이름. 차례대로다.
  final List<String> destinations;

  /// 끝까지 갔는가.
  ///
  /// 중간에 멈춘 작업의 마지막 목적지는 **가지 않은 자리**다. 그것을 지금
  /// 자리로 보면 로봇이 실제로 있는 곳보다 앞서 그려진다.
  final bool completed;
}

/// 이 로봇이 마지막으로 간 자리. 알 수 없으면 null.
///
/// 끝난 작업만 본다. 그중 가장 나중에 끝난 것의 **마지막** 목적지가 답이다 —
/// 여러 자리를 거치는 작업이면 마지막에 선 곳이 지금 자리다.
String? lastVisitedPlace({
  required String robotId,
  required Iterable<RobotTaskTrace> tasks,
}) {
  RobotTaskTrace? latest;
  for (final task in tasks) {
    if (task.robotId != robotId) continue;
    if (!task.completed) continue;
    final at = task.finishedAt;
    if (at == null) continue;
    if (task.destinations.every((name) => name.trim().isEmpty)) continue;
    final best = latest?.finishedAt;
    if (best == null || at.isAfter(best)) latest = task;
  }
  if (latest == null) return null;
  for (final name in latest.destinations.reversed) {
    final trimmed = name.trim();
    if (trimmed.isNotEmpty) return trimmed;
  }
  return null;
}

/// 지도에 그릴 자리와 그것을 어디서 알았는지.
///
/// [telemetryPlace] 는 토픽에서 온 자리다. 있으면 언제나 이긴다 — 짐작보다
/// 실측이 낫고, 사람이 로봇을 옮겼어도 토픽은 그것을 안다.
///
/// [registeredPlace] 는 등록의 자리다. 마지막 자리조차 없으면 여기로 떨어진다.
({String? place, RobotPlaceSource source}) resolveRobotPlace({
  String? telemetryPlace,
  String? lastPlace,
  String? registeredPlace,
}) {
  final live = (telemetryPlace ?? '').trim();
  if (live.isNotEmpty) {
    return (place: live, source: RobotPlaceSource.telemetry);
  }
  final last = (lastPlace ?? '').trim();
  if (last.isNotEmpty) {
    return (place: last, source: RobotPlaceSource.lastTask);
  }
  final registered = (registeredPlace ?? '').trim();
  return (
    place: registered.isEmpty ? null : registered,
    source: RobotPlaceSource.registration,
  );
}

/// 자리를 못 찾은 로봇을 알릴 말. 알릴 것이 없으면 null.
///
/// **조용히 넘기면 안 된다.** 예전에는 자리를 못 찾으면 그냥 안 그렸다. 그래서
/// 지도에 로봇이 없는 것이 "아직 안 왔다" 인지 "어디 있는지 모른다" 인지
/// 구별되지 않았고, 사람은 기다리기만 했다.
///
/// 자리를 모르는 까닭은 셋 중 하나다 — 토픽이 안 오고, 끝낸 작업이 없고,
/// 등록의 자리 이름이 지도에 없다. 어느 쪽이든 사람이 **로봇 등록에서 자리를
/// 정해 주면** 풀린다.
String? unknownPlaceMessage(List<String> robotLabels) {
  if (robotLabels.isEmpty) return null;
  final lines = [for (final label in robotLabels) '  · $label'];
  return '다음 로봇이 지금 어디 있는지 모릅니다.\n\n'
      '${lines.join('\n')}\n\n'
      '토픽이 아직 안 오고, 마지막으로 간 자리도 없습니다. '
      '지도에 안 그려지므로 작업을 낼 수 없습니다.\n\n'
      '로봇 등록에서 자리 Waypoint 를 정해 주세요. 로봇이 실제로 서 있는 '
      '자리를 고르면 됩니다 — 토픽이 오기 시작하면 그때부터는 로봇이 말하는 '
      '위치를 씁니다.';
}

/// 이 자리를 어디서 알았는지 사람이 읽을 말.
///
/// 짐작을 실측처럼 보여 주면 안 된다. 그것을 믿고 작업을 내면, 로봇이 실제로
/// 있는 곳과 다른 자리에서 출발한 것으로 계산된다.
String robotPlaceSourceLabel(RobotPlaceSource source) => switch (source) {
  RobotPlaceSource.telemetry => '로봇이 보내는 위치',
  RobotPlaceSource.lastTask => '마지막 작업이 끝난 자리 — 짐작입니다',
  RobotPlaceSource.registration => '등록된 자리 — 아직 움직인 기록이 없습니다',
};
