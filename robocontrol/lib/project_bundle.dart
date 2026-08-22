/// 프로젝트 하나를 기계 사이로 옮기는 꾸러미.
///
/// 원장은 MySQL 이다. 그래서 저장소를 `git pull` 한 다른 기계에는 **아무것도
/// 안 온다** — 스키마는 `db/schema.sql` 과 migration 이 자동으로 맞춰 주지만
/// (`database_migration_io.dart`), 그렇게 만들어진 DB 는 비어 있다. 도면도
/// 로봇 등록도 플릿 설정도 전부 이쪽 기계의 MySQL 안에만 있었다.
///
/// `robocontrol/project/*.rmfproject` 는 이 문제를 못 푼다. **지도만** 담기
/// 때문이다 — 도면·Waypoint·Lane·축척은 있지만 로봇 등록도 플릿 설정도 없다.
/// 그것만 옮기면 지도는 열리는데 로봇이 한 대도 없는 프로젝트가 된다. 게다가
/// 그 파일은 `.gitignore` 에 걸려 있어 애초에 push 되지도 않는다.
///
/// 그래서 프로젝트에 딸린 것을 **한 파일에 모아** git 에 올릴 수 있게 한다.
/// 여기서 하는 것은 꾸러미를 짜고 푸는 일뿐이고, MySQL 도 파일도 만지지 않는다.
///
/// ## 무엇이 들어가고 무엇이 안 들어가는가
///
/// 들어가는 것은 **프로젝트를 프로젝트이게 하는 것** 이다 — 지도, 로봇 등록,
/// 플릿 설정, 시뮬레이션 설정, policy 연결. 안 들어가는 것은 그날그날의
/// 운영 기록이다 — 작업·주문·재고·텔레메트리. 그것까지 옮기면 두 기계가 서로의
/// 작업 이력을 덮어쓴다.
///
/// Policy 는 **기본 정보만** 들어간다. 학습 결과 ZIP 은 수백 MB 라 git 에
/// 올리지 않으므로(`WorkcellPolicy.archiveMissing` 이 그것을 위한 표시다),
/// 받은 쪽에서는 다시 받아야 한다.
library;

/// 꾸러미 파일임을 밝히는 표시. 다른 JSON 을 열었을 때 조용히 넘어가지 않는다.
const String projectBundleFormat = 'robosapiens-project-bundle';

/// 지금 쓰는 꾸러미 판. 읽을 때 이 값만 받는다.
const int projectBundleVersion = 1;

/// 지도 부분이 달고 있어야 하는 표시. `.rmfproject` 와 같은 것이다.
const String projectBundleMapFormat = 'robosapiens-map-project';

/// 꾸러미 파일 이름. 프로젝트 이름은 사람이 타자로 치므로 걸러 낸다.
String projectBundleFileName(String mapName) {
  final normalized = mapName.trim().replaceAll(
    RegExp(r'[^a-zA-Z0-9가-힣_-]'),
    '_',
  );
  if (normalized.isEmpty) throw ArgumentError('프로젝트 이름이 비어 있습니다.');
  return '$normalized.rmfbundle';
}

/// 프로젝트 하나에 딸린 것 전부.
class ProjectBundle {
  const ProjectBundle({
    required this.mapName,
    required this.project,
    this.buildingYaml,
    this.buildingYamlName,
    this.fleetSettings,
    this.robots = const [],
    this.simulation,
    this.policies = const [],
  });

  /// 프로젝트 구분자. `map_projects.map_name` 과 같은 값이다.
  final String mapName;

  /// `.rmfproject` 와 같은 지도 payload. 도면 바이트까지 들어 있다.
  final Map<String, dynamic> project;

  /// 저장할 때 만들어 둔 Open-RMF building.yaml. 없을 수 있다.
  final String? buildingYaml;
  final String? buildingYamlName;

  /// 플릿 설정(`map_project_fleets.settings`).
  final Map<String, Object?>? fleetSettings;

  /// 로봇 등록(`map_project_robots`). spawn 좌표가 여기 있다.
  final List<Map<String, Object?>> robots;

  /// 시뮬레이션 실행 설정(`map_project_simulation_settings`).
  final Map<String, Object?>? simulation;

  /// Policy 기본 정보. ZIP 은 안 들어간다.
  final List<Map<String, Object?>> policies;

  Map<String, Object?> toJson() => {
    'format': projectBundleFormat,
    'version': projectBundleVersion,
    'mapName': mapName,
    'project': project,
    // 없는 것과 비어 있는 것은 다르다. 없으면 아예 안 적어서, 받는 쪽이 그
    // 부분을 건드리지 않게 한다.
    if (buildingYaml != null) 'buildingYaml': buildingYaml,
    if (buildingYamlName != null) 'buildingYamlName': buildingYamlName,
    if (fleetSettings != null || robots.isNotEmpty)
      'fleet': {
        if (fleetSettings != null) 'settings': fleetSettings,
        'robots': robots,
      },
    if (simulation != null) 'simulation': simulation,
    if (policies.isNotEmpty) 'policies': policies,
  };

  /// 꾸러미 JSON 을 읽는다. 무엇이 잘못됐는지까지 밝힌다 — "지원하지 않는
  /// 파일입니다" 만으로는 받은 쪽에서 무엇을 해야 할지 알 수 없다.
  static ProjectBundle parse(Map<String, dynamic> data) {
    final format = data['format'];
    if (format != projectBundleFormat) {
      throw FormatException(
        '프로젝트 꾸러미가 아닙니다(format: ${format ?? '없음'}). '
        '`$projectBundleFormat` 이어야 합니다.',
      );
    }
    final version = data['version'];
    if (version != projectBundleVersion) {
      throw FormatException(
        '이 앱이 읽을 수 없는 꾸러미 판입니다(version: ${version ?? '없음'}). '
        '이 앱은 v$projectBundleVersion 을 읽습니다 — 앱을 최신으로 올리세요.',
      );
    }
    final mapName = (data['mapName'] as String? ?? '').trim();
    if (mapName.isEmpty) {
      throw const FormatException('꾸러미에 프로젝트 이름이 없습니다.');
    }
    final project = data['project'];
    if (project is! Map<String, dynamic>) {
      throw const FormatException('꾸러미에 지도가 없습니다.');
    }
    if (project['format'] != projectBundleMapFormat) {
      throw FormatException(
        '꾸러미 안의 지도가 맵 프로젝트가 아닙니다'
        '(format: ${project['format'] ?? '없음'}).',
      );
    }
    final fleet = data['fleet'];
    return ProjectBundle(
      mapName: mapName,
      project: project,
      buildingYaml: data['buildingYaml'] as String?,
      buildingYamlName: data['buildingYamlName'] as String?,
      fleetSettings: fleet is Map<String, dynamic>
          ? _asMap(fleet['settings'])
          : null,
      robots: fleet is Map<String, dynamic>
          ? _asMapList(fleet['robots'])
          : const [],
      simulation: _asMap(data['simulation']),
      policies: _asMapList(data['policies']),
    );
  }

  static Map<String, Object?>? _asMap(Object? value) =>
      value is Map ? value.cast<String, Object?>() : null;

  static List<Map<String, Object?>> _asMapList(Object? value) => [
    if (value is List)
      for (final item in value)
        if (item is Map) item.cast<String, Object?>(),
  ];
}

/// 받는 쪽에 보여 줄 요약. 무엇이 들어오는지 **누르기 전에** 알아야 한다.
///
/// [exists] 는 같은 이름의 프로젝트가 이미 MySQL 에 있는지. 덮어쓰는 것이면
/// 그 말부터 한다 — 가져오기는 그 프로젝트의 지도와 로봇 등록을 통째로 바꾼다.
String describeProjectBundle(ProjectBundle bundle, {required bool exists}) {
  final policiesWithoutArchive = bundle.policies
      .where((policy) => (policy['archiveName'] as String? ?? '').isNotEmpty)
      .length;
  return [
    if (exists)
      '`${bundle.mapName}` 프로젝트가 이미 있습니다. 지도·로봇 등록·플릿 설정을 '
          '꾸러미의 것으로 **덮어씁니다.**'
    else
      '`${bundle.mapName}` 프로젝트를 새로 만듭니다.',
    '',
    '가져오는 것',
    '  · 지도(도면·Waypoint·Lane·축척)',
    '  · 로봇 등록 ${bundle.robots.length}대',
    if (bundle.fleetSettings != null) '  · 플릿 설정',
    if (bundle.simulation != null) '  · 시뮬레이션 실행 설정',
    if (bundle.policies.isNotEmpty)
      '  · Policy ${bundle.policies.length}개 (기본 정보만 · ZIP '
          '$policiesWithoutArchive개는 이 기계에서 다시 받아야 합니다)',
    '',
    '가져오지 않는 것: 작업·주문·재고·로봇 위치 기록. '
        '두 기계의 운영 기록이 서로를 덮어쓰지 않게 하려는 것입니다.',
  ].join('\n');
}
