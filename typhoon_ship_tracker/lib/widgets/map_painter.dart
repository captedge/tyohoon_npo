import 'package:flutter/material.dart';

import '../utils/interpolation.dart';
import '../utils/map_bounds.dart';

/// Draws the simplified plot map: a lat/lon grid, placeholder coastlines,
/// the typhoon forecast track, and the ship/typhoon markers with a distance
/// line between them.
///
/// The coastline shapes here are rough placeholders (see TODO below) — they
/// exist only to confirm the layout. Replace with real coastline data
/// (Natural Earth, clipped to MapBounds) before shipping.
class MapPainter extends CustomPainter {
  final LatLng shipPosition;
  final List<LatLng> shipRoute;
  final LatLng typhoonPosition;
  final List<LatLng> typhoonForecastTrack;
  final double distanceNauticalMiles;

  MapPainter({
    required this.shipPosition,
    required this.shipRoute,
    required this.typhoonPosition,
    required this.typhoonForecastTrack,
    required this.distanceNauticalMiles,
  });

  @override
  void paint(Canvas canvas, Size size) {
    _drawGrid(canvas, size);
    _drawPlaceholderCoastlines(canvas, size);
    _drawShipRoute(canvas, size);
    _drawTyphoonTrack(canvas, size);
    _drawDistanceLine(canvas, size);
    _drawShip(canvas, size);
    _drawTyphoon(canvas, size);
  }

  // Full planned route (all waypoints, past and future) as a dotted line
  // with small markers at each waypoint. The current ship position is drawn
  // separately, on top, by _drawShip.
  void _drawShipRoute(Canvas canvas, Size size) {
    if (shipRoute.length < 2) return;
    final routePaint = Paint()
      ..color = Colors.blue.shade300
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    final path = Path();
    for (var i = 0; i < shipRoute.length; i++) {
      final o = MapBounds.toOffset(shipRoute[i].latitude, shipRoute[i].longitude, size);
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
      final o = MapBounds.toOffset(p.latitude, p.longitude, size);
      canvas.drawCircle(o, 3.5, wptPaint);
      canvas.drawCircle(o, 3.5, wptBorder);
    }
  }

  void _drawGrid(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = Colors.grey.withOpacity(0.4)
      ..strokeWidth = 1;
    final textStyle = TextStyle(color: Colors.grey.shade700, fontSize: 11);

    for (var lon = MapBounds.minLon; lon <= MapBounds.maxLon; lon += 5) {
      final p1 = MapBounds.toOffset(MapBounds.maxLat, lon, size);
      final p2 = MapBounds.toOffset(MapBounds.minLat, lon, size);
      canvas.drawLine(p1, p2, gridPaint);
      _drawText(canvas, '${lon.round()}E', Offset(p1.dx + 2, 2), textStyle);
    }
    for (var lat = MapBounds.minLat; lat <= MapBounds.maxLat; lat += 5) {
      final p1 = MapBounds.toOffset(lat, MapBounds.minLon, size);
      final p2 = MapBounds.toOffset(lat, MapBounds.maxLon, size);
      canvas.drawLine(p1, p2, gridPaint);
      _drawText(canvas, '${lat.round()}N', Offset(2, p1.dy + 2), textStyle);
    }
  }

  // TODO(map-data): replace with real coastline polygons clipped to
  // MapBounds (Natural Earth or similar free dataset). These shapes are
  // rough placeholders only, sized to roughly match Japan/Korea/China/
  // Taiwan/Philippines for layout purposes.
  void _drawPlaceholderCoastlines(Canvas canvas, Size size) {
    final land = Paint()..color = Colors.grey.shade400;
    Offset o(double lat, double lon) => MapBounds.toOffset(lat, lon, size);

    final japan = Path()
      ..moveTo(o(45, 144).dx, o(45, 144).dy)
      ..lineTo(o(43, 146).dx, o(43, 146).dy)
      ..lineTo(o(40, 142).dx, o(40, 142).dy)
      ..lineTo(o(37, 140).dx, o(37, 140).dy)
      ..lineTo(o(35, 138).dx, o(35, 138).dy)
      ..lineTo(o(34, 136).dx, o(34, 136).dy)
      ..lineTo(o(33, 134).dx, o(33, 134).dy)
      ..lineTo(o(32, 131).dx, o(32, 131).dy)
      ..lineTo(o(33, 129).dx, o(33, 129).dy)
      ..lineTo(o(35, 130).dx, o(35, 130).dy)
      ..lineTo(o(37, 133).dx, o(37, 133).dy)
      ..lineTo(o(39, 136).dx, o(39, 136).dy)
      ..lineTo(o(42, 139).dx, o(42, 139).dy)
      ..lineTo(o(44, 142).dx, o(44, 142).dy)
      ..close();
    canvas.drawPath(japan, land);

    final korea = Path()
      ..moveTo(o(38, 124.5).dx, o(38, 124.5).dy)
      ..lineTo(o(38.5, 126.5).dx, o(38.5, 126.5).dy)
      ..lineTo(o(37, 129).dx, o(37, 129).dy)
      ..lineTo(o(35, 129.5).dx, o(35, 129.5).dy)
      ..lineTo(o(34.2, 127).dx, o(34.2, 127).dy)
      ..lineTo(o(35, 125).dx, o(35, 125).dy)
      ..lineTo(o(36.5, 124.5).dx, o(36.5, 124.5).dy)
      ..close();
    canvas.drawPath(korea, land);

    final china = Path()
      ..moveTo(o(46, 115).dx, o(46, 115).dy)
      ..lineTo(o(46, 122).dx, o(46, 122).dy)
      ..lineTo(o(40, 121).dx, o(40, 121).dy)
      ..lineTo(o(36, 119).dx, o(36, 119).dy)
      ..lineTo(o(32, 120).dx, o(32, 120).dy)
      ..lineTo(o(28, 118).dx, o(28, 118).dy)
      ..lineTo(o(24, 115).dx, o(24, 115).dy)
      ..lineTo(o(5, 115).dx, o(5, 115).dy)
      ..lineTo(o(46, 115).dx, o(46, 115).dy)
      ..close();
    canvas.drawPath(china, land);

    canvas.drawOval(
      Rect.fromCenter(
        center: o(23.5, 121),
        width: (o(23.5, 122).dx - o(23.5, 120).dx).abs(),
        height: (o(25.5, 121).dy - o(22, 121).dy).abs(),
      ),
      land,
    );

    final luzon = Path()
      ..moveTo(o(19, 121).dx, o(19, 121).dy)
      ..lineTo(o(17, 122).dx, o(17, 122).dy)
      ..lineTo(o(14, 121.5).dx, o(14, 121.5).dy)
      ..lineTo(o(13, 120).dx, o(13, 120).dy)
      ..lineTo(o(15, 119.5).dx, o(15, 119.5).dy)
      ..lineTo(o(18, 120).dx, o(18, 120).dy)
      ..close();
    canvas.drawPath(luzon, land);

    canvas.drawOval(
      Rect.fromCenter(center: o(11, 123.5), width: 60, height: 44),
      land,
    );
    canvas.drawOval(
      Rect.fromCenter(center: o(8, 125), width: 90, height: 80),
      land,
    );
  }

  void _drawTyphoonTrack(Canvas canvas, Size size) {
    if (typhoonForecastTrack.isEmpty) return;
    final trackPaint = Paint()
      ..color = Colors.deepOrange
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    final path = Path()
      ..moveTo(
        MapBounds.toOffset(typhoonPosition.latitude, typhoonPosition.longitude, size).dx,
        MapBounds.toOffset(typhoonPosition.latitude, typhoonPosition.longitude, size).dy,
      );
    for (final p in typhoonForecastTrack) {
      final o = MapBounds.toOffset(p.latitude, p.longitude, size);
      path.lineTo(o.dx, o.dy);
    }
    canvas.drawPath(_dashed(path), trackPaint);

    final markerPaint = Paint()..color = Colors.orange.shade200;
    final markerBorder = Paint()
      ..color = Colors.deepOrange.shade900
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    for (final p in typhoonForecastTrack) {
      final o = MapBounds.toOffset(p.latitude, p.longitude, size);
      canvas.drawCircle(o, 5, markerPaint);
      canvas.drawCircle(o, 5, markerBorder);
    }
  }

  void _drawDistanceLine(Canvas canvas, Size size) {
    final shipOffset = MapBounds.toOffset(shipPosition.latitude, shipPosition.longitude, size);
    final typhoonOffset = MapBounds.toOffset(typhoonPosition.latitude, typhoonPosition.longitude, size);
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

  void _drawShip(Canvas canvas, Size size) {
    final o = MapBounds.toOffset(shipPosition.latitude, shipPosition.longitude, size);
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

  void _drawTyphoon(Canvas canvas, Size size) {
    final o = MapBounds.toOffset(typhoonPosition.latitude, typhoonPosition.longitude, size);
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
        oldDelegate.typhoonPosition.longitude != typhoonPosition.longitude;
  }
}
