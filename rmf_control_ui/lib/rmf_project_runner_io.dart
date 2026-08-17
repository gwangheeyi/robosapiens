/// 프로젝트 실행 스크립트를 앱에서 띄우고 내린다.
///
/// 앱이 띄운 것만 앱이 내린다. 사용자가 터미널에서 직접 띄운 것을 앱이 종료할
/// 때 같이 죽이면 놀랄 일이다.
///
/// 자식 프로세스를 **자기 프로세스 그룹**으로 띄운다(`setsid`). 그래야 앱이
/// 죽어도 ros2 launch 가 함께 끌려가지 않고, 반대로 내릴 때는 그룹째 한 번에
/// 정리할 수 있다.
library;

import 'dart:io';

import 'package:meta/meta.dart';

import 'rmf_config_export.dart';
import 'simulation_backend.dart';

export 'simulation_backend.dart';

class RmfRunResult {
  const RmfRunResult({required this.success, required this.message});
  final bool success;
  final String message;
}

/// 이 컨트롤러를 **못 올린** 자국이 로그에 있는가.
///
/// 이름이 보이는 것과 못 올린 것은 다르다. controller_manager 는 정상으로 올릴
/// 때도 `Loading controller : 'x' of type '...'` 을 찍고, 낡은 형식이면 성공한
/// 뒤에도 `[Deprecated]` 를 한 줄 남긴다. 그것을 실패로 읽으면 멀쩡한 백엔드를
/// 두고 엉뚱한 패키지를 깔라고 시키게 된다.
bool _controllerFailed(String text, String controller) {
  final marks = [
    "Loader for controller '$controller'",
    "Could not load controller '$controller'",
    "Failed to load controller '$controller'",
    "Controller '$controller' with type",
  ];
  for (final mark in marks) {
    if (!text.contains(mark)) continue;
    // 같은 줄에 실패라고 적혀 있어야 한다.
    for (final line in text.split('\n')) {
      if (!line.contains(mark)) continue;
      final lower = line.toLowerCase();
      if (lower.contains('error') ||
          lower.contains('failed') ||
          lower.contains('could not') ||
          lower.contains('does not exist') ||
          lower.contains('not available')) {
        return true;
      }
    }
  }
  return false;
}

/// `/dev/shm` 에 남아 있는 DDS 조각 수. 못 세면 null.
///
/// 숫자를 함께 보여 줘야 "탐색이 무너졌다" 는 말이 손에 잡힌다. 수백 개면
/// 그것이 원인이고, 열 개 남짓이면 다른 곳을 봐야 한다.
int? _staleDdsSegments() {
  try {
    final directory = Directory('/dev/shm');
    if (!directory.existsSync()) return null;
    return directory.listSync().where((entry) {
      final name = entry.uri.pathSegments.last;
      return name.startsWith('fastrtps_') || name.startsWith('fastdds_');
    }).length;
  } catch (_) {
    return null;
  }
}

/// 백엔드가 내려간 뒤 사용자에게 보여 줄 진단 보고서를 만든다.
///
/// 실행 스크립트는 detached 이므로 [startProject] 가 성공한 뒤에도 Gazebo 나
/// ros2_control 이 몇 초 뒤 실패할 수 있다. 그때 단순히 "안 됨" 이라고 하지
/// 않고 오류 로그, 알려진 원인, 그대로 붙여 넣을 명령을 함께 돌려준다.
///
/// **아는 것만 말한다.** 짐작으로 원인을 붙이면 사람이 엉뚱한 곳을 뒤진다.
Future<String> diagnoseProjectBackendFailure(String mapName) async {
  final directory = _mapDirectory(mapName);
  if (directory == null) {
    return '원인: rmf_maps 디렉터리를 찾을 수 없습니다.\n'
        '조치: RMF_ROOT를 RoboSapiens 프로젝트 루트로 지정하세요.';
  }
  final errorFile = File('$directory/$mapName.err.log');
  final runFile = File('$directory/$mapName.log');
  var text = '';
  for (final file in [errorFile, runFile]) {
    if (!file.existsSync()) continue;
    try {
      final contents = await file.readAsString();
      // 로그 전체가 수백 MB여도 진단에는 마지막 부분이면 충분하다.
      final start = contents.length > 24000 ? contents.length - 24000 : 0;
      text += '\n${contents.substring(start)}';
    } on FileSystemException {
      // 한 파일을 못 읽어도 다른 파일과 일반 안내로 진단을 계속한다.
    }
  }

  final reasons = <String>[];
  final commands = <String>[];
  // 컨트롤러는 **실패한 자국**으로만 판정한다.
  //
  // 예전에는 로그에 컨트롤러 **형식 이름**이 보이기만 하면 문제라고 했다.
  // 그런데 그 이름은 정상으로 뜰 때도 찍힌다 —
  //
  //     Loading controller : 'gripper_controller' of type
  //       'position_controllers/GripperActionController'      ← 성공 경로
  //     [Deprecated]: the `position_controllers/...` controllers are
  //       replaced by 'parallel_gripper_controllers/...'      ← 그냥 안내
  //
  // 실제로 셋 다 `active` 인데도 "플러그인을 못 찾았다", "형식이 잘못됐다" 가
  // 떴고, 이미 깔린 패키지를 `apt install` 하라고 시켰다(2026-08-17). 사람이
  // 엉뚱한 곳을 30분 뒤지게 만드는 것이 조용히 넘기는 것보다 나쁘다.
  if (_controllerFailed(text, 'arm_controller')) {
    if (File(
      '/opt/ros/jazzy/lib/libjoint_trajectory_controller.so',
    ).existsSync()) {
      reasons.add(
        'arm_controller 플러그인은 설치되어 있는데 실행 중인 ROS 환경이 '
        '찾지 못했습니다. 백엔드를 완전히 중지한 뒤 다시 실행하세요.',
      );
    } else {
      reasons.add('OpenManipulator arm_controller 플러그인이 설치되지 않았습니다.');
      commands.add('sudo apt install ros-jazzy-joint-trajectory-controller');
    }
  }
  if (_controllerFailed(text, 'gripper_controller')) {
    // `gripper_controllers` 패키지가 내보내는 이름은 `position_controllers/
    // GripperActionController` 다(패키지 이름과 클래스 이름이 다르다). 라이브러리
    // 파일 이름도 `libgripper_action_controller.so` 다 — 예전에는 없는 이름으로
    // 찾아서 늘 "설치하세요" 가 됐다.
    if (File(
      '/opt/ros/jazzy/lib/libgripper_action_controller.so',
    ).existsSync()) {
      reasons.add(
        'gripper_controller 를 못 올렸습니다. 플러그인은 설치되어 있으니 '
        '백엔드를 완전히 중지한 뒤 다시 실행하세요. '
        '그래도 안 되면 형식을 Jazzy 의 새 이름 '
        'parallel_gripper_controllers/GripperActionController 로 바꿔 보세요.',
      );
    } else {
      reasons.add('gripper_controller 플러그인이 설치되지 않았습니다.');
      commands.add('sudo apt install ros-jazzy-gripper-controllers');
    }
  }
  if (text.contains("invalid choice: 'control'") ||
      text.contains('ros2controlcli')) {
    reasons.add('ros2 control 명령 패키지가 설치되지 않았습니다.');
    commands.add('sudo apt install ros-jazzy-ros2controlcli');
  }
  final missingMatch = RegExp(r'없는 ROS 패키지:\s*([^\n\r]+)').firstMatch(text);
  if (missingMatch != null) {
    reasons.add('필수 ROS 패키지가 없습니다: ${missingMatch.group(1)!.trim()}');
  }
  if (text.contains('Gazebo 가') && text.contains('안에 뜨지 않았습니다')) {
    reasons.add('Gazebo가 제한 시간 안에 /clock을 발행하지 못했습니다.');
  }
  // 실행 스크립트가 스스로 남긴 자국. 여기서 막히면 그 뒤(어댑터·플릿 등록)는
  // 전부 따라 무너지므로, 뒤쪽 증상보다 이것을 먼저 말해야 한다.
  if (text.contains('지도 서버를') && text.contains('초 안에 켜지 못했습니다')) {
    reasons.add(
      '지도 서버(map_server)가 제한 시간 안에 active 가 되지 못했습니다. '
      'Nav2 노드는 시뮬 시각으로 도는데 시뮬이 느리면 그 시간이 벽시계로 몇 배가 '
      '됩니다 — Gazebo 창을 끄고, 카메라 같은 무거운 센서를 뺀 뒤 다시 띄워 '
      '보세요. 그래도 걸리면 MAP_SERVER_WAIT 를 늘려 실행하세요.',
    );
    commands.add('MAP_SERVER_WAIT=300 GAZEBO_GUI=false ./run_$mapName.sh');
  }
  // 노드는 살아 있는데 **서비스가 안 보이는** 상태. DDS 탐색이 무너진 것이다.
  //
  // 실측(2026-08-17) — `/dev/shm` 에 `fastrtps_*` 484개(48MB)가 쌓여 있었고,
  // 그중 200개가 지난 실행 잔재였다. 그 상태에서 map_server 프로세스는 멀쩡히
  // 살아 있었지만 `ros2 node list` 에도 안 나오고 서비스도 안 잡혔다.
  if (text.contains('Waiting for service map_server/get_state')) {
    final segments = _staleDdsSegments();
    reasons.add(
      'lifecycle manager 가 map_server 의 서비스를 못 찾고 있습니다. '
      '프로세스는 살아 있는데 서로를 못 보는 것이라 DDS 탐색이 무너진 것입니다'
      '${segments == null ? '' : ' (/dev/shm 에 DDS 조각 $segments 개)'}. '
      '백엔드를 완전히 중지하고, 남은 ROS 프로세스가 없는 상태에서 공유메모리를 '
      '치운 뒤 다시 띄우세요. 실행 스크립트는 띄우기 전에 스스로 치웁니다 — '
      '옛 스크립트라면 다시 배포하세요.',
    );
    commands.add('pkill -f "ros2 service call /map_server/"');
    commands.add(
      'ros2 daemon stop; rm -f /dev/shm/fastrtps_* /dev/shm/fastdds_*',
    );
  }
  if (text.contains('RMF fleet state에') && text.contains('등록이 없습니다')) {
    reasons.add(
      'fleet adapter 가 로봇을 플릿에 등록하지 못했습니다. 위의 지도 서버 '
      '문제가 있으면 그것부터 풀어야 합니다 — 지도가 없으면 AMCL 이 위치를 '
      '못 내고, 위치가 없으면 등록도 없습니다.',
    );
  }
  if (text.contains('Isaac Sim 프로세스가 /clock 발행 전에 종료됐습니다')) {
    reasons.add('Isaac Sim 프로세스가 /clock 발행 전에 종료됐습니다.');
  }
  if (text.contains('세그멘테이션 오류') || text.contains('Segmentation fault')) {
    reasons.add('시뮬레이터 프로세스가 세그멘테이션 오류로 종료됐습니다.');
  }
  if (text.contains('No database selected')) {
    reasons.add('MySQL 마이그레이션에 사용할 데이터베이스가 선택되지 않았습니다.');
  }

  final interesting = text.split('\n').where((line) {
    final lower = line.toLowerCase();
    return lower.contains('error') ||
        lower.contains('failed') ||
        lower.contains('not found') ||
        lower.contains('실패') ||
        lower.contains('없습니다') ||
        lower.contains('종료됐습니다');
  }).toList();
  final tail = interesting.length > 12
      ? interesting.sublist(interesting.length - 12)
      : interesting;

  final report = StringBuffer('백엔드가 실행 상태에 도달하지 못했습니다.\n');
  if (reasons.isEmpty) {
    report.writeln('\n원인: 로그에서 알려진 원인을 자동으로 특정하지 못했습니다.');
  } else {
    report.writeln('\n원인');
    for (final reason in reasons.toSet()) {
      report.writeln('- $reason');
    }
  }
  if (commands.isNotEmpty) {
    report.writeln('\n필요한 명령 — 아래 내용을 복사해서 터미널에서 실행하세요.');
    report.writeln(commands.toSet().join('\n'));
    report.writeln('\n설치 후 백엔드를 중지하고 다시 실행하세요.');
  }
  if (tail.isNotEmpty) {
    report.writeln('\n최근 오류 로그');
    report.writeln(tail.join('\n'));
  }
  report.writeln('\n전체 로그: $directory/$mapName.err.log');
  return report.toString().trimRight();
}

/// 앱이 띄운 프로젝트. 종료할 때 이것만 정리한다.
///
/// **기억일 뿐 사실이 아니다.** 앱 밖에서 `stop_<맵>.sh` 를 돌리면 프로세스는
/// 사라지는데 이 변수는 그대로 남는다. 예전에는 실행 여부를 이 변수만으로
/// 판단해서, 터미널에서 내린 뒤 앱에서 다시 띄우려 하면 영영 `이미 띄워
/// 두었습니다` 로 막혔다. 앱을 껐다 켜야만 풀렸다.
///
/// 그래서 실제 판단은 늘 [findRunningProjects] 로 한다. 이 변수는 **누가
/// 띄웠는지**만 기억한다 — 앱을 닫을 때 앱이 띄운 것만 정리하기 위해서다.
String? _startedProject;
int? _startedPid;

/// 앱이 지금 띄워 둔 프로젝트 이름. 없으면 null.
///
/// 화면을 그리는 중에 읽으므로 프로세스를 뒤지지 않고 기억만 돌려준다. 낡았을
/// 수 있다 — 버튼을 다시 그리기 전에 [refreshRunningProject] 로 맞춘다.
String? get runningProjectName => _startedProject;

/// 테스트에서만 쓰는 뿌리 경로. 평소에는 null 이다.
///
/// 실행기는 평소 현재 디렉터리에서 위로 올라가며 `rmf_maps` 를 찾는다. 그런데
/// 현재 디렉터리는 프로세스 전체가 공유하는 값이라, 테스트가 그것을 바꾸면 같은
/// 프로세스의 다른 테스트까지 흔든다. 더 나쁜 것은 그러다 **진짜 rmf_maps** 를
/// 찾아 사용자의 배포를 건드릴 수 있다는 점이다.
@visibleForTesting
String? debugProjectRootOverride;

Directory? _findProjectRoot() {
  final override = debugProjectRootOverride;
  if (override != null) return Directory(override).absolute;
  final configured = Platform.environment['RMF_ROOT'];
  if (configured != null && configured.isNotEmpty) {
    final directory = Directory(configured).absolute;
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

String? _mapDirectory(String mapName) {
  final root = _findProjectRoot();
  if (root == null) return null;
  return '${root.path}/rmf_maps/${safeMapDirectoryName(mapName)}';
}

/// 실행 스크립트가 남긴 프로세스 그룹 파일. 이것이 실행 여부의 근거다.
///
/// `run_<맵>.sh` 가 뜨면서 제 PGID 를 여기 적고, `stop_<맵>.sh` 가 내리면서
/// 지운다. 앱이 띄웠든 터미널에서 띄웠든 같은 파일이라, 누가 띄웠는지와 무관하게
/// 지금 도는지를 알 수 있다.
File _pgidFile(String directory, String mapName) =>
    File('$directory/.$mapName.pgid');

/// 파일에 적힌 프로세스 그룹이 살아 있으면 그 번호를, 아니면 null 을 준다.
///
/// 죽어 있으면 파일을 지운다. 프로세스가 이미 없는데 파일만 남아 있으면 다음
/// 실행이 또 막힌다 — 사용자가 손으로 지워야 풀리는 상태를 만들지 않는다.
/// 지우기가 실패해도(권한·경합) 살아 있지 않다는 답은 그대로 준다.
///
/// 다만 **빈 파일은 건드리지 않는다.** 실행 스크립트는 `ps ... > 파일` 로
/// 적는데, 셸이 파일을 먼저 만들고 그 다음에 쓴다. 그 찰나에 우리가 지우면
/// 스크립트의 쓰기는 이름 없는 inode 로 흘러가 **그룹 번호가 영영 사라진다.**
/// 그러면 중지할 때 무엇을 끊어야 할지 알 수 없다.
Future<int?> _pgidIfAlive(File file) async {
  if (!file.existsSync()) return null;
  final text = (await file.readAsString()).trim();
  if (text.isEmpty) return null;
  final pgid = int.tryParse(text);
  // 음수는 프로세스 그룹. 시그널 0 은 죽이지 않고 살아 있는지만 본다.
  if (pgid != null) {
    final alive = await Process.run('kill', ['-0', '--', '-$pgid']);
    if (alive.exitCode == 0) return pgid;
  }
  try {
    if (file.existsSync()) await file.delete();
  } on FileSystemException {
    // 지우지 못해도 살아 있지 않다는 판단은 바뀌지 않는다.
  }
  return null;
}

/// 그 프로젝트가 지금 실제로 도는지 본다. 돌면 프로세스 그룹 번호.
Future<int?> _runningPgid(String mapName) async {
  final directory = _mapDirectory(mapName);
  if (directory == null) return null;
  return _pgidIfAlive(_pgidFile(directory, mapName));
}

/// `run_<맵이름>.sh` 를 띄운다.
///
/// [gazeboGui] 와 [rviz] 는 창을 띄울지 말지다. 실행 스크립트가 같은 이름의
/// 환경 변수로 받는다. 기본은 둘 다 안 띄우는 것이다 — 창이 없어도 라이다·
/// 카메라는 돌고, 창 두 개를 함께 띄우면 시뮬레이션이 눈에 띄게 느려진다.
Future<RmfRunResult> startProject(
  String mapName, {
  SimulationBackend backend = SimulationBackend.gazebo,
  bool gazeboGui = false,
  bool rviz = false,
}) async {
  // 앱의 기억이 아니라 지금 도는 프로세스를 본다. 터미널에서 내린 것을 앱은
  // 모르므로, 기억만 믿으면 그 뒤로 영영 `이미 띄워 두었습니다` 가 된다.
  final running = await findRunningProjects();
  if (running.isNotEmpty) {
    // 요청한 맵이 도는 중이면 그것을 짚어 준다. 다른 맵이면 그것을 짚는다 —
    // 한 번에 하나만 띄운다. 두 벌이 같은 도메인에 뜨면 schedule node 가
    // 부딪혀 엉뚱한 오류로 나타난다.
    final blocking = running.firstWhere(
      (project) => project.mapName == mapName,
      orElse: () => running.first,
    );
    final byApp = blocking.mapName == _startedProject;
    return RmfRunResult(
      success: false,
      message:
          '`${blocking.mapName}` 이(가) 이미 돌고 있습니다 '
          '(프로세스 그룹 ${blocking.pgid}).\n'
          '${byApp ? '먼저 중지하세요.' : '앱이 띄운 것이 아닙니다. 터미널에서 stop_${blocking.mapName}.sh 를 돌리거나 '
                    '로봇 운영 화면에서 정리하세요.'}',
    );
  }
  // 여기까지 왔으면 도는 것이 없다. 기억이 남아 있었다면 그것이 낡은 것이다.
  _startedProject = null;
  _startedPid = null;

  final directory = _mapDirectory(mapName);
  if (directory == null) {
    return const RmfRunResult(
      success: false,
      message: 'rmf_maps 디렉터리를 찾을 수 없습니다. RMF_ROOT 를 지정하세요.',
    );
  }
  final script = File('$directory/run_$mapName.sh');
  if (!script.existsSync()) {
    return RmfRunResult(
      success: false,
      message:
          '${script.path} 가 없습니다.\n'
          '설정 파일 메뉴에서 `디스크로 내보내기`를 먼저 누르세요.',
    );
  }
  // 예전에 내보낸 스크립트는 HEADLESS 하나로 둘을 함께 껐다. 그것에 대고
  // GAZEBO_GUI 를 넘겨 봐야 아무 일도 일어나지 않는다. 조용히 넘기면 "창을
  // 골랐는데 안 뜬다" 가 되고, 원인이 디스크의 낡은 파일이라는 것은 어디에도
  // 안 보인다. 창을 달라고 했을 때만 막는다 — 안 띄우는 것은 예전 스크립트도
  // 결과가 같다.
  final scriptContents = script.readAsStringSync();
  if ((gazeboGui || rviz) && !scriptContents.contains('GAZEBO_GUI')) {
    return RmfRunResult(
      success: false,
      message:
          '${script.path} 는 창을 따로 고를 수 없는 예전 판입니다.\n'
          '설정 파일 메뉴에서 `디스크로 내보내기`를 한 번 눌러 다시 만든 뒤 '
          '실행하세요.\n\n'
          '창 없이 띄우는 것은 지금 그대로도 됩니다.',
    );
  }
  if (backend != SimulationBackend.gazebo &&
      !scriptContents.contains('SIM_BACKEND')) {
    return RmfRunResult(
      success: false,
      message:
          '${script.path} 는 Gazebo만 지원하는 예전 판입니다.\n'
          '설정 파일 메뉴에서 `디스크로 내보내기`를 한 번 눌러 다시 만든 뒤 '
          '실행하세요.',
    );
  }
  if (backend == SimulationBackend.isaacSim) {
    final isaacScript = File('$directory/isaac/start_$mapName.py');
    final isaacConverter = File('$directory/isaac/convert_$mapName.py');
    final home = Platform.environment['HOME'] ?? '';
    final configuredPython = Platform.environment['ISAAC_SIM_PYTHON'];
    final configuredRoot = Platform.environment['ISAAC_SIM_ROOT'];
    final candidates = <String>[
      if (configuredPython != null && configuredPython.isNotEmpty)
        configuredPython,
      if (configuredRoot != null && configuredRoot.isNotEmpty)
        '$configuredRoot/python.sh',
      if (home.isNotEmpty) '$home/isaacsim/python.sh',
      if (home.isNotEmpty)
        '$home/isaac/isaacsim/_build/linux-x86_64/release/python.sh',
      if (home.isNotEmpty) '$home/isaac/env_isaaclab/bin/python',
    ];
    final launcher = candidates
        .where((path) => File(path).existsSync())
        .firstOrNull;
    if (launcher == null) {
      return const RmfRunResult(
        success: false,
        message:
            'Isaac Sim Python 실행기를 찾지 못했습니다.\n'
            'ISAAC_SIM_PYTHON 또는 ISAAC_SIM_ROOT를 지정하세요.',
      );
    }
    final missing = <String>[
      if (!isaacScript.existsSync()) isaacScript.path,
      if (!isaacConverter.existsSync()) isaacConverter.path,
    ];
    if (missing.isNotEmpty) {
      return RmfRunResult(
        success: false,
        message:
            'Isaac Sim 프로젝트 산출물이 없습니다.\n'
            '필요한 파일:\n${missing.join('\n')}\n\n'
            '프로젝트를 다시 저장하여 변환기를 생성한 뒤 실행하세요.',
      );
    }
  }
  try {
    // detached 로 띄우면 Dart 가 새 세션을 만들어 주므로 앱이 죽어도 함께
    // 끌려가지 않는다. 다만 여기서 받는 pid 는 그룹 리더가 아니다 — 그룹 정리는
    // 실행 스크립트가 남긴 PGID 파일을 보고 중지 스크립트가 한다.
    //
    // stdio 를 물리지 않는다. detachedWithStdio 로 띄우면 파이프가 생기는데
    // 앱이 그것을 읽지 않아, 64KB 가 차는 순간 Gazebo 가 write 에서 영원히
    // 멈춘다. 물리가 돌지 않아 모델도 안 올라오고 토픽에 값도 오지 않았다.
    // 출력은 실행 스크립트가 제 로그 파일로 보낸다.
    final process = await Process.start(
      'bash',
      [script.path],
      workingDirectory: directory,
      // 스크립트가 고른 값을 그대로 읽는다. 인자가 아니라 환경 변수인 것은,
      // 터미널에서 직접 띄울 때와 같은 방법이라야 앱 밖에서도 재현되기
      // 때문이다.
      environment: {
        'SIM_BACKEND': backend.storageValue,
        'GAZEBO_GUI': '$gazeboGui',
        'SIMULATOR_GUI': '$gazeboGui',
        'RVIZ': '$rviz',
      },
      mode: ProcessStartMode.detached,
    );
    _startedProject = mapName;
    _startedPid = process.pid;
    final shown = [
      if (gazeboGui && backend != SimulationBackend.none) '${backend.label} 창',
      if (rviz) 'RViz',
    ];
    return RmfRunResult(
      success: true,
      message:
          '`$mapName` 을 ${backend.label} 백엔드로 띄웠습니다 (pid $_startedPid).\n'
          '${shown.isEmpty ? '창 없이 띄웁니다.' : '${shown.join(' · ')} 을(를) 함께 띄웁니다.'}',
    );
  } catch (error) {
    return RmfRunResult(success: false, message: '$error');
  }
}

/// `stop_<맵이름>.sh` 로 내린다. [mapName] 을 주지 않으면 앱이 띄운 것을 내린다.
Future<RmfRunResult> stopProject([String? mapName]) async {
  // 기억이 낡았을 수 있다. 내릴 대상을 정하기 전에 실제와 맞춘다.
  final target = mapName ?? await refreshRunningProject();
  if (target == null) {
    // 앱이 띄운 것은 없지만 다른 것이 돌 수 있다. 그냥 `없습니다` 로 끝내면
    // 무엇이 실행 버튼을 막고 있는지 화면에서 알 길이 없다.
    final running = await findRunningProjects();
    if (running.isEmpty) {
      return const RmfRunResult(success: false, message: '앱이 띄워 둔 프로젝트가 없습니다.');
    }
    return RmfRunResult(
      success: false,
      message:
          '앱이 띄워 둔 프로젝트는 없습니다.\n'
          '다만 아직 도는 것이 있습니다 — '
          '${running.map((p) => '${p.mapName} (그룹 ${p.pgid})').join(', ')}.\n'
          '로봇 운영 화면에서 정리하세요.',
    );
  }
  final directory = _mapDirectory(target);
  if (directory == null) {
    return const RmfRunResult(
      success: false,
      message: 'rmf_maps 디렉터리를 찾을 수 없습니다.',
    );
  }
  final buffer = StringBuffer();
  final script = File('$directory/stop_$target.sh');
  if (script.existsSync()) {
    try {
      final result = await Process.run('bash', [
        script.path,
      ], workingDirectory: directory).timeout(const Duration(seconds: 60));
      buffer.writeln(result.stdout.toString().trim());
      final error = result.stderr.toString().trim();
      if (error.isNotEmpty) buffer.writeln(error);
    } catch (error) {
      buffer.writeln('중지 스크립트 실패: $error');
    }
  } else {
    buffer.writeln('${script.path} 가 없습니다. 프로세스 그룹만 정리합니다.');
  }
  // 중지 스크립트가 없거나 놓친 것이 있으면 여기서 마무리한다.
  //
  // 그룹 번호는 실행 스크립트가 남긴 파일에서 읽는다. Process.start 가 돌려준
  // pid 는 그룹 리더가 아니라서 그 번호로 그룹을 끊으면 엉뚱한 곳을 건드린다.
  final pgidFile = _pgidFile(directory, target);
  if (pgidFile.existsSync()) {
    final pgid = int.tryParse((await pgidFile.readAsString()).trim());
    if (pgid != null) {
      final alive = await Process.run('kill', ['-0', '--', '-$pgid']);
      if (alive.exitCode == 0) {
        await Process.run('kill', ['-INT', '--', '-$pgid']);
        await Future<void>.delayed(const Duration(seconds: 3));
        await Process.run('kill', ['-TERM', '--', '-$pgid']);
        buffer.writeln('프로세스 그룹 $pgid 를 정리했습니다.');
      }
    }
    if (pgidFile.existsSync()) await pgidFile.delete();
  }
  _startedProject = null;
  _startedPid = null;
  return RmfRunResult(success: true, message: buffer.toString().trim());
}

/// 지난 실행에서 정리되지 않고 남은 프로젝트.
class OrphanedProject {
  const OrphanedProject({required this.mapName, required this.pgid});

  final String mapName;
  final int pgid;
}

/// 지금 실제로 도는 프로젝트를 모두 찾는다. 누가 띄웠는지는 가리지 않는다.
///
/// 실행 스크립트가 남긴 `.<맵이름>.pgid` 를 훑어 그 프로세스 그룹이 아직 살아
/// 있는지 본다. 이것이 실행 여부의 유일한 근거다 — 앱의 기억은 앱 밖에서 벌어진
/// 일을 모른다.
///
/// 프로세스가 이미 없는 파일은 조용히 지운다. 남지도 않은 것을 두고 알릴 일은
/// 아니다.
Future<List<OrphanedProject>> findRunningProjects() async {
  final root = _findProjectRoot();
  if (root == null) return const [];
  final maps = Directory('${root.path}/rmf_maps');
  if (!maps.existsSync()) return const [];
  final found = <OrphanedProject>[];
  for (final entry in maps.listSync()) {
    if (entry is! Directory) continue;
    for (final file in entry.listSync()) {
      if (file is! File) continue;
      final name = file.uri.pathSegments.last;
      if (!name.startsWith('.') || !name.endsWith('.pgid')) continue;
      final mapName = name.substring(1, name.length - '.pgid'.length);
      final pgid = await _pgidIfAlive(file);
      if (pgid == null) continue;
      found.add(OrphanedProject(mapName: mapName, pgid: pgid));
    }
  }
  found.sort((a, b) => a.mapName.compareTo(b.mapName));
  return found;
}

/// 강제 종료로 남은 프로젝트를 찾는다. 앱이 띄워 둔 것은 뺀다.
///
/// 앱이 강제로 죽으면(kill -9·전원) 종료 훅이 돌지 않아 프로세스가 그대로
/// 남는다. 그것을 시작할 때 알아채고 정리하라고 알린다.
Future<List<OrphanedProject>> findOrphanedProjects() async {
  final running = await findRunningProjects();
  // 도는 것이 없으면 앱의 기억도 낡은 것이다. 여기서 같이 털어 낸다.
  if (!running.any((project) => project.mapName == _startedProject)) {
    _startedProject = null;
    _startedPid = null;
  }
  return running
      .where((project) => project.mapName != _startedProject)
      .toList(growable: false);
}

/// [runningProjectName] 을 실제 프로세스와 맞춘다. 맞춘 뒤의 값을 돌려준다.
///
/// 앱 밖에서 내린 프로젝트를 앱이 계속 띄워 둔 것으로 알고 있으면, 실행 버튼
/// 대신 중지 버튼이 남아 다시 띄울 길이 없어진다. 화면을 그리기 전에 부른다.
///
/// 앱이 띄우지 않은 것은 여기서 제 것으로 삼지 않는다. 그랬다가는 앱을 닫을 때
/// 사용자가 터미널에서 띄운 것까지 함께 내린다.
Future<String?> refreshRunningProject() async {
  final started = _startedProject;
  if (started == null) return null;
  if (await _runningPgid(started) != null) return started;
  _startedProject = null;
  _startedPid = null;
  return null;
}
