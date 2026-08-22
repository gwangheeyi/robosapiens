import 'dart:io';

import 'robot_drive_mode.dart';

/// 배포 파일을 보존하고, 실행 중인 이 로봇의 Nav2 파라미터만 즉시 바꾼다.
///
/// Nav2의 costmap/controller 파라미터는 실행 중 갱신할 수 있다. 그래서 Gazebo,
/// RMF, 로봇 브링업을 내리지 않는다. 파일도 함께 바꾸므로 다음 Nav2 기동에도
/// 같은 모드가 유지된다.
Future<({bool ok, String output})> applyRobotDriveMode({
  required String mapDirectory,
  required String robotDirectory,
  required String namespace,
  required String nav2Params,
}) async {
  final params = File('$mapDirectory/robots/$robotDirectory/nav2_params.yaml');
  if (!await params.parent.exists()) {
    return (ok: false, output: '배포된 로봇 폴더가 없습니다: ${params.parent.path}');
  }
  final temporary = File('${params.path}.mode.tmp');
  await temporary.writeAsString(nav2Params, flush: true);
  await temporary.rename(params.path);

  final mode = nav2Params.contains('inflation_radius: 0.050')
      ? RobotDriveMode.forced
      : RobotDriveMode.normal;
  final costmap = costmapForDriveMode(mode);
  final footprint = RegExp(
    r'^\s*footprint:\s*(\[\[.*\]\])',
    multiLine: true,
  ).firstMatch(nav2Params)?.group(1);
  final ns = namespace.replaceAll(RegExp(r'^/+|/+$'), '');
  final changes = <(String, String, String)>[
    for (final node in [
      'local_costmap/local_costmap',
      'global_costmap/global_costmap',
    ]) ...[
      (node, 'inflation_layer.inflation_radius', '${costmap.inflationRadius}'),
      (
        node,
        'inflation_layer.cost_scaling_factor',
        '${costmap.costScalingFactor}',
      ),
      (node, 'footprint_padding', '${costmap.footprintPadding}'),
      if (footprint != null) (node, 'footprint', footprint),
      if (node.startsWith('local_'))
        (node, 'voxel_layer.enabled', '${mode != RobotDriveMode.forced}'),
      if (node.startsWith('global_')) ...[
        (node, 'static_layer.enabled', '${mode != RobotDriveMode.forced}'),
        (node, 'obstacle_layer.enabled', '${mode != RobotDriveMode.forced}'),
      ],
    ],
    (
      'controller_server',
      'FollowPath.inflation_cost_scaling_factor',
      '${costmap.costScalingFactor}',
    ),
    (
      'controller_server',
      'FollowPath.use_collision_detection',
      '${mode != RobotDriveMode.forced}',
    ),
    (
      'controller_server',
      'progress_checker.movement_time_allowance',
      '${costmap.movementTimeAllowance}',
    ),
    (
      'controller_server',
      'progress_checker.required_movement_radius',
      '${costmap.requiredMovementRadius}',
    ),
  ];
  final failures = <String>[];
  for (final (node, key, value) in changes) {
    try {
      final result = await Process.run('ros2', [
        'param',
        'set',
        '/$ns/$node',
        key,
        value,
      ], runInShell: false).timeout(const Duration(seconds: 4));
      if (result.exitCode != 0 ||
          !result.stdout.toString().contains('Successful')) {
        failures.add(
          '/$ns/$node $key: ${result.stderr}${result.stdout}'.trim(),
        );
      }
    } catch (error) {
      failures.add('/$ns/$node $key: $error');
    }
  }
  if (failures.isNotEmpty) {
    return (
      ok: false,
      output: '설정 파일은 저장했지만 실행 중 Nav2 반영에 실패했습니다.\n${failures.join('\n')}',
    );
  }
  return (
    ok: true,
    output: '${mode.label} 모드를 해당 로봇 Nav2에 반영했습니다. 전체 백엔드와 브링업은 그대로입니다.',
  );
}
