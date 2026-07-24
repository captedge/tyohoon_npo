import 'dart:ui';

/// Fixed geographic display range for the whole app (decided 2026-07-26,
/// see docs/devlog-map-design.md): Philippines, Taiwan, Korea, the China
/// coast and all of Japan.
class MapBounds {
  static const double minLat = 5.0;
  static const double maxLat = 50.0;
  static const double minLon = 115.0;
  static const double maxLon = 150.0;

  /// Converts a lat/lon pair to a canvas offset within [size], with (0,0)
  /// at the top-left. Latitude increases upward (north), so it is inverted
  /// relative to the y axis.
  static Offset toOffset(double lat, double lon, Size size) {
    final x = (lon - minLon) / (maxLon - minLon) * size.width;
    final y = (maxLat - lat) / (maxLat - minLat) * size.height;
    return Offset(x, y);
  }
}
