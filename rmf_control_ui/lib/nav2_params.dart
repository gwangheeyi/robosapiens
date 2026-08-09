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
Nav2ParamsRewrite rewriteNav2Params({
  required String source,
  required String namespace,
  double? initialX,
  double? initialY,
  double? initialYaw,
}) {
  final ns = namespace.startsWith('/') ? namespace.substring(1) : namespace;
  final changes = <String>[];
  final warnings = <String>[];
  final out = <String>[];

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
    if (key == 'plugin' && _unquote(_split(rest).value).endsWith('StaticLayer')) {
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
        warnings.add(
          'initial_pose 를 채울 자리를 모릅니다. AMCL 이 원점에서 시작합니다.',
        );
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

    // ③ TF 프레임. 로봇마다 갈라야 한다.
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
