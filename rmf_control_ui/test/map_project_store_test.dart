import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rmf_control_ui/map_project_store.dart';

/// 지도 이름으로 프로젝트를 가르는 저장소의 계약을 확인한다.
///
/// 실제 MySQL이 필요하다. 다음처럼 켠다:
///   RUN_MYSQL_MAP_PROJECT_TEST=1 ROBOSAPIENS_DB_HOST=127.0.0.1 \
///   ROBOSAPIENS_DB_PORT=3306 ROBOSAPIENS_DB_USER=root \
///   ROBOSAPIENS_DB_NAME=robosapiens ROBOSAPIENS_DB_PASSWORD=robosapiens \
///   flutter test test/map_project_store_test.dart
void main() {
  final enabled = Platform.environment['RUN_MYSQL_MAP_PROJECT_TEST'] == '1';

  String payload(String mapName, int waypointCount) => jsonEncode({
    'format': 'robosapiens-map-project',
    'version': 2,
    'mapName': mapName,
    'drawing': {'name': '$mapName.png', 'extension': 'png', 'size': 12},
    'waypoints': [
      for (var i = 0; i < waypointCount; i++)
        {
          'point': [i * 3.0, i * 1.5],
          'name': i.isEven ? '홈${i ~/ 2 + 1}' : '대기${i ~/ 2 + 1}',
          'category': i.isEven ? '주차' : '대기',
        },
    ],
    'laneDirections': [
      for (var i = 0; i < waypointCount - 1; i++)
        {
          'start': [i * 3.0, i * 1.5],
          'end': [(i + 1) * 3.0, (i + 1) * 1.5],
          'direction': '양방향',
        },
    ],
  });

  group('맵 프로젝트 저장소', () {
    const first = '테스트 창고 A';
    const second = '테스트 창고 B';

    setUp(() async {
      await deleteMapProject(first);
      await deleteMapProject(second);
    });

    tearDown(() async {
      await deleteMapProject(first);
      await deleteMapProject(second);
    });

    test('지도 이름으로 프로젝트를 구분해 저장하고 되읽는다', () async {
      await saveMapProject(mapName: first, payloadJson: payload(first, 6));
      await saveMapProject(mapName: second, payloadJson: payload(second, 3));

      expect(await mapProjectExists(first), isTrue);
      expect(await mapProjectExists(second), isTrue);
      expect(await mapProjectExists('있을 리 없는 맵'), isFalse);

      final loaded = jsonDecode((await loadMapProject(first))!)
          as Map<String, dynamic>;
      expect(loaded['mapName'], first);
      expect((loaded['waypoints'] as List).length, 6);

      final summaries = {
        for (final project in await listMapProjects()) project.mapName: project,
      };
      expect(summaries[first]!.waypointCount, 6);
      expect(summaries[first]!.laneCount, 5);
      expect(summaries[second]!.waypointCount, 3);
      expect(summaries[second]!.laneCount, 2);
    });

    test('같은 이름으로 저장하면 새로 만들지 않고 그 프로젝트를 덮어쓴다', () async {
      await saveMapProject(mapName: first, payloadJson: payload(first, 6));
      final before = (await listMapProjects()).length;

      await saveMapProject(mapName: first, payloadJson: payload(first, 2));

      final after = await listMapProjects();
      expect(after.length, before, reason: '프로젝트 수가 늘면 안 된다');
      final updated = after.firstWhere((project) => project.mapName == first);
      // 조회용 사본은 증분이 아니라 통째로 다시 만든다. 줄어든 Waypoint 수가
      // 그대로 반영돼야 예전 지점이 남아 도는 일이 없다.
      expect(updated.waypointCount, 2);
      expect(updated.laneCount, 1);
    });

    test('삭제한 프로젝트는 목록과 조회에서 사라진다', () async {
      await saveMapProject(mapName: first, payloadJson: payload(first, 4));
      await saveMapProject(mapName: second, payloadJson: payload(second, 4));

      await deleteMapProject(first);

      expect(await mapProjectExists(first), isFalse);
      expect(await loadMapProject(first), isNull);
      expect(await mapProjectExists(second), isTrue, reason: '다른 프로젝트는 남는다');
    });
  }, skip: enabled ? false : 'MySQL 맵 프로젝트 테스트 환경이 설정되지 않았습니다.');
}
