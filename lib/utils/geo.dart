import 'dart:math' as math;

const _earthRadiusMeters = 6371008.8;

/// Points on the ring [radiusMeters] around ([lat], [lon]), as (lat, lon)
/// pairs. The first point is repeated at the end so it forms a closed ring.
List<(double, double)> circleRing(
  double lat,
  double lon,
  double radiusMeters, {
  int steps = 64,
}) {
  final lat1 = lat * math.pi / 180;
  final lon1 = lon * math.pi / 180;
  final angular = radiusMeters / _earthRadiusMeters;
  final ring = <(double, double)>[];
  for (var i = 0; i <= steps; i++) {
    final bearing = 2 * math.pi * (i % steps) / steps;
    final lat2 = math.asin(
      math.sin(lat1) * math.cos(angular) +
          math.cos(lat1) * math.sin(angular) * math.cos(bearing),
    );
    final lon2 =
        lon1 +
        math.atan2(
          math.sin(bearing) * math.sin(angular) * math.cos(lat1),
          math.cos(angular) - math.sin(lat1) * math.sin(lat2),
        );
    ring.add((lat2 * 180 / math.pi, lon2 * 180 / math.pi));
  }
  return ring;
}
