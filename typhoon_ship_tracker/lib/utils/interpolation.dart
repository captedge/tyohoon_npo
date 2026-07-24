import 'dart:math' as math;

import '../models/track_point.dart';

/// A latitude/longitude pair without a timestamp, used for interpolated
/// results and for distance calculations.
class LatLng {
  final double latitude;
  final double longitude;

  const LatLng(this.latitude, this.longitude);
}

/// Finds the position at [time] by linearly interpolating between the two
/// track points that straddle it.
///
/// - If [time] is before the first point, returns the first point's position.
/// - If [time] is after the last point, returns the last point's position.
/// - [points] must be sorted by time ascending and contain at least one point.
LatLng positionAt(List<TrackPoint> points, DateTime time) {
  assert(points.isNotEmpty, 'points must not be empty');

  if (points.length == 1 || time.isBefore(points.first.time)) {
    return LatLng(points.first.latitude, points.first.longitude);
  }
  if (!time.isBefore(points.last.time)) {
    return LatLng(points.last.latitude, points.last.longitude);
  }

  for (var i = 0; i < points.length - 1; i++) {
    final a = points[i];
    final b = points[i + 1];
    if (!time.isBefore(a.time) && !time.isAfter(b.time)) {
      final totalMs = b.time.difference(a.time).inMilliseconds;
      if (totalMs == 0) return LatLng(a.latitude, a.longitude);
      final elapsedMs = time.difference(a.time).inMilliseconds;
      final t = elapsedMs / totalMs;
      final lat = a.latitude + (b.latitude - a.latitude) * t;
      final lon = a.longitude + (b.longitude - a.longitude) * t;
      return LatLng(lat, lon);
    }
  }

  // Should not be reached given the guards above.
  return LatLng(points.last.latitude, points.last.longitude);
}

/// Distance in nautical miles between two positions using mid-latitude
/// sailing (中分緯度法), suitable for the limited regional scope of this
/// app (Hokkaido to the Philippines). Great-circle (Haversine) precision is
/// not required at this scale — see docs/devlog-map-design.md.
double distanceNm(LatLng a, LatLng b) {
  final deltaLatMin = (b.latitude - a.latitude) * 60;
  final deltaLonMin = (b.longitude - a.longitude) * 60;
  final midLatRad = ((a.latitude + b.latitude) / 2) * (math.pi / 180);
  final departureMin = deltaLonMin * math.cos(midLatRad);
  return math.sqrt(deltaLatMin * deltaLatMin + departureMin * departureMin);
}
