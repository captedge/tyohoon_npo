/// Shared deg-min ("DD-MM.MM") conversion helpers for latitude/longitude
/// (2026-07-31), used by both the live cursor readout (map_screen.dart's
/// `_formatDegMin`, which wraps [formatDegMin] and adds its own N/S/E/W
/// hemisphere suffix on top) and the Passage Plan waypoint editor
/// (voyage_plan_screen.dart, which uses [formatDegMin]/[parseDegMin]
/// directly with no suffix — see that file for why). Factored out here so
/// the two screens' conversions can't silently drift apart from each other.
///
/// This app's whole display range (N5-50, E85-170 — see map_bounds.dart) is
/// always positive latitude/longitude, so unlike a general-purpose
/// implementation, [parseDegMin] doesn't accept a leading sign or a
/// hemisphere letter — see its own doc comment. [formatDegMin] takes the
/// absolute value of whatever it's given, so it never produces a negative
/// or signed string either.

/// Converts [decimalDegrees] to "DD-MM.MM" (degrees, a dash, minutes to
/// [minuteDecimals] decimal places) — e.g. `formatDegMin(35.1550)` ->
/// "35-9.30".
///
/// Always formats the *absolute* value (see this file's own doc comment for
/// why) — passing a negative [decimalDegrees] silently discards the sign
/// rather than producing something like "-35-9.30", which callers outside
/// this app's always-positive display range should not rely on.
String formatDegMin(double decimalDegrees, {int minuteDecimals = 2}) {
  final absValue = decimalDegrees.abs();
  var deg = absValue.floor();
  var minutes = double.parse(((absValue - deg) * 60).toStringAsFixed(minuteDecimals));
  // Carry a minutes-rounds-up-to-60 edge case into degrees (e.g. 34-59.997
  // rounded to 2 decimals would otherwise print as "34-60.00").
  if (minutes >= 60) {
    minutes -= 60;
    deg += 1;
  }
  return '$deg-${minutes.toStringAsFixed(minuteDecimals)}';
}

/// Parses a "DD-MM.MM" string (as [formatDegMin] produces) back into
/// decimal degrees, or null if [text] isn't in that shape — e.g.
/// `parseDegMin("35-9.30")` -> 35.155.
///
/// Deliberately strict (exactly one dash separating a non-negative integer
/// degree part from a `[0, 60)` minutes part) so a genuinely malformed value
/// is reported as an error rather than silently misparsed into something the
/// user didn't type — see voyage_plan_screen.dart's `_save` for how a null
/// here surfaces as a per-row validation message. Does not itself enforce a
/// latitude/longitude range (e.g. degrees <= 90 or <= 180) — that stays the
/// caller's responsibility, same as it already was when that caller parsed
/// plain decimal degrees directly.
double? parseDegMin(String text) {
  final trimmed = text.trim();
  final dashIndex = trimmed.indexOf('-');
  // dashIndex <= 0 rejects both "no dash found" (-1) and a leading dash with
  // an empty degrees part (e.g. "-9.30", which this app's always-positive
  // convention doesn't support — see this file's own doc comment).
  if (dashIndex <= 0 || dashIndex == trimmed.length - 1) return null;
  final deg = int.tryParse(trimmed.substring(0, dashIndex));
  final minutes = double.tryParse(trimmed.substring(dashIndex + 1));
  if (deg == null || deg < 0) return null;
  if (minutes == null || minutes < 0 || minutes >= 60) return null;
  return deg + minutes / 60;
}
