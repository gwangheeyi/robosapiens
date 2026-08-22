import 'dart:convert';
import 'dart:io';

import 'drive_learning_models.dart';

Map<String, String> _environment() => {
  ...Platform.environment,
  'MYSQL_PWD': Platform.environment['ROBOSAPIENS_DB_PASSWORD'] ?? 'robosapiens',
};
List<String> _arguments() => [
  '--batch',
  '--raw',
  '--skip-column-names',
  '--host=${Platform.environment['ROBOSAPIENS_DB_HOST'] ?? '127.0.0.1'}',
  '--port=${Platform.environment['ROBOSAPIENS_DB_PORT'] ?? '3306'}',
  '--user=${Platform.environment['ROBOSAPIENS_DB_USER'] ?? 'root'}',
  Platform.environment['ROBOSAPIENS_DB_NAME'] ?? 'robosapiens',
];
String _b64(String value) => base64Encode(utf8.encode(value));
String _date(DateTime value) => value
    .toUtc()
    .toIso8601String()
    .replaceFirst('T', ' ')
    .replaceFirst('Z', '');
Future<String> _query(String sql) async {
  final process = await Process.start(
    'mysql',
    _arguments(),
    environment: _environment(),
  );
  process.stdin.write(sql);
  await process.stdin.close();
  final output = process.stdout.transform(utf8.decoder).join();
  final error = process.stderr.transform(utf8.decoder).join();
  final code = await process.exitCode;
  final stderr = await error;
  if (code != 0) throw StateError('주행학습 DB 작업 실패: ${stderr.trim()}');
  return (await output).trim();
}

Future<void> saveDriveLearningSample(DriveLearningSample s) => _query('''
INSERT INTO drive_learning_samples
(map_name, task_id, task_name, robot_id, waypoint_name, drive_mode,
 started_at, finished_at, linear_velocity, linear_acceleration,
 angular_velocity, angular_acceleration, goal_tolerance,
 goal_x, goal_y, actual_x, actual_y, position_error,
 goal_heading, actual_heading, heading_error, success, nav2_status,
 failure_reason, error_log)
VALUES
(FROM_BASE64('${_b64(s.mapName)}'), FROM_BASE64('${_b64(s.taskId)}'),
 FROM_BASE64('${_b64(s.taskName)}'), FROM_BASE64('${_b64(s.robotId)}'),
 FROM_BASE64('${_b64(s.waypointName)}'), '${s.driveMode}',
 '${_date(s.startedAt)}', '${_date(s.finishedAt)}',
 ${s.linearVelocity}, ${s.linearAcceleration}, ${s.angularVelocity},
 ${s.angularAcceleration}, ${s.goalTolerance}, ${s.goalX}, ${s.goalY},
 ${s.actualX}, ${s.actualY}, ${s.positionError},
 ${s.goalHeading ?? 'NULL'}, ${s.actualHeading ?? 'NULL'}, ${s.headingError ?? 'NULL'},
 ${s.success ? 1 : 0}, ${s.nav2Status ?? 'NULL'},
 ${s.failureReason == null ? 'NULL' : "FROM_BASE64('${_b64(s.failureReason!)}')"},
 ${s.errorLog == null ? 'NULL' : "FROM_BASE64('${_b64(s.errorLog!)}')"});
''');

Future<List<DriveLearningSample>> loadDriveLearningSamples({
  String? mapName,
}) async {
  final where = mapName == null
      ? ''
      : "WHERE map_name=FROM_BASE64('${_b64(mapName)}')";
  final output = await _query('''
SELECT REPLACE(REPLACE(TO_BASE64(CAST(COALESCE(JSON_ARRAYAGG(JSON_OBJECT(
 'id',id,'mapName',map_name,'taskId',task_id,'taskName',task_name,
 'robotId',robot_id,'waypointName',waypoint_name,'driveMode',drive_mode,
 'startedAt',DATE_FORMAT(started_at,'%Y-%m-%dT%H:%i:%s.%fZ'),
 'finishedAt',DATE_FORMAT(finished_at,'%Y-%m-%dT%H:%i:%s.%fZ'),
 'linearVelocity',linear_velocity,'linearAcceleration',linear_acceleration,
 'angularVelocity',angular_velocity,'angularAcceleration',angular_acceleration,
 'goalTolerance',goal_tolerance,'goalX',goal_x,'goalY',goal_y,
 'actualX',actual_x,'actualY',actual_y,'positionError',position_error,
 'goalHeading',goal_heading,'actualHeading',actual_heading,
 'headingError',heading_error,'success',success,'nav2Status',nav2_status,
 'failureReason',failure_reason,'errorLog',error_log)),JSON_ARRAY()) AS CHAR)), '\n',''),'\r','')
FROM (SELECT * FROM drive_learning_samples $where ORDER BY finished_at DESC LIMIT 2000) s;
''');
  if (output.isEmpty || output == 'NULL') return const [];
  final decoded = utf8.decode(base64Decode(output.split('\n').last));
  return (jsonDecode(decoded) as List)
      .cast<Map<String, dynamic>>()
      .map(DriveLearningSample.fromJson)
      .toList();
}
