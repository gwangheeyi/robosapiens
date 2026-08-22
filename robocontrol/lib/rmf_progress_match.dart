/// 어댑터가 낸 도착 소식을 우리 단계 목록의 어디에 맞출지 고른다.
///
/// 앱의 단계와 RMF 가 실제로 모는 것은 하나씩 짝지어지지 않는다. RMF 는 Lane 을
/// 따라 중간 Waypoint 를 스스로 끼워 넣으므로, 도착 소식은 우리가 적어 둔 자리
/// 것보다 훨씬 자주 온다. 그래서 **우리 단계의 목적지와 같을 때만** 넘긴다.
///
/// 문제는 그 다음이었다. 예전에는 지금 단계에 안 맞는 소식을 전부 버렸다. 소식
/// 하나만 놓치면 지금 단계가 영영 뒤에 남고, 그 뒤로 오는 소식은 모두 안 맞아서
/// 또 버려진다. 2026-08-17 에 실제로 그랬다 —
///
///   대기3 → 픽업3 → 적재 → 대기3
///
/// 짜리 작업에서 첫 `navigate_start` 를 놓쳐(구독이 늦게 붙었다) 첫 도착이
/// 버려졌고, 그 뒤 픽업3 도착도 적재 완료도 전부 안 맞는 소식이 되었다. 로봇은
/// 적재를 끝내고 대기3 까지 돌아왔는데 화면은 `적재 안 됨 · 진행중` 이었다.
///
/// 그래서 여기서는 **앞을 본다.** 지금 단계에 안 맞으면 그 뒤 단계에 맞는지
/// 보고, 맞으면 사이의 단계까지 함께 끝난 것으로 본다. RMF 는 단계를 건너뛰지
/// 않으므로, 뒤 단계에 닿았다는 것은 앞 단계를 이미 지났다는 뜻이다.
library;

import 'dart:math' as math;

/// 앞을 볼 때 이 안에 들면 같은 자리로 본다 [m].
///
/// RMF 가 주는 좌표는 nav graph 의 Waypoint 값 그대로이므로 우리가 도면에서
/// 계산한 값과 소수점 아래까지 같아야 한다. 2cm 는 반올림 자리를 덮는 값이지
/// "이쯤이면 됐다" 가 아니다 — 넓히면 옆 Waypoint 를 제 자리로 착각한다.
const double progressGoalToleranceMeters = .02;

/// 단계 하나의 성격. 이 파일은 앱의 단계 종류를 알 필요가 없다.
enum ProgressStepKind {
  /// 어딘가로 간다. 도착 소식이 목적지로 짝지어진다.
  movement,

  /// 설비가 짐을 올린다. `action_done` 이 짝이다.
  armLoad,

  /// 그 밖. 도착 소식으로는 넘어가지 않는다.
  other,
}

/// 맞춰 볼 단계 하나.
class ProgressStep {
  const ProgressStep({required this.kind, this.x, this.y});

  final ProgressStepKind kind;

  /// 이동 단계면 목적지. RMF 월드 좌표(m). 모르면 null.
  final double? x;
  final double? y;
}

/// 도착 소식 하나로 **어느 단계까지 끝난 것으로 볼지** 고른다.
///
/// 돌려주는 것은 끝난 것으로 볼 마지막 단계의 자리이고, 맞는 것이 없으면 null
/// 이다. [currentIndex] 부터 그 자리까지가 한꺼번에 끝난 것이 된다.
///
/// [isArmLoad] 가 참이면 `action_done`, 거짓이면 `navigate_done` 이다.
///
/// **적재 단계는 절대 뛰어넘지 않는다.** 이동 소식으로 앞을 볼 때 적재 단계를
/// 만나면 거기서 멈춘다. 로봇이 지나갔다는 것만 보고 짐을 실었다고 적으면,
/// 아무도 안 본 적재가 완료로 남는다 — 그것이 이 화면이 하면 안 되는 거짓말이다.
int? matchedProgressStep({
  required List<ProgressStep> steps,
  required int currentIndex,
  required bool isArmLoad,
  double? goalX,
  double? goalY,
  double tolerance = progressGoalToleranceMeters,
}) {
  if (currentIndex < 0 || currentIndex >= steps.length) return null;
  if (isArmLoad) {
    for (var index = currentIndex; index < steps.length; index++) {
      if (steps[index].kind == ProgressStepKind.armLoad) return index;
    }
    return null;
  }
  if (goalX == null || goalY == null) return null;
  for (var index = currentIndex; index < steps.length; index++) {
    final step = steps[index];
    if (step.kind == ProgressStepKind.armLoad) return null;
    if (step.kind != ProgressStepKind.movement) continue;
    final x = step.x;
    final y = step.y;
    if (x == null || y == null) continue;
    final gap = math.sqrt(math.pow(goalX - x, 2) + math.pow(goalY - y, 2));
    if (gap <= tolerance) return index;
  }
  return null;
}
