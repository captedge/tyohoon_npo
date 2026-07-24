import 'dart:math' as math;
import 'dart:ui';

/// Fixed geographic display range for the whole app (decided 2026-07-26,
/// see docs/devlog-map-design.md): Philippines, Taiwan, Korea, the China
/// coast and all of Japan.
///
/// Coordinates are projected with Web Mercator (the same projection used by
/// Google Maps and most familiar web maps), not a plain equirectangular
/// (linear lat/lon) projection. Two reasons:
/// 1. It keeps local shapes correct ("conformal") at any latitude, so Japan
///    etc. render in the shape people actually recognize.
/// 2. Combined with [canvasSize] below (a fixed logical size whose aspect
///    ratio matches the projected bounds), it avoids the map being
///    stretched or squashed to whatever rectangle happens to be on screen —
///    see 2026-07-26 feedback in docs/devlog-map-design.md.
class MapBounds {
  static const double minLat = 5.0;
  static const double maxLat = 50.0;
  static const double minLon = 115.0;
  static const double maxLon = 150.0;

  /// A point roughly at the center of Japan, used as the app's default
  /// starting view (2026-07-26 decision) instead of showing the full
  /// N5-50/E115-150 range zoomed all the way out.
  static const double defaultCenterLat = 30.0;
  static const double defaultCenterLon = 135.0;

  // Web Mercator y (in "degree-equivalent" units, i.e. scaled so 1 unit of
  // longitude and 1 unit of projected latitude are the same size at the
  // equator — this is what keeps shapes undistorted).
  static double _mercatorY(double latDeg) {
    final latRad = latDeg * (math.pi / 180);
    return math.log(math.tan(math.pi / 4 + latRad / 2)) * (180 / math.pi);
  }

  /// Inverse of [_mercatorY]: converts a projected Mercator y value (in the
  /// same "degree-equivalent" units) back to a latitude in degrees.
  static double _inverseMercatorY(double mercatorYDeg) {
    final mercatorYRad = mercatorYDeg * (math.pi / 180);
    final latRad = 2 * math.atan(math.exp(mercatorYRad)) - math.pi / 2;
    return latRad * (180 / math.pi);
  }

  static final double _yTop = _mercatorY(maxLat);
  static final double _yBottom = _mercatorY(minLat);

  /// True width:height ratio of the bounding box under Web Mercator.
  static final double aspectRatio = (maxLon - minLon) / (_yTop - _yBottom);

  /// Fixed logical canvas size (in arbitrary "map units", not device
  /// pixels) that the whole map is drawn into and that [InteractiveViewer]
  /// zooms/pans. Its aspect ratio always matches [aspectRatio], so the map
  /// never looks stretched regardless of the app window's shape.
  static const double canvasWidth = 900.0;
  static double get canvasHeight => canvasWidth / aspectRatio;
  static Size get canvasSize => Size(canvasWidth, canvasHeight);

  /// Converts a lat/lon pair to an offset on [canvasSize], with (0,0) at
  /// the top-left.
  static Offset toOffset(double lat, double lon) {
    final x = (lon - minLon) / (maxLon - minLon) * canvasWidth;
    final y = (_yTop - _mercatorY(lat)) / (_yTop - _yBottom) * canvasHeight;
    return Offset(x, y);
  }

  /// Inverse of [toOffset]: converts a point on [canvasSize] back to a
  /// lat/lon pair. Used for the cursor position readout (2026-07-27) — the
  /// result is not clamped to MapBounds, so callers over/under the visible
  /// range will get lat/lon values slightly outside N5-50/E115-150.
  static ({double lat, double lon}) fromOffset(Offset offset) {
    final lon = offset.dx / canvasWidth * (maxLon - minLon) + minLon;
    final mercatorY = _yTop - offset.dy / canvasHeight * (_yTop - _yBottom);
    final lat = _inverseMercatorY(mercatorY);
    return (lat: lat, lon: lon);
  }
}
