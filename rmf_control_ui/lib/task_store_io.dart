import 'dart:convert';
import 'dart:io';

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
    throw StateError('MySQL 작업 실패: ${error.trim()}');
  }
  return output.trim();
}

Future<String?> loadSavedTasks() async {
  final output = await _query('''
CREATE TABLE IF NOT EXISTS rmf_ui_tasks (
  id VARCHAR(64) NOT NULL PRIMARY KEY,
  name VARCHAR(255) NOT NULL,
  status VARCHAR(32) NOT NULL,
  payload JSON NOT NULL,
  created_at DATETIME(6) NOT NULL,
  updated_at DATETIME(6) NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
CREATE TABLE IF NOT EXISTS rmf_ui_task_history (
  id BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY,
  task_id VARCHAR(64) NOT NULL,
  event_type VARCHAR(32) NOT NULL,
  payload JSON NOT NULL,
  recorded_at DATETIME(6) NOT NULL,
  KEY idx_rmf_ui_task_history_task (task_id, recorded_at),
  KEY idx_rmf_ui_task_history_at (recorded_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
SELECT COALESCE(JSON_ARRAYAGG(payload), JSON_ARRAY())
FROM rmf_ui_tasks;
''');
  return output.isEmpty ? '[]' : output.split('\n').last;
}

Future<void> saveTasks(String contents) async {
  final snapshot = base64Encode(utf8.encode(contents));
  await _query('''
SET @snapshot = CAST(CONVERT(FROM_BASE64('$snapshot') USING utf8mb4) AS JSON);
START TRANSACTION;

INSERT INTO rmf_ui_task_history (task_id, event_type, payload, recorded_at)
SELECT incoming.id, 'created', incoming.payload, NOW(6)
FROM JSON_TABLE(
  @snapshot,
  '\$[*]' COLUMNS (
    id VARCHAR(64) PATH '\$.id',
    payload JSON PATH '\$'
  )
) AS incoming
LEFT JOIN rmf_ui_tasks existing
  ON existing.id = (incoming.id COLLATE utf8mb4_unicode_ci)
WHERE existing.id IS NULL;

INSERT INTO rmf_ui_task_history (task_id, event_type, payload, recorded_at)
SELECT
  incoming.id,
  CASE
    WHEN JSON_UNQUOTE(JSON_EXTRACT(existing.payload, '\$.status')) <> incoming.status
      THEN 'status_changed'
    ELSE 'updated'
  END,
  incoming.payload,
  NOW(6)
FROM JSON_TABLE(
  @snapshot,
  '\$[*]' COLUMNS (
    id VARCHAR(64) PATH '\$.id',
    status VARCHAR(32) PATH '\$.status',
    payload JSON PATH '\$'
  )
) AS incoming
JOIN rmf_ui_tasks existing
  ON existing.id = (incoming.id COLLATE utf8mb4_unicode_ci)
WHERE NOT (existing.payload <=> incoming.payload);

INSERT INTO rmf_ui_task_history (task_id, event_type, payload, recorded_at)
SELECT existing.id, 'deleted', existing.payload, NOW(6)
FROM rmf_ui_tasks existing
LEFT JOIN JSON_TABLE(
  @snapshot,
  '\$[*]' COLUMNS (id VARCHAR(64) PATH '\$.id')
) AS incoming
  ON existing.id = (incoming.id COLLATE utf8mb4_unicode_ci)
WHERE incoming.id IS NULL;

INSERT INTO rmf_ui_tasks (id, name, status, payload, created_at, updated_at)
SELECT
  incoming.id,
  incoming.name,
  incoming.status,
  incoming.payload,
  STR_TO_DATE(incoming.created_at, '%Y-%m-%dT%H:%i:%s.%f'),
  NOW(6)
FROM JSON_TABLE(
  @snapshot,
  '\$[*]' COLUMNS (
    id VARCHAR(64) PATH '\$.id',
    name VARCHAR(255) PATH '\$.name',
    status VARCHAR(32) PATH '\$.status',
    created_at VARCHAR(64) PATH '\$.createdAt',
    payload JSON PATH '\$'
  )
) AS incoming
ON DUPLICATE KEY UPDATE
  name = VALUES(name),
  status = VALUES(status),
  payload = VALUES(payload),
  updated_at = NOW(6);

DELETE existing
FROM rmf_ui_tasks existing
LEFT JOIN JSON_TABLE(
  @snapshot,
  '\$[*]' COLUMNS (id VARCHAR(64) PATH '\$.id')
) AS incoming
  ON existing.id = (incoming.id COLLATE utf8mb4_unicode_ci)
WHERE incoming.id IS NULL;

COMMIT;
''');
}

Future<String> loadPendingOrders() async {
  final output = await _query('''
SELECT COALESCE(JSON_ARRAYAGG(order_data), JSON_ARRAY())
FROM (
  SELECT JSON_OBJECT(
    'id', orders.id,
    'customer', orders.customer,
    'urgency', orders.urgency,
    'zones', COALESCE(
      (
        SELECT JSON_ARRAYAGG(
          COALESCE(
            (
              SELECT lots.zone
              FROM lots
              WHERE lots.sku = order_lines.sku AND lots.qty > lots.reserved
              ORDER BY lots.expiry
              LIMIT 1
            ),
            'ambient'
          )
        )
        FROM order_lines
        WHERE order_lines.order_id = orders.id
      ),
      JSON_ARRAY('ambient')
    )
  ) AS order_data
  FROM orders
  WHERE expanded = 0
  ORDER BY created_at
  LIMIT 20
) pending;
''');
  return output.isEmpty ? '[]' : output.split('\n').last;
}

Future<void> markOrderDispatched(String orderId, String taskId) async {
  final encodedOrderId = base64Encode(utf8.encode(orderId));
  final encodedTaskId = base64Encode(utf8.encode(taskId));
  await _query('''
SET @order_id = CONVERT(FROM_BASE64('$encodedOrderId') USING utf8mb4);
SET @task_id = CONVERT(FROM_BASE64('$encodedTaskId') USING utf8mb4);
START TRANSACTION;
UPDATE orders SET expanded = 1 WHERE id = @order_id AND expanded = 0;
INSERT INTO events (
  at, severity, category, source, message, task_id, order_id
)
SELECT
  NOW(6), 'info', 'order_dispatch', 'rmf_control_ui',
  CONCAT('주문 자동 분류 및 작업 생성: ', @task_id), @task_id, @order_id
WHERE ROW_COUNT() > 0;
COMMIT;
''');
}
