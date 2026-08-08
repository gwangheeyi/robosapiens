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

/// Gazebo 에 이 프로젝트의 월드와 로봇을 올리는 bringup launch.
///
/// 로봇마다 네임스페이스를 나눈다. 그래야 `/pinky_01/odom` 처럼 로봇별 토픽이
/// 갈리고, fleet adapter 가 어느 로봇의 위치인지 구분할 수 있다.
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
    ..writeln('')
    ..writeln('  <set_env name="GZ_SIM_RESOURCE_PATH"')
    ..writeln(
      '           value="\$(find-pkg-share pinky_description)/../:'
      '\$(var map_dir)/generated_models:\$(env HOME)/.gazebo/models"/>',
    )
    ..writeln('')
    ..writeln('  <!-- 화면이 없는 환경에서는 headless 로 서버만 띄운다. -->')
    ..writeln(
      '  <include file="\$(find-pkg-share ros_gz_sim)'
      '/launch/gz_sim.launch.py">',
    )
    ..writeln('    <arg name="gz_args" value="-r -s -v2 \$(var world)"/>')
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
  if (robots.isEmpty) {
    buffer
      ..writeln('')
      ..writeln('  <!-- 등록된 로봇이 없다. RMF 설정에서 추가한다. -->');
  }
  for (final robot in robots) {
    final x = (robot.spawnX ?? 0).toStringAsFixed(3);
    final y = (robot.spawnY ?? 0).toStringAsFixed(3);
    buffer
      ..writeln('')
      ..writeln('  <!-- ${robot.robotId} · ${robot.displayName} -->')
      ..writeln('  <group>')
      ..writeln('    <push-ros-namespace namespace="${robot.gzName}"/>')
      ..writeln(
        '    <include file="\$(find-pkg-share pinky_description)'
        '/launch/upload_robot.launch.py">',
      )
      ..writeln('      <arg name="namespace" value="${robot.gzName}"/>')
      ..writeln('      <arg name="use_sim_time" value="True"/>')
      ..writeln('      <arg name="is_sim" value="True"/>')
      ..writeln('    </include>')
      ..writeln('    <node pkg="ros_gz_sim" exec="create" output="screen"')
      ..writeln(
        '          args="-name ${robot.gzName} '
        '-topic robot_description '
        '-x $x -y $y -z 0.1 '
        '-Y ${robot.spawnHeading.toStringAsFixed(3)}">',
      )
      ..writeln('      <param name="use_sim_time" value="True"/>')
      ..writeln('    </node>')
      ..writeln('    <node pkg="ros_gz_bridge" exec="parameter_bridge"')
      ..writeln('          output="screen"')
      ..writeln(
        '          args="--ros-args -p config_file:='
        '\$(find-pkg-share pinky_gz_sim)/params/pinky_bridge.yaml"/>',
      )
      ..writeln('  </group>');
  }
  buffer.writeln('</launch>');
  return buffer.toString();
}

/// 프로젝트를 통째로 띄우는 셸 스크립트.
///
/// ROS 환경을 읽고 bringup 과 RMF 를 순서대로 띄운다. Gazebo 가 먼저 떠야
/// `/clock` 이 나오고, 그래야 use_sim_time 을 쓰는 RMF 노드가 시간을 맞춘다.
String buildProjectRunScript({
  required String mapName,
  required String mapDirectory,
  String rosSetup = '/opt/ros/jazzy/setup.bash',
  String rmfWorkspace = r'$HOME/rmf_ws',
  String pinkyWorkspace = r'$HOME/robosapiens/pinky_pro',
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
set -u

cleanup() {
  echo "정리 중..."
  kill \$(jobs -p) 2>/dev/null || true
}
trap cleanup EXIT INT TERM

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
}) =>
    '''#!/usr/bin/env bash
# $mapName 프로젝트로 띄운 프로세스를 내린다.
# rmf_control_ui 가 맵 프로젝트에서 생성했다.
#
# 이 프로젝트의 launch 경로로 시작한 것만 고른다. 다른 맵으로 띄운 RMF 나
# 관계없는 Gazebo 는 건드리지 않는다.
set -euo pipefail

MAP_DIR="\${MAP_DIR:-$mapDirectory}"

stop_matching() {
  local label="\$1" pattern="\$2"
  mapfile -t pids < <(pgrep -u "\$(id -u)" -f "\$pattern" 2>/dev/null || true)
  if ((\${#pids[@]} == 0)); then
    echo "\$label: 실행 중이 아님"
    return
  fi
  echo "\$label 중지: \${pids[*]}"
  kill -INT "\${pids[@]}" 2>/dev/null || true
  sleep 3
  kill -TERM "\${pids[@]}" 2>/dev/null || true
}

stop_matching "Open-RMF ($mapName)" "ros2 launch \$MAP_DIR/$mapName.launch.xml"
stop_matching "Gazebo bringup ($mapName)" \\
  "ros2 launch \$MAP_DIR/${mapName}_bringup.launch.xml"
stop_matching "Gazebo 서버 ($mapName)" "gz sim.*\$MAP_DIR/$mapName.world"

echo "$mapName 프로젝트 프로세스를 정리했습니다."
''';
