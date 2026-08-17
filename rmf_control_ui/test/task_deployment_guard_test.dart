import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rmf_control_ui/deployed_map_service.dart';

void main() {
  test('로봇 작업 생성 전에 현재 프로젝트의 배포 여부를 확인한다', () {
    final source = File('lib/main.dart').readAsStringSync();
    final createTask = source.indexOf('Future<void> _createMockTask()');
    final editor = source.indexOf(
      'showMovableDialog<_TaskEditorResult>',
      createTask,
    );
    final guard = source.indexOf(
      'if (!_isDeployed && !loadedOperationalMap && !deployedOnDisk)',
      createTask,
    );

    expect(createTask, greaterThanOrEqualTo(0));
    expect(guard, greaterThan(createTask));
    expect(guard, lessThan(editor));
    expect(source, contains('먼저 맵을 배포하세요'));
    expect(source, contains('맵 관리에서 `배포하기`를 완료하세요.'));
  });

  test('배포 여부는 앱의 기억이 아니라 디스크에서도 본다', () {
    // `_isDeployed` 는 이 세션에서 방금 배포했다는 기억일 뿐이다. 앱을 다시
    // 켜거나 배포가 확인 단계에서만 실패해도 꺼져서, 멀쩡히 배포된 맵을 두고
    // `먼저 맵을 배포하세요` 가 떴다.
    final source = File('lib/main.dart').readAsStringSync();
    final createTask = source.indexOf('Future<void> _createMockTask()');
    final check = source.indexOf('deployedMapExists(', createTask);
    final guard = source.indexOf(
      'if (!_isDeployed && !loadedOperationalMap && !deployedOnDisk)',
      createTask,
    );

    // 막을지 정하기 **전에** 디스크를 본다. 뒤에서 보면 이미 팝업이 떠 있다.
    expect(check, greaterThan(createTask));
    expect(check, lessThan(guard));
  });

  group('deployedMapExists', () {
    late Directory root;
    late Directory previousCwd;

    // 임시 뿌리에서 돌린다. `_findProjectRoot` 는 `RMF_ROOT` 가 없으면 지금
    // 디렉터리에서 위로 올라가며 `rmf_maps` 를 찾으므로, 여기를 옮겨 두면
    // 이 저장소의 실제 배포물과 상관없이 시험할 수 있다.
    setUp(() {
      previousCwd = Directory.current;
      root = Directory.systemTemp.createTempSync('deployed-map-');
      Directory('${root.path}/rmf_maps').createSync(recursive: true);
      Directory.current = root;
    });

    tearDown(() {
      Directory.current = previousCwd;
      root.deleteSync(recursive: true);
    });

    /// 배포가 만드는 것만 놓는다. 실행 스크립트와 로봇 디렉터리는 내보내기가
    /// 만드는 것이라 배포 여부와 상관이 없다.
    void deploy(String mapName, {bool navGraph = true}) {
      final dir = Directory('${root.path}/rmf_maps/$mapName')
        ..createSync(recursive: true);
      File(
        '${dir.path}/$mapName.building.yaml',
      ).writeAsStringSync('name: "$mapName"\nlevels:\n  L1: {}\n');
      if (navGraph) {
        Directory('${dir.path}/nav_graphs').createSync();
        File('${dir.path}/nav_graphs/0.yaml').writeAsStringSync('vertices: []');
      }
    }

    test('건물 맵과 주행 그래프가 다 있으면 배포된 것이다', () {
      deploy('project1-ver2');
      expect(deployedMapExists('project1-ver2'), isTrue);
    });

    test('주행 그래프가 없으면 배포된 것이 아니다', () {
      // nav graph 가 없으면 RMF 가 길을 못 만든다. 건물 맵만 두고 배포됐다고
      // 하면 작업을 만들 수는 있는데 로봇이 아무 데도 못 간다.
      deploy('project1-ver2', navGraph: false);
      expect(deployedMapExists('project1-ver2'), isFalse);
    });

    test('없는 맵은 false 다', () {
      deploy('project1-ver2');
      expect(deployedMapExists('project2'), isFalse);
    });

    test('빈 이름은 디스크를 보지 않고 false 다', () {
      expect(deployedMapExists('   '), isFalse);
    });
  });
}
