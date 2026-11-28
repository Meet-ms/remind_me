import 'package:flutter_test/flutter_test.dart';
import 'package:remind_me/models/condition.dart';
import 'package:remind_me/utils/geo.dart';

void main() {
  test('circleRing is a closed ring at the requested radius', () {
    const lat = 12.9716, lon = 77.5946;
    final ring = circleRing(lat, lon, 150);

    expect(ring.first, ring.last);
    for (final (pLat, pLon) in ring) {
      final d = LocationCondition.distanceMeters(lat, lon, pLat, pLon);
      expect(d, closeTo(150, 1));
    }
  });
}
