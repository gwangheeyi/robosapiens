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

/// 이 로봇에서 살아 있는지 확인할 토픽.
///
/// 이동 로봇은 `/odom` 이다. 설치 로봇은 바퀴가 없어 `/odom` 이 아예 없다 —
/// 그런데도 `/odom` 을 읽으러 가서, 등록도 Gazebo 도 멀쩡한 OpenMANIPULATOR 가
/// 앱에서는 영영 Mock 으로만 보였다. 팔이 내는 것은 관절 상태다.
String _liveTopicFor(RmfProjectRobot robot) =>
    robot.isMobile ? '/${robot.gzName}/odom' : '/${robot.gzName}/joint_states';

/// 로봇 한 대의 위치 토픽을 읽는 자식 프로세스.
class _RobotFeed {
  _RobotFeed({
    required this.robotId,
    required this.topic,
    this.spawnX,
    this.spawnY,
    this.spawnHeading = 0,
  });

  final String robotId;
  final String topic;

  /// 로봇을 올린 자리. odom 의 원점이라서 월드 좌표로 옮길 때 필요하다.
  final double? spawnX;
  final double? spawnY;
  final double spawnHeading;
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

  /// 죽은 구독을 다시 띄우는 시계.
  ///
  /// 백엔드는 앱과 따로 오르내린다. 사람이 다시 붙여 주기를 기다리면 그동안
  /// 화면은 조용한데 왜 조용한지 알 수 없다.
  Timer? _healer;

  /// 다시 붙일 로봇. 마지막으로 [sync] 에 들어온 것을 기억해 둔다.
  final Map<String, RmfProjectRobot> _wanted = {};
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
        if (robot.runsInGazebo) robot.robotId: robot,
    };
    for (final id in _feeds.keys.toList()) {
      final feed = _feeds[id]!;
      final robot = wanted[id];
      // 스폰 자리가 바뀌면 odom 을 옮길 기준이 달라진다. 토픽이 같아도 다시
      // 붙여야 위치가 어긋나지 않는다.
      if (robot != null &&
          // 프로세스가 죽었으면 다시 띄워야 한다. 백엔드를 내렸다 올리면
          // `ros2 topic echo` 도 함께 죽는데, 여기서 그냥 넘기면 앱은
          // 영영 아무 값도 못 받는다 — 등록도 토픽도 멀쩡한데 화면만
          // 조용한 것이 그 증상이었다.
          feed.process != null &&
          _liveTopicFor(robot) == feed.topic &&
          robot.spawnX == feed.spawnX &&
          robot.spawnY == feed.spawnY &&
          robot.spawnHeading == feed.spawnHeading) {
        continue;
      }
      await _feeds.remove(id)!.close();
    }
    for (final entry in wanted.entries) {
      if (_feeds.containsKey(entry.key)) continue;
      await _open(entry.key, entry.value);
    }
    _wanted
      ..clear()
      ..addAll(wanted);
    _startHealer();
    _controller.add(status);
  }

  /// 5초마다 죽은 구독을 다시 띄운다.
  ///
  /// 붙을 것이 없으면 시계도 멈춘다. 살려 둘 이유가 없다.
  void _startHealer() {
    if (_wanted.isEmpty) {
      _healer?.cancel();
      _healer = null;
      return;
    }
    _healer ??= Timer.periodic(const Duration(seconds: 5), (_) async {
      final dead = [
        for (final entry in _wanted.entries)
          if (_feeds[entry.key]?.process == null) entry,
      ];
      if (dead.isEmpty) return;
      for (final entry in dead) {
        await _feeds.remove(entry.key)?.close();
        await _open(entry.key, entry.value);
      }
      _controller.add(status);
    });
  }

  Future<void> _open(String robotId, RmfProjectRobot robot) async {
    final topic = _liveTopicFor(robot);
    // 설치 로봇은 제자리에 붙어 있다. 자세를 풀어낼 것이 없으므로 관절 이름만
    // 받아 살아 있는지만 본다 — 값이 온다는 것이 곧 Gazebo 에 올라와 있고
    // 컨트롤러가 돌고 있다는 뜻이다. 자리는 등록에서 정한 spawn 그대로다.
    final stationary = !robot.isMobile;
    final field = stationary ? 'name' : 'pose.pose';
    final feed = _RobotFeed(
      robotId: robotId,
      topic: topic,
      spawnX: robot.spawnX,
      spawnY: robot.spawnY,
      spawnHeading: robot.spawnHeading,
    );
    _feeds[robotId] = feed;
    try {
      final process = await Process.start('bash', [
        '-lc',
        _withRosEnvironment('exec ros2 topic echo $topic --field $field --csv'),
      ]);
      feed.process = process;
      feed.lines = process.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
            if (stationary) {
              // 한 줄이라도 오면 살아 있는 것이다. 관절 이름을 파싱하지는
              // 않는다 — 팔이 어느 각도인지는 앱 지도에 그릴 것이 없다.
              if (line.trim().isEmpty) return;
              feed.pose = RobotPose(
                x: feed.spawnX ?? 0,
                y: feed.spawnY ?? 0,
                heading: feed.spawnHeading,
                at: DateTime.now(),
              );
              feed.error = null;
              _controller.add(status);
              return;
            }
            final pose = RobotPose.parseCsv(line, DateTime.now());
            if (pose == null) return;
            // odom 은 올린 자리가 원점이다. 그대로 두면 홈1 에 세운 로봇이
            // 지도 원점에 그려진다.
            feed.pose = pose.toWorld(
              spawnX: feed.spawnX,
              spawnY: feed.spawnY,
              spawnHeading: feed.spawnHeading,
            );
            feed.error = null;
            _controller.add(status);
          });
      // 끝나면 표시를 남긴다. 남기지 않으면 죽은 것을 살아 있는 것으로 알고
      // 다시 띄우지 않는다.
      unawaited(
        process.exitCode.then((code) {
          if (feed.process != process) return;
          feed.process = null;
          feed.error = '토픽 읽기가 끝났습니다. 백엔드가 내려갔을 수 있습니다.';
          _controller.add(status);
        }),
      );
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
    _healer?.cancel();
    _healer = null;
    _wanted.clear();
    for (final feed in _feeds.values.toList()) {
      await feed.close();
    }
    _feeds.clear();
    _controller.add(RobotTelemetryStatus.idle);
  }
}
