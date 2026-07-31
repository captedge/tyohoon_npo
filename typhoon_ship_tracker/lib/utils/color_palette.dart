import 'package:flutter/material.dart';

/// Shared color choices for the Passage Plan-Edit (ship/route) and Forecast
/// (typhoon track) color pickers (2026-08-xx request: let the user override
/// the automatic default color per plan/typhoon source). Kept in one file
/// since both map_screen.dart and voyage_plan_screen.dart need the same
/// ship palette, and this is a natural home for the typhoon palette too.

/// Ship/route color choices (Passage Plan-Edit). Same 10 colors already used
/// for automatic per-plan color assignment (map_screen.dart's `_shipColors`,
/// which is now just an alias for this list) — copied verbatim so existing
/// automatic assignment (by registration order, cycling if there are ever
/// more than 10) is unchanged.
const List<Color> kShipColorPalette = [
  Color(0xFF1E88E5), // blue
  Color(0xFF43A047), // green
  Color(0xFFFFB300), // amber
  Color(0xFFD81B60), // pink
  Color(0xFF8E24AA), // purple
  Color(0xFF00ACC1), // cyan
  Color(0xFF6D4C41), // brown
  Color(0xFF3949AB), // indigo
  Color(0xFF7CB342), // light green
  Color(0xFFF4511E), // deep orange
];

/// Typhoon track color choices (Forecast dialog). First two entries match
/// the existing default JTWC/JMA colors so they visually double as
/// "reset to default" options; the rest are additional distinct choices.
const List<Color> kTyphoonColorPalette = [
  Color(0xFFE53935), // JTWC default (red)
  Color(0xFFEF6C00), // JMA default (orange)
  Color(0xFF1E88E5),
  Color(0xFF43A047),
  Color(0xFF8E24AA),
  Color(0xFF00897B),
  Color(0xFFFDD835),
  Color(0xFF6D4C41),
  Color(0xFFD81B60),
  Color(0xFF3949AB),
];
