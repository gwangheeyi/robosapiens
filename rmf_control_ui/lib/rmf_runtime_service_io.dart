/// 이미 떠 있는 Open-RMF 백엔드를 확인하고 내린다.
///
/// 남아 있는 노드를 모르고 새 백엔드를 띄우면 schedule node 와 fleet adapter 가
/// 서로 부딪혀 엉뚱한 오류로 나타난다. 화면에서 먼저 보고 정리할 수 있어야 한다.
library;

import 'dart:io';

import 'rmf_config_export.dart';
import 'rmf_runtime_models.dart';

/// 노드 이름이 이 조각을 담고 있으면 RMF 백엔드로 본다.
///
/// `ros2 node list` 에는 이 앱이 띄운 Gazebo 브리지 같은 것도 함께 나오므로,
/// 내려야 할 대상만 골라낸다.
const List<String> _rmfNodeHints = [
  'rmf',
  'fleet_adapter',
  'fleet_manager',
  'building_map_server',
  'traffic_schedule',
  'door_supervisor',
  'lift_supervisor',
  'dispatcher',
];

Directory? _findProjectRoot() {
  final configuredRoot = Platform.environment['RMF_ROOT'];
  if (configuredRoot != null && configuredRoot.isNotEmpty) {
    final directory = Directory(configuredRoot).absolute;
    if (File('${directory.path}/openrmf/scripts/stop_office.sh').existsSync()) {
      return directory;
    }
  }
  var directory = Directory.current.absolute;
  for (var i = 0; i < 8; i++) {
    if (File('${directory.path}/openrmf/scripts/stop_office.sh').existsSync()) {
      return directory;
    }
    final parent = directory.parent;
    if (parent.path == directory.path) break;
    directory = parent;
  }
  return null;
}

/// ROS 환경을 읽어 들인 뒤 [command] 를 실행하는 셸 한 줄.
///
/// 앱은 보통 ROS 를 source 하지 않은 셸에서 실행된다. 그대로 `ros2` 를 부르면
/// 명령을 찾지 못하므로 setup.bash 를 먼저 읽는다. 경로는 환경 변수로 바꿀 수
/// 있게 두었다 — 배포마다 workspace 위치가 다르다.
String _withRosEnvironment(String command) {
  final rosSetup =
      Platform.environment['ROS_SETUP'] ?? '/opt/ros/jazzy/setup.bash';
  final workspace =
      Platform.environment['RMF_WS'] ??
      '${Platform.environment['HOME'] ?? ''}/rmf_ws';
  return 'set +u; '
      '[ -f "$rosSetup" ] && . "$rosSetup"; '
      '[ -f "$workspace/install/setup.bash" ] && . "$workspace/install/setup.bash"; '
      '$command';
}

/// 떠 있는 RMF 노드를 확인한다.
Future<RmfRuntimeStatus> probeRmfRuntime() async {
  try {
    final result = await Process.run('bash', [
      '-lc',
      _withRosEnvironment('ros2 node list'),
    ]).timeout(const Duration(seconds: 12));
    if (result.exitCode != 0) {
      final error = result.stderr.toString().trim();
      return RmfRuntimeStatus(
        available: false,
        nodes: const [],
        message: error.isEmpty
            ? 'ros2 명령을 실행하지 못했습니다. ROS 환경을 확인하세요.'
            : 'ros2 node list 실패: $error',
      );
    }
    final nodes =
        result.stdout
            .toString()
            .split('\n')
            .map((line) => line.trim())
            .where((line) => line.isNotEmpty)
            .where(
              (line) => _rmfNodeHints.any(
                (hint) => line.toLowerCase().contains(hint),
              ),
            )
            .toList()
          ..sort();
    return RmfRuntimeStatus(
      available: true,
      nodes: nodes,
      message: nodes.isEmpty
          ? '떠 있는 Open-RMF 백엔드가 없습니다.'
          : 'Open-RMF 백엔드가 이미 떠 있습니다.',
    );
  } on ProcessException catch (error) {
    return RmfRuntimeStatus(
      available: false,
      nodes: const [],
      message: 'ros2 명령을 찾을 수 없습니다: ${error.message}',
    );
  } catch (error) {
    return RmfRuntimeStatus(
      available: false,
      nodes: const [],
      message: '확인하지 못했습니다: $error',
    );
  }
}

/// 떠 있는 백엔드를 내린다.
///
/// 예전에는 무조건 `stop_office.sh` 만 돌렸다. 그 스크립트는 office 데모의
/// 경로(`tinyRobot_config.yaml`)로만 대상을 고르므로, 맵 프로젝트로 띄운
/// 백엔드는 **한 번도 대상이 아니었다.** `백엔드 중지` 를 눌러도
/// `<맵>_pinky_fleet_manager` 가 그대로 남았다.
///
/// [mapName] 을 주면 그 프로젝트의 중지 스크립트를 먼저 돌린다. office 데모
/// 스크립트는 그다음에 돌려 남은 데모 프로세스를 정리한다.
Future<RmfStopResult> stopRmfBackend({String? mapName}) async {
  final root = _findProjectRoot();
  if (root == null) {
    return const RmfStopResult(
      success: false,
      output:
          '프로젝트 위치를 찾을 수 없습니다. '
          'RMF_ROOT 환경 변수로 지정하세요.',
    );
  }
  final buffer = StringBuffer();
  var success = true;

  Future<void> run(String label, String script, String workingDirectory) async {
    if (!File(script).existsSync()) return;
    buffer.writeln('[$label] $script');
    try {
      final result = await Process.run(
        'bash',
        [script],
        workingDirectory: workingDirectory,
        runInShell: false,
      ).timeout(const Duration(seconds: 90));
      final output = [result.stdout, result.stderr]
          .map((value) => value.toString().trim())
          .where((value) => value.isNotEmpty)
          .join('\n');
      if (output.isNotEmpty) buffer.writeln(output);
      if (result.exitCode != 0) success = false;
    } catch (error) {
      success = false;
      buffer.writeln('실패: $error');
    }
    buffer.writeln();
  }

  if (mapName != null) {
    final directory =
        '${root.path}/rmf_maps/${safeMapDirectoryName(mapName)}';
    await run('맵 프로젝트', '$directory/stop_$mapName.sh', directory);
  }
  await run(
    'office 데모',
    '${root.path}/openrmf/scripts/stop_office.sh',
    root.path,
  );

  final text = buffer.toString().trim();
  if (text.isEmpty) {
    return const RmfStopResult(
      success: false,
      output:
          '돌릴 중지 스크립트가 없습니다.\n'
          '맵 프로젝트를 열고 `설정 파일` 에서 `디스크로 내보내기` 를 '
          '한 번 누르면 중지 스크립트도 함께 생깁니다.',
    );
  }
  return RmfStopResult(success: success, output: text);
}
