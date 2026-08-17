/// 벤더의 Nav2 파라미터를 로봇 한 대에 맞춰 다시 쓴다.
///
/// `pinky_navigation/params/nav2_params.yaml` 은 로봇 한 대를 전제로 쓰였다.
/// 두 대를 같은 월드에 올리면 **서로의 라이다를 보고** `map`·`odom` TF 가
/// 충돌한다. 벤더 bridge yaml 이 상대 이름을 써서 로봇들이 서로 부딪혔던 것과
/// 같은 문제다 — `docs/MULTI_ROBOT_NAMESPACES.md` 를 보라.
///
/// 벤더 파일을 **고치지 않는다.** 읽어서 로봇마다 다시 쓴다. 벤더가 맞춰 둔
/// 속도·컨트롤러 설정과 주석을 그대로 살리면서 이름만 가른다.
///
/// 줄 단위로 다시 쓴다. YAML 로 읽어 다시 쓰면 주석이 전부 날아가는데, 벤더
/// 파일의 주석은 왜 그 값인지를 적어 둔 것이라 잃으면 손해다.
library;

import 'nav2_progress_checker.dart';

/// 다시 쓴 결과.
class Nav2ParamsRewrite {
  const Nav2ParamsRewrite({
    required this.yaml,
    required this.changes,
    required this.warnings,
  });

  /// 다시 쓴 내용.
  final String yaml;

  /// 무엇을 바꿨는지. 사람이 확인할 수 있어야 한다.
  final List<String> changes;

  /// 손대지 못한 것. 벤더 파일이 바뀌면 여기 걸린다.
  final List<String> warnings;

  bool get clean => warnings.isEmpty;
}

/// Nav2 가 쓰는 점유격자가 나가는 토픽.
///
/// `/map` 을 쓸 수 없다. RMF 의 `building_map_server` 가 이미 그 이름으로
/// `rmf_building_map_msgs/BuildingMap` 을 내고 있어서, 같이 쓰면 한 토픽에 형식이
/// 둘 올라간다. 로봇마다 가르지도 않는다 — 같은 건물이므로 하나면 된다.
const String nav2MapTopic = '/nav2_map';

/// `map_server` 쪽에 주는 이름. 루트 네임스페이스라 빗금을 뺀 것이 같은 곳이다.
const String nav2MapTopicName = 'nav2_map';

/// 로봇마다 갈라야 하는 TF 프레임.
///
/// `map` 은 여기 없다 — 같은 건물이므로 **함께 쓴다**. 로봇마다 제 AMCL 이
/// `map → <로봇>/odom` 을 내므로 프레임 이름이 다르면 한 트리에 공존한다.
const Set<String> _frameKeys = {
  'base_frame_id',
  'odom_frame_id',
  'robot_base_frame',
  'local_frame',
};

/// 값이 `odom` 일 때만 갈라야 하는 프레임. `map` 이면 그대로 둔다.
const Set<String> _conditionalFrameKeys = {'global_frame', 'global_frame_id'};

/// 로봇마다 갈라야 하는 토픽.
///
/// 상대 이름이라 네임스페이스 아래에서 저절로 풀리는 것도 있지만, 전부 절대
/// 이름으로 적는다. 해석 규칙에 기대지 않으면 어긋날 여지가 없다.
const Set<String> _topicKeys = {
  'scan_topic',
  'odom_topic',
  'speed_limit_topic',
  'topic',
};

/// 로봇별로 가르면 **안 되는** 토픽. 월드에 하나뿐인 것들이다.
const Set<String> _sharedTopics = {'/map', '/tf', '/tf_static', '/clock'};

/// 파일 전체에서 `키: 숫자` 를 찾는다. 처음 것만 쓴다. 없으면 null.
///
/// 벤더 파일에서 이 이름들이 유일해서 어느 블록에 있는지 따질 필요가 없다.
double? _numberOf(String yaml, String key) {
  final pattern = RegExp('^\\s*$key:\\s*(.*)\$', multiLine: true);
  final match = pattern.firstMatch(yaml);
  if (match == null) return null;
  final raw = match.group(1)!;
  final hash = raw.indexOf('#');
  return double.tryParse((hash >= 0 ? raw.substring(0, hash) : raw).trim());
}

/// `[0.25, 0.0, 1.5]` 의 첫 항. 그 모양이 아니면 null.
///
/// Nav2 의 속도 벡터는 `[x, y, theta]` 다. 차동 구동이라 y 는 늘 0 이고, 직진
/// 속도는 첫 항이다.
double? _firstOfVector(String value) {
  final text = value.trim();
  if (!text.startsWith('[') || !text.endsWith(']')) return null;
  final items = text.substring(1, text.length - 1).split(',');
  if (items.isEmpty) return null;
  return double.tryParse(items.first.trim());
}

/// 첫 항만 갈아 끼운 벡터. 나머지 항은 글자 그대로 둔다.
String _withFirst(String value, String first) {
  final text = value.trim();
  final items = text.substring(1, text.length - 1).split(',');
  return '[$first, ${items.skip(1).map((item) => item.trim()).join(', ')}]';
}

final RegExp _topLevelKey = RegExp(r'^([A-Za-z_][A-Za-z_0-9]*):\s*$');
final RegExp _setting = RegExp(r'^(\s*)([A-Za-z_][A-Za-z_0-9]*):\s*(.*)$');

/// 값에서 따옴표와 뒤따르는 주석을 떼어 낸다.
({String value, String comment}) _split(String raw) {
  var value = raw;
  var comment = '';
  // 주석은 따옴표 밖에 있을 때만 주석이다.
  var quoted = false;
  for (var i = 0; i < raw.length; i++) {
    if (raw[i] == '"' || raw[i] == "'") quoted = !quoted;
    if (raw[i] == '#' && !quoted) {
      value = raw.substring(0, i).trimRight();
      comment = raw.substring(i);
      break;
    }
  }
  return (value: value.trim(), comment: comment);
}

String _unquote(String value) {
  if (value.length >= 2 &&
      ((value.startsWith('"') && value.endsWith('"')) ||
          (value.startsWith("'") && value.endsWith("'")))) {
    return value.substring(1, value.length - 1);
  }
  return value;
}

String _requote(String original, String replacement) =>
    original.startsWith('"') || original.startsWith("'")
    ? '"$replacement"'
    : replacement;

/// [source] 를 [namespace] 로봇 한 대에 맞춰 다시 쓴다.
///
/// [initialX]·[initialY]·[initialYaw] 는 AMCL 이 처음 찍는 자리다. 로봇을 올린
/// 자리(RMF 월드 좌표)를 그대로 넣는다. 이것이 틀리면 AMCL 이 엉뚱한 데서
/// 시작해 라이다를 못 맞춘다.
/// 코스트맵 한 칸의 크기 [m]. 도착 반경의 바닥값을 여기서 잡는다.
const double nav2CostmapResolution = 0.05;

/// 벤더가 준 도착 반경 [m]. 사람 다니는 복도를 전제한 값이다.
const double vendorGoalTolerance = 0.25;

/// 출발 전 제자리 회전에 들어가는 문턱 [rad]. 약 45도.
///
/// 벤더 값은 0.35rad(20도)라, 경로가 조금만 꺾여도 멈춰 서서 다 돌고 출발한다.
/// 이 맵들은 Waypoint 간격이 0.3~0.8m 로 촘촘해 길이 자주 꺾이므로 그 문턱에
/// 늘 걸린다.
///
/// 45도를 넘겨야 제자리 회전을 쓴다. 그 아래는 돌면서 전진해 곡선으로
/// 빠져나간다.
const double rotateToHeadingMinAngle = 0.785;

/// 도착으로 치는 각도 오차 [rad]. 약 5도.
///
/// 벤더 값은 0.25rad(약 14도)다. 사람 다니는 복도에서 "대충 그쪽을 봤다" 면
/// 충분한 값이라 여태 문제가 없었다.
///
/// 픽업 자리는 다르다. 핑키는 수납함을 뒤에 달고 다니고, 팔이 그 수납함을
/// 집어야 한다. 수납함이 로봇 중심에서 30cm 쯤 뒤에 있으니 —
///
///     14도 어긋남 → 수납함이 옆으로 7.3cm
///      5도 어긋남 → 수납함이 옆으로 2.6cm
///
/// 7cm 는 팔이 헛집는 거리다.
///
/// 이 값은 **모든 목적지**에 걸린다. 목적지마다 다른 판정기를 쓰려면
/// 행동나무(BT) XML 을 따로 만들어야 하는데 그만한 이득이 없다 — 조여서
/// 손해 보는 것은 목적지마다 회전에 조금 더 쓰는 것뿐이다.
///
/// **아직 안 잰 것.** 이것은 "여기 들어오면 도착으로 친다" 는 판정 문턱이지,
/// 로봇이 실제로 **멎는** 자세가 아니다. 제자리 회전은
/// `rotate_to_heading_angular_vel: 1.0` rad/s 로 돌다가 판정이 나는 순간
/// 멈추므로, 멎는 자세는 문턱보다 조금 더 간다. 얼마나 더 가는지는 로봇을
/// 실제로 돌려 재 봐야 안다.
///
/// 그래서 워크셀의 관문(`DOCK_YAW_TOLERANCE`, 약 10도)은 여기에 묶지 않고
/// 일부러 헐겁게 두었다. 같은 값으로 묶으면 Nav2 가 도착이라고 놓아준 로봇을
/// 워크셀이 매번 거절해 멀쩡한 작업이 전부 실패한다.
const double dockYawTolerance = 0.087;

/// 이 맵에서 더 조일 수 없는 도착 반경 [m].
///
/// 코스트맵 한 칸이 0.05m 다. 그보다 촘촘히 요구하면 로봇이 영영 도착하지
/// 못하고 목표 주변을 맴돈다. 두 칸을 바닥으로 잡는다.
double minimumGoalTolerance({
  double costmapResolution = nav2CostmapResolution,
}) => costmapResolution * 2;

/// 맵 축척에서 뽑은 도착 반경 [m].
///
/// 이웃 Waypoint 까지 거리의 4분의 1이면 옆 Waypoint 의 도착 원과 겹치지
/// 않는다. 어느 지점에 섰는지가 분명해진다.
///
/// [minLaneSpacing] 은 레인으로 이어진 Waypoint 사이의 최소 거리다. 모르면
/// 벤더 기본값을 그대로 쓴다 — 함부로 조이면 도착을 못 한다.
double recommendedGoalTolerance({
  double? minLaneSpacing,
  double costmapResolution = nav2CostmapResolution,
}) {
  final floor = minimumGoalTolerance(costmapResolution: costmapResolution);
  if (minLaneSpacing == null || minLaneSpacing <= 0) return vendorGoalTolerance;
  final quarter = minLaneSpacing / 4;
  if (quarter < floor) return floor;
  if (quarter > vendorGoalTolerance) return vendorGoalTolerance;
  return quarter;
}

Nav2ParamsRewrite rewriteNav2Params({
  required String source,
  required String namespace,
  double? initialX,
  double? initialY,
  double? initialYaw,
  double? goalTolerance,
  // 목표 직진 속도 [m/s]. 주면 벤더 값을 덮어쓴다. RMF 쪽 한계와 같은 값을
  // 넣어야 배차 계산과 실제 주행이 어긋나지 않는다.
  double? linearVelocity,
}) {
  final ns = namespace.startsWith('/') ? namespace.substring(1) : namespace;
  final changes = <String>[];
  final warnings = <String>[];
  final out = <String>[];

  // 끼었나 판정에 쓰는 여유 시간. `required_movement_radius` 보다 먼저 나오지만
  // 그 순서에 기대지 않고 미리 훑는다 — 벤더 파일이 바뀌어 순서가 뒤집히면
  // 조용히 옛 값으로 계산하게 된다.
  final allowance = _numberOf(source, 'movement_time_allowance');
  final vendorRadius = _numberOf(source, 'required_movement_radius');

  /// 상대 이름이든 절대 이름이든 이 로봇 것으로 만든다.
  String namespaced(String name) {
    final bare = name.startsWith('/') ? name.substring(1) : name;
    return '/$ns/$bare';
  }

  final lines = source.split('\n');
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];

    // ① 맨 위 칸의 노드 이름. `amcl:` 은 `/amcl` 을 뜻하므로 그대로 두면
    //    `/pinky_01/amcl` 에 하나도 안 붙는다. 조용히 기본값으로 돈다.
    final top = _topLevelKey.firstMatch(line);
    if (top != null) {
      final name = top.group(1)!;
      out.add('/$ns/$name:');
      changes.add('$name → /$ns/$name');
      continue;
    }

    final setting = _setting.firstMatch(line);
    if (setting == null) {
      out.add(line);
      continue;
    }
    final indent = setting.group(1)!;
    final key = setting.group(2)!;
    final rest = setting.group(3)!;

    // ⓪ costmap 의 static_layer 는 지도를 제가 따로 구독한다. 벤더 파일에는 그
    //    토픽이 안 적혀 있어서 기본값 `map` 을 쓰는데, 네임스페이스 아래에서는
    //    `/pinky_01/map` 이 되어 아무것도 안 온다. 여기서 넣어 준다.
    if (key == 'plugin' &&
        _unquote(_split(rest).value).endsWith('StaticLayer')) {
      // 형제 키와 같은 칸에 둔다. 한 칸이라도 어긋나면 다른 항목이 된다.
      out
        ..add(line)
        ..add('${indent}map_topic: $nav2MapTopic');
      changes.add('static_layer 에 map_topic: $nav2MapTopic 을 넣었습니다');
      continue;
    }
    if (rest.isEmpty) {
      out.add(line);
      continue;
    }
    final parts = _split(rest);
    final bare = _unquote(parts.value);

    // ② AMCL 이 처음 찍는 자리. 벤더 파일은 `initial_pose: [0, 0, 0]` 이라고
    //    적어 두었는데, AMCL 은 `initial_pose.x/.y/.z/.yaw` 로 선언한다. 리스트는
    //    맞는 이름이 없어서 **조용히 버려진다.** 제대로 된 모양으로 다시 쓴다.
    if (key == 'initial_pose') {
      if (initialX == null || initialY == null) {
        out.add(line);
        warnings.add('initial_pose 를 채울 자리를 모릅니다. AMCL 이 원점에서 시작합니다.');
        continue;
      }
      out
        ..add('$indent$key:')
        ..add('$indent  x: ${initialX.toStringAsFixed(6)}')
        ..add('$indent  y: ${initialY.toStringAsFixed(6)}')
        ..add('$indent  z: 0.0')
        ..add('$indent  yaw: ${(initialYaw ?? 0).toStringAsFixed(6)}');
      changes.add(
        'initial_pose → x ${initialX.toStringAsFixed(3)} · '
        'y ${initialY.toStringAsFixed(3)} '
        '(벤더의 리스트 모양은 AMCL 이 못 읽어 버려집니다)',
      );
      continue;
    }

    // ③ 도착 반경. 벤더 값은 사람 다니는 복도를 전제한 0.25m 라, Waypoint 가
    //    0.33m 간격인 맵에서는 이웃 Waypoint 의 도착 원과 겹친다. 어느 지점에
    //    섰는지 구별이 안 된다.
    if (key == 'xy_goal_tolerance' && goalTolerance != null) {
      final before = double.tryParse(parts.value.trim());
      final after = goalTolerance.toStringAsFixed(3);
      out.add(
        '$indent$key: $after'
        '${parts.comment.isEmpty ? '' : ' ${parts.comment}'}',
      );
      if (before == null || (before - goalTolerance).abs() > 1e-9) {
        changes.add(
          'xy_goal_tolerance: ${parts.value.trim()} → $after '
          '(맵 축척에 맞춤)',
        );
      }
      continue;
    }

    // ③-1 출발 전 제자리 회전에 들어가는 문턱.
    //
    // 벤더 값은 0.35rad(20도)다. 경로 방향과 로봇이 보는 쪽이 20도만 어긋나도
    // **멈춰 서서 다 돌고 나서** 출발한다. `allow_reversing` 이 꺼져 있어
    // 후진으로 때울 수도 없다.
    //
    // 이 맵들은 Waypoint 간격이 0.3~0.8m 로 촘촘해서 길이 자주 꺾인다. 20도
    // 문턱이면 출발할 때마다 제자리 회전이 붙어 "왜 한 바퀴 돌고 가느냐" 가
    // 된다. 45도로 두면 어지간한 각도는 돌면서 전진해 곡선으로 빠져나가고,
    // 정말 뒤로 가야 할 때만 제자리 회전이 남는다.
    //
    // 로봇을 세워 두는 방향(`spawn_heading`)을 나가는 길에 맞추는 것이 먼저고,
    // 이것은 그 다음 방어선이다.
    if (key == 'rotate_to_heading_min_angle') {
      final before = double.tryParse(parts.value.trim());
      final after = rotateToHeadingMinAngle.toStringAsFixed(3);
      out.add(
        '$indent$key: $after'
        '${parts.comment.isEmpty ? '' : ' ${parts.comment}'}',
      );
      if (before == null || (before - rotateToHeadingMinAngle).abs() > 1e-9) {
        changes.add(
          'rotate_to_heading_min_angle: ${parts.value.trim()} → $after '
          '(약 45도. 출발할 때 제자리 회전을 줄인다)',
        );
      }
      continue;
    }

    // ③-1-1 도착으로 치는 각도 오차.
    //
    // 작업의 `go_to_place` 에 `orientation` 을 실으면 RMF 가 그 자세를 경로의
    // 마지막 목표로 넣고, 어댑터가 그대로 `NavigateToPose` 목표 자세에 담는다.
    // 그 자세에 들어왔는지 판정하는 것이 이 값이다 — 여기가 헐거우면 위에서
    // 아무리 정확한 각도를 보내도 그만큼 어긋난 채로 "도착" 이 된다.
    if (key == 'yaw_goal_tolerance') {
      final before = double.tryParse(parts.value.trim());
      final after = dockYawTolerance.toStringAsFixed(3);
      out.add(
        '$indent$key: $after'
        '${parts.comment.isEmpty ? '' : ' ${parts.comment}'}',
      );
      if (before == null || (before - dockYawTolerance).abs() > 1e-9) {
        changes.add(
          'yaw_goal_tolerance: ${parts.value.trim()} → $after '
          '(약 5도. 픽업 자리에서 수납함을 팔에 대야 한다)',
        );
      }
      continue;
    }

    // ③-2 주행 속도. 로봇을 실제로 움직이는 것은 이 값이다.
    //
    // RMF 쪽 한계(`rmf_fleet.limits`)는 **배차 시간 계산에만** 쓰인다. 거기에
    // 1.0 m/s 를 적어도 로봇은 벤더 파일의 0.2 m/s 로 간다. 둘이 어긋나면
    // RMF 는 멀쩡히 가는 로봇을 5배 늦었다고 보고 경로를 다시 짠다.
    //
    // 그래서 앱의 속도 하나로 양쪽을 다 쓴다. 벤더 파일은 그대로 두고 이
    // 로봇의 복사본만 고친다 — 어차피 프레임과 토픽도 이미 갈라 놓았다.
    if (linearVelocity != null) {
      // 두 곳을 함께 고쳐야 한다. desired_linear_vel 만 올리고
      // velocity_smoother 의 상한을 두면, 스무더가 그 위에서 잘라 버려 아무
      // 것도 안 빨라진다. 실제로 0.2 를 올려도 0.25 에서 막혔다.
      if (key == 'desired_linear_vel') {
        final after = linearVelocity.toStringAsFixed(3);
        out.add(
          '$indent$key: $after'
          '${parts.comment.isEmpty ? '' : ' ${parts.comment}'}',
        );
        changes.add('desired_linear_vel: ${parts.value.trim()} → $after');
        continue;
      }
      if (key == 'max_velocity') {
        final vector = _firstOfVector(parts.value);
        if (vector != null) {
          // 상한은 목표보다 살짝 위여야 한다. 딱 같게 두면 스무더가 목표에
          // 닿기 직전에 늘 걸린다.
          final ceiling = (linearVelocity * 1.25).toStringAsFixed(3);
          final replaced = _withFirst(parts.value, ceiling);
          out.add(
            '$indent$key: $replaced'
            '${parts.comment.isEmpty ? '' : ' ${parts.comment}'}',
          );
          changes.add(
            'velocity_smoother max_velocity: ${parts.value.trim()} → $replaced '
            '(목표 속도의 1.25배 상한)',
          );
          continue;
        }
        warnings.add(
          'velocity_smoother 의 max_velocity 가 `[x, y, theta]` 모양이 아니라 '
          '건드리지 않았습니다. 이 값이 목표 속도보다 낮으면 여기서 잘립니다.',
        );
      }

      // ③-3 "끼었나" 판정. 속도를 낮추면 이것도 같이 낮춰야 한다.
      //
      // SimpleProgressChecker 는 movement_time_allowance 초 동안
      // required_movement_radius 를 못 벗어나면 끼었다고 보고 제자리 회전과
      // 후진을 시킨다. 벤더 값 10초·0.5m 는 0.05m/s 이상을 전제한다.
      //
      // 속도만 낮추고 이것을 그대로 두면 **정상 주행이 실패로 판정된다.**
      // 0.02m/s 로 내렸더니 10초에 0.2m 밖에 못 가는데 0.5m 를 요구받아, 로봇이
      // 목적지로 가다 말고 되돌아오기를 되풀이했다. 그 헛회전이 odom 에 쌓여
      // AMCL 보정이 46도까지 벌어졌고, 화면마다 위치가 달라 보였다.
      if (key == 'required_movement_radius' &&
          allowance != null &&
          vendorRadius != null) {
        final radius = progressCheckerRadius(
          linearVelocity: linearVelocity,
          allowanceSeconds: allowance,
          vendorRadius: vendorRadius,
        );
        final after = radius.toStringAsFixed(3);
        out.add(
          '$indent$key: $after'
          '${parts.comment.isEmpty ? '' : ' ${parts.comment}'}',
        );
        if ((radius - vendorRadius).abs() > 1e-9) {
          changes.add(
            'required_movement_radius: ${parts.value.trim()} → $after '
            '(직진 속도 ${linearVelocity.toStringAsFixed(3)}m/s 에 맞춤)',
          );
        }
        final problem = progressCheckerWarning(
          linearVelocity: linearVelocity,
          allowanceSeconds: allowance,
          vendorRadius: vendorRadius,
        );
        if (problem != null) warnings.add(problem);
        continue;
      }
    }

    // ④ TF 프레임. 로봇마다 갈라야 한다.
    if (_frameKeys.contains(key) ||
        (_conditionalFrameKeys.contains(key) && bare == 'odom')) {
      if (bare == 'map') {
        out.add(line);
        continue;
      }
      final replaced = '$ns/$bare';
      out.add(
        '$indent$key: ${_requote(parts.value, replaced)}'
        '${parts.comment.isEmpty ? '' : ' ${parts.comment}'}',
      );
      changes.add('$key: $bare → $replaced');
      continue;
    }

    // `map` 프레임은 함께 쓴다. 같은 건물이니까.
    if (_conditionalFrameKeys.contains(key) && bare == 'map') {
      out.add(line);
      changes.add('$key: map — 함께 씁니다 (같은 건물)');
      continue;
    }

    // 지도는 로봇마다 가르지 않는다. 같은 건물이므로 하나를 함께 본다.
    if (key == 'map_topic') {
      out.add(
        '$indent$key: ${_requote(parts.value, nav2MapTopic)}'
        '${parts.comment.isEmpty ? '' : ' ${parts.comment}'}',
      );
      changes.add('map_topic: $bare → $nav2MapTopic (함께 씁니다)');
      continue;
    }

    // ④ 토픽. 절대 이름으로 이 로봇 것을 가리키게 한다.
    if (_topicKeys.contains(key)) {
      if (_sharedTopics.contains(bare)) {
        out.add(line);
        continue;
      }
      final replaced = namespaced(bare);
      out.add(
        '$indent$key: ${_requote(parts.value, replaced)}'
        '${parts.comment.isEmpty ? '' : ' ${parts.comment}'}',
      );
      changes.add('$key: $bare → $replaced');
      continue;
    }

    // ⑤ 손대지 않은 절대 이름. 벤더 파일이 바뀌면 여기 걸린다.
    if (bare.startsWith('/') &&
        !_sharedTopics.contains(bare) &&
        !bare.startsWith('/$ns/')) {
      warnings.add('${i + 1}번째 줄 `$key: $bare` 는 손대지 않았습니다.');
    }
    out.add(line);
  }

  return Nav2ParamsRewrite(
    yaml: out.join('\n'),
    changes: changes,
    warnings: warnings,
  );
}
