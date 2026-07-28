import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../utils/interpolation.dart';
import '../utils/map_bounds.dart';

/// One typhoon to draw (2026-07-28 request: this area can have more than
/// one active typhoon at once, up to 3).
///
/// Modeled after the ship: [track] is the *entire* chronological track
/// (like [ShipMarker.route]) and is drawn persistently — with markers at
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

  /// Valid time for each point in [track], same length/order as [track]
  /// (2026-07-27 request: show each forecast point's time — e.g. JTWC's
  /// "270600Z" — as "27/15" (day/hour, JST) next to its circle). These are
  /// already JST wall-clock values by the time they reach this painter: the
  /// caller (map_screen.dart) builds every [TrackPoint.time] as an offset
  /// from `_startTime`, which is itself resolved from the warning's
  /// "DDHHMMZ" line via [JtwcTyphoonInfo.issuedAtJst] (UTC→JST, +9h) — so
  /// reading `.day`/`.hour` directly here (no further conversion) gives the
  /// correct JST day/hour, consistent with how every other DateTime in this
  /// app is treated as a plain wall-clock value (see issuedAtJst's doc
  /// comment for why `DateTime.utc(...)` is deliberately avoided app-wide).
  final List<DateTime> trackTimes;

  /// Whether to draw the 100nm/200nm distance rings around
  /// [currentPosition] (2026-08-14 request). Off by default; toggled either
  /// from the AppBar's rings menu or by tapping the typhoon's red icon on
  /// the map — both handled by the caller (map_screen.dart), this painter
  /// just draws whatever's set here.
  final bool showRings;

  /// Per-source color (2026-07-28 request: "気象庁と米軍の予報を両方表示...
  /// 色分けをする...米軍であれば赤" — JTWC and JMA can now both be displayed
  /// at once per typhoon slot, so each needs a distinct color to stay
  /// readable). Assigned by the caller (map_screen.dart's `_jtwcColor`/
  /// `_jmaColor`) and used for this typhoon's track line, marker dots, icon
  /// tint, designation label, and pressure label — plus, on the ship side,
  /// the matching distance-line/readout color (see [ShipTyphoonDistance]).
  final Color color;

  const TyphoonMarker({
    required this.track,
    required this.pastTrack,
    required this.futureTrack,
    required this.currentPosition,
    required this.label,
    this.pressureLabel,
    this.showRings = false,
    this.trackTimes = const [],
    this.color = Colors.deepOrange,
  });
}

/// One ship's distance to one currently-displayed typhoon marker, colored to
/// match that typhoon's own [TyphoonMarker.color] so the reading is
/// traceable to its source at a glance (2026-07-28 request: "船との距離は
/// 上記表示のOn/Offで表示し、同じ色とする"). A [ShipMarker] carries one of
/// these per currently-displayed typhoon (see [ShipMarker.typhoonDistances]) —
/// zero when none are displayed, more than one when e.g. both JTWC and JMA
/// are shown for the same slot at once.
class ShipTyphoonDistance {
  final double distanceNm;
  final Color color;

  const ShipTyphoonDistance({required this.distanceNm, required this.color});
}

/// One ship/route to draw — either the single fallback sample track, or one
/// entry per Display-on registered Passage Plan (2026-08-xx request: compare
/// multiple route options from the same departure port/time to different
/// destinations, each running fully independently — *not* concatenated into
/// one combined track like an earlier, since-reverted design attempted for a
/// different use case).
///
/// Modeled after [TyphoonMarker]: [route] is the whole track (past+future,
/// for the waypoint dots), split into [pastRoute] (solid) / [futureRoute]
/// (dotted) at the current slider time, sharing the interpolated
/// [position] as their boundary. [label] is the user-entered "Ship's Name"
/// (Information dialog) — the *same* text on every [ShipMarker], since these
/// represent route *options* for one physical ship, not separate vessels
/// (2026-08-xx revision: this used to carry the Passage Plan's own name, but
/// that moved to a dedicated on-screen legend — see map_screen.dart's
/// Passage Plan legend overlay — so routes are told apart by [color] alone
/// there, freeing this label to show the ship's actual name instead). Empty
/// when the user hasn't entered a name, in which case the painter simply
/// skips drawing it (no empty box reserving space behind the ship).
/// [typhoonDistances] is this ship's own distance to every currently-
/// displayed typhoon marker at the current time, *grouped by typhoon slot*
/// (2026-07-29 revision: previously a flat `List<ShipTyphoonDistance>` drawn
/// one after another, further and further behind the ship — including JTWC
/// and JMA of the *same* typhoon, which read oddly as two separate stops
/// instead of a pair. Now one inner list per slot — 1 entry when only one
/// source is displayed for that typhoon, 2 when both JTWC and JMA are —
/// see map_screen.dart's `_typhoonMarkerGroups`/`_buildShipMarkers`. The
/// painter draws each group's entries stacked vertically at one shared
/// distance behind the ship, then moves on to the *next slot's* group
/// further out — see [MapPainter._drawShip]). Outer list empty when there's
/// no typhoon to compare against; computed independently per ship so each
/// route's distance readouts are its own, not shared.
class ShipMarker {
  final LatLng position;
  final List<LatLng> route;
  final List<LatLng> pastRoute;
  final List<LatLng> futureRoute;
  final LatLng? nextWaypoint;
  final String label;
  final List<List<ShipTyphoonDistance>> typhoonDistances;

  /// Per-route color (2026-08-xx request: comparing multiple routes from the
  /// same departure port/time made them hard to tell apart when all drawn
  /// the same blue). Assigned by the caller (map_screen.dart, cycling
  /// through a fixed palette by list position) and used for this route's
  /// line/waypoint dots and its ship icon tint — not its text labels, which
  /// stay black for legibility against the sea/land background.
  final Color color;

  const ShipMarker({
    required this.position,
    required this.route,
    required this.pastRoute,
    required this.futureRoute,
    this.nextWaypoint,
    required this.label,
    this.typhoonDistances = const [],
    this.color = Colors.blue,
  });
}

/// Draws the simplified plot map: a lat/lon grid, coastline, the ship/
/// typhoon tracks, and their markers, with a distance line between each ship
/// and the first (primary) typhoon.
///
/// Always paints into a canvas sized [MapBounds.canvasSize] (see that
/// class for why) — the `size` passed to [paint] should match it.
class MapPainter extends CustomPainter {
  /// Every ship/route to draw (2026-08-xx: 0, 1, or many — see [ShipMarker]),
  /// already filtered to "Display checkbox on" by the caller (map_screen.dart)
  /// — this painter just draws whatever's in the list, in order.
  final List<ShipMarker> ships;

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

  /// Up to 3 slots × 2 sources (JTWC/JMA, 2026-07-28), already filtered to
  /// "Display checkbox on" and "has at least a current position" by the
  /// caller — this painter just draws whatever's in the list, in order. Each
  /// ship draws one distance line/readout to *every* entry here (see
  /// [ShipMarker.typhoonDistances]), not just a single "primary" one.
  final List<TyphoonMarker> typhoons;

  /// Ship/typhoon marker icon images (2026-08-xx request: replace the
  /// placeholder triangle/circle with `assets/ship_icon01.png` /
  /// `assets/typhoon_icon01.png`). Loaded once in map_screen.dart
  /// (`loadUiImage`, lib/utils/marker_icons.dart) and passed in here — null
  /// until that load completes, in which case the previous placeholder
  /// shape is drawn instead so the map isn't left blank while the asset
  /// decodes (same "graceful until loaded" pattern as CoastlineData.empty).
  /// [shipIcon] is shared by every entry in [ships] — all routes use the
  /// same icon graphic, distinguished by their [ShipMarker.label] instead.
  final ui.Image? shipIcon;
  final ui.Image? typhoonIcon;

  MapPainter({
    this.ships = const [],
    this.coastlinePolygons = const [],
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
    for (final ship in ships) {
      _drawShipRoute(canvas, ship);
    }
    for (final typhoon in typhoons) {
      _drawTyphoonTrack(canvas, typhoon);
    }
    // One dashed line per (ship, displayed typhoon) pair, each colored to
    // match that typhoon's own color (2026-07-28: previously only drawn to
    // `typhoons.first` — extended to every displayed typhoon once JTWC/JMA
    // could both be shown at once per slot, see ShipTyphoonDistance).
    for (final ship in ships) {
      for (final typhoon in typhoons) {
        _drawDistanceLine(canvas, ship.position, typhoon.currentPosition, typhoon.color);
      }
    }
    for (final ship in ships) {
      _drawShip(canvas, ship);
    }
    for (final typhoon in typhoons) {
      _drawTyphoonMarker(canvas, typhoon);
    }
  }

  // Planned route, split at the current slider time (2026-08-03): the
  // already-sailed portion (pastRoute) as a solid line, the remaining
  // portion (futureRoute) as a dotted line — plus a small fixed-size dot
  // marker at every waypoint (past and future alike). The current ship
  // position is drawn separately, on top, by _drawShip.
  void _drawShipRoute(Canvas canvas, ShipMarker ship) {
    if (ship.route.length < 2) return;
    _drawPolyline(canvas, ship.pastRoute, ship.color, dashed: false);
    _drawPolyline(canvas, ship.futureRoute, ship.color, dashed: true);

    final wptPaint = Paint()..color = ship.color.withOpacity(0.35);
    final wptBorder = Paint()
      ..color = ship.color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    for (final p in ship.route) {
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
    _drawPolyline(canvas, typhoon.pastTrack, typhoon.color, dashed: false);
    _drawPolyline(canvas, typhoon.futureTrack, typhoon.color, dashed: true);

    // Marker dots derived from the typhoon's own color (2026-07-28: used to
    // be a fixed orange/deepOrange pair) — a translucent fill in the source
    // color plus a darker-shaded border, same relationship the original
    // orange/deepOrange.shade900 pairing had.
    final markerPaint = Paint()..color = typhoon.color.withOpacity(0.35);
    final markerBorder = Paint()
      ..color = Color.lerp(typhoon.color, Colors.black, 0.4)!
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    const dotRadius = 5.0;
    for (var i = 0; i < typhoon.track.length; i++) {
      final p = typhoon.track[i];
      final o = MapBounds.toOffset(p.latitude, p.longitude);
      _drawFixedCircle(canvas, o, dotRadius, markerPaint, markerBorder);
      if (i < typhoon.trackTimes.length) {
        _drawForecastPointTime(canvas, o, dotRadius, typhoon.trackTimes[i]);
      }
    }
  }

  // Forecast point time label ("27/15" = day/hour, JST — 2026-07-27
  // request: "12W (DOLPHIN)で言えば、270600Z→27/15"), placed to the right of
  // each forecast point's circle. Same fixed-on-screen-size treatment and
  // font size as the Range Ring labels ("同じ大きさでズームしても...同じ
  // 大きさ" — user asked for visual consistency with those), but black
  // ("文字色は黒とする") rather than the ring's teal/purple, since this isn't
  // tied to a specific ring's color.
  static const _forecastTimeLabelStyle = TextStyle(
    color: Colors.black,
    fontSize: 9,
    fontWeight: FontWeight.w600,
  );

  void _drawForecastPointTime(Canvas canvas, Offset center, double dotRadius, DateTime time) {
    final dd = time.day.toString().padLeft(2, '0');
    final hh = time.hour.toString().padLeft(2, '0');
    final painter = TextPainter(
      text: TextSpan(text: '$dd/$hh', style: _forecastTimeLabelStyle),
      textDirection: TextDirection.ltr,
    )..layout();
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.scale(_invZoom);
    const gap = 3.0; // clearance from the dot's edge
    painter.paint(canvas, Offset(dotRadius + gap, -painter.height / 2));
    canvas.restore();
  }

  // [color] matches the typhoon this line measures to (2026-07-28: used to
  // be a fixed grey regardless of which typhoon) so a line is traceable to
  // its source even with several on screen (JTWC/JMA per slot, multiple
  // slots) at once.
  void _drawDistanceLine(Canvas canvas, LatLng shipPosition, LatLng typhoonPosition, Color color) {
    final shipOffset = MapBounds.toOffset(shipPosition.latitude, shipPosition.longitude);
    final typhoonOffset = MapBounds.toOffset(typhoonPosition.latitude, typhoonPosition.longitude);
    final dashPaint = Paint()
      ..color = color
      ..strokeWidth = 1.5;
    final path = Path()
      ..moveTo(shipOffset.dx, shipOffset.dy)
      ..lineTo(typhoonOffset.dx, typhoonOffset.dy);
    canvas.drawPath(_dashed(path, dashLength: 4, gapLength: 3), dashPaint);

    // The distance readout itself is drawn together with the ship's name
    // label in _drawShip (both stack behind the ship, name innermost /
    // distance readouts outermost), so nothing else to draw here.
  }

  // Distance readout, pinned behind the ship — i.e. the opposite direction
  // from its heading toward its next waypoint (2026-07-28 request: a fixed
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
  // past whatever's already stacked closer to the ship). [distanceNm] is
  // per-ship, per-typhoon (2026-07-28: each ship can now show more than one
  // distance box at once, one per currently-displayed typhoon — see
  // ShipMarker.typhoonDistances). [color] is that typhoon's own color; used
  // as the box's *fill* with a black border (2026-07-28 revision: an earlier
  // version colored only the border on a fixed dark-blueGrey fill, but the
  // user reported the border-only coloring was hard to tell apart at a
  // glance — filling the whole box in the source color reads much more
  // clearly, and a plain black outline keeps the box legible against both
  // the sea/land background and the similarly-colored track line).
  // [extraOffset] (2026-07-29 addition) is added on top of the usual
  // behind-axis placement, in the same local (unrotated — see _drawShip,
  // which only translates+scales this space, never rotates it) coordinate
  // space — used by _drawShip to nudge a box straight up/down off the
  // behind-axis centerline when pairing JTWC/JMA of one typhoon slot as a
  // vertically-stacked pair sharing a single `startDistance` (see
  // ShipMarker.typhoonDistances's doc comment) instead of trailing one
  // after another.
  void _drawDistanceLabel(
    Canvas canvas,
    Offset behind,
    double startDistance,
    double distanceNm,
    Color color, {
    Offset extraOffset = Offset.zero,
  }) {
    const style = TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700);
    final painter = TextPainter(
      text: TextSpan(text: '${distanceNm.round()} nm', style: style),
      textDirection: TextDirection.ltr,
    )..layout();

    const paddingH = 6.0;
    const paddingV = 3.0;
    final boxWidth = painter.width + paddingH * 2;
    final boxHeight = painter.height + paddingV * 2;
    final diagonal = math.sqrt(boxWidth * boxWidth + boxHeight * boxHeight);
    final localCenter = behind * (startDistance + diagonal / 2) + extraOffset;

    final rect = Rect.fromCenter(center: localCenter, width: boxWidth, height: boxHeight);
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(4));

    canvas.drawRRect(rrect, Paint()..color = color.withOpacity(0.92));
    canvas.drawRRect(
      rrect,
      Paint()
        ..color = Colors.black
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
    painter.paint(canvas, Offset(rect.left + paddingH, rect.top + paddingV));
  }

  /// Total on-screen footprint (stacking distance + its own diagonal) one
  /// [_drawDistanceLabel] box occupies along the "behind" axis — used by
  /// [_drawShip] to lay out multiple distance boxes one after another
  /// without needing to duplicate this sizing math.
  double _distanceLabelExtent(double startDistance, double distanceNm) {
    final painter = TextPainter(
      text: TextSpan(text: '${distanceNm.round()} nm', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
      textDirection: TextDirection.ltr,
    )..layout();
    const paddingH = 6.0;
    const paddingV = 3.0;
    final boxWidth = painter.width + paddingH * 2;
    final boxHeight = painter.height + paddingV * 2;
    final diagonal = math.sqrt(boxWidth * boxWidth + boxHeight * boxHeight);
    return startDistance + diagonal;
  }

  /// A [_drawDistanceLabel] box's on-screen height (2026-07-29 addition) —
  /// constant regardless of the distance value's digit count, since only the
  /// text's *width* changes with more digits, not a single line's height.
  /// Used by [_drawShip] to work out how far apart to nudge a vertically-
  /// stacked JTWC/JMA pair so the two boxes don't overlap.
  double _distanceLabelBoxHeight() {
    final painter = TextPainter(
      text: const TextSpan(text: '0 nm', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
      textDirection: TextDirection.ltr,
    )..layout();
    const paddingV = 3.0;
    return painter.height + paddingV * 2;
  }

  // Unit vector pointing opposite a ship's heading toward its next waypoint —
  // the same heading _drawShip rotates its icon toward, just reversed and
  // normalized here since this needs a direction to offset along rather
  // than a rotation angle. Falls back to south (opposite of the default
  // north-pointing icon) when there's no next waypoint, matching _drawShip's
  // own fallback for that case.
  Offset _shipBehindDirection(ShipMarker ship, Offset shipOffset) {
    final next = ship.nextWaypoint;
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
  // place its designation label "behind" it the same way a ship's name sits
  // behind the ship (2026-08-xx request). Unlike the ship there's no
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

  // Ship icon: an isosceles triangle whose apex points toward its next
  // waypoint (2026-07-27 request) instead of always pointing north. The
  // bearing is computed directly in canvas (projected) space rather than on
  // the sphere — fine at this scale, since Web Mercator is conformal
  // (locally angle-preserving), and it keeps this in the same coordinate
  // space as everything else the painter draws.
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
  //
  // 2026-08-xx: this now draws one [ShipMarker] at a time (called in a loop
  // from paint()) instead of the single ship this painter used to carry —
  // multiple routes (e.g. comparing destination options from the same
  // departure port/time) can be on screen at once, each with its own icon,
  // label, and distance-to-typhoon readout.
  static const double _shipIconDisplayHeightPx = 26.0;
  static const double _shipIconAnchorXFrac = 0.5;
  static const double _shipIconAnchorYFrac = 0.85; // 15% up from the bottom

  void _drawShip(Canvas canvas, ShipMarker ship) {
    final o = MapBounds.toOffset(ship.position.latitude, ship.position.longitude);

    var angle = 0.0; // radians, clockwise from north (0 = pointing up)
    final next = ship.nextWaypoint;
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
        // Tinted to this route's color (2026-08-xx: distinguish multiple
        // routes compared from the same departure port/time) via a srcIn
        // color filter — this replaces the icon's own shading with a flat
        // silhouette in [ship.color], which reads clearly as "this route's
        // color" at the map's small icon size, at the cost of the original
        // artwork's shading detail.
        Paint()
          ..filterQuality = FilterQuality.medium
          ..colorFilter = ColorFilter.mode(ship.color, BlendMode.srcIn),
      );
    } else {
      // Fallback while the icon asset is still decoding (loadUiImage is
      // async) so the map isn't left blank for a frame or two.
      final paint = Paint()..color = ship.color;
      final border = Paint()
        ..color = Color.lerp(ship.color, Colors.black, 0.4)!
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

    // Ship name (if entered) + one distance-to-typhoon group per currently-
    // displayed typhoon *slot*, all stacked behind the ship (2026-08-xx
    // request: labels used to sit fixed to the right of the icon; now they
    // follow the "behind" direction — opposite of the heading toward the
    // next waypoint — so they read naturally regardless of which way the
    // ship is heading). Stacked with the name innermost (closest to the
    // ship) and each typhoon slot's group further out than the last (2026-
    // 07-28: extended from a single distance box to one per displayed
    // typhoon; 2026-07-29: regrouped by slot — see ShipMarker.typhoonDistances'
    // doc comment — so JTWC/JMA of the *same* typhoon sit at one shared
    // distance behind the ship as a vertically-stacked pair, rather than
    // each pushing the next one further back). Font size/weight/color for
    // the name are unchanged from before.
    final behind = _shipBehindDirection(ship, o);
    canvas.save();
    canvas.translate(o.dx, o.dy);
    canvas.scale(_invZoom);

    // Clearance from the ship icon to the first stacked item, and between
    // each subsequent item (2026-08-xx: tightened from 14.0/4.0 — the
    // previous values read as "too spread out" once the name label sits
    // right above the distance box(es), per user feedback).
    const gap = 8.0;
    const stackGap = 2.0;

    var nextStart = gap;
    final name = ship.label.trim();
    if (name.isNotEmpty) {
      const nameStyle = TextStyle(color: Colors.black87, fontSize: 11, fontWeight: FontWeight.w600);
      final namePainter = TextPainter(
        text: TextSpan(text: name, style: nameStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      final nameDiagonal = math.sqrt(namePainter.width * namePainter.width + namePainter.height * namePainter.height);
      final nameDistance = nextStart + nameDiagonal / 2;
      final nameCenter = behind * nameDistance;
      namePainter.paint(canvas, nameCenter - Offset(namePainter.width / 2, namePainter.height / 2));
      nextStart = nameDistance + nameDiagonal / 2 + stackGap;
    }

    // Vertical gap between the two boxes of a JTWC+JMA pair (2026-07-29
    // addition) — small and fixed, in the same "screen pixel" units as
    // everything else in this translate+scale(1/zoom) block.
    const groupVerticalGap = 2.0;

    for (final group in ship.typhoonDistances) {
      if (group.isEmpty) continue;
      if (group.length == 1) {
        // Only one source displayed for this typhoon slot — same single-box
        // placement as before.
        _drawDistanceLabel(canvas, behind, nextStart, group.first.distanceNm, group.first.color);
        nextStart = _distanceLabelExtent(nextStart, group.first.distanceNm) + stackGap;
      } else {
        // Both JTWC and JMA displayed for this slot (2026-07-29 request:
        // "台風１→船の後方にJTWC/JMAを縦に並べる") — both boxes sit at the
        // *same* distance behind the ship, offset up/down instead of one
        // trailing further back than the other. "Vertically" here is a
        // literal screen-space up/down offset, not rotated to the ship's
        // heading — this whole block (see _drawShip's canvas.save above)
        // only translates+scales, it never rotates, so straight Offset(0, ±)
        // is already what "vertical" means on screen at this point.
        final halfSpan = _distanceLabelBoxHeight() / 2 + groupVerticalGap / 2;
        _drawDistanceLabel(canvas, behind, nextStart, group[0].distanceNm, group[0].color,
            extraOffset: Offset(0, -halfSpan));
        _drawDistanceLabel(canvas, behind, nextStart, group[1].distanceNm, group[1].color,
            extraOffset: Offset(0, halfSpan));
        // Advance past whichever of the pair reaches furthest along the
        // behind axis (their widths can differ slightly by digit count).
        final extent0 = _distanceLabelExtent(nextStart, group[0].distanceNm);
        final extent1 = _distanceLabelExtent(nextStart, group[1].distanceNm);
        nextStart = math.max(extent0, extent1) + stackGap;
      }
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
        Paint()
          ..filterQuality = FilterQuality.medium
          // Tinted to this typhoon's source color (2026-07-28: JTWC/JMA can
          // both be shown at once, so the icon itself — not just the track —
          // needs to carry the color), same srcIn-tint approach as the ship
          // icon.
          ..colorFilter = ColorFilter.mode(typhoon.color, BlendMode.srcIn),
      );
    } else {
      // Fallback while the icon asset is still decoding.
      final paint = Paint()..color = typhoon.color.withOpacity(0.85);
      final border = Paint()
        ..color = Color.lerp(typhoon.color, Colors.black, 0.35)!
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2;
      canvas.drawCircle(Offset.zero, 10, paint);
      canvas.drawCircle(Offset.zero, 10, border);
    }

    final labelStyle = TextStyle(color: typhoon.color, fontSize: 11, fontWeight: FontWeight.w600);
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
          TextStyle(color: Color.lerp(typhoon.color, Colors.black, 0.35), fontSize: 10, fontWeight: FontWeight.w600));
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
    return oldDelegate.coastlinePolygons.length != coastlinePolygons.length ||
        oldDelegate.zoom != zoom ||
        oldDelegate.shipIcon != shipIcon ||
        oldDelegate.typhoonIcon != typhoonIcon ||
        oldDelegate.ships.length != ships.length ||
        _shipsChanged(oldDelegate.ships) ||
        oldDelegate.typhoons.length != typhoons.length ||
        _typhoonsChanged(oldDelegate.typhoons);
  }

  bool _shipsChanged(List<ShipMarker> old) {
    for (var i = 0; i < ships.length && i < old.length; i++) {
      if (old[i].label != ships[i].label ||
          old[i].color != ships[i].color ||
          old[i].typhoonDistances.length != ships[i].typhoonDistances.length ||
          _typhoonDistancesChanged(old[i].typhoonDistances, ships[i].typhoonDistances) ||
          old[i].route.length != ships[i].route.length ||
          old[i].pastRoute.length != ships[i].pastRoute.length ||
          old[i].futureRoute.length != ships[i].futureRoute.length ||
          old[i].position.latitude != ships[i].position.latitude ||
          old[i].position.longitude != ships[i].position.longitude ||
          old[i].nextWaypoint?.latitude != ships[i].nextWaypoint?.latitude ||
          old[i].nextWaypoint?.longitude != ships[i].nextWaypoint?.longitude) {
        return true;
      }
    }
    return false;
  }

  // 2026-07-29: typhoonDistances is now grouped by slot (List<List<...>>,
  // see ShipMarker.typhoonDistances' doc comment) — compares group-by-group,
  // then entry-by-entry within each group.
  bool _typhoonDistancesChanged(List<List<ShipTyphoonDistance>> old, List<List<ShipTyphoonDistance>> current) {
    for (var i = 0; i < current.length && i < old.length; i++) {
      final oldGroup = old[i];
      final currentGroup = current[i];
      if (oldGroup.length != currentGroup.length) return true;
      for (var j = 0; j < currentGroup.length; j++) {
        if (oldGroup[j].distanceNm != currentGroup[j].distanceNm || oldGroup[j].color != currentGroup[j].color) {
          return true;
        }
      }
    }
    return false;
  }

  bool _typhoonsChanged(List<TyphoonMarker> old) {
    for (var i = 0; i < typhoons.length && i < old.length; i++) {
      if (old[i].label != typhoons[i].label ||
          old[i].pressureLabel != typhoons[i].pressureLabel ||
          old[i].showRings != typhoons[i].showRings ||
          old[i].color != typhoons[i].color ||
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
