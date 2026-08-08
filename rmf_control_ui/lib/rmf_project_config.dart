/// 맵 프로젝트에서 Open-RMF 설정 파일을 만든다.
///
/// 플릿 설정은 맵을 따라간다. 맵이 다르면 Waypoint 이름도 충전소 위치도 다르므로
/// 전역 fleet.yaml 하나를 돌려 쓰면 프로젝트를 바꾸는 순간 어긋난다.
///
/// 여기서 만든 결과는 `map_project_files` 에 프로젝트별로 보관한다.
library;

/// 프로젝트에 속한 로봇 한 대.
class RmfProjectRobot {
  const RmfProjectRobot({
    required this.robotId,
    required this.displayName,
    required this.model,
    required this.gzName,
    required this.zones,
    this.chargerWaypoint,
    this.spawnX,
    this.spawnY,
    this.spawnHeading = 0,
  });

  final String robotId;
  final String displayName;
  final String model;

  /// Gazebo 모델 이름. 토픽 네임스페이스로도 쓰인다(`/<gzName>/odom`).
  final String gzName;

  /// TempZone.name 목록. 관제 배차의 입찰 자격이 된다.
  final List<String> zones;

  /// 충전 Waypoint 이름. fleet adapter 의 `robots[].charger` 로 나간다.
  final String? chargerWaypoint;
  final double? spawnX;
  final double? spawnY;
  final double spawnHeading;

  Map<String, Object?> toJson() => {
    'robotId': robotId,
    'displayName': displayName,
    'model': model,
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
  if (robots.isEmpty) {
    buffer.writeln('    {} # 등록된 로봇이 없다.');
  } else {
    for (final robot in robots) {
      buffer
        ..writeln('    ${robot.robotId}:')
        ..writeln('        charger: "${robot.chargerWaypoint ?? ''}"');
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
      ..writeln('    model: ${robot.model}')
      ..writeln('    gz_name: ${robot.gzName}')
      ..writeln('    zones: [${robot.zones.join(', ')}]');
    if (robot.chargerWaypoint != null) {
      buffer.writeln('    home_charger: ${robot.chargerWaypoint}');
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
