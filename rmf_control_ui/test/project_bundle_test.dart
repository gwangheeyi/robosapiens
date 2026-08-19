/// 프로젝트 하나를 다른 기계로 옮기는 꾸러미.
///
/// 2026-08-19 에 겪은 일이다. 한쪽에서 작업하고 `git push` 한 뒤 다른 기계에서
/// `git pull` 했는데 아무것도 안 열렸다. 스키마는 문제가 아니었다 —
/// `db/schema.sql` 과 migration 이 git 에 있어 앱이 빈 DB 를 최신 스키마로
/// 알아서 만든다. **비어 있다는 것이 문제였다.** 도면도 로봇 등록도 플릿 설정도
/// 전부 저쪽 기계의 MySQL 안에만 있었고, `rmf_control_ui/project/*.rmfproject`
/// 는 지도만 담는 데다 `.gitignore` 에 걸려 push 되지도 않았다.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:rmf_control_ui/project_bundle.dart';

void main() {
  Map<String, dynamic> mapPayload() => {
    'format': 'robosapiens-map-project',
    'version': 2,
    'mapName': 'project1-ver2',
    'waypoints': [
      {'x': 1025.696, 'y': 1677.020, 'name': '픽업3', 'category': '픽업'},
    ],
  };

  ProjectBundle sample() => ProjectBundle(
    mapName: 'project1-ver2',
    project: mapPayload(),
    buildingYaml: 'levels:\n  L1: {}\n',
    buildingYamlName: 'project1-ver2.building.yaml',
    fleetSettings: const {'fleetName': 'pinky', 'footprintRadius': .1},
    robots: const [
      {
        'robotId': 'omx_01',
        'displayName': 'OMX-01',
        'model': 'omx_f',
        'kind': 'workcell',
        'chargerWaypoint': '설비3',
        'spawnX': 1.1699252329465406,
        'spawnY': -2.322449350034983,
      },
      {'robotId': 'pinky_01', 'displayName': 'PINKY', 'kind': 'mobile'},
    ],
    simulation: const {'backend': 'gazebo', 'rviz': true},
    policies: const [
      {'policyId': 'pick@1.0', 'name': 'pick', 'archiveName': 'policy.zip'},
    ],
  );

  group('꾸러미를 짜고 푼다', () {
    test('넣은 것이 그대로 나온다', () {
      final restored = ProjectBundle.parse(
        Map<String, dynamic>.from(sample().toJson()),
      );
      expect(restored.mapName, 'project1-ver2');
      expect(restored.project['mapName'], 'project1-ver2');
      expect(restored.buildingYamlName, 'project1-ver2.building.yaml');
      expect(restored.fleetSettings?['fleetName'], 'pinky');
      expect(restored.robots.length, 2);
      expect(restored.simulation?['backend'], 'gazebo');
      expect(restored.policies.single['policyId'], 'pick@1.0');
    });

    test('로봇 등록이 함께 간다 — 이것이 없어서 만든 기능이다', () {
      // `.rmfproject` 는 지도만 담아서, 옮긴 쪽에서 로봇이 한 대도 없었다.
      final restored = ProjectBundle.parse(
        Map<String, dynamic>.from(sample().toJson()),
      );
      final arm = restored.robots.firstWhere((r) => r['robotId'] == 'omx_01');
      expect(arm['spawnX'], 1.1699252329465406);
      expect(arm['spawnY'], -2.322449350034983);
      expect(arm['chargerWaypoint'], '설비3');
    });

    test('없는 것은 아예 안 적는다', () {
      // 비어 있는 것과 없는 것은 다르다. 없으면 받는 쪽이 그 부분을 안 건드린다.
      final bare = ProjectBundle(
        mapName: 'gwanghee',
        project: mapPayload(),
      ).toJson();
      expect(bare.containsKey('buildingYaml'), isFalse);
      expect(bare.containsKey('fleet'), isFalse);
      expect(bare.containsKey('simulation'), isFalse);
      expect(bare.containsKey('policies'), isFalse);
    });

    test('로봇만 있고 플릿 설정이 없어도 로봇은 실어 보낸다', () {
      final json = ProjectBundle(
        mapName: 'gwanghee',
        project: mapPayload(),
        robots: const [
          {'robotId': 'pinky_01'},
        ],
      ).toJson();
      expect(ProjectBundle.parse(json.cast<String, dynamic>()).robots.length, 1);
    });
  });

  group('아닌 파일을 열었을 때', () {
    test('꾸러미가 아니면 무엇이어야 하는지 밝힌다', () {
      expect(
        () => ProjectBundle.parse({'format': 'something-else', 'version': 1}),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('robosapiens-project-bundle'),
          ),
        ),
      );
    });

    test('판이 다르면 앱을 올리라고 말한다', () {
      final future = Map<String, dynamic>.from(sample().toJson())
        ..['version'] = projectBundleVersion + 1;
      expect(
        () => ProjectBundle.parse(future),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('앱을 최신으로'),
          ),
        ),
      );
    });

    test('이름 없는 꾸러미는 받지 않는다', () {
      final nameless = Map<String, dynamic>.from(sample().toJson())
        ..['mapName'] = '   ';
      expect(() => ProjectBundle.parse(nameless), throwsFormatException);
    });

    test('지도가 빠졌으면 그렇다고 한다', () {
      final noMap = Map<String, dynamic>.from(sample().toJson())
        ..remove('project');
      expect(
        () => ProjectBundle.parse(noMap),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('지도가 없습니다'),
          ),
        ),
      );
    });

    test('지도 자리에 엉뚱한 JSON 이 있으면 거른다', () {
      final wrong = Map<String, dynamic>.from(sample().toJson())
        ..['project'] = <String, dynamic>{'format': 'nav2-map'};
      expect(() => ProjectBundle.parse(wrong), throwsFormatException);
    });
  });

  group('파일 이름', () {
    test('한글 프로젝트 이름을 그대로 쓴다', () {
      expect(projectBundleFileName('창고1'), '창고1.rmfbundle');
    });

    test('경로가 될 수 있는 글자는 걷어낸다', () {
      // 점도 슬래시도 남기지 않는다. 꾸러미는 정해진 한 폴더에만 놓인다.
      expect(projectBundleFileName('../etc/passwd'), '___etc_passwd.rmfbundle');
    });

    test('빈 이름은 막는다', () {
      expect(() => projectBundleFileName('  '), throwsArgumentError);
    });
  });

  group('받는 쪽에 보여 줄 요약', () {
    test('덮어쓰는 것이면 그 말부터 한다', () {
      final text = describeProjectBundle(sample(), exists: true);
      expect(text, contains('덮어씁니다'));
      expect(text, contains('로봇 등록 2대'));
    });

    test('새로 만드는 것이면 그렇게 말한다', () {
      final text = describeProjectBundle(sample(), exists: false);
      expect(text, contains('새로 만듭니다'));
      expect(text, isNot(contains('덮어씁니다')));
    });

    test('안 가져오는 것을 반드시 밝힌다', () {
      // 작업·주문까지 옮기면 두 기계가 서로의 운영 기록을 덮어쓴다.
      expect(
        describeProjectBundle(sample(), exists: false),
        contains('가져오지 않는 것'),
      );
    });
  });
}
