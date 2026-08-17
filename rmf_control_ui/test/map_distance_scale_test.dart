import 'package:flutter_test/flutter_test.dart';
import 'package:rmf_control_ui/map_distance_scale.dart';

void main() {
  group('formatMapDistance', () {
    test('uses the Measurement meters-per-pixel scale', () {
      expect(formatMapDistance(500, 0.02), '10.00 m');
    });

    test('labels uncalibrated distances as pixels', () {
      expect(formatMapDistance(500, null), '500.0 px');
      expect(formatMapDistance(500, 0), '500.0 px');
      expect(formatMapDistance(500, double.nan), '500.0 px');
    });
  });
}
