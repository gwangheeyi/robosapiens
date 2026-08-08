/// Gazebo 가 내는 위치 토픽을 앱으로 끌어온다.
///
/// 지금까지 화면의 숫자는 전부 앱이 계산한 것이었다. 출처를 Gazebo 로 골라도
/// 값은 여전히 앱 것이어서 작업 상세의 띠가 그 사실을 경고로 알렸다.
///
/// 앱에 rclpy·rclcpp 바인딩이 없으므로 `ros2 topic echo` 를 자식 프로세스로
/// 띄워 읽는다. MySQL 도 `mysql` 클라이언트를 부르고 노드 확인도 `ros2 node
/// list` 를 부르는 것과 같은 방식이다.
///
/// `--field pose.pose --csv` 는 `x,y,z,qx,qy,qz,qw` 일곱 개만 한 줄로 낸다.
/// 전체 Odometry 를 YAML 로 받아 파싱하는 것보다 훨씬 싸다.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'rmf_project_config.dart';
import 'robot_telemetry_models.dart';

/// ROS 환경을 읽어 들인 뒤 [command] 를 실행하는 셸 한 줄.
///
/// 앱은 보통 ROS 를 source 하지 않은 셸에서 실행된다. 그대로 `ros2` 를 부르면
/// 명령을 찾지 못한다.
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

/// 로봇 한 대의 위치 토픽을 읽는 자식 프로세스.
class _RobotFeed {
  _RobotFeed({required this.robotId, required this.topic});

  final String robotId;
  final String topic;
  Process? process;
  StreamSubscription<String>? lines;
  RobotPose? pose;

  /// 프로세스가 낸 마지막 오류. 토픽이 없으면 여기 남는다.
  String? error;

  Future<void> close() async {
    await lines?.cancel();
    lines = null;
    // 셸을 `exec` 로 띄웠으므로 이 pid 가 곧 `ros2` 프로세스다. 그룹을 따로
    // 끊을 것이 없다.
    final target = process;
    process = null;
    if (target == null) return;
    target.kill(ProcessSignal.sigint);
    // 곧바로 안 죽으면 한 번 더. 남겨 두면 다음 실행에서 같은 토픽을 두 번
    // 읽는다.
    unawaited(
      target.exitCode.timeout(
        const Duration(seconds: 3),
        onTimeout: () {
          target.kill(ProcessSignal.sigterm);
          return -1;
        },
      ),
    );
  }
}

/// 등록된 Gazebo 로봇의 위치를 계속 받아 둔다.
///
/// 화면 여러 곳이 같은 값을 봐야 하므로 앱에 하나만 둔다.
class RobotTelemetryBridge {
  RobotTelemetryBridge._();

  static final RobotTelemetryBridge instance = RobotTelemetryBridge._();

  final Map<String, _RobotFeed> _feeds = {};
  final StreamController<RobotTelemetryStatus> _controller =
      StreamController<RobotTelemetryStatus>.broadcast();

  /// 값이 바뀔 때마다 흘러나온다. 화면이 이것을 듣고 다시 그린다.
  Stream<RobotTelemetryStatus> get updates => _controller.stream;

  bool get subscribing => _feeds.isNotEmpty;

  /// 지금까지 받은 자세.
  Map<String, RobotPose> get poses => {
    for (final feed in _feeds.values)
      if (feed.pose != null) feed.robotId: feed.pose!,
  };

  RobotTelemetryStatus get status {
    if (_feeds.isEmpty) return RobotTelemetryStatus.idle;
    final live = _feeds.values.where((feed) => feed.pose != null).length;
    final errors = _feeds.values
        .where((feed) => feed.pose == null && feed.error != null)
        .map((feed) => '${feed.robotId}: ${feed.error}')
        .toList();
    return RobotTelemetryStatus(
      subscribing: true,
      poses: poses,
      message: errors.isEmpty
          ? '$live/${_feeds.length}대에서 위치를 받고 있습니다.'
          : '$live/${_feeds.length}대 수신 중. ${errors.join(' · ')}',
    );
  }

  /// [robots] 중 Gazebo 로 돌리는 것만 구독한다.
  ///
  /// 이미 붙어 있는 것은 그대로 두고, 빠진 것만 끊고 새로 생긴 것만 붙인다.
  /// 매번 전부 다시 띄우면 화면이 잠깐씩 빈다.
  Future<void> sync(Iterable<RmfProjectRobot> robots) async {
    final wanted = {
      for (final robot in robots)
        if (robot.runsInGazebo) robot.robotId: '/${robot.gzName}/odom',
    };
    for (final id in _feeds.keys.toList()) {
      if (wanted[id] == _feeds[id]!.topic) continue;
      await _feeds.remove(id)!.close();
    }
    for (final entry in wanted.entries) {
      if (_feeds.containsKey(entry.key)) continue;
      await _open(entry.key, entry.value);
    }
    _controller.add(status);
  }

  Future<void> _open(String robotId, String topic) async {
    final feed = _RobotFeed(robotId: robotId, topic: topic);
    _feeds[robotId] = feed;
    try {
      final process = await Process.start('bash', [
        '-lc',
        _withRosEnvironment('exec ros2 topic echo $topic --field pose.pose --csv'),
      ]);
      feed.process = process;
      feed.lines = process.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
            final pose = RobotPose.parseCsv(line, DateTime.now());
            if (pose == null) return;
            feed.pose = pose;
            feed.error = null;
            _controller.add(status);
          });
      // 토픽이 없으면 여기로 사유가 온다. 조용히 아무 값도 안 오는 것보다
      // 왜 안 오는지 보이는 편이 낫다.
      unawaited(
        process.stderr
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .where((line) => line.trim().isNotEmpty)
            .take(1)
            .forEach((line) {
              feed.error = line.trim();
              _controller.add(status);
            }),
      );
    } catch (error) {
      feed.error = '$error';
      _controller.add(status);
    }
  }

  /// 전부 끊는다. 앱을 닫거나 프로젝트를 바꿀 때 부른다.
  Future<void> stop() async {
    for (final feed in _feeds.values.toList()) {
      await feed.close();
    }
    _feeds.clear();
    _controller.add(RobotTelemetryStatus.idle);
  }
}
