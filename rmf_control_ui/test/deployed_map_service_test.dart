/// 배포한 맵을 목록에서 골라 다시 불러올 수 있는지 지킨다.
///
/// 이 시험은 `rmf_maps/` 에 실제로 깔린 것을 읽는다. 그래서 **어느 맵 하나를
/// 이름으로 짚으면 안 된다** — 예전에는 `robosapiens` 를 짚어 두었는데 그 맵이
/// 저장소에서 빠지자, 불러오기는 멀쩡한데 시험만 깨졌다. 고칠 것이 없는 실패는
/// 사람이 곧 무시하게 되고, 그러면 진짜 깨졌을 때도 안 본다.
///
/// 그래서 이름 대신 **불러올 수 있는 맵이 하나라도 있는가** 를 본다.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:rmf_control_ui/deployed_map_service.dart';

void main() {
  test('배포 맵 목록에서 골라 도면과 nav graph 를 되읽는다', () async {
    final maps = await listDeployedMaps();
    expect(maps, isNotEmpty, reason: 'rmf_maps 에 배포된 맵이 하나도 없다');

    // 도면 이미지가 없는 맵도 목록에는 오른다(`warehouse` 가 그렇다). 그것은
    // 불러오기의 잘못이 아니므로 다음 맵으로 넘어간다.
    DeployedMapData? loaded;
    final failures = <String>[];
    for (final summary in maps.where((map) => map.hasNavGraph)) {
      try {
        loaded = await loadDeployedMap(summary);
        break;
      } catch (error) {
        failures.add('${summary.name}: $error');
      }
    }

    expect(
      loaded,
      isNotNull,
      reason: '불러올 수 있는 맵이 하나도 없다\n${failures.join('\n')}',
    );
    // 도면·좌표·자리가 다 살아 와야 화면에 그릴 수 있다.
    expect(loaded!.imageName, endsWith('.png'));
    expect(loaded.imageBytes, isNotEmpty);
    expect(loaded.imageSize.width, greaterThan(0));
    expect(loaded.imageSize.height, greaterThan(0));
    expect(loaded.lanes, isNotEmpty);
    expect(loaded.waypoints, isNotEmpty);
  });
}
