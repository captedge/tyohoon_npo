import 'open_meteo_marine_fetcher.dart';

/// **Personal-build only** (see build_flags.dart's `kPersonalBuild` — every
/// caller of this file's functions must already be behind that gate, same
/// as open_meteo_marine_fetcher.dart itself). Supports the "wave field" map
/// overlay (2026-07-29 request: "地図上に波高を色分け表示、Windy風のアニメー
/// ション、航路周辺のみ") — a grid of Open-Meteo sample points covering the
/// area around the active route(s), rendered by MapPainter's
/// `WaveFieldSample`/`_drawWaveField` (map_painter.dart doesn't import this
/// file or open_meteo_marine_fetcher.dart at all — it only knows about the
/// generic `WaveFieldSample` type, so the actual data-source/licensing
/// specifics stay confined to this personal-build-only layer).

/// One sampled grid point, carrying the full hourly series so the caller can
/// re-interpolate at whatever playback time the user has the slider on
/// (`interpolateHourlyValue` below) without re-fetching.
class WaveFieldPoint {
  const WaveFieldPoint({required this.lat, required this.lon, required this.hourly});

  final double lat;
  final double lon;
  final List<OpenMeteoMarinePoint> hourly;
}

/// Builds a regular lat/lon grid covering the box
/// [minLat]-[maxLat]/[minLon]-[maxLon] (already expected to include whatever
/// padding the caller wants — this function doesn't add its own), spaced
/// [spacingDeg] apart. If that spacing would produce more than [maxPoints]
/// points, the spacing is coarsened (multiplied up) just enough to fit
/// within the cap — kept deliberately small (2026-07-29 "航路周辺のみ"
/// decision) to bound both the single batched Open-Meteo request's size and
/// how many blobs/streaks the map painter draws per frame.
///
/// Returns an empty list if the box is degenerate (max <= min on either
/// axis).
List<({double lat, double lon})> buildWaveFieldGridPoints({
  required double minLat,
  required double maxLat,
  required double minLon,
  required double maxLon,
  double spacingDeg = 0.4,
  int maxPoints = 120,
}) {
  if (maxLat <= minLat || maxLon <= minLon) return const [];

  var spacing = spacingDeg;
  while (true) {
    final cols = ((maxLon - minLon) / spacing).floor() + 1;
    final rows = ((maxLat - minLat) / spacing).floor() + 1;
    if (cols * rows <= maxPoints || spacing > 10) break;
    // Coarsen by 25% at a time rather than doubling — doubling can overshoot
    // straight past a spacing that would've fit comfortably under maxPoints,
    // producing a visibly sparser grid than necessary.
    spacing *= 1.25;
  }

  final points = <({double lat, double lon})>[];
  final cols = ((maxLon - minLon) / spacing).floor() + 1;
  final rows = ((maxLat - minLat) / spacing).floor() + 1;
  for (var r = 0; r < rows; r++) {
    final lat = minLat + r * spacing;
    if (lat > maxLat) continue;
    for (var c = 0; c < cols; c++) {
      final lon = minLon + c * spacing;
      if (lon > maxLon) continue;
      points.add((lat: lat, lon: lon));
    }
  }

  // The coarsening loop above bails out once `spacing > 10` even if
  // cols*rows is still over maxPoints (Agent review, 2026-07-29) — not
  // reachable with this app's current call site (route-vicinity padding is
  // always well above spacingDeg, and the full-map-extent worst case still
  // stays under the default maxPoints), but truncating here makes the cap
  // an actual guarantee rather than "true for now" if a future caller ever
  // passes a very large box with a very small maxPoints.
  if (points.length > maxPoints) return points.take(maxPoints).toList();
  return points;
}

/// Linearly interpolates one numeric field of an hourly hourly series at
/// [time] — the same "find the two straddling samples, lerp" approach as
/// `positionAt` in interpolation.dart, but for a plain `double` value
/// (wave height/direction/period) rather than a lat/lon pair, since
/// `TrackPoint`/`positionAt` isn't reusable here (Open-Meteo's points don't
/// implement that interface and direction wraps at 360°, which plain linear
/// lerp deliberately does NOT attempt to handle specially — see
/// [wrapsAt360] below).
///
/// Returns null if [hourly] is empty, or if [select] returns null for the
/// relevant sample(s) (missing data for that hour — see
/// `OpenMeteoMarinePoint`'s doc comment).
///
/// [wrapsAt360] should be true for direction-like fields (0-360°, where 359°
/// and 1° are close together, not far apart) — when true, the interpolation
/// takes the shorter way around the circle instead of a plain straight-line
/// lerp that could swing the "wrong way" through 0°/360°.
double? interpolateHourlyValue(
  List<OpenMeteoMarinePoint> hourly,
  DateTime time,
  double? Function(OpenMeteoMarinePoint) select, {
  bool wrapsAt360 = false,
}) {
  if (hourly.isEmpty) return null;
  if (!time.isAfter(hourly.first.time)) return select(hourly.first);
  if (!time.isBefore(hourly.last.time)) return select(hourly.last);

  for (var i = 0; i < hourly.length - 1; i++) {
    final a = hourly[i];
    final b = hourly[i + 1];
    if (!time.isBefore(a.time) && !time.isAfter(b.time)) {
      final av = select(a);
      final bv = select(b);
      if (av == null || bv == null) return av ?? bv;
      final totalMs = b.time.difference(a.time).inMilliseconds;
      if (totalMs == 0) return av;
      final t = time.difference(a.time).inMilliseconds / totalMs;
      if (!wrapsAt360) return av + (bv - av) * t;
      var delta = (bv - av) % 360;
      if (delta > 180) delta -= 360;
      if (delta < -180) delta += 360;
      return (av + delta * t) % 360;
    }
  }
  // Should not be reached given the guards above (mirrors positionAt's own
  // fallback in interpolation.dart).
  return select(hourly.last);
}
