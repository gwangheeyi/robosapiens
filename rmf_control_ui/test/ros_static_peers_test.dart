/// 앱이 띄우는 `ros2` 자식이 `ROS_STATIC_PEERS` 를 물려받는지 지킨다.
///
/// 로봇이 다른 기계에 있으면 이 값 없이는 토픽을 못 찾는다. 그러면 값이 안 오고,
/// `effectiveDataSource` 가 멀쩡한 실물 로봇을 Mock 으로 떨어뜨린다.
///
/// 실측(2026-08-17) — 백엔드는 실행 스크립트에 값을 줘서 붙었는데 앱은 안 줘서
/// 못 붙었다. 그래서 **RViz(백엔드가 띄운 것)에는 로봇이 보이는데 앱에서는
/// Mock** 인 상태가 됐다. 같은 명령을 값만 빼고 돌려 보면 이렇게 갈린다:
///
///     피어 없음 → WARNING: topic [/pinky_01/odom] does not appear to be
///                 published yet · Could not determine the type
///     피어 있음 → 토픽 형식을 찾아 구독까지 간다
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('셸 한 줄', () {
    late String source;
    setUpAll(
      () => source = File('lib/ros_static_peers_io.dart').readAsStringSync(),
    );

    test('값이 없으면 아무것도 안 내보낸다', () {
      // 빈 값을 내보내면 rmw 가 빈 피어를 하나 읽고 경고를 낸다.
      expect(source, contains("if (peers == null || peers.isEmpty) return '';"));
    });

    test('작은따옴표로 감싼다', () {
      // 피어는 `;` 로 나눈다. 안 감싸면 셸이 그 자리에서 명령을 끊는다.
      expect(source, contains('_shellQuote(peers)'));
      expect(source, contains(r"""'${value.replaceAll("'", r"'\''")}'"""));
    });
  });

  group('부르는 쪽', () {
    test('ros2 를 띄우는 세 곳이 모두 물려준다', () {
      // 한 곳만 빠져도 그 경로만 조용히 Mock 으로 떨어진다.
      for (final path in const [
        'lib/robot_telemetry_bridge_io.dart',
        'lib/rmf_task_bridge_io.dart',
        'lib/rmf_runtime_service_io.dart',
      ]) {
        final source = File(path).readAsStringSync();
        expect(
          source,
          contains("import 'ros_static_peers_io.dart';"),
          reason: '$path 가 안 가져옵니다',
        );
        expect(
          source,
          contains(r"'${rosStaticPeersExport()}'"),
          reason: '$path 가 자식에게 안 물려줍니다',
        );
      }
    });

    test('로봇 위치를 읽는 곳이 특히 그렇다', () {
      // `isLive` 가 이 피드의 값으로 판단한다 — 여기가 비면 Mock 이 된다.
      final source = File(
        'lib/robot_telemetry_bridge_io.dart',
      ).readAsStringSync();
      final start = source.indexOf('String _withRosEnvironment(');
      expect(start, greaterThanOrEqualTo(0));
      final body = source.substring(start, source.indexOf('\n}\n', start));
      expect(body, contains('rosStaticPeersExport()'));
      // 도메인도 함께 넘어가야 한다. 둘 중 하나만 있으면 여전히 못 찾는다.
      expect(body, contains('export ROS_DOMAIN_ID='));
    });
  });
}
