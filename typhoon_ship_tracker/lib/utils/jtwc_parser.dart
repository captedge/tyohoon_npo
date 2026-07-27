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
  /// e.g. "250000Z" → 25th 09:00 JST. JTWC bulletins give only day/hour/
  /// minute, no month/year, so [reference] (pass in the real current date,
  /// not a previously-resolved _startTime, to avoid drift if this is called
  /// again later) is used to disambiguate which month/year the bare "day"
  /// number belongs to. Returns null if no such line was parsed.
  ///
  /// Deliberately builds a plain (non-UTC-tagged) DateTime whose fields
  /// directly represent the JST wall-clock time, computing the UTC→JST
  /// +9h day carry by hand instead of going through `DateTime.utc(...).add(...)`.
  /// This app never calls `toUtc()`/`toLocal()` — every DateTime everywhere
  /// (including `DateTime(_startTime.year, _startTime.month, _startTime.day)`
  /// in the playback bar's day segments) is treated as a plain wall-clock
  /// value. A `DateTime.utc(...)`-derived value here (2026-07-30 bug) is
  /// tagged as UTC and so represents a different real instant than those
  /// plain DateTimes whenever the device's OS timezone isn't UTC+0 — e.g. on
  /// a JST machine, "UTC 25th 15:00" is actually the instant "26th 00:00
  /// JST", which shifted the playback bar's day boundaries by a day even
  /// though the displayed HH:MM (read via raw field access, unaffected by
  /// the UTC tag) still looked correct.
  ///
  /// Month/year disambiguation (2026-07-27 fix): simply combining `day +
  /// dayCarry` with [reference]'s month/year (letting DateTime's own
  /// overflow normalization handle a month-end rollover, e.g. day 32 →
  /// the 1st/2nd of the next month) only works while [reference] is still
  /// in the *same* month the warning's bare day number belongs to. Once the
  /// device's calendar has itself already rolled over to the next month by
  /// the time the text is pasted in — e.g. a "311800Z" (31st) warning
  /// entered when the PC reads "8/1 03:30" — [reference].month is already
  /// the *next* month, so combining it with `day` (31) double-advances
  /// (July 31 + 9h JST = Aug 1, but `DateTime(<Aug>, 32, ...)` normalizes to
  /// Sep 1, one month too far). To handle this, two candidate dates are
  /// built — one using [reference]'s month, one using the month before it
  /// (with automatic year rollover for a December→January boundary) — and
  /// whichever candidate is not more than [_futureTolerance] ahead of
  /// [reference], and is the more recent of the two such candidates, is
  /// used. Since JTWC warnings always describe a very recent (same-day or
  /// previous-day) position, exactly one of the two candidates should
  /// satisfy "not implausibly far in the future" in the normal case; when
  /// both do (the common case, no month boundary involved), the more recent
  /// one is simply the correct same-month reading.
  static const _futureTolerance = Duration(hours: 6);

  DateTime? issuedAtJst(DateTime reference) {
    final day = positionValidDay;
    if (day == null) return null;
    final utcMinutesOfDay = (positionValidHourUtc ?? 0) * 60 + (positionValidMinuteUtc ?? 0);
    final jstMinutesOfDay = utcMinutesOfDay + 9 * 60;
    final dayCarry = jstMinutesOfDay ~/ (24 * 60);
    final minuteOfDay = jstMinutesOfDay % (24 * 60);
    final hour = minuteOfDay ~/ 60;
    final minute = minuteOfDay % 60;

    DateTime candidateFor(int year, int month) {
      return DateTime(year, month, day + dayCarry, hour, minute);
    }

    final sameMonthCandidate = candidateFor(reference.year, reference.month);
    final previousMonth = reference.month == 1 ? 12 : reference.month - 1;
    final previousMonthYear = reference.month == 1 ? reference.year - 1 : reference.year;
    final previousMonthCandidate = candidateFor(previousMonthYear, previousMonth);

    final futureLimit = reference.add(_futureTolerance);
    DateTime? best;
    for (final candidate in [sameMonthCandidate, previousMonthCandidate]) {
      if (candidate.isAfter(futureLimit)) continue;
      if (best == null || candidate.isAfter(best)) best = candidate;
    }
    // Fall back to the same-month reading if both candidates somehow land
    // in the future (shouldn't happen for a real warning text, but avoids
    // returning null and silently discarding the resolved start time).
    return best ?? sameMonthCandidate;
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
  // Matches any JTWC intensity classification, not just "TYPHOON" — a
  // warning can be issued for a system at any stage (2026-07-27 report:
  // "TROPICAL STORM 12W (DOLPHIN)" was rejected because the old pattern
  // only matched the literal word "TYPHOON"). The number/name pair is what
  // this app actually needs (designation); the classification word itself
  // is intentionally discarded — the user wants every stage tracked the
  // same way ("台風として認識して構わない"), not labeled by category.
  final designationMatch = RegExp(
    r'(?:SUPER\s+TYPHOON|TYPHOON|SEVERE\s+TROPICAL\s+STORM|TROPICAL\s+STORM|TROPICAL\s+DEPRESSION)'
    r'\s+(\d+[A-Z])\s*\(([^)]+)\)',
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
