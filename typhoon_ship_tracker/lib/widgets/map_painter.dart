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

  MapPainter({
    required this.shipPosition,
    required this.shipRoute,
    required this.typhoonPosition,
    required this.typhoonForecastTrack,
    required this.distanceNauticalMiles,
    this.coastlinePolygons = const [],
  });

  @override
  void paint(Canvas canvas, Size size) {
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
      ..color = Colors.blue.shade300
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

  void _drawGrid(Canvas canvas) {
    final gridPaint = Paint()
      ..color = Colors.grey.withOpacity(0.4)
      ..strokeWidth = 1;
    final textStyle = TextStyle(color: Colors.grey.shade700, fontSize: 11);

    for (var lon = MapBounds.minLon; lon <= MapBounds.maxLon; lon += 5) {
      final p1 = MapBounds.toOffset(MapBounds.maxLat, lon);
      final p2 = MapBounds.toOffset(MapBounds.minLat, lon);
      canvas.drawLine(p1, p2, gridPaint);
      _drawText(canvas, '${lon.round()}E', Offset(p1.dx + 2, 2), textStyle);
    }
    for (var lat = MapBounds.minLat; lat <= MapBounds.maxLat; lat += 5) {
      final p1 = MapBounds.toOffset(lat, MapBounds.minLon);
      final p2 = MapBounds.toOffset(lat, MapBounds.maxLon);
      canvas.drawLine(p1, p2, gridPaint);
      _drawText(canvas, '${lat.round()}N', Offset(2, p1.dy + 2), textStyle);
    }
  }

  // Real coastline (Natural Earth 1:110m, clipped to MapBounds — see
  // assets/coastline/README.md). Land/sea colors are placeholders pending
  // the color discussion noted in TASKS.md.
  void _drawCoastline(Canvas canvas) {
    if (coastlinePolygons.isEmpty) return;
    final land = Paint()
      ..color = Colors.grey.shade400
      ..style = PaintingStyle.fill;
    final outline = Paint()
      ..color = Colors.grey.shade600
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

  void _drawShip(Canvas canvas) {
    final o = MapBounds.toOffset(shipPosition.latitude, shipPosition.longitude);
    final paint = Paint()..color = Colors.blue.shade400;
    final border = Paint()
      ..color = Colors.blue.shade900
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final path = Path()
      ..moveTo(o.dx, o.dy - 8)
      ..lineTo(o.dx + 7, o.dy + 7)
      ..lineTo(o.dx - 7, o.dy + 7)
      ..close();
    canvas.drawPath(path, paint);
    canvas.drawPath(path, border);
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
        oldDelegate.shipRoute.length != shipRoute.length;
  }
}
