import 'dart:convert';
import 'dart:io';

import 'build_flags.dart';
import 'open_meteo_marine_fetcher.dart';
import 'portable_storage_dir.dart';
import 'wave_field.dart';

/// **Personal-build only** (see build_flags.dart's [kPersonalBuild] — every
/// caller here must already be behind that gate, same convention as
/// open_meteo_marine_fetcher.dart/wave_field.dart).
///
/// This file has been redesigned twice on 2026-07-30, in the same session:
/// 1. Originally: cache each fetch's own viewport-derived box, reused only
///    if a later box was fully contained in an earlier one — real-world
///    panning almost never satisfied that (proven mathematically: with the
///    same padding formula applied to both the old and new box, any nonzero
///    pan leaves the new box's far edge past the old one's, so containment
///    only holds for an unchanged view).
/// 2. Redesigned to a fixed 8°×8° tile grid (tile-index match instead of
///    geometric containment), with a per-round new-tile cap and a real-fetch
///    cooldown to bound worst-case call rate. This worked for panning, but
///    real-world testing hit Open-Meteo's free-tier *daily* call cap anyway
///    — the round-cap overflow auto-continued fetching in the background
///    (via a timer) with no further user action, so simply leaving a
///    zoomed-out cold view open kept firing real requests unattended.
///
/// The user then proposed a fundamentally simpler model instead of further
/// tuning the dynamic-viewport machinery: **one fixed geographic area**
/// ([waveFieldFixedMinLat]/[waveFieldFixedMaxLat]/[waveFieldFixedMinLon]/
/// [waveFieldFixedMaxLon] below — 25N-45N/125E-150E, the "②" candidate from
/// the earlier rate-limit range investigation, see
/// docs/devlog-online-xml.md "レート制限対策の検討過程"), fetched only when
/// the user presses an explicit "Import wave field" button — mirroring this
/// app's existing JMA/JTWC/Marine-Forecast convention of a "Display
/// checkbox + Import button" pair (see map_screen.dart's
/// `_showLabelSettingsDialog`, "Wave Field" section) — with **no
/// TTL/staleness/auto-refetch at all**: whatever was last imported stays
/// shown until the user presses Import again. Map pan/zoom no longer
/// triggers any fetch whatsoever — it only changes what part of this one
/// fixed grid happens to be visible on screen.
///
/// Consequently this file now persists exactly one thing: the last
/// successful import (its points + when it was fetched) plus the Display
/// on/off flag, so the Information dialog can restore both across an app
/// restart the same way Marine Forecast does. Kept in its own file rather
/// than folded into `AppStateStorage` so a mainline (non-personal) build
/// never carries Open-Meteo-specific fields.
class WaveFieldSavedState {
  const WaveFieldSavedState({
    required this.displayEnabled,
    required this.points,
    required this.fetchedAt,
  });

  final bool displayEnabled;
  final List<WaveFieldPoint> points;

  /// Wall-clock real time (device-local `DateTime.now()`) the last
  /// successful Import completed — shown to the user as "Cached: ..." (same
  /// convention as Marine Forecast's own fetchedAt label) so they can judge
  /// for themselves whether it's worth re-importing, rather than the app
  /// silently deciding that on their behalf via a TTL.
  final DateTime? fetchedAt;

  static const empty = WaveFieldSavedState(displayEnabled: false, points: [], fetchedAt: null);
}

/// Fixed area this feature always fetches (2026-07-30 user decision) — no
/// longer tied to the map viewport at all. Candidate "②" from the earlier
/// rate-limit range investigation (docs/devlog-online-xml.md「レート制限
/// 対策の検討過程」), chosen because it comfortably covers Japan's near seas
/// (Kyushu/Shikoku/Honshu/Hokkaido, the Korea Strait, and the East China
/// Sea approach) without needing the full N5-50/E85-170 display range.
const double waveFieldFixedMinLat = 25.0;
const double waveFieldFixedMaxLat = 45.0;
const double waveFieldFixedMinLon = 125.0;
const double waveFieldFixedMaxLon = 150.0;

/// Point cap for the fixed-area grid (2026-08-xx, corrected — see below;
/// originally set to 3,500, which was wrong).
///
/// **Correction (2026-08-xx)**: the original 3,500 figure was sized by
/// assuming "1 HTTP request ≈ 1 rate-limited call", i.e. that
/// [_maxConcurrentBatches] (open_meteo_marine_fetcher.dart) — which only
/// throttles *concurrent* requests — was also enough to stay under
/// Open-Meteo's 600-calls/minute figure. That assumption was wrong: per the
/// maintainer (github.com/open-meteo/open-meteo#1295), "using multiple
/// coordinates multiplies the value of a single coordinate API call" — a
/// 100-location batch counts as roughly 100 calls, not 1, regardless of how
/// many requests it took to send it. The real per-point weight (per
/// open-meteo/open-meteo#485/#1295) is
/// `max(1, variables/10) * max(1, forecastDays/7)` — with this feature's 3
/// variables (wave_height/direction/period) that first factor floors to 1,
/// so weight per point ≈ `max(1, forecastDays/7)`. At `forecastDays`' own
/// documented max of 8 (see importWaveField in map_screen.dart), that's
/// 8/7 ≈ 1.143 — the worst case this cap must stay safe under, since
/// `forecastDays` varies with whatever voyage plan happens to be loaded at
/// Import time.
///
/// 3,500 points × 1.143 ≈ 4,000 — nowhere near the literal request-count
/// figuring's "35 requests" but almost **7× over** the real 600/minute
/// limit in a single Import click (this is what caused the repeated
/// "Minutely" errors, see docs/completed-log.md). Solving
/// `points × 8/7 <= 600` gives a hard ceiling of 525 points; this constant
/// is set well under that (≈5% margin) rather than exactly at it, in case
/// Open-Meteo's own weight rounding isn't a plain floor/ceiling. The
/// consequence is a much coarser grid than originally intended: at this
/// fixed area's ~500 square-degree extent (20°×25°), 500 points works out
/// to roughly 1.0° spacing (`sqrt(500 / 500)`), not the ~0.4° this file
/// originally aimed for — that finer density simply isn't reachable for an
/// area this large within the free tier's per-minute weight budget, given
/// this feature fetches everything for one Import click within well under
/// a minute (5 batches at [_maxLocationsPerRequest]-ish size — see
/// open_meteo_marine_fetcher.dart — comfortably clear in a few seconds).
const int waveFieldFixedAreaMaxPoints = 500;

/// Not cached as a field (2026-07-27 CsvLibrary precedent, same reasoning):
/// re-resolved on every call rather than caching the Directory/File after
/// first use, so this stays robust if the underlying folder is removed out
/// from under the app.
///
/// **2026-08 change**: resolved under [appDataDir] (`portable_storage_dir.dart`)
/// instead of the OS's per-user "application support" directory directly —
/// on Windows this now lives in a `UserData` folder next to the exe, same as
/// `AppStateStorage`/`CsvLibrary` (see `docs/devlog-portable-data-dir.md`).
Future<File> _waveFieldCacheFile() async {
  final dir = await appDataDir();
  return File('${dir.path}${Platform.pathSeparator}wave_field_cache.json');
}

/// Loads the persisted Display flag + last-imported grid. Returns
/// [WaveFieldSavedState.empty] if the file is missing, unreadable, or
/// malformed — fails soft (same convention as `AppStateStorage.load`): a
/// corrupt cache file should never block the app from starting, it just
/// means the overlay starts empty/off until the user imports again.
Future<WaveFieldSavedState> loadWaveFieldCache() async {
  assert(
    kPersonalBuild,
    'loadWaveFieldCache must only be reachable from personal-build-gated '
    'code paths (see build_flags.dart) — a caller outside that gate is a bug.',
  );
  try {
    final file = await _waveFieldCacheFile();
    String? raw;
    if (await file.exists()) {
      raw = await file.readAsString();
    } else if (Platform.isWindows) {
      // One-time migration (2026-08 change, see _waveFieldCacheFile doc
      // above): fall back to the old per-user location so a device that
      // already had a cached wave field grid doesn't lose it after
      // upgrading to a build with this change.
      final legacyBase = await legacyAppDataDir();
      final legacyFile = File('${legacyBase.path}${Platform.pathSeparator}wave_field_cache.json');
      if (await legacyFile.exists()) {
        raw = await legacyFile.readAsString();
        try {
          await file.writeAsString(raw);
        } catch (_) {
          // Best-effort copy-forward; still use the just-read value below
          // for this session even if it failed.
        }
      }
    }
    if (raw == null) return WaveFieldSavedState.empty;
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) return WaveFieldSavedState.empty;

    final fetchedAtRaw = decoded['fetchedAt'];
    final fetchedAt = fetchedAtRaw is String ? DateTime.tryParse(fetchedAtRaw) : null;

    final points = <WaveFieldPoint>[];
    final pointsJson = decoded['points'];
    if (pointsJson is List) {
      for (final pJson in pointsJson) {
        if (pJson is! Map<String, dynamic>) continue;
        final lat = pJson['lat'];
        final lon = pJson['lon'];
        final hourlyJson = pJson['hourly'];
        if (lat is! num || lon is! num || hourlyJson is! List) continue;
        final hourly = <OpenMeteoMarinePoint>[];
        for (final hJson in hourlyJson) {
          if (hJson is! Map<String, dynamic>) continue;
          final timeRaw = hJson['time'];
          if (timeRaw is! String) continue;
          final time = DateTime.tryParse(timeRaw);
          if (time == null) continue;
          hourly.add(OpenMeteoMarinePoint(
            time: time,
            waveHeightM: (hJson['waveHeightM'] as num?)?.toDouble(),
            waveDirectionDeg: (hJson['waveDirectionDeg'] as num?)?.toDouble(),
            wavePeriodS: (hJson['wavePeriodS'] as num?)?.toDouble(),
          ));
        }
        points.add(WaveFieldPoint(lat: lat.toDouble(), lon: lon.toDouble(), hourly: hourly));
      }
    }

    return WaveFieldSavedState(
      displayEnabled: decoded['displayEnabled'] == true,
      points: points,
      fetchedAt: fetchedAt,
    );
  } catch (_) {
    return WaveFieldSavedState.empty;
  }
}

/// Persists [state] (Display flag + last-imported grid) to disk.
/// Fire-and-forget from the caller's point of view (map_screen.dart doesn't
/// await this) — a failed/slow write just means the next app restart starts
/// from an empty/off overlay instead of restoring it, the same best-effort
/// spirit as `AppStateStorage.save`'s own fire-and-forget callers.
Future<void> saveWaveFieldCache(WaveFieldSavedState state) async {
  assert(
    kPersonalBuild,
    'saveWaveFieldCache must only be reachable from personal-build-gated '
    'code paths (see build_flags.dart) — a caller outside that gate is a bug.',
  );
  final file = await _waveFieldCacheFile();
  final json = {
    'displayEnabled': state.displayEnabled,
    'fetchedAt': state.fetchedAt?.toIso8601String(),
    'points': [
      for (final p in state.points)
        {
          'lat': p.lat,
          'lon': p.lon,
          'hourly': [
            for (final h in p.hourly)
              {
                'time': h.time.toIso8601String(),
                'waveHeightM': h.waveHeightM,
                'waveDirectionDeg': h.waveDirectionDeg,
                'wavePeriodS': h.wavePeriodS,
              },
          ],
        },
    ],
  };
  await file.writeAsString(jsonEncode(json));
}
