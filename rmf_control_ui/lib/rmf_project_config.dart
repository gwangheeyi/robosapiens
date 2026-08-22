/// 맵 프로젝트에서 Open-RMF 설정 파일을 만든다.
///
/// 플릿 설정은 맵을 따라간다. 맵이 다르면 Waypoint 이름도 충전소 위치도 다르므로
/// 전역 fleet.yaml 하나를 돌려 쓰면 프로젝트를 바꾸는 순간 어긋난다.
///
/// 여기서 만든 결과는 `map_project_files` 에 프로젝트별로 보관한다.
library;

import 'dart:math' as math;

import 'robot_drive_mode.dart';
import 'nav2_params.dart'
    show
        nav2LifecycleBondTimeoutSeconds,
        nav2LifecycleServiceTimeoutSeconds,
        nav2MapTopic,
        nav2MapTopicName;
import 'rmf_task_request.dart' show rmfArmLoadAction;
import 'workcell_pairing.dart';
import 'workcell_policy.dart';

/// 이 로봇의 값이 어디서 오는가.
///
/// 로봇마다 다를 수 있다. 실물 두 대를 돌리면서 한 대만 Gazebo 로 시험하는 일이
/// 흔하다. 앱 전체에 하나로 두면 그런 구성을 담을 수 없다.
///
/// 무엇을 고르느냐에 따라 실행에 들어가는 자리가 갈린다.
///
/// | | fleet adapter | Gazebo bringup | 토픽 다리 |
/// |---|---|---|---|
/// | mock   | 안 감 | 안 감 | 안 감 |
/// | gazebo | 감 | 감 | 감 |
/// | real   | 감 | 안 감 | 안 감 |
enum RobotDataSource {
  /// 앱이 100ms 마다 직접 계산한 값. ROS 는 아예 관여하지 않는다.
  mock,

  /// Gazebo 가 물리를 돌리고 그 결과가 ROS 토픽으로 온다.
  gazebo,

  /// 실물 로봇에서 온 ROS 토픽.
  real;

  String get label => switch (this) {
    RobotDataSource.mock => '앱 Mock 데이터',
    RobotDataSource.gazebo => 'Gazebo 시뮬레이션',
    RobotDataSource.real => '실제 로봇',
  };

  /// 로봇 화면의 `로봇 실행 방식` 에 쓰는 짧은 이름.
  String get shortLabel => switch (this) {
    RobotDataSource.mock => '앱 Mock',
    RobotDataSource.gazebo => 'Gazebo 시뮬레이션',
    RobotDataSource.real => '실제 로봇',
  };

  /// 이 값이 무엇인지 한 줄로.
  String get summary => switch (this) {
    RobotDataSource.mock => '앱이 계산한 값입니다. 실제 로봇도 Gazebo도 아닙니다.',
    RobotDataSource.gazebo => 'Gazebo가 물리를 돌리고 그 결과를 ROS 토픽으로 주고받습니다.',
    RobotDataSource.real => '실물 로봇이 보내는 ROS 토픽입니다.',
  };

  /// ROS 토픽을 주고받는가. Mock 은 앱 안에서만 돈다.
  bool get usesTopics => this != RobotDataSource.mock;

  static RobotDataSource parse(String? value) => switch (value) {
    'gazebo' => RobotDataSource.gazebo,
    'real' => RobotDataSource.real,
    _ => RobotDataSource.mock,
  };
}

/// 로봇이 돌아다니는지 한자리에 붙어 있는지.
///
/// 둘은 등록 정보도 실행 방법도 다르다. 이동 로봇은 충전소가 있어야 하고
/// fleet adapter 가 배차한다. 설치 로봇은 설비 자리에 고정되고 fleet 에 들어가지
/// 않는다 — Open-RMF 에서 이런 것은 플릿이 아니라 workcell 이다.
enum RmfRobotKind {
  /// 이동 로봇. Pinky 처럼 Lane 을 따라 다닌다.
  mobile,

  /// 설치 로봇. OpenMANIPULATOR 처럼 설비 자리에 고정된다.
  workcell;

  String get label => this == RmfRobotKind.mobile ? '이동 로봇' : '설치 로봇';

  /// 이 로봇이 설 자리를 고를 Waypoint 카테고리.
  String get waypointCategory => this == RmfRobotKind.mobile ? '충전' : '설비';

  static RmfRobotKind parse(String? value) =>
      value == 'workcell' ? RmfRobotKind.workcell : RmfRobotKind.mobile;

  String get storageValue => name;
}

/// ROS 2 는 도메인으로 망을 가른다. 안 정하면 0 이다.
///
/// 같은 도메인에 있는 노드끼리만 서로를 본다. 이것이 어긋나면 **아무 오류도
/// 안 나면서** 아무것도 안 통한다 — 지도를 배포해도 시뮬레이터가 못 받고,
/// 로봇을 띄워도 관제가 못 본다. 그래서 프로젝트가 이 값을 들고 있어야 한다.
const int defaultRosDomainId = 0;

/// 여기까지는 어느 환경에서나 안전하다. 그 위는 OS 의 임시 포트 범위와 겹칠 수
/// 있어 DDS 가 포트를 못 잡는 일이 생긴다.
const int safeMaxRosDomainId = 101;

/// ROS 2 가 받는 가장 큰 도메인 번호.
const int maxRosDomainId = 232;

/// 이 번호를 도메인으로 쓸 수 있나. 쓸 수 있으면 null, 아니면 까닭.
String? rosDomainIdError(int? domainId) {
  if (domainId == null) return '0 부터 $maxRosDomainId 사이의 정수를 넣으세요.';
  if (domainId < 0 || domainId > maxRosDomainId) {
    return '0 부터 $maxRosDomainId 사이여야 합니다.';
  }
  return null;
}

/// 받기는 하지만 알려 줘야 하는 번호인가. 문제없으면 null.
String? rosDomainIdWarning(int domainId) {
  if (domainId <= safeMaxRosDomainId) return null;
  return '$safeMaxRosDomainId 을 넘는 도메인은 OS 의 임시 포트 범위와 겹칠 수 '
      '있습니다. DDS 가 포트를 못 잡으면 노드가 서로를 못 봅니다.';
}

/// 프로젝트에 속한 로봇 한 대.
class RmfProjectRobot {
  const RmfProjectRobot({
    required this.robotId,
    required this.displayName,
    required this.model,
    required this.gzName,
    required this.zones,
    this.kind = RmfRobotKind.mobile,
    this.dataSource = RobotDataSource.mock,
    this.chargerWaypoint,
    this.spawnX,
    this.spawnY,
    this.spawnHeading = 0,
    this.rosDomainId,
    this.ssh,
    this.driveMode = RobotDriveMode.normal,
    this.allowReversing = false,
  });

  /// 후진으로도 갈 수 있는가.
  ///
  /// 좁은 곳에서는 앞으로 들어갈 수 없는 자리가 있다. 켜면 경로계획이 후진
  /// 구간을 만들 수 있게 된다 — 대신 제자리 회전이 꺼진다. 까닭은
  /// `robot_drive_mode.dart` 의 [reversingSettings] 에 적었다.
  final bool allowReversing;

  /// 장애물을 얼마나 피하는가.
  ///
  /// 실험실처럼 스쳐도 괜찮은 곳에서는 `강제` 로 두어 여유를 줄인다. 까닭은
  /// `robot_drive_mode.dart` 에 적었다.
  final RobotDriveMode driveMode;

  /// 실물 로봇에 들어가는 길. 안 적었으면 null.
  ///
  /// 실물 로봇은 앱이 도는 PC 가 아니라 제 안에서 하드웨어를 연다. 그래서
  /// 브링업은 사람이 로봇에 들어가 손으로 쳐야 했고, 그 자리에서 네임스페이스와
  /// 도메인이 자주 어긋났다 — **어긋나도 오류가 안 나서** 라이다나 AMCL 을
  /// 의심하며 한참을 헤맸다.
  ///
  /// 여기에 주소를 적어 두면 앱이 대신 띄운다. 명령은 등록된 값으로 만들어지므로
  /// 오타로 어긋날 일이 없다.
  ///
  /// 형식은 `RobotSshTarget.toJson` 이다. 그 클래스를 여기서 쓰지 않는 것은
  /// `robot_ssh.dart` 가 이 파일을 읽기 때문이다 — 서로 읽으면 순환이 된다.
  final Map<String, dynamic>? ssh;

  /// 이 로봇만 다른 ROS 도메인을 쓸 때 그 번호. null 이면 프로젝트 기본값.
  ///
  /// 실물 로봇은 제 도메인을 갖고 오는 일이 흔하다. 한 대만 다른 망에 있어도
  /// 나머지를 따라 옮길 이유는 없으므로 대마다 따로 둔다.
  ///
  /// **Gazebo 로봇은 시뮬레이터와 같은 도메인이어야 한다.** 다르면 다리가
  /// 걸어 놓은 토픽에 값이 하나도 안 온다 — 오류는 안 난다.
  final int? rosDomainId;

  final String robotId;
  final String displayName;
  final String model;

  /// 돌아다니는 로봇인지 한자리에 붙은 설비인지.
  final RmfRobotKind kind;

  /// 이 로봇의 값이 어디서 오는가. 실행에 들어가는 자리가 여기서 갈린다.
  final RobotDataSource dataSource;

  /// Gazebo 모델 이름. 토픽 네임스페이스로도 쓰인다(`/<gzName>/odom`).
  final String gzName;

  /// TempZone.name 목록. 관제 배차의 입찰 자격이 된다. 설치 로봇은 배차를 받지
  /// 않으므로 비어 있어도 된다.
  final List<String> zones;

  /// 이 로봇이 서 있는 Waypoint 이름.
  ///
  /// 이동 로봇이면 충전 Waypoint 로, fleet adapter 의 `robots[].charger` 가 된다.
  /// 설치 로봇이면 설비 Waypoint 로, 그 자리에 고정 설치된다.
  final String? chargerWaypoint;
  final double? spawnX;
  final double? spawnY;
  final double spawnHeading;

  /// 올릴 자리만 바꾼 사본.
  ///
  /// spawn 좌표는 늘 자리 Waypoint 에서 나오므로, 지도를 다시 읽었을 때 이름은
  /// 그대로 두고 좌표만 다시 계산해 넣는다.
  RmfProjectRobot withSpawn({
    required double? spawnX,
    required double? spawnY,
    double? spawnHeading,
  }) => RmfProjectRobot(
    robotId: robotId,
    displayName: displayName,
    model: model,
    gzName: gzName,
    zones: zones,
    kind: kind,
    dataSource: dataSource,
    chargerWaypoint: chargerWaypoint,
    spawnX: spawnX,
    spawnY: spawnY,
    spawnHeading: spawnHeading ?? this.spawnHeading,
    rosDomainId: rosDomainId,
    ssh: ssh,
    driveMode: driveMode,
    allowReversing: allowReversing,
  );

  /// 설 자리만 바꾼 사본. 좌표는 비운다.
  ///
  /// 자리가 바뀌면 옛 좌표는 거짓이다. 남겨 두면 등록에는 새 자리 이름이
  /// 적혀 있는데 좌표는 옛 자리인 상태가 되고, 산출물에 나가는 것은 좌표다 —
  /// 팔은 옛 자리에 서고 핑키만 새 자리로 간다. 좌표는 지도에서 다시 넣는다
  /// ([robotsWithMapSpawnPoints]).
  RmfProjectRobot withStation(String? station) => RmfProjectRobot(
    robotId: robotId,
    displayName: displayName,
    model: model,
    gzName: gzName,
    zones: zones,
    kind: kind,
    dataSource: dataSource,
    chargerWaypoint: station,
    spawnX: null,
    spawnY: null,
    spawnHeading: spawnHeading,
    rosDomainId: rosDomainId,
    ssh: ssh,
    driveMode: driveMode,
    allowReversing: allowReversing,
  );

  /// 주행 모드만 바꾼 사본.
  RmfProjectRobot withDriveMode(RobotDriveMode mode) => RmfProjectRobot(
    robotId: robotId,
    displayName: displayName,
    model: model,
    gzName: gzName,
    zones: zones,
    kind: kind,
    dataSource: dataSource,
    chargerWaypoint: chargerWaypoint,
    spawnX: spawnX,
    spawnY: spawnY,
    spawnHeading: spawnHeading,
    rosDomainId: rosDomainId,
    ssh: ssh,
    driveMode: mode,
    allowReversing: allowReversing,
  );

  bool get isMobile => kind == RmfRobotKind.mobile;

  /// Gazebo 에 올릴 로봇인가. Mock 은 앱 안에만 있고, 실물은 이미 있다.
  bool get runsInGazebo => dataSource == RobotDataSource.gazebo;

  /// Open-RMF 가 관제하는가. Mock 은 앱이 직접 굴리므로 플릿에 넣지 않는다.
  bool get isManagedByRmf => dataSource != RobotDataSource.mock;

  Map<String, Object?> toJson() => {
    'robotId': robotId,
    'displayName': displayName,
    'model': model,
    'kind': kind.storageValue,
    'dataSource': dataSource.name,
    'gzName': gzName,
    'zones': zones,
    'chargerWaypoint': chargerWaypoint,
    'spawnX': spawnX,
    'spawnY': spawnY,
    'spawnHeading': spawnHeading,
    'rosDomainId': rosDomainId,
    'ssh': ssh,
    'driveMode': driveMode.storageValue,
    'allowReversing': allowReversing,
  };

  static RmfProjectRobot fromJson(Map<String, dynamic> data) => RmfProjectRobot(
    robotId: data['robotId'] as String,
    displayName: data['displayName'] as String? ?? data['robotId'] as String,
    model: data['model'] as String? ?? 'PINKY',
    kind: RmfRobotKind.parse(data['kind'] as String?),
    dataSource: RobotDataSource.parse(data['dataSource'] as String?),
    gzName: data['gzName'] as String? ?? data['robotId'] as String,
    zones: [
      for (final zone in (data['zones'] as List<dynamic>? ?? const []))
        zone.toString(),
    ],
    chargerWaypoint: data['chargerWaypoint'] as String?,
    spawnX: (data['spawnX'] as num?)?.toDouble(),
    spawnY: (data['spawnY'] as num?)?.toDouble(),
    spawnHeading: (data['spawnHeading'] as num?)?.toDouble() ?? 0,
    rosDomainId: (data['rosDomainId'] as num?)?.toInt(),
    ssh: (data['ssh'] as Map?)?.cast<String, dynamic>(),
    driveMode: parseRobotDriveMode(data['driveMode'] as String?),
    allowReversing: data['allowReversing'] as bool? ?? false,
  );
}

/// 설치 로봇으로 고를 수 있는 OpenMANIPULATOR 모델과 그 컨트롤러.
///
/// `open_manipulator_description` 의 xacro 가 펼쳐지고 Gazebo 용 컨트롤러 설정이
/// 있는 것만 넣는다. 고를 수 있는데 띄우면 죽는 항목은 없느니만 못하다.
///
/// 뺀 것들:
/// - `omy_f3m` — `realsense2_description` 이 있어야 xacro 가 펼쳐진다
/// - `omx_l`, `omy_l100` — 원격 조종의 leader 쪽이라 설비로 세울 것이 아니다
///
/// 모델마다 컨트롤러가 다르다. `omy_3m` 은 그리퍼가 없어서 있지도 않은
/// `gripper_controller` 를 올리면 spawner 가 기다리다 실패한다.
const Map<String, List<String>> openManipulatorControllers = {
  'open_manipulator_x': [
    'joint_state_broadcaster',
    'arm_controller',
    'gripper_controller',
  ],
  'omx_f': ['joint_state_broadcaster', 'arm_controller', 'gripper_controller'],
  'omy_3m': ['joint_state_broadcaster', 'arm_controller'],
};

/// 설치 로봇으로 고를 수 있는 모델 이름.
List<String> get openManipulatorModels =>
    openManipulatorControllers.keys.toList();

/// 프로젝트의 플릿 설정. Open-RMF fleet adapter 의 `rmf_fleet` 블록과 대응한다.
class RmfFleetSettings {
  const RmfFleetSettings({
    this.fleetName = 'pinky',
    this.linearVelocity = .5,
    this.linearAcceleration = .75,
    this.angularVelocity = .6,
    this.angularAcceleration = 2.0,
    this.footprintRadius = .3,
    this.vicinityRadius = .5,
    this.reversible = false,
    this.batteryVoltage = 12,
    this.batteryCapacity = 24,
    this.chargingCurrent = 5,
    this.mass = 20,
    this.momentOfInertia = 10,
    this.frictionCoefficient = .22,
    this.ambientPower = 20,
    this.toolPower = 0,
    this.rechargeThreshold = .1,
    this.rechargeSoc = 1,
    this.fleetManagerIp = '127.0.0.1',
    this.fleetManagerPort = 22011,
    this.goalToleranceMeters,
    this.manualFootprintRadius,
    this.manualVicinityRadius,
  });

  /// 사람이 직접 넣은 충돌 반경 [m]. null 이면 로봇 폭의 절반으로 계산한다.
  ///
  /// 계산값은 로봇을 원으로 본 어림이다. 적재물이나 범퍼가 튀어나오면 실제
  /// 몸이 그 원보다 크고, RMF 는 그만큼을 모르는 채로 두 로봇을 붙인다.
  /// 재서 넣을 수 있어야 한다.
  final double? manualFootprintRadius;

  /// 사람이 직접 넣은 접근 금지 반경 [m]. null 이면 충돌 반경 + 위치 오차 여유.
  ///
  /// RMF 는 이 원 안에 다른 로봇을 안 들인다. 좁은 통로에서 이 값이 크면 서로
  /// 비켜 주기만 하다 아무도 못 지나가고, 작으면 실제로 닿는다.
  final double? manualVicinityRadius;

  /// Nav2 가 "도착했다" 고 인정하는 반경 [m].
  ///
  /// 비워 두면 맵에서 계산한 값을 쓴다 — [recommendedGoalTolerance].
  /// 벤더 기본값 0.25m 는 사람 다니는 복도를 전제한 것이라, Waypoint 가
  /// 0.33m 간격인 맵에서는 이웃 Waypoint 의 도착 원과 겹친다. 실제로 충전1 로
  /// 돌아오라 했는데 0.246m 어긋난 자리에서 멈추고 도착으로 쳤다.
  final double? goalToleranceMeters;

  final String fleetName;
  final double linearVelocity;
  final double linearAcceleration;
  final double angularVelocity;
  final double angularAcceleration;

  /// 로봇을 원으로 본 반경. 로봇 안전 기준의 폭 절반에서 가져온다.
  final double footprintRadius;

  /// 다른 로봇이 접근하지 않아야 하는 반경. footprint 에 위치 오차 여유를 더한다.
  final double vicinityRadius;
  final bool reversible;
  final double batteryVoltage;
  final double batteryCapacity;
  final double chargingCurrent;
  final double mass;
  final double momentOfInertia;
  final double frictionCoefficient;
  final double ambientPower;
  final double toolPower;
  final double rechargeThreshold;
  final double rechargeSoc;
  final String fleetManagerIp;
  final int fleetManagerPort;

  /// 맵의 로봇 안전 기준에서 프로필 반경을 가져온 설정.
  ///
  /// 사용자가 이미 입력한 값을 다시 묻지 않는다. 두 곳에 따로 적으면 어긋난다.
  ///
  /// 다만 **직접 넣은 값이 있으면 그것이 이긴다.** 로봇을 원으로 보는 계산은
  /// 어림이라, 실제 몸이 원이 아니거나 적재물이 튀어나오면 사람이 재서 넣는
  /// 편이 맞다. 그때 폭을 고쳤다고 넣은 값을 덮어쓰면 안 된다.
  RmfFleetSettings withRobotSafety({
    required double widthMeters,
    required double localizationMarginMeters,
  }) => copyWith(
    footprintRadius: manualFootprintRadius ?? widthMeters / 2,
    vicinityRadius:
        manualVicinityRadius ?? widthMeters / 2 + localizationMarginMeters,
  );

  RmfFleetSettings copyWith({
    String? fleetName,
    double? linearVelocity,
    double? linearAcceleration,
    double? angularVelocity,
    double? angularAcceleration,
    double? footprintRadius,
    double? vicinityRadius,
    double? goalToleranceMeters,
    bool clearGoalTolerance = false,
    double? manualFootprintRadius,
    double? manualVicinityRadius,
    bool clearManualProfile = false,
  }) => RmfFleetSettings(
    goalToleranceMeters: clearGoalTolerance
        ? null
        : goalToleranceMeters ?? this.goalToleranceMeters,
    manualFootprintRadius: clearManualProfile
        ? null
        : manualFootprintRadius ?? this.manualFootprintRadius,
    manualVicinityRadius: clearManualProfile
        ? null
        : manualVicinityRadius ?? this.manualVicinityRadius,
    fleetName: fleetName ?? this.fleetName,
    linearVelocity: linearVelocity ?? this.linearVelocity,
    linearAcceleration: linearAcceleration ?? this.linearAcceleration,
    angularVelocity: angularVelocity ?? this.angularVelocity,
    angularAcceleration: angularAcceleration ?? this.angularAcceleration,
    footprintRadius: footprintRadius ?? this.footprintRadius,
    vicinityRadius: vicinityRadius ?? this.vicinityRadius,
    reversible: reversible,
    batteryVoltage: batteryVoltage,
    batteryCapacity: batteryCapacity,
    chargingCurrent: chargingCurrent,
    mass: mass,
    momentOfInertia: momentOfInertia,
    frictionCoefficient: frictionCoefficient,
    ambientPower: ambientPower,
    toolPower: toolPower,
    rechargeThreshold: rechargeThreshold,
    rechargeSoc: rechargeSoc,
    fleetManagerIp: fleetManagerIp,
    fleetManagerPort: fleetManagerPort,
  );

  Map<String, Object?> toJson() => {
    'fleetName': fleetName,
    'linearVelocity': linearVelocity,
    'linearAcceleration': linearAcceleration,
    'angularVelocity': angularVelocity,
    'angularAcceleration': angularAcceleration,
    'footprintRadius': footprintRadius,
    'vicinityRadius': vicinityRadius,
    'reversible': reversible,
    'batteryVoltage': batteryVoltage,
    'batteryCapacity': batteryCapacity,
    'chargingCurrent': chargingCurrent,
    'mass': mass,
    'momentOfInertia': momentOfInertia,
    'frictionCoefficient': frictionCoefficient,
    'ambientPower': ambientPower,
    'toolPower': toolPower,
    'rechargeThreshold': rechargeThreshold,
    'rechargeSoc': rechargeSoc,
    'fleetManagerIp': fleetManagerIp,
    'fleetManagerPort': fleetManagerPort,
    'goalToleranceMeters': goalToleranceMeters,
    // 비어 있으면 로봇 폭에서 계산한다는 뜻이다. 계산값을 적어 두면 나중에
    // 폭을 고쳐도 옛 값이 남아, 왜 안 따라오는지 알 수 없다.
    'manualFootprintRadius': manualFootprintRadius,
    'manualVicinityRadius': manualVicinityRadius,
  };

  static RmfFleetSettings fromJson(Map<String, dynamic> d) {
    double num_(String key, double fallback) =>
        (d[key] as num?)?.toDouble() ?? fallback;
    const base = RmfFleetSettings();
    return RmfFleetSettings(
      fleetName: d['fleetName'] as String? ?? base.fleetName,
      linearVelocity: num_('linearVelocity', base.linearVelocity),
      linearAcceleration: num_('linearAcceleration', base.linearAcceleration),
      angularVelocity: num_('angularVelocity', base.angularVelocity),
      angularAcceleration: num_(
        'angularAcceleration',
        base.angularAcceleration,
      ),
      footprintRadius: num_('footprintRadius', base.footprintRadius),
      vicinityRadius: num_('vicinityRadius', base.vicinityRadius),
      reversible: d['reversible'] as bool? ?? base.reversible,
      batteryVoltage: num_('batteryVoltage', base.batteryVoltage),
      batteryCapacity: num_('batteryCapacity', base.batteryCapacity),
      chargingCurrent: num_('chargingCurrent', base.chargingCurrent),
      mass: num_('mass', base.mass),
      momentOfInertia: num_('momentOfInertia', base.momentOfInertia),
      frictionCoefficient: num_(
        'frictionCoefficient',
        base.frictionCoefficient,
      ),
      ambientPower: num_('ambientPower', base.ambientPower),
      toolPower: num_('toolPower', base.toolPower),
      rechargeThreshold: num_('rechargeThreshold', base.rechargeThreshold),
      rechargeSoc: num_('rechargeSoc', base.rechargeSoc),
      fleetManagerIp: d['fleetManagerIp'] as String? ?? base.fleetManagerIp,
      fleetManagerPort:
          (d['fleetManagerPort'] as num?)?.toInt() ?? base.fleetManagerPort,
      goalToleranceMeters: (d['goalToleranceMeters'] as num?)?.toDouble(),
      manualFootprintRadius: (d['manualFootprintRadius'] as num?)?.toDouble(),
      manualVicinityRadius: (d['manualVicinityRadius'] as num?)?.toDouble(),
    );
  }
}

String _n(double value) => value.toStringAsFixed(3);

/// 임의의 프로젝트 이름을 유효한 ROS 2 node 이름으로 바꾼다.
/// 파일 이름에는 `-`가 허용되지만 node 이름에는 허용되지 않는다.
String _rosNodeName(String value) {
  var sanitized = value.replaceAll(RegExp(r'[^A-Za-z0-9_]'), '_');
  if (sanitized.isEmpty) return 'robosapiens_node';
  if (RegExp(r'^[0-9]').hasMatch(sanitized)) sanitized = 'n_$sanitized';
  return sanitized;
}

/// Open-RMF fleet adapter 설정(`<fleet>_config.yaml`).
///
/// `rmf_demos` 의 tinyRobot_config.yaml 과 같은 구조다. 이것이 없어서 지금까지
/// office 데모 설정을 빌려 썼고, 로봇 이름·속도·배터리가 전부 맞지 않았다.
String buildFleetAdapterYaml({
  required RmfFleetSettings fleet,
  required List<RmfProjectRobot> robots,
  required String mapName,
}) {
  final buffer = StringBuffer()
    ..writeln('# $mapName 프로젝트의 Open-RMF fleet adapter 설정.')
    ..writeln('# rmf_control_ui 가 맵 프로젝트에서 생성했다. 손으로 고치면')
    ..writeln('# 다음 저장 때 덮어써진다.')
    ..writeln('rmf_fleet:')
    ..writeln('  name: "${fleet.fleetName}"')
    ..writeln('  limits:')
    ..writeln(
      '    linear: [${_n(fleet.linearVelocity)}, '
      '${_n(fleet.linearAcceleration)}] # velocity, acceleration',
    )
    ..writeln(
      '    angular: [${_n(fleet.angularVelocity)}, '
      '${_n(fleet.angularAcceleration)}]',
    )
    ..writeln('  profile: # 로봇을 원으로 본 반경. 맵의 로봇 안전 기준에서 가져왔다.')
    ..writeln('    footprint: ${_n(fleet.footprintRadius)}')
    ..writeln('    vicinity: ${_n(fleet.vicinityRadius)}')
    // Pinky의 Nav2 RPP는 allow_reversing=false다. RMF만 후진 가능으로 두면
    // 대기점에서 반대 방향 자세를 목표로 준 뒤 Nav2가 다시 전진 방향으로
    // 돌리는 왕복 회전이 생긴다. 두 계층을 전진 전용으로 맞춘다.
    ..writeln('  reversible: False')
    ..writeln('  battery_system:')
    ..writeln('    voltage: ${_n(fleet.batteryVoltage)}')
    ..writeln('    capacity: ${_n(fleet.batteryCapacity)}')
    ..writeln('    charging_current: ${_n(fleet.chargingCurrent)}')
    ..writeln('  mechanical_system:')
    ..writeln('    mass: ${_n(fleet.mass)}')
    ..writeln('    moment_of_inertia: ${_n(fleet.momentOfInertia)}')
    ..writeln('    friction_coefficient: ${_n(fleet.frictionCoefficient)}')
    ..writeln('  ambient_system:')
    ..writeln('    power: ${_n(fleet.ambientPower)}')
    ..writeln('  tool_system:')
    ..writeln('    power: ${_n(fleet.toolPower)}')
    ..writeln('  recharge_threshold: ${_n(fleet.rechargeThreshold)}')
    ..writeln('  recharge_soc: ${_n(fleet.rechargeSoc)}')
    ..writeln('  publish_fleet_state: 10.0')
    ..writeln('  account_for_battery_drain: True')
    ..writeln('  task_capabilities:')
    ..writeln('    loop: True')
    ..writeln('    delivery: True')
    // 이 플릿이 맡을 수 있는 별도 동작. 여기 없는 것을 작업에 넣으면 RMF 가
    // `Fleet not configured to perform this action` 이라며 통째로 거절한다.
    // `armLoad` 는 앱의 연속 작업에 있는 매니퓰레이터 적재 단계다.
    ..writeln('  actions: ["teleop", "$rmfArmLoadAction"]')
    // Jazzy easy_full_control은 시작 위치가 주차 지점과 같을 때 자동 park를
    // 즉시 완료하는 경로에서 SIGSEGV가 발생할 수 있다.
    ..writeln('  finishing_request: "nothing"')
    // 대기점 도착 뒤 별도 responsive-wait 자세를 만들지 않는다. 작업의 다음
    // 목적지가 정해졌다면 그 경로를 바로 넘겨 불필요한 대기 회전을 막는다.
    ..writeln('  responsive_wait: False')
    ..writeln('  reassign_task_interval: 120')
    ..writeln('  robots:');
  // 플릿은 돌아다니는 로봇의 모임이다. 한자리에 붙은 설치 로봇을 여기 넣으면
  // fleet adapter 가 배차 대상으로 보고 갈 수 없는 곳으로 보내려 한다.
  // Open-RMF 에서 그런 것은 플릿이 아니라 workcell 로 다룬다.
  //
  // Mock 로봇도 넣지 않는다. 앱이 제 안에서 굴리는 것이라 실제로는 없다.
  // 넣으면 fleet adapter 가 오지 않을 로봇의 상태를 계속 기다린다.
  final mobile = [
    for (final robot in robots)
      if (robot.isMobile && robot.isManagedByRmf) robot,
  ];
  if (mobile.isEmpty) {
    buffer.writeln('    {} # 관제 대상 이동 로봇이 없다.');
  } else {
    for (final robot in mobile) {
      buffer
        ..writeln('    ${robot.robotId}:')
        ..writeln('        charger: "${robot.chargerWaypoint ?? ''}"');
    }
  }
  final workcells = [
    for (final robot in robots)
      if (!robot.isMobile && robot.isManagedByRmf) robot,
  ];
  if (workcells.isNotEmpty) {
    buffer
      ..writeln('')
      ..writeln('# 설치 로봇은 플릿에 넣지 않는다. 배차 대상이 아니다.')
      ..writeln('# 이 프로젝트의 설치 로봇:');
    for (final robot in workcells) {
      buffer.writeln(
        '#   ${robot.robotId} · ${robot.displayName} '
        '(${robot.model}) @ ${robot.chargerWaypoint ?? '자리 미지정'}',
      );
    }
  }
  final appOnly = [
    for (final robot in robots)
      if (!robot.isManagedByRmf) robot,
  ];
  if (appOnly.isNotEmpty) {
    buffer
      ..writeln('')
      ..writeln('# 앱 Mock 로봇은 플릿에 넣지 않는다. 실제로는 없는 로봇이다.')
      ..writeln('# 이 프로젝트의 Mock 로봇:');
    for (final robot in appOnly) {
      buffer.writeln('#   ${robot.robotId} · ${robot.displayName}');
    }
  }
  buffer
    ..writeln('')
    ..writeln('fleet_manager:')
    ..writeln('  ip: "${fleet.fleetManagerIp}"')
    ..writeln('  port: ${fleet.fleetManagerPort}');
  return buffer.toString();
}

/// Gazebo 에 띄울 로봇 목록(`fleet.yaml`).
///
/// spawn 좌표는 맵의 Waypoint 에서 가져온다. 맵이 바뀌면 이 값도 함께 바뀌어야
/// 하므로 프로젝트에 묶어 둔다.
String buildFleetSimYaml({
  required List<RmfProjectRobot> robots,
  required String mapName,
}) {
  final buffer = StringBuffer()
    ..writeln('# $mapName 프로젝트에 띄울 로봇 목록.')
    ..writeln('# rmf_control_ui 가 맵 프로젝트에서 생성했다.')
    ..writeln('#')
    ..writeln('# spawn_x / spawn_y 는 맵 Waypoint 좌표다. zones 는 이 로봇이')
    ..writeln('# 진입 가능한 3온도 구획으로 관제 배차의 입찰 자격이 된다.')
    ..writeln('robots:');
  if (robots.isEmpty) {
    buffer.writeln('  [] # 등록된 로봇이 없다.');
  }
  for (final robot in robots) {
    buffer
      ..writeln('  - id: ${robot.robotId}')
      ..writeln('    name: ${robot.displayName}')
      ..writeln('    kind: ${robot.kind.storageValue} # ${robot.kind.label}')
      ..writeln('    model: ${robot.model}')
      ..writeln('    gz_name: ${robot.gzName}')
      ..writeln('    zones: [${robot.zones.join(', ')}]');
    if (robot.chargerWaypoint != null) {
      buffer.writeln(
        robot.isMobile
            ? '    home_charger: ${robot.chargerWaypoint}'
            : '    station: ${robot.chargerWaypoint}',
      );
    }
    if (robot.spawnX != null && robot.spawnY != null) {
      buffer
        ..writeln('    spawn_x: ${_n(robot.spawnX!)}')
        ..writeln('    spawn_y: ${_n(robot.spawnY!)}');
    }
    buffer.writeln('    spawn_heading: ${_n(robot.spawnHeading)}');
  }
  return buffer.toString();
}

/// 프로젝트를 통째로 띄우는 launch 파일.
///
/// RMF core(schedule·blockade·building map server·supervisor·dispatcher)와 이
/// 프로젝트의 fleet adapter 를 함께 띄운다. 경로는 전부 이 프로젝트 것으로
/// 박아 둔다 — 맵마다 building.yaml 도 nav graph 도 플릿 설정도 다르다.
///
/// [mapDirectory] 는 배포 산출물이 있는 곳(`rmf_maps/<맵이름>`)이다. 설정
/// 파일도 같은 곳에 내보내므로 한 디렉터리만 가리키면 된다.
/// 이 프로젝트를 Nav2 가 모는가.
///
/// `rmf_demos_fleet_adapter` 는 slotcar 전용이다. 그것은 Gazebo 안의 slotcar
/// 플러그인에게 직접 명령하고, 우리 핑키에게는 상대가 없다. 토픽을 쓰는 이동
/// 로봇이 하나라도 있으면 그것 대신 이 프로젝트의 nav2 어댑터를 띄워야 한다.
bool projectUsesNav2(List<RmfProjectRobot> robots) =>
    robots.any((robot) => robot.isMobile && robot.dataSource.usesTopics);

/// Nav2 가 몰 이동 로봇. Gazebo 든 실물이든 **위쪽은 똑같다.**
///
/// 아래에서 Gazebo 를 몰든 진짜 모터를 몰든 `/<로봇>/odom` · `/scan` · `/cmd_vel`
/// 이라는 같은 이름으로 같은 형식을 주고받는다. 그래서 Nav2 도 어댑터도 가릴
/// 이유가 없다.
///
/// 예전에는 이 자리가 `runsInGazebo` 였다. 실물 로봇의 출처를 바꾸는 순간
/// Nav2 도, 어댑터 매핑도, 로봇별 `nav2_params.yaml` 도 통째로 안 만들어졌다 —
/// **그런데 플릿 설정에는 그대로 들어갔다.** RMF 는 로봇을 아는데 그 로봇을
/// 모는 것이 하나도 없는 상태가 되고, 오류는 한 줄도 안 났다.
List<RmfProjectRobot> navigatingRobots(List<RmfProjectRobot> robots) => [
  for (final robot in robots)
    if (robot.isMobile && robot.dataSource.usesTopics) robot,
];

/// RMF·Nav2·어댑터가 시뮬레이터 시계(`/clock`)를 써야 하는가.
///
/// **실물 이동 로봇이 하나라도 있으면 벽시계로 통일한다.** 실물의 `odom` ·
/// `scan` · `tf` 는 벽시계로 찍혀 온다. 그 위의 AMCL 과 어댑터가 sim 시계를
/// 보면 TF lookup 이 전부 어긋나는데, **오류는 안 나고** 로봇만 안 움직인다.
///
/// Gazebo 를 함께 돌려도 된다. 시뮬레이터는 제 안에서만 sim 시계를 쓰고
/// (`spawn.launch.xml` 의 `use_sim_time=True`), 바깥과는 워크셀 노드를 통해
/// 만나는데 그쪽은 애초에 벽시계로 돌며 TF 를 안 쓴다. 팔에 보내는 궤적도
/// `time_from_start` 라는 **상대 시간**이라 어느 시계에서도 같게 돈다.
bool projectUsesSimTime(List<RmfProjectRobot> robots) => !robots.any(
  (robot) => robot.isMobile && robot.dataSource == RobotDataSource.real,
);

String buildProjectLaunchXml({
  required String mapName,
  required String fleetName,
  required String mapDirectory,
  required String buildingYamlName,
  List<RmfProjectRobot> robots = const [],
  bool useSimTime = true,
  // rmf-web 을 안 띄우면 비운다. 주소를 넘기면 RMF 가 1초마다 영원히 다시
  // 붙으려 하고, 그 여덟 줄이 로그를 채워 정작 볼 것을 덮는다.
  String? serverUri,
  // RViz 가 nav graph 를 그리는 굵기. 맵 크기에 견줘 정한다 — 자세한 것은
  // [navGraphLaneWidth].
  double laneWidth = defaultNavGraphLaneWidth,
  // Waypoint 원과 이름표를 Lane 굵기의 몇 배로 그릴까. 상류 기본값은 1.3·0.7
  // 인데, 작은 도면에서는 Waypoint 원끼리 겹쳐서 1.0·0.6 으로 줄였다.
  double waypointScale = 1.0,
  double textScale = .6,
  // RViz 가 로봇을 그릴 공 반지름(m). 플릿의 footprint 를 그대로 쓴다.
  //
  // 이것을 안 넘기면 상류가 **0.5m 를 쓴다** — 지름 1m 짜리 공이다. 2.3m 짜리
  // 도면에서는 건물 절반을 덮는 자홍색 덩어리가 되어 로봇인지도 모른다.
  double footprintRadius = .3,
}) {
  final usesNav2 = projectUsesNav2(robots);
  final buffer = StringBuffer()
    ..writeln("<?xml version='1.0' ?>")
    ..writeln('<!--')
    ..writeln('  $mapName 프로젝트 실행 launch.')
    ..writeln('  rmf_control_ui 가 맵 프로젝트에서 생성했다. 손으로 고치면')
    ..writeln('  다음 저장 때 덮어써진다.')
    ..writeln('')
    ..writeln('  실행:')
    ..writeln('    source /opt/ros/jazzy/setup.bash')
    ..writeln('    source <robosapiens>/rmf_ws/install/setup.bash')
    ..writeln('    ros2 launch $mapDirectory/$mapName.launch.xml')
    ..writeln('-->')
    ..writeln('<launch>')
    ..writeln('  <arg name="use_sim_time" default="$useSimTime"/>')
    ..writeln('  <arg name="headless" default="true"/>')
    ..writeln(
      serverUri == null || serverUri.isEmpty
          ? '  <!-- rmf-web 을 안 씁니다. 주소를 넘기면 dispatcher 가 1초마다\n'
                '       영원히 다시 붙으려 하고, 그 여덟 줄이 로그를 채웁니다.\n'
                '       띄우실 때 server_uri 를 넣으세요. -->\n'
                '  <arg name="server_uri" default=""/>'
          : '  <arg name="server_uri" default="$serverUri"/>',
    )
    ..writeln('  <arg name="map_dir" default="$mapDirectory"/>')
    ..writeln('')
    ..writeln('  <!--')
    ..writeln('    RMF core. 이것이 먼저 떠야 fleet adapter 가 붙는다.')
    ..writeln('')
    ..writeln('    rmf_demos 의 common.launch.xml 을 `include` 하지 않고 같은')
    ..writeln('    내용을 여기 편다. 그 파일이 시각화에 Lane 굵기·글자 크기를')
    ..writeln('    넘기지 않기 때문이다 — 인자로도, set_parameter 로도 밖에서')
    ..writeln('    못 바꾼다(launch_ros 는 노드에 직접 준 param 이 이기게 한다).')
    ..writeln('    기본값 0.5m 는 창고용이라, 2~3m 짜리 도면에서는 Lane 하나가')
    ..writeln('    건물 폭의 1/5 이 되어 스무 개가 서로 겹쳐 덩어리로 보였다.')
    ..writeln('')
    ..writeln('    RMF 가 올라가면 이 부분을 그쪽과 맞춰야 한다. 원본:')
    ..writeln('    \$(find-pkg-share rmf_demos)/common.launch.xml')
    ..writeln('  -->')
    ..writeln('  <arg name="initial_map" default="L1"/>')
    ..writeln('  <arg name="lane_width" default="${_n(laneWidth)}"/>')
    ..writeln('  <arg name="waypoint_scale" default="${_n(waypointScale)}"/>')
    ..writeln('  <arg name="text_scale" default="${_n(textScale)}"/>')
    ..writeln('')
    ..writeln('  <node pkg="rmf_traffic_ros2" exec="rmf_traffic_schedule"')
    ..writeln('        name="rmf_traffic_schedule_primary" output="both">')
    ..writeln('    <param name="use_sim_time" value="\$(var use_sim_time)"/>')
    ..writeln('  </node>')
    ..writeln('  <node pkg="rmf_traffic_ros2" exec="rmf_traffic_blockade"')
    ..writeln('        output="both">')
    ..writeln('    <param name="use_sim_time" value="\$(var use_sim_time)"/>')
    ..writeln('  </node>')
    ..writeln('  <node pkg="rmf_building_map_tools" exec="building_map_server"')
    ..writeln('        args="\$(var map_dir)/$buildingYamlName">')
    ..writeln('    <param name="use_sim_time" value="\$(var use_sim_time)"/>')
    ..writeln('  </node>')
    ..writeln('')
    ..writeln('  <!-- 지도·nav graph·로봇을 마커로 내는 시각화 노드들.')
    ..writeln('')
    ..writeln('       <group> 으로 감싸야 한다. XML launch 의 <include> 는')
    ..writeln('       스스로 범위를 만들지 않아서, 여기 준 <arg> 가 바깥으로')
    ..writeln('       샌다. 안 감쌌더니 아래 headless 가 true 로 덮여 RViz 가')
    ..writeln('       아예 안 떴다 — 오류는 한 줄도 안 났다. -->')
    ..writeln('  <group>')
    // 로봇을 그릴 공의 크기.
    //
    // fleet_states_visualizer 는 로봇을 지름 `2 × <플릿이름>_radius` 짜리
    // SPHERE 로 그린다. 그 값을 **플릿 설정에서 읽지 않는다.** 상류 launch 가
    // rmf_demos 플릿 다섯 개(tinyRobot 0.3 · deliveryRobot 0.6 · caddy 1.5 …)
    // 만 적어 두었고, 목록에 없는 이름은 노드 기본값 0.5m 가 된다.
    //
    // 그래서 지름 1m 짜리 자홍색 공이 나왔다. 2.3m 짜리 도면에서 건물 절반을
    // 덮어 로봇인지 알아볼 수도 없었다. 실제 핑키는 footprint 0.1m 다.
    //
    // <param> 은 남의 launch 안에 있는 노드에 못 붙인다. <set_parameter> 로
    // 이 <group> 안의 모든 노드에 건다 — 이름이 플릿 전용이라 나머지 노드는
    // 선언하지 않고 그냥 지나친다.
    ..writeln('    <set_parameter name="${fleetName}_radius"')
    ..writeln('                   value="${_n(footprintRadius)}"/>');
  // 로봇을 그리는 색. 라이다 점과 같은 색을 줘야 화면에서 공과 점이 한 로봇의
  // 것으로 읽힌다. 상류는 모든 로봇을 자홍으로 칠했다 — 두 대가 같은 복도에
  // 있으면 어느 공이 누구인지 알 수 없었다.
  //
  // `<로봇이름>_color` 는 우리가 fleet_states_visualizer 에 추가한 것이다.
  // 이 파라미터를 모르는 예전 빌드에서는 그냥 무시되고 자홍으로 남는다.
  final painted = navigatingRobots(robots);
  for (var i = 0; i < painted.length; i++) {
    final color = robotColorFor(i);
    buffer
      ..writeln('    <set_parameter name="${painted[i].robotId}_color"')
      ..writeln('                   value="${color.launchList}"/>');
  }
  buffer
    ..writeln(
      '    <include file="\$(find-pkg-share rmf_visualization)'
      '/visualization.launch.xml">',
    )
    ..writeln('      <arg name="use_sim_time" value="\$(var use_sim_time)"/>')
    ..writeln('      <arg name="map_name" value="\$(var initial_map)"/>')
    ..writeln('      <arg name="lane_width" value="\$(var lane_width)"/>')
    ..writeln(
      '      <arg name="waypoint_scale" value="\$(var waypoint_scale)"/>',
    )
    ..writeln('      <arg name="text_scale" value="\$(var text_scale)"/>')
    // 이 include 안의 rviz2 는 띄우지 않는다. 그 설정(rmf.rviz)은 office 데모를
    // 보게 맞춰져 있어 우리 도면이 화면 밖이고, 바닥 그림 토픽 이름도 어긋나
    // 있다 — 그래서 창은 뜨는데 까맣다. 아래에서 우리 설정으로 띄운다.
    ..writeln('      <arg name="headless" value="true"/>')
    ..writeln('    </include>')
    ..writeln('  </group>')
    ..writeln('')
    ..writeln('  <node pkg="rmf_fleet_adapter" exec="door_supervisor">')
    ..writeln('    <param name="use_sim_time" value="\$(var use_sim_time)"/>')
    ..writeln('  </node>')
    ..writeln('  <node pkg="rmf_fleet_adapter" exec="lift_supervisor">')
    ..writeln('    <param name="use_sim_time" value="\$(var use_sim_time)"/>')
    ..writeln('  </node>')
    ..writeln('  <node pkg="rmf_fleet_adapter" exec="mutex_group_supervisor"/>')
    ..writeln('  <node pkg="rmf_task_ros2" exec="rmf_task_dispatcher"')
    ..writeln('        output="screen">')
    ..writeln('    <param name="use_sim_time" value="\$(var use_sim_time)"/>')
    ..writeln('    <param name="bidding_time_window" value="2.0"/>')
    ..writeln('    <param name="use_unique_hex_string_with_task_id"')
    ..writeln('           value="true"/>')
    ..writeln('    <param name="server_uri" value="\$(var server_uri)"/>')
    ..writeln('  </node>')
    ..writeln('')
    ..writeln('  <!--')
    ..writeln('    이 맵을 볼 RViz.')
    ..writeln('')
    ..writeln('    설정은 이 프로젝트의 $mapName.rviz 다 — 카메라가 이 도면을')
    ..writeln('    보고, 바닥 그림은 /floorplan 에서 받는다.')
    ..writeln('')
    ..writeln('    use_sim_time 을 반드시 넘긴다. Gazebo 시간으로 찍힌 라이다와')
    ..writeln('    TF 를 벽시계로 보면 시각이 안 맞아 아무것도 안 그려진다.')
    ..writeln('  -->')
    ..writeln('  <group unless="\$(var headless)">')
    ..writeln('    <node pkg="rviz2" exec="rviz2" name="rviz2" output="both"')
    ..writeln('          args="-d \$(var map_dir)/$mapName.rviz">')
    ..writeln('      <param name="use_sim_time" value="\$(var use_sim_time)"/>')
    ..writeln('    </node>')
    ..writeln('  </group>')
    ..writeln('');
  if (usesNav2) {
    buffer
      ..writeln('  <!--')
      ..writeln('    이 프로젝트의 플릿은 여기 없다.')
      ..writeln('')
      ..writeln('    rmf_demos_fleet_adapter 는 slotcar 전용이다. Gazebo 안의')
      ..writeln('    slotcar 플러그인에게 직접 명령하는 것이라, 토픽으로 도는')
      ..writeln('    우리 핑키에게는 상대가 없다. 붙여 놓으면 설정에')
      ..writeln('    user·password 가 없다며 죽고, 죽은 줄 모르면 배차만')
      ..writeln('    하고 로봇은 가만히 있는다.')
      ..writeln('')
      ..writeln('    플릿은 ${mapName}_nav2.launch.xml 이 띄운다. 거기에')
      ..writeln('    Nav2 와 ${mapName}_nav2_adapter.py 가 함께 있다.')
      ..writeln('    실행 스크립트가 이 launch 다음에 그것을 띄운다 —')
      ..writeln('    RMF core 가 먼저 떠야 어댑터가 schedule node 를 찾는다.')
      ..writeln('  -->')
      ..writeln('</launch>');
    return buffer.toString();
  }
  buffer
    ..writeln('  <!-- 이 프로젝트의 플릿. 설정과 nav graph 모두 이 맵의 것이다.')
    ..writeln('       <group> 으로 감싼다 — include 의 <arg> 는 감싸지 않으면')
    ..writeln('       바깥으로 샌다. -->')
    ..writeln('  <group>')
    ..writeln(
      '    <include file="\$(find-pkg-share rmf_demos_fleet_adapter)'
      '/launch/fleet_adapter.launch.xml">',
    )
    ..writeln('      <arg name="use_sim_time" value="\$(var use_sim_time)"/>')
    ..writeln(
      '      <arg name="config_file" value="\$(var map_dir)'
      '/${fleetName}_config.yaml"/>',
    )
    ..writeln(
      '      <arg name="nav_graph_file" '
      'value="\$(var map_dir)/nav_graphs/0.yaml"/>',
    )
    ..writeln('      <arg name="server_uri" value="\$(var server_uri)"/>')
    ..writeln('    </include>')
    ..writeln('  </group>')
    ..writeln('</launch>');
  return buffer.toString();
}

/// Gazebo 와 ROS 사이의 토픽 다리 설정.
///
/// 벤더의 `pinky_bridge.yaml` 은 이름이 상대 경로(`odom`, `cmd_vel`)라서 로봇이
/// 하나일 때만 맞는다. 여러 대를 띄우면 전부 같은 `/odom` 으로 겹친다.
///
/// 그래서 프로젝트마다 **양쪽 다 절대 이름**으로 새로 만든다. 네임스페이스
/// 해석 규칙에 기대지 않으므로 어긋날 여지가 없다.
///
/// `clock` 과 `tf` 는 월드에 하나뿐이라 로봇별로 나누지 않는다. 프레임 이름은
/// `frame_prefix` 로 이미 갈라져 있어 `/tf` 를 함께 써도 섞이지 않는다.
String buildProjectGzBridgeYaml({
  required String mapName,
  required List<RmfProjectRobot> robots,
  bool includeGlobal = true,
}) {
  void entry(
    StringBuffer out, {
    required String ros,
    required String gz,
    required String rosType,
    required String gzType,
    required String direction,
  }) {
    out
      ..writeln('- ros_topic_name: "$ros"')
      ..writeln('  gz_topic_name: "$gz"')
      ..writeln('  ros_type_name: "$rosType"')
      ..writeln('  gz_type_name: "$gzType"')
      ..writeln('  direction: $direction')
      ..writeln();
  }

  final buffer = StringBuffer()
    ..writeln('# $mapName 프로젝트의 ros_gz_bridge 설정.')
    ..writeln('# rmf_control_ui 가 맵 프로젝트에서 생성했다.')
    ..writeln('#')
    ..writeln('# 이름을 양쪽 다 절대 경로로 적는다. 로봇이 여러 대일 때')
    ..writeln('# 상대 이름을 쓰면 전부 같은 토픽으로 겹친다.')
    ..writeln();
  if (includeGlobal) {
    entry(
      buffer,
      ros: '/clock',
      gz: '/clock',
      rosType: 'rosgraph_msgs/msg/Clock',
      gzType: 'gz.msgs.Clock',
      direction: 'GZ_TO_ROS',
    );
    entry(
      buffer,
      ros: '/tf',
      gz: '/tf',
      rosType: 'tf2_msgs/msg/TFMessage',
      gzType: 'gz.msgs.Pose_V',
      direction: 'GZ_TO_ROS',
    );
  }
  // Gazebo 와 ROS 사이의 다리다. Mock 과 실물은 Gazebo 에 없으므로 놓을 다리도
  // 없다. 넣어 두면 오지 않을 토픽을 기다리는 다리가 조용히 남는다.
  final bridged = [
    for (final robot in robots)
      if (robot.runsInGazebo) robot,
  ];
  if (bridged.isEmpty) {
    buffer.writeln('# Gazebo 로 돌릴 로봇이 없다.');
  }
  for (final robot in bridged) {
    final ns = '/${robot.gzName}';
    buffer.writeln(
      '# ${robot.robotId} · ${robot.displayName} (${robot.kind.label})',
    );
    // 설치 로봇에는 다리를 놓지 않는다.
    //
    // 여기에 `joint_states` 다리를 놓아 두었었는데, 옮길 gz 토픽이 애초에
    // 없었다. 이동 로봇의 URDF 에는 `gz::sim::systems::JointStatePublisher` 가
    // 있어 gz 쪽에 그 이름이 생긴다. OpenMANIPULATOR 의 Gazebo 플러그인은
    // `gz_ros2_control` 하나뿐이라 gz 토픽을 아무것도 내지 않는다.
    //
    // 그 대신 `gz_ros2_control` 이 Gazebo 프로세스 **안에서**
    // controller_manager 를 띄우고 ROS 2 로 직접 말한다 —
    // `joint_state_broadcaster` 가 같은 이름의 ROS 토픽을 내고, 팔은
    // `arm_controller`·`gripper_controller` 의 액션으로 움직인다. 다리를
    // 거치지 않는다.
    //
    // 그래서 다리를 놓으면 값은 영영 오지 않으면서 같은 토픽에 발행자만 둘이
    // 된다 — 조용한 다리 하나와 진짜 값을 내는 broadcaster 하나. "다리는
    // 걸려 있는데 값이 안 온다" 로 보이던 것이 이것이다.
    if (!robot.isMobile) {
      buffer
        ..writeln('#   다리 없음. gz_ros2_control 이 ROS 2 로 직접 주고받는다.')
        ..writeln('#   관절 상태: joint_state_broadcaster 가 $ns/joint_states 로 낸다.')
        ..writeln('#   팔 명령: $ns/arm_controller · $ns/gripper_controller 액션.')
        ..writeln();
      continue;
    }
    entry(
      buffer,
      ros: '$ns/odom',
      gz: '$ns/odom',
      rosType: 'nav_msgs/msg/Odometry',
      gzType: 'gz.msgs.Odometry',
      direction: 'GZ_TO_ROS',
    );
    entry(
      buffer,
      // buildNav2Launch 가 controller/behavior 의 원시 출력을 cmd_vel_nav 로,
      // velocity_smoother 의 최종 출력을 cmd_vel 로 리맵한다. 그래서 여기의
      // cmd_vel 은 이미 smoother 를 거친 값이고, 실물 로봇이 구독하는 이름과도
      // 같다. Nav2 기본 이름인 cmd_vel_smoothed 를 적으면 발행자가 없어
      // Gazebo 에 속도가 한 번도 도달하지 않는다.
      ros: '$ns/cmd_vel',
      gz: '$ns/cmd_vel',
      rosType: 'geometry_msgs/msg/Twist',
      gzType: 'gz.msgs.Twist',
      direction: 'ROS_TO_GZ',
    );
    entry(
      buffer,
      ros: '$ns/scan',
      gz: '$ns/scan',
      rosType: 'sensor_msgs/msg/LaserScan',
      gzType: 'gz.msgs.LaserScan',
      direction: 'GZ_TO_ROS',
    );
    entry(
      buffer,
      ros: '$ns/joint_states',
      gz: '$ns/joint_states',
      rosType: 'sensor_msgs/msg/JointState',
      gzType: 'gz.msgs.Model',
      direction: 'GZ_TO_ROS',
    );
    entry(
      buffer,
      // 벤더 xacro 가 정한 이름이다. 양쪽을 같게 두어야 다리가 어긋나지 않는다.
      ros: '$ns/imu_raw',
      gz: '$ns/imu_raw',
      rosType: 'sensor_msgs/msg/Imu',
      gzType: 'gz.msgs.IMU',
      direction: 'GZ_TO_ROS',
    );
  }
  return buffer.toString();
}

/// 로봇마다 제 도메인에 있는 실물 Pinky 를 관제 도메인 하나로 모으는 설정.
///
/// ## 왜 필요한가
///
/// namespace 로 가르려면 `bringup_robot_namespaced.launch.xml` 이 로봇마다
/// 설치되고 빌드돼 있어야 한다. 로봇 쪽 workspace 를 못 고치는 동안에는 두 대
/// 모두 루트 이름(`/cmd_vel` · `/odom` · `/scan`)으로 낸다. 같은 도메인에 두면
/// **두 대가 같은 토픽을 쓴다** — `/cmd_vel` 하나에 둘 다 붙어서, 한 대에게
/// 보낸 명령으로 두 대가 같이 움직인다. 오류는 안 난다.
///
/// `domain_bridge` 는 도메인을 경계로 쓴다. 로봇마다 **다른 도메인**에 그대로
/// 두고(각자 루트 이름을 써도 도메인이 다르니 안 겹친다), 다리가 관제 도메인
/// 으로 옮기면서 이름 앞에 namespace 를 붙인다.
///
/// ```text
/// 도메인 61  /cmd_vel /odom /scan   (pinky_01, 로봇 그대로)
/// 도메인 62  /cmd_vel /odom /scan   (pinky_02, 로봇 그대로)
///                  ↓ domain_bridge
/// 도메인 52  /pinky_01/odom  /pinky_02/odom  ...   (관제)
/// ```
///
/// 로봇 펌웨어도 workspace 도 안 고친다. 로봇이 바꾸는 것은
/// `ROS_DOMAIN_ID` 하나뿐이다.
///
/// ## `/tf` 를 다리로 옮기지 않는다
///
/// `/tf` 는 월드에 하나뿐인 토픽이라 로봇별로 나누지 않는다
/// ([MULTI_ROBOT_NAMESPACES.md] 6절). 그런데 루트 이름을 쓰는 로봇은 `/tf` 안의
/// **프레임 이름**도 `odom → base_footprint` 로 똑같다. 그대로 옮기면 두 대의
/// TF 나무가 관제 도메인에서 한 이름으로 겹쳐, TF 가 두 로봇 사이를 오가며
/// 튄다.
///
/// `domain_bridge` 는 토픽 이름만 바꾸고 **메시지 안은 못 고친다.** 그래서 이
/// 파일은 `/tf` 를 옮기지 않는다. 프레임을 가르는 것은 로봇 쪽
/// `bringup_namespaced.py` 뿐이다 — 그것이 끝나면 이 다리는 필요 없다.
///
/// 이 다리만으로 되는 것과 안 되는 것:
///
/// | | 다리로 되나 |
/// |---|---|
/// | 토픽 이름 분리 (`/pinky_01/odom`) | **된다** |
/// | 명령이 한 대에만 가기 (`cmd_vel`) | **된다** |
/// | 메시지 안 프레임 이름 분리 | **안 된다** — 로봇 쪽을 고쳐야 |
/// | 그래서 Nav2 자율주행 | **안 된다** — TF 가 필요하다 |
///
/// 즉 이것은 namespace 이관까지의 **중간 다리**다. 원격 조종·상태 확인·앱
/// 표시까지는 이걸로 되고, Nav2 는 [PINKY_NAMESPACE_MIGRATION.md] 를 끝내야
/// 한다.
/// ## 왜 로봇마다 파일이 따로인가
///
/// `domain_bridge` 의 `topics:` 는 **토픽 이름이 열쇠(key)** 인 맵이다. 그런데
/// 이관 전 로봇은 두 대 모두 루트 이름 `/odom` 을 쓴다. 한 파일에 모으면
/// 열쇠가 겹쳐서, YAML 을 읽는 순간 **뒤엣것이 앞엣것을 덮어쓴다.**
///
/// ```yaml
/// topics:
///   "/odom": { from_domain: 61 }   # pinky_01 — 사라진다
///   "/odom": { from_domain: 62 }   # pinky_02 만 남는다
/// ```
///
/// 오류가 안 난다. 다리는 멀쩡히 뜨고 한 대만 조용히 빠진다. 그래서 로봇마다
/// 파일과 프로세스를 따로 둔다 — 겹칠 열쇠가 애초에 없다.
///
/// 파일 이름은 `<맵>_domain_bridge_<로봇 namespace>.yaml` 이다.
String buildRobotDomainBridgeYaml({
  required String mapName,
  required RmfProjectRobot robot,
  required int projectDomainId,
}) {
  final from = robot.rosDomainId;
  final ns = robot.gzName;
  final buffer = StringBuffer()
    ..writeln('# ${robot.robotId} · ${robot.displayName} 의 domain_bridge 설정.')
    ..writeln('# rmf_control_ui 가 맵 프로젝트에서 생성했다.')
    ..writeln('#')
    ..writeln('# 이 로봇은 제 도메인에서 루트 이름(/odom · /cmd_vel)을 그대로')
    ..writeln('# 쓴다. 이 다리가 관제 도메인 $projectDomainId 으로 옮기면서')
    ..writeln('# 이름 앞에 $ns 을 붙인다.')
    ..writeln('#')
    ..writeln('#   ros2 run domain_bridge domain_bridge \\')
    ..writeln('#     <맵 디렉터리>/${mapName}_domain_bridge_$ns.yaml')
    ..writeln('#')
    ..writeln('# 로봇마다 파일과 프로세스가 따로다. 한 파일에 모으면 두 대의')
    ..writeln('# 루트 이름이 같은 열쇠로 겹쳐, 뒤엣것이 앞엣것을 덮어쓰고 한')
    ..writeln('# 대가 조용히 빠진다.')
    ..writeln('#')
    ..writeln('# /tf 는 옮기지 않는다. 이름은 바꿀 수 있어도 메시지 안의')
    ..writeln('# 프레임 이름은 못 고쳐서, 두 대의 TF 가 한 이름으로 겹친다.')
    ..writeln('# 그래서 이 다리로는 Nav2 가 안 된다 — namespace 이관이 끝나야')
    ..writeln('# 한다. PINKY_NAMESPACE_MIGRATION.md 를 보라.')
    ..writeln();

  // 로봇이 제 도메인을 안 정했거나 관제와 같으면 다리를 놓을 수 없다. 조용히
  // 빈 파일을 내지 말고 무엇을 고쳐야 하는지 파일에 남긴다.
  if (from == null) {
    buffer
      ..writeln('# 이 로봇의 ROS domain ID 가 비어 있다. 로봇 등록에서')
      ..writeln('# 관제($projectDomainId)와 다른 값을 정해야 다리를 놓는다.')
      ..writeln('topics: {}');
    return buffer.toString();
  }
  if (from == projectDomainId) {
    buffer
      ..writeln('# 로봇 도메인이 관제와 같다($projectDomainId). 옮길 것이 없고,')
      ..writeln('# 다른 로봇과 루트 토픽이 그대로 겹친다. 로봇 등록에서 이')
      ..writeln('# 로봇만 쓰는 도메인을 정한다.')
      ..writeln('topics: {}');
    return buffer.toString();
  }

  buffer.writeln('topics:');
  // 로봇이 내는 것(odom·scan)은 로봇→관제, 명령(cmd_vel)은 관제→로봇이다.
  // 방향을 뒤집으면 다리는 뜨는데 값이 한쪽으로만 안 온다.
  void topic(String leaf, String type, {required bool toRobot}) {
    buffer
      ..writeln('  "${toRobot ? '/$ns/$leaf' : '/$leaf'}":')
      ..writeln('    type: $type')
      ..writeln('    from_domain: ${toRobot ? projectDomainId : from}')
      ..writeln('    to_domain: ${toRobot ? from : projectDomainId}')
      ..writeln('    remap: "${toRobot ? '/$leaf' : '/$ns/$leaf'}"');
  }

  topic('odom', 'nav_msgs/msg/Odometry', toRobot: false);
  topic('scan', 'sensor_msgs/msg/LaserScan', toRobot: false);
  topic('joint_states', 'sensor_msgs/msg/JointState', toRobot: false);
  topic('battery/voltage', 'std_msgs/msg/Float32', toRobot: false);
  topic('battery/percent', 'std_msgs/msg/Float32', toRobot: false);
  // 관제가 내려보내는 유일한 명령이다. 이것만 방향이 반대다.
  topic('cmd_vel', 'geometry_msgs/msg/Twist', toRobot: true);
  return buffer.toString();
}

/// 이 프로젝트에서 도메인 다리를 놓을 로봇들.
///
/// 실물 이동 로봇만이다. Gazebo 는 같은 PC 의 한 도메인에 있고 Mock 은 ROS 를
/// 아예 안 쓴다 — 넣어 두면 오지 않을 토픽을 기다리는 다리가 조용히 남는다.
List<RmfProjectRobot> domainBridgeRobots(List<RmfProjectRobot> robots) => [
  for (final robot in robots)
    if (robot.dataSource == RobotDataSource.real && robot.isMobile) robot,
];

/// 로봇마다 도메인 다리를 하나씩 띄우는 실행 스크립트.
///
/// 다리는 로봇 수만큼 프로세스가 뜬다. 하나가 죽어도 나머지는 살아 있어야 해서
/// 배경으로 띄우고 PID 를 남긴다.
String buildDomainBridgeScript({
  required String mapName,
  required List<RmfProjectRobot> robots,
  required int projectDomainId,
}) {
  final bridged = domainBridgeRobots(robots);
  final buffer = StringBuffer()
    ..writeln('#!/usr/bin/env bash')
    ..writeln('#')
    ..writeln('# $mapName · 실물 로봇 도메인 다리.')
    ..writeln('# rmf_control_ui 가 맵 프로젝트에서 생성했다.')
    ..writeln('#')
    ..writeln('# 로봇마다 다리를 하나씩 띄운다. 로봇은 제 도메인에서 루트')
    ..writeln('# 이름을 그대로 쓰고, 관제 도메인 $projectDomainId 에서만')
    ..writeln('# /<로봇>/odom 처럼 갈라져 보인다.')
    ..writeln('#')
    ..writeln('#   ./${mapName}_domain_bridge.sh          # 띄운다')
    ..writeln('#   ./${mapName}_domain_bridge.sh stop     # 내린다')
    ..writeln()
    // ROS 2 와 colcon 의 setup 스크립트가 미정의 변수를 참조해서, -u 로
    // source 하면 그 자리에서 죽는다.
    ..writeln('set -eo pipefail')
    ..writeln()
    ..writeln('cd "\$(dirname "\$0")"')
    ..writeln('PID_FILE=".${mapName}_domain_bridge.pids"')
    ..writeln()
    ..writeln('stop_bridges() {')
    ..writeln('  [[ -f \$PID_FILE ]] || return 0')
    ..writeln('  while read -r pid; do')
    ..writeln('    [[ -n \$pid ]] && kill "\$pid" 2>/dev/null || true')
    ..writeln('  done < "\$PID_FILE"')
    ..writeln('  rm -f "\$PID_FILE"')
    ..writeln('}')
    ..writeln()
    ..writeln('if [[ \${1:-} == stop ]]; then')
    ..writeln('  stop_bridges')
    ..writeln('  echo "도메인 다리를 내렸습니다."')
    ..writeln('  exit 0')
    ..writeln('fi')
    ..writeln()
    // 두 번 띄우면 같은 토픽에 다리가 둘이 된다. 먼저 내린다.
    ..writeln('stop_bridges')
    ..writeln()
    ..writeln('source /opt/ros/jazzy/setup.bash')
    ..writeln();

  if (bridged.isEmpty) {
    buffer
      ..writeln('echo "실물 이동 로봇이 등록돼 있지 않습니다. 놓을 다리가 없습니다."')
      ..writeln('exit 0');
    return buffer.toString();
  }

  for (final robot in bridged) {
    final ns = robot.gzName;
    final config = '${mapName}_domain_bridge_$ns.yaml';
    buffer.writeln('# ${robot.robotId} · ${robot.displayName}');
    if (robot.rosDomainId == null || robot.rosDomainId == projectDomainId) {
      // 설정 파일이 비어 있으므로 띄워도 아무것도 안 옮긴다. 왜 빠졌는지
      // 화면에 남긴다 — 조용히 넘기면 "다리는 떴는데 값이 안 온다" 가 된다.
      buffer
        ..writeln(
          'echo "  ${robot.robotId}: ROS 도메인이 '
          '${robot.rosDomainId == null ? '비어 있어' : '관제와 같아'} 건너뜁니다."',
        )
        ..writeln();
      continue;
    }
    buffer
      ..writeln(
        'ros2 run domain_bridge domain_bridge "$config" '
        '>> "$mapName.log" 2>&1 &',
      )
      ..writeln('echo \$! >> "\$PID_FILE"')
      ..writeln(
        'echo "  ${robot.robotId}: 도메인 ${robot.rosDomainId} → $projectDomainId"',
      )
      ..writeln();
  }
  buffer.writeln('echo "도메인 다리를 띄웠습니다. 내리려면 stop 을 붙여 실행합니다."');
  return buffer.toString();
}

/// Gazebo 에 이 프로젝트의 월드와 로봇을 올리는 bringup launch.
///
/// 로봇마다 네임스페이스를 나눈다. 그래야 `/pinky_01/odom` 처럼 로봇별 토픽이
/// 갈리고, fleet adapter 가 어느 로봇의 위치인지 구분할 수 있다.
///
/// 네임스페이스는 `upload_robot.launch.py` 의 인자로만 넘긴다. `<group>` 에
/// `push-ros-namespace` 를 함께 걸면 `/pinky_01/pinky_01/...` 로 두 번 겹쳐,
/// `create` 가 기다리는 `robot_description` 이 영영 오지 않는다.
String buildProjectBringupXml({
  required String mapName,
  required List<RmfProjectRobot> robots,
  required String mapDirectory,
}) {
  final buffer = StringBuffer()
    ..writeln("<?xml version='1.0' ?>")
    ..writeln('<!--')
    ..writeln('  $mapName 프로젝트의 Gazebo bringup.')
    ..writeln('  rmf_control_ui 가 맵 프로젝트에서 생성했다.')
    ..writeln('')
    ..writeln('  월드는 배포 산출물을 쓰고, 로봇은 이 프로젝트에 등록된 것만')
    ..writeln('  올린다. 로봇마다 네임스페이스를 나눠 토픽을 구분한다.')
    ..writeln('-->')
    ..writeln('<launch>')
    ..writeln('  <arg name="headless" default="true"/>')
    ..writeln('  <arg name="map_dir" default="$mapDirectory"/>')
    ..writeln('  <arg name="world" default="\$(var map_dir)/$mapName.world"/>')
    ..writeln(
      '  <arg name="bridge_params" '
      'default="\$(var map_dir)/${mapName}_gz_bridge.yaml"/>',
    )
    ..writeln('')
    // 없는 패키지를 가리키면 launch 가 통째로 예외를 내며 멈춘다. 워크셀이
    // 하나도 없는데 open_manipulator 를 찾으면, 그것을 안 쓰는 프로젝트에서도
    // Pinky 까지 못 뜬다.
    ..writeln('  <set_env name="GZ_SIM_RESOURCE_PATH"')
    ..writeln(
      '           value="\$(find-pkg-share pinky_description)/../:'
      '${robots.any((robot) => !robot.isMobile && robot.runsInGazebo) ? '\$(find-pkg-share open_manipulator_description)/../:' : ''}'
      '\$(var map_dir)/generated_models:\$(env HOME)/.gazebo/models"/>',
    )
    ..writeln('')
    // `--headless-rendering` 이 있어야 라이다·카메라가 돈다. gpu_lidar 는 GPU
    // 렌더링으로 거리를 재므로 그릴 자리가 없으면 **아무것도 발행하지 않는다.**
    // 토픽 이름은 보이는데 데이터가 영영 안 오고, 오류도 안 난다. 이것이 없으면
    // AMCL 도 Nav2 도 불가능하다.
    // XML 주석 안에는 붙임표 두 개를 쓸 수 없다. 옵션 이름을 그대로 적으면
    // 파일이 깨져서 bringup 이 통째로 안 뜬다.
    ..writeln('  <!-- 화면이 없는 환경에서는 headless 로 서버만 띄운다.')
    ..writeln('       헤드리스 렌더링이 있어야 라이다·카메라가 돈다.')
    ..writeln('       gpu_lidar 는 GPU 로 거리를 재므로 그릴 자리가 없으면')
    ..writeln('       아무것도 발행하지 않는다. 오류도 나지 않는다. -->')
    // include 의 <arg> 는 <group> 으로 감싸지 않으면 바깥으로 샌다.
    ..writeln('  <group>')
    ..writeln(
      '    <include file="\$(find-pkg-share ros_gz_sim)'
      '/launch/gz_sim.launch.py">',
    )
    ..writeln(
      '      <arg name="gz_args"'
      ' value="-r -s -v2 --headless-rendering \$(var world)"/>',
    )
    ..writeln('      <arg name="on_exit_shutdown" value="true"/>')
    ..writeln('    </include>')
    ..writeln('  </group>')
    ..writeln('  <group unless="\$(var headless)">')
    ..writeln(
      '    <include file="\$(find-pkg-share ros_gz_sim)'
      '/launch/gz_sim.launch.py">',
    )
    ..writeln('      <arg name="gz_args" value="-g -v2"/>')
    ..writeln('    </include>')
    ..writeln('  </group>');
  // Gazebo 로 돌리기로 한 것만 올린다. Mock 은 앱 안에만 있고, 실물은 이미
  // 있으므로 시뮬레이터에 또 띄우면 같은 이름이 두 번 뜬다.
  final spawned = [
    for (final robot in robots)
      if (robot.runsInGazebo) robot,
  ];
  if (spawned.isEmpty) {
    buffer
      ..writeln('')
      ..writeln('  <!-- Gazebo 로 돌릴 로봇이 없다. -->')
      ..writeln('  <!-- 로봇 등록에서 값의 출처를 Gazebo 로 골라야 올라온다. -->');
  }
  // 로봇 하나가 디렉터리 하나다. 여기서는 불러오기만 한다.
  //
  // 로봇마다 설정을 제 자리에 두면 한 대를 빼거나 옮길 때 그 디렉터리만
  // 보면 된다. 이 파일에 다 적어 두면 로봇이 늘수록 어느 줄이 누구 것인지
  // 찾기 어려워진다.
  for (final robot in spawned) {
    buffer
      ..writeln('')
      ..writeln(
        '  <!-- ${robot.robotId} · ${robot.displayName} '
        '· ${robot.kind.label} @ ${robot.chargerWaypoint ?? '자리 미지정'} -->',
      );
    // 자리를 안 고르면 spawn 좌표가 없어 지도 원점(0,0)에 놓인다. 건물 밖일
    // 때가 많고, 그러면 로봇은 올라왔는데 아무 데도 안 보인다. 조용히 넘기지
    // 않고 파일에 적어 둔다.
    if (robot.spawnX == null || robot.spawnY == null) {
      buffer.writeln(
        '  <!-- 주의: 자리를 안 골라 spawn 좌표가 없다. '
        '지도 원점에 놓인다. 로봇 등록에서 '
        '${robot.kind.waypointCategory} Waypoint 를 고르세요. -->',
      );
    }
    buffer.writeln(
      '  <include file="\$(var map_dir)/'
      '${robotDirectoryName(robot)}/spawn.launch.xml"/>',
    );
  }
  buffer
    ..writeln('')
    ..writeln('  <!-- 다리는 하나로 묶는다. 설정에 이름이 절대 경로로 적혀')
    ..writeln('       있어 로봇이 몇 대든 겹치지 않는다. -->')
    ..writeln('  <node pkg="ros_gz_bridge" exec="parameter_bridge"')
    ..writeln('        name="gz_bridge" output="screen"')
    ..writeln(
      '        args="--ros-args -p config_file:=\$(var bridge_params)"/>',
    )
    ..writeln('</launch>');
  return buffer.toString();
}

/// 이 프로젝트의 로봇을 띄우는 데 꼭 있어야 하는 ROS 패키지.
///
/// 없는 것을 launch 가 찾으면 통째로 예외를 내며 멈춘다. 워크셀이 하나도 없는
/// 프로젝트에 open_manipulator 를 요구하면, 그것을 쓰지 않는 사람도 Pinky 를
/// 못 띄운다.
List<String> _requiredPackages(List<RmfProjectRobot> robots) => [
  'rmf_demos',
  'rmf_demos_fleet_adapter',
  // building.yaml 에서 nav_graphs/0.yaml 을 다시 만드는 데 쓴다.
  'rmf_building_map_tools',
  'ros_gz_sim',
  if (robots.any((robot) => robot.runsInGazebo && robot.isMobile)) ...[
    'pinky_description',
    // 벤더 launch 대신 우리가 직접 띄우므로 이 둘이 있어야 한다.
    'robot_state_publisher',
    'joint_state_publisher',
  ],
  if (robots.any((robot) => robot.runsInGazebo && !robot.isMobile))
    'open_manipulator_description',
];

/// Isaac Sim에서 프로젝트 USD stage를 열고 ROS 2 Action Graph를 실행한다.
///
/// USD에는 로봇 articulation과 /clock·odom·scan·joint_states·tf·cmd_vel 그래프가
/// 들어 있어야 한다. 이 실행기는 stage 경로와 GUI/headless 선택을 표준화한다.
String buildIsaacProjectScript({required String mapName}) =>
    '''#!/usr/bin/env python3
import argparse

parser = argparse.ArgumentParser()
parser.add_argument('--stage', required=True)
display = parser.add_mutually_exclusive_group()
display.add_argument('--headless', action='store_true')
display.add_argument('--gui', action='store_true')
args = parser.parse_args()

from isaacsim import SimulationApp

app = SimulationApp({'headless': not args.gui})

import omni.timeline
from isaacsim.core.utils.extensions import enable_extension
from isaacsim.core.utils.stage import open_stage

enable_extension('isaacsim.ros2.bridge')
open_stage(args.stage)
app.update()

import omni.graph.core as og
try:
    og.Controller.edit(
        {'graph_path': '/World/ROS2Clock', 'evaluator_name': 'execution'},
        {
            og.Controller.Keys.CREATE_NODES: [
                ('Tick', 'omni.graph.action.OnPlaybackTick'),
                ('SimTime', 'isaacsim.core.nodes.IsaacReadSimulationTime'),
                ('PublishClock', 'isaacsim.ros2.bridge.ROS2PublishClock'),
            ],
            og.Controller.Keys.CONNECT: [
                ('Tick.outputs:tick', 'PublishClock.inputs:execIn'),
                ('SimTime.outputs:simulationTime', 'PublishClock.inputs:timeStamp'),
            ],
        },
    )
except Exception as error:
    if 'already exists' not in str(error):
        raise
app.update()

timeline = omni.timeline.get_timeline_interface()
timeline.play()
try:
    while app.is_running():
        app.update()
finally:
    timeline.stop()
    app.close()
''';

/// Gazebo가 생성한 건물 OBJ와 로봇 URDF를 Isaac USD stage로 묶는다.
String buildIsaacConversionScript({required String mapName}) =>
    '''#!/usr/bin/env python3
import argparse
import os
import re

parser = argparse.ArgumentParser()
parser.add_argument('--map-dir', required=True)
parser.add_argument('--stage', required=True)
args = parser.parse_args()

from isaacsim import SimulationApp
app = SimulationApp({'headless': True})

from pxr import Gf, Usd, UsdGeom, UsdPhysics
from isaacsim.asset.importer.urdf.impl import URDFImporter, URDFImporterConfig

def safe_name(value):
    return re.sub(r'[^A-Za-z0-9_]', '_', value)

def read_obj(path, stage, prim_path):
    points, counts, indices = [], [], []
    with open(path, encoding='utf-8', errors='replace') as handle:
        for raw in handle:
            line = raw.strip()
            if line.startswith('v '):
                points.append(Gf.Vec3f(*(float(v) for v in line.split()[1:4])))
            elif line.startswith('f '):
                face = [int(v.split('/')[0]) - 1 for v in line.split()[1:]]
                if len(face) >= 3:
                    counts.append(len(face))
                    indices.extend(face)
    if not points or not counts:
        raise RuntimeError(f'OBJ에 형상이 없습니다: {path}')
    mesh = UsdGeom.Mesh.Define(stage, prim_path)
    mesh.CreatePointsAttr(points)
    mesh.CreateFaceVertexCountsAttr(counts)
    mesh.CreateFaceVertexIndicesAttr(indices)
    mesh.CreateSubdivisionSchemeAttr('none')
    UsdPhysics.CollisionAPI.Apply(mesh.GetPrim())

def yaml_value(path, key, default=''):
    pattern = re.compile(r'^' + re.escape(key) + r':\\s*(.*?)\\s*(?:#.*)?\$')
    with open(path, encoding='utf-8') as handle:
        for line in handle:
            match = pattern.match(line)
            if match:
                return match.group(1).strip()
    return default

def ros_packages_for(urdf_path):
    with open(urdf_path, encoding='utf-8') as handle:
        packages = sorted(set(re.findall(r'package://([^/]+)/', handle.read())))
    prefixes = [p for p in os.environ.get('AMENT_PREFIX_PATH', '').split(':') if p]
    resolved = []
    for package in packages:
        for prefix in prefixes:
            path = os.path.join(prefix, 'share', package)
            if os.path.isdir(path):
                resolved.append({'name': package, 'path': path})
                break
        else:
            raise RuntimeError(f'URDF package를 찾지 못했습니다: {package}')
    return resolved

stage_path = os.path.abspath(args.stage)
os.makedirs(os.path.dirname(stage_path), exist_ok=True)
stage = Usd.Stage.CreateNew(stage_path)
world = UsdGeom.Xform.Define(stage, '/World')
stage.SetDefaultPrim(world.GetPrim())
UsdGeom.SetStageUpAxis(stage, UsdGeom.Tokens.z)
UsdGeom.SetStageMetersPerUnit(stage, 1.0)
UsdPhysics.Scene.Define(stage, '/World/PhysicsScene')

mesh_dir = os.path.join(args.map_dir, 'generated_models', '${mapName}_L1', 'meshes')
for name in ('floor_1.obj', 'wall_1.obj'):
    source = os.path.join(mesh_dir, name)
    if not os.path.isfile(source):
        raise RuntimeError(f'Gazebo 건물 메시가 없습니다: {source}')
    read_obj(source, stage, '/World/Environment/' + safe_name(name))

robots_dir = os.path.join(args.map_dir, 'robots')
urdf_dir = os.path.join(args.map_dir, 'isaac', 'robots')
asset_dir = os.path.join(args.map_dir, 'isaac', 'assets')
os.makedirs(asset_dir, exist_ok=True)
if os.path.isdir(urdf_dir):
    for filename in sorted(os.listdir(urdf_dir)):
        if not filename.endswith('.urdf'):
            continue
        robot_id = filename[:-5]
        urdf = os.path.join(urdf_dir, filename)
        config = URDFImporterConfig()
        config.urdf_path = urdf
        config.usd_path = os.path.join(asset_dir, robot_id)
        config.ros_package_paths = ros_packages_for(urdf)
        config.fix_base = False
        config.make_default_prim = True
        output = URDFImporter(config).import_urdf()
        if not output or not os.path.isfile(output):
            raise RuntimeError(f'URDF 변환 실패: {urdf}')
        root = UsdGeom.Xform.Define(stage, '/World/Robots/' + safe_name(robot_id))
        root.GetPrim().GetReferences().AddReference(output)
        meta = os.path.join(robots_dir, robot_id, 'robot.yaml')
        x = float(yaml_value(meta, 'spawn_x', '0') or 0)
        y = float(yaml_value(meta, 'spawn_y', '0') or 0)
        heading = float(yaml_value(meta, 'spawn_heading', '0') or 0)
        transform = UsdGeom.Xformable(root)
        transform.AddTranslateOp().Set(Gf.Vec3d(x, y, 0.0))
        transform.AddRotateZOp().Set(heading * 180.0 / 3.141592653589793)

stage.GetRootLayer().Save()
print(f'Isaac USD 생성 완료: {stage_path}')
app.close()
''';

/// 프로젝트를 통째로 띄우는 셸 스크립트.
///
/// ROS 환경을 읽고 bringup 과 RMF 를 순서대로 띄운다. Gazebo 가 먼저 떠야
/// `/clock` 이 나오고, 그래야 use_sim_time 을 쓰는 RMF 노드가 시간을 맞춘다.
String buildProjectRunScript({
  required String mapName,
  required String mapDirectory,
  List<RmfProjectRobot> robots = const [],
  String rosSetup = '/opt/ros/jazzy/setup.bash',
  String rmfWorkspace = r'$APP_ROOT/rmf_ws',
  String pinkyWorkspace = r'$APP_ROOT/robot_model/pinky_pro',
  String manipulatorWorkspace = r'$APP_ROOT/robot_model/open_manipulator',
  int rosDomainId = defaultRosDomainId,
}) =>
    '''#!/usr/bin/env bash
# $mapName 프로젝트 실행.
# rmf_control_ui 가 맵 프로젝트에서 생성했다. 손으로 고치면 다음 저장 때
# 덮어써진다.
#
# 순서가 중요하다. Gazebo 가 먼저 떠야 /clock 이 나오고, 그래야 use_sim_time 을
# 쓰는 RMF 노드가 시간을 맞춘다. 반대로 하면 RMF 가 시간이 멈춘 줄 알고 멈춰
# 있는다.
set -euo pipefail

# ROS 도메인. 같은 도메인끼리만 서로를 본다.
#
# 이것이 어긋나면 **아무 오류도 안 나면서** 아무것도 안 통한다. 앱이 띄운
# 것과 터미널에서 띄운 것이 서로를 못 보던 일이 그래서 생겼다 — 앱은
# 비대화형 셸로 스크립트를 돌리므로 ~/.bashrc 의 export 를 못 읽는다.
# 그래서 맵 프로젝트가 정한 값을 여기 박아 둔다.
# 어디서 온 값인지 남긴다.
#
# `:-` 는 환경 변수가 이기게 한다 — 터미널에서 한 번만 다른 망에 띄워 보는 길이다.
# 그런데 `~/.bashrc` 에 `export ROS_DOMAIN_ID=22` 가 박혀 있으면 **늘** 이긴다.
# 실제로 도메인을 52 로 고치고 다시 배포해도 백엔드는 계속 22 에서 돌았고, 로봇은
# 52 에 있어 `/tf` 가 하나도 안 왔다. 화면에는 `frame does not exist` 로만 보여서
# 프레임 이름이 틀린 줄 알고 한참을 뒤졌다. 그래서 덮였다는 사실을 여기 적는다.
if [[ -n "\${ROS_DOMAIN_ID:-}" && "\$ROS_DOMAIN_ID" != "$rosDomainId" ]]; then
  ROS_DOMAIN_SOURCE="환경 변수 — 프로젝트 설정 $rosDomainId 을 덮었습니다"
else
  ROS_DOMAIN_SOURCE="프로젝트 설정"
fi
export ROS_DOMAIN_ID="\${ROS_DOMAIN_ID:-$rosDomainId}"

# 고정 peer 없이 같은 서브넷의 DDS 멀티캐스트로만 서로를 찾는다.
unset ROS_STATIC_PEERS ROS_LOCALHOST_ONLY
export ROS_AUTOMATIC_DISCOVERY_RANGE=SUBNET

MAP_DIR="\${MAP_DIR:-$mapDirectory}"
APP_ROOT="\${ROBOSAPIENS_ROOT:-\$(cd "\$MAP_DIR/../.." && pwd)}"
export FASTDDS_BUILTIN_TRANSPORTS=UDPv4
# 관제 PC에서는 Fast DDS 공유메모리 포트가 노드 수만큼 쌓여 adapter가
# SIGSEGV로 죽을 수 있다. 로봇과의 통신도 어차피 UDP이므로 UDP 전용 프로필을
# 기본으로 쓴다. 외부에서 값을 주면 그 선택을 존중한다.
if [[ -z "\${FASTRTPS_DEFAULT_PROFILES_FILE:-}" && \\
      -f "\$APP_ROOT/openrmf/fastdds_pc.xml" ]]; then
  export FASTRTPS_DEFAULT_PROFILES_FILE="\$APP_ROOT/openrmf/fastdds_pc.xml"
fi
ROS_SETUP="\${ROS_SETUP:-$rosSetup}"
RMF_WS="\${RMF_WS:-$rmfWorkspace}"
PINKY_WS="\${PINKY_WS:-$pinkyWorkspace}"
OMX_WS="\${OMX_WS:-$manipulatorWorkspace}"

# 상용 배포 구조는 하나로 고정한다. 환경 변수로 예전 경로를 넘겨 조용히
# 실행하면 개발 PC에서는 되지만 고객 패키지에서는 빠지는 파일이 생긴다.
EXPECTED_RMF_WS="\$APP_ROOT/rmf_ws"
EXPECTED_PINKY_WS="\$APP_ROOT/robot_model/pinky_pro"
EXPECTED_OMX_WS="\$APP_ROOT/robot_model/open_manipulator"
WORKSPACE_ENTRIES=(
  "RMF_WS|\$RMF_WS|\$EXPECTED_RMF_WS"
  "PINKY_WS|\$PINKY_WS|\$EXPECTED_PINKY_WS"
  "OMX_WS|\$OMX_WS|\$EXPECTED_OMX_WS"
)
for entry in "\${WORKSPACE_ENTRIES[@]}"; do
  IFS='|' read -r label actual expected <<< "\$entry"
  if [[ "\$actual" != "\$expected" || -L "\$actual" || ! -d "\$actual" ]]; then
    echo "잘못된 RoboSapiens 파일 구조: \$label=\$actual" >&2
    echo "실제 디렉터리를 다음 위치에 두세요: \$expected" >&2
    echo "심볼릭 링크와 외부 workspace는 지원하지 않습니다." >&2
    exit 1
  fi
done
if [[ ! -f "\$RMF_WS/install/setup.bash" ]]; then
  echo "Open-RMF가 빌드되지 않았습니다: \$RMF_WS/install/setup.bash" >&2
  exit 1
fi

# ── 지난 실행이 남긴 DDS 공유메모리 정리 ──────────────────────────────────
#
# Fast DDS 는 참가자마다 `/dev/shm/fastrtps_*` 를 만든다. 곱게 끝나면 스스로
# 지우지만, `kill -9` 로 끊기거나 매달린 채 남으면 그대로 쌓인다. 쌓이면
# **탐색이 무너진다** — 노드는 살아 있는데 서비스가 안 보이고, 옆 노드는
# 영영 기다린다.
#
# 실측(2026-08-17) —
#
#     /dev/shm 의 fastrtps_* 484개 (48MB), 그중 200개가 지난 실행 잔재
#     [lifecycle_manager_map]: Waiting for service map_server/get_state...
#     → map_server 는 살아 있는데 서비스가 안 보여 지도가 영영 안 켜졌다
#
# **도는 것이 있으면 손대지 않는다.** 살아 있는 참가자의 조각을 지우면 그
# 노드가 통째로 먹통이 된다. 그래서 이 맵의 ROS 프로세스가 하나도 없을 때만
# 치운다.
sweep_stale_dds_segments() {
  local alive
  alive="\$(pgrep -u "\$(id -u)" -c -f 'gz sim|ros2 launch|nav2_|rmf_' \\
    2>/dev/null || true)"
  if [[ "\${alive:-0}" != 0 ]]; then
    echo "ROS 프로세스가 도는 중이라 DDS 공유메모리는 건드리지 않습니다." >&2
    return 0
  fi
  local segments
  segments="\$(find /dev/shm -maxdepth 1 -user "\$(id -u)" \\
    \\( -name 'fastrtps_*' -o -name 'fastdds_*' \\) 2>/dev/null | wc -l)"
  if ((segments == 0)); then
    return 0
  fi
  find /dev/shm -maxdepth 1 -user "\$(id -u)" \\
    \\( -name 'fastrtps_*' -o -name 'fastdds_*' \\) -delete 2>/dev/null || true
  echo "지난 실행이 남긴 DDS 공유메모리 \$segments 개를 정리했습니다." >&2
  # 탐색 캐시를 들고 있는 데몬도 함께 내린다. 다음 물음에서 새로 뜬다.
  ros2 daemon stop >/dev/null 2>&1 || true
}

# 이 프로젝트의 로봇이 실제로 쓰는 패키지. 등록된 로봇에서 뽑았다.
REQUIRED_PACKAGES="${_requiredPackages(robots).join(' ')}"

# 창을 띄울지 말지. Gazebo 와 RViz 를 따로 고른다.
#
# 예전에는 HEADLESS 하나가 둘을 함께 껐다 켰다 했다. 그런데 보고 싶은 것이
# 서로 다르다 — 로봇이 물리적으로 어디 있는지는 Gazebo 창에서, 계획한 경로와
# 코스트맵은 RViz 에서 본다. 하나만 보려고 둘을 다 띄우면 이 컴퓨터에서
# 프레임이 떨어져 시뮬레이션까지 느려졌다.
#
# 둘 다 안 띄워도 라이다·카메라는 돈다. Gazebo 서버는 언제나 헤드리스
# 렌더링으로 뜨기 때문이다. 창은 보는 용도일 뿐 데이터와는 무관하다.
#
# 앱이 실행할 때 환경 변수로 넘긴다. 터미널에서 직접 띄울 때는 이렇게 쓴다:
#   GAZEBO_GUI=true RVIZ=true ./run_$mapName.sh
is_true() {
  case "\${1,,}" in
    true|1|yes|on) return 0 ;;
    *) return 1 ;;
  esac
}

# HEADLESS 만 준 예전 방식도 그대로 받는다. 따로 준 값이 있으면 그쪽이 이긴다.
if is_true "\${HEADLESS:-true}"; then
  GUI_DEFAULT=false
else
  GUI_DEFAULT=true
fi
GAZEBO_GUI="\${GAZEBO_GUI:-\$GUI_DEFAULT}"
SIMULATOR_GUI="\${SIMULATOR_GUI:-\$GAZEBO_GUI}"
SIM_BACKEND="\${SIM_BACKEND:-gazebo}"
RVIZ="\${RVIZ:-\$GUI_DEFAULT}"

case "\$SIM_BACKEND" in
  gazebo|isaac_sim|none) ;;
  *)
    echo "지원하지 않는 SIM_BACKEND: \$SIM_BACKEND (gazebo|isaac_sim|none)" >&2
    exit 1
    ;;
esac

# launch 인자는 반대말(headless)이다. 여기서 한 번만 뒤집는다.
if is_true "\$GAZEBO_GUI"; then GAZEBO_HEADLESS=false; else GAZEBO_HEADLESS=true; fi
if is_true "\$RVIZ"; then RVIZ_HEADLESS=false; else RVIZ_HEADLESS=true; fi

BUILDING_YAML="\$MAP_DIR/$mapName.building.yaml"
NAV_GRAPH="\$MAP_DIR/nav_graphs/0.yaml"

if [[ ! -f "\$BUILDING_YAML" ]]; then
  echo "없는 파일: \$BUILDING_YAML" >&2
  echo "앱의 맵 관리에서 배포하기와 RMF 설정 내보내기를 먼저 하세요." >&2
  exit 1
fi

set +u
# shellcheck disable=SC1090
source "\$ROS_SETUP"
[[ -f "\$RMF_WS/install/setup.bash" ]] && source "\$RMF_WS/install/setup.bash"
[[ -f "\$PINKY_WS/install/setup.bash" ]] && source "\$PINKY_WS/install/setup.bash"
[[ -f "\$OMX_WS/install/setup.bash" ]] && source "\$OMX_WS/install/setup.bash"
set -u

# C++ RMF 라이브러리와 Python 바인딩이 다른 설치본에서 섞이면 다중 로봇
# 등록 중 SIGSEGV가 날 수 있으므로 작업공간 설치본만 허용한다.
RMF_ADAPTER_MODULE="\$(python3 -c 'import rmf_adapter; print(rmf_adapter.__file__)' 2>/dev/null || true)"
case "\$RMF_ADAPTER_MODULE" in
  "\$RMF_WS"/install/*) ;;
  *)
    echo "호환되지 않는 rmf_adapter가 선택됐습니다: \${RMF_ADAPTER_MODULE:-찾지 못함}" >&2
    echo "필요한 경로: \$RMF_WS/install 아래" >&2
    echo "RMF↔Nav2 어댑터를 시작하지 않습니다." >&2
    exit 1
    ;;
esac
echo "RMF adapter: \$RMF_ADAPTER_MODULE"

# nav_graphs/0.yaml 은 building.yaml 에서 파생된다. 맵에서 Waypoint 나 Lane 을
# 고쳐도 이 파일이 그대로면 RMF 는 옛날 지도를 본다. 없는 것이 아니라 낡은
# 것이라 오류가 나지 않는다 — 충전 Waypoint 를 방금 이었는데도 RMF 가 "충전
# 지점을 못 찾겠다"고 하는 것이 이 경우다. 그래서 매번 다시 만든다.
if [[ ! -f "\$NAV_GRAPH" || "\$BUILDING_YAML" -nt "\$NAV_GRAPH" ]]; then
  echo "nav_graphs/0.yaml 을 building.yaml 에서 다시 만든다."
  mkdir -p "\$MAP_DIR/nav_graphs"
  if ! ros2 run rmf_building_map_tools building_map_generator nav \\
      "\$BUILDING_YAML" "\$MAP_DIR/nav_graphs"; then
    echo "nav graph 생성 실패. rmf_building_map_tools 가 있는지 보세요." >&2
    exit 1
  fi
fi

if [[ ! -f "\$NAV_GRAPH" ]]; then
  echo "없는 파일: \$NAV_GRAPH" >&2
  exit 1
fi

# 모든 출력을 로그 파일로 보낸다.
#
# 앱이 이 스크립트를 파이프에 물려 띄우면, 그 파이프를 읽는 쪽이 없을 때
# 64KB 가 차는 순간 Gazebo 가 write 에서 영원히 멈춘다. 물리가 돌지 않아
# 모델도 안 올라오고 토픽에 값도 오지 않는다. 파일로 보내면 막힐 일이 없고,
# 무슨 일이 있었는지 나중에 볼 수도 있다.
#
# 다만 그대로 두면 감당이 안 된다. Gazebo 의 ODE 가 메시끼리 닿을 때마다
# 같은 경고 한 줄을 물리 스텝마다 찍어, 시간당 1.8GB 씩 찼다. 그래서 거른다.
#
#   1. launch 접두사만 있고 내용이 없는 줄은 버린다.
#   2. 바로 앞과 똑같은 줄은 세기만 하고, 다른 줄이 오면 "몇 번 더" 로 접는다.
#   3. 그래도 넘치면 한 번 밀어 두고 새로 쓴다 (최대 2 배까지만 남는다).
#
# 에러만 남기지는 않는다. 지금까지 원인을 알려 준 것은 대부분 ERROR 가 아니라
# 뜨는 순서였다 — Gazebo 가 먼저인지, /clock 이 나왔는지, 다리가 어느 토픽을
# 걸었는지. 대신 ERROR·경고·역추적만 따로 모은 파일을 하나 더 쓴다.
LOG_FILE="\$MAP_DIR/$mapName.log"
ERR_FILE="\$MAP_DIR/$mapName.err.log"
LOG_MAX_MB="\${LOG_MAX_MB:-200}"

# UI의 두 실행 경로가 거의 동시에 눌려도 두 번째 스크립트가 기존 로그를
# 비우거나 같은 월드를 한 벌 더 띄우지 못하게 한다. 잠금 FD는 이 셸이 끝날
# 때까지 유지된다.
LOCK_FILE="\$MAP_DIR/.$mapName.run.lock"
NAV2_LOCK_FILE="\$MAP_DIR/.$mapName.nav2.lock"
exec 9>"\$LOCK_FILE"
if ! flock -n 9; then
  echo "$mapName 프로젝트가 이미 실행 중입니다." >&2
  exit 1
fi
: > "\$ERR_FILE"

# mawk 는 detached 세션의 프로세스 치환 파이프에서 읽기가 멈춘 사례가 있다.
# unbuffered Python 수집기는 시작할 때 파일을 먼저 열고 한 줄씩 즉시 기록한다.
exec > >(exec python3 -u "\$APP_ROOT/openrmf/scripts/log_collector.py" \\
  --out "\$LOG_FILE" --err "\$ERR_FILE" --max-mb "\$LOG_MAX_MB") 2>&1
echo "=== \$(date '+%Y-%m-%d %H:%M:%S') $mapName 실행 ==="
# 창을 띄웠는지 안 띄웠는지 로그만 봐도 알게 한다. "화면이 안 뜬다" 는 물음이
# 실은 안 띄우기로 고른 것이었던 적이 여러 번이다.
echo "Gazebo 창: \$GAZEBO_GUI · RViz: \$RVIZ · ROS_DOMAIN_ID: \$ROS_DOMAIN_ID (\$ROS_DOMAIN_SOURCE)"
echo "시뮬레이션 백엔드: \$SIM_BACKEND · 시뮬레이터 창: \$SIMULATOR_GUI"

# 자기 프로세스 그룹 번호를 남긴다. 중지 스크립트가 이 그룹을 통째로 끊는다.
# 앱이 detached 로 띄우면 이 셸의 PID 는 그룹 리더가 아니므로, PID 가 아니라
# 실제 PGID 를 적어야 한다.
PGID_FILE="\$MAP_DIR/.$mapName.pgid"
ps -o pgid= -p \$\$ | tr -d ' ' > "\$PGID_FILE"

# 배포가 남긴 Building Map Server 를 먼저 내린다.
#
# `deploy_map.sh` 는 배포를 마치고 `building_map_server` 하나를 **일부러 띄운
# 채로** 끝난다(배포한 지도를 바로 볼 수 있게). 그런데 아래 launch 도 같은
# 파일로 제 것을 띄운다. 그대로 두면 `/building_map_server` 라는 **같은 이름의
# 노드가 둘**이 되고, `/get_building_map` 을 두 곳이 답한다. 누가 답할지는
# 그때그때 다르다.
#
# 게다가 앱은 맵 디렉터리를 물고 있는 프로세스를 세어 백엔드가 도는지 본다.
# 배포만 하고 아무것도 안 띄웠는데 그 서버 하나 때문에 `백엔드 실행 중` 이
# 되어, 정작 띄우려 하면 이미 돈다고 한다.
#
# 배포한 지도는 이미 파일로 깔려 있고 아래에서 다시 읽는다. 여기서 내려도
# 잃는 것이 없다.
DEPLOY_MAP_SERVER_PID="\$APP_ROOT/openrmf/.runtime/building_map_server.pid"
if [[ -f "\$DEPLOY_MAP_SERVER_PID" ]]; then
  stale="\$(cat "\$DEPLOY_MAP_SERVER_PID" 2>/dev/null || true)"
  if [[ -n "\$stale" ]] && kill -0 "\$stale" 2>/dev/null; then
    echo "배포가 띄워 둔 Building Map Server(\$stale)를 내립니다 — 이 launch 가"
    echo "같은 이름으로 제 것을 띄웁니다."
    kill "\$stale" 2>/dev/null || true
  fi
  rm -f "\$DEPLOY_MAP_SERVER_PID"
fi
# pid 파일이 없어도 남아 있을 수 있다(앱이 아닌 곳에서 띄웠거나 파일을 지웠거나).
pkill -u "\$(id -u)" -f \\
  "/rmf_building_map_tools/building_map_server \$MAP_DIR/" 2>/dev/null || true

cleanup() {
  echo "정리 중..."
  kill \$(jobs -p) 2>/dev/null || true
  # PGID 파일은 지우지 않는다.
  #
  # 이 셸이 먼저 끝나고 자식이 살아남는 일이 있다. 그때 파일까지 지우면
  # 그 그룹을 끊을 손잡이가 사라져, 중지 스크립트도 다음 실행의 남은 항목
  # 검사도 그 프로세스를 영영 못 찾는다. 파일은 중지 스크립트가 지운다.
}
trap cleanup EXIT INT TERM

# 필요한 패키지가 없으면 launch 가 통째로 예외를 내며 멈춘다. 그러면 다른
# 로봇까지 안 뜨는데, 화면에는 찾아본 경로 목록만 잔뜩 나와 원인을 알기 어렵다.
missing=()
for pkg in \$REQUIRED_PACKAGES; do
  if [[ "\$SIM_BACKEND" != gazebo && "\$pkg" == ros_gz_sim ]]; then
    continue
  fi
  ros2 pkg prefix "\$pkg" >/dev/null 2>&1 || missing+=("\$pkg")
done
if ((\${#missing[@]} > 0)); then
  echo "없는 ROS 패키지: \${missing[*]}" >&2
  echo "" >&2
  echo "이 프로젝트의 로봇을 띄우려면 아래를 빌드하고 다시 실행하세요." >&2
  for pkg in "\${missing[@]}"; do
    case "\$pkg" in
      pinky_*) echo "  \$pkg  ->  cd \$PINKY_WS && colcon build" >&2 ;;
      open_manipulator_*) echo "  \$pkg  ->  cd \$OMX_WS && colcon build" >&2 ;;
      *) echo "  \$pkg" >&2 ;;
    esac
  done
  exit 1
fi

# 월드에 센서 시스템을 채운다.
#
# 월드는 rmf_building_map_tools 가 제 템플릿(gz_world.sdf)에서 만드는데, 거기에는
# Physics · UserCommands · SceneBroadcaster 셋뿐이다. RMF 의 시범 로봇(slotcar)은
# 라이다를 안 쓰므로 필요가 없었다.
#
# 우리 핑키는 gpu_lidar · camera · imu 를 단다. 센서 시스템이 없으면 이 센서들이
# **하나도 발행하지 않는다.** 토픽 이름은 보이는데 데이터가 영영 안 온다. 라이다가
# 없으면 AMCL 도 Nav2 도 불가능하다.
#
# 배포할 때마다 월드가 다시 만들어지므로 여기서 매번 채운다. 이미 있으면 넘어간다.
ensure_world_sensors() {
  local world="\$1"
  [ -f "\$world" ] || return 0
  python3 - "\$world" <<'PYTHON'
import sys

path = sys.argv[1]
with open(path, encoding='utf-8') as handle:
    world = handle.read()

# 이름으로 찾는다. filename 은 앞에 lib 이 붙기도 하고 안 붙기도 한다.
wanted = [
    ('gz::sim::systems::Sensors',
     '    <plugin filename="gz-sim-sensors-system"\\n'
     '            name="gz::sim::systems::Sensors">\\n'
     '      <render_engine>ogre2</render_engine>\\n'
     '    </plugin>\\n'),
    ('gz::sim::systems::Imu',
     '    <plugin filename="gz-sim-imu-system"\\n'
     '            name="gz::sim::systems::Imu">\\n'
     '    </plugin>\\n'),
]
added = [name for name, _ in wanted if name not in world]
if not added:
    print('월드에 센서 시스템이 이미 있습니다.')
    sys.exit(0)

block = ''.join(snippet for name, snippet in wanted if name not in world)
# <world ...> 바로 다음에 넣는다. 시스템 플러그인은 월드의 자식이어야 한다.
marker = world.index('>', world.index('<world')) + 1
with open(path, 'w', encoding='utf-8') as handle:
    handle.write(world[:marker] + '\\n' + block + world[marker:])
print('월드에 센서 시스템을 넣었습니다: ' + ', '.join(added))
PYTHON
}
ensure_world_sensors "\$MAP_DIR/$mapName.world"

# 월드의 충돌 검출기를 bullet 으로 바꾼다.
#
# 기본값은 ODE 인데, 메시끼리 닿으면 무너진다. 우리 로봇은 충돌 도형이 전부
# 메시(핑키의 base_link.stl 따위)이고, 건물 바닥·벽도 배포가 만든 메시
# (generated_models/<맵>_L1/meshes/floor_1.obj)다. 그래서 로봇이 바닥에 서 있는
# 것만으로도 메시 대 메시다.
#
# 로봇 두 대가 겹쳐 놓이면 접점이 폭발해 여기서 죽는다:
#
#   ODE Message 2: Trimesh-trimesh contact hash table bucket overflow   (103번)
#   ODE INTERNAL ERROR 1: assertion "keyindex < lastkeyindex || ..." failed
#     in UpdateArbitraryContactInNode() [collision_trimesh_trimesh.cpp:285]
#   [ERROR] [gazebo-1]: process has died ... exit code 134
#
# 자리를 안 고른 로봇은 전부 지도 원점에 놓이므로 두 대만 있어도 이렇게 된다.
# 실제로 스폰 4초 만에 Gazebo 가 죽었고, 그 뒤 RMF 와 Nav2 만 살아남아 토픽
# 이름은 있는데 값은 하나도 안 오는 상태로 30분을 돌았다.
#
# bullet 은 같은 조건에서 경고 한 줄 없이 버틴다. 주행 거리도 ODE 와 같다
# (0.2 m/s 로 4초에 ODE 0.811 m · bullet 0.807 m). 자리를 겹쳐 놓는 것 자체는
# 여전히 잘못이지만, 그것 때문에 시뮬레이터가 죽지는 않게 한다.
#
# 배포할 때마다 월드가 다시 만들어지므로 여기서 매번 채운다. 이미 있으면 넘어간다.
ensure_world_collision_detector() {
  local world="\$1"
  [ -f "\$world" ] || return 0
  python3 - "\$world" <<'PYTHON'
import re
import sys

path = sys.argv[1]
with open(path, encoding='utf-8') as handle:
    world = handle.read()

if '<collision_detector>' in world:
    print('월드에 충돌 검출기가 이미 지정돼 있습니다.')
    sys.exit(0)

block = ('      <dart>\\n'
         '        <collision_detector>bullet</collision_detector>\\n'
         '      </dart>\\n')

opening = re.search(r'<physics\\b[^>]*?(/?)>', world)
if opening is None:
    # 월드를 못 고쳐도 실행은 계속한다. 여기서 멈추면 다른 로봇까지 안 뜬다.
    sys.stderr.write('<physics> 가 없어 충돌 검출기를 못 넣었습니다.\\n')
    sys.exit(0)

if opening.group(1):
    # <physics ... /> 처럼 닫혀 있으면 열어서 넣는다.
    head = opening.group(0)[:-2].rstrip() + '>\\n'
    world = (world[:opening.start()] + head + block + '    </physics>'
             + world[opening.end():])
else:
    end = world.find('</physics>', opening.end())
    if end < 0:
        sys.stderr.write('</physics> 가 없어 충돌 검출기를 못 넣었습니다.\\n')
        sys.exit(0)
    # 닫는 태그가 놓인 줄의 맨 앞에서 자른다. 태그 바로 앞에서 자르면 그 줄의
    # 들여쓰기가 우리 블록 앞에 붙고 </physics> 가 1열로 밀린다.
    head = world.rfind('\\n', 0, end) + 1
    if world[head:end].strip():
        head = end
    world = world[:head] + block + world[head:]

with open(path, 'w', encoding='utf-8') as handle:
    handle.write(world)
print('월드의 충돌 검출기를 bullet 으로 바꿨습니다.')
PYTHON
}
ensure_world_collision_detector "\$MAP_DIR/$mapName.world"

# Gazebo 가 실제로 떴는지 보고 다음 단계로 넘어간다.
#
# 예전에는 `&` 로 띄우고 `sleep 12` 만 했다. 뜬 줄 알고 넘어간 것이지 확인한
# 것이 아니었다. 그래서 Gazebo 가 스폰 4초 만에 죽었는데도(ODE 메시 충돌
# 어서션, exit 134) RMF 와 Nav2 가 그 시체 위에 올라갔다. 프로세스는 15개가
# 30분 넘게 살아 있었고 토픽 이름도 다 나왔지만 발행자는 0개였다 — 이름은
# 다리와 구독자가 남긴 것이다. 무엇이 잘못됐는지 어디에도 안 보였다.
#
# 두 가지를 본다. 월드를 물고 있는 `gz sim` 이 있는가, 그리고 /clock 이 나오는가.
# 떠 있는 것과 물리가 도는 것은 다르다. use_sim_time 을 쓰는 RMF 노드는 /clock
# 이 없으면 시간이 멈춘 줄 알고 그대로 멈춰 있는다.
GAZEBO_WAIT="\${GAZEBO_WAIT:-90}"
ISAAC_WAIT="\${ISAAC_WAIT:-300}"
wait_for_gazebo() {
  local world="\$1"
  local deadline=\$((SECONDS + GAZEBO_WAIT))
  while ((SECONDS < deadline)); do
    if pgrep -u "\$(id -u)" -f "gz sim.*\$world" >/dev/null 2>&1 &&
       timeout 5 ros2 topic echo /clock --once >/dev/null 2>&1; then
      return 0
    fi
    sleep 2
  done
  return 1
}

# 선택한 물리 백엔드를 시작한다. 양쪽 모두 같은 ROS 토픽(/clock, odom, scan,
# joint_states, tf, cmd_vel)을 제공해야 이후 Nav2와 RMF를 그대로 쓸 수 있다.
start_simulator() {
  case "\$SIM_BACKEND" in
    gazebo)
      echo "${projectUsesNav2(robots) ? '[1/3]' : '[1/2]'} Gazebo bringup"
      ros2 launch "\$MAP_DIR/${mapName}_bringup.launch.xml" headless:="\$GAZEBO_HEADLESS" &
      if ! wait_for_gazebo "\$MAP_DIR/$mapName.world"; then
        echo "Gazebo 가 \$GAZEBO_WAIT 초 안에 뜨지 않았습니다." >&2
        return 1
      fi
      ;;
    isaac_sim)
      local launcher="\${ISAAC_SIM_PYTHON:-}"
      if [[ -z "\$launcher" ]]; then
        local candidate
        local candidates=(
          "\${ISAAC_SIM_ROOT:+\$ISAAC_SIM_ROOT/python.sh}"
          "\$HOME/isaacsim/python.sh"
          "\$HOME/isaac/isaacsim/_build/linux-x86_64/release/python.sh"
          "\$HOME/isaac/env_isaaclab/bin/python"
        )
        for candidate in "\${candidates[@]}"; do
          if [[ -n "\$candidate" && -x "\$candidate" ]]; then
            launcher="\$candidate"
            break
          fi
        done
      fi
      local script="\${ISAAC_PROJECT_SCRIPT:-\$MAP_DIR/isaac/start_$mapName.py}"
      local converter="\${ISAAC_PROJECT_CONVERTER:-\$MAP_DIR/isaac/convert_$mapName.py}"
      local stage="\${ISAAC_STAGE:-\$MAP_DIR/isaac/$mapName.usd}"
      if [[ ! -x "\$launcher" ]]; then
        echo "Isaac Sim Python 실행기를 찾지 못했습니다." >&2
        echo "확인한 기본 위치: \$HOME/isaacsim, \$HOME/isaac/isaacsim, \$HOME/isaac/env_isaaclab" >&2
        echo "다른 위치라면 ISAAC_SIM_ROOT 또는 ISAAC_SIM_PYTHON을 지정하세요." >&2
        return 1
      fi
      echo "Isaac Sim Python: \$launcher"
      if [[ ! -f "\$script" || ! -f "\$converter" ]]; then
        echo "Isaac Sim 프로젝트 산출물이 없습니다." >&2
        echo "필요한 파일: \$script" >&2
        echo "필요한 파일: \$converter" >&2
        return 1
      fi
      local rebuild=false
      [[ ! -f "\$stage" || "\$MAP_DIR/$mapName.world" -nt "\$stage" ]] && rebuild=true
      local generator
      for generator in "\$MAP_DIR"/robots/*/robot_description.sh; do
        [[ -e "\$generator" ]] || continue
        [[ "\$generator" -nt "\$stage" ]] && rebuild=true
      done
      if is_true "\$rebuild"; then
        echo "Gazebo 맵·로봇을 Isaac USD로 자동 변환합니다."
        mkdir -p "\$MAP_DIR/isaac/robots"
        for generator in "\$MAP_DIR"/robots/*/robot_description.sh; do
          [[ -e "\$generator" ]] || continue
          local robot_id
          robot_id="\$(basename "\$(dirname "\$generator")")"
          bash "\$generator" > "\$MAP_DIR/isaac/robots/\$robot_id.urdf"
        done
        if ! "\$launcher" "\$converter" --map-dir "\$MAP_DIR" --stage "\$stage"; then
          echo "Gazebo → Isaac USD 자동 변환에 실패했습니다." >&2
          return 1
        fi
      fi
      if [[ ! -f "\$stage" ]]; then
        echo "Isaac USD가 생성되지 않았습니다: \$stage" >&2
        return 1
      fi
      local gui_arg="--headless"
      is_true "\$SIMULATOR_GUI" && gui_arg="--gui"
      echo "Isaac Sim bringup: \$stage"
      "\$launcher" "\$script" --stage "\$stage" "\$gui_arg" &
      local isaac_pid=\$!
      local deadline=\$((SECONDS + ISAAC_WAIT))
      while ((SECONDS < deadline)); do
        timeout 5 ros2 topic echo /clock --once >/dev/null 2>&1 && return 0
        if ! kill -0 "\$isaac_pid" 2>/dev/null; then
          wait "\$isaac_pid" || true
          echo "Isaac Sim 프로세스가 /clock 발행 전에 종료됐습니다." >&2
          return 1
        fi
        sleep 2
      done
      echo "Isaac Sim이 \$ISAAC_WAIT 초 안에 /clock을 발행하지 않았습니다." >&2
      return 1
      ;;
    none)
      echo "물리 시뮬레이터 없이 RMF/RViz만 시작합니다."
      ;;
  esac
}

${projectUsesNav2(robots) ? '''
# 띄우기 전에 지난 실행의 잔재부터 치운다. 쌓인 조각은 탐색을 무너뜨린다.
sweep_stale_dds_segments
echo "[1/3] 시뮬레이션 백엔드"
if ! start_simulator; then
  echo "" >&2
  echo "시뮬레이션 백엔드가 준비되지 않았습니다." >&2
  echo "RMF 와 Nav2 는 띄우지 않고 여기서 멈춥니다 — 물리가 없으면 그 둘은" >&2
  echo "토픽 이름만 만들어 놓고 값은 하나도 못 받습니다." >&2
  echo "" >&2
  echo "무엇이 있었는지: \$LOG_FILE" >&2
  echo "오류만 모은 것: \$ERR_FILE" >&2
  exit 1
fi

echo "[2/3] Open-RMF"
ros2 launch "\$MAP_DIR/$mapName.launch.xml" headless:="\$RVIZ_HEADLESS" &
sleep 12

# RMF↔Nav2 어댑터가 뜨고 계속 살아 있는지 지켜본다.
#
# 이 어댑터가 죽어도 Gazebo·Nav2·RMF core 는 그대로 남는다. 그래서 토픽은 잘
# 오는데 주문만 안 먹는 상태가 된다. 화면에는 `RMF 가 답하지 않았습니다` 로만
# 보이고 무엇이 죽었는지는 어디에도 안 나왔다.
#
# 실제로 로봇 ID 에 하이픈이 있어(`PK-01`) 어댑터가 로봇을 플릿에 붙이는 순간
# 죽은 일이 있다. RMF 가 `rmf/dynamic_event/begin/<플릿>/<로봇>` 토픽을 만드는데
# ROS 2 토픽 이름에는 하이픈을 못 쓰기 때문이다.
ADAPTER_WAIT="\${ADAPTER_WAIT:-90}"
# launch 의 respawn_delay 보다 넉넉해야 한다. 짧으면 다시 뜨는 중인 것을 두고
# 죽었다고 알린다.
ADAPTER_RESPAWN_WAIT="\${ADAPTER_RESPAWN_WAIT:-30}"
# 어댑터가 로봇을 놓치면 **스스로 다시 붙지 않는다.** 뜰 때 `/fleet_states` 에서
# 로봇을 찾아 등록하는데, 그때 Nav2·AMCL 이 아직이면 위치를 몰라 등록을 못 하고
# 그대로 있는다. 재기동해야 붙는다 — 실측으로 재기동 자체는 4초면 끝났다.
#
# 그러니 오래 기다릴 이유가 없다. 예전 값(유예 120초 · 주기 30초 · 3회)이면
# 최악에 210초, 3분 반을 기다린 뒤에야 재기동했다. 그동안 화면에는 어댑터가
# 연결되는 중으로만 보인다.
#
# 유예는 Nav2 가 뜨는 데 걸리는 만큼만 준다. 너무 짧으면 정상 기동 중인 어댑터를
# 죽여 오히려 느려지므로, 라즈베리파이가 느린 것을 감안해 45초를 둔다.
# 최악 = 45 + 15*2 = 75초.
ADAPTER_HEALTH_GRACE="\${ADAPTER_HEALTH_GRACE:-45}"
ADAPTER_HEALTH_INTERVAL="\${ADAPTER_HEALTH_INTERVAL:-15}"
ADAPTER_HEALTH_FAILURES="\${ADAPTER_HEALTH_FAILURES:-2}"
EXPECTED_FLEET_ROBOTS="${navigatingRobots(robots).map((robot) => robot.robotId).join(' ')}"

# ── 지도 서버가 정말 켜졌는지 ──────────────────────────────────────────────
#
# `map_server` 는 생명주기 노드다. `nav2_lifecycle_manager` 가 configure 로
# 지도를 읽히고 activate 로 넘겨야 비로소 지도를 낸다.
#
# **그 사이가 끊어진다.** 관리자가 부르는 `change_state` 의 응답 시한이 5초로
# **코드에 박혀 있다** — 파라미터가 없어 늘릴 수 없다(`ros2 param list
# /lifecycle_manager_map` 에 `service_timeout` 이 없다). 기계가 바쁘면 지도를
# 읽는 데 5초가 넘고, map_server 는 제대로 configure 를 마쳤는데 응답만 늦게
# 간다. 관리자는 그것을 실패로 보고 **거기서 멈춘다. 다시 시도하지 않는다.**
#
#     [map_server.rclcpp]: failed to send response to /map_server/change_state
#                          (timeout): client will not receive response
#
# 그러면 map_server 가 inactive 로 남고, 증상은 세 단계 떨어진 곳에 뜬다 —
#
#     amcl:            Waiting for map....
#     global_costmap:  Invalid frame ID "map" ... frame does not exist
#     어댑터:          TF 를 못 읽어 로봇을 등록 못 함
#     화면:            "rmf-nav2 연결 실패"
#
# 어댑터를 아무리 다시 띄워도 소용없다. 지도가 없는 한 등록할 수 없다.
# 그래서 어댑터를 탓하기 전에 여기부터 본다. 그리고 멈춰 있으면 **직접
# 넘긴다** — 관리자가 안 하는 일을 대신 하는 것이라 안전하다.
#
# 생명주기 전이 번호: 1=configure 2=cleanup 3=activate 4=deactivate
MAP_SERVER_WAIT="\${MAP_SERVER_WAIT:-90}"

# ── 지난 실행이 남긴 지도 서버 문의 정리 ─────────────────────────────────
#
# `ros2 service call` 은 상대가 없으면 **영원히 기다린다.** 지금은 `timeout` 을
# 씌우지만, 그것이 없던 판으로 띄운 것이 남아 있으면 계속 매달린 채로 같은
# 도메인을 쓴다 — 실측(2026-08-17) 세 개가 30분 넘게 남아 있었다.
#
# **`ros2 service call` 을 통째로 죽이지 않는다.** 사람이 터미널에서 다른
# 서비스를 부르고 있을 수 있다. 우리가 부르는 그 서비스 이름만 고르고, 지금 이
# 스크립트의 프로세스 그룹은 건드리지 않는다(우리 것은 timeout 이 거둔다).
sweep_stale_map_server_calls() {
  local mine killed=0 pid pgid
  mine="\$(ps -o pgid= -p \$\$ 2>/dev/null | tr -d ' ')"
  for pid in \$(pgrep -u "\$(id -u)" -f \\
      'ros2 service call /map_server/' 2>/dev/null || true); do
    pgid="\$(ps -o pgid= -p "\$pid" 2>/dev/null | tr -d ' ')"
    if [[ -z "\$pgid" || "\$pgid" == "\$mine" ]]; then
      continue
    fi
    if kill "\$pid" 2>/dev/null; then
      killed=\$((killed + 1))
    fi
  done
  if ((killed > 0)); then
    echo "지난 실행이 남긴 지도 서버 문의 \$killed 개를 정리했습니다." >&2
  fi
  return 0
}

map_server_state() {
  timeout 15 ros2 service call /map_server/get_state \\
      lifecycle_msgs/srv/GetState 2>/dev/null \\
    | grep -o "label='[a-z]*'" | tail -1 | cut -d"'" -f2
}
map_server_transition() {
  timeout 25 ros2 service call /map_server/change_state \\
    lifecycle_msgs/srv/ChangeState "{transition: {id: \$1}}" >/dev/null 2>&1
}
# 켜져 있으면 0. 켰으면 0. 아직 못 켜면 1.
ensure_map_server_active() {
  local state
  state="\$(map_server_state)"
  case "\$state" in
    active) return 0 ;;
    '') return 1 ;;
    unconfigured|finalized)
      echo "지도 서버가 [\$state] 입니다. 지도를 읽힙니다." >&2
      map_server_transition 1
      sleep 2
      state="\$(map_server_state)"
      ;;
  esac
  [ "\$state" = inactive ] || return 1
  echo "지도 서버가 [inactive] 에 멈춰 있습니다. 직접 켭니다." >&2
  echo "(생명주기 관리자의 5초 시한을 넘겨 activate 가 오지 않았습니다.)" >&2
  map_server_transition 3
  sleep 2
  if [ "\$(map_server_state)" = active ]; then
    echo "지도 서버를 켰습니다. AMCL 이 지도를 받습니다." >&2
    return 0
  fi
  return 1
}
watch_map_server() {
  # 묻기 전에 지난 실행이 남긴 문의부터 거둔다.
  sweep_stale_map_server_calls
  local deadline=\$((SECONDS + MAP_SERVER_WAIT))
  while ((SECONDS < deadline)); do
    ensure_map_server_active && return 0
    sleep 3
  done
  echo "" >&2
  echo "지도 서버를 \$MAP_SERVER_WAIT 초 안에 켜지 못했습니다." >&2
  echo "지도가 없으면 AMCL 이 map → <로봇>/odom 을 못 내고, 어댑터는 로봇의" >&2
  echo "위치를 몰라 플릿에 등록하지 못합니다. 화면에는 연결 실패로만 보입니다." >&2
  echo "지도 파일을 확인하세요: \$MAP_DIR/nav2_map/$mapName.yaml" >&2
  echo "오류만 모은 것: \$ERR_FILE" >&2
  return 1
}

watch_fleet_adapter() {
  local pattern="\$MAP_DIR/${mapName}_nav2_adapter.py"
  local deadline=\$((SECONDS + ADAPTER_WAIT))
  while ((SECONDS < deadline)); do
    pgrep -u "\$(id -u)" -f "\$pattern" >/dev/null 2>&1 && break
    sleep 2
  done
  if ! pgrep -u "\$(id -u)" -f "\$pattern" >/dev/null 2>&1; then
    echo "" >&2
    echo "RMF↔Nav2 어댑터가 \$ADAPTER_WAIT 초 안에 뜨지 않았습니다." >&2
    echo "RMF 는 주문을 받아도 배차할 플릿이 없습니다." >&2
    echo "오류만 모은 것: \$ERR_FILE" >&2
    return
  fi
  echo "RMF↔Nav2 어댑터가 떴습니다."
  local health_after=\$((SECONDS + ADAPTER_HEALTH_GRACE))
  local last_health=0
  local failed_health=0
  # 뜬 다음 죽는 것이 진짜 문제다. 계속 지켜본다.
  #
  # 다만 launch 가 respawn 으로 다시 띄운다. 사라진 그 순간에 죽었다고 알리면
  # 5초 뒤 멀쩡히 살아난 것을 두고 사람을 뛰게 만든다. 돌아오기를 기다렸다가,
  # 정말 안 돌아올 때만 알린다.
  while :; do
    if pgrep -u "\$(id -u)" -f "\$pattern" >/dev/null 2>&1; then
      if ((SECONDS >= health_after && SECONDS - last_health >= ADAPTER_HEALTH_INTERVAL)); then
        last_health=\$SECONDS
        local fleet_state
        fleet_state="\$(timeout 12 ros2 topic echo /fleet_states --once 2>/dev/null || true)"
        local missing=0
        local robot
        for robot in \$EXPECTED_FLEET_ROBOTS; do
          if ! grep -Fq "name: \$robot" <<<"\$fleet_state"; then
            missing=1
            echo "RMF fleet state에 \$robot 등록이 없습니다." >&2
          fi
        done
        if ((missing)); then
          # 어댑터를 탓하기 전에 지도부터 본다. 지도 서버가 꺼져 있으면 AMCL 이
          # map TF 를 못 내고, 어댑터는 로봇 위치를 몰라 **영원히** 등록하지
          # 못한다. 그 상태에서 어댑터만 다시 띄우면 30초마다 되풀이될 뿐이다.
          if ! ensure_map_server_active; then
            echo "지도 서버가 아직 안 켜져 있습니다. 어댑터는 그대로 둡니다 —" >&2
            echo "지도가 없으면 몇 번을 다시 띄워도 등록할 수 없습니다." >&2
            failed_health=0
            sleep 5
            continue
          fi
          failed_health=\$((failed_health + 1))
          if ((failed_health >= ADAPTER_HEALTH_FAILURES)); then
            echo "fleet 등록 확인이 \$failed_health 회 연속 실패했습니다. 어댑터를 재기동합니다." >&2
            pkill -u "\$(id -u)" -f "\$pattern" || true
            failed_health=0
            health_after=\$((SECONDS + ADAPTER_HEALTH_GRACE))
          fi
        else
          failed_health=0
        fi
      fi
      sleep 5
      continue
    fi
    local back=\$((SECONDS + ADAPTER_RESPAWN_WAIT))
    local revived=0
    while ((SECONDS < back)); do
      sleep 2
      if pgrep -u "\$(id -u)" -f "\$pattern" >/dev/null 2>&1; then
        revived=1
        break
      fi
    done
    if ((revived)); then
      echo "RMF↔Nav2 어댑터가 죽었다가 다시 떴습니다." >&2
      continue
    fi
    break
  done
  echo "" >&2
  echo "RMF↔Nav2 어댑터가 죽었고 다시 뜨지도 않았습니다." >&2
  echo "이제 RMF 는 주문을 받지 못하고, RViz 에서는 경로와 로봇이 사라집니다 —" >&2
  echo "그 둘을 내는 /nav_graphs · /fleet_states 가 이 어댑터에서만 나옵니다." >&2
  echo "Gazebo 와 Nav2 는 그대로 살아 있어 토픽은 계속 옵니다. 그래서 겉으로는" >&2
  echo "멀쩡해 보입니다." >&2
  echo "" >&2
  echo "먼저 위에 출력된 RMF adapter 경로가 rmf_ws/install 아래인지 확인하세요." >&2
  echo "C++ 라이브러리와 Python 바인딩의 설치본이 섞이면 다중 로봇 등록 중" >&2
  echo "SIGSEGV가 날 수 있습니다." >&2
  echo "또 다른 원인은 로봇 ID 입니다. RMF 가 ID 로 토픽을 만드는데" >&2
  echo "(rmf/dynamic_event/begin/<플릿>/<로봇>) 영문·숫자·밑줄만 쓸 수 있습니다." >&2
  echo "하이픈이 들어간 ID 는 로봇을 플릿에 붙이는 순간 어댑터를 죽입니다." >&2
  echo "" >&2
  echo "무엇이 있었는지: \$LOG_FILE" >&2
  echo "오류만 모은 것: \$ERR_FILE" >&2
}

# Nav2 와 RMF↔Nav2 어댑터. 이것이 없으면 RMF 가 배차해도 로봇이 안 움직인다 —
# /<로봇>/cmd_vel 에 발행하는 것이 아무것도 없기 때문이다.
#
# RMF core 다음이라야 한다. 어댑터는 뜨자마자 schedule node 를 찾는다.
echo "[3/3] Nav2 와 RMF 어댑터"
# 지도 서버를 먼저 지킨다. 어댑터 감시자보다 앞이라야 한다 — 어댑터가 등록에
# 실패하는 첫 이유가 지도가 없어서이기 때문이다.
watch_map_server &
watch_fleet_adapter &
exec 8>"\$NAV2_LOCK_FILE"
while pgrep -u "\$(id -u)" -f "ros2 launch \$MAP_DIR/${mapName}_nav2.launch.xml" >/dev/null 2>&1 || ! flock -n 8; do
  echo "Nav2가 이미 실행 중입니다. 중복 실행하지 않고 종료를 기다립니다."
  sleep 2
done
ros2 launch "\$MAP_DIR/${mapName}_nav2.launch.xml"''' : '''
sweep_stale_dds_segments
echo "[1/2] 시뮬레이션 백엔드"
if ! start_simulator; then
  echo "" >&2
  echo "시뮬레이션 백엔드가 준비되지 않았습니다." >&2
  echo "Open-RMF 는 띄우지 않고 여기서 멈춥니다 — 월드가 없으면 토픽 이름만" >&2
  echo "만들어 놓고 값은 하나도 못 받습니다." >&2
  echo "" >&2
  echo "무엇이 있었는지: \$LOG_FILE" >&2
  echo "오류만 모은 것: \$ERR_FILE" >&2
  exit 1
fi

echo "[2/2] Open-RMF"
ros2 launch "\$MAP_DIR/$mapName.launch.xml" headless:="\$RVIZ_HEADLESS"'''}
''';

/// 이 프로젝트로 띄운 것을 내리는 셸 스크립트.
/// 바꾼 것에 딸린 것만 다시 띄우는 스크립트.
///
/// Waypoint 하나를 옮기고 전체를 다시 띄우면 1~2분이 걸린다. Gazebo 가 다시
/// 서고 로봇이 다시 스폰되고 Nav2 가 처음부터 lifecycle 을 밟는다 — 정작
/// 바뀐 것은 nav graph 하나인데.
///
/// 무엇이 무엇을 읽는지는 정해져 있다. 셋 다 **기동할 때 한 번** 읽고 그 뒤로는
/// 메모리에 든 것을 쓰므로, 다시 읽히려면 그 프로세스를 다시 띄우는 수밖에 없다.
String buildProjectRestartScript({
  required String mapName,
  required String mapDirectory,
}) =>
    '''#!/usr/bin/env bash
# $mapName 프로젝트의 일부만 다시 띄운다.
# rmf_control_ui 가 맵 프로젝트에서 생성했다. 손으로 고치면 다음 배포 때
# 덮어써진다.
#
#   $mapName.building.yaml  ->  building_map_server
#   nav_graphs/0.yaml       ->  fleet_adapter (-n 인자)
#   nav2_params.yaml        ->  로봇 Nav2 노드들
#
#   ./restart_$mapName.sh rmf     지도(Waypoint·레인)가 바뀌었을 때
#   ./restart_$mapName.sh nav2    로봇 파라미터가 바뀌었을 때
set -euo pipefail

MAP_DIR="$mapDirectory"
MODE="\${1:-rmf}"

if [[ -f /opt/ros/jazzy/setup.bash ]]; then
  set +u
  . /opt/ros/jazzy/setup.bash
  set -u
fi

# 이 프로젝트가 띄운 것만 고른다. 다른 맵으로 띄운 RMF 는 건드리지 않는다.
stop_launch() {
  local label="\$1" pattern="\$2" pids
  mapfile -t pids < <(pgrep -u "\$(id -u)" -f "\$pattern" 2>/dev/null || true)
  if ((\${#pids[@]} == 0)); then
    echo "  \$label: 안 떠 있었습니다"
    return
  fi
  kill -TERM "\${pids[@]}" 2>/dev/null || true
  # 자식까지 내려갈 시간을 준다. ros2 launch 는 TERM 을 받고 제 자식에게 다시
  # 보낸다 — 바로 KILL 하면 자식이 고아로 남아 다음에 띄운 것과 두 벌이 된다.
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    sleep 1
    pgrep -u "\$(id -u)" -f "\$pattern" >/dev/null 2>&1 || break
  done
  pkill -KILL -u "\$(id -u)" -f "\$pattern" 2>/dev/null || true
  echo "  \$label: 내렸습니다"
}

case "\$MODE" in
  rmf)
    echo "[1/2] RMF 계층을 내립니다 (Gazebo · 로봇 Nav2 · 브링업은 그대로)"
    stop_launch "Open-RMF" "ros2 launch \$MAP_DIR/$mapName.launch.xml"
    # 어댑터는 nav graph 를 -n 인자로 물고 있다. 지도가 바뀌면 이것도 다시
    # 읽어야 하므로 함께 내린다.
    stop_launch "Nav2 어댑터" "\$MAP_DIR/${mapName}_nav2_adapter.py"
    echo "[2/2] 다시 띄웁니다"
    nohup ros2 launch "\$MAP_DIR/$mapName.launch.xml" headless:=true > "\$MAP_DIR/$mapName.restart.log" 2>&1 &
    echo "완료. 어댑터가 로봇을 다시 등록하기까지 20초쯤 걸립니다."
    ;;
  nav2)
    echo "[1/2] 로봇 Nav2 를 내립니다 (RMF · Gazebo · 브링업은 그대로)"
    stop_launch "로봇 Nav2" "ros2 launch \$MAP_DIR/${mapName}_nav2.launch.xml"
    echo "[2/2] 다시 띄웁니다"
    nohup bash -lc 'exec 8>"\$1"; flock -n 8 || exit 0; exec ros2 launch "\$2"' nav2-restart "\$MAP_DIR/.$mapName.nav2.lock" "\$MAP_DIR/${mapName}_nav2.launch.xml" > "\$MAP_DIR/${mapName}_nav2.restart.log" 2>&1 &
    echo "완료. lifecycle 이 다 켜지기까지 10초쯤 걸립니다."
    ;;
  *)
    echo "쓰는 법: \$0 [rmf|nav2]" >&2
    exit 2
    ;;
esac
''';

String buildProjectStopScript({
  required String mapName,
  required String mapDirectory,
  List<RmfProjectRobot> robots = const [],
}) =>
    '''#!/usr/bin/env bash
# $mapName 프로젝트로 띄운 프로세스를 내린다.
# rmf_control_ui 가 맵 프로젝트에서 생성했다.
#
# 이 프로젝트의 launch 경로로 시작한 것만 고른다. 다른 맵으로 띄운 RMF 나
# 관계없는 Gazebo 는 건드리지 않는다.
set -euo pipefail

MAP_DIR="\${MAP_DIR:-$mapDirectory}"

# 이 프로젝트가 쓰는 로봇 네임스페이스. 인자에 맵 경로가 없는 노드는 이 이름으로
# 찾는다 — robot_state_publisher 같은 것은 URDF 만 들고 있어 경로가 없다.
ROBOT_NAMESPACES="${robots.where((robot) => robot.runsInGazebo).map((robot) => robot.gzName).join(' ')}"
APP_ROOT="\${ROBOSAPIENS_ROOT:-\$(cd "\$MAP_DIR/../.." && pwd)}"
RMF_WS="\${RMF_WS:-\$APP_ROOT/rmf_ws}"
LOCK_FILE="\$MAP_DIR/.$mapName.run.lock"

# INT → TERM → KILL 로 올려 가며 내린다.
#
# rclpy 노드는 TERM 을 받고도 종료 중에 스레드가 서로를 기다리며 굳는 일이
# 있다. 거기서 멈추면 노드가 살아남아 다음 실행에서 이름이 겹친다.
stop_pids() {
  local label="\$1"
  shift
  local pids=("\$@") remaining=() pid
  if ((\${#pids[@]} == 0)); then
    echo "\$label: 실행 중이 아님"
    return
  fi
  echo "\$label 중지: \${pids[*]}"
  local signal
  for signal in INT TERM KILL; do
    remaining=()
    for pid in "\${pids[@]}"; do
      # 좀비는 이미 끝난 것이다. 기다릴 것이 없다.
      if kill -0 "\$pid" 2>/dev/null &&
         [[ "\$(ps -o stat= -p "\$pid" 2>/dev/null)" != *Z* ]]; then
        remaining+=("\$pid")
      fi
    done
    if ((\${#remaining[@]} == 0)); then
      return
    fi
    [[ "\$signal" == "KILL" ]] &&
      echo "  \$label: 응답이 없어 강제 종료합니다 (\${remaining[*]})"
    kill "-\$signal" "\${remaining[@]}" 2>/dev/null || true
    sleep 3
  done
}

stop_matching() {
  local label="\$1" pattern="\$2"
  mapfile -t pids < <(pgrep -u "\$(id -u)" -f "\$pattern" 2>/dev/null || true)
  stop_pids "\$label" "\${pids[@]}"
}

# ros2 launch 가 죽으면 자식이 init 으로 재부모화된다. 그룹도 잃고
# `ros2 launch <경로>` 라는 이름도 잃어서, 이름이나 PGID 로는 잡히지 않는다.
# 이 맵 디렉터리를 인자로 물고 있으면 이 프로젝트가 띄운 것이다.
sweep_map_dir() {
  local label="\$1" pids=() pid args
  while read -r pid; do
    [[ -z "\$pid" || "\$pid" == "\$\$" || "\$pid" == "\$PPID" ]] && continue
    # pgrep 과 여기 사이에 끝난 프로세스가 있을 수 있다. 없으면 조용히 넘긴다.
    [[ -r "/proc/\$pid/cmdline" ]] || continue
    # 2>/dev/null 을 먼저 건다. 뒤에 걸면 입력 리다이렉트가 먼저 실패하면서
    # 셸이 그 오류를 그대로 찍는다 — pgrep 과 여기 사이에 끝난 프로세스가 있다.
    args="\$(tr '\\0' ' ' 2>/dev/null < "/proc/\$pid/cmdline" || true)"
    # 이 스크립트 자신과 이것을 부른 셸은 건드리지 않는다.
    [[ "\$args" == *"stop_$mapName.sh"* ]] && continue
    [[ "\$args" == *"\$MAP_DIR"* ]] || continue
    pids+=("\$pid")
  done < <(pgrep -u "\$(id -u)" -f "\$MAP_DIR" 2>/dev/null || true)
  if ((\${#pids[@]} == 0)); then
    echo "\$label: 남은 것 없음"
    return
  fi
  stop_pids "\$label" "\${pids[@]}"
}

stop_matching "Open-RMF ($mapName)" "ros2 launch \$MAP_DIR/$mapName.launch.xml"
stop_matching "Gazebo bringup ($mapName)" \\
  "ros2 launch \$MAP_DIR/${mapName}_bringup.launch.xml"
stop_matching "Gazebo 서버 ($mapName)" "gz sim.*\$MAP_DIR/$mapName.world"

# 실행 스크립트가 남긴 프로세스 그룹을 통째로 끊는다. 이름으로 못 찾은 자식이
# 있어도 여기서 정리된다.
PGID_FILE="\$MAP_DIR/.$mapName.pgid"
if [[ -f "\$PGID_FILE" ]]; then
  PGID="\$(cat "\$PGID_FILE")"
  if [[ "\$PGID" =~ ^[0-9]+\$ ]] && kill -0 -- "-\$PGID" 2>/dev/null; then
    echo "프로세스 그룹 \$PGID 중지"
    kill -INT -- "-\$PGID" 2>/dev/null || true
    sleep 3
    kill -TERM -- "-\$PGID" 2>/dev/null || true
  fi
  rm -f "\$PGID_FILE"
fi

# 마지막으로 재부모화되어 살아남은 것을 쓸어낸다. fleet_manager 처럼 launch 가
# 죽어도 혼자 도는 것들이 여기서 잡힌다.
sweep_map_dir "이 맵을 물고 남은 노드 ($mapName)"

# 네임스페이스로 한 번 더 쓸어낸다.
#
# robot_state_publisher 같은 노드는 인자에 맵 경로가 없다. 대신 ROS 가 넣어 준
# `__ns:=/<gz 이름>` 을 들고 있다. 이 프로젝트가 쓰는 이름은 우리가 정한
# 것이므로 다른 것과 겹치지 않는다.
sweep_namespaces() {
  local pids=() pid ns
  for ns in \$ROBOT_NAMESPACES; do
    while read -r pid; do
      [[ -z "\$pid" || "\$pid" == "\$\$" || "\$pid" == "\$PPID" ]] && continue
      pids+=("\$pid")
    done < <(pgrep -u "\$(id -u)" -f -- "__ns:=/\$ns\\b" 2>/dev/null || true)
  done
  if ((\${#pids[@]} == 0)); then
    echo "로봇 네임스페이스 ($mapName): 남은 것 없음"
    return
  fi
  stop_pids "로봇 네임스페이스 ($mapName)" "\${pids[@]}"
}

sweep_namespaces

# 마지막으로 RMF core 를 쓸어낸다.
#
# schedule node 나 supervisor 는 인자에 맵 경로도 로봇 네임스페이스도 없다.
# launch 가 죽고 PGID 파일도 없으면 어떤 방법으로도 못 찾는다. RMF core 는
# 한 번에 하나만 뜰 수 있으므로, 백엔드를 내리기로 한 이상 이것이 대상이다.
sweep_rmf_core() {
  mapfile -t pids < <(
    pgrep -u "\$(id -u)" -f "\$RMF_WS/install/rmf_" 2>/dev/null || true
  )
  if ((\${#pids[@]} == 0)); then
    echo "RMF core: 남은 것 없음"
    return
  fi
  stop_pids "RMF core" "\${pids[@]}"
}

sweep_rmf_core

# Gazebo 다리를 쓸어낸다.
#
# `parameter_bridge` 는 인자에 맵 경로가 있는 것도 있지만, `/clock` 하나만 잇는
# 것은 인자가 `/clock@rosgraph_msgs...` 뿐이라 위 그물에 하나도 안 걸린다.
# 부모마저 systemd 로 바뀌면 프로세스 그룹으로도 못 잡는다.
#
# 그러면 다음 실행에서 **/clock 을 두 곳이 낸다.** 두 시계가 번갈아 나오니
# 시각이 앞뒤로 튀고, tf2 가 `Detected jump back in time` 으로 버퍼를 통째로
# 비운다. AMCL 은 위치추정을 잃고 Nav2 는 명령을 멈춘다 — 로봇은 멀쩡한데
# 가만히 서 있고, 그 원인이 한 시간 전에 남은 프로세스라는 것은 어디에도
# 안 보인다. 실제로 그렇게 39번 튀었다.
sweep_bridges() {
  mapfile -t pids < <(
    pgrep -u "\$(id -u)" -f "ros_gz_bridge/parameter_bridge" 2>/dev/null || true
  )
  if ((\${#pids[@]} == 0)); then
    echo "Gazebo 다리: 남은 것 없음"
    return
  fi
  stop_pids "Gazebo 다리" "\${pids[@]}"
}

sweep_bridges

# 실행 셸의 FD 9는 모든 자식에게 상속된다. launch가 죽은 뒤 이름도 경로도 없는
# lifecycle_manager가 고아로 남아도 이 잠금 FD만큼은 그대로 들고 있다. 따라서
# 이름 검색이 모두 실패한 뒤 잠금 파일을 연 PID를 직접 찾아 마지막으로 끊는다.
sweep_lock_holders() {
  local pass fd target pid pids=()
  for pass in 1 2 3; do
    pids=()
    for fd in /proc/[0-9]*/fd/*; do
      target="\$(readlink "\$fd" 2>/dev/null || true)"
      [[ "\$target" == "\$LOCK_FILE" ]] || continue
      pid="\${fd#/proc/}"
      pid="\${pid%%/*}"
      [[ "\$pid" == "\$\$" || "\$pid" == "\$PPID" ]] && continue
      [[ " \${pids[*]} " == *" \$pid "* ]] || pids+=("\$pid")
    done
    ((\${#pids[@]} == 0)) && return
    stop_pids "실행 잠금 보유 프로세스 ($mapName, 확인 \$pass)" "\${pids[@]}"
  done
}

sweep_lock_holders

# 종료 성공은 이름 검색 결과가 아니라 새 실행이 잠금을 잡을 수 있는지로 판정한다.
# 좀비는 FD를 보유하지 않으므로 잠금 검사를 통과하며, 살아 있는 숨은 프로세스는
# 반드시 실패시킨다. 실패를 성공처럼 표시하지 않도록 0이 아닌 코드로 끝낸다.
if ! flock -n "\$LOCK_FILE" true; then
  echo "오류: $mapName 실행 잠금이 아직 사용 중입니다." >&2
  echo "확인: fuser -v \$LOCK_FILE" >&2
  exit 1
fi

remaining_zombies="\$(ps -u "\$(id -u)" -o pid=,ppid=,pgid=,stat=,args= |
  awk -v map="\$MAP_DIR" '\$4 ~ /^Z/ && index(\$0, map) {print}')"
if [[ -n "\$remaining_zombies" ]]; then
  echo "오류: $mapName 관련 좀비 프로세스가 남았습니다:" >&2
  echo "\$remaining_zombies" >&2
  exit 1
fi

# 배포가 남긴 Building Map Server 도 함께 내린다.
#
# 그것은 이 프로젝트의 프로세스 그룹 밖에 있어서 위의 그룹 끊기로는 안 죽는다.
# 남겨 두면 앱이 맵 디렉터리를 물고 있는 프로세스를 세다가 **백엔드가 아직
# 돈다** 고 보고, 화면에서 백엔드가 영영 안 내려간 것처럼 보인다.
DEPLOY_MAP_SERVER_PID="\$APP_ROOT/openrmf/.runtime/building_map_server.pid"
if [[ -f "\$DEPLOY_MAP_SERVER_PID" ]]; then
  stale="\$(cat "\$DEPLOY_MAP_SERVER_PID" 2>/dev/null || true)"
  if [[ -n "\$stale" ]] && kill -0 "\$stale" 2>/dev/null; then
    kill "\$stale" 2>/dev/null || true
  fi
  rm -f "\$DEPLOY_MAP_SERVER_PID"
fi
pkill -u "\$(id -u)" -f \\
  "/rmf_building_map_tools/building_map_server \$MAP_DIR/" 2>/dev/null || true

# 지도 서버 상태를 묻던 `ros2 service call` 이 남아 있으면 상대가 사라진 뒤에도
# **영원히 기다린다.** 실측(2026-08-17) 세 개가 30분 넘게 매달려 있었다.
#
# 우리가 부르는 그 서비스 이름만 고른다 — `ros2 service call` 을 통째로 죽이면
# 사람이 터미널에서 부르던 것까지 함께 죽는다.
stale_calls="\$(pgrep -u "\$(id -u)" -f 'ros2 service call /map_server/' \\
  2>/dev/null | tr '\\n' ' ' || true)"
if [[ -n "\${stale_calls// /}" ]]; then
  # shellcheck disable=SC2086
  kill \$stale_calls 2>/dev/null || true
  echo "매달려 있던 지도 서버 문의를 정리했습니다: \$stale_calls"
fi

echo "$mapName 프로젝트 프로세스를 정리했습니다."
''';

/// 로봇 한 대의 Nav2 를 띄우는 launch.
///
/// **네임스페이스 아래에서만 돈다.** 노드마다 이름을 걸지 않고 그룹에
/// `push-ros-namespace` 를 한 번 건다 — 두 번 걸면 `/pinky_01/pinky_01/amcl` 이
/// 되어 파라미터가 하나도 안 붙는다(`docs/MULTI_ROBOT_NAMESPACES.md` 함정 1).
///
/// `map_server` 는 여기 없다. 같은 건물이므로 **월드에 하나만** 띄운다.
String buildRobotNav2LaunchXml(
  RmfProjectRobot robot,
  String mapName, {
  int projectDomainId = defaultRosDomainId,
}) {
  final namespace = robot.gzName;
  final odomFrame = '${robot.gzName}/odom';
  final baseFrame = '${robot.gzName}/base_footprint';
  // lifecycle_manager 가 이 차례로 켠다. costmap 을 쓰는 것보다 그것을 만드는
  // 쪽이 먼저 서야 한다.
  const managed = [
    'controller_server',
    'smoother_server',
    'planner_server',
    'behavior_server',
    'bt_navigator',
    'waypoint_follower',
    'velocity_smoother',
  ];
  final buffer = StringBuffer()
    ..writeln("<?xml version='1.0' ?>")
    ..writeln('<!--')
    ..writeln('  ${robot.robotId} · ${robot.displayName} 의 Nav2.')
    ..writeln('  rmf_control_ui 가 맵 프로젝트에서 생성했다.')
    ..writeln('')
    ..writeln('  이 로봇의 라이다로 제 위치를 잡고(AMCL) 길을 만들어 간다.')
    ..writeln('  파라미터는 같은 디렉터리의 nav2_params.yaml 이다 — 벤더의')
    ..writeln('  nav2_params.yaml 을 이 로봇 이름에 맞춰 다시 쓴 것이다.')
    ..writeln('')
    ..writeln('  map_server 는 여기 없다. 같은 건물이므로 월드에 하나만 띄운다.')
    ..writeln('  ${mapName}_nav2.launch.xml 이 그것을 맡는다.')
    ..writeln('')
    ..writeln('  혼자 시험하려면 map_server 를 먼저 띄우고 이것을 돌린다.')
    ..writeln('-->')
    ..writeln('<launch>')
    ..write(_robotDomainEnv(robot))
    // 실물은 벽시계로 값을 찍어 보낸다. 여기를 true 로 두면 AMCL 이 sim 시계를
    // 보고, 오지 않을 시각의 scan 을 기다리다 위치추정을 못 한다 — 오류는 안
    // 난다. 프로젝트 launch 가 이 값을 다시 넘기므로 여기 기본값은 이 파일만
    // 따로 돌려 볼 때 쓰인다.
    ..writeln('  <arg name="use_sim_time" default="${robot.runsInGazebo}"/>')
    ..writeln('  <group>')
    // 한 번만 건다. 아래 노드에는 네임스페이스를 따로 걸지 않는다.
    ..write(
      '    <push-ros-namespace namespace="$namespace"/>\n',
    )
    ..writeln('')
    ..writeln('    <!-- 라이다로 제 위치를 잡는다. map → $odomFrame -->')
    ..writeln('    <node pkg="nav2_amcl" exec="amcl" name="amcl"')
    ..writeln('          output="screen">')
    ..writeln('      <param from="\$(dirname)/nav2_params.yaml"/>')
    ..writeln('      <param name="use_sim_time" value="\$(var use_sim_time)"/>')
    // 지도는 로봇마다 가르지 않는다. `/map` 은 RMF 의 building_map_server 가
    // 이미 쓰고 있어서 한 토픽에 형식이 둘 올라간다.
    ..writeln('      <param name="map_topic" value="$nav2MapTopic"/>')
    ..writeln('    </node>');
  for (final node in managed) {
    final package = switch (node) {
      'controller_server' => 'nav2_controller',
      'smoother_server' => 'nav2_smoother',
      'planner_server' => 'nav2_planner',
      'behavior_server' => 'nav2_behaviors',
      'bt_navigator' => 'nav2_bt_navigator',
      'waypoint_follower' => 'nav2_waypoint_follower',
      _ => 'nav2_velocity_smoother',
    };
    buffer
      ..writeln('')
      ..writeln('    <node pkg="$package" exec="$node" name="$node"')
      ..writeln('          output="screen">')
      ..writeln('      <param from="\$(dirname)/nav2_params.yaml"/>')
      ..writeln(
        '      <param name="use_sim_time" value="\$(var use_sim_time)"/>',
      );
    if (node == 'behavior_server') {
      // behavior_server 는 제 이름으로 TF 를 본다. 파라미터로만 주면 늦게
      // 붙는 일이 있어 여기서도 못 박는다.
      buffer.writeln(
        '      <param name="robot_base_frame" '
        'value="$baseFrame"/>',
      );
    }
    // controller와 recovery behavior의 원시 속도는 smoother 입력으로 보낸다.
    // smoother의 최종 출력만 실제 로봇이 구독하는 cmd_vel에 연결해야 한다.
    // 이 remap이 없으면 cmd_vel_smoothed는 구독자 0인 채 버려지고, 실물은
    // smoothing을 우회한 원시 명령을 간헐적으로 받는다.
    if (node == 'controller_server' || node == 'behavior_server') {
      buffer.writeln('      <remap from="cmd_vel" to="cmd_vel_nav"/>');
    }
    if (node == 'velocity_smoother') {
      buffer
        ..writeln('      <remap from="cmd_vel" to="cmd_vel_nav"/>')
        ..writeln('      <remap from="cmd_vel_smoothed" to="cmd_vel"/>');
    }
    buffer.writeln('    </node>');
  }
  buffer
    ..writeln('')
    ..writeln('    <!-- 위 노드들을 차례로 켜고 끈다. -->')
    ..writeln('    <node pkg="nav2_lifecycle_manager" exec="lifecycle_manager"')
    ..writeln('          name="lifecycle_manager_navigation" output="screen">')
    // Nav2 노드와 같은 clock을 써야 lifecycle 전이와 costmap의 TF 시간이
    // 어긋나지 않는다. 실물은 launch 인자가 false라 벽시계를 계속 쓴다.
    ..writeln('      <param name="use_sim_time" value="\$(var use_sim_time)"/>')
    ..writeln('      <param name="autostart" value="true"/>')
    // 라즈베리파이에서 `controller_server` 는 costmap 을 만드느라 기동이
    // 무겁다. 그 사이 전이 응답이 늦으면 관리자가 실패로 보고 **뒤의 노드는
    // 시도조차 하지 않는다** — amcl 만 active 고 나머지는 unconfigured 로 남아,
    // 위치는 뜨는데 주행만 안 되는 상태가 된다.
    ..writeln(
      '      <param name="service_timeout" '
      'value="$nav2LifecycleServiceTimeoutSeconds"/>',
    )
    // 기동 직후 바쁜 노드가 heartbeat 를 늦게 보내는 것만으로 죽은 것으로
    // 보지 않게 한다.
    ..writeln(
      '      <param name="bond_timeout" '
      'value="$nav2LifecycleBondTimeoutSeconds"/>',
    )
    ..writeln('      <param name="node_names"')
    ..writeln('             value="[amcl, ${managed.join(', ')}]"/>')
    ..writeln('    </node>')
    ..writeln('  </group>')
    ..writeln('</launch>');
  return buffer.toString();
}

/// 앱이 만든 작업을 RMF 에 넣어 주는 작은 다리.
///
/// RMF 는 `task_api_requests` 토픽 하나로 작업을 받는다. 그런데 `ros2 topic
/// pub` 으로는 이 일을 제대로 할 수 없다 — 요청과 응답을 `request_id` 로 맞춰야
/// 하고, QoS 가 transient_local 이라 한 번 실은 뒤 잠깐 살아 있어야 한다.
///
/// 그래서 짧은 스크립트를 하나 둔다. 앱이 JSON 파일 하나를 주면 실어 보내고,
/// RMF 의 답을 그대로 찍고 끝난다. 앱은 `ros2 topic echo` 를 띄우는 것과 같은
/// 방식으로 이것을 부른다.
///
/// **실물 로봇에서도 그대로 돈다.** 여기는 RMF 와만 이야기한다.
String buildTaskBridgeScript({
  required String mapName,
  required String fleetName,
}) =>
    '''#!/usr/bin/env python3
"""$mapName 프로젝트의 작업 다리 — 앱이 만든 작업을 RMF 에 넣는다.

rmf_control_ui 가 맵 프로젝트에서 생성했다. 손으로 고치면 다음 저장 때
덮어써진다.

  ${mapName}_task_bridge.py --submit 작업.json

작업.json 은 `robot_task_request` 나 `dispatch_task_request` 한 덩어리다.
성공하면 RMF 의 답을 그대로 찍고 0 으로 끝난다.
"""

import argparse
import json
import sys
import uuid

import rclpy
import rclpy.node
from rclpy.qos import QoSProfile, QoSDurabilityPolicy, QoSHistoryPolicy

from rmf_task_msgs.msg import ApiRequest, ApiResponse

FLEET_NAME = '$fleetName'

# RMF 의 task API 는 transient_local 이다. 늦게 붙는 쪽도 마지막 것을 받는다.
API_QOS = QoSProfile(
    history=QoSHistoryPolicy.KEEP_LAST,
    depth=10,
    durability=QoSDurabilityPolicy.TRANSIENT_LOCAL)


def main(argv=sys.argv):
    parser = argparse.ArgumentParser(prog='$mapName' + '_task_bridge')
    parser.add_argument('--submit', required=True,
                        help='보낼 작업 JSON 파일')
    parser.add_argument('--timeout', type=float, default=15.0,
                        help='답을 기다리는 초')
    args = parser.parse_args(argv[1:])

    with open(args.submit, encoding='utf-8') as handle:
        payload = json.load(handle)

    rclpy.init(args=None)
    node = rclpy.node.Node('$fleetName' + '_task_bridge')
    publisher = node.create_publisher(ApiRequest, 'task_api_requests', API_QOS)

    request = ApiRequest()
    request.request_id = 'rmf_control_ui-' + str(uuid.uuid4())[:8]
    request.json_msg = json.dumps(payload, ensure_ascii=False)

    answer = {}

    def on_response(message):
        # 남의 요청에 대한 답도 같은 토픽으로 온다.
        if message.request_id != request.request_id:
            return
        answer['body'] = json.loads(message.json_msg)

    node.create_subscription(ApiResponse, 'task_api_responses',
                             on_response, API_QOS)

    # 구독이 붙기 전에 실으면 답을 놓친다. 한 바퀴 돌려 놓고 보낸다.
    rclpy.spin_once(node, timeout_sec=0.5)
    publisher.publish(request)

    deadline = node.get_clock().now().nanoseconds + int(args.timeout * 1e9)
    while 'body' not in answer:
        if node.get_clock().now().nanoseconds > deadline:
            print(json.dumps({
                'success': False,
                'errors': [{'code': 0, 'category': 'timeout', 'detail':
                            'RMF 가 답하지 않았습니다. fleet adapter 가 떠 '
                            '있는지 확인하세요.'}],
            }, ensure_ascii=False))
            node.destroy_node()
            if rclpy.ok():
                rclpy.shutdown()
            return 1
        rclpy.spin_once(node, timeout_sec=0.2)

    print(json.dumps(answer['body'], ensure_ascii=False))
    node.destroy_node()
    if rclpy.ok():
        rclpy.shutdown()
    return 0 if answer['body'].get('success') else 1


if __name__ == '__main__':
    sys.exit(main(sys.argv))
''';

/// 로봇의 센서를 앱이 볼 수 있게 파일로 내려 준다.
///
/// 앱에는 rclpy 바인딩이 없다. 지금까지는 `ros2 topic echo` 를 자식 프로세스로
/// 띄워 읽었는데, **카메라 영상에는 그 방법을 쓸 수 없다** — 1280×720 한 장이
/// YAML 로 2.7MB 다. 초당 서른 장이면 읽기 전에 앱이 멈춘다.
///
/// 그래서 작은 relay 노드를 하나 둔다. 구독해서 줄여 파일로 쓰고, 앱은 그 파일만
/// 읽는다. 로봇마다 프로세스를 띄우지 않으므로 대수가 늘어도 가볍다.
///
/// **실물 로봇에서도 그대로 돈다.** 토픽 이름만 같으면 되고, Gazebo 인지 진짜
/// 카메라인지는 이 노드가 알 필요가 없다.
String buildSensorRelayScript({
  required String mapName,
  required List<RmfProjectRobot> robots,
}) {
  final nodeName = _rosNodeName('${mapName}_sensor_relay');
  final watched = robots
      .where((robot) => robot.isMobile && robot.dataSource.usesTopics)
      .toList();
  final mapping = watched
      .map((robot) => "    ('${robot.robotId}', '${robot.gzName}'),")
      .join('\n');
  return '''#!/usr/bin/env python3
"""$mapName 프로젝트의 센서 relay.

rmf_control_ui 가 맵 프로젝트에서 생성했다. 손으로 고치면 다음 저장 때
덮어써진다.

로봇의 라이다와 카메라를 구독해서 앱이 읽을 수 있는 파일로 내려 준다. 앱에는
rclpy 가 없고, 카메라 영상은 `ros2 topic echo` 로 읽기에 너무 크다.

파일은 --out 디렉터리에 로봇 ID 로 쌓인다.

    <ID>.scan   라이다 한 줄 (텍스트)
    <ID>.frame  카메라 한 장 (RGBA 날바이트, 앞에 작은 머리글)

둘 다 임시 파일에 쓰고 rename 한다. 앱이 반쯤 쓰인 파일을 읽는 일이 없다.
"""

import argparse
import os
import struct
import sys

import numpy as np
import rclpy
from rclpy.node import Node
from rclpy.qos import qos_profile_sensor_data

from sensor_msgs.msg import Image, LaserScan

# (RMF 가 아는 이름, ROS 네임스페이스)
ROBOTS = [
$mapping
]

# 카메라를 줄여서 보낼 크기. 원본 그대로 두면 한 장에 2.7MB 라 디스크만 먹는다.
# 로봇 상세에서 보기에는 이 정도면 넉넉하다.
FRAME_WIDTH = 320
FRAME_HEIGHT = 180

# 라이다는 이만큼으로 솎는다. 640개를 다 그려도 눈에 보이는 차이가 없다.
SCAN_POINTS = 180

# 카메라를 초당 몇 장까지 내릴까. 앱은 0.2초마다 읽으므로 이보다 많이 내려도
# 보이지 않고 디스크만 먹는다.
FRAME_INTERVAL = 1.0 / 6

# 카메라 파일 머리글. 앱이 이 네 글자로 파일이 맞는지 본다.
FRAME_MAGIC = b'RSIM'


def write_atomic(path, data, binary=True):
    """반쯤 쓰인 파일을 앱이 읽지 않도록 임시 파일에 쓰고 옮긴다."""
    tmp = path + '.tmp'
    with open(tmp, 'wb' if binary else 'w') as handle:
        handle.write(data)
    os.replace(tmp, path)


class SensorRelay(Node):

    def __init__(self, out_dir):
        super().__init__('${nodeName}')
        self.out_dir = out_dir
        self.last_frame = {}
        os.makedirs(out_dir, exist_ok=True)
        for robot_id, namespace in ROBOTS:
            self.create_subscription(
                LaserScan, f'/{namespace}/scan',
                lambda msg, rid=robot_id: self.on_scan(rid, msg),
                qos_profile_sensor_data)
            self.get_logger().info(f'[{robot_id}] /{namespace} 를 봅니다.')

    def on_scan(self, robot_id, msg):
        ranges = list(msg.ranges)
        if not ranges:
            return
        # 고르게 솎는다. 앞쪽만 잘라내면 뒤가 안 보인다.
        step = max(1, len(ranges) // SCAN_POINTS)
        thinned = ranges[::step]
        # 무한대와 NaN 은 텍스트로 옮기면 파서가 걸린다. 잴 수 없었다는 뜻이므로
        # 최대 거리로 적는다.
        cleaned = []
        for value in thinned:
            if value != value or value == float('inf') or value > msg.range_max:
                cleaned.append(msg.range_max)
            else:
                cleaned.append(value)
        head = '{:.6f},{:.6f},{:.3f},{:.3f}'.format(
            msg.angle_min, msg.angle_max, msg.range_min, msg.range_max)
        body = ','.join('{:.3f}'.format(value) for value in cleaned)
        write_atomic(
            os.path.join(self.out_dir, robot_id + '.scan'),
            head + '\\n' + body + '\\n', binary=False)

    def on_image(self, robot_id, msg):
        # 속도를 제한한다. 앱은 0.2초마다 읽으므로 더 자주 내려도 보이지 않는다.
        now = self.get_clock().now().nanoseconds / 1e9
        if now - self.last_frame.get(robot_id, 0.0) < FRAME_INTERVAL:
            return
        self.last_frame[robot_id] = now

        pixels = self.to_rgba(msg)
        if pixels is None:
            return
        header = FRAME_MAGIC + struct.pack('<II', FRAME_WIDTH, FRAME_HEIGHT)
        write_atomic(
            os.path.join(self.out_dir, robot_id + '.frame'), header + pixels)

    def to_rgba(self, msg):
        """영상을 줄여서 RGBA 로 만든다.

        화소를 파이썬 반복문으로 옮기면 안 된다. 320x180 한 장에 5만 7천 번이고,
        두 대가 초당 열두 장이면 코어 하나를 통째로 먹는다 — 실제로 101% 를
        썼다. numpy 는 rclpy 가 이미 쓰고 있으므로 새로 받을 것이 없다.
        """
        if msg.encoding not in ('rgb8', 'bgr8'):
            self.get_logger().warn(
                f'모르는 영상 형식 [{msg.encoding}] 입니다.', once=True)
            return None

        frame = np.frombuffer(msg.data, dtype=np.uint8)
        # step 은 한 줄의 바이트 수다. 폭보다 클 수 있어서 잘라 낸다.
        frame = frame.reshape(msg.height, msg.step)[:, :msg.width * 3]
        frame = frame.reshape(msg.height, msg.width, 3)

        # 가장 가까운 화소를 집는다. 보간은 필요 없다 — 보여 주기용이다.
        rows = (np.arange(FRAME_HEIGHT) * msg.height) // FRAME_HEIGHT
        columns = (np.arange(FRAME_WIDTH) * msg.width) // FRAME_WIDTH
        small = frame[rows][:, columns]
        if msg.encoding == 'bgr8':
            small = small[:, :, ::-1]

        alpha = np.full((FRAME_HEIGHT, FRAME_WIDTH, 1), 255, dtype=np.uint8)
        return np.concatenate([small, alpha], axis=2).tobytes()


def main(argv=sys.argv):
    parser = argparse.ArgumentParser(prog='${mapName}_sensor_relay')
    parser.add_argument('-o', '--out', required=True)
    args = parser.parse_args(rclpy.utilities.remove_ros_args(argv)[1:])

    rclpy.init(args=argv)
    node = SensorRelay(args.out)
    if not ROBOTS:
        node.get_logger().warn('볼 로봇이 없습니다.')
    try:
        rclpy.spin(node)
    except KeyboardInterrupt:
        pass
    node.destroy_node()
    # rclpy 의 신호 처리기가 먼저 context 를 닫아 놓는 일이 있다. 그때 또
    # 부르면 예외가 올라와, 멀쩡히 끝난 것이 죽은 것처럼 보인다.
    if rclpy.ok():
        rclpy.shutdown()


if __name__ == '__main__':
    main(sys.argv)
''';
}

/// RMF 와 Nav2 를 잇는 어댑터.
///
/// 지금까지 이 고리가 끊겨 있었다.
///
/// ```
/// /robot_state          발행자 0 · 구독자 1   ← RMF 가 듣는데 아무도 말 안 함
/// /robot_path_requests  발행자 1 · 구독자 0   ← RMF 가 말하는데 아무도 안 들음
/// ```
///
/// 저 두 토픽은 RMF 시범 로봇(slotcar)의 것이다. 핑키는 slotcar 가 아니라
/// `/cmd_vel` · `/odom` 만 아는 diff drive 라서 상대가 없었다.
///
/// `EasyFullControl` 이 그 사이를 잇는다. RMF 가 주는 목적지를 Nav2 의
/// `NavigateToPose` 로 바꾸고, TF 에서 읽은 위치를 RMF 에 되돌린다.
///
/// **이 노드가 실물에서도 그대로 돈다.** Nav2 가 아래에서 Gazebo 를 몰든 진짜
/// 모터를 몰든 위쪽은 같기 때문이다.
String buildNav2FleetAdapterScript({
  required String mapName,
  required String fleetName,
  required List<RmfProjectRobot> robots,
  int projectDomainId = defaultRosDomainId,
}) {
  final navigating = navigatingRobots(robots);
  // RMF 가 아는 이름(로봇 ID)과 ROS 네임스페이스(Gazebo 이름)는 다르다.
  final mapping = navigating
      .map(
        (robot) =>
            "    '${robot.robotId}': '${robot.gzName}',",
      )
      .join('\n');
  return '''#!/usr/bin/env python3
"""$mapName 프로젝트의 RMF ↔ Nav2 어댑터.

rmf_control_ui 가 맵 프로젝트에서 생성했다. 손으로 고치면 다음 저장 때
덮어써진다.

RMF 가 주는 목적지를 Nav2 의 NavigateToPose 로 바꾸고, TF 에서 읽은 위치를 RMF 에
되돌린다. rmf_demos_fleet_adapter 는 slotcar 전용이라 우리 핑키에게는 상대가 없다.

이 노드는 실물에서도 그대로 돈다. Nav2 가 아래에서 Gazebo 를 몰든 진짜 모터를
몰든 위쪽은 같기 때문이다.
"""

import argparse
import json
import math
import sys
import threading
import math
import time
import uuid

import rclpy
import rclpy.node
from rclpy.action import ActionClient
from rclpy.duration import Duration
from rclpy.parameter import Parameter

import rmf_adapter
from rmf_adapter import Adapter
import rmf_adapter.easy_full_control as rmf_easy

from action_msgs.msg import GoalStatus
from nav2_msgs.action import NavigateToPose
from geometry_msgs.msg import PoseStamped
from rmf_dispenser_msgs.msg import DispenserRequest, DispenserRequestItem, DispenserResult
from rmf_fleet_msgs.msg import FleetState
from rmf_task_msgs.msg import ApiRequest
from rclpy.qos import QoSProfile, QoSDurabilityPolicy, QoSReliabilityPolicy
from std_msgs.msg import String as StringMsg
import tf2_ros

# 워크셀이 실패라고 답했을 때 다시 물어보는 횟수.
#
# 실패가 늘 영구적인 것은 아니다. 로봇이 도착 직후 마지막 자세를 다듬는 동안
# 걸리면, 몇 초 뒤에는 멀쩡히 된다. 한 번 실패했다고 작업을 접으면 멀쩡한
# 픽업이 버려진다.
WORKCELL_RETRIES = 3
WORKCELL_RETRY_SECONDS = 5.0

# 진행 상황을 내보내는 자리. 앱이 이것을 읽어 단계를 넘긴다.
#
# RMF 의 작업 상태는 rmf-web 의 웹소켓으로만 나간다. 웹서버를 띄우지 않으면
# 어디에서도 볼 수 없다. 그런데 목적지를 하나씩 받는 것은 이 어댑터이므로,
# 여기가 진행을 아는 가장 이른 자리다.
PROGRESS_TOPIC = '$fleetName/task_progress'
_progress = None


def report(**fields):
    """앱에게 지금 무엇을 하는지 알린다. 없으면 조용히 넘어간다."""
    if _progress is None:
        return
    message = StringMsg()
    message.data = json.dumps(fields, ensure_ascii=False)
    _progress.publish(message)

# RMF 가 아는 이름 -> ROS 네임스페이스.
ROBOT_NAMESPACES = {
$mapping
}

# 건물 층 이름. nav graph 의 level 과 같아야 한다.
MAP_NAME = 'L1'


def yaw_of(rotation):
    """사원수에서 yaw 를 푼다. 평면을 도는 로봇이라 이것 하나면 된다."""
    x, y, z, w = rotation.x, rotation.y, rotation.z, rotation.w
    return math.atan2(2 * (w * z + x * y), 1 - 2 * (y * y + z * z))


class RobotAdapter:
    """로봇 한 대. RMF 쪽과 Nav2 쪽을 양쪽으로 붙인다."""

    next_registration_at = 0.0

    def __init__(self, name, namespace, node, tf_buffer, fleet_handle,
                 fleet_config, registration_delay):
        self.name = name
        self.namespace = namespace
        self.node = node
        self.tf_buffer = tf_buffer
        self.fleet_handle = fleet_handle
        self.fleet_config = fleet_config
        self.update_handle = None
        self.update_ready_at = None
        self.execution = None
        self.goal_handle = None
        # Nav2 액션 결과는 비동기로 늦게 돌아온다. 새 목적지가 옛 목적지를
        # 선점한 뒤 옛 취소 결과가 도착해도 현재 RMF 실행을 끝내면 안 된다.
        self.goal_generation = 0
        self.warned = False
        self.lock = threading.Lock()
        self.prefix = f'/{namespace}' if namespace else ''
        self.nav = ActionClient(
            node, NavigateToPose, f'{self.prefix}/navigate_to_pose')
        request_qos = QoSProfile(
            depth=10,
            reliability=QoSReliabilityPolicy.RELIABLE,
            durability=QoSDurabilityPolicy.TRANSIENT_LOCAL,
        )
        self.dispenser_requests = node.create_publisher(
            DispenserRequest, '/dispenser_requests', request_qos)
        self.dispenser_result_subscription = node.create_subscription(
            DispenserResult, '/dispenser_results',
            self.on_dispenser_result, 10)
        self.dispenser_execution = None
        self.dispenser_request_guid = None
        self.dispenser_target_guid = None
        self.dispenser_item = 'policy_1'
        self.dispenser_quantity = 1
        self.dispenser_attempt = 0

        # 워크셀이 끝내 안 되면 작업을 취소해야 한다. 취소하려면 작업 번호가
        # 필요한데, 그것은 우리가 만든 것이 아니라 RMF 가 붙인 것이다.
        # `/fleet_states` 에 실려 오므로 여기서 받아 둔다.
        self.current_task_id = ''
        self.task_api = node.create_publisher(
            ApiRequest, 'task_api_requests', request_qos)
        self.fleet_state_subscription = node.create_subscription(
            FleetState, '/fleet_states', self.on_fleet_state, 10)
        # pybind C++가 콜백을 사용하는 동안 Python 객체가 회수되지 않게 한다.
        self.callbacks = self.make_callbacks()

    def on_fleet_state(self, msg):
        for robot in msg.robots:
            if robot.name == self.name:
                self.current_task_id = robot.task_id
                return

    # ── RMF 가 부르는 쪽 ────────────────────────────────────────────────

    def make_callbacks(self):
        return rmf_easy.RobotCallbacks(
            lambda destination, execution: self.navigate(destination, execution),
            lambda activity: self.stop(activity),
            lambda category, description, execution: self.execute_action(
                category, description, execution),
        )

    def navigate(self, destination, execution):
        """RMF 가 준 목적지로 Nav2 를 보낸다."""
        with self.lock:
            self.goal_generation += 1
            generation = self.goal_generation
            self.execution = execution
        x, y, yaw = destination.position
        self.node.get_logger().info(
            f'[{self.name}] -> ({x:.3f}, {y:.3f}, {math.degrees(yaw):.0f}도)'
            f' 지도 [{destination.map}]')
        report(robot=self.name, event='navigate_start',
               x=float(x), y=float(y), yaw=float(yaw))

        if not self.nav.wait_for_server(timeout_sec=5.0):
            self.node.get_logger().error(
                f'[{self.name}] Nav2 가 없습니다. '
                f'{self.prefix}/navigate_to_pose 를 확인하세요.')
            self.finish(generation, execution)
            return

        goal = NavigateToPose.Goal()
        goal.pose = PoseStamped()
        goal.pose.header.frame_id = 'map'
        goal.pose.header.stamp = self.node.get_clock().now().to_msg()
        goal.pose.pose.position.x = float(x)
        goal.pose.pose.position.y = float(y)
        goal.pose.pose.orientation.z = math.sin(yaw / 2)
        goal.pose.pose.orientation.w = math.cos(yaw / 2)

        future = self.nav.send_goal_async(goal)
        future.add_done_callback(
            lambda done: self.on_goal_response(done, generation, execution))

    def on_goal_response(self, future, generation, execution):
        handle = future.result()
        if handle is None or not handle.accepted:
            with self.lock:
                current = generation == self.goal_generation
            if not current:
                return
            self.node.get_logger().error(f'[{self.name}] Nav2 가 거절했습니다.')
            self.finish(generation, execution)
            return
        with self.lock:
            if generation != self.goal_generation:
                handle.cancel_goal_async()
                return
            self.goal_handle = handle
        handle.get_result_async().add_done_callback(
            lambda done: self.on_goal_result(done, generation, execution))

    def on_goal_result(self, future, generation, execution):
        # 결과를 봐야 한다. 안 보고 끝났다고 알리면 RMF 는 그 자리에 닿은 줄
        # 알고 다음 단계로 넘어간다 — 픽업에 가지도 않았는데 드랍오프로 가는
        # 것이 이것 때문이었다.
        status = getattr(future.result(), 'status', None)
        ok = status == GoalStatus.STATUS_SUCCEEDED
        with self.lock:
            # 새 목표가 이 목표를 선점했다. Nav2의 CANCELED/ABORTED는 옛 목표의
            # 결과이지 현재 RMF 실행의 실패가 아니다.
            if generation != self.goal_generation:
                return
            self.goal_handle = None
        if ok:
            self.node.get_logger().info(f'[{self.name}] 도착했습니다.')
            report(robot=self.name, event='navigate_done')
        else:
            self.node.get_logger().error(
                f'[{self.name}] 목적지에 닿지 못했습니다 (Nav2 status '
                f'{status}). 도착 반경이 코스트맵 한 칸보다 촘촘하면 영영 '
                f'못 맞춥니다.')
            report(robot=self.name, event='navigate_failed', status=status)
        self.finish(generation, execution)

    def finish(self, generation, execution):
        """RMF 에 이 명령이 끝났다고 알린다."""
        with self.lock:
            if (generation != self.goal_generation or
                    self.execution is not execution):
                return
            self.execution = None
        execution.finished()

    def stop(self, activity):
        """RMF 가 멈추라고 한다. 지금 가고 있는 것만 멈춘다."""
        with self.lock:
            execution = self.execution
            handle = self.goal_handle
        if execution is None or not execution.identifier.is_same(activity):
            return
        self.node.get_logger().info(f'[{self.name}] 멈춥니다.')
        if handle is not None:
            handle.cancel_goal_async()
        with self.lock:
            self.goal_generation += 1
            self.execution = None
            self.goal_handle = None
            if self.dispenser_execution is execution:
                self.dispenser_execution = None
                self.dispenser_request_guid = None
                self.dispenser_target_guid = None

    def execute_action(self, category, description, execution):
        """armLoad 를 해당 픽업 자리의 RMF 워크셀 요청으로 바꾼다."""
        seconds = 1.0
        target_guid = None
        item_type = 'policy_1'
        quantity = 1
        if isinstance(description, dict):
            target_guid = description.get('target_guid')
            item_type = str(description.get('item_type') or 'policy_1')
            quantity = max(1, int(description.get('quantity') or 1))
            for key, scale in (('seconds', 1.0),
                               ('unix_millis_action_duration_estimate',
                                0.001)):
                value = description.get(key)
                if isinstance(value, (int, float)) and value > 0:
                    seconds = float(value) * scale
                    break
        if category != 'armLoad' or not target_guid:
            self.node.get_logger().error(
                f'[{self.name}] 동작 [{category}]에 워크셀 위치가 없습니다.')
            report(robot=self.name, event='action_failed', category=category)
            execution.finished()
            return

        with self.lock:
            self.execution = execution
            self.dispenser_execution = execution
            self.dispenser_target_guid = str(target_guid)
            self.dispenser_item = item_type
            self.dispenser_quantity = quantity
            self.dispenser_attempt = 0
        report(robot=self.name, event='action_start',
               category=category, seconds=seconds)
        self.send_workcell_request()

    def send_workcell_request(self):
        """워크셀에 적재를 부탁한다. 다시 부탁할 때도 여기로 온다."""
        request_guid = f'{self.name}-{uuid.uuid4()}'
        with self.lock:
            if self.dispenser_execution is None:
                return
            self.dispenser_request_guid = request_guid
            self.dispenser_attempt += 1
            attempt = self.dispenser_attempt
            target_guid = self.dispenser_target_guid
            item_type = self.dispenser_item
            quantity = self.dispenser_quantity
        again = '' if attempt == 1 else f' (다시 {attempt - 1}번째)'
        self.node.get_logger().info(
            f'[{self.name}] 동작 [armLoad] → 워크셀 [{target_guid}] 요청'
            f'{again} ({request_guid})')
        request = DispenserRequest()
        request.time = self.node.get_clock().now().to_msg()
        request.request_guid = request_guid
        request.target_guid = str(target_guid)
        request.transporter_type = self.name
        item = DispenserRequestItem()
        item.type_guid = item_type
        item.quantity = quantity
        item.compartment_name = 'pinky_tray'
        request.items = [item]
        self.dispenser_requests.publish(request)

    def on_dispenser_result(self, result):
        """워크셀의 답. 셋 중 하나이고, **셋 다 반드시 처리해야 한다.**

        예전에는 실패를 오류로 적고 그냥 돌아갔다. 그러면 RMF 는 이 동작이
        끝나기를 영원히 기다리고 로봇은 그 자리에 선 채로 남는다 — 오류
        팝업도 안 뜨고, 로그를 열어 보기 전에는 아무도 모른다. 2026-08-17 에
        핑키가 픽업3 에서 그렇게 멈춰 있었다.
        """
        with self.lock:
            if (result.request_guid != self.dispenser_request_guid or
                    self.dispenser_execution is None):
                return
            target = self.dispenser_target_guid
            if result.status == DispenserResult.ACKNOWLEDGED:
                self.node.get_logger().info(
                    f'[{self.name}] 워크셀 [{target}]이 요청을 받았습니다.')
                return
            attempt = self.dispenser_attempt
            retry = (result.status != DispenserResult.SUCCESS
                     and attempt <= WORKCELL_RETRIES)
            self.dispenser_request_guid = None
            if retry:
                # 다시 부탁할 것이라 execution 은 그대로 쥐고 있는다.
                execution = None
            else:
                execution = self.dispenser_execution
                self.dispenser_execution = None
                self.dispenser_target_guid = None
                if self.execution is execution:
                    self.execution = None

        # 락 밖에서 알린다. 여기서 부르는 것들이 다시 락을 잡는다.
        if result.status == DispenserResult.SUCCESS:
            self.node.get_logger().info(f'[{self.name}] 워크셀 [{target}] 동작 완료.')
            report(robot=self.name, event='action_done', category='armLoad')
            execution.finished()
            return

        self.node.get_logger().error(
            f'[{self.name}] 워크셀 [{target}] 요청 실패 (status={result.status})')
        if retry:
            # 늘 영구적인 실패가 아니다. 로봇이 도착 직후 마지막 자세를 다듬는
            # 동안 걸리면 몇 초 뒤에는 멀쩡히 된다. 한 번 실패했다고 작업을
            # 접으면 멀쩡한 픽업이 버려진다.
            self.node.get_logger().warning(
                f'[{self.name}] {WORKCELL_RETRY_SECONDS:.0f}초 뒤에 다시 '
                f'부탁합니다 ({attempt}/{WORKCELL_RETRIES}).')
            self.retry_workcell_later()
            return
        self.node.get_logger().error(
            f'[{self.name}] 워크셀 [{target}] 요청이 {WORKCELL_RETRIES}번 다시 '
            '부탁해도 계속 실패했습니다. 작업을 취소합니다 — 그냥 두면 로봇이 '
            '그 자리에 영원히 서 있습니다.')
        report(robot=self.name, event='action_failed', category='armLoad')
        self.cancel_current_task()

    def retry_workcell_later(self):
        """조금 뒤에 다시 부탁한다. 콜백 안에서 자므로 타이머를 쓴다."""
        timer = None

        def again():
            timer.cancel()
            self.send_workcell_request()

        timer = self.node.create_timer(WORKCELL_RETRY_SECONDS, again)

    def cancel_current_task(self):
        """이 로봇이 하던 RMF 작업을 취소한다.

        RMF 에 "이 동작이 실패했다" 고 말할 방법이 없다 — EasyFullControl 의
        `CommandExecution` 에는 `finished()` 만 있고 `okay()` 는 읽기 전용이다
        (RMF 가 우리에게 알리는 쪽이다). `finished()` 를 부르면 성공한 척이
        되어 빈 수납함으로 다음 자리에 간다.

        그래서 작업을 취소한다. 로봇이 풀려나고, 화면에도 취소로 보인다.
        아무 말 없이 서 있는 것보다 낫다.
        """
        task_id = self.current_task_id
        if not task_id:
            self.node.get_logger().error(
                f'[{self.name}] 취소할 작업 번호를 모릅니다. 로봇이 이 자리에 '
                '남습니다 — 화면에서 작업을 취소해 주세요.')
            return
        request = ApiRequest()
        request.request_id = f'{self.name}-cancel-{str(uuid.uuid4())[:8]}'
        request.json_msg = json.dumps(
            {'type': 'cancel_task', 'task_id': task_id}, ensure_ascii=False)
        self.task_api.publish(request)
        self.node.get_logger().error(
            f'[{self.name}] 작업 [{task_id}] 취소를 보냈습니다.')

    # ── RMF 에 알리는 쪽 ────────────────────────────────────────────────

    def read_state(self):
        """TF 에서 지금 자리를 읽는다. AMCL 이 map -> odom 을 낸다."""
        try:
            base_frame = f'{self.namespace}/base_footprint'
            tf = self.tf_buffer.lookup_transform(
                'map', base_frame,
                rclpy.time.Time(), timeout=Duration(seconds=0.2))
        except Exception:
            return None
        t = tf.transform.translation
        return rmf_easy.RobotState(
            MAP_NAME,
            [t.x, t.y, yaw_of(tf.transform.rotation)],
            # 시뮬레이터에는 배터리가 없다. 실물로 가면 여기에 진짜 값을 넣는다.
            1.0,
        )

    def update(self):
        state = self.read_state()
        if state is None:
            return
        if self.update_handle is None:
            if time.monotonic() < RobotAdapter.next_registration_at:
                return
            # 처음 자리를 알게 된 순간에 RMF 에 등록한다. 자리를 모르는 채로
            # 넣으면 RMF 가 그 로봇을 어디에 둘지 모른다.
            handle = self.fleet_handle.add_robot(
                self.name, state,
                self.fleet_config.get_known_robot_configuration(self.name),
                self.callbacks)
            if handle is None:
                # 자리가 nav graph 에서 너무 멀면 RMF 가 받지 않는다. 다음에 다시
                # 해 본다 — AMCL 이 아직 안 잡혔을 수 있다. 같은 말을 0.1초마다
                # 되풀이하면 로그를 못 읽으므로 한 번만 적는다.
                if not self.warned:
                    self.warned = True
                    x, y, _ = state.position
                    self.node.get_logger().warn(
                        f'[{self.name}] 자리 ({x:.2f}, {y:.2f}) 가 nav graph 에서'
                        f' 멀어 RMF 가 받지 않습니다. AMCL 이 잡히면 다시 붙습니다.')
                return
            self.update_handle = handle
            RobotAdapter.next_registration_at = time.monotonic() + 3.0
            # add_robot의 C++ 측 등록 완료 콜백이 끝나기 전에 update()를 호출하면
            # Jazzy rmf_adapter가 SIGSEGV를 낸다. wall clock으로 여유를 둔다.
            self.update_ready_at = time.monotonic() + 2.0
            self.warned = False
            self.node.get_logger().info(f'[{self.name}] RMF 에 붙었습니다.')
            return
        if (self.update_ready_at is not None and
                time.monotonic() < self.update_ready_at):
            return
        with self.lock:
            activity = (
                self.execution.identifier if self.execution is not None else None)
        self.update_handle.update(state, activity)


def main(argv=sys.argv):
    rclpy.init(args=argv)
    rmf_adapter.init_rclcpp()
    parser = argparse.ArgumentParser(prog='$fleetName' + '_nav2_adapter')
    parser.add_argument('-c', '--config_file', required=True)
    parser.add_argument('-n', '--nav_graph', required=True)
    parser.add_argument('-s', '--use_sim_time', action='store_true')
    args = parser.parse_args(rclpy.utilities.remove_ros_args(argv)[1:])

    fleet_config = rmf_easy.FleetConfiguration.from_config_files(
        args.config_file, args.nav_graph)
    assert fleet_config, f'설정을 읽지 못했습니다: {args.config_file}'

    node = rclpy.node.Node(fleet_config.fleet_name + '_nav2_adapter')
    global _progress
    # 앱이 늦게 붙어도 마지막 소식은 받도록 남겨 둔다.
    _progress = node.create_publisher(StringMsg, PROGRESS_TOPIC, 10)
    adapter = Adapter.make(fleet_config.fleet_name + '_fleet_adapter')
    assert adapter, (
        'fleet adapter 를 만들지 못했습니다. '
        'rmf_traffic_schedule_primary 가 떠 있는지 확인하세요.')

    if args.use_sim_time:
        node.set_parameters(
            [Parameter('use_sim_time', Parameter.Type.BOOL, True)])
        adapter.node.use_sim_time()

    adapter.start()
    time.sleep(1.0)

    tf_buffer = tf2_ros.Buffer()
    tf2_ros.TransformListener(tf_buffer, node)

    fleet_handle = adapter.add_easy_fleet(fleet_config)

    robots = []
    for index, name in enumerate(fleet_config.known_robots):
        namespace = ROBOT_NAMESPACES.get(name)
        if namespace is None:
            node.get_logger().warn(
                f'[{name}] 의 ROS 네임스페이스를 모릅니다. 건너뜁니다.')
            continue
        robots.append(
            RobotAdapter(
                name, namespace, node, tf_buffer, fleet_handle, fleet_config,
                index * 3.0))

    if not robots:
        node.get_logger().error('이을 로봇이 없습니다.')

    period = fleet_config.update_interval.total_seconds()
    node.create_timer(period, lambda: [robot.update() for robot in robots])

    node.get_logger().info(
        f'{fleet_config.fleet_name} 를 Nav2 에 이었습니다. '
        f'로봇 {len(robots)}대, {period:.2f}초마다 알립니다.')

    try:
        rclpy.spin(node)
    except KeyboardInterrupt:
        pass
    node.destroy_node()
    adapter.stop()
    # 신호로 끊길 때 rclpy 가 먼저 context 를 닫아 놓는다. 그때 또 부르면
    # 예외가 올라와, 멀쩡히 끝난 것이 죽은 것처럼 보인다.
    if rclpy.ok():
        rclpy.shutdown()


if __name__ == '__main__':
    main(sys.argv)
''';
}

/// 프로젝트의 Nav2 를 한꺼번에 띄우는 launch.
///
/// 건물 지도(`map_server`)는 **하나만** 띄우고, 이동 로봇마다 제 Nav2 를
/// 붙인다. 로봇들은 `map` 프레임을 함께 쓰고 `<로봇>/odom` 만 서로 다르다.
/// [warnings] 는 파라미터를 다시 쓰면서 손대지 못한 것이다. 여기 주석으로
/// 적어 둔다 — 이 launch 가 안 뜰 때 사람이 제일 먼저 여는 파일이다.
/// [mapYamlName] 은 `nav2_map/` 안에서 `map_server` 가 띄울 파일 이름이다.
///
/// 기본은 도면에서 만든 `<맵>.yaml` 이다. 실물 건물에서 SLAM 으로 뜬 지도를
/// 올려 그것을 쓰기로 골랐으면 `<맵>_slam.yaml` 이 들어온다. 이 값을 못박아
/// 두었더니 SLAM 지도를 올려도 `map_server` 는 계속 도면 지도를 띄웠다.
String buildProjectNav2LaunchXml({
  required String mapName,
  required List<RmfProjectRobot> robots,
  String? fleetName,
  String? mapYamlName,
  List<String> warnings = const [],
}) {
  final mapYaml = (mapYamlName == null || mapYamlName.trim().isEmpty)
      ? '$mapName.yaml'
      : mapYamlName.trim();
  final usingSlam = mapYaml != '$mapName.yaml';
  final navigating = navigatingRobots(robots);
  final useSimTime = projectUsesSimTime(robots);
  final buffer = StringBuffer()
    ..writeln("<?xml version='1.0' ?>")
    ..writeln('<!--')
    ..writeln('  $mapName 프로젝트의 Nav2.')
    ..writeln('  rmf_control_ui 가 맵 프로젝트에서 생성했다.')
    ..writeln('')
    ..writeln('  건물 지도는 하나만 띄우고 이동 로봇마다 제 Nav2 를 붙인다.')
    ..writeln('  로봇들은 map 프레임을 함께 쓰고 <로봇>/odom 만 서로 다르다.')
    ..writeln('  그래서 한 TF 트리에 map → pinky_01/odom, map → pinky_02/odom')
    ..writeln('  이 나란히 선다.')
    ..writeln('')
    ..writeln('  지도는 nav2_map/$mapYaml 이다.');
  if (usingSlam) {
    buffer
      ..writeln('  로봇이 SLAM 으로 뜬 지도다. 원점을 사람이 RMF 월드에 맞춰')
      ..writeln('  두었다 — 그 값이 틀리면 로봇이 엉뚱한 데로 간다.');
  } else {
    buffer.writeln('  도면에서 만든 것이라 원점이 RMF 월드에 정확히 맞는다.');
  }
  buffer
    ..writeln('')
    ..writeln('  아직 RMF 와 이어지지 않았다. 지금은 Nav2 만 따로 돈다.');
  if (warnings.isNotEmpty) {
    buffer
      ..writeln('')
      ..writeln('  ── 확인이 필요한 것 ──────────────────────────────');
    for (final warning in warnings) {
      buffer.writeln('  · $warning');
    }
  }
  buffer
    ..writeln('-->')
    ..writeln('<launch>')
    ..writeln('  <arg name="map_dir" default="\$(dirname)"/>')
    // 실물 이동 로봇이 있으면 벽시계다. 자세한 까닭은 [projectUsesSimTime].
    ..writeln('  <arg name="use_sim_time" default="$useSimTime"/>')
    // relay 와 앱이 만나는 곳. 앱은 ROBOSAPIENS_SENSOR_DIR 환경 변수를 보고
    // 같은 자리를 읽는다.
    ..writeln(
      '  <arg name="sensor_dir"'
      ' default="\$(env ROBOSAPIENS_SENSOR_DIR /tmp/robosapiens_sensors)"/>',
    )
    ..writeln('')
    ..writeln('  <!-- 건물 지도. 로봇들이 함께 본다. -->')
    ..writeln('  <node pkg="nav2_map_server" exec="map_server"')
    ..writeln('        name="map_server" output="screen">')
    ..writeln(
      '    <param name="yaml_filename" '
      'value="\$(var map_dir)/nav2_map/$mapYaml"/>',
    )
    ..writeln('    <param name="use_sim_time" value="\$(var use_sim_time)"/>')
    // `/map` 은 RMF 의 building_map_server 가 이미 쓴다. 같이 쓰면 한 토픽에
    // OccupancyGrid 와 BuildingMap 이 함께 올라가 아무도 제대로 못 읽는다.
    ..writeln('    <param name="topic_name" value="$nav2MapTopicName"/>')
    ..writeln('  </node>')
    ..writeln('  <node pkg="nav2_lifecycle_manager" exec="lifecycle_manager"')
    ..writeln('        name="lifecycle_manager_map" output="screen">')
    // 관리자는 sim 시간을 쓰지 않는다. 위와 같은 이유다.
    ..writeln('    <param name="use_sim_time" value="false"/>')
    ..writeln('    <param name="autostart" value="true"/>')
    // 지도 파일을 읽는 데 5초가 넘어 `get_state` 응답이 늦는 일이 실제로
    // 있었다. 그러면 map_server 가 inactive 로 남고, 증상은 세 단계 떨어진
    // 곳(로봇이 안 움직인다)에 뜬다. 실행 스크립트의
    // `ensure_map_server_active` 가 뒤늦게 되살리지만, 애초에 안 넘어가는
    // 편이 낫다.
    ..writeln(
      '    <param name="service_timeout" '
      'value="$nav2LifecycleServiceTimeoutSeconds"/>',
    )
    ..writeln(
      '    <param name="bond_timeout" '
      'value="$nav2LifecycleBondTimeoutSeconds"/>',
    )
    ..writeln('    <param name="node_names" value="[map_server]"/>')
    ..writeln('  </node>');
  if (navigating.isEmpty) {
    buffer
      ..writeln('')
      ..writeln('  <!-- Gazebo 로 돌리는 이동 로봇이 없다. 지도만 띄운다. -->');
  }
  for (final robot in navigating) {
    buffer
      ..writeln('')
      ..writeln('  <!-- ${robot.robotId} · ${robot.displayName} -->')
      // include 의 <arg> 는 <group> 으로 감싸지 않으면 바깥으로 샌다.
      ..writeln('  <group>')
      ..writeln(
        '    <include file="\$(var map_dir)/'
        '${robotDirectoryName(robot)}/nav2.launch.xml">',
      )
      ..writeln('      <arg name="use_sim_time" value="\$(var use_sim_time)"/>')
      ..writeln('    </include>')
      ..writeln('  </group>');
  }
  if (navigating.isNotEmpty && fleetName != null) {
    buffer
      ..writeln('')
      ..writeln('  <!-- RMF 와 Nav2 를 잇는다. 이것이 없으면 RMF 가 배차해도')
      ..writeln('       로봇이 안 움직인다.')
      ..writeln('')
      ..writeln('       RViz 도 이것에 매달려 있다. 경로(Lane·Waypoint)를 그리는')
      ..writeln('       /nav_graphs 와 로봇을 그리는 /fleet_states 를 내는 것이')
      ..writeln('       RMF 안에서 이 어댑터(FleetUpdateHandle) 하나뿐이다.')
      ..writeln('       이것이 죽으면 RViz 는 도면만 남고 텅 빈다.')
      ..writeln('')
      ..writeln('       네이티브 RMF 라이브러리 오류나 시작 순서 문제로 종료되더라도')
      ..writeln('       계속 다시 띄운다. 실행 스크립트는 프로세스뿐 아니라')
      ..writeln('       /fleet_states 의 실제 로봇 등록 상태도 별도로 감시한다. -->')
      // ROS 패키지에 든 노드가 아니라 이 프로젝트가 만든 스크립트라 <node> 로는
      // 못 돌린다. <executable> 은 아무 명령이나 그대로 띄운다.
      //
      ..writeln('  <executable output="screen"')
      // 무한히 되살리지는 않는다. 설정이 잘못돼 뜨자마자 죽는 경우, 끝없이
      // 되살리면 로그가 같은 역추적으로 덮여 **진짜 첫 오류가 묻힌다.** 몇 번
      // 해 보고 그래도 안 되면 멈추고, 실행 스크립트의 감시가 그것을 알린다.
      ..writeln('              respawn="true" respawn_delay="5.0"')
      ..writeln('              respawn_max_retries="10"')
      ..writeln(
        '              cmd="python3 \$(var map_dir)/${mapName}_nav2_adapter.py'
        ' -c \$(var map_dir)/${fleetName}_config.yaml'
        ' -n \$(var map_dir)/nav_graphs/0.yaml'
        // `-s` 는 어댑터를 sim 시계로 돌린다. 실물 로봇의 TF 는 벽시계로 오므로
        // 이것이 박혀 있으면 어댑터가 로봇 자리를 영영 못 읽는다.
        '${useSimTime ? ' -s' : ''}"/>',
      )
      ..writeln('')
      ..writeln('  <!-- 설비 로봇을 RMF 워크셀로 잇는다. 이것이 없으면 로봇이')
      ..writeln('       픽업 자리에 닿아도 RMF 가 답을 못 받아 영원히')
      ..writeln('       기다린다 — 오류는 안 나고 작업만 멈춘다. -->')
      ..writeln('  <executable output="screen"')
      ..writeln(
        '              cmd="python3 \$(var map_dir)/${mapName}_workcell.py"/>',
      )
      ..writeln('')
      ..writeln('  <!-- 라이다·카메라를 앱이 읽을 수 있게 파일로 내려 준다. -->')
      ..writeln('  <executable output="screen"')
      ..writeln(
        '              cmd="python3 \$(var map_dir)/${mapName}_sensor_relay.py'
        ' -o \$(var sensor_dir)"/>',
      );
  }
  buffer.writeln('</launch>');
  return buffer.toString();
}

/// 지도 그림의 픽셀을 RMF 월드 좌표(m)로 옮긴다.
///
/// RMF 지도 생성기(`rmf_building_map_tools`)는 building.yaml 에 적힌 픽셀을
/// 그대로 `(px × 축척, −py × 축척)` 으로 옮긴다. 원점은 **그림의 왼쪽 위**이고
/// y 는 위로 갈수록 커진다. Gazebo 월드도 nav graph 도 이 좌표를 쓰므로,
/// 로봇을 올릴 자리도 반드시 이 좌표로 적어야 한다.
///
/// 화면에 사람이 읽으라고 보여 주는 바닥 좌표는 바닥 왼쪽 **아래**가 원점이라
/// y 부호가 반대다. 그 값을 spawn 좌표로 쓰면 로봇이 건물 밖 허공에 놓여
/// 끝없이 떨어진다.
({double x, double y}) rmfWorldFromPixel(
  double px,
  double py,
  double metersPerPixel,
) => (x: px * metersPerPixel, y: -py * metersPerPixel);

/// [rmfWorldFromPixel] 의 역. 토픽이 준 미터를 화면 픽셀로 되돌린다.
({double dx, double dy}) pixelFromRmfWorld(
  double x,
  double y,
  double metersPerPixel,
) => (dx: x / metersPerPixel, dy: -y / metersPerPixel);

/// 등록된 로봇의 올릴 자리를 지금 지도에서 다시 계산한다.
///
/// spawn 좌표는 언제나 자리 Waypoint 에서 나온다. 예전 판은 화면에 보여 주는
/// 바닥 좌표(바닥 왼쪽 아래가 원점, y 는 위로)를 그대로 넣었는데, RMF 는 그림
/// 왼쪽 위가 원점이고 y 가 아래로 갈수록 음수다. 그렇게 저장된 프로젝트는 로봇을
/// 건물 밖 허공에 올려서 끝없이 떨어뜨렸다. 사람에게 다시 등록하라고 시키는
/// 대신 여기서 고쳐 준다.
///
/// [pixelOf] 는 로봇이 선 Waypoint 의 지도 픽셀을 돌려준다. 자리를 못 찾으면
/// null 을 돌려주고, 그런 로봇은 건드리지 않는다 — 지도가 아직 안 올라왔을 수
/// 있고, 그때 지워 버리면 멀쩡한 등록이 좌표를 잃는다.
///
/// **설비 로봇은 언제나 자리 Waypoint 를 따라온다.** 이동 로봇만 등록해 둔 유효한
/// 시작 좌표를 지킨다. 까닭은 아래 `hasExplicitSpawn` 자리에 적었다.
///
/// [headingRadiansOf] 는 로봇이 선 자리 Waypoint 에 적힌 방향(라디안)을 돌려준다.
/// 자리에 방향이 없으면 null 이다.
///
/// **등록에 넣은 방향이 이긴다.** 자리 방향은 등록이 비어 있을 때(0)만 채워
/// 넣는 기본값이다.
///
/// 처음에는 반대였다 — 자리가 이기게 했더니, 사람이 로봇 등록에서 90도를
/// 넣어 저장해도 다음에 열면 늘 자리의 180도로 돌아왔다. 저장이 안 된 것처럼
/// 보이지만 실제로는 저장된 값을 덮어쓴 것이라, 어디를 고쳐야 할지 알 수 없다.
///
/// 로봇마다 방향을 달리 줄 이유도 있다. 같은 충전대라도 로봇이 서는 쪽이
/// 다르거나, 나가는 길이 달라 미리 돌려 세워 두고 싶을 때다.
///
/// 등록이 0 이면 "안 정했다" 로 본다. [RmfProjectRobot.spawnHeading] 이
/// non-nullable 이라 "0도로 정함" 과 "안 정함" 을 가릴 수 없다. 둘 중에는
/// 자리 값을 쓰는 편이 낫다 — 0도가 진짜로 필요하면 자리 방향을 0 으로 두면
/// 되고, 자리에도 없으면 어차피 0 이다.
///
/// 바꿀 것이 없으면 받은 목록을 그대로 돌려준다. 부르는 쪽이 `identical` 로
/// 달라졌는지 가려서 쓸데없이 다시 그리거나 저장하지 않게 한다.
List<RmfProjectRobot> robotsWithMapSpawnPoints(
  List<RmfProjectRobot> robots,
  ({double dx, double dy})? Function(RmfProjectRobot robot) pixelOf,
  double metersPerPixel, {
  double? Function(RmfProjectRobot robot)? headingRadiansOf,
}) {
  if (metersPerPixel <= 0) return robots;
  var changed = false;
  final result = <RmfProjectRobot>[];
  for (final robot in robots) {
    // 자리에 적힌 방향은 좌표와 따로 본다. 좌표는 "따로 고른 시작 자리" 라는
    // 예외가 있지만(아래 `hasExplicitSpawn`), 방향에는 그런 예외가 없다 —
    // 시작 자리를 따로 골랐더라도 충전 단자가 보는 쪽은 자리가 정한다.
    final mapHeading = headingRadiansOf?.call(robot);
    RmfProjectRobot withHeading(RmfProjectRobot value) {
      if (mapHeading == null) return value;
      // 등록에 넣은 값이 이긴다. 자리 방향은 등록이 비어 있을 때만 채운다 —
      // 안 그러면 사람이 저장한 각도가 다음에 열 때마다 사라진다.
      if (value.spawnHeading.abs() > 1e-6) return value;
      if ((value.spawnHeading - mapHeading).abs() < 1e-6) return value;
      changed = true;
      return value.withSpawn(
        spawnX: value.spawnX,
        spawnY: value.spawnY,
        spawnHeading: mapHeading,
      );
    }

    final pixel = pixelOf(robot);
    if (pixel == null) {
      result.add(withHeading(robot));
      continue;
    }
    final spawn = rmfWorldFromPixel(pixel.dx, pixel.dy, metersPerPixel);
    // 유효한 RMF 좌표가 충전 자리와 다르면 사용자가 별도의 시작 Waypoint를
    // 선택한 것이다. 충전은 작업 후 복귀 지점이고 spawn은 Gazebo 최초 위치라
    // 둘이 같을 필요가 없다. 예전 좌표계 버그는 화면 y를 그대로 저장해 spawnY가
    // 양수였으므로 그 값만 아래에서 현재 지도 기준으로 교정한다.
    //
    // **이동 로봇만 그렇다.** 설비 로봇은 그 Waypoint 에 붙박여 있어서 "따로 고른
    // 시작 자리" 라는 것이 없다. 등록 좌표와 설비 Waypoint 가 다르면 둘 중 하나는
    // 거짓이고, 배포에 나가는 것은 등록 좌표다 — 설비 Waypoint 를 옮겨 팔을 떼어
    // 놓았는데 팔이 옛 자리에 그대로 서는 것이 이 예외 때문이었다. 그때 `자리
    // 맞추기` 는 여기서 막혀 0대를 고치고도 고쳤다고 말했다.
    final hasExplicitSpawn =
        robot.isMobile &&
        robot.spawnX != null &&
        robot.spawnY != null &&
        robot.spawnY! <= 0;
    if (hasExplicitSpawn) {
      result.add(withHeading(robot));
      continue;
    }
    if (robot.spawnX != null &&
        robot.spawnY != null &&
        (spawn.x - robot.spawnX!).abs() < 1e-6 &&
        (spawn.y - robot.spawnY!).abs() < 1e-6) {
      result.add(withHeading(robot));
      continue;
    }
    changed = true;
    result.add(withHeading(robot.withSpawn(spawnX: spawn.x, spawnY: spawn.y)));
  }
  return changed ? result : robots;
}

/// 로봇 하나가 쓰는 디렉터리 이름. `robots/<로봇 ID>`.
///
/// 로봇마다 제 디렉터리를 두면 한 대를 빼거나 옮길 때 그 디렉터리만 보면 된다.
/// 파일 이름으로 쓸 수 없는 글자는 걷어낸다 — 로봇 ID 에 슬래시가 들어가면
/// 엉뚱한 곳에 디렉터리가 생긴다.
String robotDirectoryName(RmfProjectRobot robot) {
  final safe = robot.robotId.replaceAll(RegExp(r'[^a-zA-Z0-9가-힣_-]'), '_');
  return 'robots/${safe.isEmpty ? robot.gzName : safe}';
}

/// 이 맵이 RMF 월드에서 차지하는 범위(m). RViz 카메라를 여기에 맞춘다.
typedef RmfMapExtent = ({double minX, double maxX, double minY, double maxY});

/// RViz 가 nav graph 를 그리는 굵기의 기본값(m). `visualization.launch.xml` 값.
///
/// RMF 데모(창고 수십 미터)에 맞춘 값이다. 2~3m 짜리 실험실 도면에서는 Lane
/// 하나가 건물 폭의 1/5 이라, 스무 개가 겹쳐 덩어리로 보인다.
const double defaultNavGraphLaneWidth = .5;

/// 시각화 노드가 받는 가장 가는 Lane(m).
///
/// `NavGraphVisualizer.cpp` 가 `std::max(0.1, lane_width)` 로 깎는다. 더 가늘게
/// 적어도 0.1m 로 그려지므로, 화면에서 먼저 알려 준다.
const double minNavGraphLaneWidth = .1;

/// nav graph 를 얼마나 굵게 그릴까(m).
///
/// [manual] 이 있으면 그 값이다. 없으면 **로봇 폭**으로 그린다 — "이 Lane 을 이
/// 로봇이 지난다" 가 그림 그대로 보이는 것이 어림값보다 낫다.
double navGraphLaneWidth({required double robotWidthMeters, double? manual}) {
  final value = manual ?? robotWidthMeters;
  if (!value.isFinite || value <= 0) return defaultNavGraphLaneWidth;
  return value.clamp(minNavGraphLaneWidth, 2.0);
}

/// 바닥 그림이 오는 곳. `rmf_visualization_floorplans` 가 내는 이름이다.
///
/// **밑줄이 없다.** RMF 가 함께 주는 `rmf.rviz` 는 `/floor_plan` 을 보고 있어서
/// 도면이 영영 안 온다. 우리가 설정을 따로 만드는 첫 번째 이유다.
const String rmfFloorplanTopic = '/floorplan';

/// 로봇 하나에 배정하는 색과 그 색의 이름.
typedef RobotColor = ({int r, int g, int b, String label});

/// 로봇별 색. 라이다 점과 RViz 의 로봇 표시가 **같은 색**을 쓴다. 전부 같은
/// 색이면 스캔이 겹쳤을 때 어느 로봇이 무엇을 보고 있는지 구분할 수 없다.
///
/// 배경(48;48;48)·격자(130;130;130)·흑백 지도 위에서 서로 갈리는 색만 골랐다.
/// 첫 색은 원래 라이다에 쓰던 주황이라 로봇이 한 대뿐이면 그림이 그대로다.
const List<RobotColor> robotPalette = [
  (r: 255, g: 85, b: 0, label: '주황'),
  (r: 0, g: 170, b: 255, label: '하늘'),
  (r: 0, g: 255, b: 128, label: '연두'),
  (r: 255, g: 0, b: 255, label: '자홍'),
  (r: 255, g: 220, b: 0, label: '노랑'),
  (r: 170, g: 85, b: 255, label: '보라'),
];

/// 색 하나를 쓰는 곳이 두 군데다. 표기를 손으로 두 번 적으면 언젠가 어긋난다
/// — 값은 팔레트 한 곳에만 두고 표기만 여기서 만든다.
extension RobotColorFormat on RobotColor {
  /// RViz 설정의 `Color:` 표기.
  String get rviz => '$r; $g; $b';

  /// launch `<set_parameter>` 가 fleet_states_visualizer 에 넘기는 표기.
  /// 그쪽은 `[r, g, b]` 정수 배열을 읽는다.
  String get launchList => '[$r, $g, $b]';
}

/// [index] 번째 로봇의 색. 로봇이 팔레트보다 많으면 처음부터 돈다.
RobotColor robotColorFor(int index) =>
    robotPalette[index % robotPalette.length];

/// 이 프로젝트를 볼 RViz 설정.
///
/// RMF 가 함께 주는 `rmf_visualization_schedule/config/rmf.rviz` 를 그대로 쓰면
/// **검은 화면**이 된다. 그 파일은 office 데모를 보라고 맞춰 둔 것이다.
///
///   1. 카메라가 (17.7, -20.0) 을 가운데 놓고 폭 27m 를 본다. 우리 도면은
///      원점 둘레 두세 미터라 통째로 화면 밖이다.
///   2. 바닥 그림을 `/floor_plan` 에서 찾는다. 실제로 오는 이름은
///      `/floorplan` 이다(밑줄 없음). 이름이 어긋나 도면이 안 온다.
///   3. Grid 가 꺼져 있다. 그래서 카메라가 엉뚱한 데를 봐도 아무 단서가 없이
///      그냥 까맣다 — 고장 난 것과 구분되지 않는다.
///
/// 그래서 맵마다 우리가 만든다. 카메라는 이 맵의 [extent] 가운데를 보고, 토픽
/// 이름은 실제로 오는 것을 쓰고, Grid 는 켜 둔다.
///
/// [extent] 가 없으면(축척이나 Floor 가 아직 없으면) 원점 둘레를 넓게 본다.
String buildProjectRvizConfig({
  required String mapName,
  List<RmfProjectRobot> robots = const [],
  RmfMapExtent? extent,
}) {
  // 카메라가 볼 창 크기를 이만큼으로 잡고 배율을 정한다. 실제 창이 이보다
  // 크면 더 넓게 보일 뿐이라 지도가 잘리지 않는다.
  const viewportWidth = 1600.0;
  const viewportHeight = 900.0;
  // 도면 둘레를 조금 남긴다. 벽이 화면 가장자리에 딱 붙으면 답답하다.
  const margin = 1.25;

  final centerX = extent == null ? 0.0 : (extent.minX + extent.maxX) / 2;
  final centerY = extent == null ? 0.0 : (extent.minY + extent.maxY) / 2;
  final spanX = extent == null ? 0.0 : (extent.maxX - extent.minX).abs();
  final spanY = extent == null ? 0.0 : (extent.maxY - extent.minY).abs();
  // TopDownOrtho 의 `Scale` 은 1m 가 몇 픽셀인가다. 크면 확대다.
  final scale = spanX <= 0 || spanY <= 0
      ? 50.0
      : math
            .min(
              viewportWidth / (spanX * margin),
              viewportHeight / (spanY * margin),
            )
            .clamp(2.0, 500.0);
  // 격자는 지도를 덮고도 남게 깐다. 배경만 있는 화면과 구분되는 것이 목적이다.
  final gridCells = spanX <= 0 || spanY <= 0
      ? 40
      : (math.max(spanX, spanY).ceil() + 6).clamp(10, 200);

  final buffer = StringBuffer()
    ..writeln('# $mapName 프로젝트 RViz 설정.')
    ..writeln('# rmf_control_ui 가 맵 프로젝트에서 생성했다. 손으로 고치면')
    ..writeln('# 다음 저장 때 덮어써진다.')
    ..writeln('#')
    ..writeln('# 카메라는 이 맵의 가운데(${_n(centerX)}, ${_n(centerY)})를 본다.')
    ..writeln('# RMF 가 주는 rmf.rviz 는 office 데모 자리를 보고 있어 이 도면이')
    ..writeln('# 화면 밖이었다. 바닥 그림 토픽 이름도 거기서는 어긋나 있다.')
    ..writeln('Panels:')
    ..writeln('  - Class: rviz_common/Displays')
    ..writeln('    Name: Displays')
    ..writeln('    Property Tree Widget:')
    ..writeln('      Expanded: ~')
    ..writeln('      Splitter Ratio: 0.5')
    ..writeln('    Tree Height: 600')
    ..writeln('  - Class: rviz_common/Views')
    ..writeln('    Name: Views')
    ..writeln('Visualization Manager:')
    ..writeln('  Class: ""')
    ..writeln('  Displays:');

  // 격자. 아무 데이터가 없어도 이것만은 그려진다 — 화면이 살아 있다는 표시다.
  buffer
    ..writeln('    - Class: rviz_default_plugins/Grid')
    ..writeln('      Name: 격자 (1m)')
    ..writeln('      Enabled: true')
    ..writeln('      Alpha: 0.35')
    ..writeln('      Cell Size: 1')
    ..writeln('      Color: 130; 130; 130')
    ..writeln('      Line Style:')
    ..writeln('        Line Width: 0.03')
    ..writeln('        Value: Lines')
    ..writeln('      Normal Cell Count: 0')
    ..writeln('      Offset:')
    ..writeln('        X: 0')
    ..writeln('        Y: 0')
    ..writeln('        Z: 0')
    ..writeln('      Plane: XY')
    ..writeln('      Plane Cell Count: $gridCells')
    ..writeln('      Reference Frame: <Fixed Frame>')
    ..writeln('      Value: true');

  void mapDisplay({
    required String name,
    required String topic,
    required double alpha,
    required bool enabled,
  }) {
    buffer
      ..writeln('    - Class: rviz_default_plugins/Map')
      ..writeln('      Name: $name')
      ..writeln('      Enabled: $enabled')
      ..writeln('      Alpha: $alpha')
      ..writeln('      Color Scheme: map')
      ..writeln('      Draw Behind: true')
      ..writeln('      Topic:')
      ..writeln('        Depth: 5')
      // 지도는 한 번 내고 만다. Volatile 로 받으면 늦게 붙은 RViz 는 영영
      // 아무것도 못 받는다 — rmf.rviz 가 그렇게 돼 있다.
      ..writeln('        Durability Policy: Transient Local')
      ..writeln('        History Policy: Keep Last')
      ..writeln('        Reliability Policy: Reliable')
      ..writeln('        Value: $topic')
      ..writeln('      Use Timestamp: false')
      ..writeln('      Value: true');
  }

  void markerArray({
    required String name,
    required String topic,
    required bool transientLocal,
    bool enabled = true,
  }) {
    buffer
      ..writeln('    - Class: rviz_default_plugins/MarkerArray')
      ..writeln('      Name: $name')
      ..writeln('      Enabled: $enabled')
      ..writeln('      Namespaces:')
      ..writeln('        {}')
      ..writeln('      Topic:')
      ..writeln('        Depth: 10')
      ..writeln(
        '        Durability Policy: '
        '${transientLocal ? 'Transient Local' : 'Volatile'}',
      )
      ..writeln('        History Policy: Keep Last')
      ..writeln('        Reliability Policy: Reliable')
      ..writeln('        Value: $topic')
      ..writeln('      Value: true');
  }

  mapDisplay(
    name: '도면 (RMF 바닥 그림)',
    topic: rmfFloorplanTopic,
    alpha: 0.9,
    enabled: true,
  );
  if (projectUsesNav2(robots)) {
    // 로봇이 실제로 위치를 맞추는 지도다. 도면과 겹쳐 놓으면 두 장이 포개져
    // 무엇이 무엇인지 알 수 없으므로 꺼 둔다. 도면과 어긋났는지 볼 때 켠다 —
    // 그때는 도면을 끄고 이것만 본다.
    mapDisplay(
      name: 'Nav2 지도 (도면과 견줄 때 켜세요)',
      topic: nav2MapTopic,
      alpha: 0.7,
      enabled: false,
    );
  }
  markerArray(
    name: 'Nav graph (Lane·Waypoint)',
    topic: '/map_markers',
    transientLocal: true,
  );
  // 로봇 자리는 계속 새로 온다. `/fleet_markers` 에는 발행자가 둘인데(하나는
  // transient local, 하나는 volatile), transient local 로 받으면 volatile 쪽과
  // QoS 가 안 맞아 그 발행자의 값이 하나도 안 온다. volatile 로 받으면 둘 다
  // 받는다 — RViz 가 "incompatible QoS" 경고를 내던 것이 이것이다.
  markerArray(
    name: '로봇 (RMF fleet)',
    topic: '/fleet_markers',
    transientLocal: false,
  );
  markerArray(name: '예약 경로', topic: '/schedule_markers', transientLocal: false);
  markerArray(
    name: '문·리프트',
    topic: '/building_systems_markers',
    transientLocal: true,
  );

  // 라이다. 벽 높이를 낮춰 놓고 라이다가 벽을 넘겨다보는지 여기서 확인한다.
  //
  // 색은 로봇마다 다르게 준다. 색 이름을 표시 이름에도 적어 둬야 화면의 점과
  // 왼쪽 목록의 로봇을 눈으로 이을 수 있다.
  final scanning = navigatingRobots(robots);
  for (var i = 0; i < scanning.length; i++) {
    final robot = scanning[i];
    final color = robotColorFor(i);
    buffer
      ..writeln('    - Class: rviz_default_plugins/LaserScan')
      ..writeln('      Name: 라이다 ${robot.robotId} (${color.label})')
      ..writeln('      Enabled: true')
      ..writeln('      Alpha: 1')
      ..writeln('      Color: ${color.rviz}')
      ..writeln('      Color Transformer: FlatColor')
      ..writeln('      Decay Time: 0')
      ..writeln('      Position Transformer: XYZ')
      ..writeln('      Size (m): 0.03')
      ..writeln('      Style: Points')
      ..writeln('      Topic:')
      ..writeln('        Depth: 5')
      ..writeln('        Durability Policy: Volatile')
      ..writeln('        History Policy: Keep Last')
      ..writeln('        Reliability Policy: Best Effort')
      ..writeln('        Value: /${robot.gzName}/scan')
      ..writeln('      Value: true');
  }

  // TF 는 꺼 둔다. 프레임이 로봇 수만큼 늘어나 지도를 덮는다. 위치가 안 맞을
  // 때 켜서 map → odom → base_link 가 이어져 있는지 본다.
  buffer
    ..writeln('    - Class: rviz_default_plugins/TF')
    ..writeln('      Name: TF (필요할 때 켜세요)')
    ..writeln('      Enabled: false')
    ..writeln('      Marker Scale: 0.4')
    ..writeln('      Show Arrows: true')
    ..writeln('      Show Axes: true')
    ..writeln('      Show Names: true')
    ..writeln('      Value: true')
    ..writeln('  Enabled: true')
    ..writeln('  Global Options:')
    ..writeln('    Background Color: 48; 48; 48')
    // RMF 도 Nav2 도 이 프레임을 쓴다. 마커와 지도가 모두 여기 실려 온다.
    ..writeln('    Fixed Frame: map')
    ..writeln('    Frame Rate: 30')
    ..writeln('  Name: root')
    ..writeln('  Tools:')
    ..writeln('    - Class: rviz_default_plugins/MoveCamera')
    ..writeln('    - Class: rviz_default_plugins/Select')
    ..writeln('    - Class: rviz_default_plugins/FocusCamera')
    ..writeln('    - Class: rviz_default_plugins/Measure')
    ..writeln('      Line color: 128; 128; 0')
    ..writeln('  Transformation:')
    ..writeln('    Current:')
    ..writeln('      Class: rviz_default_plugins/TF')
    ..writeln('  Value: true')
    ..writeln('  Views:')
    ..writeln('    Current:')
    ..writeln('      Class: rviz_default_plugins/TopDownOrtho')
    ..writeln('      Name: Current View')
    ..writeln('      Angle: 0')
    ..writeln('      Near Clip Distance: 0.01')
    ..writeln('      Scale: ${_n(scale.toDouble())}')
    ..writeln('      Target Frame: <Fixed Frame>')
    ..writeln('      X: ${_n(centerX)}')
    ..writeln('      Y: ${_n(centerY)}')
    ..writeln('      Value: TopDownOrtho (rviz_default_plugins)')
    ..writeln('    Saved: ~')
    ..writeln('Window Geometry:')
    ..writeln('  Displays:')
    ..writeln('    collapsed: false')
    ..writeln('  Height: ${viewportHeight.round()}')
    ..writeln('  Hide Left Dock: false')
    ..writeln('  Hide Right Dock: true')
    ..writeln('  Views:')
    ..writeln('    collapsed: true')
    ..writeln('  Width: ${viewportWidth.round()}')
    ..writeln('  X: 60')
    ..writeln('  Y: 60');
  return buffer.toString();
}

/// 로봇 한 대의 등록 정보. 사람이 읽고 확인하는 용도다.
String buildRobotInfoYaml(RmfProjectRobot robot) {
  final buffer = StringBuffer()
    ..writeln('# ${robot.robotId} · ${robot.displayName}')
    ..writeln('# rmf_control_ui 가 맵 프로젝트에서 생성했다. 손으로 고치면')
    ..writeln('# 다음 저장 때 덮어써진다. 고치려면 앱의 로봇 등록에서 고친다.')
    ..writeln('id: ${robot.robotId}')
    ..writeln('name: ${robot.displayName}')
    ..writeln('kind: ${robot.kind.storageValue} # ${robot.kind.label}')
    ..writeln(
      'data_source: ${robot.dataSource.name} # ${robot.dataSource.label}',
    )
    ..writeln('model: ${robot.model}')
    ..writeln('gz_name: ${robot.gzName} # 토픽 네임스페이스')
    ..writeln(
      robot.rosDomainId == null
          ? 'ros_domain_id: # 비었으면 프로젝트 기본값을 쓴다'
          : 'ros_domain_id: ${robot.rosDomainId} # 이 로봇만 따로 정했다',
    )
    ..writeln('zones: [${robot.zones.join(', ')}]');
  if (robot.chargerWaypoint != null) {
    buffer.writeln(
      robot.isMobile
          ? 'charger_waypoint: ${robot.chargerWaypoint} # 충전 자리'
          : 'station_waypoint: ${robot.chargerWaypoint} # 설비 자리',
    );
  }
  if (robot.spawnX != null && robot.spawnY != null) {
    buffer
      ..writeln('spawn_x: ${_n(robot.spawnX!)}')
      ..writeln('spawn_y: ${_n(robot.spawnY!)}');
  }
  buffer.writeln('spawn_heading: ${_n(robot.spawnHeading)}');
  return buffer.toString();
}

/// 이 로봇만 다른 도메인을 쓸 때 launch 맨 위에 넣을 줄.
///
/// `set_env` 는 그 뒤에 뜨는 프로세스의 환경을 바꾼다. 노드가 도메인을 정하는
/// 것은 `ROS_DOMAIN_ID` 환경 변수뿐이라, 이 방법 말고는 대마다 가를 수 없다.
///
/// 프로젝트 기본값을 쓰는 로봇은 아무것도 안 쓴다 — 빈 값을 넣으면 스크립트가
/// 내보낸 값을 덮어써서, 기본값을 고쳐도 안 따라온다.
String _robotDomainEnv(RmfProjectRobot robot) {
  final domain = robot.rosDomainId;
  if (domain == null) return '';
  return '  <!-- 이 로봇만 도메인 $domain 을 쓴다. 프로젝트 기본값이 아니다.\n'
      '       Gazebo 로봇이면 시뮬레이터와 같아야 한다 — 다르면 다리가 걸어 둔\n'
      '       토픽에 값이 하나도 안 온다. 오류는 안 난다. -->\n'
      '  <set_env name="ROS_DOMAIN_ID" value="$domain"/>\n';
}

/// 로봇 한 대만 Gazebo 에 올리는 launch.
///
/// 프로젝트 bringup 이 이 파일을 `<include>` 한다. 로봇을 빼려면 등록에서 지우면
/// 되고, 한 대만 따로 시험하려면 이 파일만 돌려 보면 된다.
String buildRobotSpawnLaunchXml(RmfProjectRobot robot) {
  final x = (robot.spawnX ?? 0).toStringAsFixed(3);
  final y = (robot.spawnY ?? 0).toStringAsFixed(3);
  final heading = robot.spawnHeading.toStringAsFixed(3);
  final buffer = StringBuffer()
    ..writeln("<?xml version='1.0' ?>")
    ..writeln('<!--')
    ..writeln('  ${robot.robotId} · ${robot.displayName} (${robot.kind.label})')
    ..writeln('  rmf_control_ui 가 맵 프로젝트에서 생성했다.')
    ..writeln('')
    ..writeln('  이 로봇 한 대만 Gazebo 에 올린다. 월드는 이미 떠 있다고 본다.')
    ..writeln('')
    ..writeln('  값의 출처: ${robot.dataSource.label}');
  if (robot.runsInGazebo) {
    buffer.writeln('  프로젝트 bringup 이 이 파일을 include 한다.');
  } else {
    // 출처가 Gazebo 가 아니면 bringup 이 이 파일을 부르지 않는다. 파일만 보고
    // 왜 안 올라오는지 헤매지 않도록 여기 적어 둔다.
    buffer
      ..writeln('  값의 출처가 Gazebo 가 아니라서 bringup 이 부르지 않는다.')
      ..writeln('  Gazebo 로 돌리려면 로봇 등록에서 출처를 Gazebo 로 바꾼다.');
  }
  buffer
    ..writeln('')
    ..writeln('  혼자 시험하려면:')
    ..writeln('    ros2 launch <이 파일>')
    ..writeln('-->')
    ..writeln('<launch>')
    ..write(_robotDomainEnv(robot));
  if (!robot.isMobile) {
    // 설치 로봇은 설명 파일도 실행 방법도 다르다. pinky_description 이 아니라
    // open_manipulator_description 의 xacro 를 펼치고, 바퀴 대신 ros2_control
    // 컨트롤러를 올린다.
    buffer
      ..writeln('  <group>')
      // 여기서는 push-ros-namespace 를 쓴다. 아래 노드들에 네임스페이스를 따로
      // 걸지 않으므로 두 겹이 되지 않는다. 이동 로봇 쪽은 include 하는 launch 가
      // 이미 namespace 인자를 받으므로 겹쳐 걸면 안 된다.
      ..writeln('    <push-ros-namespace namespace="${robot.gzName}"/>')
      ..writeln('    <node pkg="robot_state_publisher"')
      ..writeln('          exec="robot_state_publisher" output="screen">')
      ..writeln('      <param name="use_sim_time" value="True"/>')
      ..writeln('      <param name="frame_prefix" value="${robot.gzName}/"/>')
      ..writeln('      <param name="robot_description"')
      // 벤더 xacro 의 gz_ros2_control 플러그인에는 네임스페이스가 없다. 그대로
      // 두면 플러그인이 루트 `/robot_description` 을 기다리며 **Gazebo 의 갱신
      // 루프 전체를 막는다.** 시간이 안 흘러 /clock 도 odom 도 나오지 않는다.
      // 그래서 펼친 URDF 에 네임스페이스를 끼워 넣는 스크립트를 거친다.
      ..writeln(
        '             value="\$(command \'\$(dirname)'
        '/robot_description.sh\')"/>',
      )
      ..writeln('    </node>')
      ..writeln('    <node pkg="ros_gz_sim" exec="create" output="screen"')
      ..writeln(
        '          args="-name ${robot.gzName} '
        '-topic robot_description '
        '-x $x -y $y -z 0.0 -Y $heading '
        '-allow_renaming true">',
      )
      ..writeln('      <param name="use_sim_time" value="True"/>')
      ..writeln('    </node>')
      ..writeln('    <!-- 팔은 ros2_control 컨트롤러가 움직인다. -->');
    // 모델마다 컨트롤러가 다르다. 없는 것을 올리면 spawner 가 기다리다
    // 실패한다 — 예를 들어 omy_3m 에는 그리퍼가 없다.
    final controllers =
        openManipulatorControllers[robot.model] ??
        const ['joint_state_broadcaster', 'arm_controller'];
    for (final controller in controllers) {
      buffer
        ..writeln('    <node pkg="controller_manager" exec="spawner"')
        ..writeln('          args="$controller" output="screen"/>');
    }
    buffer
      ..writeln('  </group>')
      ..writeln('</launch>');
    return buffer.toString();
  }
  buffer
    ..writeln('  <group>')
    // 벤더의 upload_robot.launch.py 를 그대로 쓰지 않는다. 그 launch 가 펼치는
    // xacro 는 링크 이름에는 네임스페이스를 안 붙이면서 <gazebo reference> 에는
    // 붙여서, 라이다·카메라·IMU 가 통째로 버려진다. robot_description.sh 가
    // 펼친 뒤 그 접두사를 뗀다. 나머지는 벤더 launch 와 똑같이 맞춘다.
    ..writeln('    <push-ros-namespace namespace="${robot.gzName}"/>')
    ..writeln('    <node pkg="robot_state_publisher"')
    ..writeln('          exec="robot_state_publisher"')
    ..writeln('          name="robot_state_publisher" output="screen">')
    ..writeln('      <param name="use_sim_time" value="True"/>')
    ..writeln('      <param name="ignore_timestamp" value="False"/>')
    // TF 프레임의 접두사는 여기서 붙는다. 링크 이름을 안 건드리는 이유다.
    ..writeln('      <param name="frame_prefix" value="${robot.gzName}/"/>')
    ..writeln(
      '      <param name="robot_description"'
      ' value="\$(command \'\$(dirname)/robot_description.sh\')"/>',
    )
    ..writeln('    </node>')
    ..writeln('    <node pkg="joint_state_publisher"')
    ..writeln('          exec="joint_state_publisher"')
    ..writeln('          name="joint_state_publisher" output="screen">')
    ..writeln('      <param name="use_sim_time" value="True"/>')
    ..writeln('      <param name="rate" value="20.0"/>')
    ..writeln('      <param name="source_list" value="[joint_states]"/>')
    ..writeln('    </node>')
    ..writeln('    <node pkg="ros_gz_sim" exec="create" output="screen"')
    ..writeln(
      '          args="-name ${robot.gzName} '
      '-topic /${robot.gzName}/robot_description '
      '-x $x -y $y -z 0.1 -Y $heading">',
    )
    ..writeln('      <param name="use_sim_time" value="True"/>')
    ..writeln('    </node>')
    ..writeln('  </group>')
    ..writeln('</launch>');
  return buffer.toString();
}

/// 설치 로봇의 URDF 를 만드는 스크립트.
///
/// 벤더 xacro 의 `gz_ros2_control` 플러그인에는 네임스페이스가 없다. 그대로
/// 두면 플러그인이 루트 `/robot_description` 을 기다리는데, 우리는 로봇마다
/// 네임스페이스를 나누므로 그 토픽이 영영 오지 않는다.
///
/// 그냥 못 뜨고 마는 것이 아니다. **플러그인이 Gazebo 의 갱신 루프 안에서
/// 기다리기 때문에 시뮬레이션 전체가 멈춘다.** `/clock` 이 안 나오고, 같은
/// 월드의 Pinky 도 odom 을 못 낸다. 관제 노드 19개가 sim 시간을 기다리며
/// 통째로 굳는다.
///
/// 그래서 펼친 URDF 에 네임스페이스를 끼워 넣는다.
/// 핑키에 카메라를 달 것인가. **안 단다.**
///
/// 벤더 xacro 는 1280×720 을 30Hz 로, 그것도 `always_on` 으로 돌린다. 라이다를
/// 살리려고 월드에 `gz::sim::systems::Sensors` 를 넣은 뒤로는 그 카메라가 매
/// 프레임 렌더되기 시작했다.
///
/// 실측(2026-08-17, project1-ver2 월드) —
///
///     real_time_factor: 0.16      시뮬이 실시간의 16% 로 돈다
///     gz sim 서버 107% CPU        GUI 70% CPU
///
/// **그런데 그 그림을 받는 곳이 하나도 없다.** `<맵>_gz_bridge.yaml` 에 카메라
/// 항목이 없어 ROS 로 넘어오지도 않고, `<맵>_sensor_relay.py` 는 `/scan` 만
/// 구독한다. 아무도 안 보는 그림을 그리느라 시뮬이 1/6 속도로 돈 것이다.
///
/// 그래서 아예 안 단다. 카메라가 필요해지면 그때는 브리지와 릴레이까지 함께
/// 손봐야 하고, 급하면 생성된 `robot_description.sh` 에 `CAM_ENABLED=1` 로
/// 되살릴 수 있다 — 그때도 아래 값(640×360·5Hz·`always_on` 0)으로 붙는다.
const bool cameraEnabled = false;
const int cameraWidth = 640;
const int cameraHeight = 360;
const int cameraHz = 5;

/// 펼친 URDF 에서 카메라를 떼거나(기본) 값을 낮춰 다는 파이썬 조각.
///
/// `camera` (붙일지·너비·높이·주기·always_on) 와 `urdf` 가 이미 있다고 보고
/// `urdf` 를 고쳐 놓는다. 스크립트 안에 박아 넣지 않고 따로 둔 것은, 이 조각만
/// 떼어 실제 URDF 에 돌려 볼 수 있게 하기 위해서다.
const String cameraTuningPython = r'''
enabled, width, height, hz, always_on = camera


def tune(match):
    block = match.group(0)
    block = re.sub(r'<width>\d+</width>',
                   '<width>' + width + '</width>', block)
    block = re.sub(r'<height>\d+</height>',
                   '<height>' + height + '</height>', block)
    block = re.sub(r'<update_rate>[^<]+</update_rate>',
                   '<update_rate>' + hz + '</update_rate>', block)
    block = re.sub(r'<always_on>[^<]+</always_on>',
                   '<always_on>' + always_on + '</always_on>', block)
    return block


camera_block = r'<sensor[^>]*type="camera"[\s\S]*?</sensor>\s*'
if enabled == '1':
    urdf, touched = re.subn(camera_block, tune, urdf)
else:
    # 카메라를 떼어 낸다. 받는 곳이 없는 그림을 그리느라 시뮬이 느려진다.
    urdf, touched = re.subn(camera_block, '', urdf)
    # 센서가 빠져 껍데기만 남은 <gazebo reference="...camera..."> 도 걷어낸다.
    urdf = re.sub(
        r'<gazebo reference="[^"]*camera[^"]*">\s*</gazebo>\s*', '', urdf)
if touched == 0:
    sys.stderr.write('카메라 sensor 를 못 찾았습니다.\n')
''';

String buildRobotDescriptionScript(RmfProjectRobot robot) => robot.isMobile
    ? _buildMobileDescriptionScript(robot)
    : _buildWorkcellDescriptionScript(robot);

/// 이동 로봇의 URDF 를 만든다.
///
/// 벤더 xacro 는 **링크 이름에는 네임스페이스를 안 붙이는데
/// `<gazebo reference>` 에는 붙인다.**
///
/// ```xml
/// <link name="rplidar_link"/>                  ← 접두사 없음
/// <gazebo reference="pinky_01/rplidar_link">   ← 접두사 있음
///   <sensor name="pinky_01/gpu_lidar" type="gpu_lidar">
/// ```
///
/// 맞는 링크가 없으니 그 `<gazebo>` 블록이 통째로 버려진다. **라이다도 카메라도
/// IMU 도 올라가지 않는다.** 토픽 이름은 다리(bridge)가 만들어서 보이는데 데이터가
/// 영영 안 온다. 오류도 나지 않는다. 바퀴 마찰(`mu1`·`mu2`·`kp`)도 같이 버려진다.
///
/// 링크에 접두사를 붙이지 않는 것은 일부러다 — TF 는 `robot_state_publisher` 의
/// `frame_prefix` 가 붙인다. 그러니 `reference` 쪽 접두사를 떼는 것이 맞다.
///
/// 벤더 파일은 건드리지 않는다. 펼친 뒤에 고친다.
String _buildMobileDescriptionScript(RmfProjectRobot robot) =>
    '''#!/usr/bin/env bash
# ${robot.robotId} 의 URDF 를 만든다.
# rmf_control_ui 가 맵 프로젝트에서 생성했다.
#
# 벤더 xacro 는 링크 이름에는 네임스페이스를 안 붙이면서 <gazebo reference> 에는
# 붙인다. 맞는 링크가 없어 그 블록이 통째로 버려지고, 라이다·카메라·IMU 가
# 하나도 안 올라간다. 토픽 이름은 보이는데 데이터가 영영 안 오고 오류도 안 난다.
#
# 링크에 접두사를 안 붙이는 것은 일부러다 — TF 는 robot_state_publisher 의
# frame_prefix 가 붙인다. 그러니 reference 쪽 접두사를 떼는 것이 맞다.
set -euo pipefail

NAMESPACE="\${NAMESPACE:-${robot.gzName}}"
CAM_TILT_DEG="\${CAM_TILT_DEG:-0}"

# 핑키에 카메라를 달지. 기본은 안 단다 — 받는 곳이 없는 그림을 그리느라
# 시뮬이 1/6 속도로 돌았다. 까닭과 실측은 rmf_project_config.dart 의
# cameraEnabled 주석에 있다.
CAM_ENABLED="\${CAM_ENABLED:-${cameraEnabled ? 1 : 0}}"

# 되살릴 때 붙는 값.
CAM_WIDTH="\${CAM_WIDTH:-$cameraWidth}"
CAM_HEIGHT="\${CAM_HEIGHT:-$cameraHeight}"
CAM_HZ="\${CAM_HZ:-$cameraHz}"
# 1 로 두면 보는 사람이 없어도 계속 그린다. 벤더 값이 그렇다.
CAM_ALWAYS_ON="\${CAM_ALWAYS_ON:-0}"

XACRO="\$(ros2 pkg prefix pinky_description)"
XACRO="\$XACRO/share/pinky_description/urdf/robot.urdf.xacro"

# 펼친 결과를 파일에 받는다. python 을 heredoc 으로 넘기려면 표준 입력이
# 비어 있어야 한다.
RAW="\$(mktemp)"
trap 'rm -f "\$RAW"' EXIT

# 벤더 launch 와 같은 인자로 펼친다. 네임스페이스 끝의 빗금까지 같아야 한다.
xacro "\$XACRO" \\
  namespace:="\$NAMESPACE/" \\
  is_sim:=true \\
  cam_tilt_deg:="\$CAM_TILT_DEG" > "\$RAW"

python3 - "\$RAW" "\$NAMESPACE" "\$CAM_ENABLED" "\$CAM_WIDTH" "\$CAM_HEIGHT" \\
  "\$CAM_HZ" "\$CAM_ALWAYS_ON" <<'PYTHON'
import re
import sys

path, namespace = sys.argv[1], sys.argv[2]
camera = sys.argv[3:8]
with open(path, encoding="utf-8") as handle:
    urdf = handle.read()

# ── 카메라 ──────────────────────────────────
# 기본은 안 단다. 까닭과 실측은 rmf_project_config.dart 의 cameraEnabled 주석.
$cameraTuningPython

links = set(re.findall('<link name="([^"]+)"', urdf))
joints = set(re.findall('<joint name="([^"]+)"', urdf))
prefix = namespace + '/'

# 조인트 이름에는 네임스페이스가 붙어 있고 링크 이름에는 안 붙어 있다. 그래서
# 무조건 떼면 조인트 쪽이 깨진다. 가리키는 것이 무엇인지 보고 정한다.
def fix(match):
    name = match.group(1)
    if name in links or name in joints:
        return match.group(0)
    if name.startswith(prefix) and name[len(prefix):] in links:
        return '<gazebo reference="' + name[len(prefix):] + '"'
    sys.stderr.write(
        name + ' 이(가) 없어 그 <gazebo> 블록이 버려집니다.\\n')
    return match.group(0)

urdf, seen = re.subn('<gazebo reference="([^"]+)"', fix, urdf)
if seen == 0:
    sys.stderr.write('<gazebo reference> 가 하나도 없습니다.\\n')

sys.stdout.write(urdf)
PYTHON
''';

String _buildWorkcellDescriptionScript(RmfProjectRobot robot) =>
    '''#!/usr/bin/env bash
# ${robot.robotId} 의 URDF 를 만든다.
# rmf_control_ui 가 맵 프로젝트에서 생성했다.
#
# 벤더 xacro 의 gz_ros2_control 플러그인에 네임스페이스를 끼워 넣는다. 없으면
# 플러그인이 루트 /robot_description 을 기다리며 Gazebo 갱신 루프를 막는다.
set -euo pipefail

MODEL="\${MODEL:-${robot.model}}"
NAMESPACE="\${NAMESPACE:-${robot.gzName}}"

XACRO="\$(ros2 pkg prefix open_manipulator_description)"
XACRO="\$XACRO/share/open_manipulator_description/urdf/\$MODEL/\$MODEL.urdf.xacro"

xacro "\$XACRO" use_sim:=true | python3 -c '
import re
import sys

namespace = sys.argv[1]
urdf = sys.stdin.read()
# 플러그인 여는 태그 바로 뒤에 끼워 넣는다. 벤더 파일을 건드리지 않는다.
urdf = re.sub(
    r"(<plugin[^>]*gz_ros2_control[^>]*>)",
    r"\\1<ros><namespace>/" + namespace + r"</namespace></ros>"
    r"<robot_param_node>robot_state_publisher</robot_param_node>",
    urdf,
    count=1,
)
sys.stdout.write(urdf)
' "\$NAMESPACE"
''';

/// 로봇 한 대의 토픽 다리 설정.
///
/// 실행에는 프로젝트 전체를 묶은 `<맵이름>_gz_bridge.yaml` 을 쓴다. 이 파일은
/// 이 로봇이 무엇을 주고받는지 한자리에서 보기 위한 것이다. 둘 다 같은 등록
/// 정보에서 만들어지므로 어긋나지 않는다.
String buildRobotBridgeYaml(RmfProjectRobot robot) =>
    buildProjectGzBridgeYaml(
          mapName: robot.robotId,
          robots: [robot],
          // clock 과 tf 는 월드에 하나뿐이다. 로봇별 파일에 넣어 두면 이것만
          // 보고 돌렸을 때 같은 토픽에 다리를 두 번 놓게 된다.
          includeGlobal: false,
        )
        .replaceFirst(
          '# ${robot.robotId} 프로젝트의 ros_gz_bridge 설정.',
          '# ${robot.robotId} 한 대의 토픽 목록.',
        )
        .replaceFirst(
          '# rmf_control_ui 가 맵 프로젝트에서 생성했다.',
          '# 실행에는 프로젝트 전체를 묶은 <맵이름>_gz_bridge.yaml 을 쓴다.\n'
              '# clock 과 tf 는 월드에 하나뿐이라 여기 넣지 않았다.',
        );

/// 로봇 디렉터리에 함께 두는 설명.
/// [projectDomainId] 는 프로젝트 기본 도메인이다. 실물 로봇을 띄우는 명령에
/// 그대로 박아 넣는다 — 도메인이 어긋나면 토픽 이름만 보이고 값은 하나도 안
/// 오는데 **오류가 안 나서**, 라이다나 AMCL 을 의심하며 한참을 헤매게 된다.
/// 로봇이 제 도메인을 따로 가지면 그것이 이긴다.
String buildRobotReadme(
  RmfProjectRobot robot,
  String mapName, {
  int projectDomainId = 0,
}) {
  final station = robot.chargerWaypoint ?? '미지정';
  final rosDomainId = robot.rosDomainId ?? projectDomainId;
  final buffer = StringBuffer()
    ..writeln('# ${robot.robotId} · ${robot.displayName}')
    ..writeln()
    ..writeln('$mapName 프로젝트의 ${robot.kind.label}입니다.')
    ..writeln('rmf_control_ui 가 로봇 등록에서 만들었습니다.')
    ..writeln()
    ..writeln('| 항목 | 값 |')
    ..writeln('|---|---|')
    ..writeln('| 종류 | ${robot.kind.label} |')
    ..writeln('| 값의 출처 | ${robot.dataSource.label} |')
    ..writeln('| 모델 | ${robot.model} |')
    ..writeln('| Gazebo 이름 | ${robot.gzName} |')
    ..writeln('| 토픽 네임스페이스 | `/${robot.gzName}` |')
    ..writeln('| ${robot.isMobile ? '충전' : '설비'} 자리 | $station |');
  if (robot.isMobile) {
    buffer.writeln('| 구획 자격 | ${robot.zones.join(', ')} |');
  }
  buffer
    ..writeln()
    ..writeln(robot.dataSource.summary)
    ..writeln();
  if (robot.runsInGazebo) {
    buffer.writeln('프로젝트 bringup 이 이 로봇을 Gazebo 에 올립니다.');
  } else if (robot.dataSource == RobotDataSource.real) {
    buffer
      ..writeln('실물이 이미 있으므로 Gazebo 에는 올리지 않습니다.')
      ..writeln('fleet adapter 에는 들어갑니다.');
  } else {
    buffer
      ..writeln('앱 안에서만 도는 로봇입니다.')
      ..writeln('fleet adapter 에도 Gazebo 에도 들어가지 않습니다.');
  }
  // 실물 이동 로봇은 앱이 대신 띄워 줄 수 없다. 사람이 로봇에 들어가 손으로
  // 올려야 하고, 그때 **네임스페이스와 도메인이 어긋나면** 토픽 이름만 있고
  // 값은 하나도 안 온다. 오류는 안 난다 — 그래서 라이다나 AMCL 을 의심하며
  // 한참을 헤매게 된다. 실제로 그 일이 있었다.
  //
  // 그러니 이 로봇을 어떻게 띄우는지 여기에 그대로 적어 둔다. 로봇마다 이름이
  // 다르므로 명령도 로봇마다 다르다.
  if (robot.isMobile && robot.dataSource == RobotDataSource.real) {
    buffer
      ..writeln()
      ..writeln('## 로봇에서 띄우기')
      ..writeln()
      ..writeln('이 로봇은 앱이 못 띄웁니다. 로봇에 들어가 직접 올립니다.')
      ..writeln()
      ..writeln('**네임스페이스와 도메인이 아래와 같아야 합니다.**')
      ..writeln('어긋나면 토픽 이름만 보이고 값은 하나도 안 옵니다 —')
      ..writeln('오류가 안 나서 라이다나 AMCL 을 의심하게 됩니다.')
      ..writeln()
      ..writeln('```bash')
      ..writeln('# ① 하드웨어 (라이다 · 모터 · 배터리)')
      ..writeln('export ROS_DOMAIN_ID=$rosDomainId')
      ..writeln('source /opt/ros/jazzy/setup.bash')
      ..writeln('source ~/pinky_pro/install/setup.bash')
      ..writeln()
      ..writeln(
        'ros2 launch pinky_bringup bringup_robot_namespaced.launch.xml \\',
      )
      ..writeln('  namespace:=${robot.gzName}')
      ..writeln('```')
      ..writeln()
      ..writeln('```bash')
      ..writeln('# ② Nav2 (①이 값을 내기 시작한 뒤에 띄웁니다)')
      ..writeln('export ROS_DOMAIN_ID=$rosDomainId')
      ..writeln(
        'ros2 launch \$MAP_DIR/${robotDirectoryName(robot)}/nav2.launch.xml',
      )
      ..writeln('```')
      ..writeln()
      ..writeln('### 잘 떴는지 보기')
      ..writeln()
      ..writeln('```bash')
      ..writeln('export ROS_DOMAIN_ID=$rosDomainId')
      ..writeln()
      ..writeln('# 하드웨어가 값을 내는가 (둘 다 나와야 합니다)')
      ..writeln('ros2 topic echo /${robot.gzName}/scan --once | head -5')
      ..writeln('ros2 topic echo /${robot.gzName}/odom --once | head -5')
      ..writeln()
      ..writeln('# Nav2 가 다 켜졌는가 (전부 active 여야 합니다)')
      ..writeln(
        'for n in amcl controller_server planner_server bt_navigator; do',
      )
      ..writeln('  echo -n "\$n: "; ros2 lifecycle get /${robot.gzName}/\$n')
      ..writeln('done')
      ..writeln()
      ..writeln('# 로봇이 지도 위에 섰는가 — 이것이 나오면 다 된 것입니다')
      ..writeln('ros2 run tf2_ros tf2_echo map ${robot.gzName}/odom')
      ..writeln('```')
      ..writeln()
      ..writeln('`tf2_echo` 는 처음 몇 초 `frame does not exist` 를 냅니다.')
      ..writeln('TF 버퍼가 차는 동안이라 정상입니다 — 조금 기다립니다.')
      ..writeln()
      ..writeln('### 안 될 때')
      ..writeln()
      ..writeln('| 증상 | 볼 곳 |')
      ..writeln('|---|---|')
      ..writeln('| 토픽이 루트(`/scan`)로 나온다 | `namespace:=` 를 빠뜨렸습니다 |')
      ..writeln('| 토픽이 아무것도 안 보인다 | `ROS_DOMAIN_ID` 가 $rosDomainId 인지 |')
      ..writeln('| `scan`·`odom` 이 안 나온다 | 시리얼 포트를 다른 프로세스가 잡고 있는지 |')
      ..writeln('| `amcl` 만 active 다 | 나머지가 못 켜졌습니다. Nav2 를 다시 띄웁니다 |')
      ..writeln('| `map` 프레임이 없다 | 관제 PC 의 `map_server` 가 떴는지 |')
      ..writeln()
      ..writeln('로봇을 손으로 옮겨 위치를 잃으면, 앱의 로봇 상세에서')
      ..writeln('`이 자리를 초기 위치로 보내기` 를 누릅니다.');
  }
  buffer
    ..writeln()
    ..writeln('## 파일')
    ..writeln()
    ..writeln('| 파일 | 용도 |')
    ..writeln('|---|---|')
    ..writeln('| `robot.yaml` | 이 로봇의 등록 정보 |');
  // Gazebo 에 안 올리는 로봇에게 `spawn.launch.xml` 을 안내하면, 그것을 돌려
  // 보고 안 된다고 여긴다. 실물은 이미 그 자리에 있다.
  if (robot.runsInGazebo) {
    buffer.writeln('| `spawn.launch.xml` | 이 로봇만 Gazebo 에 올리는 launch |');
  }
  if (robot.isMobile && robot.dataSource.usesTopics) {
    buffer.writeln('| `nav2.launch.xml` | 이 로봇의 Nav2 (AMCL · 경로 · 제어) |');
    buffer.writeln('| `nav2_params.yaml` | 그 Nav2 의 파라미터 |');
  }
  buffer
    ..writeln('| `bridge.yaml` | 이 로봇이 주고받는 토픽 |')
    ..writeln();
  if (robot.runsInGazebo) {
    buffer
      ..writeln('프로젝트 bringup 이 `spawn.launch.xml` 을 include 합니다.')
      ..writeln('이 로봇만 따로 시험하려면 그 파일을 직접 돌리면 됩니다.');
  }
  buffer
    ..writeln()
    ..writeln('## 고치는 곳')
    ..writeln()
    ..writeln('여기 파일을 손으로 고치지 마세요. 다음 저장 때 덮어써집니다.')
    ..writeln('앱의 `로봇` 메뉴 → `로봇 등록`에서 고칩니다.');
  if (!robot.isMobile) {
    buffer
      ..writeln()
      ..writeln('## 설치 로봇 참고')
      ..writeln()
      ..writeln('한자리에 고정되므로 fleet adapter 에 들어가지 않습니다.')
      ..writeln('배차 대상이 아니라 Open-RMF 에서는 workcell 로 다룹니다.')
      ..writeln()
      ..writeln('올리는 컨트롤러:')
      ..writeln();
    final controllers =
        openManipulatorControllers[robot.model] ??
        const ['joint_state_broadcaster', 'arm_controller'];
    for (final controller in controllers) {
      buffer.writeln('- `$controller`');
    }
  }
  return buffer.toString();
}

/// 설비 로봇을 RMF 의 워크셀(dispenser·ingestor)로 잇는 노드.
///
/// 로봇이 픽업 자리에 닿으면 RMF 가 `/dispenser_requests` 에
/// `target_guid: 픽업2` 를 낸다. **그 이름으로 답하는 노드가 없으면 RMF 는
/// 영원히 기다린다** — 오류는 안 나고 작업만 그 자리에서 멈춘다.
///
/// 이 노드가 그 답을 한다. 요청을 받으면 팔에 관절 궤적을 보내고, 끝나면
/// `/dispenser_results` 에 SUCCESS 를 낸다.
///
/// `/dispenser_states` 를 1초마다 내는 것도 함께 한다. RMF 는 상태가 안 오는
/// 워크셀을 **없는 것으로 본다** — 요청조차 안 보낸다.
String buildWorkcellScript({
  required String mapName,
  required WorkcellPairingResult pairing,
  List<WorkcellPolicy> policies = const [],
  Map<String, double> dockHeadings = const {},
  Map<String, String> policyArchives = const {},
  String policyRunnerPath = '',
}) {
  final nodeName = _rosNodeName('${mapName}_workcell');
  final archiveEntries = policyArchives.entries
      .where((item) => item.value.trim().isNotEmpty)
      .map((item) => "    '${item.key}': '${item.value}',")
      .join('\n');
  final headingEntries = dockHeadings.entries
      .map(
        (item) =>
            "    '${item.key}': ${(item.value * math.pi / 180).toStringAsFixed(6)},"
            '  # ${_n(item.value)}도',
      )
      .join('\n');
  final entries = pairing.pairings
      .map(
        (item) =>
            "    ('${item.robot.robotId}', '${item.robot.gzName}', "
            "'${item.robot.model}', ${_pyList(item.dispensers)}, "
            '${_pyList(item.ingestors)}, '
            '${_pyList([for (final policy in policies)
              if (policy.deployedWorkcells.contains(item.robot.robotId) && policy.robotModel == item.robot.model) policy.id])}),',
      )
      .join('\n');
  return '''#!/usr/bin/env python3
"""$mapName 프로젝트의 RMF 워크셀 어댑터.

rmf_control_ui 가 맵 프로젝트에서 생성했다. 손으로 고치면 다음 저장 때
덮어써진다.

로봇이 픽업 자리에 닿으면 RMF 가 `/dispenser_requests` 로 그 자리 이름을
부른다. 여기서 팔을 움직이고 `/dispenser_results` 로 끝났다고 답한다.

답하지 않으면 RMF 는 영원히 기다린다. 오류는 안 난다 — 작업이 그 자리에서
멈춰 있을 뿐이다.

**시계로 판단하지 않는다.** 예전에는 관절 궤적을 토픽에 던지고 4초 뒤에
성공을 알렸다. 던지고 끝이라 팔이 받았는지, 움직였는지, 끝냈는지 아무도 묻지
않았다 — 팔이 느리든 막혔든 구독자가 아예 없든 똑같이 성공이었고, 핑키는 빈
채로 떠났다. 지금은 세 가지를 **토픽으로 듣고** 정한다.

    ① 로봇이 제자리에 제 자세로 섰나   /fleet_states
    ② 팔이 궤적을 끝냈나               follow_joint_trajectory 액션 결과
    ③ 팔이 정말 멈췄나                 <네임스페이스>/joint_states

그리고 ①은 팔이 움직이는 **내내** 다시 본다. 적재 중에 로봇이 흔들리면 궤적을
취소하고 실패로 답한다 — 움직이는 로봇에 물건을 올리지 않는다.
"""

import math
import os
import subprocess
import sys
import threading
import time

import rclpy
import rclpy.node
from rclpy.action import ActionClient
from rclpy.qos import QoSProfile, QoSDurabilityPolicy, QoSReliabilityPolicy

from builtin_interfaces.msg import Time
from control_msgs.action import FollowJointTrajectory
from rmf_dispenser_msgs.msg import DispenserRequest, DispenserResult, DispenserState
from rmf_fleet_msgs.msg import FleetState
from rmf_ingestor_msgs.msg import IngestorRequest, IngestorResult, IngestorState
from sensor_msgs.msg import JointState
from trajectory_msgs.msg import JointTrajectory, JointTrajectoryPoint

# 로봇 ID, ROS 네임스페이스, 모델, 맡은 자리와 **이 팔에 붙인** policy.
#
# 팔마다 배운 것이 다르다. 프로젝트에 등록했다고 모든 팔이 쓰는 것이 아니라,
# 로봇 관리에서 그 팔에 붙인 것만 여기 온다.
WORKCELLS = [
$entries
]

# policy 별 학습 결과 ZIP. 러너가 이것을 풀어 쓴다.
#
# ZIP 은 git 에 올리지 않으므로 이 자리에 없을 수 있다. 없으면 아래 시험
# 동작으로 대신하고, 앱의 `Policy 관리` 에서 다시 받으라고 로그에 남긴다.
POLICY_ARCHIVES = {
$archiveEntries
}

# 학습 policy 를 실제로 돌리는 러너. 같은 배포 산출물 안에 함께 나온다.
#
# **Gazebo 든 실물이든 같은 것을 쓴다.** 러너는 네임스페이스만 달리 받아
# `/<네임스페이스>/joint_states` 를 보고 `/<네임스페이스>/arm_controller/
# joint_trajectory` 로 낸다 — 시뮬과 실물의 차이는 그 토픽 뒤에 무엇이 붙어
# 있느냐뿐이다.
POLICY_RUNNER = '$policyRunnerPath'

# 러너가 이 시간 안에 안 끝나면 끊고 실패로 답한다 [s, 벽시계].
POLICY_TIMEOUT = 600.0

# 러너가 남긴 말. 왜 추론이 안 돌았는지는 여기에 있다.
POLICY_LOG = os.path.join(
    os.path.dirname(POLICY_RUNNER) if POLICY_RUNNER else '.',
    '${mapName}_policy_runner.log')

# 자리마다 로봇이 볼 방향 [rad]. 맵 관리의 `적재 방향` 에서 온다.
#
# 핑키는 수납함을 뒤에 달고 다닌다. 들어온 그대로 서면 수납함이 팔에서 가장
# 먼 자리에 온다. 그래서 그 자리로 가는 작업의 `go_to_place` 에 이 각도가
# `orientation` 으로 실리고, 여기서는 **정말 그렇게 섰는지** 다시 본다.
#
# RMF 가 맞다고 하는 것과 로봇이 실제로 그렇게 선 것은 다른 이야기다.
DOCK_HEADINGS = {
$headingEntries
}

# 팔이 한 번 움직이는 데 걸리는 시간 [s].
#
# RMF 는 이 시간을 모른다. 우리가 끝났다고 알릴 때까지 기다릴 뿐이다.
ACTION_SECONDS = 4.0

# 자세가 이만큼 어긋나도 그 자세로 섰다고 본다 [rad]. 약 10도.
#
# **Nav2 의 `yaw_goal_tolerance`(약 5도)보다 일부러 헐겁다.** 둘은 하는 일이
# 다르다 —
#
#   Nav2 쪽은 **요구**다. 그 각도에 들어올 때까지 도착으로 안 친다.
#   여기는 **관문**이다. 잘못 선 로봇에 팔이 나가는 것을 막는다.
#
# 같은 값으로 묶으면 안 된다. 제자리 회전은 1.0 rad/s 로 돌다가 도착 판정이
# 나는 순간 멈추므로, 실제로 멎는 자세는 판정 문턱보다 조금 더 간다. 얼마나
# 더 가는지는 로봇을 돌려 재 봐야 아는 값인데 아직 안 쟀다. 같은 값으로 묶어
# 두면 Nav2 가 도착이라고 놓아준 로봇을 워크셀이 매번 거절해, 멀쩡한 작업이
# 전부 실패한다.
#
# 잡으려는 것은 몇 도의 오차가 아니라 **안 돈 로봇**이다. 수납함을 뒤에 달고
# 들어온 그대로 선 로봇은 180도가 어긋난다 — 10도로도 넉넉히 걸린다.
DOCK_YAW_TOLERANCE = 0.175

# 로봇이 섰다고 보는 문턱. **거리가 아니라 속도다.**
#
# 예전에는 두 번의 `/fleet_states` 사이에 얼마나 움직였나로 쟀다. 그것이
# 시뮬레이터 속도에 휘둘린다 — `/fleet_states` 는 벽시계 10Hz 인데 로봇은 시뮬
# 시계로 움직이므로, 시뮬이 느리면 눈금당 이동이 그만큼 줄어든다.
#
# 실측(2026-08-17) — Gazebo 실시간 배율(RTF) 0.101, `/fleet_states` 10.00Hz.
# 0.2m/s 로 달리는 로봇이 눈금당 0.002m 밖에 안 움직인다. 2cm 문턱이면
# **달리는 로봇이 섰다고 나온다.**
#
# `Location.t` 는 시뮬 시계 시각이다. 그것으로 나누면 진짜 속도가 나오고,
# 시뮬이 몇 배로 느리든 값이 같다.
ROBOT_STILL_SPEED = 0.03      # [m/s] 핑키 순항은 0.2
ROBOT_STILL_TURN_RATE = 0.20  # [rad/s] 제자리 회전은 1.0

# 적재를 시작한 자리에서 이만큼 벗어나면 중단한다.
#
# 시작할 때의 자세를 기준으로 잰다. **눈금 사이의 차이로 재면 안 된다** —
# 위에서 본 흔들림이 그대로 중단 사유가 되기 때문이다. 잡으려는 것은 몇 도의
# 떨림이 아니라 **로봇이 자리를 떠난 것**이고, 그것은 몇십 cm 단위로 뚜렷하다.
#
# 팔이 이미 움직이는 중에 끊는 것 자체가 위험하므로, 정말 떠났을 때만 끊는다.
ARM_ABORT_METERS = 0.15
ARM_ABORT_RADIANS = 0.52

# 이보다 오래된 로봇 소식은 안 믿는다 [s]. 어댑터는 10Hz 로 낸다.
FLEET_STATE_MAX_AGE = 3.0

# 로봇이 자리에 설 때까지 기다려 주는 시간 [s, 벽시계].
#
# RMF 는 도착했다고 보고 우리를 부르는데, 그 순간 로봇이 마지막 몇 도를 돌고
# 있을 수 있다. 여기서 바로 거절하면 멀쩡한 작업이 실패한다.
#
# 넉넉해야 한다. 시뮬이 실시간의 1/10 로 돌면(실측 RTF 0.101) 로봇이 마지막
# 자세를 다듬는 데도 벽시계로 열 배가 걸린다.
ROBOT_SETTLE_TIMEOUT = 60.0

# 팔이 궤적을 끝낼 때까지 기다리는 한계 [s, 벽시계].
#
# **성능 예산이 아니라 멈춤 감지다.** 답을 안 하면 RMF 는 영원히 기다리므로
# 언젠가는 끊어야 하지만, 조이면 느린 시뮬에서 멀쩡한 궤적을 끊는다.
#
# 실측(2026-08-17) — 시뮬 4초짜리 궤적이 벽시계로 55.5초 걸렸다(RTF 0.101).
#
#     [omx_01.arm_controller] Accepted new action goal   435.180
#     [omx_01.arm_controller] Goal reached, success!     490.698
#
# 샌드위치 재생은 시뮬 35초짜리라 같은 배율이면 벽시계 350초가 넘는다. 예전
# 값(120초)이면 그것이 매번 끊겼다.
ARM_RESULT_TIMEOUT = 600.0

# 액션이 끝난 뒤 두는 여유 [s].
#
# **판정이 아니라 여유다.** 끝났다고 정하는 것은 액션 결과이고, 이 시간은
# 로봇이 곧바로 튀어 나가지 않게 두는 것뿐이다. 이만큼 지나면 관절이 멎었다고
# 보이든 아니든 넘어간다.
ARM_SETTLE_SECONDS = 2.0

# 관절이 멎었다고 보는 속도 [rad/s].
#
# 이 값 아래로 내려오면 여유를 다 안 쓰고 바로 넘어간다. 못 내려와도 막지
# 않는다 — 이 팔에서는 실제로 못 내려온다.
#
# 실측(2026-08-17, OMX in Gazebo, 팔이 멈춰 있는 상태, 표본 148) —
#
#     최소 0.113   중앙 1.291   최대 1.443  [rad/s]
#     0.02 아래인 비율 0%    0.10 아래인 비율 0%
#
# 멈춰 있는 팔이 1.3 rad/s 로 도는 것으로 나온다. `joint_states` 의 velocity
# 가 이 설정에서는 믿을 값이 아니라는 뜻이다. 그래서 이 확인은 **거부권이
# 없다.** 문턱을 실측에 맞춰 올리지 마라 — 올려 봐야 늘 통과가 되어 확인이
# 아니게 된다. 못 믿는 신호는 못 믿는 채로 두고, 판정은 액션 결과가 한다.
ARM_STILL_VELOCITY = 0.02

# 감시 주기 [s]. 이 노드는 `use_sim_time` 을 안 쓰므로 시스템 시계로 돈다.
WATCHDOG_PERIOD = 0.2

# 물품 종류별 가상 모방학습 policy. 모든 OMX가 같은 다섯 policy를 제공한다.
# 각 값은 시간 비율과 joint1~4 자세이며 실제 추론기 연결 전 동작 검증용이다.
JOINT_NAMES = ['joint1', 'joint2', 'joint3', 'joint4']
HOME_POSE = [0.0, -1.0, 0.3, 0.7]
POLICY_MOTIONS = {
    'policy_1': [[0.00, 0.45, -0.30, 0.65], [0.00, 0.75, -0.55, 0.90]],
    'policy_2': [[0.35, 0.35, -0.20, 0.55], [0.55, 0.70, -0.45, 0.80]],
    'policy_3': [[-0.35, 0.35, -0.20, 0.55], [-0.55, 0.70, -0.45, 0.80]],
    'policy_4': [[0.20, 0.15, 0.05, 0.45], [0.35, 0.55, -0.20, 0.70]],
    'policy_5': [[-0.20, 0.15, 0.05, 0.45], [-0.35, 0.55, -0.20, 0.70]],
}

# 학습 policy 실행기를 연결하기 전 controller·RMF 경로를 검증하는 저속 궤적.
# 실제 ACT 추론 결과가 아니며 배포된 policy ID에만 사용한다.
MODEL_TEST_MOTIONS = {
    'open_manipulator_x': {
        'joints': ['joint1', 'joint2', 'joint3', 'joint4'],
        'home': [0.0, -1.0, 0.3, 0.7],
        'poses': [[0.15, -0.85, 0.25, 0.65], [-0.15, -0.85, 0.25, 0.65]],
    },
    'omx_f': {
        'joints': ['joint1', 'joint2', 'joint3', 'joint4', 'joint5', 'gripper_joint_1'],
        'home': [0.0, -1.0, 0.3, 0.7, 0.0, 0.0],
        'poses': [[0.15, -0.85, 0.25, 0.65, 0.10, 0.0],
                  [-0.15, -0.85, 0.25, 0.65, -0.10, 0.0]],
    },
}

# 2usang/trihouse-sandwich episode 0의 성공 시연을 1초 간격으로 추린 값.
# [시각(s), joint1~5(deg), gripper(deg)]이며 controller 전송 때 rad로 바꾼다.
SANDWICH_REPLAY_DEG = [
    [0.0, -0.611, -66.398, 55.018, 47.692, 0.415, 60.147],
    [1.0, -0.611, -66.398, 55.018, 47.692, 0.415, 60.147],
    [2.0, -0.611, -66.398, 55.018, 47.692, 0.415, 60.147],
    [3.0, -0.611, -66.398, 55.018, 47.692, 0.415, 60.147],
    [4.0, -0.611, -66.398, 55.018, 47.692, 0.415, 60.147],
    [5.0, -0.659, -66.398, 55.018, 47.692, 0.415, 60.147],
    [6.0, -0.708, -66.545, 55.018, 43.834, 0.562, 61.001],
    [7.0, -3.053, -66.545, 54.969, 28.547, 0.317, 60.977],
    [8.0, -8.474, -66.545, 54.872, 24.884, 0.708, 59.487],
    [9.0, -18.437, -66.252, 37.729, 25.421, 0.073, 59.219],
    [10.0, -30.696, -49.109, 20.147, 25.079, -7.937, 58.999],
    [11.0, -33.529, -40.757, 10.916, 21.270, -7.253, 58.632],
    [12.0, -33.480, -39.585, 10.183, 17.216, -3.639, 58.657],
    [13.0, -33.431, -34.945, 6.325, 16.044, -3.248, 58.657],
    [14.0, -33.480, -34.212, 6.374, 15.263, -3.492, 58.657],
    [15.0, -33.431, -32.405, 6.716, 14.481, -3.541, 58.681],
    [16.0, -33.431, -32.259, 6.618, 14.432, -3.492, 58.681],
    [17.0, -34.896, -26.593, 6.716, 12.088, -3.394, 58.657],
    [18.0, -34.408, -21.661, -0.659, 12.381, -0.073, 58.388],
    [19.0, -34.164, -17.216, -3.980, 12.234, -0.122, 57.875],
    [20.0, -33.187, -14.286, -5.934, 12.186, -0.073, 57.680],
    [21.0, -32.112, -13.211, -6.032, 11.990, -0.366, 53.187],
    [22.0, -31.233, -14.530, -5.836, 9.499, -0.171, 47.131],
    [23.0, -33.529, -20.684, -5.055, 10.183, -0.122, 46.716],
    [24.0, -45.250, -24.298, -1.245, 13.260, 1.783, 46.716],
    [25.0, -51.013, -24.835, 6.862, 12.772, 1.685, 46.740],
    [26.0, -60.488, -20.488, 7.692, 14.969, 3.932, 46.716],
    [27.0, -65.763, -12.381, 7.839, 20.391, 7.497, 46.716],
    [28.0, -69.035, -3.883, 7.448, 19.365, 7.448, 46.862],
    [29.0, -68.742, -2.711, 6.569, 18.486, 7.497, 59.243],
    [30.0, -65.226, -21.465, 10.574, 18.193, 7.399, 59.341],
    [31.0, -48.767, -56.337, 45.250, 7.106, 7.253, 59.316],
    [32.0, -9.304, -66.447, 55.263, 12.088, 7.448, 59.365],
    [33.0, 1.490, -66.398, 55.263, 42.076, 7.399, 59.365],
    [34.0, 1.050, -66.447, 55.263, 48.620, 7.399, 59.365],
    [34.7, 1.050, -66.447, 55.263, 48.620, 7.350, 59.365],
]


def now_msg(node):
    stamp = node.get_clock().now().to_msg()
    return Time(sec=stamp.sec, nanosec=stamp.nanosec)


def wrap_angle(radians):
    """-pi 초과 pi 이하로 접는다. 179도와 -179도는 2도 차이지 358도가 아니다."""
    return (radians + math.pi) % (2 * math.pi) - math.pi


def trajectory_of(joint_names, poses, seconds):
    """자세 목록을 시간에 고르게 펴서 궤적 하나로 만든다."""
    message = JointTrajectory()
    message.joint_names = list(joint_names)
    for index, pose in enumerate(poses, start=1):
        point = JointTrajectoryPoint()
        point.positions = [float(value) for value in pose]
        at = seconds * index / len(poses)
        point.time_from_start.sec = int(at)
        point.time_from_start.nanosec = int((at % 1) * 1e9)
        message.points.append(point)
    return message


class Job:
    """처리 중인 요청 하나. 어디까지 왔는지와 언제까지 기다릴지를 들고 있다."""

    def __init__(self, msg, dispenser, robot_name, required_yaw, trajectory,
                 policy_id=None, policy_archive=None):
        self.msg = msg
        self.dispenser = dispenser
        self.robot_name = robot_name
        self.required_yaw = required_yaw
        self.trajectory = trajectory
        # 학습 policy 로 돌릴 일이면 그 policy 와 ZIP 자리. 아니면 None.
        self.policy_id = policy_id
        self.policy_archive = policy_archive
        # 러너 프로세스. 'policy' 단계에서만 있다.
        self.process = None
        # 'waiting_robot' → ('policy' | 'moving') → 'settling'
        self.stage = 'waiting_robot'
        self.goal_handle = None
        self.deadline = time.monotonic() + ROBOT_SETTLE_TIMEOUT
        # 팔을 움직이기 시작한 순간의 로봇 자리. 적재 중에는 이것과 견준다.
        self.anchor = None


class Workcell:
    """설비 한 대. 맡은 자리 이름으로 불린다."""

    def __init__(self, node, robot_id, namespace, model, dispensers, ingestors,
                 deployed_policies):
        self.node = node
        self.robot_id = robot_id
        self.namespace = namespace
        self.model = model
        self.dispensers = dispensers
        self.ingestors = ingestors
        self.deployed_policies = set(deployed_policies)
        self.busy = False
        self.active_request = None
        self.completed_requests = set()
        self.lock = threading.Lock()
        self.job = None

        # 토픽이 아니라 **액션**이다. 토픽 publish 는 던지고 끝이라 팔이
        # 끝냈는지 물을 방법이 없다. 액션은 받았다(accepted)와 끝났다(result)를
        # 돌려준다 — 우리가 RMF 에 성공을 알리는 근거가 그 result 다.
        self.arm_action_name = (
            f'/{namespace}/arm_controller/follow_joint_trajectory')
        self.arm = ActionClient(node, FollowJointTrajectory,
                                self.arm_action_name)

        # 액션이 끝났다고 한 뒤 관절이 정말 멎었는지 보는 곳.
        self.joint_velocity = None
        self.joint_state_at = 0.0
        # 속도로는 멎었는지 알 수 없다는 말을 한 번만 적는다.
        self.warned_arm_velocity = False
        node.create_subscription(
            JointState, f'/{namespace}/joint_states', self.on_joint_state, 10)

    def serves(self, guid):
        return guid in self.dispensers or guid in self.ingestors

    def on_joint_state(self, msg):
        if not msg.velocity:
            # 속도를 안 내는 컨트롤러도 있다. 그러면 이 확인은 건너뛴다.
            return
        self.joint_velocity = max(abs(value) for value in msg.velocity)
        self.joint_state_at = time.monotonic()

    def arm_still(self):
        """관절이 멎었나. 속도를 못 들으면 판단을 미룬다(None)."""
        if self.joint_velocity is None:
            return None
        if time.monotonic() - self.joint_state_at > FLEET_STATE_MAX_AGE:
            return None
        return self.joint_velocity <= ARM_STILL_VELOCITY

    # ── 무엇을 시킬지 정하는 쪽 ────────────────────────────────────────────

    def policy_trajectory(self, policy_id, seconds):
        """선택한 가상 policy의 관절 궤적."""
        return trajectory_of(
            JOINT_NAMES, [*POLICY_MOTIONS[policy_id], HOME_POSE], seconds)

    def test_trajectory(self, reason, seconds=None):
        """관절 몇 개를 눈에 보이게 움직였다가 집으로 돌아오는 시험 동작.

        **붙인 policy 가 없을 때 여기로 온다.** 아무것도 안 보내면 기다릴 것도
        없어 그 자리에서 성공이 되고, 그러면 팔이 살아 있는지조차 모르는 채로
        작업만 넘어간다. 그래서 짧게라도 실제로 움직이고, 그 동작이 끝난 것을
        액션 결과로 확인한 뒤에 RMF 에 성공을 알린다 — 다음 단계는 그때 간다.

        학습한 동작이 아니다. 팔·컨트롤러·RMF 의 고리가 살아 있는지 보는 것뿐이다.
        """
        seconds = ACTION_SECONDS if seconds is None else seconds
        self.node.get_logger().warning(
            f'[{self.robot_id}] [TEST] {reason}')
        profile = MODEL_TEST_MOTIONS.get(self.model)
        if profile is None:
            # 모르는 모델이다. 기본 관절 이름으로 조금씩만 움직인다.
            return trajectory_of(
                JOINT_NAMES,
                [[0.20, -0.85, 0.25, 0.65], [-0.20, -0.85, 0.25, 0.65],
                 HOME_POSE],
                seconds)
        return trajectory_of(
            profile['joints'], [*profile['poses'], profile['home']], seconds)

    def sandwich_replay_trajectory(self, policy_id):
        """학습 episode의 샌드위치 집기 시연을 관절 재생한다."""
        message = JointTrajectory()
        message.joint_names = list(MODEL_TEST_MOTIONS['omx_f']['joints'])
        lead_in = 1.0
        for row in SANDWICH_REPLAY_DEG:
            point = JointTrajectoryPoint()
            point.positions = [math.radians(value) for value in row[1:]]
            at = lead_in + row[0]
            point.time_from_start.sec = int(at)
            point.time_from_start.nanosec = int((at % 1) * 1e9)
            message.points.append(point)
        self.node.get_logger().info(
            f'[{self.robot_id}] [{policy_id}] 학습 episode 0 샌드위치 동작 재생')
        return message

    def policy_archive(self, policy_id):
        """이 policy 의 학습 결과 ZIP. 이 자리에 없으면 None."""
        path = POLICY_ARCHIVES.get(policy_id)
        return path if path and os.path.exists(path) else None


class WorkcellAdapter(rclpy.node.Node):

    def __init__(self):
        super().__init__('${nodeName}')

        # RMF 는 상태를 **transient local** 로 듣는다. 늦게 뜬 쪽도 마지막
        # 상태를 받아야 워크셀이 있다는 것을 알기 때문이다.
        state_qos = QoSProfile(
            depth=10,
            reliability=QoSReliabilityPolicy.RELIABLE,
            durability=QoSDurabilityPolicy.TRANSIENT_LOCAL,
        )
        self.dispenser_states = self.create_publisher(
            DispenserState, '/dispenser_states', state_qos)
        self.ingestor_states = self.create_publisher(
            IngestorState, '/ingestor_states', state_qos)
        self.dispenser_results = self.create_publisher(
            DispenserResult, '/dispenser_results', 10)
        self.ingestor_results = self.create_publisher(
            IngestorResult, '/ingestor_results', 10)

        self.cells = [
            Workcell(self, robot_id, namespace, model, dispensers, ingestors, policies)
            for robot_id, namespace, model, dispensers, ingestors, policies in WORKCELLS
        ]

        # Fleet adapter의 요청은 transient local이다. 워크셀이 늦게 떠도 이미
        # 보낸 픽업 요청을 받아야 하므로 같은 QoS로 구독한다.
        self.create_subscription(
            DispenserRequest, '/dispenser_requests',
            lambda msg: self.on_request(msg, dispenser=True), state_qos)
        self.create_subscription(
            IngestorRequest, '/ingestor_requests',
            lambda msg: self.on_request(msg, dispenser=False), state_qos)

        # 로봇이 정말 그 자리에 그 자세로 섰는지 보는 곳. 어댑터가 10Hz 로
        # 낸다. RMF 가 "도착했다" 고 말하는 것과 로봇이 실제로 그렇게 선
        # 것은 다른 이야기라, 팔을 움직이기 전에 여기서 직접 확인한다.
        self.robot_pose = {}
        self.create_subscription(
            FleetState, '/fleet_states', self.on_fleet_state, 10)

        # 상태를 안 내면 RMF 가 이 워크셀을 없는 것으로 보고 요청조차 안 한다.
        self.create_timer(1.0, self.publish_states)
        self.create_timer(WATCHDOG_PERIOD, self.watch)

        served = sum(len(c.dispensers) + len(c.ingestors) for c in self.cells)
        self.get_logger().info(
            f'워크셀 {len(self.cells)}대, 맡은 자리 {served}곳을 RMF 에 이었습니다.')
        if DOCK_HEADINGS:
            places = ', '.join(
                f'{name} {math.degrees(yaw):.0f}도'
                for name, yaw in sorted(DOCK_HEADINGS.items()))
            self.get_logger().info(f'적재 방향을 정해 둔 자리: {places}')

    # ── 로봇이 어디에 어떻게 서 있나 ──────────────────────────────────────

    def on_fleet_state(self, msg):
        for robot in msg.robots:
            previous = self.robot_pose.get(robot.name)
            location = robot.location
            # 시뮬 시계 시각. 속도를 여기서 뽑는다 — 벽시계로 나누면 시뮬이
            # 느릴 때 달리는 로봇도 섰다고 나온다.
            stamp = location.t.sec + location.t.nanosec * 1e-9
            # 첫 소식만으로는 섰는지 알 수 없다. 속도는 **두 소식 사이**에서
            # 나오므로 한 건으로는 잴 것이 없다. 0 으로 채워 두면 방금 처음
            # 본 로봇이 멈춰 있는 것으로 보여, 달려오는 중에 팔이 움직인다.
            speed = None
            turn_rate = None
            if previous is not None:
                span = stamp - previous['stamp']
                if span > 1e-6:
                    speed = math.hypot(location.x - previous['x'],
                                       location.y - previous['y']) / span
                    turn_rate = abs(
                        wrap_angle(location.yaw - previous['yaw'])) / span
                else:
                    # 같은 시각이 두 번 왔다. 이전 값을 그대로 들고 간다 —
                    # 모른다고 하면 그때마다 처음부터 다시 기다리게 된다.
                    speed = previous['speed']
                    turn_rate = previous['turn_rate']
            self.robot_pose[robot.name] = {
                'x': location.x,
                'y': location.y,
                'yaw': location.yaw,
                'stamp': stamp,
                'speed': speed,
                'turn_rate': turn_rate,
                'at': time.monotonic(),
            }

    def robot_problem(self, job):
        """로봇이 팔을 움직여도 되는 상태인가. 괜찮으면 None, 아니면 이유."""
        if not job.robot_name:
            # 어댑터가 `transporter_type` 에 로봇 이름을 넣는다. 비어 있으면
            # 어느 로봇인지 알 수 없어 확인 자체를 못 한다.
            return '요청에 로봇 이름이 없습니다'
        pose = self.robot_pose.get(job.robot_name)
        if pose is None:
            return f'{job.robot_name} 의 위치를 /fleet_states 에서 못 받았습니다'
        age = time.monotonic() - pose['at']
        if age > FLEET_STATE_MAX_AGE:
            return f'{job.robot_name} 의 마지막 소식이 {age:.1f}초 전입니다'
        if pose['speed'] is None:
            return f'{job.robot_name} 의 소식이 아직 한 건뿐입니다'
        if pose['speed'] > ROBOT_STILL_SPEED or \\
                pose['turn_rate'] > ROBOT_STILL_TURN_RATE:
            return (f'{job.robot_name} 이 아직 움직이고 있습니다 '
                    f'({pose["speed"]:.3f}m/s · '
                    f'{math.degrees(pose["turn_rate"]):.1f}도/s)')
        if job.required_yaw is None:
            return None
        error = abs(wrap_angle(pose['yaw'] - job.required_yaw))
        if error > DOCK_YAW_TOLERANCE:
            return (f'{job.robot_name} 이 {math.degrees(pose["yaw"]):.1f}도를 '
                    f'보고 있습니다. 이 자리는 '
                    f'{math.degrees(job.required_yaw):.1f}도가 필요합니다 '
                    f'(차이 {math.degrees(error):.1f}도)')
        return None

    def robot_left(self, job):
        """적재를 시작한 자리를 떠났나. 안 떠났으면 None, 떠났으면 이유.

        **시작할 때의 자세와 견준다.** 눈금 사이의 차이로 재면 도착 직후의
        떨림(실측 3.4도)이 그대로 중단 사유가 된다. 잡으려는 것은 떨림이
        아니라 로봇이 자리를 뜬 것이다.
        """
        if job.anchor is None:
            return None
        pose = self.robot_pose.get(job.robot_name)
        if pose is None:
            return None
        age = time.monotonic() - pose['at']
        if age > FLEET_STATE_MAX_AGE:
            return f'{job.robot_name} 의 마지막 소식이 {age:.1f}초 전입니다'
        moved = math.hypot(pose['x'] - job.anchor['x'],
                           pose['y'] - job.anchor['y'])
        if moved > ARM_ABORT_METERS:
            return (f'{job.robot_name} 이 적재를 시작한 자리에서 '
                    f'{moved*100:.0f}cm 벗어났습니다')
        turned = abs(wrap_angle(pose['yaw'] - job.anchor['yaw']))
        if turned > ARM_ABORT_RADIANS:
            return (f'{job.robot_name} 이 적재를 시작한 자세에서 '
                    f'{math.degrees(turned):.0f}도 돌았습니다')
        return None

    def publish_states(self):
        for cell in self.cells:
            mode = DispenserState.BUSY if cell.busy else DispenserState.IDLE
            for guid in cell.dispensers:
                self.dispenser_states.publish(DispenserState(
                    time=now_msg(self), guid=guid, mode=mode,
                    request_guid_queue=[], seconds_remaining=0.0))
            for guid in cell.ingestors:
                self.ingestor_states.publish(IngestorState(
                    time=now_msg(self), guid=guid, mode=mode,
                    request_guid_queue=[], seconds_remaining=0.0))

    # `handle` 이라고 부르면 안 된다. rclpy 의 Node 가 같은 이름의 속성을
    # 쓰는데, 메서드로 덮으면 Node.__init__ 이 `with self.handle:` 에서
    # TypeError 로 죽는다 — 노드가 아예 안 뜬다.
    def on_request(self, msg, dispenser):
        cell = next((c for c in self.cells if c.serves(msg.target_guid)), None)
        if cell is None:
            # 우리 것이 아니다. 남의 워크셀 요청일 수 있으므로 조용히 넘긴다.
            return

        # 같은 요청은 답을 받을 때까지 반복된다. 같은 GUID로 팔을 두 번
        # 움직이지 않고, 현재 상태만 다시 답한다.
        with cell.lock:
            if msg.request_guid in cell.completed_requests:
                repeated_status = DispenserResult.SUCCESS
            elif cell.active_request == msg.request_guid:
                repeated_status = DispenserResult.ACKNOWLEDGED
            else:
                repeated_status = None
            if repeated_status is not None:
                pass
            elif cell.busy:
                return
            else:
                cell.busy = True
                cell.active_request = msg.request_guid
        if repeated_status is not None:
            self.answer(msg, dispenser, repeated_status)
            return

        self.get_logger().info(
            f'[{cell.robot_id}] {msg.target_guid} 요청 받음 '
            f'({msg.request_guid})')
        self.answer(msg, dispenser, DispenserResult.ACKNOWLEDGED)

        # 무엇으로 움직일지 정하는 사다리.
        #
        #   ① 이 팔에 붙인 학습 policy + ZIP + 러너가 다 있으면 → 러너로 추론
        #   ② 붙어는 있으나 러너가 없거나 ZIP 이 없으면   → 시험 동작 (이유를 남김)
        #   ③ 가상 policy(policy_1..5)                   → 그 policy 의 궤적
        #   ④ 붙인 policy 가 없으면(armLoad)             → 시험 동작
        #
        # 어느 길로 가든 **끝났다는 것을 확인한 뒤** RMF 에 성공을 알린다.
        # 그래야 다음 단계로 넘어간다.
        policy_id = msg.items[0].type_guid if msg.items else 'armLoad'
        is_deployed = policy_id in cell.deployed_policies
        if (policy_id != 'armLoad' and policy_id not in POLICY_MOTIONS
                and not is_deployed):
            # 이 팔에 붙지 않은 policy 다. 조용히 다른 동작으로 바꾸면 어느
            # 팔이 무엇을 했는지 알 수 없게 되므로 실패로 답한다.
            self.fail(
                cell, msg, dispenser,
                f'[{cell.robot_id}] 에 붙지 않은 policy 입니다 [{policy_id}] — '
                f'붙은 것: {sorted(cell.deployed_policies) or "없음"}')
            return

        archive = cell.policy_archive(policy_id) if is_deployed else None
        runner_ready = bool(POLICY_RUNNER) and os.path.exists(POLICY_RUNNER)
        replay_name = policy_id.split('@', 1)[0].lower()
        if is_deployed and archive is not None and runner_ready:
            self.get_logger().info(
                f'[{cell.robot_id}] [{policy_id}] 학습 policy 로 움직입니다')
            trajectory = None
        elif (is_deployed and cell.model == 'omx_f'
                and replay_name in ('sandwich', 'sandwitch')):
            trajectory = cell.sandwich_replay_trajectory(policy_id)
        elif is_deployed:
            trajectory = cell.test_trajectory(
                f'[{policy_id}] 학습 결과 파일이 없어' if archive is None
                else f'[{policy_id}] 러너({POLICY_RUNNER})가 없어')
            archive = None
        elif policy_id == 'armLoad':
            trajectory = cell.test_trajectory('붙인 policy 가 없어')
        else:
            self.get_logger().info(
                f'[{cell.robot_id}] 물품 [{policy_id}] 가상 policy 실행')
            trajectory = cell.policy_trajectory(policy_id, ACTION_SECONDS)

        # 팔이 없으면 시작하지 않는다. 예전에는 토픽에 던지고 4초 뒤 성공이라
        # 답했으므로, 팔이 아예 안 떠 있어도 작업이 그대로 넘어갔다.
        if not cell.arm.server_is_ready():
            self.fail(
                cell, msg, dispenser,
                f'팔이 없습니다. {cell.arm_action_name} 액션 서버가 안 보입니다')
            return

        job = Job(msg, dispenser, msg.transporter_type,
                  DOCK_HEADINGS.get(msg.target_guid), trajectory,
                  policy_id=policy_id if archive is not None else None,
                  policy_archive=archive)
        with cell.lock:
            cell.job = job
        # 로봇이 설 때까지 감시자가 기다렸다가 보낸다. 여기서 바로 보내면
        # 마지막 몇 도를 돌고 있는 멀쩡한 로봇을 거절하게 된다.

    # ── 단계를 넘기는 쪽. 전부 토픽·액션이 알려 준 것으로만 정한다 ────────

    def watch(self):
        for cell in self.cells:
            job = cell.job
            if job is None:
                continue
            if job.stage == 'waiting_robot':
                self.watch_robot(cell, job)
            elif job.stage == 'policy':
                self.watch_policy(cell, job)
            elif job.stage == 'moving':
                self.watch_arm(cell, job)
            elif job.stage == 'settling':
                self.watch_settle(cell, job)

    def watch_robot(self, cell, job):
        problem = self.robot_problem(job)
        if problem is None:
            job.stage = 'moving'
            job.deadline = time.monotonic() + ARM_RESULT_TIMEOUT
            # 지금 이 자리가 기준이 된다. 적재 중에는 여기서 얼마나 벗어났나만
            # 본다.
            pose = self.robot_pose.get(job.robot_name)
            job.anchor = None if pose is None else dict(pose)
            if job.policy_archive is not None:
                self.start_policy_runner(cell, job)
                return
            self.get_logger().info(
                f'[{cell.robot_id}] {job.msg.target_guid}: 로봇이 제자리에 '
                '섰습니다. 팔을 움직입니다.')
            goal = FollowJointTrajectory.Goal()
            goal.trajectory = job.trajectory
            future = cell.arm.send_goal_async(goal)
            future.add_done_callback(
                lambda done: self.on_arm_accepted(cell, job, done))
            return
        if time.monotonic() > job.deadline:
            self.fail(cell, job.msg, job.dispenser, f'로봇을 기다리다 지쳤습니다 — {problem}')

    def on_arm_accepted(self, cell, job, future):
        if cell.job is not job:
            return
        try:
            handle = future.result()
        except Exception as error:
            self.fail(cell, job.msg, job.dispenser, f'팔에 궤적을 못 보냈습니다: {error}')
            return
        if not handle.accepted:
            self.fail(cell, job.msg, job.dispenser, '팔이 궤적을 거절했습니다')
            return
        job.goal_handle = handle
        handle.get_result_async().add_done_callback(
            lambda done: self.on_arm_result(cell, job, done))

    def on_arm_result(self, cell, job, future):
        if cell.job is not job:
            return
        try:
            result = future.result().result
        except Exception as error:
            self.fail(cell, job.msg, job.dispenser, f'팔의 결과를 못 받았습니다: {error}')
            return
        if result.error_code != FollowJointTrajectory.Result.SUCCESSFUL:
            self.fail(
                cell, job.msg, job.dispenser,
                f'팔이 궤적을 못 끝냈습니다 (error_code={result.error_code} '
                f'{result.error_string})')
            return
        job.stage = 'settling'
        job.deadline = time.monotonic() + ARM_SETTLE_SECONDS

    # ── 학습 policy 를 실제로 돌리는 쪽 ───────────────────────────────────

    def start_policy_runner(self, cell, job):
        """이 팔에 붙인 학습 policy 로 움직이게 한다.

        **Gazebo 든 실물이든 같은 러너다.** 네임스페이스만 달리 받아 그 팔의
        `joint_states` 를 보고 그 팔의 컨트롤러로 낸다 — 시뮬과 실물의 차이는
        토픽 뒤에 무엇이 붙어 있느냐뿐이다.

        못 띄우면 여기서 작업을 실패시키지 않는다. 시험 동작으로 갈아타 다음
        단계로 넘어가게 하고, 왜 추론이 안 돌았는지는 로그에 남긴다.
        """
        command = [
            sys.executable, POLICY_RUNNER,
            '--policy', job.policy_archive,
            '--policy-id', job.policy_id,
            '--namespace', cell.namespace,
            '--model', cell.model,
            '--seconds', str(ACTION_SECONDS),
        ]
        try:
            log = open(POLICY_LOG, 'a', buffering=1)
            at = time.strftime('%Y-%m-%d %H:%M:%S')
            log.write(f'\\n=== {at} {cell.robot_id} {job.policy_id} ===\\n')
            job.process = subprocess.Popen(
                command, stdout=log, stderr=subprocess.STDOUT)
        except Exception as error:
            self.get_logger().error(
                f'[{cell.robot_id}] policy 러너를 못 띄웠습니다: {error}')
            self.fall_back_to_test(cell, job, f'[{job.policy_id}] 러너를 못 띄워')
            return
        job.stage = 'policy'
        job.deadline = time.monotonic() + POLICY_TIMEOUT
        self.get_logger().info(
            f'[{cell.robot_id}] [{job.policy_id}] 학습 policy 추론 시작 — '
            f'기록은 {POLICY_LOG}')

    def watch_policy(self, cell, job):
        """추론이 끝나기를 기다린다. 끝나야 RMF 에 성공을 알린다."""
        # 적재 중에 로봇이 자리를 뜨면 팔 궤적 때와 똑같이 중단한다.
        problem = self.robot_left(job)
        if problem is not None:
            self.stop_runner(job)
            self.fail(cell, job.msg, job.dispenser,
                      f'적재 중에 로봇이 자리를 떴습니다 — {problem}')
            return
        code = job.process.poll() if job.process is not None else 1
        if code is None:
            if time.monotonic() > job.deadline:
                self.stop_runner(job)
                self.fail(
                    cell, job.msg, job.dispenser,
                    f'[{job.policy_id}] 추론이 {POLICY_TIMEOUT:.0f}초 안에 '
                    '안 끝났습니다')
            return
        if code == 0:
            self.get_logger().info(
                f'[{cell.robot_id}] [{job.policy_id}] 추론 동작을 끝냈습니다')
            job.stage = 'settling'
            job.deadline = time.monotonic() + ARM_SETTLE_SECONDS
            return
        # 추론기가 이 자리에 없거나 policy 를 못 읽었다. 작업까지 멈추지는
        # 않는다 — 무엇이 없어서 못 했는지만 분명히 남기고 시험 동작으로 간다.
        self.get_logger().warning(
            f'[{cell.robot_id}] [{job.policy_id}] 추론이 안 됐습니다 '
            f'(종료 코드 {code}). 까닭은 {POLICY_LOG} 에 있습니다.')
        self.fall_back_to_test(cell, job, f'[{job.policy_id}] 추론이 안 돼')

    def stop_runner(self, job):
        if job.process is None or job.process.poll() is not None:
            return
        job.process.terminate()
        try:
            job.process.wait(timeout=5)
        except Exception:
            job.process.kill()

    def fall_back_to_test(self, cell, job, reason):
        """추론 대신 시험 동작으로 간다.

        팔이 정말 움직이고 끝냈는지는 그대로 확인한다. 확인 없이 성공만
        돌려주면 팔이 안 떠 있어도 작업이 넘어간다.
        """
        job.policy_archive = None
        job.process = None
        job.trajectory = cell.test_trajectory(reason)
        job.stage = 'moving'
        job.deadline = time.monotonic() + ARM_RESULT_TIMEOUT
        goal = FollowJointTrajectory.Goal()
        goal.trajectory = job.trajectory
        future = cell.arm.send_goal_async(goal)
        future.add_done_callback(
            lambda done: self.on_arm_accepted(cell, job, done))

    def watch_arm(self, cell, job):
        # 적재 중에도 로봇이 그 자리에 있는지 계속 본다. 자리를 뜨면 물건이
        # 엉뚱한 곳에 놓이므로 궤적을 취소하고 실패로 답한다.
        #
        # 시작한 자리와 견준다. 눈금 사이의 차이로 재면 도착 직후의 떨림이
        # 그대로 중단 사유가 된다 — 실제로 그래서 멀쩡한 적재가 1초 만에
        # 끊겼다(2026-08-17, 0.6cm · 3.4도).
        problem = self.robot_left(job)
        if problem is not None:
            if job.goal_handle is not None:
                job.goal_handle.cancel_goal_async()
            self.fail(cell, job.msg, job.dispenser,
                      f'적재 중에 로봇이 자리를 떴습니다 — {problem}')
            return
        if time.monotonic() > job.deadline:
            if job.goal_handle is not None:
                job.goal_handle.cancel_goal_async()
            self.fail(
                cell, job.msg, job.dispenser,
                f'팔이 {ARM_RESULT_TIMEOUT:.0f}초 안에 안 끝났습니다')

    def watch_settle(self, cell, job):
        """팔이 멎기를 잠깐 기다린다. **막지는 않는다.**

        끝났다고 정하는 것은 액션 결과다. 컨트롤러가 `Goal reached, success!`
        를 냈으면 궤적은 끝난 것이고, 여기는 로봇이 곧바로 튀어 나가지 않게
        두는 짧은 여유일 뿐이다.

        여기서 거부하면 안 된다. 예전에는 `joint_states` 속도가 문턱 아래로
        안 내려가면 실패로 답했는데, 이 팔은 **멈춰 있어도** 그 값이 안
        내려간다. 실측(2026-08-17, OMX in Gazebo, 표본 148) —

            최소 0.113  중앙 1.291  최대 1.443  [rad/s]
            0.02 아래인 비율 0%   0.10 아래인 비율 0%

        그래서 픽업이 매번 실패했다. 팔은 멀쩡히 끝냈는데도 —

            [omx_01.arm_controller] Goal reached, success!
            [omx_01] 픽업3: 팔이 5초가 지나도 안 멎었습니다   ← 여기서 막힘
        """
        if cell.arm_still() is True:
            self.succeed(cell, job)
            return
        if time.monotonic() <= job.deadline:
            return
        # 여유를 다 썼다. 액션이 끝났다고 했으므로 그 말을 믿는다.
        if not cell.warned_arm_velocity:
            cell.warned_arm_velocity = True
            measured = ('못 읽음' if cell.joint_velocity is None
                        else f'{cell.joint_velocity:.3f} rad/s')
            self.get_logger().warning(
                f'[{cell.robot_id}] {cell.namespace}/joint_states 로는 팔이 '
                f'멎었는지 알 수 없습니다 (속도 {measured}). 액션 결과만 믿고 '
                '넘어갑니다. 이 줄은 한 번만 적습니다.')
        self.succeed(cell, job)

    def succeed(self, cell, job):
        with cell.lock:
            cell.busy = False
            cell.active_request = None
            cell.completed_requests.add(job.msg.request_guid)
            cell.job = None
        self.get_logger().info(f'[{cell.robot_id}] {job.msg.target_guid} 끝.')
        self.answer(job.msg, job.dispenser, DispenserResult.SUCCESS)

    def fail(self, cell, msg, dispenser, reason):
        """실패를 **말한다.** 조용히 두면 RMF 가 영원히 기다린다.

        답할 요청을 인자로 받는다. `cell.job` 에서 꺼내면, 아직 job 을 만들기
        전에 걸린 실패(모르는 policy · 팔 없음)에서 답할 곳을 잃는다.
        """
        # 추론이 돌고 있었으면 먼저 세운다. 두고 나가면 팔이 계속 움직인다.
        if cell.job is not None:
            self.stop_runner(cell.job)
        with cell.lock:
            cell.busy = False
            cell.active_request = None
            cell.job = None
        self.get_logger().error(
            f'[{cell.robot_id}] {msg.target_guid}: {reason}')
        self.answer(msg, dispenser, DispenserResult.FAILED)

    def answer(self, msg, dispenser, status):
        if dispenser:
            self.dispenser_results.publish(DispenserResult(
                time=now_msg(self), request_guid=msg.request_guid,
                source_guid=msg.target_guid, status=status))
        else:
            self.ingestor_results.publish(IngestorResult(
                time=now_msg(self), request_guid=msg.request_guid,
                source_guid=msg.target_guid, status=status))


def main(argv=sys.argv):
    rclpy.init(args=argv)
    node = WorkcellAdapter()
    try:
        rclpy.spin(node)
    except KeyboardInterrupt:
        pass
    node.destroy_node()
    if rclpy.ok():
        rclpy.shutdown()


if __name__ == '__main__':
    main()
''';
}

/// 붙여 둔 학습 policy 로 로봇팔을 움직이는 실행기.
///
/// 워크셀 노드가 픽업 요청을 받으면 이것을 따로 띄우고 **종료 코드로만** 판단
/// 한다. 0 이면 추론 동작을 끝낸 것이고, 0 이 아니면 이 자리에 추론기가 없다는
/// 뜻이라 노드가 시험 동작으로 대신한다 — 작업은 어느 쪽이든 다음 단계로 간다.
///
/// Gazebo 와 실물을 가리지 않는다. 받는 것은 네임스페이스 하나뿐이고, 그 뒤에
/// 시뮬레이터가 있든 실제 컨트롤러가 있든 토픽은 같다.
String buildPolicyRunnerScript({required String mapName}) =>
    '''#!/usr/bin/env python3
"""$mapName 프로젝트의 학습 policy 실행기.

rmf_control_ui 가 맵 프로젝트에서 생성했다. 손으로 고치면 다음 저장 때
덮어써진다.

하는 일은 하나다 — **붙여 둔 policy 로 그 팔을 움직이고 끝나면 0 으로 끝난다.**

    /<네임스페이스>/joint_states                    관측(관절 위치)
    /<네임스페이스>/arm_controller/joint_trajectory 명령
    /<네임스페이스>/camera/image_raw                policy 가 이미지를 볼 때만

Gazebo 와 실물의 차이는 그 토픽 뒤에 무엇이 붙어 있느냐뿐이라, 같은 러너가
둘 다 움직인다.

**추론기가 없는 것은 오류가 아니다.** torch·lerobot 이 이 자리에 없으면 2 로
끝내고, 워크셀 노드가 시험 동작으로 대신한다. 그래야 추론기를 아직 안 깐
자리에서도 RMF 작업이 멈추지 않는다.

종료 코드
    0  추론 동작을 끝냈다
    2  추론기가 없거나 policy 를 못 읽었다
    3  관절 상태가 안 온다 (팔이 안 떠 있다)
    4  policy 압축이 이상하다
"""

import argparse
import json
import os
import sys
import time
import zipfile

# 관측을 몇 Hz 로 넣고 명령을 몇 Hz 로 낼지.
CONTROL_HZ = 10.0

# 첫 관절 상태를 이만큼 기다린다 [s]. 안 오면 팔이 없는 것이다.
OBSERVATION_TIMEOUT = 10.0

# 명령 하나가 목표에 닿을 시간 [s]. 너무 짧으면 컨트롤러가 따라오지 못한다.
COMMAND_HORIZON = 0.3

# 끝내고 집으로 돌아가는 데 주는 시간 [s].
HOME_SECONDS = 2.0


def log(message):
    print(f'[policy_runner] {message}', flush=True)


def unpack(archive, policy_id):
    """policy ZIP 을 캐시에 한 번만 푼다. 수백 MB 를 매번 풀 이유가 없다."""
    safe = ''.join(c if c.isalnum() or c in '-_' else '_' for c in policy_id)
    target = os.path.join(
        os.path.expanduser('~/.cache/robosapiens/policies'), safe)
    marker = os.path.join(target, 'config.json')
    if os.path.exists(marker):
        return target
    os.makedirs(target, exist_ok=True)
    try:
        with zipfile.ZipFile(archive) as bundle:
            for entry in bundle.namelist():
                # ZIP 안의 경로를 그대로 믿지 않는다.
                if entry.startswith('/') or '..' in entry.split('/'):
                    continue
                bundle.extract(entry, target)
    except (zipfile.BadZipFile, OSError) as error:
        log(f'policy 압축을 못 풀었습니다: {error}')
        sys.exit(4)
    if not os.path.exists(marker):
        log('config.json 이 없습니다. LeRobot policy 가 아닙니다.')
        sys.exit(4)
    return target


def load_policy(directory):
    """LeRobot policy 를 불러온다. 추론기가 없으면 2 로 끝낸다."""
    try:
        import torch
    except Exception as error:
        log(f'torch 가 없습니다: {error}')
        log('이 자리에는 추론기가 없습니다. 워크셀이 시험 동작으로 대신합니다.')
        sys.exit(2)
    loaders = []
    try:
        from lerobot.common.policies.factory import get_policy_class
        loaders.append(lambda: get_policy_class(
            json.load(open(os.path.join(directory, 'config.json')))
            .get('type', 'act')).from_pretrained(directory))
    except Exception:
        pass
    try:
        from lerobot.common.policies.act.modeling_act import ACTPolicy
        loaders.append(lambda: ACTPolicy.from_pretrained(directory))
    except Exception:
        pass
    if not loaders:
        log('lerobot 이 없습니다. 워크셀이 시험 동작으로 대신합니다.')
        sys.exit(2)
    last = None
    for loader in loaders:
        try:
            policy = loader()
            policy.eval()
            return torch, policy
        except Exception as error:
            last = error
    log(f'policy 를 못 불러왔습니다: {last}')
    sys.exit(2)


def image_features(directory):
    """policy 가 이미지를 요구하는가. 요구하면 그 키 이름들."""
    try:
        with open(os.path.join(directory, 'config.json')) as handle:
            config = json.load(handle)
    except Exception:
        return []
    features = config.get('input_features') or {}
    return [key for key in features if 'image' in key]


def to_array(numpy, message):
    """sensor_msgs/Image 를 HxWx3 배열로. cv_bridge 없이 직접 옮긴다."""
    data = numpy.frombuffer(message.data, dtype=numpy.uint8)
    frame = data.reshape(message.height, message.width, -1)
    if message.encoding == 'bgr8':
        frame = frame[:, :, ::-1]
    return frame[:, :, :3]


def main(argv):
    parser = argparse.ArgumentParser()
    parser.add_argument('--policy', required=True, help='policy ZIP 자리')
    parser.add_argument('--policy-id', required=True)
    parser.add_argument('--namespace', required=True)
    parser.add_argument('--model', default='')
    parser.add_argument('--seconds', type=float, default=6.0)
    args = parser.parse_args(argv[1:])

    if not os.path.exists(args.policy):
        log(f'학습 결과 파일이 없습니다: {args.policy}')
        log('앱의 `Policy 관리` 에서 다시 받으세요.')
        sys.exit(2)

    directory = unpack(args.policy, args.policy_id)
    torch, policy = load_policy(directory)
    images = image_features(directory)
    import numpy

    import rclpy
    import rclpy.node
    from sensor_msgs.msg import Image, JointState
    from trajectory_msgs.msg import JointTrajectory, JointTrajectoryPoint

    rclpy.init(args=argv)
    node = rclpy.node.Node('policy_runner')
    state = {'joints': None, 'names': None, 'frame': None}

    def on_joint_state(message):
        state['names'] = list(message.name)
        state['joints'] = list(message.position)

    def on_image(message):
        state['frame'] = to_array(numpy, message)

    node.create_subscription(
        JointState, f'/{args.namespace}/joint_states', on_joint_state, 10)
    if images:
        node.create_subscription(
            Image, f'/{args.namespace}/camera/image_raw', on_image, 1)
    command = node.create_publisher(
        JointTrajectory,
        f'/{args.namespace}/arm_controller/joint_trajectory', 10)

    # 팔이 무엇을 하고 있는지 알기 전에는 명령하지 않는다.
    deadline = time.monotonic() + OBSERVATION_TIMEOUT
    while state['joints'] is None and time.monotonic() < deadline:
        rclpy.spin_once(node, timeout_sec=0.1)
    if state['joints'] is None:
        log(f'/{args.namespace}/joint_states 가 안 옵니다. 팔이 떠 있습니까?')
        node.destroy_node()
        rclpy.shutdown()
        sys.exit(3)
    if images and state['frame'] is None:
        log('policy 가 이미지를 요구하는데 카메라 토픽이 안 옵니다: '
            f'/{args.namespace}/camera/image_raw')
        node.destroy_node()
        rclpy.shutdown()
        sys.exit(3)

    home = list(state['joints'])
    names = list(state['names'])
    log(f'[{args.policy_id}] 추론 시작 — 관절 {len(names)}개, '
        f'이미지 {len(images)}개, {args.seconds:.1f}초')

    period = 1.0 / CONTROL_HZ
    finish = time.monotonic() + args.seconds
    sent = 0
    while time.monotonic() < finish:
        rclpy.spin_once(node, timeout_sec=period)
        observation = {
            'observation.state': torch.tensor(
                [state['joints']], dtype=torch.float32),
        }
        for key in images:
            if state['frame'] is None:
                continue
            frame = numpy.ascontiguousarray(
                state['frame'].transpose(2, 0, 1))
            observation[key] = torch.tensor(
                frame[None], dtype=torch.float32) / 255.0
        try:
            with torch.no_grad():
                action = policy.select_action(observation)
        except Exception as error:
            log(f'추론이 실패했습니다: {error}')
            node.destroy_node()
            rclpy.shutdown()
            sys.exit(2)
        target = [float(value) for value in action.squeeze(0).tolist()]
        if len(target) < len(names):
            # 액션이 관절보다 적으면 앞에서부터 채우고 나머지는 그대로 둔다.
            target = target + list(state['joints'])[len(target):]
        message = JointTrajectory()
        message.joint_names = names[:len(target)]
        point = JointTrajectoryPoint()
        point.positions = target[:len(message.joint_names)]
        point.time_from_start.sec = int(COMMAND_HORIZON)
        point.time_from_start.nanosec = int((COMMAND_HORIZON % 1) * 1e9)
        message.points.append(point)
        command.publish(message)
        sent += 1

    # 끝내고 시작 자세로 돌아간다. 다음 요청이 늘 같은 자리에서 시작하도록.
    message = JointTrajectory()
    message.joint_names = names
    point = JointTrajectoryPoint()
    point.positions = home
    point.time_from_start.sec = int(HOME_SECONDS)
    message.points.append(point)
    command.publish(message)
    end = time.monotonic() + HOME_SECONDS
    while time.monotonic() < end:
        rclpy.spin_once(node, timeout_sec=0.1)

    log(f'[{args.policy_id}] 추론 동작을 끝냈습니다 (명령 {sent}회)')
    node.destroy_node()
    if rclpy.ok():
        rclpy.shutdown()
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
''';

/// 파이썬 문자열 목록 리터럴.
String _pyList(List<String> values) =>
    '[${values.map((value) => "'$value'").join(', ')}]';
