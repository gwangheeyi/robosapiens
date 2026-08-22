/// 맵 관리가 좌표를 **RMF 월드 좌표(m)** 로 보여 주는지 지킨다.
///
/// 이 값이 `nav_graphs/0.yaml`, `robot.yaml` 의 `spawn_x/spawn_y`, Gazebo
/// `create -x -y`, AMCL `initial_pose`, RViz, 로그에 나오는 그 값이다. 화면만
/// 다른 좌표로 보여 주면, 어긋났을 때 두 숫자가 같은 자리를 가리키는지부터
/// 사람이 손으로 맞춰 봐야 한다.
///
/// 예전에는 바닥 왼쪽 아래를 원점으로 한 픽셀을 보여 줬다. 원점이 **바닥
/// 폴리곤의 경계**라, 바닥을 조금만 고쳐도 같은 자리의 숫자가 통째로 달라졌다.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:robocontrol/rmf_project_config.dart';

void main() {
  late String source;

  setUpAll(() => source = File('lib/main.dart').readAsStringSync());

  group('화면 표시', () {
    test('바닥 기준 좌표로는 더 이상 보여 주지 않는다', () {
      // 지워진 것까지 지킨다. 다시 들어오면 같은 혼동이 되살아난다.
      expect(source, isNot(contains('_floorCoordinate')));
      expect(source, isNot(contains('toFloor')));
      // 지도 위젯 안에도 같은 변환이 하나 더 있었다(`_imageToFloor`). 마우스를
      // 올렸을 때 뜨는 딱지가 그걸 썼다.
      expect(source, isNot(contains('_imageToFloor')));
    });

    test('마우스를 올렸을 때 뜨는 좌표도 RMF 다', () {
      // Waypoint 를 찍기 **전에** 그 자리가 어디인지 보는 값이다. 여기서 본
      // 숫자가 그대로 nav graph 와 robot.yaml 에 들어간다.
      final badge = source.indexOf('class _WaypointCoordinateBadge');
      expect(badge, greaterThanOrEqualTo(0));
      final body = source.substring(badge, badge + 3000);
      expect(body, contains('rmfWorldFromPixel('));
      // 벽까지 거리 두 줄은 좌표가 아니라 잰 길이다. 그대로 둔다.
      expect(body, contains('formatMapDistance('));
    });

    test('Waypoint 이름표가 RMF 좌표를 쓴다', () {
      expect(source, contains('String _waypointLabel(Offset point)'));
      expect(source, contains('final position = _pointText(point'));
    });

    test('맵 관리의 좌표는 한 곳도 빠짐없이 RMF 다', () {
      // 처음 고칠 때 세 곳을 빠뜨렸다 — 시나리오 자동 완성 실패 경고, 이름
      // 없는 Waypoint 이름표, 자리 배정 목록. 화면 한 곳만 픽셀로 남아도
      // 그 숫자를 nav graph 와 맞춰 보다 시간을 버린다.
      //
      // 사람에게 보여 주는 좌표는 전부 `_pointText` 를 지나야 한다. 날것으로
      // 찍는 자리가 새로 생기면 여기서 잡힌다.
      final raw = RegExp(
        r'\$\{[a-zA-Z.]*\.d[xy]\.toStringAsFixed',
      ).allMatches(source).map((m) => m.group(0)!).toList();

      // 남아도 되는 것 셋 —
      //   `_pointText`·두 `_point`·마우스 딱지의 "축척 없음" 갈래
      //     (px 라고 밝히므로 미터로 오해할 일이 없다)
      //   `spawnWorld` (이미 RMF 미터다)
      //   building.yaml 생성 (그 파일의 형식이 픽셀이다)
      final allowed = <String>{
        r'${point.dx.toStringAsFixed',
        r'${point.dy.toStringAsFixed',
        r'${world.dx.toStringAsFixed',
        r'${world.dy.toStringAsFixed',
        r'${spawnWorld.dx.toStringAsFixed',
        r'${spawnWorld.dy.toStringAsFixed',
        r'${imagePoint.dx.toStringAsFixed',
        r'${imagePoint.dy.toStringAsFixed',
      };
      expect(raw.toSet().difference(allowed), isEmpty);
    });

    test('축척이 없으면 미터인 척하지 않는다', () {
      // 축척을 안 쟀으면 옮길 수가 없다. 픽셀을 미터라고 적으면 그 숫자를
      // 그대로 spawn 에 넣게 된다 — 로봇이 건물 밖에 놓인다.
      expect(source, contains('px'));
      expect(source, contains('축척 없음'));
      expect(source, contains('축척을 재야 미터로 보입니다'));
    });
  });

  group('좌표 변환 자체', () {
    // 도면 픽셀 → RMF 월드. y 부호가 뒤집힌다.
    const scale = 0.0011568648414519475;

    test('충전1 픽셀이 nav graph 의 값과 같아진다', () {
      final world = rmfWorldFromPixel(1393.213, 619.922, scale);
      expect(world.x, closeTo(1.612, 0.001));
      expect(world.y, closeTo(-0.717, 0.001));
    });

    test('충전2 픽셀이 nav graph 의 값과 같아진다', () {
      final world = rmfWorldFromPixel(1394.524, 940.258, scale);
      expect(world.x, closeTo(1.613, 0.001));
      expect(world.y, closeTo(-1.088, 0.001));
    });

    test('건물 안은 y 가 음수다', () {
      // 픽셀 y 는 아래로 커지는데 RMF 는 위로 커진다. 부호를 안 뒤집으면
      // 로봇이 바닥 없는 자리에 놓여 끝없이 떨어진다.
      expect(rmfWorldFromPixel(1000, 500, scale).y, lessThan(0));
    });

    test('도면에서 위에 있는 자리가 y 가 더 크다', () {
      // 충전1(픽셀 y 620)이 충전2(픽셀 y 940)보다 위에 있다.
      final upper = rmfWorldFromPixel(1393.213, 619.922, scale);
      final lower = rmfWorldFromPixel(1394.524, 940.258, scale);
      expect(upper.y, greaterThan(lower.y));
    });
  });
}
