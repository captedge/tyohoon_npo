import 'open_meteo_marine_fetcher.dart';

/// **Personal-build only** (see build_flags.dart's `kPersonalBuild` — every
/// caller of this file's functions must already be behind that gate, same
/// as open_meteo_marine_fetcher.dart itself). Supports the "wave field" map
/// overlay (2026-07-29 request: "地図上に波高を色分け表示、Windy風のアニメー
/// ション") — a grid of Open-Meteo sample points covering an area of the
/// map, rendered by MapPainter's `WaveFieldSample`/`_drawWaveField`
/// (map_painter.dart doesn't import this file or
/// open_meteo_marine_fetcher.dart at all — it only knows about the generic
/// `WaveFieldSample` type, so the actual data-source/licensing specifics
/// stay confined to this personal-build-only layer).
///
/// Which area that grid covers has changed several times (2026-07-29→30):
/// "route vicinity only" → "whatever's currently visible in the map
/// viewport, refetched as the user pans/zooms" (with a tile-based cache) →
/// finally a **single fixed area, fetched only on an explicit "Import wave
/// field" button press** (see wave_field_cache.dart's class doc for the
/// full history and why the dynamic-viewport designs were abandoned). The
/// fixed box's bounds now come from wave_field_cache.dart's
/// `waveFieldFixedMinLat`/`MaxLat`/`MinLon`/`MaxLon`, passed in by
/// map_screen.dart's `importWaveField` closure (inside
/// `_showLabelSettingsDialog`) — this file stays agnostic to where the box
/// comes from and just turns whatever box it's given into a grid.

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
/// within the cap, so the grid never exceeds [maxPoints] regardless of how
/// large the requested box is — this matters now that the box is the
/// current map viewport (2026-07-30) rather than a fixed route-vicinity
/// box: a zoomed-out viewport can span the app's entire N5-50/E85-170
/// display range.
///
/// [maxPoints]' default (900, raised from an original 120) reflects
/// 2026-07-30 user feedback that the full-viewport grid ("網羅されたが...
/// 波浪情報として使えないレベル") was too sparse to be useful compared to
/// the original route-vicinity-only box's density. Request-URL size is
/// *not* a reason to keep this small — [fetchOpenMeteoMarineGrid] in
/// open_meteo_marine_fetcher.dart splits [points] into several small HTTP
/// requests regardless of how large [maxPoints] is (a single request built
/// from the full 900 points hit HTTP 414 "URI Too Long" in practice before
/// that batching was added — see that function's doc comment). The
/// remaining real ceiling on [maxPoints] is render cost: more points means
/// more blobs/streaks for MapPainter to draw every animation frame, which
/// depends on how the map actually performs at a given point count on real
/// hardware, not on anything this function can measure itself (Windows
/// real-machine check needed, see TASKS.md).
///
/// Returns an empty list if the box is degenerate (max <= min on either
/// axis).
List<({double lat, double lon})> buildWaveFieldGridPoints({
  required double minLat,
  required double maxLat,
  required double minLon,
  required double maxLon,
  double spacingDeg = 0.4,
  int maxPoints = 900,
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
  // cols*rows is still over maxPoints (Agent review, 2026-07-29). With the
  // current default maxPoints (900) this genuinely can be reached at the
  // full N5-50/E85-170 viewport extent (85x45 degrees needs spacing ~2.06
  // to land at 900 points, well under the `spacing > 10` bailout — so in
  // practice the coarsening loop itself already satisfies the cap there),
  // but this truncation stays as a hard backstop guarantee for any future
  // caller that passes a very large box with a much smaller maxPoints,
  // where the `spacing > 10` bailout could otherwise be hit first.
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
