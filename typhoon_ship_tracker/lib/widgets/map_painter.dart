import 'dart:math' as math;
import 'dart:ui' as ui;

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

  /// Whether to draw the 100nm/200nm distance rings around
  /// [currentPosition] (2026-08-14 request). Off by default; toggled either
  /// from the AppBar's rings menu or by tapping the typhoon's red icon on
  /// the map — both handled by the caller (map_screen.dart), this painter
  /// just draws whatever's set here.
  final bool showRings;

  const TyphoonMarker({
    required this.track,
    required this.pastTrack,
    required this.futureTrack,
    required this.currentPosition,
    required this.label,
    this.pressureLabel,
    this.showRings = false,
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

  /// Ship/typhoon marker icon images (2026-08-xx request: replace the
  /// placeholder triangle/circle with `assets/ship_icon01.png` /
  /// `assets/typhoon_icon01.png`). Loaded once in map_screen.dart
  /// (`loadUiImage`, lib/utils/marker_icons.dart) and passed in here — null
  /// until that load completes, in which case the previous placeholder
  /// shape is drawn instead so the map isn't left blank while the asset
  /// decodes (same "graceful until loaded" pattern as CoastlineData.empty).
  final ui.Image? shipIcon;
  final ui.Image? typhoonIcon;

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
    this.shipIcon,
    this.typhoonIcon,
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

    // The distance readout itself is now drawn together with the ship name
    // label in _drawShip (2026-08-xx request: both stack behind the ship,
    // name innermost / distance outermost), so nothing else to draw here.
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
  // pixel" units instead of "scene/canvas" units.
  //
  // 2026-08-xx: no longer manages its own translate/scale/direction — the
  // caller (_drawShip) already established the ship-local, zoom-corrected
  // canvas space (so this stacks correctly with the name label drawn in the
  // same space) and passes in [behind] (unit direction) and [startDistance]
  // (how far along that direction this box's near edge should start, i.e.
  // past whatever's already stacked closer to the ship).
  void _drawDistanceLabel(Canvas canvas, Offset behind, double startDistance) {
    const style = TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700);
    final painter = TextPainter(
      text: TextSpan(text: '${distanceNauticalMiles.round()} nm', style: style),
      textDirection: TextDirection.ltr,
    )..layout();

    const paddingH = 6.0;
    const paddingV = 3.0;
    final boxWidth = painter.width + paddingH * 2;
    final boxHeight = painter.height + paddingV * 2;
    final diagonal = math.sqrt(boxWidth * boxWidth + boxHeight * boxHeight);
    final localCenter = behind * (startDistance + diagonal / 2);

    final rect = Rect.fromCenter(center: localCenter, width: boxWidth, height: boxHeight);
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(4));

    canvas.drawRRect(rrect, Paint()..color = Colors.blueGrey.shade800.withOpacity(0.9));
    canvas.drawRRect(
      rrect,
      Paint()
        ..color = Colors.white.withOpacity(0.6)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
    painter.paint(canvas, Offset(rect.left + paddingH, rect.top + paddingV));
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

  // Unit vector pointing opposite a typhoon's direction of travel, used to
  // place its designation label "behind" it the same way the ship's name
  // sits behind the ship (2026-08-xx request). Unlike the ship there's no
  // explicit "next waypoint" — direction is inferred from the track itself:
  // prefer the next forecast point just ahead of the current (interpolated)
  // position ([futureTrack]'s second point, since its first point is always
  // the current position — see splitTrackAtTime); if there's no forecast
  // data left (already past the last point), fall back to the most recent
  // leg of [pastTrack]. Falls back to south, matching the ship's own
  // no-data fallback, if there isn't enough track to infer a direction from.
  Offset _typhoonBehindDirection(TyphoonMarker typhoon, Offset currentOffset) {
    if (typhoon.futureTrack.length >= 2) {
      final target = typhoon.futureTrack[1];
      final targetOffset = MapBounds.toOffset(target.latitude, target.longitude);
      final dx = targetOffset.dx - currentOffset.dx;
      final dy = targetOffset.dy - currentOffset.dy;
      final length = math.sqrt(dx * dx + dy * dy);
      if (length > 0) return Offset(-dx / length, -dy / length);
    }
    if (typhoon.pastTrack.length >= 2) {
      final previous = typhoon.pastTrack[typhoon.pastTrack.length - 2];
      final previousOffset = MapBounds.toOffset(previous.latitude, previous.longitude);
      final dx = currentOffset.dx - previousOffset.dx;
      final dy = currentOffset.dy - previousOffset.dy;
      final length = math.sqrt(dx * dx + dy * dy);
      if (length > 0) return Offset(-dx / length, -dy / length);
    }
    return const Offset(0, 1); // south, same no-data fallback as the ship
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
  // Ship icon: assets/ship_icon01.png, bow drawn pointing "up" in the
  // source image — same up-is-north convention the previous placeholder
  // triangle used, so the existing heading-rotation math (angle=0 → apex/
  // bow pointing up) applies unchanged. Anchored not at its own center but
  // at (horizontal center, 15% up from the bottom edge) per the 2026-08-xx
  // request, i.e. near the stern/keel notch visible in the artwork — that
  // point, not the image's bounding-box center, is what's placed at the
  // ship's actual lat/lon and what canvas.rotate below pivots around.
  static const double _shipIconDisplayHeightPx = 26.0;
  static const double _shipIconAnchorXFrac = 0.5;
  static const double _shipIconAnchorYFrac = 0.85; // 15% up from the bottom

  void _drawShip(Canvas canvas) {
    final o = MapBounds.toOffset(shipPosition.latitude, shipPosition.longitude);

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

    canvas.save();
    canvas.translate(o.dx, o.dy);
    canvas.scale(_invZoom);
    canvas.rotate(angle);

    final icon = shipIcon;
    if (icon != null) {
      final displayHeight = _shipIconDisplayHeightPx;
      final displayWidth = displayHeight * icon.width / icon.height;
      final anchorX = displayWidth * _shipIconAnchorXFrac;
      final anchorY = displayHeight * _shipIconAnchorYFrac;
      canvas.drawImageRect(
        icon,
        Rect.fromLTWH(0, 0, icon.width.toDouble(), icon.height.toDouble()),
        Rect.fromLTWH(-anchorX, -anchorY, displayWidth, displayHeight),
        Paint()..filterQuality = FilterQuality.medium,
      );
    } else {
      // Fallback while the icon asset is still decoding (loadUiImage is
      // async) so the map isn't left blank for a frame or two.
      final paint = Paint()..color = Colors.blue.shade400;
      final border = Paint()
        ..color = Colors.blue.shade900
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5;
      final path = Path()
        ..moveTo(0, -8)
        ..lineTo(7, 7)
        ..lineTo(-7, 7)
        ..close();
      canvas.drawPath(path, paint);
      canvas.drawPath(path, border);
    }
    canvas.restore();

    // Ship name + distance-to-typhoon, stacked behind the ship (2026-08-xx
    // request: labels used to sit fixed to the right of the icon; now both
    // always follow the "behind" direction — opposite of the heading toward
    // nextWaypoint, same direction the distance box already used — so they
    // read naturally regardless of which way the ship is heading. Stacked
    // with the name innermost (closer to the ship) and the distance box
    // outermost so the two never overlap. Font size/weight/color for the
    // name are unchanged from before.
    final behind = _shipBehindDirection(o);
    canvas.save();
    canvas.translate(o.dx, o.dy);
    canvas.scale(_invZoom);

    const nameStyle = TextStyle(color: Colors.black87, fontSize: 11, fontWeight: FontWeight.w600);
    final namePainter = TextPainter(
      text: TextSpan(text: shipLabel, style: nameStyle),
      textDirection: TextDirection.ltr,
    )..layout();

    const gap = 14.0; // clearance from the ship icon (icon anchored near the stern, ~5px half-width)
    const stackGap = 4.0; // clearance between the name and the distance box
    final nameDiagonal = math.sqrt(namePainter.width * namePainter.width + namePainter.height * namePainter.height);
    final nameDistance = gap + nameDiagonal / 2;
    final nameCenter = behind * nameDistance;
    namePainter.paint(canvas, nameCenter - Offset(namePainter.width / 2, namePainter.height / 2));

    if (typhoons.isNotEmpty) {
      _drawDistanceLabel(canvas, behind, nameDistance + nameDiagonal / 2 + stackGap);
    }
    canvas.restore();
  }

  // Moving "now" marker + label (designation only, e.g. "11W (NOUL)") at
  // the current slider time, plus — pinned to the track's *first* point
  // rather than following the marker — the central pressure at read time
  // (2026-07-28: "読み込み時の最低気圧は最初の点に残し固定。再生後は「番号
  // （名称）」のみ追従する").
  // 2026-08-03: icon + labels drawn inside translate+scale(1/zoom) blocks
  // (fixed-size request), same treatment as _drawShip.
  // Typhoon icon: assets/typhoon_icon01.png, a square swirl graphic —
  // anchored at its own center (2026-08-xx request), so unlike the ship
  // icon no anchor-fraction offset is needed. Display size chosen close to
  // the previous placeholder circle's diameter (20px, radius 10).
  static const double _typhoonIconDisplaySizePx = 24.0;

  void _drawTyphoonMarker(Canvas canvas, TyphoonMarker typhoon) {
    final o = MapBounds.toOffset(typhoon.currentPosition.latitude, typhoon.currentPosition.longitude);
    _drawTyphoonRings(canvas, typhoon, o);

    // Designation label ("11W (NOUL)") now sits behind the typhoon's
    // direction of travel (2026-08-xx request), same treatment as the ship
    // name — previously fixed to the right of the icon. Font size/weight/
    // color unchanged.
    final behind = _typhoonBehindDirection(typhoon, o);
    canvas.save();
    canvas.translate(o.dx, o.dy);
    canvas.scale(_invZoom);

    final icon = typhoonIcon;
    if (icon != null) {
      const size = _typhoonIconDisplaySizePx;
      canvas.drawImageRect(
        icon,
        Rect.fromLTWH(0, 0, icon.width.toDouble(), icon.height.toDouble()),
        Rect.fromCenter(center: Offset.zero, width: size, height: size),
        Paint()..filterQuality = FilterQuality.medium,
      );
    } else {
      // Fallback while the icon asset is still decoding.
      final paint = Paint()..color = Colors.red.shade400;
      final border = Paint()
        ..color = Colors.red.shade900
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2;
      canvas.drawCircle(Offset.zero, 10, paint);
      canvas.drawCircle(Offset.zero, 10, border);
    }

    const labelStyle = TextStyle(color: Colors.red, fontSize: 11, fontWeight: FontWeight.w600);
    final labelPainter = TextPainter(
      text: TextSpan(text: typhoon.label, style: labelStyle),
      textDirection: TextDirection.ltr,
    )..layout();
    const gap = 14.0; // clearance from the typhoon icon (radius 10)
    final diagonal = math.sqrt(labelPainter.width * labelPainter.width + labelPainter.height * labelPainter.height);
    final labelCenter = behind * (gap + diagonal / 2);
    labelPainter.paint(canvas, labelCenter - Offset(labelPainter.width / 2, labelPainter.height / 2));
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

  // 100nm/200nm distance rings around a typhoon's current position
  // (2026-08-14 request), toggled per-typhoon via [TyphoonMarker.showRings].
  // Colors are an initial pick ("ひとまずお任せ" — user deferred to us),
  // chosen to read clearly against the sea/land/track/marker palette
  // already in use: teal for the inner (100nm) ring, purple for the outer
  // (200nm) one.
  static const _ring100Color = Color(0xFF00897B);
  static const _ring200Color = Color(0xFF6A1B9A);
  static const double _ringStrokeWidthPx = 1.5;

  // Rings are drawn in scene coordinates (so they zoom/pan with the map
  // like the coastline — they represent a real geographic distance, unlike
  // the fixed-size icons/labels), converting nautical miles to canvas
  // pixels via [_pxPerNm]. Their outline thickness and the "100nm"/"200nm"
  // labels are still fixed-size on screen, same treatment as the other
  // labels (translate+scale(1/zoom)).
  void _drawTyphoonRings(Canvas canvas, TyphoonMarker typhoon, Offset center) {
    if (!typhoon.showRings) return;
    final pxPerNm = _pxPerNm(typhoon.currentPosition.latitude);
    _drawRing(canvas, center, 100 * pxPerNm, _ring100Color, '100nm');
    _drawRing(canvas, center, 200 * pxPerNm, _ring200Color, '200nm');
  }

  // Canvas pixels per nautical mile at [latDeg] — a single scalar since Web
  // Mercator is conformal (locally the same scale factor in every
  // direction), derived from the fixed canvas-px-per-longitude-degree scale
  // and the standard "1 degree of longitude = 60nm × cos(lat)" relation
  // (verified against the y-axis derivative of MapBounds' Mercator formula
  // giving the same result, as expected for a conformal projection).
  double _pxPerNm(double latDeg) {
    final pxPerLonDeg = MapBounds.canvasWidth / (MapBounds.maxLon - MapBounds.minLon);
    final latRad = latDeg * math.pi / 180;
    return pxPerLonDeg / (60 * math.cos(latRad));
  }

  // Draws one ring (outline only, no fill, so it doesn't obscure the map)
  // plus its "100nm"/"200nm" label just outside the ring at the top
  // (12 o'clock) — simple, predictable placement that doesn't need to
  // reason about the typhoon's heading the way the designation label does.
  void _drawRing(Canvas canvas, Offset center, double radiusScene, Color color, String label) {
    final paint = Paint()
      ..color = color.withOpacity(0.85)
      ..style = PaintingStyle.stroke
      ..strokeWidth = _ringStrokeWidthPx * _invZoom;
    canvas.drawCircle(center, radiusScene, paint);

    final labelStyle = TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.w600);
    final painter = TextPainter(
      text: TextSpan(text: label, style: labelStyle),
      textDirection: TextDirection.ltr,
    )..layout();
    final topPoint = Offset(center.dx, center.dy - radiusScene);
    canvas.save();
    canvas.translate(topPoint.dx, topPoint.dy);
    canvas.scale(_invZoom);
    painter.paint(canvas, Offset(-painter.width / 2, -painter.height - 2));
    canvas.restore();
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
        oldDelegate.shipIcon != shipIcon ||
        oldDelegate.typhoonIcon != typhoonIcon ||
        oldDelegate.typhoons.length != typhoons.length ||
        _typhoonsChanged(oldDelegate.typhoons);
  }

  bool _typhoonsChanged(List<TyphoonMarker> old) {
    for (var i = 0; i < typhoons.length && i < old.length; i++) {
      if (old[i].label != typhoons[i].label ||
          old[i].pressureLabel != typhoons[i].pressureLabel ||
          old[i].showRings != typhoons[i].showRings ||
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
