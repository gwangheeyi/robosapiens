/// 맵 프로젝트에서 Open-RMF 설정 파일을 만든다.
///
/// 플릿 설정은 맵을 따라간다. 맵이 다르면 Waypoint 이름도 충전소 위치도 다르므로
/// 전역 fleet.yaml 하나를 돌려 쓰면 프로젝트를 바꾸는 순간 어긋난다.
///
/// 여기서 만든 결과는 `map_project_files` 에 프로젝트별로 보관한다.
library;

import 'nav2_params.dart' show nav2MapTopic, nav2MapTopicName;

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

  static RmfRobotKind parse(String? value) => value == 'workcell'
      ? RmfRobotKind.workcell
      : RmfRobotKind.mobile;

  String get storageValue => name;
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
  });

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
    this.reversible = true,
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
  });

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
  RmfFleetSettings withRobotSafety({
    required double widthMeters,
    required double localizationMarginMeters,
  }) => copyWith(
    footprintRadius: widthMeters / 2,
    vicinityRadius: widthMeters / 2 + localizationMarginMeters,
  );

  RmfFleetSettings copyWith({
    String? fleetName,
    double? footprintRadius,
    double? vicinityRadius,
  }) => RmfFleetSettings(
    fleetName: fleetName ?? this.fleetName,
    linearVelocity: linearVelocity,
    linearAcceleration: linearAcceleration,
    angularVelocity: angularVelocity,
    angularAcceleration: angularAcceleration,
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
    );
  }
}

String _n(double value) => value.toStringAsFixed(3);

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
    ..writeln('  reversible: ${fleet.reversible ? 'True' : 'False'}')
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
    ..writeln('  actions: ["teleop"]')
    ..writeln('  finishing_request: "park"')
    ..writeln('  responsive_wait: True')
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
String buildProjectLaunchXml({
  required String mapName,
  required String fleetName,
  required String mapDirectory,
  required String buildingYamlName,
  bool useSimTime = true,
  String serverUri = 'ws://127.0.0.1:8000/_internal',
}) {
  final buffer = StringBuffer()
    ..writeln("<?xml version='1.0' ?>")
    ..writeln('<!--')
    ..writeln('  $mapName 프로젝트 실행 launch.')
    ..writeln('  rmf_control_ui 가 맵 프로젝트에서 생성했다. 손으로 고치면')
    ..writeln('  다음 저장 때 덮어써진다.')
    ..writeln('')
    ..writeln('  실행:')
    ..writeln('    source /opt/ros/jazzy/setup.bash')
    ..writeln('    source \$HOME/rmf_ws/install/setup.bash')
    ..writeln('    ros2 launch $mapDirectory/$mapName.launch.xml')
    ..writeln('-->')
    ..writeln('<launch>')
    ..writeln('  <arg name="use_sim_time" default="$useSimTime"/>')
    ..writeln('  <arg name="headless" default="true"/>')
    ..writeln('  <arg name="server_uri" default="$serverUri"/>')
    ..writeln('  <arg name="map_dir" default="$mapDirectory"/>')
    ..writeln('')
    ..writeln('  <!-- RMF core. 이것이 먼저 떠야 fleet adapter 가 붙는다. -->')
    ..writeln(
      '  <include file="\$(find-pkg-share rmf_demos)/common.launch.xml">',
    )
    ..writeln('    <arg name="use_sim_time" value="\$(var use_sim_time)"/>')
    ..writeln('    <arg name="headless" value="\$(var headless)"/>')
    ..writeln(
      '    <arg name="config_file" value="\$(var map_dir)/$buildingYamlName"/>',
    )
    ..writeln('    <arg name="server_uri" value="\$(var server_uri)"/>')
    ..writeln('  </include>')
    ..writeln('')
    ..writeln('  <!-- 이 프로젝트의 플릿. 설정과 nav graph 모두 이 맵의 것이다. -->')
    ..writeln(
      '  <include file="\$(find-pkg-share rmf_demos_fleet_adapter)'
      '/launch/fleet_adapter.launch.xml">',
    )
    ..writeln('    <arg name="use_sim_time" value="\$(var use_sim_time)"/>')
    ..writeln(
      '    <arg name="config_file" value="\$(var map_dir)'
      '/${fleetName}_config.yaml"/>',
    )
    ..writeln(
      '    <arg name="nav_graph_file" '
      'value="\$(var map_dir)/nav_graphs/0.yaml"/>',
    )
    ..writeln('    <arg name="server_uri" value="\$(var server_uri)"/>')
    ..writeln('  </include>')
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
    // 설치 로봇은 바퀴도 LiDAR 도 없다. 관절 상태만 오간다. 나머지는
    // ros2_control 이 컨트롤러 인터페이스로 직접 주고받는다.
    if (!robot.isMobile) {
      entry(
        buffer,
        ros: '$ns/joint_states',
        gz: '$ns/joint_states',
        rosType: 'sensor_msgs/msg/JointState',
        gzType: 'gz.msgs.Model',
        direction: 'GZ_TO_ROS',
      );
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
      ros: '$ns/camera/camera_info',
      gz: '$ns/camera/camera_info',
      rosType: 'sensor_msgs/msg/CameraInfo',
      gzType: 'gz.msgs.CameraInfo',
      direction: 'GZ_TO_ROS',
    );
  }
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
    ..writeln(
      '  <include file="\$(find-pkg-share ros_gz_sim)'
      '/launch/gz_sim.launch.py">',
    )
    ..writeln(
      '    <arg name="gz_args"'
      ' value="-r -s -v2 --headless-rendering \$(var world)"/>',
    )
    ..writeln('    <arg name="on_exit_shutdown" value="true"/>')
    ..writeln('  </include>')
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
      )
      ..writeln(
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

/// 프로젝트를 통째로 띄우는 셸 스크립트.
///
/// ROS 환경을 읽고 bringup 과 RMF 를 순서대로 띄운다. Gazebo 가 먼저 떠야
/// `/clock` 이 나오고, 그래야 use_sim_time 을 쓰는 RMF 노드가 시간을 맞춘다.
String buildProjectRunScript({
  required String mapName,
  required String mapDirectory,
  List<RmfProjectRobot> robots = const [],
  String rosSetup = '/opt/ros/jazzy/setup.bash',
  String rmfWorkspace = r'$HOME/rmf_ws',
  String pinkyWorkspace = r'$HOME/robosapiens/pinky_pro',
  String manipulatorWorkspace = r'$HOME/robosapiens/open_manipulator',
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

MAP_DIR="\${MAP_DIR:-$mapDirectory}"
ROS_SETUP="\${ROS_SETUP:-$rosSetup}"
RMF_WS="\${RMF_WS:-$rmfWorkspace}"
PINKY_WS="\${PINKY_WS:-$pinkyWorkspace}"
OMX_WS="\${OMX_WS:-$manipulatorWorkspace}"

# 이 프로젝트의 로봇이 실제로 쓰는 패키지. 등록된 로봇에서 뽑았다.
REQUIRED_PACKAGES="${_requiredPackages(robots).join(' ')}"
HEADLESS="\${HEADLESS:-true}"

for required in "\$MAP_DIR/$mapName.building.yaml" "\$MAP_DIR/nav_graphs/0.yaml"; do
  if [[ ! -f "\$required" ]]; then
    echo "없는 파일: \$required" >&2
    echo "앱의 맵 관리에서 배포하기와 RMF 설정 내보내기를 먼저 하세요." >&2
    exit 1
  fi
done

set +u
# shellcheck disable=SC1090
source "\$ROS_SETUP"
[[ -f "\$RMF_WS/install/setup.bash" ]] && source "\$RMF_WS/install/setup.bash"
[[ -f "\$PINKY_WS/install/setup.bash" ]] && source "\$PINKY_WS/install/setup.bash"
[[ -f "\$OMX_WS/install/setup.bash" ]] && source "\$OMX_WS/install/setup.bash"
set -u

# 모든 출력을 로그 파일로 보낸다.
#
# 앱이 이 스크립트를 파이프에 물려 띄우면, 그 파이프를 읽는 쪽이 없을 때
# 64KB 가 차는 순간 Gazebo 가 write 에서 영원히 멈춘다. 물리가 돌지 않아
# 모델도 안 올라오고 토픽에 값도 오지 않는다. 파일로 보내면 막힐 일이 없고,
# 무슨 일이 있었는지 나중에 볼 수도 있다.
LOG_FILE="\$MAP_DIR/$mapName.log"
exec > "\$LOG_FILE" 2>&1
echo "=== \$(date '+%Y-%m-%d %H:%M:%S') $mapName 실행 ==="

# 자기 프로세스 그룹 번호를 남긴다. 중지 스크립트가 이 그룹을 통째로 끊는다.
# 앱이 detached 로 띄우면 이 셸의 PID 는 그룹 리더가 아니므로, PID 가 아니라
# 실제 PGID 를 적어야 한다.
PGID_FILE="\$MAP_DIR/.$mapName.pgid"
ps -o pgid= -p \$\$ | tr -d ' ' > "\$PGID_FILE"

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

echo "[1/2] Gazebo bringup"
ros2 launch "\$MAP_DIR/${mapName}_bringup.launch.xml" headless:="\$HEADLESS" &
sleep 12

echo "[2/2] Open-RMF"
ros2 launch "\$MAP_DIR/$mapName.launch.xml" headless:="\$HEADLESS"
''';

/// 이 프로젝트로 띄운 것을 내리는 셸 스크립트.
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
RMF_WS="\${RMF_WS:-\$HOME/rmf_ws}"

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

echo "$mapName 프로젝트 프로세스를 정리했습니다."
''';

/// 로봇 한 대의 Nav2 를 띄우는 launch.
///
/// **네임스페이스 아래에서만 돈다.** 노드마다 이름을 걸지 않고 그룹에
/// `push-ros-namespace` 를 한 번 건다 — 두 번 걸면 `/pinky_01/pinky_01/amcl` 이
/// 되어 파라미터가 하나도 안 붙는다(`docs/MULTI_ROBOT_NAMESPACES.md` 함정 1).
///
/// `map_server` 는 여기 없다. 같은 건물이므로 **월드에 하나만** 띄운다.
String buildRobotNav2LaunchXml(RmfProjectRobot robot, String mapName) {
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
    ..writeln('  <arg name="use_sim_time" default="true"/>')
    ..writeln('  <group>')
    // 한 번만 건다. 아래 노드에는 네임스페이스를 따로 걸지 않는다.
    ..writeln('    <push-ros-namespace namespace="${robot.gzName}"/>')
    ..writeln('')
    ..writeln('    <!-- 라이다로 제 위치를 잡는다. map → ${robot.gzName}/odom -->')
    ..writeln('    <node pkg="nav2_amcl" exec="amcl" name="amcl"')
    ..writeln('          output="screen">')
    ..writeln(
      '      <param from="\$(dirname)/nav2_params.yaml"/>',
    )
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
        'value="${robot.gzName}/base_footprint"/>',
      );
    }
    buffer.writeln('    </node>');
  }
  buffer
    ..writeln('')
    ..writeln('    <!-- 위 노드들을 차례로 켜고 끈다. -->')
    ..writeln('    <node pkg="nav2_lifecycle_manager" exec="lifecycle_manager"')
    ..writeln('          name="lifecycle_manager_navigation" output="screen">')
    // 관리자는 sim 시간을 쓰지 않는다. 전이 응답을 기다리는 시간 제한이 sim
    // 시계에 걸리면 `Configuring` 에서 영영 멈춘다. 관리자가 하는 일은 순서대로
    // 켜고 끄는 것뿐이라 벽시계로 재는 것이 맞다.
    ..writeln('      <param name="use_sim_time" value="false"/>')
    ..writeln('      <param name="autostart" value="true"/>')
    ..writeln('      <param name="node_names"')
    ..writeln('             value="[amcl, ${managed.join(', ')}]"/>')
    ..writeln('    </node>')
    ..writeln('  </group>')
    ..writeln('</launch>');
  return buffer.toString();
}

/// 프로젝트의 Nav2 를 한꺼번에 띄우는 launch.
///
/// 건물 지도(`map_server`)는 **하나만** 띄우고, 이동 로봇마다 제 Nav2 를
/// 붙인다. 로봇들은 `map` 프레임을 함께 쓰고 `<로봇>/odom` 만 서로 다르다.
/// [warnings] 는 파라미터를 다시 쓰면서 손대지 못한 것이다. 여기 주석으로
/// 적어 둔다 — 이 launch 가 안 뜰 때 사람이 제일 먼저 여는 파일이다.
String buildProjectNav2LaunchXml({
  required String mapName,
  required List<RmfProjectRobot> robots,
  List<String> warnings = const [],
}) {
  final navigating = robots
      .where((robot) => robot.isMobile && robot.runsInGazebo)
      .toList();
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
    ..writeln('  지도는 nav2_map/ 에 있다. 도면에서 만든 것이라 원점이 RMF')
    ..writeln('  월드에 정확히 맞는다.')
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
    ..writeln('  <arg name="use_sim_time" default="true"/>')
    ..writeln('')
    ..writeln('  <!-- 건물 지도. 로봇들이 함께 본다. -->')
    ..writeln('  <node pkg="nav2_map_server" exec="map_server"')
    ..writeln('        name="map_server" output="screen">')
    ..writeln(
      '    <param name="yaml_filename" '
      'value="\$(var map_dir)/nav2_map/$mapName.yaml"/>',
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
      ..writeln(
        '  <include file="\$(var map_dir)/'
        '${robotDirectoryName(robot)}/nav2.launch.xml">',
      )
      ..writeln('    <arg name="use_sim_time" value="\$(var use_sim_time)"/>')
      ..writeln('  </include>');
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
/// 바꿀 것이 없으면 받은 목록을 그대로 돌려준다. 부르는 쪽이 `identical` 로
/// 달라졌는지 가려서 쓸데없이 다시 그리거나 저장하지 않게 한다.
List<RmfProjectRobot> robotsWithMapSpawnPoints(
  List<RmfProjectRobot> robots,
  ({double dx, double dy})? Function(RmfProjectRobot robot) pixelOf,
  double metersPerPixel,
) {
  if (metersPerPixel <= 0) return robots;
  var changed = false;
  final result = <RmfProjectRobot>[];
  for (final robot in robots) {
    final pixel = pixelOf(robot);
    if (pixel == null) {
      result.add(robot);
      continue;
    }
    final spawn = rmfWorldFromPixel(pixel.dx, pixel.dy, metersPerPixel);
    if (robot.spawnX != null &&
        robot.spawnY != null &&
        (spawn.x - robot.spawnX!).abs() < 1e-6 &&
        (spawn.y - robot.spawnY!).abs() < 1e-6) {
      result.add(robot);
      continue;
    }
    changed = true;
    result.add(robot.withSpawn(spawnX: spawn.x, spawnY: spawn.y));
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

/// 로봇 한 대의 등록 정보. 사람이 읽고 확인하는 용도다.
String buildRobotInfoYaml(RmfProjectRobot robot) {
  final buffer = StringBuffer()
    ..writeln('# ${robot.robotId} · ${robot.displayName}')
    ..writeln('# rmf_control_ui 가 맵 프로젝트에서 생성했다. 손으로 고치면')
    ..writeln('# 다음 저장 때 덮어써진다. 고치려면 앱의 로봇 등록에서 고친다.')
    ..writeln('id: ${robot.robotId}')
    ..writeln('name: ${robot.displayName}')
    ..writeln('kind: ${robot.kind.storageValue} # ${robot.kind.label}')
    ..writeln('data_source: ${robot.dataSource.name} # ${robot.dataSource.label}')
    ..writeln('model: ${robot.model}')
    ..writeln('gz_name: ${robot.gzName} # 토픽 네임스페이스')
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
    ..writeln('<launch>');
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

python3 - "\$RAW" "\$NAMESPACE" <<'PYTHON'
import re
import sys

path, namespace = sys.argv[1], sys.argv[2]
with open(path, encoding="utf-8") as handle:
    urdf = handle.read()

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
String buildRobotReadme(RmfProjectRobot robot, String mapName) {
  final station = robot.chargerWaypoint ?? '미지정';
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
  buffer
    ..writeln()
    ..writeln('## 파일')
    ..writeln()
    ..writeln('| 파일 | 용도 |')
    ..writeln('|---|---|')
    ..writeln('| `robot.yaml` | 이 로봇의 등록 정보 |')
    ..writeln('| `spawn.launch.xml` | 이 로봇만 Gazebo 에 올리는 launch |')
    ..writeln('| `bridge.yaml` | 이 로봇이 주고받는 토픽 |')
    ..writeln()
    ..writeln('프로젝트 bringup 이 `spawn.launch.xml` 을 include 합니다.')
    ..writeln('이 로봇만 따로 시험하려면 그 파일을 직접 돌리면 됩니다.')
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
