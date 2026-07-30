import 'dart:convert';
import 'dart:io';

import 'build_flags.dart';

/// **Personal-build only** (see build_flags.dart's [kPersonalBuild] doc
/// comment for why). This whole file exists to try out Open-Meteo's Marine
/// Weather API as a possible replacement/supplement for the JMA VPCY51
/// (地方海上予報) route — see docs/devlog-online-xml.md "Open-Meteoとの比較"
/// for the tradeoffs already researched: unlike VPCY51's discrete per-area
/// blocks issued 4x/day, Open-Meteo returns a continuous hourly time series
/// for one exact point, so it can reuse this app's existing
/// point-in-time-interpolation pattern (interpolation.dart) directly, and is
/// available on demand rather than only near the 6/12/18/24 JST issue
/// windows.
///
/// Official docs: https://open-meteo.com/en/docs/marine-weather-api
///
/// **Attribution requirement (must stay visible wherever this data is
/// shown)**: "All users of Open-Meteo data must provide a clear attribution
/// to DWD as well as a reference to Open-Meteo." (wave data here comes from
/// DWD's ICON Wave model via Open-Meteo).
class OpenMeteoFetchException implements Exception {
  OpenMeteoFetchException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// One hourly time step of Open-Meteo's Marine Weather API `hourly` output.
/// [time] is a plain (not UTC-tagged) `DateTime` already in the timezone the
/// request asked for (this app always asks for `Asia/Tokyo`, i.e. JST) — see
/// [_parseLocalTimestamp]'s doc comment for why it's built manually instead
/// of via `DateTime.parse`. Fields the API didn't return a value for (either
/// because that variable wasn't requested, or the model has no data for that
/// hour) are null rather than omitted from the list, so [points] stays one
/// entry per hour with no gaps to reconcile against `time`.
class OpenMeteoMarinePoint {
  const OpenMeteoMarinePoint({
    required this.time,
    this.waveHeightM,
    this.waveDirectionDeg,
    this.wavePeriodS,
  });

  final DateTime time;

  /// Significant wave height, metres (API's `wave_height`, unit confirmed
  /// "Meter" in the API docs — no unit-conversion parameter needed, unlike
  /// wind/current speed variables this app deliberately doesn't request).
  final double? waveHeightM;

  /// Mean wave direction *the waves come from*, degrees (0=N, 90=E) — API's
  /// `wave_direction`.
  final double? waveDirectionDeg;

  /// Wave period, seconds — API's `wave_period`.
  final double? wavePeriodS;
}

class OpenMeteoMarineResult {
  const OpenMeteoMarineResult({
    required this.latitude,
    required this.longitude,
    required this.points,
  });

  /// Centre of the model grid cell actually used (API docs: "might be a few
  /// kilometres away from the requested coordinate") — kept distinct from
  /// the coordinates passed into [fetchOpenMeteoMarine] so a caller/debug UI
  /// can show the discrepancy rather than silently assuming an exact match.
  final double latitude;
  final double longitude;

  final List<OpenMeteoMarinePoint> points;
}

const _marineApiBase = 'https://marine-api.open-meteo.com/v1/marine';

Future<String> _fetchText(Uri uri) async {
  final client = HttpClient();
  client.connectionTimeout = const Duration(seconds: 15);
  try {
    final request = await client.getUrl(uri);
    final response = await request.close();
    final body = await response.transform(utf8.decoder).join();
    if (response.statusCode != 200) {
      // Open-Meteo returns a JSON body with an `error`/`reason` pair even on
      // a 400 (API docs "Errors") — surface that message instead of just the
      // bare status code when it's present, since it usually says exactly
      // what was wrong with the request (e.g. an invalid variable name).
      String? reason;
      try {
        final decoded = jsonDecode(body);
        if (decoded is Map && decoded['reason'] is String) reason = decoded['reason'] as String;
      } catch (_) {
        // Body wasn't JSON (or wasn't the expected shape) — fall through to
        // the generic status-code message below.
      }
      throw OpenMeteoFetchException(reason ?? 'HTTP ${response.statusCode}（$uri）');
    }
    return body;
  } on OpenMeteoFetchException {
    rethrow;
  } on SocketException catch (e) {
    throw OpenMeteoFetchException('ネットワークに接続できませんでした: ${e.message}');
  } on HttpException catch (e) {
    throw OpenMeteoFetchException('HTTPエラー: ${e.message}');
  } finally {
    client.close();
  }
}

/// Parses an Open-Meteo hourly timestamp ("YYYY-MM-DDTHH:MM", the format the
/// API docs confirm is used "when `timezone` is set, all timestamps are
/// returned as local-time") into a plain `DateTime` with no timezone tag.
///
/// Deliberately NOT `DateTime.parse(s)`: a string with no explicit UTC/
/// offset suffix is parsed by `DateTime.parse` as *this device's own local
/// timezone*, not necessarily JST — this is the exact bug class already
/// documented in docs/completed-log.md "再生バーの日付ずれバグ修正"
/// (`jtwc_parser.dart`'s `issuedAtJst` originally used `DateTime.utc(...)`
/// and produced a mismatched "actual instant" depending on the running
/// machine's timezone setting). Since this app's request always pins
/// `timezone=Asia/Tokyo` (see [fetchOpenMeteoMarine]), the returned strings
/// are already JST wall-clock time; parsing the numeric components directly
/// keeps that as a plain DateTime, consistent with how the rest of the app
/// treats already-JST values (never re-tags them as UTC).
DateTime _parseLocalTimestamp(String s) {
  final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2})').firstMatch(s);
  if (match == null) {
    throw OpenMeteoFetchException('Open-Meteoの時刻表記が想定外でした: $s');
  }
  return DateTime(
    int.parse(match.group(1)!),
    int.parse(match.group(2)!),
    int.parse(match.group(3)!),
    int.parse(match.group(4)!),
    int.parse(match.group(5)!),
  );
}

double? _numAt(List<dynamic>? list, int index) {
  if (list == null || index >= list.length) return null;
  final value = list[index];
  if (value == null) return null;
  if (value is num) return value.toDouble();
  return null;
}

const _hourlyVars = 'wave_height,wave_direction,wave_period';

/// Parses one "single location" JSON object out of an Open-Meteo Marine API
/// response — the whole top-level response body for a single-coordinate
/// request (see [fetchOpenMeteoMarine]), or one element of the top-level
/// array for a multi-coordinate request (see [fetchOpenMeteoMarineGrid] —
/// API docs: "To return data for multiple locations the JSON output changes
/// to a list of structures", each structure being this same per-location
/// shape). Shared here so both call sites parse identically instead of
/// duplicating the `hourly.time`/`wave_height`/etc. extraction logic.
///
/// [fallbackLatitude]/[fallbackLongitude] are used only if the response
/// itself omits `latitude`/`longitude` (shouldn't normally happen — kept as
/// a defensive fallback, same spirit as this function's other null-handling).
OpenMeteoMarineResult _parseSingleLocationResult(
  Map<String, dynamic> decoded, {
  required double fallbackLatitude,
  required double fallbackLongitude,
}) {
  final hourly = decoded['hourly'];
  if (hourly is! Map || hourly['time'] is! List) {
    throw OpenMeteoFetchException('レスポンスに hourly.time が見つかりませんでした。');
  }
  final times = (hourly['time'] as List).cast<String>();
  final waveHeights = hourly['wave_height'] as List?;
  final waveDirections = hourly['wave_direction'] as List?;
  final wavePeriods = hourly['wave_period'] as List?;

  final points = <OpenMeteoMarinePoint>[
    for (var i = 0; i < times.length; i++)
      OpenMeteoMarinePoint(
        time: _parseLocalTimestamp(times[i]),
        waveHeightM: _numAt(waveHeights, i),
        waveDirectionDeg: _numAt(waveDirections, i),
        wavePeriodS: _numAt(wavePeriods, i),
      ),
  ];

  final resolvedLat = (decoded['latitude'] as num?)?.toDouble() ?? fallbackLatitude;
  final resolvedLon = (decoded['longitude'] as num?)?.toDouble() ?? fallbackLongitude;
  return OpenMeteoMarineResult(latitude: resolvedLat, longitude: resolvedLon, points: points);
}

/// Fetches an hourly wave forecast (`wave_height`/`wave_direction`/
/// `wave_period`) for one point from Open-Meteo's Marine Weather API.
///
/// [forecastDays] mirrors the API's own `forecast_days` parameter (default
/// 5 server-side; the API accepts 0-8) — kept small by default here since
/// this is currently only used by a manual debug/trial UI, not a
/// route-wide forecast overlay.
///
/// Throws [OpenMeteoFetchException] for network/HTTP failures, a non-200
/// response, or a response that doesn't have the expected `hourly.time`
/// shape.
Future<OpenMeteoMarineResult> fetchOpenMeteoMarine({
  required double latitude,
  required double longitude,
  int forecastDays = 3,
}) async {
  assert(
    kPersonalBuild,
    'fetchOpenMeteoMarine must only be reachable from personal-build-gated '
    'code paths (see build_flags.dart) — a caller outside that gate is a bug.',
  );

  final uri = Uri.parse(_marineApiBase).replace(queryParameters: {
    'latitude': latitude.toStringAsFixed(4),
    'longitude': longitude.toStringAsFixed(4),
    'hourly': _hourlyVars,
    'timezone': 'Asia/Tokyo',
    'forecast_days': '$forecastDays',
  });

  final body = await _fetchText(uri);
  final Map<String, dynamic> decoded;
  try {
    decoded = jsonDecode(body) as Map<String, dynamic>;
  } on FormatException catch (e) {
    throw OpenMeteoFetchException('JSONとして解析できませんでした: ${e.message}');
  }
  return _parseSingleLocationResult(decoded, fallbackLatitude: latitude, fallbackLongitude: longitude);
}

/// Batch size for [fetchOpenMeteoMarineGrid]'s chunked requests (below).
///
/// **Hit in practice, 2026-07-30**: a single request built from
/// [buildWaveFieldGridPoints]' new 900-point cap (see that function's doc
/// comment in wave_field.dart) failed with HTTP 414 "URI Too Long" — the
/// comma-separated `latitude`/`longitude` query values for 900 points
/// produced a URL far past whatever length limit Open-Meteo's server (or a
/// proxy in front of it) enforces. Open-Meteo's own docs don't actually
/// document a URL-length ceiling (only a "up to 1000 locations" figure that
/// evidently isn't the binding constraint in practice), so rather than
/// guessing at a single safe point count for one request, [points] is split
/// into batches of at most this many locations, fetched as separate
/// concurrent HTTP requests and merged — keeping every individual request's
/// URL comfortably short (well under 2,000 characters even at 100 points)
/// regardless of how large the overall grid (`maxPoints` in
/// wave_field.dart) grows in the future. 100 is a conservative round number
/// chosen with a wide safety margin below the observed failure, not a
/// value derived from a documented limit.
const _maxLocationsPerRequest = 100;

/// Fetches the same hourly wave forecast as [fetchOpenMeteoMarine], but for
/// many points — batched into one or more HTTP requests of at most
/// [_maxLocationsPerRequest] locations each (see that constant's doc
/// comment for why), fired concurrently and merged. Used to render a wave
/// *field* over an area (2026-07-29 request: "地図上に波高を色分け表示、
/// Windy風のアニメーション"; see wave_field.dart for how [points] is
/// generated and capped).
///
/// Each returned [OpenMeteoMarineResult] carries its own resolved
/// latitude/longitude (the actual model grid-cell center — see that field's
/// doc comment), so callers should plot using those rather than assuming
/// the *n*-th result corresponds positionally to the *n*-th input [points]
/// entry — this function doesn't assert an order guarantee from the API,
/// and batching makes that doubly true (results across batches are
/// concatenated in batch order, but within Dart's `Future.wait` the
/// individual HTTP responses themselves can still complete/parse in any
/// order relative to each other before being reassembled).
///
/// Returns an empty list (not an error) for an empty [points] input,
/// without making a request. All-or-nothing on failure: if any one batch's
/// request throws (network/HTTP failure, non-200 response, or an
/// unexpected response shape), the whole call throws and no partial grid is
/// returned — simpler to reason about than a map silently missing whatever
/// patch of the grid one failed batch would have covered, at the cost of
/// occasionally discarding several batches' worth of otherwise-good data
/// alongside the one that failed.
Future<List<OpenMeteoMarineResult>> fetchOpenMeteoMarineGrid({
  required List<({double lat, double lon})> points,
  int forecastDays = 2,
}) async {
  assert(
    kPersonalBuild,
    'fetchOpenMeteoMarineGrid must only be reachable from personal-build-gated '
    'code paths (see build_flags.dart) — a caller outside that gate is a bug.',
  );
  if (points.isEmpty) return const [];

  final batches = <List<({double lat, double lon})>>[];
  for (var i = 0; i < points.length; i += _maxLocationsPerRequest) {
    final end = i + _maxLocationsPerRequest < points.length ? i + _maxLocationsPerRequest : points.length;
    batches.add(points.sublist(i, end));
  }

  final batchResults = await Future.wait(
    batches.map((batch) => _fetchOpenMeteoMarineBatch(batch, forecastDays: forecastDays)),
  );
  return [for (final batch in batchResults) ...batch];
}

/// Fetches one batch (at most [_maxLocationsPerRequest] locations, per
/// [fetchOpenMeteoMarineGrid]'s chunking) as a single HTTP request.
///
/// A batch of exactly one point is routed through [fetchOpenMeteoMarine]
/// instead of building a multi-location URL here: a single point produces
/// a comma-free latitude/longitude query value, which Open-Meteo's docs
/// describe as the trigger for the *single-object* response shape
/// (comma-separated values are what switches it to the array-of-structures
/// shape) — so parsing this batch as an array would incorrectly reject a
/// genuine 1-point batch (Agent review, 2026-07-29; this exact edge case
/// was originally guarded in [fetchOpenMeteoMarineGrid] itself before the
/// 2026-07-30 batching change moved it here, since a batch this small is
/// now reachable in practice whenever [points]' total length isn't a clean
/// multiple of [_maxLocationsPerRequest]).
Future<List<OpenMeteoMarineResult>> _fetchOpenMeteoMarineBatch(
  List<({double lat, double lon})> points, {
  required int forecastDays,
}) async {
  if (points.length == 1) {
    final only = points.single;
    return [await fetchOpenMeteoMarine(latitude: only.lat, longitude: only.lon, forecastDays: forecastDays)];
  }

  final uri = Uri.parse(_marineApiBase).replace(queryParameters: {
    'latitude': points.map((p) => p.lat.toStringAsFixed(3)).join(','),
    'longitude': points.map((p) => p.lon.toStringAsFixed(3)).join(','),
    'hourly': _hourlyVars,
    'timezone': 'Asia/Tokyo',
    'forecast_days': '$forecastDays',
  });

  final body = await _fetchText(uri);
  final dynamic decoded;
  try {
    decoded = jsonDecode(body);
  } on FormatException catch (e) {
    throw OpenMeteoFetchException('JSONとして解析できませんでした: ${e.message}');
  }
  if (decoded is! List) {
    throw OpenMeteoFetchException('複数地点のレスポンス形式が想定と異なりました（配列ではありません）。');
  }

  return [
    for (var i = 0; i < decoded.length; i++)
      _parseSingleLocationResult(
        decoded[i] as Map<String, dynamic>,
        // Fallback only kicks in if a given entry omits its own lat/lon —
        // best-effort pairing with the request list by index for that rare
        // case, not relied on for normal plotting (see doc comment above).
        fallbackLatitude: i < points.length ? points[i].lat : 0,
        fallbackLongitude: i < points.length ? points[i].lon : 0,
      ),
  ];
}
