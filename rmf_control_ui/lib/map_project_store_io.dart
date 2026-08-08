/// 맵 프로젝트를 MySQL `robosapiens` 에 지도 이름으로 구분해 담는다.
///
/// 한 관제가 여러 창고를 다루므로 프로젝트가 다르면 Waypoint·Lane·축척이 전부
/// 별개다. `map_projects.map_name` 이 그 구분자이며 UNIQUE 다 — 같은 이름으로
/// 저장하려 하면 앱이 먼저 [mapProjectExists] 로 확인해 덮어쓸지 다른 이름을
/// 쓸지 사용자에게 묻는다.
///
/// task_store_io.dart 와 같은 방식으로 `mysql` 클라이언트를 직접 부른다. 값은
/// 전부 base64 로 실어 보내고 받는다. 도면 이미지가 통째로 들어간 수백 KB짜리
/// JSON 이라 따옴표·역슬래시·개행 이스케이프를 손으로 맞추는 건 위험하다.
library;

import 'dart:convert';
import 'dart:io';

import 'map_project_models.dart';

Map<String, String> _mysqlEnvironment() {
  final password =
      Platform.environment['ROBOSAPIENS_DB_PASSWORD'] ?? 'robosapiens';
  return {...Platform.environment, 'MYSQL_PWD': password};
}

List<String> _mysqlArguments() => [
  '--batch',
  '--raw',
  '--skip-column-names',
  '--host=${Platform.environment['ROBOSAPIENS_DB_HOST'] ?? '127.0.0.1'}',
  '--port=${Platform.environment['ROBOSAPIENS_DB_PORT'] ?? '3306'}',
  '--user=${Platform.environment['ROBOSAPIENS_DB_USER'] ?? 'root'}',
  Platform.environment['ROBOSAPIENS_DB_NAME'] ?? 'robosapiens',
];

Future<String> _query(String sql) async {
  final process = await Process.start(
    'mysql',
    _mysqlArguments(),
    environment: _mysqlEnvironment(),
  );
  process.stdin.write(sql);
  await process.stdin.close();
  final outputFuture = process.stdout.transform(utf8.decoder).join();
  final errorFuture = process.stderr.transform(utf8.decoder).join();
  final exitCode = await process.exitCode;
  final output = await outputFuture;
  final error = await errorFuture;
  if (exitCode != 0) {
    throw StateError('맵 프로젝트 저장소 접근 실패: ${error.trim()}');
  }
  return output.trim();
}

String _encode(String value) => base64Encode(utf8.encode(value));

/// base64 로 감싸 돌려받은 마지막 줄을 원문으로 되돌린다.
///
/// MySQL 의 `TO_BASE64` 는 76자마다 개행을 넣으므로 그 개행을 SQL 쪽에서 이미
/// 걷어낸 상태로 받는다. 값이 없으면 빈 문자열이 온다.
String _decodeResult(String output) {
  if (output.isEmpty) return '';
  final line = output.split('\n').last.trim();
  if (line.isEmpty || line == 'NULL') return '';
  return utf8.decode(base64Decode(line));
}

/// 컬럼 값을 개행 없는 base64 한 줄로 뽑는 SQL 조각.
String _toBase64(String expression) =>
    "REPLACE(REPLACE(TO_BASE64($expression), '\\n', ''), '\\r', '')";

/// `map_name` 은 utf8mb4_unicode_ci 컬럼인데 사용자 변수는 접속 collation
/// (MySQL 8 기본 utf8mb4_0900_ai_ci)을 따라간다. 그대로 비교하면 illegal mix
/// of collations 로 죽으므로 비교할 때마다 컬럼 쪽에 맞춰 준다.
const String _nameParam = '(@map_name COLLATE utf8mb4_unicode_ci)';

/// 저장된 프로젝트 목록. 도면 바이트는 읽지 않는다.
Future<List<MapProjectSummary>> listMapProjects() async {
  final output = await _query('''
SELECT ${_toBase64('''CAST(
  COALESCE(
    JSON_ARRAYAGG(
      JSON_OBJECT(
        'mapName', map_name,
        'drawingName', drawing_name,
        'waypointCount', waypoint_count,
        'laneCount', lane_count,
        'updatedAt', DATE_FORMAT(updated_at, '%Y-%m-%dT%H:%i:%s.%f')
      )
    ),
    JSON_ARRAY()
  ) AS CHAR
)''')}
FROM map_projects;
''');
  final decoded = _decodeResult(output);
  if (decoded.isEmpty) return const [];
  final rows = jsonDecode(decoded) as List<dynamic>;
  final summaries = [
    for (final row in rows.cast<Map<String, dynamic>>())
      MapProjectSummary(
        mapName: row['mapName'] as String,
        drawingName: row['drawingName'] as String?,
        waypointCount: (row['waypointCount'] as num).toInt(),
        laneCount: (row['laneCount'] as num).toInt(),
        updatedAt:
            DateTime.tryParse(row['updatedAt'] as String? ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
      ),
  ];
  // JSON_ARRAYAGG 는 순서를 보장하지 않는다. 최근 저장 순으로 여기서 세운다.
  summaries.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  return summaries;
}

/// 같은 지도 이름의 프로젝트가 이미 있는지.
Future<bool> mapProjectExists(String mapName) async {
  final output = await _query('''
SET @map_name = CONVERT(FROM_BASE64('${_encode(mapName)}') USING utf8mb4);
SELECT COUNT(*) FROM map_projects WHERE map_name = $_nameParam;
''');
  final line = output.split('\n').last.trim();
  return (int.tryParse(line) ?? 0) > 0;
}

/// 프로젝트를 저장한다. 같은 이름이 있으면 그 프로젝트를 덮어쓴다.
///
/// 호출 전에 [mapProjectExists] 로 확인해 사용자 동의를 받아야 한다 — 이
/// 함수는 이미 결정이 끝났다고 보고 그대로 쓴다.
///
/// `payload` 는 편집 화면을 그대로 되살릴 수 있는 프로젝트 JSON 전체다.
/// 조회용 사본(map_project_waypoints / map_project_lanes)은 그 payload 에서
/// 다시 뽑아 채우므로 두 곳이 어긋날 수 없다.
Future<void> saveMapProject({
  required String mapName,
  required String payloadJson,
}) async {
  await _query('''
SET @map_name = CONVERT(FROM_BASE64('${_encode(mapName)}') USING utf8mb4);
SET @payload = CAST(
  CONVERT(FROM_BASE64('${_encode(payloadJson)}') USING utf8mb4) AS JSON
);
START TRANSACTION;

INSERT INTO map_projects (
  map_name, format_version, payload, drawing_name,
  waypoint_count, lane_count, created_at, updated_at
)
VALUES (
  @map_name,
  COALESCE(CAST(JSON_EXTRACT(@payload, '\$.version') AS UNSIGNED), 0),
  @payload,
  JSON_UNQUOTE(JSON_EXTRACT(@payload, '\$.drawing.name')),
  COALESCE(JSON_LENGTH(@payload, '\$.waypoints'), 0),
  COALESCE(JSON_LENGTH(@payload, '\$.laneDirections'), 0),
  NOW(6), NOW(6)
)
ON DUPLICATE KEY UPDATE
  format_version = VALUES(format_version),
  payload        = VALUES(payload),
  drawing_name   = VALUES(drawing_name),
  waypoint_count = VALUES(waypoint_count),
  lane_count     = VALUES(lane_count),
  updated_at     = NOW(6);

SET @project_id = (
  SELECT id FROM map_projects WHERE map_name = $_nameParam
);

-- 조회용 사본은 증분이 아니라 통째로 다시 만든다. Waypoint 를 지운 저장이
-- 반영되지 않는 사고를 없애려는 것이다.
DELETE FROM map_project_waypoints WHERE project_id = @project_id;
DELETE FROM map_project_lanes     WHERE project_id = @project_id;

INSERT INTO map_project_waypoints (project_id, seq, name, category, x, y)
SELECT @project_id, wp.seq, COALESCE(wp.name, ''), COALESCE(wp.category, '대기'),
       wp.x, wp.y
FROM JSON_TABLE(
  @payload,
  '\$.waypoints[*]' COLUMNS (
    seq      FOR ORDINALITY,
    name     VARCHAR(128) PATH '\$.name',
    category VARCHAR(32)  PATH '\$.category',
    x        DOUBLE       PATH '\$.point[0]',
    y        DOUBLE       PATH '\$.point[1]'
  )
) AS wp
WHERE wp.x IS NOT NULL AND wp.y IS NOT NULL;

INSERT INTO map_project_lanes (
  project_id, seq, start_x, start_y, end_x, end_y,
  direction, speed_limit, orientation, mutex_group
)
SELECT @project_id, ln.seq, ln.start_x, ln.start_y, ln.end_x, ln.end_y,
       COALESCE(ln.direction, '양방향'), ln.speed_limit, ln.orientation,
       ln.mutex_group
FROM JSON_TABLE(
  @payload,
  '\$.laneDirections[*]' COLUMNS (
    seq         FOR ORDINALITY,
    start_x     DOUBLE      PATH '\$.start[0]',
    start_y     DOUBLE      PATH '\$.start[1]',
    end_x       DOUBLE      PATH '\$.end[0]',
    end_y       DOUBLE      PATH '\$.end[1]',
    direction   VARCHAR(16) PATH '\$.direction',
    speed_limit DOUBLE      PATH '\$.speedLimit',
    orientation VARCHAR(16) PATH '\$.orientation',
    mutex_group VARCHAR(64) PATH '\$.mutex'
  )
) AS ln
WHERE ln.start_x IS NOT NULL AND ln.end_x IS NOT NULL;

COMMIT;
''');
}

/// 프로젝트 JSON 전체를 돌려준다. 없으면 null.
Future<String?> loadMapProject(String mapName) async {
  final output = await _query('''
SET @map_name = CONVERT(FROM_BASE64('${_encode(mapName)}') USING utf8mb4);
SELECT ${_toBase64('CAST(payload AS CHAR)')}
FROM map_projects WHERE map_name = $_nameParam;
''');
  final decoded = _decodeResult(output);
  return decoded.isEmpty ? null : decoded;
}

/// 프로젝트를 지운다. Waypoint·Lane 사본은 FK CASCADE 로 함께 사라진다.
Future<void> deleteMapProject(String mapName) async {
  await _query('''
SET @map_name = CONVERT(FROM_BASE64('${_encode(mapName)}') USING utf8mb4);
DELETE FROM map_projects WHERE map_name = $_nameParam;
''');
}
