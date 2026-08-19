/// 로봇이 장애물을 얼마나 피하는가.
///
/// 실험실에서는 벽이 스티로폼이고 로봇도 작다. 살짝 스쳐도 아무 일이 안
/// 나는데, Nav2 의 기본값은 사람이 다니는 복도를 전제로 잡혀 있어 **닿기 한참
/// 전에 길을 포기한다.** 그러면 로봇이 목표를 몇 뼘 앞에 두고 멈춰 서서, 왜
/// 안 가는지 알 수 없다.
///
/// 그렇다고 장애물을 아예 안 보게 할 수는 없다. 사람이나 다른 로봇처럼 **정말
/// 부딪히면 안 되는 것**은 여전히 있다.
///
/// 그래서 두 가지를 둔다 — 여유를 얼마나 두느냐만 다르고, 라이다로 장애물을
/// 보는 것은 둘 다 똑같다.
///
/// 판정을 화면에서 떼어 둔 것은 [RobotLink] 와 같은 이유다 — 규칙은 눌러 보지
/// 않고도 확인할 수 있어야 한다.
library;

/// 주행 모드.
enum RobotDriveMode {
  /// 일반. Nav2 기본값대로 넉넉히 피한다.
  normal,

  /// 강제. 여유를 최소로 줄여 지정한 자리까지 밀고 간다.
  ///
  /// **장애물을 무시하는 것이 아니다.** 라이다는 그대로 보고, 정말 앞을 막고
  /// 있으면 멈춘다. 다만 "닿을 것 같다" 는 이유로 길을 포기하지 않는다.
  forced,
}

/// 저장·복원에 쓰는 값.
extension RobotDriveModeStorage on RobotDriveMode {
  String get storageValue => name;

  String get label => switch (this) {
    RobotDriveMode.normal => '일반',
    RobotDriveMode.forced => '강제',
  };

  /// 이 모드가 무엇을 하는지 한 줄로.
  String get summary => switch (this) {
    RobotDriveMode.normal =>
      '장애물을 넉넉히 피합니다. 사람이나 다른 로봇이 함께 다니는 곳에 씁니다.',
    RobotDriveMode.forced =>
      '여유를 줄여 지정한 자리까지 밀고 갑니다. 스치듯 지나도 괜찮은 '
          '실험실에 씁니다 — 라이다는 그대로 보므로 앞을 막고 있으면 멈춥니다.',
  };
}

RobotDriveMode parseRobotDriveMode(String? value) =>
    value == RobotDriveMode.forced.name
    ? RobotDriveMode.forced
    : RobotDriveMode.normal;

/// 이 모드에서 쓸 costmap 값.
///
/// 바꾸는 것은 **여유뿐이다.** 라이다로 장애물을 보는 설정(`obstacle_layer` ·
/// `voxel_layer`)은 건드리지 않는다 — 그것을 끄면 정말 부딪히면 안 되는 것도
/// 안 보인다.
class DriveModeCostmap {
  const DriveModeCostmap({
    required this.inflationRadius,
    required this.costScalingFactor,
    required this.footprintPadding,
  });

  /// 장애물 둘레에 비용을 퍼뜨리는 반경 [m].
  ///
  /// 이것이 로봇 반지름보다 크면, 닿지도 않을 거리에서 이미 "못 간다" 가 된다.
  /// 핑키의 발자국은 한 변 0.12m 라 반지름이 0.06m 인데 기본값은 0.15m 였다 —
  /// 벽에서 15cm 안쪽은 통째로 막힌 것으로 본 셈이다.
  final double inflationRadius;

  /// 비용이 얼마나 가파르게 떨어지는가. 클수록 장애물 바로 옆만 비싸진다.
  final double costScalingFactor;

  /// 발자국에 덧대는 여유 [m].
  final double footprintPadding;
}

/// 일반 모드의 값. 벤더 기본값을 그대로 쓴다.
const DriveModeCostmap normalDriveCostmap = DriveModeCostmap(
  inflationRadius: 0.15,
  costScalingFactor: 3.0,
  footprintPadding: 0.03,
);

/// 강제 모드의 값.
///
/// 인플레이션을 코스트맵 한 칸(0.05m)까지 줄인다. 0 으로 두면 장애물 바로 옆도
/// 싸져서 planner 가 벽을 스치는 경로를 뽑는데, 그러면 제어 오차만큼 그대로
/// 박는다. 한 칸은 남긴다.
///
/// `cost_scaling_factor` 를 크게 잡아 비용이 가파르게 떨어지게 한다 — 장애물
/// 바로 옆만 비싸고 그 밖은 평지처럼 보인다.
///
/// 발자국 여유는 0 이다. 실측한 몸 크기 그대로 판단한다.
const DriveModeCostmap forcedDriveCostmap = DriveModeCostmap(
  inflationRadius: 0.05,
  costScalingFactor: 10.0,
  footprintPadding: 0.0,
);

DriveModeCostmap costmapForDriveMode(RobotDriveMode mode) =>
    mode == RobotDriveMode.forced ? forcedDriveCostmap : normalDriveCostmap;

/// 이 로봇이 후진으로도 갈 수 있는가.
///
/// 좁은 곳에서는 앞으로 들어갈 수 없는 자리가 있다 — 대기1 에서 −45도로 선 뒤
/// **후진으로** 픽업에 들어가는 식이다. 벤더 기본값은 `allow_reversing: false`
/// 라, 그런 자리에는 로봇이 앞으로 들어가려고 빙 돌거나 아예 길을 못 찾는다.
///
/// 켜면 **경로계획이 후진 구간을 만들 수 있게** 된다. 사람이 "여기서 뒤로
/// 가라" 고 시키는 것이 아니라, RMF 가 낸 경로를 Nav2 가 따라가다 필요하면
/// 뒤로 간다.
///
/// **제자리 회전과 함께 못 쓴다.** `RegulatedPurePursuitController` 는 후진을
/// 허용하면 `use_rotate_to_heading` 을 끄도록 되어 있다 — 뒤로 갈지 앞으로 갈지
/// 정하는 것과 고개를 먼저 돌리는 것이 서로 부딪히기 때문이다. 둘 다 켜면
/// 컨트롤러가 파라미터를 거절하고 노드가 안 뜬다.
///
/// 그래서 켜면 제자리 회전이 사라진다. 출발할 때 고개를 먼저 돌리는 대신
/// 곡선으로 빠져나가거나 뒤로 간다.
class DriveModeReversing {
  const DriveModeReversing({
    required this.allowReversing,
    required this.useRotateToHeading,
  });

  final bool allowReversing;
  final bool useRotateToHeading;
}

/// 후진을 켜고 끌 때 쓸 값.
///
/// 둘이 서로 배타적이라 한 곳에서 함께 정한다. 따로 두면 한쪽만 바꿔서
/// 노드가 안 뜨는 조합이 나간다.
DriveModeReversing reversingSettings({required bool allowReversing}) =>
    DriveModeReversing(
      allowReversing: allowReversing,
      // 후진을 켜면 제자리 회전은 반드시 꺼야 한다. 컨트롤러가 그 조합을
      // 거절한다.
      useRotateToHeading: !allowReversing,
    );

/// 후진을 켰을 때 사람에게 알릴 말. 껐으면 null.
String? reversingWarning({required bool allowReversing}) {
  if (!allowReversing) return null;
  return '후진을 켜면 제자리 회전이 꺼집니다.\n\n'
      'Nav2 의 `RegulatedPurePursuitController` 는 두 가지를 함께 쓰지 '
      '못합니다 — 뒤로 갈지 정하는 것과 고개를 먼저 돌리는 것이 서로 '
      '부딪히기 때문입니다. 둘 다 켜면 컨트롤러가 파라미터를 거절해 노드가 '
      '안 뜹니다.\n\n'
      '출발할 때 제자리에서 도는 대신 곡선으로 빠져나가거나 뒤로 갑니다. '
      '자리에 방향을 정해 두었다면 그 자세는 그대로 맞춥니다 — 도착 판정은 '
      '`yaw_goal_tolerance` 가 따로 봅니다.';
}

/// 강제 모드로 두었을 때 사람에게 알릴 말. 일반이면 null.
///
/// **어디에 써도 되는 모드가 아니다.** 사람이 함께 다니는 곳에서 이것을 켜면
/// 로봇이 사람 쪽으로 더 붙는다. 고를 때 그 말을 해 둔다.
String? forcedDriveModeWarning(RobotDriveMode mode) {
  if (mode != RobotDriveMode.forced) return null;
  return '강제 모드는 장애물에 스치듯 지나갑니다.\n\n'
      '벽이 스티로폼이거나 부딪혀도 상하지 않는 실험실에서만 쓰세요. '
      '사람이나 다른 로봇이 함께 다니는 곳에서는 일반 모드를 씁니다.\n\n'
      '라이다는 그대로 보므로 앞을 막고 있으면 멈춥니다 — 장애물을 무시하는 '
      '것이 아니라 여유를 줄이는 것입니다.';
}
