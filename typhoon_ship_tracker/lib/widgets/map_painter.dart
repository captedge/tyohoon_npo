import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../utils/interpolation.dart';
import '../utils/map_bounds.dart';

/// One typhoon to draw (2026-07-28 request: this area can have more than
/// one active typhoon at once, up to 3).
///
/// Modeled after the ship: [track] is the *entire* chronological track
/// (like [MapPainter.shipRoute]) and is drawn persistently — with markers at
/// every point regardless of the time slider ("台風の軌跡は船のように残して
/// ください", 2026-07-28) — split into [pastTrack] (already elapsed, drawn
/// solid) and [futureTrack] (still ahead, drawn dotted; 2026-08-03 request).
/// Both halves share the interpolated point at the current slider time as
/// their boundary — see `splitTrackAtTime` in `lib/utils/interpolation.dart`.
/// [currentPosition] is that same interpolated position and is drawn as the
/// moving marker, labeled with [label] (just the designation, e.g.
/// "11W (NOUL)" — no pressure, no "(now)", since those don't make sense
/// once the time slider has moved away from when the warning was read).
/// [pressureLabel] is the central pressure *at read time*, pinned to
/// `track.first` rather than following [currentPosition] — it was only
/// ever measured at that one point in time.
class TyphoonMarker {
  final List<LatLng> track;
  final List<LatLng> pastTrack;
  final List<LatLng> futureTrack;
  final LatLng currentPosition;
  final String label;
  final String? pressureLabel;

  const TyphoonMarker({
    required this.track,
    required this.pastTrack,
    required this.futureTrack,
    required this.currentPosition,
    required this.label,
    this.pressureLabel,
  });
}

/// Draws the simplified plot map: a lat/lon grid, coastline, the typhoon
/// tracks, and the ship/typhoon markers with a distance line between the
/// ship and the first (primary) typhoon.
///
/// Always paints into a canvas sized [MapBounds.canvasSize] (see that
/// class for why) — the `size` passed to [paint] should match it.
class MapPainter extends CustomPainter {
  final LatLng shipPosition;

  /// Every waypoint of the voyage plan, past and future — used only to draw
  /// the small dot marker at each waypoint. The line itself is drawn from
  /// [shipPastRoute]/[shipFutureRoute] instead (2026-08-03 split).
  final List<LatLng> shipRoute;

  /// Portion of [shipRoute] already sailed (drawn solid) / not yet reached
  /// (drawn dotted) — see `splitTrackAtTime`. Both share the current
  /// interpolated ship position as their boundary point.
  final List<LatLng> shipPastRoute;
  final List<LatLng> shipFutureRoute;

  final double distanceNauticalMiles;
  final List<List<LatLng>> coastlinePolygons;

  /// Current map zoom (InteractiveViewer's scale). Used to counter-scale
  /// point markers (ship/typhoon icons, waypoint dots) and text labels by
  /// 1/zoom so they stay a constant size on screen regardless of how far
  /// zoomed in/out the map is (2026-08-03 request: these "objects" were
  /// scaling with the map and became oversized at high zoom). Route/track
  /// *lines* intentionally keep scaling with the map — only point markers
  /// and labels are fixed-size.
  final double zoom;

  double get _invZoom => zoom > 0 ? 1 / zoom : 1.0;

  /// The next waypoint ahead of [shipPosition] in time, used so the ship
  /// icon's apex points toward it (2026-07-27 request) instead of always
  /// pointing north. Null once the voyage is complete (no waypoint left
  /// ahead) or if there's only a single track point — the icon then falls
  /// back to pointing north.
  final LatLng? nextWaypoint;

  /// Label drawn next to the ship icon (2026-07-28 request: user-entered
  /// "Ship's Name" instead of the generic "Ship", since NAVTOR-format
  /// voyage-plan CSVs don't carry a ship name field). Defaults to 'Ship'
  /// when the user hasn't set one.
  final String shipLabel;

  /// Whether to draw the ship at all (route, marker, label) — 2026-07-28
  /// "Display" checkbox request.
  final bool showShip;

  /// Up to 3 typhoons (2026-07-28 request), already filtered to "Display
  /// checkbox on" and "has at least a current position" by the caller —
  /// this painter just draws whatever's in the list, in order. The distance
  /// line/readout (when [showShip] is also true) measures to `typhoons.first`.
  final List<TyphoonMarker> typhoons;

  MapPainter({
    required this.shipPosition,
    required this.shipRoute,
    required this.shipPastRoute,
    required this.shipFutureRoute,
    required this.distanceNauticalMiles,
    this.coastlinePolygons = const [],
    this.nextWaypoint,
    this.shipLabel = 'Ship',
    this.showShip = true,
    this.typhoons = const [],
    this.zoom = 1.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    _drawSea(canvas, size);
    _drawGrid(canvas);
    _drawCoastline(canvas);
    if (showShip) _drawShipRoute(canvas);
    for (final typhoon in typhoons) {
      _drawTyphoonTrack(canvas, typhoon);
    }
    if (showShip && typhoons.isNotEmpty) {
      _drawDistanceLine(canvas, typhoons.first.currentPosition);
    }
    if (showShip) _drawShip(canvas);
    for (final typhoon in typhoons) {
      _drawTyphoonMarker(canvas, typhoon);
    }
  }

  // Planned route, split at the current slider time (2026-08-03): the
  // already-sailed portion (shipPastRoute) as a solid line, the remaining
  // portion (shipFutureRoute) as a dotted line — plus a small fixed-size dot
  // marker at every waypoint (past and future alike). The current ship
  // position is drawn separately, on top, by _drawShip.
  void _drawShipRoute(Canvas canvas) {
    if (shipRoute.length < 2) return;
    _drawPolyline(canvas, shipPastRoute, Colors.blue.shade600, dashed: false);
    _drawPolyline(canvas, shipFutureRoute, Colors.blue.shade600, dashed: true);

    final wptPaint = Paint()..color = Colors.blue.shade100;
    final wptBorder = Paint()
      ..color = Colors.blue.shade700
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    for (final p in shipRoute) {
      _drawFixedCircle(canvas, MapBounds.toOffset(p.latitude, p.longitude), 3.5, wptPaint, wptBorder);
    }
  }

  // Shared solid/dashed line thickness for both the ship route and typhoon
  // track (2026-08-03 request: "船と台風の実線/点線太さを揃えて") — in
  // fixed on-screen pixels, same as [_drawFixedCircle]/labels (see
  // strokeWidth handling below), not scene units.
  static const double _trackStrokeWidthPx = 2.0;

  // Shared dotted-line pattern for both the ship route and typhoon track
  // (2026-08-03 request: "点線の一つ一つの長さと間隔も揃えてください...今の
  // 船より少し細かいぐらいで" — finer than the ship's previous 4/3 pattern,
  // and unified with the typhoon track's previously-different default 6/4).
  static const double _trackDashLengthPx = 3.0;
  static const double _trackGapLengthPx = 2.0;

  // Draws [points] as a connected line (solid or dotted) in map/scene
  // coordinates (endpoints move/scale with pan/zoom like the rest of the
  // map) but with a stroke width that stays a constant on-screen thickness
  // regardless of zoom (2026-08-03 request) — achieved by setting the
  // Paint's strokeWidth to the desired screen pixels × 1/zoom, so that once
  // InteractiveViewer scales this whole canvas by `zoom`, the rendered
  // thickness comes back out to the desired screen pixel value. Shared by
  // the ship route and typhoon track.
  void _drawPolyline(
    Canvas canvas,
    List<LatLng> points,
    Color color, {
    required bool dashed,
    double strokeWidthPx = _trackStrokeWidthPx,
    double dashLength = _trackDashLengthPx,
    double gapLength = _trackGapLengthPx,
  }) {
    if (points.length < 2) return;
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidthPx * _invZoom
      ..style = PaintingStyle.stroke;
    final path = Path();
    for (var i = 0; i < points.length; i++) {
      final o = MapBounds.toOffset(points[i].latitude, points[i].longitude);
      if (i == 0) {
        path.moveTo(o.dx, o.dy);
      } else {
        path.lineTo(o.dx, o.dy);
      }
    }
    canvas.drawPath(dashed ? _dashed(path, dashLength: dashLength, gapLength: gapLength) : path, paint);
  }

  // Draws a small filled+outlined circle at [center] whose on-screen size
  // stays constant regardless of the map's current zoom (2026-08-03
  // request) — achieved by translating to the marker's position and scaling
  // by 1/zoom, canceling out the ambient zoom InteractiveViewer applies to
  // this whole canvas.
  void _drawFixedCircle(Canvas canvas, Offset center, double radius, Paint fill, Paint border) {
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.scale(_invZoom);
    canvas.drawCircle(Offset.zero, radius, fill);
    canvas.drawCircle(Offset.zero, radius, border);
    canvas.restore();
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

  // Full typhoon track (past and future, like _drawShipRoute), split at the
  // current slider time (2026-08-03): elapsed portion solid, remaining
  // forecast dotted — plus fixed-size marker dots at every point
  // (2026-07-28: "台風の軌跡：船のように残してください" — previously this
  // only drew the *remaining* forecast points, hiding the track behind the
  // moving marker). The moving "now" marker + label is drawn separately, on
  // top, by _drawTyphoonMarker.
  void _drawTyphoonTrack(Canvas canvas, TyphoonMarker typhoon) {
    if (typhoon.track.length < 2) return;
    _drawPolyline(canvas, typhoon.pastTrack, Colors.deepOrange, dashed: false);
    _drawPolyline(canvas, typhoon.futureTrack, Colors.deepOrange, dashed: true);

    final markerPaint = Paint()..color = Colors.orange.shade200;
    final markerBorder = Paint()
      ..color = Colors.deepOrange.shade900
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    for (final p in typhoon.track) {
      _drawFixedCircle(canvas, MapBounds.toOffset(p.latitude, p.longitude), 5, markerPaint, markerBorder);
    }
  }

  void _drawDistanceLine(Canvas canvas, LatLng typhoonPosition) {
    final shipOffset = MapBounds.toOffset(shipPosition.latitude, shipPosition.longitude);
    final typhoonOffset = MapBounds.toOffset(typhoonPosition.latitude, typhoonPosition.longitude);
    final dashPaint = Paint()
      ..color = Colors.grey.shade700
      ..strokeWidth = 1.5;
    final path = Path()
      ..moveTo(shipOffset.dx, shipOffset.dy)
      ..lineTo(typhoonOffset.dx, typhoonOffset.dy);
    canvas.drawPath(_dashed(path, dashLength: 4, gapLength: 3), dashPaint);

    _drawDistanceLabel(canvas, shipOffset);
  }

  // Distance readout, pinned behind the ship — i.e. the opposite direction
  // from its heading toward nextWaypoint (2026-07-28 request: a fixed
  // "always to the left" position looked wrong once the ship is sailing
  // west, since "left" then points into its direction of travel). Distance
  // from the ship, box size, and colors are unchanged from the previous
  // left-side version — only which side it sits on now follows the heading.
  //
  // 2026-08-03: drawn inside a translate+scale(1/zoom) block (fixed-size
  // request) so the box/text/gap stay a constant on-screen size regardless
  // of map zoom — all the pixel math below (paddingH/paddingV/gap/box size)
  // is unchanged from before and is now simply interpreted in "screen
  // pixel" units instead of "scene/canvas" units. The *direction* (behind)
  // is still computed from the real (non-fixed-scale) scene offsets, since
  // that's a geometry question, not a sizing one.
  void _drawDistanceLabel(Canvas canvas, Offset shipOffset) {
    const style = TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700);
    final painter = TextPainter(
      text: TextSpan(text: '${distanceNauticalMiles.round()} nm', style: style),
      textDirection: TextDirection.ltr,
    )..layout();

    const paddingH = 6.0;
    const paddingV = 3.0;
    const gap = 12.0; // clearance from the ship icon (icon half-width ~7)
    final boxWidth = painter.width + paddingH * 2;
    final boxHeight = painter.height + paddingV * 2;

    // Offset the box center along the "behind" direction by gap + half the
    // box's diagonal, so the box clears the ship icon for any heading angle
    // (not just left/right) instead of only being edge-aligned for one
    // fixed direction.
    final behind = _shipBehindDirection(shipOffset);
    final offsetDistance = gap + math.sqrt(boxWidth * boxWidth + boxHeight * boxHeight) / 2;
    final localCenter = behind * offsetDistance;

    final rect = Rect.fromCenter(center: localCenter, width: boxWidth, height: boxHeight);
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(4));

    canvas.save();
    canvas.translate(shipOffset.dx, shipOffset.dy);
    canvas.scale(_invZoom);
    canvas.drawRRect(rrect, Paint()..color = Colors.blueGrey.shade800.withOpacity(0.9));
    canvas.drawRRect(
      rrect,
      Paint()
        ..color = Colors.white.withOpacity(0.6)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
    painter.paint(canvas, Offset(rect.left + paddingH, rect.top + paddingV));
    canvas.restore();
  }

  // Unit vector pointing opposite the ship's heading toward nextWaypoint —
  // the same heading _drawShip rotates its icon toward, just reversed and
  // normalized here since this needs a direction to offset along rather
  // than a rotation angle. Falls back to south (opposite of the default
  // north-pointing icon) when there's no next waypoint, matching _drawShip's
  // own fallback for that case.
  Offset _shipBehindDirection(Offset shipOffset) {
    final next = nextWaypoint;
    if (next != null) {
      final target = MapBounds.toOffset(next.latitude, next.longitude);
      final dx = target.dx - shipOffset.dx;
      final dy = target.dy - shipOffset.dy;
      final length = math.sqrt(dx * dx + dy * dy);
      if (length > 0) {
        return Offset(-dx / length, -dy / length);
      }
    }
    return const Offset(0, 1); // south, opposite the default north-pointing icon
  }

  // Ship icon: an isosceles triangle whose apex points toward nextWaypoint
  // (2026-07-27 request) instead of always pointing north. The bearing is
  // computed directly in canvas (projected) space rather than on the
  // sphere — fine at this scale, since Web Mercator is conformal (locally
  // angle-preserving), and it keeps this in the same coordinate space as
  // everything else the painter draws.
  //
  // 2026-08-03: both the icon and its label are drawn inside a
  // translate+scale(1/zoom) block (fixed-size request) so they stay a
  // constant on-screen size at any map zoom, instead of growing/shrinking
  // with it. The heading angle itself is still computed from the real
  // (non-fixed-scale) scene offsets — a geometry question, not a sizing one.
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
    canvas.scale(_invZoom);
    canvas.rotate(angle);
    canvas.drawPath(path, paint);
    canvas.drawPath(path, border);
    canvas.restore();

    canvas.save();
    canvas.translate(o.dx, o.dy);
    canvas.scale(_invZoom);
    _drawText(canvas, shipLabel, const Offset(10, -6),
        const TextStyle(color: Colors.black87, fontSize: 11, fontWeight: FontWeight.w600));
    canvas.restore();
  }

  // Moving "now" marker + label (designation only, e.g. "11W (NOUL)") at
  // the current slider time, plus — pinned to the track's *first* point
  // rather than following the marker — the central pressure at read time
  // (2026-07-28: "読み込み時の最低気圧は最初の点に残し固定。再生後は「番号
  // （名称）」のみ追従する").
  // 2026-08-03: icon + labels drawn inside translate+scale(1/zoom) blocks
  // (fixed-size request), same treatment as _drawShip.
  void _drawTyphoonMarker(Canvas canvas, TyphoonMarker typhoon) {
    final o = MapBounds.toOffset(typhoon.currentPosition.latitude, typhoon.currentPosition.longitude);
    final paint = Paint()..color = Colors.red.shade400;
    final border = Paint()
      ..color = Colors.red.shade900
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    canvas.save();
    canvas.translate(o.dx, o.dy);
    canvas.scale(_invZoom);
    canvas.drawCircle(Offset.zero, 10, paint);
    canvas.drawCircle(Offset.zero, 10, border);
    _drawText(canvas, typhoon.label, const Offset(12, -6),
        const TextStyle(color: Colors.red, fontSize: 11, fontWeight: FontWeight.w600));
    canvas.restore();

    final pressureLabel = typhoon.pressureLabel;
    if (pressureLabel != null && typhoon.track.isNotEmpty) {
      final start = typhoon.track.first;
      final startOffset = MapBounds.toOffset(start.latitude, start.longitude);
      canvas.save();
      canvas.translate(startOffset.dx, startOffset.dy);
      canvas.scale(_invZoom);
      _drawText(canvas, pressureLabel, const Offset(12, 8),
          TextStyle(color: Colors.deepOrange.shade900, fontSize: 10, fontWeight: FontWeight.w600));
      canvas.restore();
    }
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
        oldDelegate.coastlinePolygons.length != coastlinePolygons.length ||
        oldDelegate.shipRoute.length != shipRoute.length ||
        oldDelegate.shipPastRoute.length != shipPastRoute.length ||
        oldDelegate.shipFutureRoute.length != shipFutureRoute.length ||
        oldDelegate.nextWaypoint?.latitude != nextWaypoint?.latitude ||
        oldDelegate.nextWaypoint?.longitude != nextWaypoint?.longitude ||
        oldDelegate.shipLabel != shipLabel ||
        oldDelegate.showShip != showShip ||
        oldDelegate.zoom != zoom ||
        oldDelegate.typhoons.length != typhoons.length ||
        _typhoonsChanged(oldDelegate.typhoons);
  }

  bool _typhoonsChanged(List<TyphoonMarker> old) {
    for (var i = 0; i < typhoons.length && i < old.length; i++) {
      if (old[i].label != typhoons[i].label ||
          old[i].pressureLabel != typhoons[i].pressureLabel ||
          old[i].track.length != typhoons[i].track.length ||
          old[i].pastTrack.length != typhoons[i].pastTrack.length ||
          old[i].futureTrack.length != typhoons[i].futureTrack.length ||
          old[i].currentPosition.latitude != typhoons[i].currentPosition.latitude ||
          old[i].currentPosition.longitude != typhoons[i].currentPosition.longitude) {
        return true;
      }
    }
    return false;
  }
}
