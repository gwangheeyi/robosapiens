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

/// 프로젝트 루트. `rmf_maps` 가 있는 곳을 기준으로 찾는다.
///
/// 예전에는 `openrmf/scripts/stop_office.sh` 가 있는 곳을 찾았다. office 데모를
/// 받지 않은 곳에서는 루트를 아예 못 찾아 중지가 통째로 실패했다. 실행도 중지도
/// 이제 프로젝트별이므로 데모와 상관이 없다.
Directory? _findProjectRoot() {
  final configuredRoot = Platform.environment['RMF_ROOT'];
  if (configuredRoot != null && configuredRoot.isNotEmpty) {
    final directory = Directory(configuredRoot).absolute;
    if (Directory('${directory.path}/rmf_maps').existsSync()) return directory;
  }
  var directory = Directory.current.absolute;
  for (var i = 0; i < 8; i++) {
    if (Directory('${directory.path}/rmf_maps').existsSync()) return directory;
    final parent = directory.parent;
    if (parent.path == directory.path) break;
    directory = parent;
  }
  return null;
}

/// 지금 프로세스가 돌고 있는 맵 프로젝트 이름.
///
/// 맵 디렉터리 경로를 인자로 물고 있으면 그 프로젝트가 띄운 것이다. 앱이 띄운
/// 것이든 터미널에서 띄운 것이든 똑같이 잡힌다.
///
/// 중지 스크립트 자신은 세지 않는다 — 그 경로에도 맵 디렉터리가 들어 있다.
Future<List<String>> runningBackendProjects() async {
  // 위젯 테스트에서는 프로세스를 뒤지지 않는다. 진짜 pgrep 을 띄우면 그
  // 프로세스가 테스트보다 오래 살고, 확인하는 것도 없다.
  if (Platform.environment.containsKey('FLUTTER_TEST')) return const [];
  final root = _findProjectRoot();
  if (root == null) return const [];
  final maps = Directory('${root.path}/rmf_maps');
  if (!maps.existsSync()) return const [];
  final running = <String>[];
  for (final entry in maps.listSync()) {
    if (entry is! Directory) continue;
    final name = entry.uri.pathSegments
        .where((segment) => segment.isNotEmpty)
        .last;
    try {
      final found = await Process.run('bash', [
        '-lc',
        'pgrep -u "\$(id -u)" -af ${_shellQuote(entry.path)} 2>/dev/null '
            "| grep -cv 'stop_' || true",
      ]).timeout(const Duration(seconds: 10));
      final count = int.tryParse(found.stdout.toString().trim()) ?? 0;
      if (count > 0) running.add(name);
    } catch (_) {
      // 한 프로젝트를 못 봐도 나머지는 봐야 한다.
    }
  }
  running.sort();
  return running;
}

/// 셸에 넘길 문자열을 작은따옴표로 감싼다. 맵 이름에 공백이 들어갈 수 있다.
String _shellQuote(String value) => "'${value.replaceAll("'", r"'\''")}'";

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

/// 떠 있는 백엔드를 내린다. **프로젝트별로만** 다룬다.
///
/// office 데모 스크립트는 부르지 않는다. 두 가지 이유가 있다.
///
/// 첫째, 그 스크립트는 대상을 office 경로(`tinyRobot_config.yaml`)로만 고르므로
/// 맵 프로젝트로 띄운 백엔드는 애초에 대상이 아니다.
///
/// 둘째, 그 스크립트는 rmf-web API 컨테이너(`docker stop`)까지 내린다. 그런데
/// 프로젝트 launch 는 `server_uri:=ws://127.0.0.1:8000/_internal` 로 그 API 를
/// 쓴다. 프로젝트를 내리면서 프로젝트가 기대는 것을 함께 끊게 된다.
///
/// [mapName] 을 주면 그 프로젝트를 내린다. 그 밖에 프로세스가 돌고 있는
/// 프로젝트도 함께 찾아 내린다 — 카드는 "떠 있는 백엔드를 내린다"고 말한다.
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

  // 열린 프로젝트를 먼저, 그다음 프로세스가 돌고 있는 다른 프로젝트를.
  final targets = <String>{
    ?mapName,
    ...await runningBackendProjects(),
  };
  for (final name in targets) {
    final directory = '${root.path}/rmf_maps/${safeMapDirectoryName(name)}';
    await run(name, '$directory/stop_$name.sh', directory);
  }

  final text = buffer.toString().trim();
  if (text.isEmpty) {
    return RmfStopResult(
      success: false,
      output: targets.isEmpty
          ? '내릴 프로젝트를 찾지 못했습니다.\n'
                '맵 프로젝트를 열고 다시 눌러 주세요.'
          : '${targets.join(', ')} 의 중지 스크립트가 디스크에 없습니다.\n'
                '`설정 파일` 에서 `디스크로 내보내기` 를 한 번 누르면 함께 '
                '생깁니다.',
    );
  }
  return RmfStopResult(success: success, output: text);
}
