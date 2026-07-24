import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../utils/interpolation.dart';
import '../utils/map_bounds.dart';

/// Draws the simplified plot map: a lat/lon grid, coastline, the typhoon
/// forecast track, and the ship/typhoon markers with a distance line
/// between them.
///
/// Always paints into a canvas sized [MapBounds.canvasSize] (see that
/// class for why) — the `size` passed to [paint] should match it.
class MapPainter extends CustomPainter {
  final LatLng shipPosition;
  final List<LatLng> shipRoute;
  final LatLng typhoonPosition;
  final List<LatLng> typhoonForecastTrack;
  final double distanceNauticalMiles;
  final List<List<LatLng>> coastlinePolygons;

  /// The next waypoint ahead of [shipPosition] in time, used so the ship
  /// icon's apex points toward it (2026-07-27 request) instead of always
  /// pointing north. Null once the voyage is complete (no waypoint left
  /// ahead) or if there's only a single track point — the icon then falls
  /// back to pointing north.
  final LatLng? nextWaypoint;

  MapPainter({
    required this.shipPosition,
    required this.shipRoute,
    required this.typhoonPosition,
    required this.typhoonForecastTrack,
    required this.distanceNauticalMiles,
    this.coastlinePolygons = const [],
    this.nextWaypoint,
  });

  @override
  void paint(Canvas canvas, Size size) {
    _drawSea(canvas, size);
    _drawGrid(canvas);
    _drawCoastline(canvas);
    _drawShipRoute(canvas);
    _drawTyphoonTrack(canvas);
    _drawDistanceLine(canvas);
    _drawShip(canvas);
    _drawTyphoon(canvas);
  }

  // Full planned route (all waypoints, past and future) as a dotted line
  // with small markers at each waypoint. The current ship position is drawn
  // separately, on top, by _drawShip.
  void _drawShipRoute(Canvas canvas) {
    if (shipRoute.length < 2) return;
    final routePaint = Paint()
      ..color = Colors.blue.shade600
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    final path = Path();
    for (var i = 0; i < shipRoute.length; i++) {
      final o = MapBounds.toOffset(shipRoute[i].latitude, shipRoute[i].longitude);
      if (i == 0) {
        path.moveTo(o.dx, o.dy);
      } else {
        path.lineTo(o.dx, o.dy);
      }
    }
    canvas.drawPath(_dashed(path, dashLength: 4, gapLength: 3), routePaint);

    final wptPaint = Paint()..color = Colors.blue.shade100;
    final wptBorder = Paint()
      ..color = Colors.blue.shade700
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    for (final p in shipRoute) {
      final o = MapBounds.toOffset(p.latitude, p.longitude);
      canvas.drawCircle(o, 3.5, wptPaint);
      canvas.drawCircle(o, 3.5, wptBorder);
    }
  }

  // Sea background, painted first so everything else layers on top of it.
  // Tentative nautical-chart palette (light blue sea / tan land) proposed
  // 2026-07-27 to replace the placeholder white-sea/grey-land look — see
  // TASKS.md, still pending the user's sign-off on colors.
  static const _seaColor = Color(0xFFD8EAF6);
  static const _landColor = Color(0xFFE7DFC6);
  static const _landOutlineColor = Color(0xFF9C8F66);

  void _drawSea(Canvas canvas, Size size) {
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = _seaColor,
    );
  }

  // Grid lines only — the "20N"/"120E" labels used to be drawn here too,
  // baked into the map canvas, which meant they scrolled off-screen when
  // zoomed/panned (2026-07-27 feedback). Labels are now a separate overlay
  // in map_screen.dart (`_buildGridLabelOverlays`) that tracks the current
  // viewport transform and stays pinned to the screen edges instead.
  void _drawGrid(Canvas canvas) {
    final gridPaint = Paint()
      ..color = Colors.blueGrey.withOpacity(0.35)
      ..strokeWidth = 1;

    for (var lon = MapBounds.minLon; lon <= MapBounds.maxLon; lon += 5) {
      final p1 = MapBounds.toOffset(MapBounds.maxLat, lon);
      final p2 = MapBounds.toOffset(MapBounds.minLat, lon);
      canvas.drawLine(p1, p2, gridPaint);
    }
    for (var lat = MapBounds.minLat; lat <= MapBounds.maxLat; lat += 5) {
      final p1 = MapBounds.toOffset(lat, MapBounds.minLon);
      final p2 = MapBounds.toOffset(lat, MapBounds.maxLon);
      canvas.drawLine(p1, p2, gridPaint);
    }
  }

  // Real coastline (Natural Earth 1:50m, clipped to MapBounds — see
  // assets/coastline/README.md). Land/sea colors are a tentative proposal
  // (see _seaColor/_landColor above), still pending the user's sign-off.
  void _drawCoastline(Canvas canvas) {
    if (coastlinePolygons.isEmpty) return;
    final land = Paint()
      ..color = _landColor
      ..style = PaintingStyle.fill;
    final outline = Paint()
      ..color = _landOutlineColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.75;

    for (final polygon in coastlinePolygons) {
      if (polygon.isEmpty) continue;
      final path = Path();
      for (var i = 0; i < polygon.length; i++) {
        final o = MapBounds.toOffset(polygon[i].latitude, polygon[i].longitude);
        if (i == 0) {
          path.moveTo(o.dx, o.dy);
        } else {
          path.lineTo(o.dx, o.dy);
        }
      }
      path.close();
      canvas.drawPath(path, land);
      canvas.drawPath(path, outline);
    }
  }

  void _drawTyphoonTrack(Canvas canvas) {
    if (typhoonForecastTrack.isEmpty) return;
    final trackPaint = Paint()
      ..color = Colors.deepOrange
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    final start = MapBounds.toOffset(typhoonPosition.latitude, typhoonPosition.longitude);
    final path = Path()..moveTo(start.dx, start.dy);
    for (final p in typhoonForecastTrack) {
      final o = MapBounds.toOffset(p.latitude, p.longitude);
      path.lineTo(o.dx, o.dy);
    }
    canvas.drawPath(_dashed(path), trackPaint);

    final markerPaint = Paint()..color = Colors.orange.shade200;
    final markerBorder = Paint()
      ..color = Colors.deepOrange.shade900
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    for (final p in typhoonForecastTrack) {
      final o = MapBounds.toOffset(p.latitude, p.longitude);
      canvas.drawCircle(o, 5, markerPaint);
      canvas.drawCircle(o, 5, markerBorder);
    }
  }

  void _drawDistanceLine(Canvas canvas) {
    final shipOffset = MapBounds.toOffset(shipPosition.latitude, shipPosition.longitude);
    final typhoonOffset = MapBounds.toOffset(typhoonPosition.latitude, typhoonPosition.longitude);
    final dashPaint = Paint()
      ..color = Colors.grey.shade700
      ..strokeWidth = 1.5;
    final path = Path()
      ..moveTo(shipOffset.dx, shipOffset.dy)
      ..lineTo(typhoonOffset.dx, typhoonOffset.dy);
    canvas.drawPath(_dashed(path, dashLength: 4, gapLength: 3), dashPaint);

    final mid = Offset(
      (shipOffset.dx + typhoonOffset.dx) / 2,
      (shipOffset.dy + typhoonOffset.dy) / 2,
    );
    _drawText(
      canvas,
      '${distanceNauticalMiles.round()} nm',
      mid,
      const TextStyle(color: Colors.black87, fontSize: 12, fontWeight: FontWeight.w500),
    );
  }

  // Ship icon: an isosceles triangle whose apex points toward nextWaypoint
  // (2026-07-27 request) instead of always pointing north. The bearing is
  // computed directly in canvas (projected) space rather than on the
  // sphere — fine at this scale, since Web Mercator is conformal (locally
  // angle-preserving), and it keeps this in the same coordinate space as
  // everything else the painter draws.
  void _drawShip(Canvas canvas) {
    final o = MapBounds.toOffset(shipPosition.latitude, shipPosition.longitude);
    final paint = Paint()..color = Colors.blue.shade400;
    final border = Paint()
      ..color = Colors.blue.shade900
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    var angle = 0.0; // radians, clockwise from north (0 = pointing up)
    final next = nextWaypoint;
    if (next != null) {
      final target = MapBounds.toOffset(next.latitude, next.longitude);
      final dx = target.dx - o.dx;
      final dy = target.dy - o.dy;
      if (dx != 0 || dy != 0) {
        angle = math.atan2(dx, -dy);
      }
    }

    final path = Path()
      ..moveTo(0, -8)
      ..lineTo(7, 7)
      ..lineTo(-7, 7)
      ..close();

    canvas.save();
    canvas.translate(o.dx, o.dy);
    canvas.rotate(angle);
    canvas.drawPath(path, paint);
    canvas.drawPath(path, border);
    canvas.restore();

    _drawText(canvas, 'Ship', Offset(o.dx + 10, o.dy - 6),
        const TextStyle(color: Colors.black87, fontSize: 11));
  }

  void _drawTyphoon(Canvas canvas) {
    final o = MapBounds.toOffset(typhoonPosition.latitude, typhoonPosition.longitude);
    final paint = Paint()..color = Colors.red.shade400;
    final border = Paint()
      ..color = Colors.red.shade900
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawCircle(o, 10, paint);
    canvas.drawCircle(o, 10, border);
    _drawText(canvas, 'Typhoon (now)', Offset(o.dx + 12, o.dy - 6),
        const TextStyle(color: Colors.red, fontSize: 11));
  }

  void _drawText(Canvas canvas, String text, Offset offset, TextStyle style) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(canvas, offset);
  }

  Path _dashed(Path source, {double dashLength = 6, double gapLength = 4}) {
    final dashPath = Path();
    for (final metric in source.computeMetrics()) {
      var distance = 0.0;
      var draw = true;
      while (distance < metric.length) {
        final next = distance + (draw ? dashLength : gapLength);
        final clampedNext = next > metric.length ? metric.length : next;
        if (draw) {
          dashPath.addPath(
            metric.extractPath(distance, clampedNext),
            Offset.zero,
          );
        }
        distance = next;
        draw = !draw;
      }
    }
    return dashPath;
  }

  @override
  bool shouldRepaint(covariant MapPainter oldDelegate) {
    return oldDelegate.shipPosition.latitude != shipPosition.latitude ||
        oldDelegate.shipPosition.longitude != shipPosition.longitude ||
        oldDelegate.typhoonPosition.latitude != typhoonPosition.latitude ||
        oldDelegate.typhoonPosition.longitude != typhoonPosition.longitude ||
        oldDelegate.coastlinePolygons.length != coastlinePolygons.length ||
        oldDelegate.shipRoute.length != shipRoute.length ||
        oldDelegate.nextWaypoint?.latitude != nextWaypoint?.latitude ||
        oldDelegate.nextWaypoint?.longitude != nextWaypoint?.longitude;
  }
}
