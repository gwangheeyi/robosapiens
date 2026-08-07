import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rmf_control_ui/task_store.dart';

void main() {
  final enabled = Platform.environment['RUN_MYSQL_INTEGRATION_TEST'] == '1';

  test(
    'MySQL에 작업 목록과 생성·수정·삭제 이력을 저장한다',
    () async {
      const created = [
        {
          'id': 'TASK-TEST-001',
          'name': '통합 테스트',
          'status': 'queued',
          'createdAt': '2026-08-07T12:00:00.000000',
          'steps': <Object?>[],
        },
      ];
      await saveTasks(jsonEncode(created));
      final loaded = jsonDecode((await loadSavedTasks())!) as List<dynamic>;
      expect(loaded.single['name'], '통합 테스트');

      final updated = [
        {...created.single, 'name': '수정된 작업', 'status': 'completed'},
      ];
      await saveTasks(jsonEncode(updated));
      await saveTasks('[]');

      final result = await Process.run(
        'mysql',
        [
          '--batch',
          '--skip-column-names',
          '--host=${Platform.environment['ROBOSAPIENS_DB_HOST']}',
          '--port=${Platform.environment['ROBOSAPIENS_DB_PORT']}',
          '--user=${Platform.environment['ROBOSAPIENS_DB_USER']}',
          Platform.environment['ROBOSAPIENS_DB_NAME']!,
          '--execute=SELECT GROUP_CONCAT(event_type ORDER BY id) FROM rmf_ui_task_history WHERE task_id = \'TASK-TEST-001\'',
        ],
        environment: {
          ...Platform.environment,
          'MYSQL_PWD': Platform.environment['ROBOSAPIENS_DB_PASSWORD']!,
        },
      );
      expect(result.exitCode, 0, reason: result.stderr as String?);
      expect(
        (result.stdout as String).trim(),
        'created,status_changed,deleted',
      );
    },
    skip: enabled ? false : 'MySQL 통합 테스트 환경이 설정되지 않았습니다.',
  );
}
