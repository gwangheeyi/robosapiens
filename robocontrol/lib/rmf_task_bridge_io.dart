/// 앱이 만든 작업을 RMF 에 넣고, 그 진행을 되받는다.
///
/// 지금까지 앱은 ROS 를 읽기만 했다 — `ros2 topic echo` 로 위치를, `ros2 node
/// list` 로 살아 있는지를. 내보내는 길이 없어서 연속 작업은 앱 안에서만 돌았고,
/// Gazebo 로봇에게는 가라고 말하는 쪽이 없었다.
///
/// 여기가 그 길이다. 나가는 것은 배포된 `<맵>_task_bridge.py` 를 자식 프로세스로
/// 부르고, 들어오는 것은 어댑터가 내는 진행 토픽을 `ros2 topic echo` 로 읽는다.
/// 읽는 방식은 위치 다리와 같다.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'rmf_task_models.dart';
import 'ros_static_peers_io.dart';
import 'workspace_paths_io.dart';

export 'rmf_task_models.dart';

/// ROS 환경을 읽어 들인 뒤 [command] 를 실행하는 셸 한 줄.
///
/// 앱은 보통 ROS 를 source 하지 않은 셸에서 실행된다.
String _withRosEnvironment(String command) {
  final rosSetup =
      Platform.environment['ROS_SETUP'] ?? '/opt/ros/jazzy/setup.bash';
  final workspace = bundledRmfWorkspace();
  return 'set +u; '
      '[ -f "$rosSetup" ] && . "$rosSetup"; '
      '[ -f "$workspace/install/setup.bash" ] && . "$workspace/install/setup.bash"; '
      // 로봇이 다른 기계에 있으면 이것 없이는 상대를 못 찾는다.
      '${rosStaticPeersExport()}'
      '$command';
}

/// 새로 띄운 `ros2 topic echo` 가 상대를 찾을 때까지 기다리는 시간.
///
/// 작업을 넘기기 전에 한 번만 치르는 값이다. 짧으면 첫 소식을 놓치고, 길면
/// 단추를 누른 사람이 그만큼 기다린다.
const Duration topicDiscoveryDelay = Duration(milliseconds: 1500);

/// 나가는 길과 들어오는 길을 함께 쥔다. 화면 여러 곳이 같은 것을 봐야 한다.
class RmfTaskBridge {
  RmfTaskBridge._();

  static final RmfTaskBridge instance = RmfTaskBridge._();

  final StreamController<RmfTaskProgress> _controller =
      StreamController<RmfTaskProgress>.broadcast();
  Process? _echo;
  String? _watchedFleet;

  /// 지금 듣고 있는 도메인. 도메인만 바뀌어도 다시 붙어야 한다 — 플릿 이름이
  /// 같다고 그대로 두면 옛 도메인에서 오지 않을 소식을 계속 기다린다.
  int? _watchedDomain;

  /// 어댑터가 내는 진행 소식. 화면이 이것을 듣고 단계를 넘긴다.
  Stream<RmfTaskProgress> get progress => _controller.stream;

  bool get watching => _echo != null;
  String? get watchedFleet => _watchedFleet;

  /// 작업 하나를 RMF 에 넣는다.
  ///
  /// [mapDirectory] 에 배포된 `<맵>_task_bridge.py` 를 쓴다. 그 파일이 없으면
  /// 배포를 안 한 것이므로 무엇을 해야 하는지 알린다.
  /// [rosDomainId] 를 반드시 넘긴다. 백엔드가 도는 도메인이 아니면 요청이
  /// **아무도 없는 도메인으로 나간다.** 그러면 `task_bridge.py` 는 15초를
  /// 기다리다 `RMF 가 답하지 않았습니다` 로 끝나는데, 그 문구가 어댑터를
  /// 가리켜서 멀쩡한 어댑터를 두고 그쪽을 뒤지게 된다.
  Future<RmfTaskSubmission> submit({
    required String mapDirectory,
    required String mapName,
    required String requestJson,
    required int rosDomainId,
  }) async {
    final script = File('$mapDirectory/${mapName}_task_bridge.py');
    if (!script.existsSync()) {
      return RmfTaskSubmission(
        accepted: false,
        message:
            '${script.path} 가 없습니다.\n'
            '맵 관리에서 RMF 설정 내보내기를 먼저 하세요.',
      );
    }
    final payload = File(
      '${Directory.systemTemp.path}/robocontrol_task_'
      '${DateTime.now().microsecondsSinceEpoch}.json',
    );
    try {
      await payload.writeAsString(requestJson);
      final result =
          await Process.run('bash', [
            '-lc',
            _withRosEnvironment(
              'export ROS_DOMAIN_ID=$rosDomainId; '
              'exec python3 ${_quote(script.path)} --submit ${_quote(payload.path)}',
            ),
          ]).timeout(
            const Duration(seconds: 30),
            onTimeout: () => ProcessResult(
              0,
              1,
              '',
              '작업 다리가 30초 안에 끝나지 않았습니다. ROS 환경을 확인하세요.',
            ),
          );
      final output = '${result.stdout}'.trim().isEmpty
          ? '${result.stderr}'
          : '${result.stdout}';
      return RmfTaskSubmission.parse(output);
    } catch (error) {
      return RmfTaskSubmission(accepted: false, message: '$error');
    } finally {
      // 작업 내용이 임시 디렉터리에 남지 않게 한다.
      if (payload.existsSync()) {
        try {
          payload.deleteSync();
        } catch (_) {}
      }
    }
  }

  /// [fleetName] 의 진행 토픽을 듣기 시작한다. 이미 같은 것을 듣고 있으면 둔다.
  ///
  /// 위젯 테스트에서는 아무것도 띄우지 않는다. 테스트가 진짜 `ros2` 를 띄우면
  /// 그 프로세스가 테스트보다 오래 살고, 화면이 없는 환경에서 무엇을 확인하는
  /// 것도 아니다.
  Future<void> watch(String fleetName, {required int rosDomainId}) async {
    if (Platform.environment.containsKey('FLUTTER_TEST')) return;
    if (_watchedFleet == fleetName &&
        _echo != null &&
        _watchedDomain == rosDomainId) {
      return;
    }
    await stop();
    _watchedFleet = fleetName;
    _watchedDomain = rosDomainId;
    try {
      final process = await Process.start('bash', [
        '-lc',
        _withRosEnvironment(
          'export ROS_DOMAIN_ID=$rosDomainId; '
          'exec ros2 topic echo /$fleetName/task_progress --field data',
        ),
      ]);
      _echo = process;
      process.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
            final event = RmfTaskProgress.parse(line);
            if (event != null) _controller.add(event);
          });
      // 백엔드가 내려가면 이 프로세스도 죽는다. 표시를 안 남기면 살아 있는
      // 줄 알고 다시 안 띄워, 로봇은 도는데 화면의 진행률만 멈춘다.
      unawaited(
        process.exitCode.then((_) {
          if (_echo != process) return;
          _echo = null;
          _watchedFleet = null;
        }),
      );
      // 붙을 틈을 준다. `Process.start` 는 프로세스를 띄우기만 하고 돌아오는데,
      // `ros2` 가 파이썬을 올리고 상대를 찾기까지 1초 남짓 걸린다. 그 사이에
      // 나간 소식은 어디에도 안 남는다 — 부르는 쪽은 이 뒤에 작업을 넘기므로,
      // 여기서 안 기다리면 첫 `navigate_start` 를 놓쳐 단계가 처음부터 어긋난다.
      await Future<void>.delayed(topicDiscoveryDelay);
    } catch (_) {
      // 토픽이 아직 없을 수 있다. 그때는 조용히 놔둔다 — 백엔드를 띄우면
      // 다시 부른다.
      _echo = null;
      _watchedFleet = null;
    }
  }

  Future<void> stop() async {
    final process = _echo;
    _echo = null;
    _watchedFleet = null;
    _watchedDomain = null;
    if (process == null) return;
    process.kill(ProcessSignal.sigint);
    // 곧바로 안 죽으면 한 번 더. 죽는 것을 보면 그 시계는 접는다 — 남겨 두면
    // 앱이 닫힌 뒤에도 3초짜리 타이머가 매달려 있다.
    final escalate = Timer(const Duration(seconds: 3), () {
      process.kill(ProcessSignal.sigterm);
    });
    unawaited(process.exitCode.whenComplete(escalate.cancel));
  }
}

/// 셸에 넘길 경로 하나. 맵 이름은 사람이 타자로 친다.
String _quote(String path) => "'${path.replaceAll("'", r"'\''")}'";
