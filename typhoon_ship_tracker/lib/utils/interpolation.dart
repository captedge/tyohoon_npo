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

/// Splits [points] into the portion already sailed/tracked through by
/// [time] ("past") and the portion still ahead ("future") — used to draw
/// the already-passed track as a solid line and the not-yet-reached planned
/// course as a dotted line (2026-08-03 request: "通過後の軌跡は実線に、通過
/// 前の予定針路は点線に"). Both halves include the interpolated position at
/// [time] as their shared boundary point, so the two line segments meet
/// with no visible gap.
///
/// - If [time] is at or before the first point, nothing has been passed yet:
///   `past` is just the first point, `future` is the whole track.
/// - If [time] is at or after the last point, everything has been passed:
///   `past` is the whole track, `future` is just the last point.
/// - [points] must be sorted by time ascending; may be empty (both empty).
({List<LatLng> past, List<LatLng> future}) splitTrackAtTime(
  List<TrackPoint> points,
  DateTime time,
) {
  if (points.isEmpty) return (past: const <LatLng>[], future: const <LatLng>[]);
  final all = [for (final p in points) LatLng(p.latitude, p.longitude)];
  if (points.length == 1) return (past: all, future: all);

  if (!time.isAfter(points.first.time)) {
    return (past: [all.first], future: all);
  }
  if (!time.isBefore(points.last.time)) {
    return (past: all, future: [all.last]);
  }

  final current = positionAt(points, time);
  final past = <LatLng>[];
  final future = <LatLng>[];
  for (var i = 0; i < points.length; i++) {
    if (!points[i].time.isAfter(time)) {
      past.add(all[i]);
    } else {
      future.add(all[i]);
    }
  }
  past.add(current);
  future.insert(0, current);
  return (past: past, future: future);
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
