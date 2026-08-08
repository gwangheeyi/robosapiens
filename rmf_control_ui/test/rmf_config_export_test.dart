import 'package:flutter_test/flutter_test.dart';
import 'package:rmf_control_ui/rmf_config_export_io.dart';

/// 설정 파일을 디스크로 내보낼 때 쓰는 경로 규칙.
///
/// 로봇마다 제 디렉터리를 쓰므로 하위 경로를 허용해야 한다. 파일 이름은 로봇
/// ID 에서 만들어지고 로봇 ID 는 사람이 타자로 친다. `..` 이 섞이면 배포
/// 디렉터리 밖에 파일을 쓰게 된다.
void main() {
  group('내보낼 경로', () {
    test('로봇 디렉터리를 그대로 지킨다', () {
      expect(
        safeExportRelativePath('robots/PK-01/spawn.launch.xml'),
        'robots/PK-01/spawn.launch.xml',
      );
    });

    test('보통 파일은 그대로 둔다', () {
      expect(safeExportRelativePath('fleet.yaml'), 'fleet.yaml');
    });

    test('밖으로 나가려는 것은 막는다', () {
      for (final sneaky in [
        '../탈출.txt',
        'robots/../../탈출.txt',
        '..',
        'a/./../../b',
        r'..\탈출.txt',
      ]) {
        expect(
          safeExportRelativePath(sneaky),
          isNull,
          reason: '$sneaky 가 통과하면 배포 디렉터리 밖에 파일을 쓴다',
        );
      }
    });

    test('빈 이름은 만들지 않는다', () {
      expect(safeExportRelativePath(''), isNull);
      expect(safeExportRelativePath('   '), isNull);
      expect(safeExportRelativePath('///'), isNull);
    });

    test('앞뒤 슬래시는 걷어낸다', () {
      // 앞에 슬래시가 붙으면 절대 경로가 되어 루트에 쓰려 든다.
      expect(safeExportRelativePath('/etc/passwd'), 'etc/passwd');
    });

    test('맵 디렉터리 이름은 한 조각으로 만든다', () {
      expect(safeMapDirectoryName('gwanghee'), 'gwanghee');
      expect(safeMapDirectoryName('창고 A/B'), isNot(contains('/')));
      expect(safeMapDirectoryName(''), 'map');
    });
  });
}
