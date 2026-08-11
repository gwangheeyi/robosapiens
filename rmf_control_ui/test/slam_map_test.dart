import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:rmf_control_ui/slam_map.dart';

/// SLAM 지도를 읽고 원점을 계산하는 부분.
///
/// 도면에서 만든 격자는 원점이 계산으로 RMF 월드에 맞는다. SLAM 지도는 원점이
/// **로봇이 SLAM 을 시작한 자리**라 아무 관계가 없다. 여기가 틀리면 로봇이
/// `픽업1로 가라`는 명령을 받고 엉뚱한 데로 간다.
void main() {
  group('map_saver yaml 읽기', () {
    test('실제 map_saver 출력을 읽는다', () {
      // nav2 map_saver_cli 가 내는 그대로.
      const yaml = '''
image: my_map.pgm
mode: trinary
resolution: 0.05
origin: [-1.24, -3.87, 0]
negate: 0
occupied_thresh: 0.65
free_thresh: 0.25
''';
      final header = parseSlamMapYaml(yaml);
      expect(header.imageName, 'my_map.pgm');
      expect(header.resolution, .05);
      expect(header.originX, -1.24);
      expect(header.originY, -3.87);
      expect(header.originYaw, 0);
      expect(header.negate, isFalse);
      expect(header.freeThreshold, .25);
    });

    test('경로가 붙어 와도 파일 이름만 쓴다', () {
      // 우리 디렉터리에 나란히 두므로 남의 경로를 따라가면 안 된다.
      final header = parseSlamMapYaml(
        'image: /home/gyi/maps/my_map.pgm\nresolution: 0.05\n'
        'origin: [0, 0, 0]\n',
      );
      expect(header.imageName, 'my_map.pgm');
    });

    test('주석과 빈 줄을 건너뛴다', () {
      final header = parseSlamMapYaml(
        '# 손으로 적어 둔 메모\n\nimage: a.pgm\n'
        '  resolution: 0.02  \norigin: [1.5, -2.5, 0.75]\n',
      );
      expect(header.imageName, 'a.pgm');
      expect(header.resolution, .02);
      expect(header.originYaw, .75);
    });

    test('지수 표기도 읽는다', () {
      final header = parseSlamMapYaml(
        'image: a.pgm\nresolution: 5e-2\norigin: [-1.2e1, 3.4e-1, 0]\n',
      );
      expect(header.resolution, .05);
      expect(header.originX, -12);
      expect(header.originY, .34);
    });

    test('resolution 이 없으면 조용히 0 을 채우지 않고 던진다', () {
      // 0 이면 지도가 한 점으로 뭉개지고, 그 증상이 원인에서 멀다.
      expect(
        () => parseSlamMapYaml('image: a.pgm\norigin: [0, 0, 0]\n'),
        throwsA(isA<SlamMapParseError>()),
      );
      expect(
        () => parseSlamMapYaml(
          'image: a.pgm\nresolution: 0\norigin: [0, 0, 0]\n',
        ),
        throwsA(isA<SlamMapParseError>()),
      );
    });

    test('origin 이나 image 가 없으면 던진다', () {
      expect(
        () => parseSlamMapYaml('image: a.pgm\nresolution: 0.05\n'),
        throwsA(isA<SlamMapParseError>()),
      );
      expect(
        () => parseSlamMapYaml('resolution: 0.05\norigin: [0, 0, 0]\n'),
        throwsA(isA<SlamMapParseError>()),
      );
    });
  });

  group('PGM 읽기', () {
    test('P5 날바이트를 읽는다', () {
      final bytes = Uint8List.fromList([
        ...'P5\n3 2\n255\n'.codeUnits,
        0, 254, 205, //
        205, 254, 0,
      ]);
      final pgm = parsePgm(bytes);
      expect(pgm.width, 3);
      expect(pgm.height, 2);
      expect(pgm.cells, [0, 254, 205, 205, 254, 0]);
    });

    test('머리글 주석을 건너뛴다', () {
      // map_saver 는 안 넣지만 다른 도구를 거치면 붙어 온다.
      final bytes = Uint8List.fromList([
        ...'P5\n# 어디서 만든 지도인가\n2 1\n255\n'.codeUnits,
        7, 9,
      ]);
      final pgm = parsePgm(bytes);
      expect(pgm.width, 2);
      expect(pgm.cells, [7, 9]);
    });

    test('P2 아스키도 읽는다', () {
      final bytes = Uint8List.fromList(
        'P2\n2 2\n255\n0 254\n205 100\n'.codeUnits,
      );
      final pgm = parsePgm(bytes);
      expect(pgm.cells, [0, 254, 205, 100]);
    });

    test('잘린 파일은 조용히 넘기지 않는다', () {
      final bytes = Uint8List.fromList([
        ...'P5\n10 10\n255\n'.codeUnits,
        1, 2, 3,
      ]);
      expect(() => parsePgm(bytes), throwsA(isA<SlamMapParseError>()));
    });

    test('회색조가 아니면 던진다', () {
      final bytes = Uint8List.fromList('P6\n2 2\n255\n'.codeUnits);
      expect(() => parsePgm(bytes), throwsA(isA<SlamMapParseError>()));
    });

    test('한 칸 2바이트는 아직 못 읽는다고 밝힌다', () {
      final bytes = Uint8List.fromList([
        ...'P5\n2 1\n65535\n'.codeUnits,
        0, 0, 0, 0,
      ]);
      expect(() => parsePgm(bytes), throwsA(isA<SlamMapParseError>()));
    });
  });

  group('원점 제안', () {
    test('두 지도의 가운데를 맞춘다', () {
      // 도면 격자: x 0~4, y −3~0 (가운데 2, −1.5)
      final origin = suggestSlamOrigin(
        slamWidth: 100,
        slamHeight: 100,
        slamResolution: .02, // 2m × 2m
        referenceMinX: 0,
        referenceMinY: -3,
        referenceWidthMeters: 4,
        referenceHeightMeters: 3,
      );
      // SLAM 지도가 2×2m 이므로 가운데를 맞추면 왼쪽 아래는 (2−1, −1.5−1).
      expect(origin.x, closeTo(1, 1e-9));
      expect(origin.y, closeTo(-2.5, 1e-9));
    });

    test('같은 크기면 도면 격자와 같은 자리에 앉는다', () {
      final origin = suggestSlamOrigin(
        slamWidth: 200,
        slamHeight: 150,
        slamResolution: .02, // 4m × 3m — 도면과 같다
        referenceMinX: -.5,
        referenceMinY: -3.25,
        referenceWidthMeters: 4,
        referenceHeightMeters: 3,
      );
      expect(origin.x, closeTo(-.5, 1e-9));
      expect(origin.y, closeTo(-3.25, 1e-9));
    });
  });

  group('yaml 다시 쓰기', () {
    test('원점만 갈아 끼우고 나머지는 지킨다', () {
      final map = SlamMap(
        imageName: 'a_slam.pgm',
        width: 4,
        height: 3,
        resolution: .05,
        originX: -1.24,
        originY: -3.87,
        originYaw: 0,
        cells: Uint8List(12),
        freeThreshold: .25,
        negate: true,
      );
      final moved = map.withOrigin(1.5, -2.5);
      expect(moved.originX, 1.5);
      expect(moved.originY, -2.5);
      expect(moved.resolution, .05, reason: '한 칸 크기는 안 바뀐다');
      expect(moved.cells.length, 12, reason: '그림은 그대로다');

      final yaml = moved.toYaml(note: '원점을 사람이 맞췄다');
      expect(yaml, contains('# 원점을 사람이 맞췄다'));
      expect(yaml, contains('image: a_slam.pgm'));
      expect(yaml, contains('origin: [1.500000, -2.500000, 0.000000]'));
      expect(yaml, contains('negate: 1'));
      expect(yaml, contains('free_thresh: 0.25'));
    });

    test('다시 읽으면 같은 값이 나온다', () {
      final map = SlamMap(
        imageName: 'a_slam.pgm',
        width: 2,
        height: 2,
        resolution: .0213,
        originX: -.486372,
        originY: -3.241447,
        originYaw: .5,
        cells: Uint8List(4),
      );
      final again = parseSlamMapYaml(map.toYaml());
      expect(again.imageName, 'a_slam.pgm');
      expect(again.resolution, closeTo(.0213, 1e-6));
      expect(again.originX, closeTo(-.486372, 1e-6));
      expect(again.originY, closeTo(-3.241447, 1e-6));
      expect(again.originYaw, closeTo(.5, 1e-6));
    });
  });

  group('덮는 범위', () {
    test('원점에서 칸 수만큼 뻗는다', () {
      final map = SlamMap(
        imageName: 'a.pgm',
        width: 100,
        height: 50,
        resolution: .05,
        originX: -1,
        originY: -2,
        originYaw: 0,
        cells: Uint8List(5000),
      );
      final b = map.bounds;
      expect(b.minX, -1);
      expect(b.maxX, closeTo(4, 1e-9)); // -1 + 100×0.05
      expect(b.minY, -2);
      expect(b.maxY, closeTo(.5, 1e-9)); // -2 + 50×0.05
    });
  });
}
