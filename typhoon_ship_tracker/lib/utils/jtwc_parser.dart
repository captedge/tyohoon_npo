import '../utils/interpolation.dart' show LatLng;

/// One forecast point from a JTWC warning's "NN HRS, VALID AT:" block, e.g.
///   12 HRS, VALID AT:
///   251200Z --- 22.0N 116.4E
/// [hoursFromNow] is the "NN" (12/24/36/48/60), used as an offset from
/// whenever the app's reference "now" (`_startTime` in map_screen.dart) is —
/// JTWC bulletins give only day/hour/minute (e.g. "251200Z"), not a full
/// date, so there's no reliable absolute timestamp to parse without also
/// knowing which month the warning is from. An offset from "now" is what
/// the rest of this app already uses for its sample/demo data, so forecast
/// points plug into the same time-slider/interpolation machinery.
class JtwcForecastPoint {
  final int hoursFromNow;
  final LatLng position;

  const JtwcForecastPoint({required this.hoursFromNow, required this.position});
}

/// Parsed-out fields from a JTWC warning text (the free-text bulletin
/// format, e.g. "WTPN31 PGTW ..." messages), for display purposes only.
///
/// This is intentionally narrow: it does not attempt to parse the full
/// warning (wind radii, storm category, etc.) — that belongs to the
/// eventual JTWC feed reader (see TASKS.md, not yet implemented). For now
/// the user pastes warning text in and this pulls out enough to draw a
/// track on the map: the typhoon's number/name, its current position and
/// central pressure, and its forecast track (12/24/36/48/60h positions).
class JtwcTyphoonInfo {
  /// e.g. "11W (NOUL)". Null if no "TYPHOON <number> (<name>)" line was found.
  final String? designation;

  /// Central pressure in hPa/mb at warning issue time (2026-07-28 request:
  /// "台風の現在（読み込み時）の最低気圧を表示する"). Null if not found.
  final int? centralPressureHpa;

  /// Current ("now") position ("REPEAT POSIT" line). Null if not found —
  /// in which case there's nothing to plot for this warning even if the
  /// designation/pressure parsed fine.
  final LatLng? position;

  /// Forecast points after [position], sorted by [JtwcForecastPoint.hoursFromNow]
  /// ascending. May be empty even when [position] is set (e.g. a warning
  /// with no "HRS, VALID AT" blocks) — the typhoon then just shows as a
  /// single static point rather than a track.
  final List<JtwcForecastPoint> forecastTrack;

  /// Day-of-month/hour/minute (UTC) parsed from the "WARNING POSITION:"
  /// block's "DDHHMMZ" line — the valid time for [position] (2026-07-28
  /// request: use this, not device "now", as the playback start time). Null
  /// if that line wasn't found. No year/month is available from the JTWC
  /// text itself (see [issuedAtJst]).
  final int? positionValidDay;
  final int? positionValidHourUtc;
  final int? positionValidMinuteUtc;

  const JtwcTyphoonInfo({
    this.designation,
    this.centralPressureHpa,
    this.position,
    this.forecastTrack = const [],
    this.positionValidDay,
    this.positionValidHourUtc,
    this.positionValidMinuteUtc,
  });

  static const empty = JtwcTyphoonInfo();

  bool get isEmpty =>
      designation == null &&
      centralPressureHpa == null &&
      position == null &&
      forecastTrack.isEmpty &&
      positionValidDay == null;

  /// Resolves the "WARNING POSITION" valid time to a concrete JST DateTime,
  /// e.g. "250000Z" → 25th 09:00 JST. Uses [reference]'s year and month
  /// since JTWC bulletins give only day/hour/minute — pass in the real
  /// current date (not a previously-resolved _startTime) to avoid drift if
  /// this is called again later. Returns null if no such line was parsed.
  DateTime? issuedAtJst(DateTime reference) {
    final day = positionValidDay;
    if (day == null) return null;
    final utc = DateTime.utc(
      reference.year,
      reference.month,
      day,
      positionValidHourUtc ?? 0,
      positionValidMinuteUtc ?? 0,
    );
    return utc.add(const Duration(hours: 9));
  }

  /// Summary text for the settings dialog, e.g. "11W (NOUL) · 980hPa · 5
  /// forecast points". Not used on the map itself (2026-07-28: the map now
  /// shows the designation and pressure as two separate labels — see
  /// map_screen.dart).
  String get summary {
    if (isEmpty) return 'No typhoon data parsed yet';
    final parts = <String>[
      if (designation != null) designation!,
      if (centralPressureHpa != null) '${centralPressureHpa}hPa',
      if (forecastTrack.isNotEmpty) '${forecastTrack.length} forecast point(s)',
    ];
    return parts.join(' · ');
  }
}

/// Parses a pasted JTWC warning text into [JtwcTyphoonInfo]. Fields that
/// don't match are simply left null/empty rather than failing outright — a
/// warning missing e.g. a REPEAT POSIT line (unusual, but not something to
/// hard-fail the whole paste over) still yields whatever else parsed.
JtwcTyphoonInfo parseJtwcWarningText(String text) {
  final designationMatch = RegExp(
    r'TYPHOON\s+(\d+[A-Z])\s*\(([^)]+)\)',
    caseSensitive: false,
  ).firstMatch(text);
  final designation = designationMatch == null
      ? null
      : '${designationMatch.group(1)!.toUpperCase()} (${designationMatch.group(2)!.trim().toUpperCase()})';

  final pressureMatch = RegExp(
    r'MINIMUM CENTRAL PRESSURE AT\s+\d+Z\s+IS\s+(\d+)\s*MB',
    caseSensitive: false,
  ).firstMatch(text);
  final pressure = pressureMatch == null ? null : int.tryParse(pressureMatch.group(1)!);

  final positionMatch = RegExp(
    r'REPEAT POSIT:\s*(\d+(?:\.\d+)?)\s*([NS])\s+(\d+(?:\.\d+)?)\s*([EW])',
    caseSensitive: false,
  ).firstMatch(text);
  final position = _latLngFromMatch(positionMatch, 1, 2, 3, 4);

  final warningTimeMatch = RegExp(
    r'WARNING POSITION:\s*\r?\n\s*(\d{2})(\d{2})(\d{2})Z',
    caseSensitive: false,
  ).firstMatch(text);
  final positionValidDay = warningTimeMatch == null ? null : int.tryParse(warningTimeMatch.group(1)!);
  final positionValidHourUtc = warningTimeMatch == null ? null : int.tryParse(warningTimeMatch.group(2)!);
  final positionValidMinuteUtc = warningTimeMatch == null ? null : int.tryParse(warningTimeMatch.group(3)!);

  final forecastTrack = <JtwcForecastPoint>[];
  final forecastPattern = RegExp(
    r'(\d+)\s*HRS,\s*VALID AT:\s*\n\s*\d{6}Z\s*---\s*'
    r'(\d+(?:\.\d+)?)\s*([NS])\s+(\d+(?:\.\d+)?)\s*([EW])',
    caseSensitive: false,
  );
  for (final m in forecastPattern.allMatches(text)) {
    final hours = int.tryParse(m.group(1)!);
    final pos = _latLngFromMatch(m, 2, 3, 4, 5);
    if (hours != null && pos != null) {
      forecastTrack.add(JtwcForecastPoint(hoursFromNow: hours, position: pos));
    }
  }
  forecastTrack.sort((a, b) => a.hoursFromNow.compareTo(b.hoursFromNow));

  return JtwcTyphoonInfo(
    designation: designation,
    centralPressureHpa: pressure,
    position: position,
    forecastTrack: forecastTrack,
    positionValidDay: positionValidDay,
    positionValidHourUtc: positionValidHourUtc,
    positionValidMinuteUtc: positionValidMinuteUtc,
  );
}

/// Builds a [LatLng] from a regex match's lat-degrees/hemisphere/lon-degrees/
/// hemisphere capture groups (by index), applying the sign for S/W. Returns
/// null if [match] itself is null (the caller's pattern didn't match).
LatLng? _latLngFromMatch(RegExpMatch? match, int latGroup, int latHemGroup, int lonGroup, int lonHemGroup) {
  if (match == null) return null;
  final latMagnitude = double.parse(match.group(latGroup)!);
  final lat = match.group(latHemGroup)!.toUpperCase() == 'S' ? -latMagnitude : latMagnitude;
  final lonMagnitude = double.parse(match.group(lonGroup)!);
  final lon = match.group(lonHemGroup)!.toUpperCase() == 'W' ? -lonMagnitude : lonMagnitude;
  return LatLng(lat, lon);
}
