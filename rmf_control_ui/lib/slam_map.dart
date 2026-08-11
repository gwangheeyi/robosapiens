/// 로봇이 SLAM 으로 뜬 지도를 읽고, RMF 프레임에 맞출 원점을 계산한다.
///
/// 도면에서 만든 격자는 원점이 계산으로 RMF 월드에 맞는다. SLAM 지도는 다르다 —
/// 원점이 **로봇이 SLAM 을 시작한 자리**라서 RMF 원점(도면 그림 왼쪽 위)과 아무
/// 관계가 없다. 올린 그대로 띄우면 로봇이 `픽업1로 가라`는 명령을 받고 엉뚱한
/// 데로 간다. 그래서 올리는 것과 원점을 맞추는 것은 한 벌이다.
///
/// 파일을 읽고 쓰는 일은 `slam_map_store.dart` 가 한다. 여기 있는 것은 계산과
/// 파싱뿐이라 플랫폼을 가리지 않고 시험할 수 있다 — `occupancy_grid.dart` 와
/// `occupancy_grid_export.dart` 를 나눠 둔 것과 같은 이유다.
library;

import 'dart:typed_data';

/// `map_saver` 가 낸 지도 한 장.
class SlamMap {
  const SlamMap({
    required this.imageName,
    required this.width,
    required this.height,
    required this.resolution,
    required this.originX,
    required this.originY,
    required this.originYaw,
    required this.cells,
    this.occupiedThreshold = .65,
    this.freeThreshold = .196,
    this.negate = false,
  });

  /// yaml 의 `image:`. 같은 디렉터리의 `.pgm` 이름이다.
  final String imageName;

  final int width;
  final int height;

  /// 한 칸이 몇 미터인가.
  final double resolution;

  /// yaml 의 `origin:` 세 숫자 — **그림 왼쪽 아래 모서리**가 지도 프레임에서
  /// 어디인가. 원점의 위치가 아니라 그림이 놓인 자리다.
  final double originX;
  final double originY;
  final double originYaw;

  /// 회색조 픽셀. 첫 줄이 위쪽이다(PGM 과 같다).
  final Uint8List cells;

  final double occupiedThreshold;
  final double freeThreshold;
  final bool negate;

  /// 이 지도가 덮는 범위(m). 지금 원점 기준이다.
  ({double minX, double maxX, double minY, double maxY}) get bounds => (
    minX: originX,
    maxX: originX + width * resolution,
    minY: originY,
    maxY: originY + height * resolution,
  );

  /// [originX]·[originY] 만 갈아 끼운 사본.
  SlamMap withOrigin(double x, double y, [double? yaw]) => SlamMap(
    imageName: imageName,
    width: width,
    height: height,
    resolution: resolution,
    originX: x,
    originY: y,
    originYaw: yaw ?? originYaw,
    cells: cells,
    occupiedThreshold: occupiedThreshold,
    freeThreshold: freeThreshold,
    negate: negate,
  );

  /// `map_server` 가 읽는 yaml. 원점이 지금 값으로 나간다.
  String toYaml({String? note}) {
    final buffer = StringBuffer();
    if (note != null && note.trim().isNotEmpty) {
      for (final line in note.trim().split('\n')) {
        buffer.writeln('# $line');
      }
    }
    buffer
      ..writeln('image: $imageName')
      ..writeln('mode: trinary')
      ..writeln('resolution: ${resolution.toStringAsFixed(6)}')
      ..writeln(
        'origin: [${originX.toStringAsFixed(6)}, '
        '${originY.toStringAsFixed(6)}, '
        '${originYaw.toStringAsFixed(6)}]',
      )
      ..writeln('negate: ${negate ? 1 : 0}')
      ..writeln('occupied_thresh: $occupiedThreshold')
      ..writeln('free_thresh: $freeThreshold');
    return buffer.toString();
  }
}

/// `map_saver` 가 낸 yaml 을 읽는다.
///
/// YAML 파서를 들이지 않고 줄 단위로 훑는다 — 필요한 것은 여섯 줄뿐이고,
/// `nav2_speed_limits.dart` 가 벤더 파일을 읽는 방식과 같다.
///
/// 못 읽으면 [SlamMapParseError] 를 던진다. 조용히 0 을 채우면 안 된다 —
/// `resolution: 0` 이면 지도가 한 점으로 뭉개지고, 그 증상이 원인에서 멀다.
({
  String imageName,
  double resolution,
  double originX,
  double originY,
  double originYaw,
  bool negate,
  double occupiedThreshold,
  double freeThreshold,
})
parseSlamMapYaml(String text) {
  String? image;
  double? resolution;
  List<double>? origin;
  var negate = false;
  var occupied = .65;
  var free = .196;

  for (final raw in text.split('\n')) {
    final line = raw.trim();
    if (line.isEmpty || line.startsWith('#')) continue;
    final colon = line.indexOf(':');
    if (colon <= 0) continue;
    final key = line.substring(0, colon).trim();
    final value = line.substring(colon + 1).trim();
    switch (key) {
      case 'image':
        // 경로가 붙어 오면 파일 이름만 쓴다. 우리 디렉터리에 나란히 둔다.
        image = value.split(RegExp(r'[/\\]')).last.trim();
      case 'resolution':
        resolution = double.tryParse(value);
      case 'origin':
        final numbers = RegExp(r'-?\d+(\.\d+)?([eE][-+]?\d+)?')
            .allMatches(value)
            .map((m) => double.parse(m.group(0)!))
            .toList();
        if (numbers.length >= 2) origin = numbers;
      case 'negate':
        negate = value == '1' || value.toLowerCase() == 'true';
      case 'occupied_thresh':
        occupied = double.tryParse(value) ?? occupied;
      case 'free_thresh':
        free = double.tryParse(value) ?? free;
    }
  }

  if (image == null || image.isEmpty) {
    throw const SlamMapParseError('yaml 에 `image:` 가 없습니다.');
  }
  if (resolution == null || resolution <= 0) {
    throw const SlamMapParseError(
      'yaml 의 `resolution:` 을 읽지 못했습니다. 한 칸이 몇 미터인지 없으면 '
      '지도를 앉힐 수 없습니다.',
    );
  }
  if (origin == null) {
    throw const SlamMapParseError(
      'yaml 의 `origin:` 을 읽지 못했습니다. 숫자 셋이 있어야 합니다.',
    );
  }
  return (
    imageName: image,
    resolution: resolution,
    originX: origin[0],
    originY: origin[1],
    originYaw: origin.length > 2 ? origin[2] : 0,
    negate: negate,
    occupiedThreshold: occupied,
    freeThreshold: free,
  );
}

/// 회색조 PGM(P2/P5) 을 읽는다.
///
/// `map_saver` 는 P5(날바이트)를 낸다. P2(아스키)도 받는 이유는 손으로 만든
/// 지도나 다른 도구를 거친 지도가 그렇게 오는 경우가 있어서다.
({int width, int height, Uint8List cells}) parsePgm(Uint8List bytes) {
  final tokens = <String>[];
  var at = 0;
  // 머리글은 아스키다. 주석(`#`)은 줄 끝까지 버린다.
  while (tokens.length < 4 && at < bytes.length) {
    final char = bytes[at];
    if (char == 0x23) {
      while (at < bytes.length && bytes[at] != 0x0A) {
        at++;
      }
      continue;
    }
    if (char == 0x20 || char == 0x09 || char == 0x0A || char == 0x0D) {
      at++;
      continue;
    }
    final start = at;
    while (at < bytes.length) {
      final c = bytes[at];
      if (c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D || c == 0x23) break;
      at++;
    }
    tokens.add(String.fromCharCodes(bytes.sublist(start, at)));
  }
  if (tokens.length < 4) {
    throw const SlamMapParseError('PGM 머리글이 짧습니다.');
  }
  final magic = tokens[0];
  if (magic != 'P5' && magic != 'P2') {
    throw SlamMapParseError('회색조 PGM(P5·P2)이 아닙니다: $magic');
  }
  final width = int.tryParse(tokens[1]) ?? 0;
  final height = int.tryParse(tokens[2]) ?? 0;
  final maxValue = int.tryParse(tokens[3]) ?? 255;
  if (width <= 0 || height <= 0) {
    throw SlamMapParseError('PGM 크기를 읽지 못했습니다: $width×$height');
  }
  if (maxValue > 255) {
    throw SlamMapParseError(
      '한 칸이 2바이트인 PGM 은 아직 못 읽습니다(maxval $maxValue).',
    );
  }

  final count = width * height;
  final cells = Uint8List(count);
  if (magic == 'P5') {
    // 머리글 바로 뒤 공백 한 칸 다음부터 그림이다.
    if (at < bytes.length) at++;
    final available = bytes.length - at;
    if (available < count) {
      throw SlamMapParseError(
        'PGM 이 잘렸습니다. $count칸이 필요한데 $available칸만 있습니다.',
      );
    }
    cells.setRange(0, count, bytes, at);
  } else {
    var written = 0;
    var index = at;
    final buffer = StringBuffer();
    while (index < bytes.length && written < count) {
      final c = bytes[index];
      if (c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D) {
        if (buffer.isNotEmpty) {
          cells[written++] = int.tryParse(buffer.toString()) ?? 0;
          buffer.clear();
        }
      } else {
        buffer.writeCharCode(c);
      }
      index++;
    }
    if (buffer.isNotEmpty && written < count) {
      cells[written++] = int.tryParse(buffer.toString()) ?? 0;
    }
    if (written < count) {
      throw SlamMapParseError(
        'PGM 이 잘렸습니다. $count칸이 필요한데 $written칸만 있습니다.',
      );
    }
  }
  return (width: width, height: height, cells: cells);
}

/// 도면에서 만든 격자와 **범위를 맞춰** SLAM 지도의 원점을 계산한다.
///
/// 두 지도가 같은 건물을 그린 것이라면 덮는 범위의 가운데가 서로 같아야 한다.
/// 그 가정으로 원점을 옮겨 준다. 사람이 숫자를 처음부터 짚는 것보다 훨씬 가깝게
/// 시작할 수 있다.
///
/// **정답이 아니라 제안이다.** SLAM 지도는 복도 하나를 덜 돌았거나 더 돌았을 수
/// 있어서 범위가 다르다. 그래서 겹쳐 보고 사람이 마지막을 잡아야 한다.
({double x, double y}) suggestSlamOrigin({
  required int slamWidth,
  required int slamHeight,
  required double slamResolution,
  required double referenceMinX,
  required double referenceMinY,
  required double referenceWidthMeters,
  required double referenceHeightMeters,
}) {
  final slamWidthMeters = slamWidth * slamResolution;
  final slamHeightMeters = slamHeight * slamResolution;
  final referenceCenterX = referenceMinX + referenceWidthMeters / 2;
  final referenceCenterY = referenceMinY + referenceHeightMeters / 2;
  return (
    x: referenceCenterX - slamWidthMeters / 2,
    y: referenceCenterY - slamHeightMeters / 2,
  );
}

/// SLAM 지도를 읽지 못했을 때.
class SlamMapParseError implements Exception {
  const SlamMapParseError(this.message);
  final String message;

  @override
  String toString() => message;
}
