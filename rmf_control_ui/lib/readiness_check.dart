/// 작업을 낼 수 있는 상태인지 단계별로 확인한다.
///
/// 로봇이 RViz 에 뜨려면 다섯 가지가 줄줄이 되어야 한다 — Gazebo, AMCL 의 TF,
/// 어댑터의 `add_robot`, RMF 의 수락, `/fleet_states` 발행. 하나만 끊겨도
/// 화면은 그냥 빈다. **오류는 어디에도 안 난다.**
///
/// 실제로 어댑터가 SIGSEGV 로 죽어 경로와 로봇이 통째로 사라진 적이 있는데,
/// Gazebo·Nav2·RMF core 는 멀쩡히 살아 있어 겉으로는 정상으로 보였다. 무엇이
/// 끊겼는지 알려면 로그를 뒤지고 토픽을 하나씩 쳐 봐야 했다.
///
/// 그 확인을 화면이 대신한다. 여기는 판단만 한다 — 값을 모으는 일은 부르는
/// 쪽이 하고, 이 파일은 프로세스도 파일도 건드리지 않는다.
library;

import 'nav2_map_alignment.dart';
import 'rmf_project_config.dart';

/// 확인 하나의 결과.
enum ReadinessState {
  /// 됐다.
  ready,

  /// 안 됐다. 무엇을 해야 하는지 안다.
  blocked,

  /// 모른다. 확인할 수단이 지금 없다는 뜻이지, 안 됐다는 뜻이 아니다.
  ///
  /// 이 둘을 뭉뚱그리면 "확인 못 함" 이 "고장" 으로 읽힌다. 백엔드가 안 떠
  /// 있으면 로봇이 붙었는지 알 길이 없는데, 그것을 빨간불로 보여 주면 멀쩡한
  /// 로봇을 두고 원인을 찾게 된다.
  unknown,
}

/// 단계 하나.
class ReadinessCheck {
  const ReadinessCheck({
    required this.title,
    required this.state,
    required this.detail,
  });

  final String title;
  final ReadinessState state;

  /// 됐으면 무엇이 확인됐는지, 안 됐으면 **무엇을 하면 되는지**.
  ///
  /// 이유만 적으면 화면을 보고도 다음 손이 안 나간다.
  final String detail;

  bool get isReady => state == ReadinessState.ready;
  bool get isBlocked => state == ReadinessState.blocked;
}

/// 확인 전체.
class ReadinessReport {
  const ReadinessReport(this.checks);

  final List<ReadinessCheck> checks;

  /// 다 됐는가. 하나라도 모르면 다 됐다고 하지 않는다.
  bool get isReady => checks.every((check) => check.isReady);

  /// 처음으로 막힌 단계. 없으면 null.
  ///
  /// 앞 단계가 막히면 뒤는 대개 따라서 막힌다. 여섯 줄을 다 읽으라고 하는 대신
  /// 손댈 곳 하나를 짚어 준다.
  ReadinessCheck? get firstBlocked =>
      checks.where((check) => check.isBlocked).firstOrNull;

  /// 한 줄 요약.
  String get summary {
    if (isReady) return '작업을 낼 수 있습니다.';
    final blocked = firstBlocked;
    if (blocked != null) return '${blocked.title} — ${blocked.detail}';
    return '아직 확인하지 못한 단계가 있습니다.';
  }
}

/// 어댑터가 `/fleet_states` 를 내기까지 기다려 주는 시간.
///
/// 백엔드를 띄우면 Gazebo·RMF core 가 먼저 서고 어댑터는 마지막에 붙는다. 그
/// 사이에는 토픽이 없는 것이 **정상**이다. 실측(2026-08-15) — 실행 14:44:59,
/// 어댑터 노드 14:45:23, 로봇 등록 14:45:31 로 32초가 걸렸다. 넉넉히 두 배를
/// 준다.
///
/// 이 시간을 안 두면 띄울 때마다 30초 동안 `어댑터가 죽었습니다` 가 뜬다.
const adapterStartupGrace = Duration(seconds: 60);

/// 지금 상태로 확인표를 만든다.
///
/// [attachedRobots] 는 `/fleet_states` 에서 읽은 로봇 이름이다. [fleetReachable]
/// 이 false 면 그 토픽을 못 읽었다는 뜻이라, 빈 목록을 "로봇이 하나도 안 붙었다"
/// 로 읽으면 안 된다.
///
/// [backendUptime] 은 백엔드가 뜬 뒤로 지난 시간이다. 못 읽은 것이 **아직**인지
/// **끊긴 것**인지는 이것으로 가른다.
ReadinessReport buildReadinessReport({
  required List<String> waypointNames,
  required List<RmfProjectRobot> robots,
  required bool exported,
  required bool backendRunning,
  required bool fleetReachable,
  required Set<String> attachedRobots,
  // 위치추정 지도와 주행 그래프가 같은 자리에 있는가. null 이면 아직 못 봤다.
  Nav2MapAlignment? alignment,
  // `/clock` 을 내는 곳의 수. null 이면 못 셌다.
  int? clockPublishers,
  // 이 프로젝트가 시뮬레이터로 도는가.
  //
  // 시뮬레이터가 없으면 `/clock` 자체가 없다 — 실행 스크립트가 `use_sim_time` 을
  // false 로 두고 모든 노드가 실제 시계를 쓴다. 그런 프로젝트에 시계 칸을 두면
  // **영영 안 채워지는 칸**이 하나 남는다. 실물 Pinky 로 돌린 확인표가 그랬다:
  //
  //     (모름) 시뮬레이션 시계 — 백엔드가 떠야 확인할 수 있습니다
  //
  // 백엔드를 띄워도 그대로였고, 그러면 다 됐는지를 이 표로 알 수 없게 된다
  // (`isReady` 는 모든 칸이 ready 여야 참이다).
  //
  // 기본값을 true 로 둔다 — 대부분의 프로젝트가 시뮬레이터를 쓰고, 모르는 채로
  // 칸을 없애면 진짜 두 시계 문제를 놓친다.
  bool usesSimulator = true,
  // Nav2 `map_server` 의 생명주기 상태(`active` 여야 지도가 나온다).
  // null 이면 못 물었다.
  String? mapServerState,
  // 백엔드가 뜬 뒤로 지난 시간. null 이면 언제 떴는지 모른다.
  Duration? backendUptime,
}) {
  final places = waypointNames
      .where((name) => name.trim().isNotEmpty)
      .toList(growable: false);
  final mobile = robots
      .where((robot) => robot.isMobile && robot.isManagedByRmf)
      .toList(growable: false);

  final checks = <ReadinessCheck>[
    // ① 갈 곳. RMF 는 좌표가 아니라 이름으로 자리를 찾는다.
    places.isEmpty
        ? const ReadinessCheck(
            title: '지도와 Waypoint',
            state: ReadinessState.blocked,
            detail:
                '이름이 붙은 Waypoint 가 없습니다. 맵 관리에서 Waypoint 를 놓고 '
                '이름을 지어 주세요 — RMF 는 좌표가 아니라 이름으로 자리를 찾습니다.',
          )
        : ReadinessCheck(
            title: '지도와 Waypoint',
            state: ReadinessState.ready,
            detail: 'Waypoint ${places.length}곳',
          ),

    // ② 맡을 로봇. RMF 는 등록된 로봇만 안다.
    mobile.isEmpty
        ? const ReadinessCheck(
            title: '로봇 등록',
            state: ReadinessState.blocked,
            detail:
                '관제할 이동 로봇이 없습니다. 로봇 화면에서 등록하세요. '
                'Mock 로봇은 앱 안에서만 돌아 RMF 가 모릅니다.',
          )
        : ReadinessCheck(
            title: '로봇 등록',
            state: ReadinessState.ready,
            detail:
                '이동 로봇 ${mobile.length}대 — '
                '${mobile.map((robot) => robot.robotId).join(' · ')}',
          ),

    // ③ 디스크의 산출물. ros2 launch 는 파일만 읽는다.
    exported
        ? const ReadinessCheck(
            title: 'RMF 설정 내보내기',
            state: ReadinessState.ready,
            detail: '실행 스크립트와 launch 파일이 디스크에 있습니다',
          )
        : const ReadinessCheck(
            title: 'RMF 설정 내보내기',
            state: ReadinessState.blocked,
            detail:
                '실행에 쓸 파일이 디스크에 없습니다. 설정 파일 메뉴에서 '
                '`디스크로 내보내기` 를 누르세요 — ros2 launch 는 앱이 아니라 '
                '파일을 읽습니다.',
          ),

    // ③-2 지도 정합. AMCL 이 맞출 격자와 RMF 가 길을 찾는 그래프가 같은 월드
    //      좌표에 있어야 한다. 어긋나면 RMF 는 `픽업1` 로 보내는데 AMCL 은
    //      로봇이 딴 데 있다고 여긴다 — 오류는 안 나고 로봇만 엉뚱하게 간다.
    if (!exported || alignment == null)
      const ReadinessCheck(
        title: '지도 정합',
        state: ReadinessState.unknown,
        detail: '내보낸 지도와 주행 그래프가 있어야 확인할 수 있습니다',
      )
    else if (alignment.isAligned)
      ReadinessCheck(
        title: '지도 정합',
        state: ReadinessState.ready,
        detail:
            '주행 그래프가 지도 안에 있습니다 '
            '(가장자리까지 ${alignment.marginMeters.toStringAsFixed(2)}m)',
      )
    else if (!alignment.covered)
      ReadinessCheck(
        title: '지도 정합',
        state: ReadinessState.blocked,
        detail:
            '${alignment.outsideWaypoints.join(' · ')} 이(가) 위치추정 지도 '
            '밖입니다. AMCL 이 자리를 못 잡아 로봇이 엉뚱한 데로 갑니다.\n'
            'SLAM 지도를 쓰고 있다면 그리드맵 화면에서 끄세요 — 도면에서 구운 '
            '격자는 주행 그래프와 같은 도면에서 나와 어긋나지 않습니다.',
      )
    else
      ReadinessCheck(
        title: '지도 정합',
        state: ReadinessState.blocked,
        detail:
            '주행 그래프가 지도 가장자리에 너무 붙어 있습니다 '
            '(${alignment.marginMeters.toStringAsFixed(2)}m, '
            '${minAlignmentMargin.toStringAsFixed(2)}m 이상 필요). '
            '그 자리에서는 라이다 절반이 지도 밖을 봐 위치추정이 흔들립니다.',
      ),

    // ④ 백엔드. 여기부터는 실제로 떠 있어야 확인할 수 있다.
    backendRunning
        ? const ReadinessCheck(
            title: 'Open-RMF 실행',
            state: ReadinessState.ready,
            detail: 'Gazebo 와 RMF core 가 떠 있습니다',
          )
        : const ReadinessCheck(
            title: 'Open-RMF 실행',
            state: ReadinessState.blocked,
            detail:
                '떠 있지 않습니다. 작업을 넣어도 받을 쪽이 없습니다. '
                '설정 파일 메뉴에서 `프로젝트 실행` 을 누르세요.',
          ),
  ];

  // ④-2 시계. `/clock` 은 **하나만** 나와야 한다.
  //
  //      둘이면 이전 실행에서 남은 `parameter_bridge` 가 살아 있다는 뜻이다.
  //      두 시계가 번갈아 나오니 시각이 앞뒤로 튀고, tf2 가 버퍼를 통째로
  //      비운다(`Detected jump back in time`). AMCL 은 위치추정을 잃고 Nav2 는
  //      명령을 멈춘다 — 로봇은 멀쩡한데 가만히 서 있고, 원인이 한 시간 전에
  //      남은 프로세스라는 것은 어디에도 안 보인다.
  //
  //      시뮬레이터가 없으면 이 칸을 아예 두지 않는다. 볼 시계가 없다.
  if (!usesSimulator) {
    // 아무 칸도 넣지 않는다.
  } else if (!backendRunning || clockPublishers == null) {
    checks.add(
      const ReadinessCheck(
        title: '시뮬레이션 시계',
        state: ReadinessState.unknown,
        detail: '백엔드가 떠야 확인할 수 있습니다',
      ),
    );
  } else if (clockPublishers == 1) {
    checks.add(
      const ReadinessCheck(
        title: '시뮬레이션 시계',
        state: ReadinessState.ready,
        detail: '/clock 을 내는 곳이 하나입니다',
      ),
    );
  } else if (clockPublishers == 0) {
    checks.add(
      const ReadinessCheck(
        title: '시뮬레이션 시계',
        state: ReadinessState.blocked,
        detail:
            '/clock 이 안 나옵니다. Gazebo 가 죽었거나 토픽 다리가 '
            '안 떴습니다 — use_sim_time 을 쓰는 노드가 전부 시간이 멈춘 줄 '
            '알고 기다립니다.',
      ),
    );
  } else {
    checks.add(
      ReadinessCheck(
        title: '시뮬레이션 시계',
        state: ReadinessState.blocked,
        detail:
            '/clock 을 $clockPublishers 곳이 내고 있습니다. 하나여야 '
            '합니다.\n이전 실행에서 남은 토픽 다리가 살아 있습니다. 시각이 '
            '앞뒤로 튀어 AMCL 이 위치추정을 잃고 로봇이 멈춥니다. '
            '`pkill -f ros_gz_bridge/parameter_bridge` 로 정리한 뒤 프로젝트를 '
            '다시 실행하세요.',
      ),
    );
  }

  // ④-1 지도 서버. 어댑터보다 **앞**이라야 한다.
  //
  //     map_server → (지도) → AMCL → (map TF) → 어댑터 → /fleet_states
  //
  // 여기가 끊기면 뒤가 전부 무너지는데, 예전에는 맨 끝만 보고 `어댑터가
  // 죽었습니다` 라고 했다. 2026-08-17 에 실제로 그랬다 — 어댑터는 멀쩡히
  // 살아서 30초마다 재기동되고 있었고, 멈춰 있던 것은 map_server 였다.
  //
  // 생명주기 관리자가 activate 를 안 보내는 일이 있다. change_state 응답
  // 시한이 5초로 코드에 박혀 있어(파라미터가 없다) 기계가 바쁘면 늦고,
  // 관리자는 실패로 보고 거기서 멈춘 채 다시 시도하지 않는다.
  final mapServerReady = mapServerState == 'active';
  if (!backendRunning) {
    checks.add(
      const ReadinessCheck(
        title: 'Nav2 지도 서버',
        state: ReadinessState.unknown,
        detail: '백엔드가 떠야 확인할 수 있습니다',
      ),
    );
  } else if (mapServerState == null) {
    checks.add(
      const ReadinessCheck(
        title: 'Nav2 지도 서버',
        state: ReadinessState.unknown,
        detail: 'map_server 에 상태를 묻지 못했습니다. 아직 뜨는 중일 수 있습니다.',
      ),
    );
  } else if (mapServerReady) {
    checks.add(
      const ReadinessCheck(
        title: 'Nav2 지도 서버',
        state: ReadinessState.ready,
        detail: 'map_server 가 active 입니다. 지도가 나옵니다.',
      ),
    );
  } else {
    checks.add(
      ReadinessCheck(
        title: 'Nav2 지도 서버',
        state: ReadinessState.blocked,
        detail:
            'map_server 가 [$mapServerState] 에 멈춰 있어 지도가 안 나옵니다. '
            'AMCL 이 map TF 를 못 내고, 그래서 로봇이 RMF 에 못 붙습니다. '
            '실행 스크립트가 스스로 켜려고 하지만 안 되면 백엔드를 다시 '
            '실행하세요. 로그: <맵>.err.log 의 "Waiting for map"',
      ),
    );
  }

  // ⑤ 어댑터. 이것이 RMF 안에서 /nav_graphs 와 /fleet_states 를 내는 유일한
  //    노드다. 죽으면 RViz 에서 경로와 로봇이 통째로 사라지는데 오류는 안 난다.
  if (!backendRunning) {
    checks.add(
      const ReadinessCheck(
        title: 'RMF↔Nav2 어댑터',
        state: ReadinessState.unknown,
        detail: '백엔드가 떠야 확인할 수 있습니다',
      ),
    );
  } else if (fleetReachable) {
    checks.add(
      const ReadinessCheck(
        title: 'RMF↔Nav2 어댑터',
        state: ReadinessState.ready,
        detail: '/fleet_states 가 나오고 있습니다',
      ),
    );
  } else if (backendUptime != null && backendUptime < adapterStartupGrace) {
    // 아직 안 온 것과 끊긴 것은 다르다. 뜨는 중을 빨간불로 보여 주면, 30초만
    // 기다리면 될 것을 두고 멀쩡한 어댑터의 원인을 찾게 된다.
    checks.add(
      ReadinessCheck(
        title: 'RMF↔Nav2 어댑터',
        state: ReadinessState.unknown,
        detail:
            '/fleet_states 를 아직 못 받았습니다. 어댑터는 Gazebo·RMF core 다음에 '
            '붙어서 ${adapterStartupGrace.inSeconds}초쯤 걸립니다 — 조금 기다려 '
            '주세요.',
      ),
    );
  } else if (mapServerState != null && !mapServerReady) {
    // 지도가 없으면 어댑터는 **살아 있어도** 등록할 수 없다. 로봇 위치를
    // TF 에서 읽는데 AMCL 이 map TF 를 안 내기 때문이다. 여기서 어댑터를
    // 죽었다고 하면, 멀쩡한 어댑터의 원인을 찾느라 시간을 버린다.
    checks.add(
      const ReadinessCheck(
        title: 'RMF↔Nav2 어댑터',
        state: ReadinessState.blocked,
        detail:
            '/fleet_states 가 안 나옵니다. 다만 어댑터 탓이 아닙니다 — '
            '위의 Nav2 지도 서버부터 켜져야 합니다. 지도가 없으면 어댑터가 '
            '로봇 위치를 읽지 못해 플릿에 등록할 수 없습니다.',
      ),
    );
  } else {
    checks.add(
      const ReadinessCheck(
        title: 'RMF↔Nav2 어댑터',
        state: ReadinessState.blocked,
        detail:
            '/fleet_states 가 안 나옵니다. 어댑터가 죽었습니다 — '
            'RViz 에서도 경로와 로봇이 사라집니다. 프로젝트를 다시 실행하세요. '
            '로그: <맵>.err.log',
      ),
    );
  }

  // ⑥ 로봇 한 대 한 대. 여기까지 와야 그 로봇에게 작업을 줄 수 있다.
  if (!backendRunning || !fleetReachable) {
    checks.add(
      const ReadinessCheck(
        title: '로봇이 RMF 에 붙음',
        state: ReadinessState.unknown,
        detail: '앞 단계가 되어야 확인할 수 있습니다',
      ),
    );
  } else {
    final missing = mobile
        .where((robot) => !attachedRobots.contains(robot.robotId))
        .map((robot) => robot.robotId)
        .toList(growable: false);
    checks.add(
      missing.isEmpty && mobile.isNotEmpty
          ? ReadinessCheck(
              title: '로봇이 RMF 에 붙음',
              state: ReadinessState.ready,
              detail: '${mobile.length}대 모두 붙었습니다',
            )
          : ReadinessCheck(
              title: '로봇이 RMF 에 붙음',
              state: ReadinessState.blocked,
              detail: mobile.isEmpty
                  ? '붙을 로봇이 없습니다'
                  : '${missing.join(' · ')} 이(가) 아직 안 붙었습니다. '
                        'AMCL 이 잡히는 데 시간이 걸립니다. 오래 걸리면 로봇이 '
                        'nav graph 에서 너무 먼 자리에 서 있는 것입니다 — '
                        '로봇 화면의 `자리 점검` 을 보세요.',
            ),
    );
  }

  return ReadinessReport(checks);
}
