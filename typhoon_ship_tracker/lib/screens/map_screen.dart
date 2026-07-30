import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../models/ship_waypoint.dart';
import '../models/track_point.dart';
import '../models/voyage_plan_entry.dart';
import '../utils/app_state_storage.dart';
import '../utils/build_flags.dart';
import '../utils/coastline.dart';
import '../utils/csv_library.dart';
import '../utils/interpolation.dart';
import '../utils/jma_feed_fetcher.dart';
import '../utils/jma_marine_feed_fetcher.dart';
import '../utils/jma_marine_xml_parser.dart';
import '../utils/jma_xml_parser.dart';
import '../utils/jtwc_feed_fetcher.dart';
import '../utils/jtwc_parser.dart';
import '../utils/map_bounds.dart';
import '../utils/marine_area_codes.dart';
import '../utils/marine_areas.dart';
import '../utils/marker_icons.dart';
import '../utils/open_meteo_marine_fetcher.dart';
import '../utils/voyage_plan.dart';
import '../utils/voyage_plan_parser.dart';
import '../utils/wave_field.dart';
import '../widgets/map_painter.dart';
import 'voyage_plan_screen.dart';

/// Main screen: map view with zoom controls and a time slider/play button.
///
/// Ship tracks come from registered Passage Plan CSVs and typhoon tracks
/// come from pasted JTWC warning text — both entered manually until the
/// real CSV/Excel voyage plan and JMA/JTWC feed readers are implemented (see
/// TODO(data) below). Nothing is drawn, and the playback bar is hidden,
/// until at least one of those is registered (2026-07-27 decision — no
/// sample/placeholder data is shown by default).
class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final TransformationController _transformationController = TransformationController();

  // TODO(data): replace with parsed voyage plan / typhoon feed data.
  //
  // Mutable (2026-07-28 request: playback should start at "the loaded
  // typhoon info's announced time", e.g. JTWC's "250000Z" → 25th 09:00 JST,
  // not device "now") — see _showLabelSettingsDialog's Save handler, which
  // updates this from JtwcTyphoonInfo.issuedAtJst() when slot 0 parses one.
  // Falls back to device "now" until then, same as before.
  DateTime _startTime = DateTime.now();

  // Registered passage plans, imported from JRC ECDIS/NAVTOR route CSVs
  // and/or edited in VoyagePlanScreen (2026-07-30, extended 2026-08-xx to
  // support up to _maxVoyagePlans registered at once — e.g. separate legs
  // of a voyage with a port call in between). Empty until the user imports
  // at least one — _activeShipTracks below is simply empty until then
  // (2026-07-27 decision: no sample/placeholder ship is drawn by default —
  // see docs/completed-log.md for the reasoning). Same pattern as the
  // typhoon slots below.
  static const int _maxVoyagePlans = 10;
  final List<VoyagePlanEntry> _voyagePlans = [];

  // Builds the track for one registered plan, or null if it can't be
  // computed (shouldn't happen — VoyagePlanScreen validates speeds before
  // Save — but guarded defensively rather than crashing the map).
  List<TrackPoint>? _trackForPlan(VoyagePlanEntry plan) {
    try {
      final track = shipTrackFromWaypoints(plan.waypoints, plan.departureTime);
      return track.isEmpty ? null : track;
    } on VoyagePlanTimeException {
      return null;
    }
  }

  // Every track that should currently be drawn: one entry per Display-on
  // registered plan (2026-08-xx request — "船は一つ、プランは複数": compare
  // route options departing the same port/time to different destinations,
  // each running fully independently). Empty when no plan is registered (or
  // registered plans are all Display-off) — 2026-07-27 decision: no sample
  // ship is drawn in that case (see docs/completed-log.md). Each entry pairs
  // the track with the label to show for it (the plan's name). An earlier
  // design concatenated Display-on plans into one combined track (for a
  // port-call/multi-leg use case) — reverted once the user clarified the
  // actual need was route *comparison*, not multi-leg concatenation; see
  // docs/devlog-passage-plan-multi.md.
  List<({List<TrackPoint> track, String label})> get _activeShipTracks {
    final result = <({List<TrackPoint> track, String label})>[];
    for (final plan in _voyagePlans) {
      if (!plan.displayEnabled) continue;
      final track = _trackForPlan(plan);
      if (track == null) continue;
      result.add((track: track, label: plan.name.isEmpty ? 'Ship' : plan.name));
    }
    return result;
  }

  // Playback bar upper bound: the latest arrival time across every
  // currently-drawn track (2026-08-10 request: "最終を航海計画の最終WP到着
  // 時としたい：台風は途中で止まっても船は到着地までいく" — the playback bar
  // runs all the way to the ship's arrival regardless of how far the loaded
  // typhoon data reaches). With multiple comparison routes possibly on
  // screen at once (2026-08-xx), this is now the *longest* of them, so the
  // slider can play out every displayed option to its own arrival. Once a
  // typhoon's own last point is earlier than this, its marker simply stays
  // put at its last known position for the remainder of the timeline
  // (positionAt clamps to the last point past a track's time range) rather
  // than the slider being artificially cut short.
  double get _maxOffsetHours {
    var shipMaxHours = 0.0;
    var anyShipInFuture = false;
    for (final entry in _activeShipTracks) {
      final points = entry.track;
      if (points.isEmpty) continue;
      final hours = points.last.time.difference(_startTime).inMinutes / 60.0;
      if (hours > 0) anyShipInFuture = true;
      if (hours > shipMaxHours) shipMaxHours = hours;
    }
    if (anyShipInFuture) return shipMaxHours;

    // Fallback (2026-07-27 bug fix): every currently-displayed ship track's
    // arrival already falls before _startTime — e.g. a Passage Plan
    // registered/persisted for an earlier voyage is left Display-on while a
    // newer typhoon warning (with a later resolved _startTime — see
    // JtwcTyphoonInfo.issuedAtJst) is loaded on top of it, as happened when
    // testing the month-boundary date fix. The ship-only rule above (2026-
    // 08-10 decision, kept unchanged for the normal case above) would then
    // hide the playback bar entirely (_buildTimelineTrack returns nothing
    // when this is <= 0), leaving no way to even scrub through the loaded
    // typhoon's own track. Falling back to the furthest-reaching
    // Display-on typhoon's last forecast point keeps the bar usable for
    // that instead of a total blackout.
    var typhoonMaxHours = 0.0;
    for (var i = 0; i < _typhoonSlots.length; i++) {
      final slot = _typhoonSlots[i];
      for (final points in [
        if (slot.jtwcDisplayEnabled) _jtwcTrackPointsForSlot(i),
        if (slot.jmaDisplayEnabled) _jmaTrackPointsForSlot(i),
      ]) {
        if (points == null || points.isEmpty) continue;
        final hours = points.last.time.difference(_startTime).inMinutes / 60.0;
        if (hours > typhoonMaxHours) typhoonMaxHours = hours;
      }
    }
    return typhoonMaxHours;
  }

  double _offsetHours = 24;
  bool _isPlaying = false;
  Timer? _playTimer;

  // --- Wave field overlay state (2026-07-29, personal build only) ---
  //
  // See build_flags.dart's kPersonalBuild and wave_field.dart's top-of-file
  // doc comment for the overall design. All of this stays at its initial
  // "off"/empty value in a mainline build since the only UI that flips
  // _waveFieldEnabled is itself gated by kPersonalBuild (see the AppBar
  // toggle in build()) — nothing here runs unless the user explicitly turns
  // the overlay on in a personal build.
  bool _waveFieldEnabled = false;
  bool _waveFieldLoading = false;
  String? _waveFieldError;
  List<WaveFieldPoint>? _waveFieldGrid;

  // Free-running animation clock for the flow streaks (see
  // MapPainter._drawWaveStreaks), independent of the playback timeline's
  // _startTime/_offsetHours — the streaks are a decorative "is the sea
  // moving" cue, not a plotted forecast value, so they animate continuously
  // in real device time rather than advancing only while Play is pressed.
  // Ticks only while _waveFieldEnabled (see _setWaveFieldEnabled), same
  // "don't pay for what you're not showing" spirit as _playTimer only
  // running while _isPlaying.
  double _waveAnimSeconds = 0;
  Timer? _waveAnimTimer;

  // Playback speed as a multiplier of the original fixed-speed behavior
  // (1.0 = "1 simulated hour per 200ms tick", which is what this screen
  // always did before). 2026-07-28 request: default to 50% (half as fast
  // as before). Range changed 2026-07-27 from 25%-150% to 1%-100% (user
  // request) — see _showPlaybackSpeedDialog.
  double _playbackSpeed = 0.5;
  static const double _minPlaybackSpeed = 0.01;
  static const double _maxPlaybackSpeed = 1.0;

  // _zoom/_translation are in MapBounds.canvasSize units (a fixed logical
  // size — see MapBounds for why). _fitScale/_coverFitScale (below) depend
  // on the window size, so they're recomputed on every layout rather than
  // being constants.
  double _zoom = 1.0;
  Offset _translation = Offset.zero;
  Size _viewportSize = Size.zero;
  // "Contain" fit (the smaller of width-ratio/height-ratio): the scale at
  // which the *whole* canvas fits inside the viewport, possibly with empty
  // gaps on one axis. Used only for the initial-view zoom multiplier below
  // (_updateViewportSize) — kept separate from _minZoom (below) since they
  // serve different purposes and conflating them changed the tuned startup
  // zoom level as an unintended side effect (2026-07-28).
  double _fitScale = 1.0;
  // "Cover" fit (the larger of width-ratio/height-ratio): the scale at
  // which the canvas fills the viewport on *both* axes with no gaps —
  // i.e. one axis exactly touches the viewport edges, the other overflows.
  // This, not _fitScale, is what InteractiveViewer's own gesture handling
  // (drag, pinch, and — now that this screen no longer duplicates wheel
  // handling — mouse wheel too) naturally won't zoom out past, since going
  // further would require showing empty space beyond the canvas edges,
  // which InteractiveViewer's default boundary constraint disallows for
  // gesture-driven transforms. 2026-07-28 request: make the +/- buttons
  // and slider's minimum match this same limit, instead of the more
  // permissive _fitScale, for consistency across all three zoom controls.
  double _coverFitScale = 1.0;
  bool _initializedView = false;

  double get _minZoom => _coverFitScale;
  double get _maxZoom => _fitScale * 12;

  CoastlineData _coastline = CoastlineData.empty;

  // --- Marine forecast (地方海上予報, VPCY51) area-fill layer — mainline
  // feature, 2026-07-30 ---
  //
  // Production replacement for the "Marine forecast (debug)" text-only
  // dialog (_showMarineForecastDebugDialog, kept as-is for raw verification)
  // once real-data fetches confirmed jma_marine_xml_parser.dart reads actual
  // bulletins correctly. Unlike the typhoon slots, this is one nationwide
  // layer, not per-slot — see AppStateStorage's top-level (not
  // TyphoonSlotSnapshot) marineForecast* fields.
  //
  // Bundled area boundary polygons (marine_areas.dart), loaded once at
  // startup — same "empty until loaded" pattern as _coastline above.
  MarineAreaData _marineAreas = MarineAreaData.empty;

  // Whether the area-fill layer is currently drawn (Information dialog's
  // "Marine Forecast" Display checkbox). Off by default — nothing fetched
  // yet on a fresh launch, same reasoning as the typhoon slots' jmaDisplayEnabled
  // default.
  bool _marineForecastDisplayEnabled = false;

  // Offline cache of the last successful "Import from JMA" (Marine
  // Forecast) press: raw bulletin XML text(s) — more than one when multiple
  // regional offices each published their own VPCY51 covering different sea
  // areas (see jma_marine_feed_fetcher.dart's _findVpcy51Urls doc comment) —
  // re-parsed on load/fetch, same "store raw, re-parse" convention as
  // _TyphoonSlot.jmaRawXml.
  List<String> _marineForecastRawXmls = [];
  DateTime? _marineForecastFetchedAtJst;

  // Parsed-and-merged cache derived from _marineForecastRawXmls (rebuilt
  // whenever that list changes — fetch success or _restoreState — not
  // reparsed on every paint/build) keyed by VPCY51 Area/Code, so
  // _marineForecastAreaPolygons below is a cheap lookup rather than
  // re-running parseJmaMarineXml every frame.
  Map<String, MarineWaveForecast> _marineForecastByArea = {};

  // Re-parses [rawXmls] (see _marineForecastByArea's doc comment) into a
  // map keyed by area code, last bulletin wins for a given code (areas
  // shouldn't actually overlap between offices, but a Map naturally handles
  // it gracefully either way). Bulletins that fail to re-parse are skipped
  // rather than thrown (same fail-safe convention _restoreState already uses
  // for the typhoon slots' cached jmaRawXml — protects against a
  // hypothetical future parser change making an already-cached bulletin no
  // longer parse).
  Map<String, MarineWaveForecast> _parseMarineForecastByArea(List<String> rawXmls) {
    final map = <String, MarineWaveForecast>{};
    for (final xml in rawXmls) {
      try {
        for (final forecast in parseJmaMarineXml(xml)) {
          map[forecast.areaCode] = forecast;
        }
      } on JmaMarineXmlParseException {
        continue;
      }
    }
    return map;
  }

  // Resolves _marineForecastByArea down to what MapPainter actually needs:
  // this area's bundled boundary polygon(s) plus its Base wave height (see
  // MarineForecastAreaPolygon.heightM doc comment for why Base rather than
  // a slider-time-resolved value). Empty whenever the layer is off, so
  // toggling Display is a cheap no-render rather than needing to also clear
  // the underlying fetched data.
  List<MarineForecastAreaPolygon> get _marineForecastAreaPolygons {
    if (!_marineForecastDisplayEnabled) return const [];
    final result = <MarineForecastAreaPolygon>[];
    for (final entry in _marineForecastByArea.entries) {
      final polygons = _marineAreas.forCode(entry.key);
      if (polygons.isEmpty) continue;
      result.add(MarineForecastAreaPolygon(id: entry.key, polygons: polygons, heightM: entry.value.baseHeightM));
    }
    return result;
  }

  // Ship/typhoon marker icon images (2026-08-xx request: replace the
  // placeholder triangle/circle with assets/ship_icon01.png and
  // assets/typhoon_icon01.png). Null until loaded — MapPainter falls back
  // to the old placeholder shapes for the frame(s) before that.
  ui.Image? _shipIcon;
  ui.Image? _typhoonIcon;

  // User-entered ship name (2026-07-28 request: NAVTOR-format voyage-plan
  // CSVs don't carry a ship name field, so it's entered here instead).
  // Drawn behind every displayed ship marker (2026-08-xx: previously unused
  // for display — the Passage Plan's own name was shown there instead, but
  // that moved to the dedicated legend overlay below, freeing this slot for
  // the ship's actual name). The same text is used for every currently
  // Display-on Passage Plan, since they represent route *options* for one
  // physical ship, not separate vessels — see ShipMarker.label's doc comment
  // in map_painter.dart.
  String _shipName = '';

  // Up to 3 typhoons (2026-07-28 request: "this area can have more than one
  // typhoon active at once"), each entered by pasting a JTWC warning text.
  // All 3 slots are treated the same — none has a sample/placeholder track
  // (2026-07-27 decision: removed the slot-0 sample forecast that used to
  // fill in until real data was pasted, see docs/completed-log.md); a slot
  // simply has no track until real data is pasted for it. See
  // _typhoonMarkers below.
  //
  // Default Display on/off (2026-07-27 request): only Ship and Typhoon 1's
  // JTWC source are on at app launch — slots 1-2 default off since they have
  // no data to show until the user pastes/fetches something for them
  // anyway. JMA display defaults off for every slot regardless (see
  // _TyphoonSlot.jmaDisplayEnabled) since there's nothing fetched yet on a
  // fresh launch either way.
  final List<_TyphoonSlot> _typhoonSlots = List.generate(
    3,
    (i) => _TyphoonSlot()..jtwcDisplayEnabled = i == 0,
  );

  // Builds the TrackPoint list a slot's JTWC track/current-position/timeline
  // math should use: the parsed JTWC data (current position + forecast
  // points, offset from _startTime — see JtwcForecastPoint), or null when
  // there's nothing to plot yet (no JTWC text pasted for this slot, or a
  // slot whose pasted text had no REPEAT POSIT line to anchor a position on).
  List<TrackPoint>? _jtwcTrackPointsForSlot(int index) {
    final info = _typhoonSlots[index].jtwcInfo;
    final position = info.position;
    if (position == null) return null;
    return [
      TrackPoint(time: _startTime, latitude: position.latitude, longitude: position.longitude),
      for (final point in info.forecastTrack)
        TrackPoint(
          time: _startTime.add(Duration(hours: point.hoursFromNow)),
          latitude: point.position.latitude,
          longitude: point.position.longitude,
        ),
    ];
  }

  // Builds the TrackPoint list a slot's JMA track/current-position/timeline
  // math should use (2026-07-28 addition): [JmaTyphoonInfo.toTrackPoints]
  // already carries absolute JST times for the observed position and every
  // forecast point, so — unlike the JTWC path above — no `_startTime`-offset
  // math is needed here at all. Null when nothing's been fetched yet for
  // this slot.
  List<TrackPoint>? _jmaTrackPointsForSlot(int index) {
    final points = _typhoonSlots[index].jmaInfo.toTrackPoints();
    return points.isEmpty ? null : points;
  }

  // Track color per source (2026-07-28 request: "気象庁と米軍の予報を両方
  // 表示...色分けをする...米軍であれば赤" — JTWC/US military is red; JMA gets
  // a different, equally distinct color so both can be on screen at once
  // without becoming unreadable). Shared by the track line, marker dots,
  // icon tint, designation label, pressure label, and the matching ship-side
  // distance readout for that source — see map_painter.dart.
  static const Color _jtwcColor = Color(0xFFE53935); // red
  static const Color _jmaColor = Color(0xFFEF6C00); // orange

  // Accent color for the Information dialog's Marine Forecast (VPCY51)
  // section (Display checkbox label, Import button icon/label, status text)
  // — distinct from _jtwcColor/_jmaColor since this isn't a typhoon source.
  // Not related to MapPainter's own per-height fill color scale
  // (_marineForecastColor in map_painter.dart) — this is a single fixed UI
  // accent, not a value-dependent one.
  static const Color _marineForecastAccentColor = Color(0xFF00695C); // teal

  // Builds one [TyphoonMarker] from an already-resolved track — shared by
  // both the JTWC and JMA paths below, which differ only in how they build
  // [points]/[designation]/[pressureLabel]/[color].
  TyphoonMarker _typhoonMarkerFromTrack(
    List<TrackPoint> points, {
    required String? designation,
    required String? pressureLabel,
    required bool showRings,
    required Color color,
  }) {
    final split = splitTrackAtTime(points, _currentTime);
    return TyphoonMarker(
      track: points.map((p) => LatLng(p.latitude, p.longitude)).toList(),
      pastTrack: split.past,
      futureTrack: split.future,
      currentPosition: positionAt(points, _currentTime),
      label: designation ?? 'Typhoon',
      pressureLabel: pressureLabel,
      showRings: showRings,
      // Parallel to `track`, same order (2026-07-27 request: show each
      // forecast point's valid time, e.g. "27/15" for JTWC's "270600Z",
      // next to its circle). `points` is already ordered/aligned with the
      // `track` list above, so a plain `.time` map keeps them in lockstep.
      trackTimes: points.map((p) => p.time).toList(),
      color: color,
    );
  }

  // Builds the actual [TyphoonMarker]s to draw, grouped by slot: each inner
  // list holds up to two entries (2026-07-28 request — JTWC and JMA shown
  // simultaneously, each independently Display-toggleable), JTWC first then
  // JMA when both are present, matching _jtwcColor/_jmaColor. Slots with
  // nothing currently displayed simply contribute no entry (not an empty
  // list) — see _typhoonMarkers below for the flat form most callers want.
  //
  // 2026-07-29: this grouping is what lets _buildShipMarkers show a ship's
  // distance to JTWC/JMA of the *same* typhoon as a vertically-stacked pair
  // rather than two separate stops further and further behind the ship (see
  // ShipMarker.typhoonDistances) — a flat list alone can't tell two
  // consecutive entries "belong to the same slot" from "happen to be
  // adjacent because the slot in between had nothing displayed".
  //
  // The slider-time interpolation and "whole track drawn persistently"
  // behavior mirror the ship's (positionAt / full-route rendering) —
  // 2026-07-28 request: "台風の軌跡：船のように残してください".
  List<List<TyphoonMarker>> get _typhoonMarkerGroups {
    final groups = <List<TyphoonMarker>>[];
    for (var i = 0; i < _typhoonSlots.length; i++) {
      final slot = _typhoonSlots[i];
      final slotMarkers = <TyphoonMarker>[];
      if (slot.jtwcDisplayEnabled) {
        final points = _jtwcTrackPointsForSlot(i);
        if (points != null && points.isNotEmpty) {
          slotMarkers.add(_typhoonMarkerFromTrack(
            points,
            designation: _jtwcMarkerLabel(slot),
            pressureLabel:
                slot.jtwcInfo.centralPressureHpa == null ? null : '${slot.jtwcInfo.centralPressureHpa}hPa',
            showRings: slot.jtwcRingsEnabled,
            color: _jtwcColor,
          ));
        }
      }
      if (slot.jmaDisplayEnabled) {
        final points = _jmaTrackPointsForSlot(i);
        if (points != null && points.isNotEmpty) {
          slotMarkers.add(_typhoonMarkerFromTrack(
            points,
            designation: _jmaMarkerLabel(slot),
            pressureLabel:
                slot.jmaInfo.centralPressureHpa == null ? null : '${slot.jmaInfo.centralPressureHpa}hPa',
            showRings: slot.jmaRingsEnabled,
            color: _jmaColor,
          ));
        }
      }
      if (slotMarkers.isNotEmpty) groups.add(slotMarkers);
    }
    return groups;
  }

  // Flat form of [_typhoonMarkerGroups] — what every other caller (the map's
  // own typhoon track/marker drawing, the Range Ring menu, etc.) actually
  // wants; only _buildShipMarkers needs the grouped form.
  List<TyphoonMarker> get _typhoonMarkers => [for (final group in _typhoonMarkerGroups) ...group];

  // Lat/lon under the mouse cursor, shown bottom-right (2026-07-27 request).
  // Null when the cursor isn't over the map (or on touch-only devices,
  // where hover events never fire — the readout just stays hidden there).
  ({double lat, double lon})? _cursorLatLon;

  DateTime get _currentTime => _startTime.add(Duration(minutes: (_offsetHours * 60).round()));

  @override
  void initState() {
    super.initState();
    _restoreState();
    CoastlineData.load().then((data) {
      if (mounted) setState(() => _coastline = data);
    });
    MarineAreaData.load().then((data) {
      if (mounted) setState(() => _marineAreas = data);
    });
    loadUiImage('assets/ship_icon01.png').then((image) {
      if (mounted) setState(() => _shipIcon = image);
    });
    loadUiImage('assets/typhoon_icon01.png').then((image) {
      if (mounted) setState(() => _typhoonIcon = image);
    });
    // Keeps (_zoom, _translation) mirroring the controller's actual value
    // for *any* change to it — drag, pinch, or InteractiveViewer's own
    // built-in mouse-wheel zoom (see 2026-07-28 bug fix note on
    // InteractiveViewer below) — rather than only re-syncing at specific
    // interaction endpoints, which turned out to miss/race with wheel
    // events.
    _transformationController.addListener(_syncFromController);
  }

  @override
  void dispose() {
    _playTimer?.cancel();
    _waveAnimTimer?.cancel();
    _transformationController.removeListener(_syncFromController);
    _transformationController.dispose();
    super.dispose();
  }

  // Restores registered Passage Plans / typhoon slots / ship name / playback
  // speed from the previous session (2026-07-27 request: "アプリを閉じ、また
  // 開いた場合に直前の入力済の登録情報が読み込まれるように"). Runs once at
  // startup, async (SharedPreferences I/O), so the first frame(s) still show
  // the empty/sample state until this resolves — same pattern already used
  // for the coastline/icon loads just above. No-ops (leaves the sample/empty
  // state as-is) on first launch or if the saved JSON can't be parsed — see
  // AppStateStorage.load's doc comment.
  Future<void> _restoreState() async {
    final snapshot = await AppStateStorage.load();
    if (snapshot == null || !mounted) return;
    setState(() {
      _shipName = snapshot.shipName;
      _playbackSpeed = snapshot.playbackSpeed;
      _voyagePlans
        ..clear()
        ..addAll(snapshot.voyagePlans);
      for (var i = 0; i < _typhoonSlots.length && i < snapshot.typhoonSlots.length; i++) {
        final saved = snapshot.typhoonSlots[i];
        final slot = _typhoonSlots[i];
        slot.pastedText = saved.pastedText;
        slot.jtwcDisplayEnabled = saved.jtwcDisplayEnabled;
        slot.jtwcRingsEnabled = saved.jtwcRingsEnabled;
        slot.jtwcInfo = saved.pastedText.trim().isEmpty
            ? JtwcTyphoonInfo.empty
            : parseJtwcWarningText(saved.pastedText);
        // JMA offline cache (2026-07-29 addition): re-parse the stored raw
        // bulletin XML the same way jtwcInfo is re-parsed from stored raw
        // text above. Falls back to JmaTyphoonInfo.empty on a parse failure
        // (e.g. a hypothetical future JMA schema change making an
        // already-cached bulletin no longer parse) rather than crashing on
        // launch — same fail-safe philosophy as AppStateStorage.load's own
        // outer catch, see its doc comment.
        final rawXml = saved.jmaRawXml;
        slot.jmaRawXml = rawXml;
        slot.jmaFetchedAtJst = saved.jmaFetchedAtJst;
        slot.jmaDisplayEnabled = saved.jmaDisplayEnabled;
        slot.jmaRingsEnabled = saved.jmaRingsEnabled;
        if (rawXml == null || rawXml.trim().isEmpty) {
          slot.jmaInfo = JmaTyphoonInfo.empty;
        } else {
          try {
            slot.jmaInfo = parseJmaTyphoonXml(rawXml);
          } on JmaXmlParseException {
            slot.jmaInfo = JmaTyphoonInfo.empty;
          }
        }
      }
      // Mirrors _showLabelSettingsDialog's Save handler: playback start time
      // follows slot 0's warning, resolved against the *real* current date
      // (not a stale value from whenever this was last saved) so a
      // multi-day-old save doesn't drift the resolved year/month. Same
      // JMA-first priority as the Save handler (2026-07-29: JMA can now be
      // restored too, see above) — a cached JMA bulletin's own exact JST
      // time is more precise than reconstructing one from JTWC's
      // day-only field, when both are available.
      final restoredSlot0Jma = _typhoonSlots[0].jmaInfo;
      final restoredStart = restoredSlot0Jma.isEmpty
          ? _typhoonSlots[0].jtwcInfo.issuedAtJst(DateTime.now())
          : (restoredSlot0Jma.observedAtJst ?? restoredSlot0Jma.reportDateTimeJst);
      if (restoredStart != null) {
        _startTime = restoredStart;
        _offsetHours = 0;
      }
      // Marine forecast (地方海上予報) offline cache (2026-07-30 addition) —
      // same re-parse-on-load treatment as the typhoon slots' jmaRawXml
      // above, just at the top level rather than per-slot.
      _marineForecastRawXmls = snapshot.marineForecastRawXmls;
      _marineForecastFetchedAtJst = snapshot.marineForecastFetchedAtJst;
      _marineForecastDisplayEnabled = snapshot.marineForecastDisplayEnabled;
      _marineForecastByArea = _parseMarineForecastByArea(_marineForecastRawXmls);
    });
  }

  // Fire-and-forget save after every mutation to the persisted fields
  // (Passage Plan add/edit/delete/Display, typhoon paste/Display/Rings,
  // ship name, playback speed) — see AppStateStorage.save's doc comment for
  // why this doesn't need to be awaited by callers.
  void _saveState() {
    AppStateStorage.save(
      shipName: _shipName,
      playbackSpeed: _playbackSpeed,
      voyagePlans: _voyagePlans,
      typhoonSlots: [
        for (final slot in _typhoonSlots)
          TyphoonSlotSnapshot(
            pastedText: slot.pastedText,
            jtwcDisplayEnabled: slot.jtwcDisplayEnabled,
            jtwcRingsEnabled: slot.jtwcRingsEnabled,
            jmaRawXml: slot.jmaRawXml,
            jmaFetchedAtJst: slot.jmaFetchedAtJst,
            jmaDisplayEnabled: slot.jmaDisplayEnabled,
            jmaRingsEnabled: slot.jmaRingsEnabled,
          ),
      ],
      marineForecastRawXmls: _marineForecastRawXmls,
      marineForecastFetchedAtJst: _marineForecastFetchedAtJst,
      marineForecastDisplayEnabled: _marineForecastDisplayEnabled,
    );
  }

  void _togglePlay() {
    setState(() => _isPlaying = !_isPlaying);
    if (_isPlaying) {
      final maxHours = _maxOffsetHours;
      _playTimer = Timer.periodic(const Duration(milliseconds: 200), (_) {
        setState(() {
          _offsetHours += 1 * _playbackSpeed;
          if (_offsetHours >= maxHours) {
            _offsetHours = maxHours;
            _isPlaying = false;
            _playTimer?.cancel();
          }
        });
      });
    } else {
      _playTimer?.cancel();
    }
  }

  // Dialog for adjusting playback speed (2026-07-28 request: "今より50%
  // 遅くする、または再生スピードを調整できるようにする"), defaulting to
  // 50% of the original fixed speed. Range changed 2026-07-27 from
  // 25%-150% to 1%-100% (user request); 1% steps below match the new
  // integer-percent range. Takes effect immediately — _togglePlay's timer
  // reads _playbackSpeed fresh on every tick, so changing it mid-playback
  // doesn't require a restart.
  Future<void> _showPlaybackSpeedDialog() async {
    var speedLocal = _playbackSpeed;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            return AlertDialog(
              title: const Text("Play Sp'd"),
              content: SizedBox(
                width: 320,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${(speedLocal * 100).round()}%',
                      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                    ),
                    Slider(
                      min: _minPlaybackSpeed,
                      max: _maxPlaybackSpeed,
                      divisions: ((_maxPlaybackSpeed - _minPlaybackSpeed) / 0.01).round(),
                      value: speedLocal,
                      label: '${(speedLocal * 100).round()}%',
                      onChanged: (v) => setDialogState(() => speedLocal = v),
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('${(_minPlaybackSpeed * 100).round()}%',
                            style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                        Text('${(_maxPlaybackSpeed * 100).round()}%',
                            style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                      ],
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () {
                    setState(() => _playbackSpeed = speedLocal);
                    _saveState();
                    Navigator.pop(dialogContext);
                  },
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // Zoom/pan are tracked explicitly as (_zoom, _translation) rather than
  // trusting the raw Matrix4, since this screen never rotates the map —
  // the transform is always "translate then uniform scale". That keeps the
  // "zoom around a fixed point" math (below) simple and easy to verify,
  // instead of chaining Matrix4 operations whose combined effect is harder
  // to reason about.
  //
  // screenPoint = _translation + _zoom * scenePoint

  void _applyTransform() {
    _transformationController.value = Matrix4.identity()
      ..translate(_translation.dx, _translation.dy)
      ..scale(_zoom);
  }

  void _zoomAtViewportPoint(Offset viewportPoint, double factor) {
    final newZoom = (_zoom * factor).clamp(_minZoom, _maxZoom).toDouble();
    if (newZoom == _zoom) return;
    final scenePoint = (viewportPoint - _translation) / _zoom;
    final newTranslation = viewportPoint - scenePoint * newZoom;
    setState(() {
      _zoom = newZoom;
      _translation = newTranslation;
    });
    _applyTransform();
  }

  Offset get _viewportCenter => Offset(_viewportSize.width / 2, _viewportSize.height / 2);

  void _zoomBy(double factor) => _zoomAtViewportPoint(_viewportCenter, factor);

  void _setZoom(double value) => _zoomAtViewportPoint(_viewportCenter, value / _zoom);

  // Converts a viewport (screen) point to lat/lon using the transform
  // controller's *current* matrix, read fresh on every hover event rather
  // than the (_zoom, _translation) state fields — those only get synced on
  // interaction end, so they'd lag while actively dragging/zooming.
  ({double lat, double lon})? _latLonAtViewportPoint(Offset viewportPoint) {
    final m = _transformationController.value;
    final scale = m.getMaxScaleOnAxis();
    if (scale == 0) return null;
    final t = m.getTranslation();
    final scenePoint = (viewportPoint - Offset(t.x, t.y)) / scale;
    return MapBounds.fromOffset(scenePoint);
  }

  void _handleHover(PointerHoverEvent event) {
    setState(() => _cursorLatLon = _latLonAtViewportPoint(event.localPosition));
  }

  // Keeps (_zoom, _translation) in sync with the transformation controller's
  // actual current value — called from the persistent listener registered
  // in initState (fires for every change: drag/pinch, InteractiveViewer's
  // own mouse-wheel zoom, or our own _applyTransform calls). Previously
  // this only ran from InteractiveViewer's onInteractionEnd callback, which
  // (2026-07-28 bug fix) turned out not to reliably cover wheel-driven
  // zoom, leaving (_zoom, _translation) stale relative to the controller —
  // the +/- buttons and slider would then compute their next zoom from
  // that stale state and fight with whatever the wheel had just done.
  void _syncFromController() {
    final m = _transformationController.value;
    final t = m.getTranslation();
    setState(() {
      _zoom = m.getMaxScaleOnAxis();
      _translation = Offset(t.x, t.y);
    });
  }

  // Recomputes _fitScale for the current viewport size, and — the first
  // time only — centers the initial view on MapBounds.defaultCenterLat/Lon
  // (roughly the middle of Japan) at a zoomed-in level, per the 2026-07-26
  // decision to always start on a recognizable view rather than the whole
  // N5-50/E85-170 range zoomed all the way out.
  //
  // Called from build() via LayoutBuilder, which runs during layout — so
  // this only does plain field mutation here (safe: nothing has read these
  // fields yet in this build pass). Actually applying the transform touches
  // _transformationController (a ChangeNotifier that InteractiveViewer
  // listens to), which is deferred to a post-frame callback to avoid
  // mutating a listened-to notifier mid-layout.
  void _updateViewportSize(Size viewportSize) {
    _viewportSize = viewportSize;
    if (viewportSize.width <= 0 || viewportSize.height <= 0) return;
    final widthRatio = viewportSize.width / MapBounds.canvasWidth;
    final heightRatio = viewportSize.height / MapBounds.canvasHeight;
    _fitScale = math.min(widthRatio, heightRatio);
    _coverFitScale = math.max(widthRatio, heightRatio);
    if (!_initializedView) {
      _initializedView = true;
      _zoom = (_fitScale * 1.8).clamp(_minZoom, _maxZoom).toDouble();
      final center = MapBounds.toOffset(MapBounds.defaultCenterLat, MapBounds.defaultCenterLon);
      _translation = _viewportCenter - center * _zoom;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _applyTransform();
      });
    } else {
      // Window resized after the initial view was set: just keep the
      // current zoom within the (possibly changed) valid range.
      final clamped = _zoom.clamp(_minZoom, _maxZoom).toDouble();
      if (clamped != _zoom) {
        _zoom = clamped;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _applyTransform();
        });
      }
    }
  }

  // TODO(timezone): _startTime currently comes from DateTime.now() (sample
  // data, device-local time). Once real voyage-plan/typhoon data is wired
  // up, convert explicitly to JST here rather than relying on the device's
  // local timezone, since the "(JST)" label is a fixed claim about the zone.
  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  String _formatDateTime(DateTime dt) {
    final dd = dt.day.toString().padLeft(2, '0');
    final mmm = _months[dt.month - 1];
    final hh = dt.hour.toString().padLeft(2, '0');
    final mi = dt.minute.toString().padLeft(2, '0');
    return '$dd $mmm. ${dt.year} $hh:$mi (JST)';
  }

  // "Import All" success status text (2026-07-29 request), e.g. "Imported
  // to Typhoon 1", "Imported to Typhoon 1, 2", "Imported to Typhoon 1, 2,
  // 3" for count == 1/2/3 — fetchAllJma/fetchAllJtwc below always fill
  // slots contiguously starting at Typhoon 1 (see their own loops), so
  // "how many were imported" fully determines which slot numbers to list
  // here without needing to track which specific slots separately.
  String _importedToSlotsLabel(int count) {
    final numbers = List.generate(count, (i) => '${i + 1}').join(', ');
    return 'Imported to Typhoon $numbers';
  }

  // Cursor lat/lon readout (2026-07-27 request), formatted as
  // "31-15.5N 140-23.4E": degrees, a dash, minutes with one decimal place
  // (seconds folded into tenths of a minute — e.g. 15' 30" = 15.5'), then
  // the hemisphere letter. The `minutes >= 60` check handles the rounding
  // edge case where minutes round up to 60.0 (carries one into degrees).
  String _formatDegMin(double value, String positiveSuffix, String negativeSuffix) {
    final suffix = value >= 0 ? positiveSuffix : negativeSuffix;
    final absValue = value.abs();
    var deg = absValue.floor();
    var minutes = double.parse(((absValue - deg) * 60).toStringAsFixed(1));
    if (minutes >= 60) {
      minutes -= 60;
      deg += 1;
    }
    return '$deg-${minutes.toStringAsFixed(1)}$suffix';
  }

  String _formatCursorLatLon(double lat, double lon) {
    return '${_formatDegMin(lat, 'N', 'S')} ${_formatDegMin(lon, 'E', 'W')}';
  }

  // Lat/lon grid labels ("20N", "120E"), pinned to the screen edges instead
  // of scrolling with the map (2026-07-27 feedback: labels used to be baked
  // into the map canvas at the true map edge, so they scrolled off-screen
  // once zoomed/panned). Wrapped in AnimatedBuilder listening directly to
  // the TransformationController — rather than _zoom/_translation, which
  // only get updated in _syncFromController on interaction *end* — so the
  // labels track smoothly during an in-progress drag/pinch too.
  Widget _buildGridLabelOverlay() {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _transformationController,
        builder: (context, _) {
          final width = _viewportSize.width;
          final height = _viewportSize.height;
          if (width <= 0 || height <= 0) return const SizedBox.shrink();

          final m = _transformationController.value;
          final scale = m.getMaxScaleOnAxis();
          final t = m.getTranslation();
          final translation = Offset(t.x, t.y);

          const margin = 4.0;
          const lonLabelWidth = 34.0;
          const latLabelHeight = 18.0;

          final children = <Widget>[];
          for (var lon = MapBounds.minLon; lon <= MapBounds.maxLon; lon += 5) {
            final mapX = MapBounds.toOffset(MapBounds.minLat, lon).dx;
            final screenX = translation.dx + scale * mapX;
            if (screenX < -lonLabelWidth || screenX > width + lonLabelWidth) continue;
            children.add(Positioned(
              left: screenX.clamp(margin, math.max(margin, width - lonLabelWidth)),
              top: margin,
              child: _gridLabelChip('${lon.round()}E'),
            ));
          }
          for (var lat = MapBounds.minLat; lat <= MapBounds.maxLat; lat += 5) {
            final mapY = MapBounds.toOffset(lat, MapBounds.minLon).dy;
            final screenY = translation.dy + scale * mapY;
            if (screenY < -latLabelHeight || screenY > height + latLabelHeight) continue;
            children.add(Positioned(
              left: margin,
              top: screenY.clamp(margin, math.max(margin, height - latLabelHeight)),
              child: _gridLabelChip('${lat.round()}N'),
            ));
          }
          return Stack(children: children);
        },
      ),
    );
  }

  Widget _gridLabelChip(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.8),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 11, color: Colors.blueGrey.shade700, fontWeight: FontWeight.w600),
      ),
    );
  }

  // Dialog for entering the ship's name, pasting up to 3 typhoons' JTWC
  // warning texts, and toggling Display on/off for the ship and each
  // typhoon (2026-07-28 request). All manual-entry stand-ins until the real
  // voyage-plan CSV (no ship-name field, per NAVTOR/JRC ECDIS format) and
  // JTWC feed reader (TASKS.md, not yet implemented) are wired up.
  Future<void> _showLabelSettingsDialog() async {
    final shipController = TextEditingController(text: _shipName);
    final typhoonControllers = [
      for (final slot in _typhoonSlots) TextEditingController(text: slot.pastedText),
    ];
    final jtwcDisplayLocal = [for (final slot in _typhoonSlots) slot.jtwcDisplayEnabled];
    final parseErrors = List<String?>.filled(_typhoonSlots.length, null);

    // JMA auto-fetch state (2026-07-28 addition, per-slot): "Import from
    // JMA" (UI label; 2026-07-29 renamed from "Fetch from JMA" per user
    // request — see below) downloads+parses the latest VPTW60 bulletin
    // (see jma_feed_fetcher.dart)
    // into jmaFetched[i] — kept as the raw [JmaTyphoonInfo] (2026-07-28
    // redesign: "気象庁と米軍の予報を両方表示" — JTWC and JMA are now two
    // independent, simultaneously-displayable sources per slot rather than
    // one overriding the other, so there's no more reason to convert into
    // JtwcTyphoonInfo's shape at fetch time). Seeded from whatever's already
    // in `_typhoonSlots[i].jmaInfo` (a previous fetch from earlier in this
    // session, or one restored from the offline cache at launch — see
    // _TyphoonSlot.jmaRawXml — if any) so reopening this dialog shows the
    // current state rather than looking freshly empty.
    final jmaFetched = List<JmaTyphoonInfo>.generate(_typhoonSlots.length, (i) => _typhoonSlots[i].jmaInfo);
    // Raw XML + fetch timestamp behind jmaFetched above (2026-07-29 offline
    // cache addition) — kept as parallel local arrays for the same reason
    // jmaFetched itself is: dialog-local "draft" state, only written back
    // into _typhoonSlots on Save, seeded from whatever's already cached so
    // reopening this dialog doesn't look like the cache was lost.
    final jmaRawXmlLocal = [for (final slot in _typhoonSlots) slot.jmaRawXml];
    final jmaFetchedAtLocal = [for (final slot in _typhoonSlots) slot.jmaFetchedAtJst];
    final jmaDisplayLocal = [for (final slot in _typhoonSlots) slot.jmaDisplayEnabled];
    final jmaFetching = List<bool>.filled(_typhoonSlots.length, false);
    final jmaFetchError = List<String?>.filled(_typhoonSlots.length, null);

    // JTWC auto-fetch state (2026-07-29 addition, per-slot): "Import from
    // JTWC" downloads the region's current TC Warning Text (see
    // jtwc_feed_fetcher.dart) and, on success, writes it straight into
    // `typhoonControllers[i]` — the *same* text box a manual paste already
    // fills. Unlike the JMA source above, there's no separate parsed/raw
    // state to track here: JTWC only ever has the one representation
    // (pasted-or-fetched text, parsed at Save time same as always), so
    // reusing the existing text box means fetch results already get every
    // bit of existing behavior — persistence, re-parsing, Display toggle —
    // for free, with no new AppStateStorage fields needed.
    final jtwcFetching = List<bool>.filled(_typhoonSlots.length, false);
    final jtwcFetchError = List<String?>.filled(_typhoonSlots.length, null);

    // Marine Forecast (地方海上予報, VPCY51) dialog-local "draft" state
    // (2026-07-30 addition) — same pattern as the JMA typhoon fetch state
    // above: seeded from whatever's already cached/set so reopening this
    // dialog doesn't look like the previous fetch/Display setting was lost,
    // only written back into the real state fields on Save.
    var marineForecastDisplayLocal = _marineForecastDisplayEnabled;
    var marineForecastRawXmlsLocal = List<String>.from(_marineForecastRawXmls);
    var marineForecastFetchedAtLocal = _marineForecastFetchedAtJst;
    var marineForecastFetching = false;
    String? marineForecastError;

    // "Import All" state (2026-07-29 addition): unlike the per-slot fetch
    // state above (one bool/error per Typhoon block), these two buttons are
    // not tied to a particular slot — each press fills as many of slots
    // 1/2/3 as the source currently has active typhoons for (see
    // fetchAllJma/fetchAllJtwc below), so there's exactly one fetching-flag
    // and one status-message per *source*, not per slot.
    var jmaFetchingAll = false;
    var jtwcFetchingAll = false;
    String? jmaFetchAllStatus;
    String? jtwcFetchAllStatus;
    // Whether the *current* jmaFetchAllStatus/jtwcFetchAllStatus text is an
    // error/nothing-found message (shown in red, matching the per-slot
    // fetch buttons' error styling) or a success confirmation (shown in the
    // source's own color) — see fetchAllJma/fetchAllJtwc below.
    var jmaFetchAllIsError = false;
    var jtwcFetchAllIsError = false;
    // Guards against calling a StatefulBuilder's setState after this dialog
    // has already been popped (Cancel/Save) while a fetch is still
    // in-flight — set false in both action handlers below, checked before
    // every setDialogState call inside fetchJma's async continuations.
    var dialogOpen = true;

    await showDialog<void>(
      context: context,
      // Explicit false (2026-07-28, Agent review finding): this dialog can
      // have an "Import from JMA" request in flight, and the default (true)
      // lets a barrier tap dismiss the dialog without going through either
      // action button below — neither of which would then run, so
      // `dialogOpen` would stay true and a fetch completing afterward could
      // call setDialogState on an already-disposed StatefulBuilder (a
      // "setState() called after dispose()" crash). Forcing Cancel/Save as
      // the only way out keeps `dialogOpen = false` reliably set on every
      // dismissal path.
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            Widget displayCheckbox(String labelText, Color labelColor, bool value, ValueChanged<bool?> onChanged) {
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Checkbox(value: value, onChanged: onChanged),
                  Text(labelText, style: TextStyle(color: labelColor, fontWeight: FontWeight.w600)),
                ],
              );
            }

            Future<void> fetchJma(int i) async {
              setDialogState(() {
                jmaFetching[i] = true;
                jmaFetchError[i] = null;
              });
              try {
                final result = await fetchLatestJmaTyphoon();
                if (!dialogOpen) return;
                if (result.info.isEmpty) {
                  // No active bulletin right now — *not* an error, and
                  // deliberately leaves jmaFetched[i]/jmaRawXmlLocal[i]/
                  // jmaFetchedAtLocal[i] untouched: if a previous fetch
                  // (this session or a restored cache) already has data,
                  // that stays visible rather than being wiped out by "I
                  // checked again and nothing's currently active" (2026-07-29
                  // offline-cache addition — this matters more now that the
                  // result can be looked at days later at sea with no way to
                  // re-check).
                  setDialogState(() {
                    jmaFetching[i] = false;
                    jmaFetchError[i] = '現在、気象庁から発表中の台風情報が見つかりませんでした。';
                  });
                  return;
                }
                setDialogState(() {
                  jmaFetching[i] = false;
                  jmaFetched[i] = result.info;
                  jmaRawXmlLocal[i] = result.rawXml;
                  jmaFetchedAtLocal[i] = DateTime.now();
                  // Auto-enable Display on a successful fetch (2026-07-28,
                  // and 2026-07-29 for fetchJtwc below): the whole point of
                  // pressing this button is to see the result, so requiring
                  // a *second* click on a separate checkbox before anything
                  // shows would be needless friction.
                  jmaDisplayLocal[i] = true;
                  jmaFetchError[i] = null;
                });
              } catch (e) {
                // Network/parse failure — including the expected "no
                // connectivity right now" case at sea. Leaves any existing
                // cached fetch (jmaFetched/jmaRawXmlLocal/jmaFetchedAtLocal)
                // untouched so it's still shown, only the error line is new.
                if (!dialogOpen) return;
                setDialogState(() {
                  jmaFetching[i] = false;
                  jmaFetchError[i] = '取得に失敗しました: $e';
                });
              }
            }

            // JTWC fetch (2026-07-29 addition): unlike fetchJma above, this
            // writes straight into typhoonControllers[i].text — the same
            // text box a manual paste already fills — rather than into a
            // separate local array, since JTWC has only the one
            // representation in this app (see jtwc_feed_fetcher.dart's
            // fetchLatestJtwcWarningText doc comment). Everything after
            // that (Save-time parsing/validation, persistence, Display) is
            // therefore identical to the manual-paste path with no further
            // wiring needed here.
            Future<void> fetchJtwc(int i) async {
              setDialogState(() {
                jtwcFetching[i] = true;
                jtwcFetchError[i] = null;
              });
              try {
                final text = await fetchLatestJtwcWarningText();
                if (!dialogOpen) return;
                if (text == null) {
                  // No active storm in the region right now — *not* an
                  // error, and deliberately leaves typhoonControllers[i]'s
                  // existing text untouched (same "don't wipe out what's
                  // already there" principle as fetchJma's isEmpty branch
                  // above).
                  setDialogState(() {
                    jtwcFetching[i] = false;
                    jtwcFetchError[i] = '現在、この海域で発表中の台風情報が見つかりませんでした。';
                  });
                  return;
                }
                setDialogState(() {
                  jtwcFetching[i] = false;
                  typhoonControllers[i].text = text;
                  jtwcDisplayLocal[i] = true;
                  jtwcFetchError[i] = null;
                });
              } catch (e) {
                // Network/parse failure — including the expected "no
                // connectivity right now" case at sea. Leaves
                // typhoonControllers[i]'s existing text untouched so it's
                // still shown, only the error line is new.
                if (!dialogOpen) return;
                setDialogState(() {
                  jtwcFetching[i] = false;
                  jtwcFetchError[i] = '取得に失敗しました: $e';
                });
              }
            }

            // Marine Forecast fetch (2026-07-30 addition): fetches every
            // currently-published VPCY51 (地方海上予報) bulletin (see
            // jma_marine_feed_fetcher.dart's fetchLatestMarineForecast — one
            // per regional office, when more than one office has a bulletin
            // out at once) and keeps only the ones that parsed cleanly.
            // Unlike fetchJma above, this isn't per-slot — one press updates
            // the single nationwide layer, so it has its own status
            // variable rather than a per-index array.
            Future<void> fetchMarineForecast() async {
              setDialogState(() {
                marineForecastFetching = true;
                marineForecastError = null;
              });
              try {
                final fetched = await fetchLatestMarineForecast();
                if (!dialogOpen) return;
                final validBulletins = fetched.bulletins.where((b) => b.parseError == null).toList();
                if (validBulletins.isEmpty) {
                  // Two different reasons look the same here — nothing to
                  // show either way — but worth telling apart in the message:
                  // "nothing published right now" (normal outside the
                  // 6/12/18/24 JST issue windows) vs. "found bulletins but
                  // every one failed to parse" (a real problem — same class
                  // of surprise the "Marine forecast (debug)" dialog exists
                  // to catch in detail, see _showMarineForecastDebugDialog).
                  // Leaves marineForecastRawXmlsLocal/FetchedAtLocal
                  // untouched either way — same "don't wipe out what's
                  // already there" principle as fetchJma's isEmpty branch.
                  setDialogState(() {
                    marineForecastFetching = false;
                    marineForecastError = fetched.bulletins.isEmpty
                        ? '現在、地方海上予報の発表が見つかりませんでした（6/12/18/24時JST前後に再度お試しください）。'
                        : '取得はできましたが解析に失敗しました。詳細は「Marine forecast (debug)」で確認してください。';
                  });
                  return;
                }
                setDialogState(() {
                  marineForecastFetching = false;
                  marineForecastRawXmlsLocal = [for (final b in validBulletins) b.rawXml];
                  marineForecastFetchedAtLocal = DateTime.now();
                  // Auto-enable Display on a successful fetch — same
                  // reasoning as fetchJma/fetchJtwc above.
                  marineForecastDisplayLocal = true;
                  marineForecastError = null;
                });
              } catch (e) {
                if (!dialogOpen) return;
                setDialogState(() {
                  marineForecastFetching = false;
                  marineForecastError = '取得に失敗しました: $e';
                });
              }
            }

            // "Import All" (2026-07-29 addition, TASKS.md「複数台風が同時に
            // 発表されている場合の対応」): finds every currently-active
            // typhoon for a source (up to 3 — see fetchActiveJmaTyphoons/
            // fetchActiveJtwcWarningTexts) and fills Typhoon 1/2/3 with them
            // in order, in one click, rather than requiring the user to
            // know in advance how many are active and press each slot's own
            // per-slot fetch button individually. Slots beyond however many
            // were found are left untouched (not cleared) — same
            // "don't erase what's already there" principle the per-slot
            // fetch closures above already follow for their own "nothing
            // found" case.
            Future<void> fetchAllJma() async {
              setDialogState(() {
                jmaFetchingAll = true;
                jmaFetchAllStatus = null;
              });
              try {
                final results = await fetchActiveJmaTyphoons();
                if (!dialogOpen) return;
                if (results.isEmpty) {
                  setDialogState(() {
                    jmaFetchingAll = false;
                    jmaFetchAllStatus = '現在、気象庁から発表中の台風情報が見つかりませんでした。';
                    jmaFetchAllIsError = true;
                  });
                  return;
                }
                setDialogState(() {
                  jmaFetchingAll = false;
                  for (var i = 0; i < results.length && i < jmaFetched.length; i++) {
                    jmaFetched[i] = results[i].info;
                    jmaRawXmlLocal[i] = results[i].rawXml;
                    jmaFetchedAtLocal[i] = DateTime.now();
                    jmaDisplayLocal[i] = true;
                  }
                  jmaFetchAllStatus = _importedToSlotsLabel(results.length);
                  jmaFetchAllIsError = false;
                });
              } catch (e) {
                if (!dialogOpen) return;
                setDialogState(() {
                  jmaFetchingAll = false;
                  jmaFetchAllStatus = '取得に失敗しました: $e';
                  jmaFetchAllIsError = true;
                });
              }
            }

            Future<void> fetchAllJtwc() async {
              setDialogState(() {
                jtwcFetchingAll = true;
                jtwcFetchAllStatus = null;
              });
              try {
                final texts = await fetchActiveJtwcWarningTexts();
                if (!dialogOpen) return;
                if (texts.isEmpty) {
                  setDialogState(() {
                    jtwcFetchingAll = false;
                    jtwcFetchAllStatus = '現在、この海域で発表中の台風情報が見つかりませんでした。';
                    jtwcFetchAllIsError = true;
                  });
                  return;
                }
                setDialogState(() {
                  jtwcFetchingAll = false;
                  for (var i = 0; i < texts.length && i < typhoonControllers.length; i++) {
                    typhoonControllers[i].text = texts[i];
                    jtwcDisplayLocal[i] = true;
                  }
                  jtwcFetchAllStatus = _importedToSlotsLabel(texts.length);
                  jtwcFetchAllIsError = false;
                });
              } catch (e) {
                if (!dialogOpen) return;
                setDialogState(() {
                  jtwcFetchingAll = false;
                  jtwcFetchAllStatus = '取得に失敗しました: $e';
                  jtwcFetchAllIsError = true;
                });
              }
            }

            return AlertDialog(
              title: const Text('Information'),
              content: SizedBox(
                width: 480,
                height: 620,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text("Ship's Name", style: TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      TextField(
                        controller: shipController,
                        decoration: const InputDecoration(
                          hintText: 'e.g. MV Example',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                      const Divider(height: 28),
                      // Marine Forecast (地方海上予報, VPCY51) section
                      // (2026-07-30 addition) — production UI replacing the
                      // "Marine forecast (debug)" text-only verification
                      // dialog (kept as a separate AppBar button for raw
                      // inspection) now that real-data fetches have
                      // confirmed jma_marine_xml_parser.dart reads actual
                      // bulletins correctly. One nationwide layer, not
                      // per-typhoon-slot — see fetchMarineForecast above.
                      const Text('Marine Forecast (JMA regional sea areas)',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      Text(
                        '地方海上予報（波高）を地図上に区域ごと色分け表示します。'
                        '表示範囲南側（フィリピン近海）は予報区の対象外のため表示されません。',
                        style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          displayCheckbox(
                            'Display',
                            _marineForecastAccentColor,
                            marineForecastDisplayLocal,
                            (v) => setDialogState(() => marineForecastDisplayLocal = v ?? false),
                          ),
                          const SizedBox(width: 8),
                          OutlinedButton.icon(
                            onPressed: marineForecastFetching ? null : fetchMarineForecast,
                            icon: marineForecastFetching
                                ? const SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : Icon(Icons.cloud_download, size: 16, color: _marineForecastAccentColor),
                            label: Text(marineForecastFetching ? 'Importing...' : 'Import from JMA'),
                          ),
                        ],
                      ),
                      if (marineForecastError != null) ...[
                        const SizedBox(height: 4),
                        Text(marineForecastError!, style: const TextStyle(fontSize: 12, color: Colors.red)),
                      ],
                      if (marineForecastRawXmlsLocal.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          '${marineForecastRawXmlsLocal.length} bulletin(s) loaded.',
                          style: TextStyle(fontSize: 11, color: _marineForecastAccentColor),
                        ),
                      ],
                      if (marineForecastFetchedAtLocal != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          'Cached: ${_formatDateTime(marineForecastFetchedAtLocal!)}',
                          style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
                        ),
                      ],
                      const Divider(height: 28),
                      // "Import All" (2026-07-29 addition, labeled "Import"
                      // rather than "Fetch" per 2026-07-29 user request —
                      // see the per-slot "Import from JMA"/"Import from
                      // JTWC" buttons further below for the same wording
                      // choice): finds every currently-active typhoon for a
                      // source (up to 3) and fills Typhoon 1/2/3 with them
                      // in one click — see fetchAllJma/fetchAllJtwc above
                      // (function/variable names keep the pre-existing
                      // "fetch" wording since they're not user-visible, only
                      // the UI text changed). The per-slot buttons further
                      // below are unchanged and still useful for refreshing
                      // just one slot.
                      const Text('Import All (multiple typhoons at once)',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      Text(
                        'Finds every typhoon currently active for a source (up to 3) and '
                        'imports them into Typhoon 1/2/3 in order.',
                        style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          OutlinedButton.icon(
                            onPressed: jmaFetchingAll ? null : fetchAllJma,
                            icon: jmaFetchingAll
                                ? const SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : Icon(Icons.cloud_download, size: 16, color: _jmaColor),
                            label: Text(jmaFetchingAll ? 'Importing...' : 'Import All (JMA)'),
                          ),
                          const SizedBox(width: 8),
                          OutlinedButton.icon(
                            onPressed: jtwcFetchingAll ? null : fetchAllJtwc,
                            icon: jtwcFetchingAll
                                ? const SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : Icon(Icons.cloud_download, size: 16, color: _jtwcColor),
                            label: Text(jtwcFetchingAll ? 'Importing...' : 'Import All (JTWC)'),
                          ),
                        ],
                      ),
                      if (jmaFetchAllStatus != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          jmaFetchAllStatus!,
                          style: TextStyle(fontSize: 11, color: jmaFetchAllIsError ? Colors.red : _jmaColor),
                        ),
                      ],
                      if (jtwcFetchAllStatus != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          jtwcFetchAllStatus!,
                          style: TextStyle(fontSize: 11, color: jtwcFetchAllIsError ? Colors.red : _jtwcColor),
                        ),
                      ],
                      for (var i = 0; i < _typhoonSlots.length; i++) ...[
                        const Divider(height: 28),
                        Row(
                          children: [
                            Expanded(
                              child: Text('Typhoon ${i + 1}',
                                  style: const TextStyle(fontWeight: FontWeight.bold)),
                            ),
                            TextButton(
                              // Clears both sources for this slot (2026-07-28:
                              // previously only cleared the JTWC paste box —
                              // extended to also drop any JMA fetch, so
                              // "Clear" reliably means "start this slot over"
                              // for either source).
                              onPressed: () => setDialogState(() {
                                typhoonControllers[i].clear();
                                parseErrors[i] = null;
                                jmaFetched[i] = JmaTyphoonInfo.empty;
                                jmaRawXmlLocal[i] = null;
                                jmaFetchedAtLocal[i] = null;
                                jmaDisplayLocal[i] = false;
                                jmaFetchError[i] = null;
                                // 2026-07-29 bug fix: JTWC Display wasn't
                                // being reset here, so a slot that had JTWC
                                // Display On kept showing the checkbox
                                // checked after Clear even though the pasted
                                // text (and thus the map marker) was gone —
                                // inconsistent with JMA Display just above,
                                // and with this button's own "for either
                                // source" comment.
                                jtwcDisplayLocal[i] = false;
                                jtwcFetchError[i] = null;
                              }),
                              child: const Text('Clear'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        // JMA source (2026-07-28: shown above JTWC since
                        // fetching is the primary/first-choice path — the
                        // paste box below is the fallback for when auto
                        // fetch isn't available/desired).
                        Row(
                          children: [
                            displayCheckbox(
                              'JMA Display',
                              _jmaColor,
                              jmaDisplayLocal[i],
                              (v) => setDialogState(() => jmaDisplayLocal[i] = v ?? false),
                            ),
                            const SizedBox(width: 8),
                            OutlinedButton.icon(
                              onPressed: jmaFetching[i] ? null : () => fetchJma(i),
                              icon: jmaFetching[i]
                                  ? const SizedBox(
                                      width: 14,
                                      height: 14,
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    )
                                  : const Icon(Icons.cloud_download, size: 16),
                              label: Text(jmaFetching[i] ? 'Importing...' : 'Import from JMA'),
                            ),
                          ],
                        ),
                        if (jmaFetchError[i] != null) ...[
                          const SizedBox(height: 4),
                          Text(jmaFetchError[i]!, style: const TextStyle(fontSize: 12, color: Colors.red)),
                        ],
                        if (!jmaFetched[i].isEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            'JMA: ${jmaFetched[i].designation ?? jmaFetched[i].classification ?? "(unnamed)"}'
                            '${jmaFetched[i].centralPressureHpa == null ? '' : ' · ${jmaFetched[i].centralPressureHpa}hPa'}'
                            '${jmaFetched[i].observedAtJst == null ? '' : ' (${_formatDateTime(jmaFetched[i].observedAtJst!)})'}',
                            style: TextStyle(fontSize: 11, color: _jmaColor),
                          ),
                          // Offline-cache freshness readout (2026-07-29
                          // addition): distinct from the bulletin's own
                          // observed-at time above — this is *when this
                          // device last successfully talked to JMA*, which
                          // is what a captain offline for days actually
                          // needs to judge how stale the cache is.
                          if (jmaFetchedAtLocal[i] != null) ...[
                            const SizedBox(height: 2),
                            Text(
                              'Cached: ${_formatDateTime(jmaFetchedAtLocal[i]!)}',
                              style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
                            ),
                          ],
                        ],
                        const SizedBox(height: 10),
                        // JTWC source (pasted warning text, or 2026-07-29:
                        // fetched via "Import from JTWC" below, which just
                        // fills the same text box — see fetchJtwc's doc
                        // comment) — unchanged parsing/validation behavior,
                        // with its own Display checkbox instead of one
                        // shared with JMA.
                        Row(
                          children: [
                            displayCheckbox(
                              'JTWC Display',
                              _jtwcColor,
                              jtwcDisplayLocal[i],
                              (v) => setDialogState(() => jtwcDisplayLocal[i] = v ?? true),
                            ),
                            const SizedBox(width: 8),
                            OutlinedButton.icon(
                              onPressed: jtwcFetching[i] ? null : () => fetchJtwc(i),
                              icon: jtwcFetching[i]
                                  ? const SizedBox(
                                      width: 14,
                                      height: 14,
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    )
                                  : const Icon(Icons.cloud_download, size: 16),
                              label: Text(jtwcFetching[i] ? 'Importing...' : 'Import from JTWC'),
                            ),
                          ],
                        ),
                        if (jtwcFetchError[i] != null) ...[
                          const SizedBox(height: 4),
                          Text(jtwcFetchError[i]!, style: const TextStyle(fontSize: 12, color: Colors.red)),
                        ],
                        const SizedBox(height: 4),
                        Text(
                          'Paste the JTWC warning text below, or use "Import from JTWC" above; '
                          'the number/name (e.g. "11W (NOUL)") and central pressure (e.g. '
                          '"980hPa") are extracted automatically. Leave blank and Save to clear.',
                          style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                        ),
                        const SizedBox(height: 4),
                        TextField(
                          controller: typhoonControllers[i],
                          maxLines: 5,
                          style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                          decoration: const InputDecoration(
                            hintText: 'Paste WTPN31 PGTW ... warning text here',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                        if (!_typhoonSlots[i].jtwcInfo.isEmpty) ...[
                          const SizedBox(height: 6),
                          Text('Current: ${_typhoonSlots[i].jtwcInfo.summary}',
                              style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                        ],
                        if (parseErrors[i] != null) ...[
                          const SizedBox(height: 6),
                          Text(parseErrors[i]!, style: const TextStyle(fontSize: 12, color: Colors.red)),
                        ],
                      ],
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    dialogOpen = false;
                    Navigator.pop(dialogContext);
                  },
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () {
                    // Validate every slot's JTWC paste box before applying
                    // anything, so a typo in one box doesn't silently
                    // discard the others — fix the error(s) shown and press
                    // Save again. JMA data needs no such validation step
                    // here — it was already a successfully-parsed
                    // JmaTyphoonInfo at fetch time (see fetchJma above).
                    final parsedJtwc = List<JtwcTyphoonInfo?>.filled(_typhoonSlots.length, null);
                    var hasError = false;
                    for (var i = 0; i < _typhoonSlots.length; i++) {
                      final pastedText = typhoonControllers[i].text;
                      if (pastedText.trim().isEmpty) {
                        parsedJtwc[i] = JtwcTyphoonInfo.empty;
                        continue;
                      }
                      final info = parseJtwcWarningText(pastedText);
                      if (info.designation == null) {
                        hasError = true;
                        parseErrors[i] = "Couldn't find a \"TYPHOON <number> (<name>)\" "
                            'line in the pasted text.';
                        continue;
                      }
                      parsedJtwc[i] = info;
                    }
                    if (hasError) {
                      setDialogState(() {});
                      return;
                    }
                    // Playback start time follows slot 0's warning (2026-07-28
                    // request: "再生開始のタイミングは...「読み込んだ情報の
                    // 発表時間」とする", e.g. "250000Z" → 25th 09:00 JST) —
                    // resolved against the real current date, not the
                    // possibly-already-shifted _startTime, so re-saving the
                    // same text repeatedly doesn't drift the year/month. When
                    // slot 0 has JMA data fetched, its bulletin's own exact
                    // JST time (already year/month-qualified — no
                    // day-only-plus-disambiguation needed, unlike JTWC's
                    // issuedAtJst) is used directly and takes priority,
                    // regardless of which source(s) end up Display-on — a
                    // fetched-but-hidden JMA time is still more precise than
                    // reconstructing one from JTWC's day-only field.
                    final slot0Jma = jmaFetched[0];
                    final newStartTime = slot0Jma.isEmpty
                        ? parsedJtwc[0]?.issuedAtJst(DateTime.now())
                        : (slot0Jma.observedAtJst ?? slot0Jma.reportDateTimeJst);
                    // Which source actually anchored playback *before* this
                    // Save — JMA if slot 0 already had JMA data, else JTWC
                    // (same priority rule as newStartTime's own ternary
                    // above). Whether that source's own raw input changed in
                    // this Save — not whether the *resolved* newStartTime
                    // differs from the current _startTime — is what should
                    // decide whether to reset (2026-07-29 second bug report:
                    // comparing resolved values, as a first attempt at this
                    // fix did, still reset when JMA was fetched for the
                    // *first time* alongside an already-running JTWC track —
                    // switching which source resolves newStartTime naturally
                    // produces a different value even though nothing the
                    // user considers "the anchor" changed. JmaTyphoonInfo has
                    // no value equality, so comparing jmaFetched[0] against
                    // the slot's stored jmaInfo by reference works out
                    // correctly anyway: they're literally the same object
                    // unless a fetch reassigned jmaFetched[0] in this dialog
                    // session — see jmaFetched's own initialization below).
                    final previousJma = _typhoonSlots[0].jmaInfo;
                    final anchorSourceChanged = previousJma.isEmpty
                        ? typhoonControllers[0].text != _typhoonSlots[0].pastedText // JTWC was anchoring
                        : !identical(slot0Jma, previousJma); // JMA was already anchoring
                    setState(() {
                      _shipName = shipController.text;
                      // 2026-07-29 bug fix: this used to reset to 0 whenever
                      // `newStartTime != null` — true on *every* Save as
                      // long as slot 0 has JTWC text pasted and/or JMA
                      // fetched — even when Save was only pressed to toggle
                      // a Display checkbox, or to add a second source
                      // alongside one that was already anchoring playback,
                      // with nothing about *that* anchoring source's own
                      // input changed. Now only resets when the source that
                      // actually determines newStartTime has itself changed
                      // (edited/new JTWC text, or a fresh JMA fetch) — see
                      // anchorSourceChanged above.
                      if (newStartTime != null && anchorSourceChanged) {
                        _startTime = newStartTime;
                        // Slider position 0 = _startTime itself, so "start
                        // of playback" actually lands on the announced time
                        // rather than wherever the slider happened to be
                        // left from a previous session/track.
                        _offsetHours = 0;
                      }
                      for (var i = 0; i < _typhoonSlots.length; i++) {
                        _typhoonSlots[i].pastedText = typhoonControllers[i].text;
                        _typhoonSlots[i].jtwcInfo = parsedJtwc[i]!;
                        _typhoonSlots[i].jtwcDisplayEnabled = jtwcDisplayLocal[i];
                        _typhoonSlots[i].jmaInfo = jmaFetched[i];
                        _typhoonSlots[i].jmaRawXml = jmaRawXmlLocal[i];
                        _typhoonSlots[i].jmaFetchedAtJst = jmaFetchedAtLocal[i];
                        _typhoonSlots[i].jmaDisplayEnabled = jmaDisplayLocal[i];
                      }
                      // Marine Forecast (2026-07-30 addition) — write back
                      // the dialog-local draft state (same pattern as the
                      // typhoon slots above) and rebuild the parsed-by-area
                      // cache _marineForecastAreaPolygons reads from.
                      _marineForecastDisplayEnabled = marineForecastDisplayLocal;
                      _marineForecastRawXmls = marineForecastRawXmlsLocal;
                      _marineForecastFetchedAtJst = marineForecastFetchedAtLocal;
                      _marineForecastByArea = _parseMarineForecastByArea(marineForecastRawXmlsLocal);
                    });
                    _saveState();
                    dialogOpen = false;
                    Navigator.pop(dialogContext);
                  },
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );
    shipController.dispose();
    for (final c in typhoonControllers) {
      c.dispose();
    }
  }

  // --- Marine forecast (VPCY51) debug fetch (2026-07-29 addition) ---
  //
  // Temporary verification tool, NOT the eventual production feature — see
  // TASKS.md "regular.xmlの実データ裏取り・パーサーの実データ確認（最優先）".
  // jma_marine_xml_parser.dart's fields are all sourced from JMA's official
  // PDF and have never been checked against a real bulletin (Cowork's
  // sandbox can't reach a fresh regular.xml — see docs/data-format-notes.md
  // "Cowork環境からのregular.xml取得の制約"). This button lets the app itself
  // fetch over the Windows machine's real network path (same verification
  // pattern already used for the JTWC/JMA typhoon fetchers) and shows the
  // raw parsed result — including any per-bulletin parse error — so a human
  // can compare it against the source XML / real forecast text. Once real
  // data confirms (or exposes bugs in) the parser, the eventual replacement
  // is the polished "取得UI" + MapPainter polygon-fill drawing described in
  // TASKS.md; this dialog is intentionally plain (no map drawing, no
  // persistence) since its only job is answering "does the parser read real
  // data correctly?".
  Future<void> _showMarineForecastDebugDialog() async {
    var loading = false;
    String? errorText;
    JmaMarineFetchResult? result;

    // Same dialog-lifecycle guard as _showLabelSettingsDialog's "Import from
    // JMA" button (barrierDismissible: false + a local dialogOpen bool
    // checked before every setDialogState call after an await): without it,
    // dismissing this dialog (barrier tap / Close / back) while a fetch is
    // in flight would let runFetch()'s setDialogState fire after the dialog
    // State is disposed once the fetch resolves — the same defect class
    // documented in docs/operation-rules.md item 5 (Agent review caught this
    // omission on the first pass; fixed here before shipping).
    var dialogOpen = true;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            Future<void> runFetch() async {
              setDialogState(() {
                loading = true;
                errorText = null;
              });
              try {
                final fetched = await fetchLatestMarineForecast();
                if (!dialogOpen) return;
                setDialogState(() {
                  result = fetched;
                  loading = false;
                });
              } on JmaMarineFetchException catch (e) {
                if (!dialogOpen) return;
                setDialogState(() {
                  errorText = e.toString();
                  loading = false;
                });
              } catch (e) {
                // Broad catch-all deliberately kept in addition to the
                // JmaMarineFetchException branch above: this dialog's whole
                // purpose is catching real-data surprises in
                // jma_marine_xml_parser.dart, whose schema is explicitly
                // unverified (see that file's top-of-file caveat). Without
                // this, an exception type other than
                // JmaMarineXmlParseException/JmaMarineFetchException (e.g. a
                // null-check or type error from an unexpected real bulletin
                // shape) would propagate uncaught, leaving `loading` stuck
                // true forever with no visible error (Agent review flagged
                // this gap).
                if (!dialogOpen) return;
                setDialogState(() {
                  errorText = 'Unexpected error: $e';
                  loading = false;
                });
              }
            }

            return AlertDialog(
              title: const Text('Marine forecast (VPCY51) — debug'),
              content: SizedBox(
                width: 480,
                height: 420,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'regular.xmlから地方海上予報（VPCY51）を取得し、パーサー結果をそのまま表示します'
                      '（検証用、地図・保存には反映されません）。',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                    ),
                    const SizedBox(height: 8),
                    FilledButton(
                      onPressed: loading ? null : runFetch,
                      child: Text(loading ? 'Fetching...' : 'Fetch regular.xml (VPCY51)'),
                    ),
                    if (errorText != null) ...[
                      const SizedBox(height: 8),
                      Text(errorText!, style: const TextStyle(color: Colors.red)),
                    ],
                    const SizedBox(height: 8),
                    Expanded(
                      child: result == null
                          ? Center(
                              child: Text(
                                loading ? '' : 'Not fetched yet.',
                                style: TextStyle(color: Colors.grey.shade600),
                              ),
                            )
                          : _buildMarineForecastDebugResult(result!),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    dialogOpen = false;
                    Navigator.pop(dialogContext);
                  },
                  child: const Text('Close'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildMarineForecastDebugResult(JmaMarineFetchResult result) {
    if (result.bulletins.isEmpty) {
      return Center(
        child: Text(
          'No 地方海上予報 entry found in regular.xml right now\n'
          '(normal outside the ~6/12/18/24 JST issue windows).',
          style: TextStyle(color: Colors.grey.shade600),
        ),
      );
    }
    return ListView(
      children: [
        for (final bulletin in result.bulletins) _buildMarineBulletinDebugTile(bulletin),
      ],
    );
  }

  Widget _buildMarineBulletinDebugTile(JmaMarineBulletin bulletin) {
    if (bulletin.parseError != null) {
      return Card(
        color: Colors.red.shade50,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Text(
            'PARSE ERROR\n${bulletin.sourceUrl}\n${bulletin.parseError}',
            style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
          ),
        ),
      );
    }
    return ExpansionTile(
      title: Text(
        '${bulletin.forecasts.length} forecast(s) — ${bulletin.sourceUrl}',
        style: const TextStyle(fontSize: 11),
      ),
      children: [
        for (final f in bulletin.forecasts)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
            child: Text(
              _formatMarineForecastDebugLine(f),
              style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
            ),
          ),
      ],
    );
  }

  // Plain-text one-line summary of one MarineWaveForecast for the debug
  // dialog above — built with a StringBuffer (rather than one large
  // interpolated literal) so the conditional "→ becoming" tail stays easy to
  // read/verify against jma_marine_xml_parser.dart's field doc comments.
  String _formatMarineForecastDebugLine(MarineWaveForecast f) {
    final buffer = StringBuffer();
    final name = f.areaName ?? marineAreaNames[f.areaCode] ?? '?';
    buffer.write('[${f.areaCode}] $name (${f.periodLabel ?? "-"}): ');
    buffer.write('base=${f.baseHeightM?.toString() ?? "-"}m');
    if (f.baseDescription != null) buffer.write(' (${f.baseDescription})');
    if (f.becoming.isNotEmpty) {
      final parts = [
        for (final b in f.becoming) '${b.timeModifierText ?? "?"}: ${b.heightM?.toString() ?? "-"}m',
      ];
      buffer.write('  →  ${parts.join(", ")}');
    }
    return buffer.toString();
  }

  // --- Open-Meteo marine weather trial (personal build only, 2026-07-29) ---
  //
  // See build_flags.dart's kPersonalBuild doc comment and
  // docs/devlog-online-xml.md "Open-Meteoとの比較" for why this exists and
  // why it's gated: Open-Meteo's free tier is documented as non-commercial-
  // use only. Capt.Edge asked to try it out (as an alternative/supplement to
  // the VPCY51 debug dialog above) before deciding whether to invest further
  // or drop it — so, same spirit as that dialog, this is a trial/
  // verification UI, not yet wired into the map itself.
  Future<void> _showOpenMeteoDebugDialog() async {
    // Default query point: the first currently-displayed ship's interpolated
    // position at the current playback time, if one is loaded (matches what
    // the user is actually looking at); otherwise MapBounds' own default
    // center (same fallback the map itself uses before any data is loaded).
    final defaultTracks = _activeShipTracks;
    final defaultPosition = defaultTracks.isNotEmpty
        ? positionAt(defaultTracks.first.track, _currentTime)
        : const LatLng(MapBounds.defaultCenterLat, MapBounds.defaultCenterLon);

    final latController = TextEditingController(text: defaultPosition.latitude.toStringAsFixed(4));
    final lonController = TextEditingController(text: defaultPosition.longitude.toStringAsFixed(4));
    var loading = false;
    String? errorText;
    OpenMeteoMarineResult? result;

    // Same dialog-lifecycle guard as the VPCY51 debug dialog above (and
    // _showLabelSettingsDialog's "Import from JMA") — see that dialog's doc
    // comment for the exact failure mode this prevents.
    var dialogOpen = true;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            Future<void> runFetch() async {
              final lat = double.tryParse(latController.text.trim());
              final lon = double.tryParse(lonController.text.trim());
              if (lat == null || lon == null) {
                setDialogState(() => errorText = '緯度・経度を数値で入力してください。');
                return;
              }
              setDialogState(() {
                loading = true;
                errorText = null;
              });
              try {
                final fetched = await fetchOpenMeteoMarine(latitude: lat, longitude: lon);
                if (!dialogOpen) return;
                setDialogState(() {
                  result = fetched;
                  loading = false;
                });
              } catch (e) {
                // Broad catch-all (same reasoning as the VPCY51 debug dialog
                // above): this is a first trial of a third-party API this
                // app has never called before, so an unexpected response
                // shape throwing something other than
                // OpenMeteoFetchException is a real possibility, not just a
                // theoretical one.
                if (!dialogOpen) return;
                setDialogState(() {
                  errorText = e.toString();
                  loading = false;
                });
              }
            }

            return AlertDialog(
              title: const Text('Open-Meteo marine (trial, personal build)'),
              content: SizedBox(
                width: 480,
                height: 460,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      '個人利用限定の試用機能です。地図・保存には反映されません。'
                      'データ提供: DWD（ドイツ気象庁）via Open-Meteo.com',
                      style: TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: latController,
                            decoration: const InputDecoration(labelText: 'Latitude', isDense: true),
                            keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: lonController,
                            decoration: const InputDecoration(labelText: 'Longitude', isDense: true),
                            keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    FilledButton(
                      onPressed: loading ? null : runFetch,
                      child: Text(loading ? 'Fetching...' : 'Fetch wave forecast'),
                    ),
                    if (errorText != null) ...[
                      const SizedBox(height: 8),
                      Text(errorText!, style: const TextStyle(color: Colors.red)),
                    ],
                    const SizedBox(height: 8),
                    Expanded(
                      child: result == null
                          ? Center(
                              child: Text(
                                loading ? '' : 'Not fetched yet.',
                                style: TextStyle(color: Colors.grey.shade600),
                              ),
                            )
                          : _buildOpenMeteoDebugResult(result!),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    dialogOpen = false;
                    Navigator.pop(dialogContext);
                  },
                  child: const Text('Close'),
                ),
              ],
            );
          },
        );
      },
    );
    latController.dispose();
    lonController.dispose();
  }

  Widget _buildOpenMeteoDebugResult(OpenMeteoMarineResult result) {
    final now = _currentTime;
    // Only show from "now" (playback current time) onward, capped at 48
    // rows, so the list stays short enough to scan by eye rather than
    // dumping the full multi-day series — this is a trial UI, not a data
    // export tool. Falls back to showing the beginning of the series if
    // every returned point is already in the past (e.g. playback scrubbed
    // to a time before the forecast's start).
    final upcoming = result.points.where((p) => !p.time.isBefore(now)).take(48).toList();
    final shown = upcoming.isEmpty ? result.points.take(48).toList() : upcoming;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Grid cell used: ${result.latitude.toStringAsFixed(3)}, ${result.longitude.toStringAsFixed(3)}',
          style: const TextStyle(fontSize: 11, color: Colors.grey),
        ),
        const SizedBox(height: 4),
        Expanded(
          child: ListView.builder(
            itemCount: shown.length,
            itemBuilder: (context, index) {
              final p = shown[index];
              final isNow = index == 0 && upcoming.isNotEmpty;
              return Text(
                '${_formatOpenMeteoDebugTime(p.time)}  '
                'wave=${p.waveHeightM?.toStringAsFixed(1) ?? "-"}m  '
                'dir=${p.waveDirectionDeg?.toStringAsFixed(0) ?? "-"}°  '
                'period=${p.wavePeriodS?.toStringAsFixed(1) ?? "-"}s'
                '${isNow ? "  ← now" : ""}',
                style: TextStyle(
                  fontSize: 12,
                  fontFamily: 'monospace',
                  fontWeight: isNow ? FontWeight.bold : FontWeight.normal,
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  String _formatOpenMeteoDebugTime(DateTime t) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(t.month)}/${two(t.day)} ${two(t.hour)}:${two(t.minute)}';
  }

  // --- Wave field map overlay (personal build only, 2026-07-29) ---
  //
  // Follow-up to the Open-Meteo text-only trial dialog above: once that
  // confirmed real wave data could be fetched, the request became "show it
  // on the map, color-coded, Windy-style animation, route vicinity only".
  // See wave_field.dart's top-of-file doc comment and
  // MapPainter._drawWaveField for the rest of the design.

  // Toggles the overlay on/off (AppBar button in build(), kPersonalBuild
  // only). Turning on starts the flow-streak animation timer and triggers a
  // fetch if there's no grid yet (or the last fetch failed); turning off
  // just stops the timer and hides the overlay — whatever grid was already
  // fetched is kept, so switching back on doesn't necessarily re-fetch. This
  // is a trial UI ("見た目を確認したい"), not a live-updating forecast
  // display, so slightly-stale cached data on toggle-back-on is an
  // acceptable tradeoff for not re-hitting the API every time.
  void _setWaveFieldEnabled(bool enabled) {
    setState(() => _waveFieldEnabled = enabled);
    if (enabled) {
      _waveAnimTimer ??= Timer.periodic(const Duration(milliseconds: 100), (_) {
        if (!mounted) return;
        setState(() => _waveAnimSeconds += 0.1);
      });
      if (_waveFieldGrid == null && !_waveFieldLoading) {
        _fetchWaveFieldGrid();
      }
    } else {
      _waveAnimTimer?.cancel();
      _waveAnimTimer = null;
    }
  }

  // Computes the sample grid's bounding box — the active route(s)' own
  // bounding box padded by _waveFieldRoutePaddingDeg ("route vicinity",
  // 2026-07-29 decision), or a small fixed box around MapBounds' default
  // center if no route is registered yet — then fetches wave data for it
  // via Open-Meteo's batched multi-location endpoint.
  static const double _waveFieldRoutePaddingDeg = 1.0;
  static const double _waveFieldDefaultHalfBoxDeg = 3.0;

  Future<void> _fetchWaveFieldGrid() async {
    setState(() => _waveFieldLoading = true);

    final tracks = _activeShipTracks;
    double minLat, maxLat, minLon, maxLon;
    if (tracks.isNotEmpty) {
      final allPoints = [for (final t in tracks) ...t.track];
      minLat = allPoints.map((p) => p.latitude).reduce(math.min) - _waveFieldRoutePaddingDeg;
      maxLat = allPoints.map((p) => p.latitude).reduce(math.max) + _waveFieldRoutePaddingDeg;
      minLon = allPoints.map((p) => p.longitude).reduce(math.min) - _waveFieldRoutePaddingDeg;
      maxLon = allPoints.map((p) => p.longitude).reduce(math.max) + _waveFieldRoutePaddingDeg;
    } else {
      minLat = MapBounds.defaultCenterLat - _waveFieldDefaultHalfBoxDeg;
      maxLat = MapBounds.defaultCenterLat + _waveFieldDefaultHalfBoxDeg;
      minLon = MapBounds.defaultCenterLon - _waveFieldDefaultHalfBoxDeg;
      maxLon = MapBounds.defaultCenterLon + _waveFieldDefaultHalfBoxDeg;
    }
    // Clamp to the app's own fixed display range (MapBounds) so a route
    // near the edge of that range doesn't request points from far outside
    // anywhere this map ever draws.
    minLat = minLat.clamp(MapBounds.minLat, MapBounds.maxLat);
    maxLat = maxLat.clamp(MapBounds.minLat, MapBounds.maxLat);
    minLon = minLon.clamp(MapBounds.minLon, MapBounds.maxLon);
    maxLon = maxLon.clamp(MapBounds.minLon, MapBounds.maxLon);

    final gridPoints = buildWaveFieldGridPoints(
      minLat: minLat,
      maxLat: maxLat,
      minLon: minLon,
      maxLon: maxLon,
    );

    // Open-Meteo's hourly series starts at *today 00:00 real/device time*
    // and runs `forecastDays` out from there (API docs) — it is NOT
    // anchored to _startTime, which can itself already be hours into that
    // window (e.g. a typhoon issued yesterday) and which playback then
    // advances up to _maxOffsetHours further. The fetch previously used the
    // function's 2-day default regardless of how long the loaded voyage
    // actually plays for; once a longer playback ran past that ~48h fetched
    // window, every later point clamped to the last fetched hour's value
    // (see interpolateHourlyValue's "not before/after the series" clamping
    // in wave_field.dart) — the color would then stop changing for the rest
    // of playback (2026-07-29 user report: "色が再生から最後まで変わって
    // いかない"). Fixed by sizing the request to the playback's own actual
    // end time (real elapsed days from now, not from _startTime), +1 day
    // safety margin, clamped to the API's documented maximum of 8.
    final playbackEnd = _startTime.add(Duration(minutes: (_maxOffsetHours * 60).round()));
    final daysFromNowToPlaybackEnd = playbackEnd.difference(DateTime.now()).inHours / 24.0;
    // math.max/min (not num.clamp, which returns `num` rather than `int` —
    // a past pitfall already hit elsewhere in this codebase, see
    // docs/completed-log.md's map-screen 2026-07-26 entries) keeps this an
    // actual `int`, matching fetchOpenMeteoMarineGrid's `int forecastDays`.
    final forecastDays = math.max(1, math.min(8, daysFromNowToPlaybackEnd.ceil() + 1));

    try {
      final results = await fetchOpenMeteoMarineGrid(points: gridPoints, forecastDays: forecastDays);
      if (!mounted) return;
      setState(() {
        _waveFieldGrid = [
          for (final r in results) WaveFieldPoint(lat: r.latitude, lon: r.longitude, hourly: r.points),
        ];
        _waveFieldLoading = false;
      });
    } catch (e) {
      // Broad catch-all deliberately kept (same reasoning as the Open-Meteo
      // debug dialog above): this batched multi-location request path is
      // even less exercised than the single-point one, so an unexpected
      // response shape is a real possibility, not just theoretical.
      if (!mounted) return;
      setState(() => _waveFieldLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Wave field fetch failed: $e')),
      );
    }
  }

  // Resolves the fetched grid (a whole hourly series per point) down to "one
  // value per point at the current playback time" for MapPainter — see
  // wave_field.dart's interpolateHourlyValue. Recomputed on every build
  // (cheap: linear scan of a small, capped-size grid) since it depends on
  // _currentTime, which changes continuously during playback; the expensive
  // part (the network fetch) stays cached in _waveFieldGrid and is not
  // touched here.
  List<WaveFieldSample> get _currentWaveFieldSamples {
    final grid = _waveFieldGrid;
    if (!_waveFieldEnabled || grid == null) return const [];
    final time = _currentTime;
    return [
      for (final p in grid)
        WaveFieldSample(
          lat: p.lat,
          lon: p.lon,
          heightM: interpolateHourlyValue(p.hourly, time, (h) => h.waveHeightM),
          directionDeg: interpolateHourlyValue(p.hourly, time, (h) => h.waveDirectionDeg, wrapsAt360: true),
        ),
    ];
  }

  // Passage Plan: import/register/edit/delete up to _maxVoyagePlans CSVs
  // (2026-08-xx request, extending the 2026-07-30 single-plan version).
  // "Import CSV" parses a JRC ECDIS route CSV, opens VoyagePlanScreen to
  // collect its departure date/time (and let the user tweak waypoints/leg
  // speeds), then registers it as a new entry. "Edit" reopens that same
  // screen seeded from an existing entry and updates it in place. Both
  // still go through VoyagePlanScreen/VoyagePlanResult unchanged — only how
  // the result is stored (a list of entries instead of one plan) changed.

  String _fileNameWithoutExtension(String path) {
    final base = path.split(RegExp(r'[\\/]')).last;
    final dot = base.lastIndexOf('.');
    return dot > 0 ? base.substring(0, dot) : base;
  }

  Future<void> _importVoyagePlanCsv() async {
    if (_voyagePlans.length >= _maxVoyagePlans) return; // button is disabled at this point anyway

    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv'],
      dialogTitle: 'Select passage plan CSV',
    );
    final path = picked?.files.single.path;
    if (path == null || !mounted) return; // user cancelled, or web (no path)

    String csvText;
    try {
      csvText = await File(path).readAsString();
    } catch (e) {
      if (mounted) _showVoyagePlanError('CSVファイルを読み込めませんでした: $e');
      return;
    }

    List<ShipWaypoint> waypoints;
    try {
      waypoints = parseVoyagePlanCsv(csvText);
    } on VoyagePlanParseException catch (e) {
      if (mounted) _showVoyagePlanError(e.message);
      return;
    }

    // Accumulate into the CSV library (2026-07-27 request: "同じファイルを
    // 毎回外部から選び直すのではなく、取り込んだCSVを蓄積して後から選べる
    // ようにしたい") before opening the departure-time screen, so a later
    // "Select CSV" can reuse this exact file without going back to the OS
    // file picker. Done only after the parse above succeeds, so a malformed
    // CSV never clobbers a good library entry.
    final libraryFileName = path.split(RegExp(r'[\\/]')).last;
    final alreadyInLibrary = await CsvLibrary.exists(libraryFileName);
    if (!mounted) return;
    if (alreadyInLibrary) {
      // "上書き保存（確認テロップ出ると良いY/N）" — declining cancels the
      // whole import (nothing is registered either), so there's no
      // half-applied state to reason about; the user can rename the source
      // file and re-import if they want to keep both.
      final overwrite = await _confirmCsvOverwrite(libraryFileName);
      if (!mounted || !overwrite) return;
    } else if (await CsvLibrary.count() >= CsvLibrary.maxEntries) {
      _showVoyagePlanError(
          'CSVライブラリの上限（${CsvLibrary.maxEntries}件）に達しています。'
          '「Edit CSV」から不要なファイルを削除してください。');
      return;
    }
    await CsvLibrary.importFrom(path);
    if (!mounted) return;

    final result = await Navigator.push<VoyagePlanResult>(
      context,
      MaterialPageRoute(
        builder: (_) => VoyagePlanScreen(
          initialWaypoints: waypoints,
          initialDepartureTime: _startTime,
        ),
      ),
    );
    if (result == null || !mounted) return;
    setState(() {
      _voyagePlans.add(VoyagePlanEntry(
        name: _fileNameWithoutExtension(path),
        waypoints: result.waypoints,
        departureTime: result.departureTime,
        // New plans default to Display-on (2026-08-xx: user's own
        // suggestion for resolving "which plan feeds the ship" — importing
        // a plan is itself the signal that it should count).
        displayEnabled: true,
        sourceCsvFileName: libraryFileName,
      ));
    });
    _saveState();
  }

  // Y/N confirmation before overwriting an existing same-named CSV library
  // entry (2026-07-27 request). Returns true only on an explicit "Yes".
  Future<bool> _confirmCsvOverwrite(String fileName) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Overwrite in CSV library?'),
        content: Text(
          '"${_fileNameWithoutExtension(fileName)}" は既にCSVライブラリに存在します。'
          '上書きしますか？',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('No'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Yes'),
          ),
        ],
      ),
    );
    return confirmed == true;
  }

  // "Select CSV" (2026-07-27 request): register a new Passage Plan from a
  // CSV already sitting in the library, instead of going back through the
  // OS file picker for a file that was imported before. Mirrors
  // _importVoyagePlanCsv's parse → VoyagePlanScreen → register flow, minus
  // the library-accumulation step (the file's already there).
  Future<void> _selectCsvFromLibrary(String fileName) async {
    if (_voyagePlans.length >= _maxVoyagePlans) {
      _showVoyagePlanError('登録できるPassage Planの上限（$_maxVoyagePlans件）に達しています。');
      return;
    }
    String csvText;
    try {
      csvText = await CsvLibrary.readText(fileName);
    } catch (e) {
      if (mounted) _showVoyagePlanError('CSVファイルを読み込めませんでした: $e');
      return;
    }
    List<ShipWaypoint> waypoints;
    try {
      waypoints = parseVoyagePlanCsv(csvText);
    } on VoyagePlanParseException catch (e) {
      if (mounted) _showVoyagePlanError(e.message);
      return;
    }
    if (!mounted) return;
    final result = await Navigator.push<VoyagePlanResult>(
      context,
      MaterialPageRoute(
        builder: (_) => VoyagePlanScreen(
          initialWaypoints: waypoints,
          initialDepartureTime: _startTime,
        ),
      ),
    );
    if (result == null || !mounted) return;
    setState(() {
      _voyagePlans.add(VoyagePlanEntry(
        name: _fileNameWithoutExtension(fileName),
        waypoints: result.waypoints,
        departureTime: result.departureTime,
        displayEnabled: true,
        sourceCsvFileName: fileName,
      ));
    });
    _saveState();
  }

  // "Select CSV" dialog (2026-07-27 request): a plain list of the CSV
  // library's contents. No per-row actions here (Rename/Delete live in
  // "Edit CSV" instead, _showCsvLibraryDialog below), so this doesn't need
  // its own StatefulBuilder — the list itself never changes while open.
  //
  // Bug fix (2026-07-27, reported same day: "Saveを押してもすぐに反映されず、
  // 一度Passage Planを閉じてから開くと表示される"): tapping a row used to
  // pop this dialog and call `_selectCsvFromLibrary(name)` *without*
  // awaiting it (the onTap callback wasn't `async`), so this method's
  // `await showDialog(...)` resolved as soon as the list dialog closed —
  // well before _selectCsvFromLibrary's own VoyagePlanScreen push/Save/
  // setState finished. That made `_showPassagePlanDialog`'s
  // `runAndRefresh(_showSelectCsvDialog)` call `setDialogState` too early,
  // so the newly-registered plan didn't show up until something else
  // (closing/reopening Passage Plan, or any other action there) triggered
  // another rebuild. Fixed by having the list dialog return the tapped
  // filename via `Navigator.pop(dialogContext, name)` and awaiting
  // _selectCsvFromLibrary *after* that dialog has actually closed, so this
  // whole method's Future doesn't complete until registration is done.
  Future<void> _showSelectCsvDialog() async {
    final names = await CsvLibrary.listFileNames();
    if (!mounted) return;
    final selected = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Select CSV'),
        content: SizedBox(
          width: 400,
          height: 380,
          child: names.isEmpty
              ? Center(
                  child: Text(
                    'CSV library is empty. Import a CSV first.',
                    style: TextStyle(color: Colors.grey.shade600),
                  ),
                )
              : ListView.separated(
                  itemCount: names.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final name = names[index];
                    return ListTile(
                      dense: true,
                      title: Text(_fileNameWithoutExtension(name), overflow: TextOverflow.ellipsis),
                      onTap: () => Navigator.pop(dialogContext, name),
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
    if (selected == null || !mounted) return;
    await _selectCsvFromLibrary(selected);
  }

  // Renames a CSV library entry (2026-07-27 request, new functionality —
  // Passage Plan entries themselves still have no rename UI, see TASKS.md).
  // Validates: non-empty, no path separators (would otherwise escape the
  // library folder via File.rename), and no collision with another
  // existing library entry — shown inline as an error rather than a
  // separate dialog, same pattern as _showLabelSettingsDialog's
  // parseErrors.
  Future<void> _renameCsvLibraryEntry(String oldFileName) async {
    final controller = TextEditingController(text: _fileNameWithoutExtension(oldFileName));
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        String? error;
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            return AlertDialog(
              title: const Text('Rename CSV'),
              content: TextField(
                controller: controller,
                autofocus: true,
                decoration: InputDecoration(
                  border: const OutlineInputBorder(),
                  isDense: true,
                  errorText: error,
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () async {
                    final trimmed = controller.text.trim();
                    if (trimmed.isEmpty || trimmed.contains('/') || trimmed.contains('\\')) {
                      setDialogState(() => error = '有効なファイル名を入力してください（/ \\ は使用不可）');
                      return;
                    }
                    final newFileName = '$trimmed.csv';
                    if (newFileName.toLowerCase() != oldFileName.toLowerCase() &&
                        await CsvLibrary.exists(newFileName)) {
                      setDialogState(() => error = '同名のファイルが既にライブラリに存在します');
                      return;
                    }
                    await CsvLibrary.rename(oldFileName, newFileName);
                    // State-level `mounted` (not a BuildContext extension),
                    // same convention as every other async gap in this file
                    // (see _editVoyagePlanEntry etc.) — avoids relying on
                    // the newer BuildContext.mounted extension.
                    if (mounted) Navigator.pop(dialogContext);
                  },
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );
    controller.dispose();
  }

  // Permanently removes a CSV from the library (2026-07-27 request: "不要に
  // なったファイルをライブラリからも完全削除する").
  //
  // Cascade-delete behavior (2026-07-27, revised same day after the user
  // tried the first version and found it confusing — "Editで削除しても
  // Passage Planには残っている"): deleting a library file that a currently
  // -registered Passage Plan was sourced from (see
  // VoyagePlanEntry.sourceCsvFileName) now also removes that plan —
  // ① if there's at least one such plan, confirm first ("このプランは選択
  // されていますが削除して良いですか？", in English per the request) since
  // this is more destructive than deleting an unused library file; ② if
  // there's none, delete immediately with no prompt, same as before. Plans
  // registered before sourceCsvFileName existed (null) are never matched,
  // so deleting their source file's *current* library entry never touches
  // them — same for a plan whose source file was later renamed in the
  // library (see that field's doc comment).
  Future<void> _deleteCsvLibraryEntry(String fileName) async {
    final linkedPlans = [
      for (var i = 0; i < _voyagePlans.length; i++)
        if (_voyagePlans[i].sourceCsvFileName == fileName) i,
    ];

    if (linkedPlans.isNotEmpty) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Delete CSV?'),
          content: const Text(
            'This CSV is currently registered as a Passage Plan. '
            'Delete it anyway?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('No'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Yes'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
      await CsvLibrary.delete(fileName);
      if (!mounted) return;
      setState(() {
        for (final i in linkedPlans.reversed) {
          _voyagePlans.removeAt(i);
        }
      });
      _saveState();
    } else {
      await CsvLibrary.delete(fileName);
    }
  }

  // "Edit CSV" dialog (2026-07-27 request): the CSV library's contents with
  // Rename/Delete per entry, plus a "position/limit" readout (e.g. "3/50")
  // next to the icons for each row — the user's own suggestion in place of
  // showing the count on the Passage Plan dialog's buttons (unlike Import
  // CSV's "(n/10)" label, which counts *registered* plans, a different cap).
  Future<void> _showCsvLibraryDialog() async {
    var names = await CsvLibrary.listFileNames();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            Future<void> refresh() async {
              final updated = await CsvLibrary.listFileNames();
              setDialogState(() => names = updated);
            }

            return AlertDialog(
              title: const Text('Edit CSV'),
              content: SizedBox(
                width: 460,
                height: 420,
                child: names.isEmpty
                    ? Center(
                        child: Text(
                          'CSV library is empty.',
                          style: TextStyle(color: Colors.grey.shade600),
                        ),
                      )
                    : ListView.separated(
                        itemCount: names.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final name = names[index];
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    _fileNameWithoutExtension(name),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                Text(
                                  '${index + 1}/${CsvLibrary.maxEntries}',
                                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                                ),
                                const SizedBox(width: 4),
                                IconButton(
                                  tooltip: 'Rename',
                                  icon: const Icon(Icons.drive_file_rename_outline, size: 20),
                                  onPressed: () async {
                                    await _renameCsvLibraryEntry(name);
                                    await refresh();
                                  },
                                ),
                                IconButton(
                                  tooltip: 'Delete',
                                  icon: const Icon(Icons.delete_outline, size: 20),
                                  onPressed: () async {
                                    await _deleteCsvLibraryEntry(name);
                                    await refresh();
                                  },
                                ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Close'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _editVoyagePlanEntry(int index) async {
    final entry = _voyagePlans[index];
    final result = await Navigator.push<VoyagePlanResult>(
      context,
      MaterialPageRoute(
        builder: (_) => VoyagePlanScreen(
          initialWaypoints: entry.waypoints,
          initialDepartureTime: entry.departureTime,
        ),
      ),
    );
    if (result == null || !mounted) return;
    setState(() {
      entry.waypoints = result.waypoints;
      entry.departureTime = result.departureTime;
    });
    _saveState();
  }

  Future<void> _deleteVoyagePlanEntry(int index) async {
    final entry = _voyagePlans[index];
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete passage plan'),
        content: Text('"${entry.name}" を削除しますか？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _voyagePlans.removeAt(index));
    _saveState();
  }

  void _showVoyagePlanError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red.shade700),
    );
  }

  // Passage Plan dialog (2026-08-xx request, extended 2026-07-27 with the
  // CSV library — see CsvLibrary): a single dialog — not a PopupMenuButton —
  // with three buttons up top ("Import CSV..."/"Select CSV..."/"Edit
  // CSV...", the first two disabled once _maxVoyagePlans registered plans
  // is reached) and, below them, one row per registered plan: a Display
  // checkbox (multiple can be on at once, each drawn as its own independent
  // route — see _activeShipTracks), its name, and Edit/Delete icon buttons.
  // Each action applies immediately (setState on the screen) rather than
  // batching behind a Save button, since there's no single combined "form"
  // to validate — Edit/Delete/Import/Select each already have their own
  // confirmation/validation step.
  Future<void> _showPassagePlanDialog() async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            Future<void> runAndRefresh(Future<void> Function() action) async {
              await action();
              setDialogState(() {});
            }

            final atLimit = _voyagePlans.length >= _maxVoyagePlans;
            return AlertDialog(
              title: const Text('Passage Plan'),
              content: SizedBox(
                width: 460,
                height: 420,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Three-tier CSV entry (2026-07-27 request): "Import
                    // CSV..." (OS file picker, also accumulates into the CSV
                    // library), "Select CSV..." (register from a file
                    // already in the library), "Edit CSV..." (Rename/Delete
                    // library entries — doesn't register anything itself, so
                    // it doesn't need runAndRefresh/atLimit).
                    OutlinedButton.icon(
                      icon: const Icon(Icons.upload_file),
                      // No count on the button itself (2026-07-27 request:
                      // move it next to each row instead, matching Edit
                      // CSV's per-row "n/50" — see the "n/$_maxVoyagePlans"
                      // Text below, next to each row's Edit/Delete icons).
                      label: const Text('Import CSV...'),
                      onPressed: atLimit ? null : () => runAndRefresh(_importVoyagePlanCsv),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.folder_open),
                      label: const Text('Select CSV...'),
                      onPressed: atLimit ? null : () => runAndRefresh(_showSelectCsvDialog),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.library_books),
                      label: const Text('Edit CSV...'),
                      // Wrapped in runAndRefresh too (2026-07-27): a cascade
                      // -delete inside Edit CSV can now remove registered
                      // plan(s) from _voyagePlans (see
                      // _deleteCsvLibraryEntry), which this Passage Plan
                      // dialog's own list needs to reflect once Edit CSV
                      // closes.
                      onPressed: () => runAndRefresh(_showCsvLibraryDialog),
                    ),
                    const SizedBox(height: 8),
                    const Divider(height: 1),
                    Expanded(
                      child: _voyagePlans.isEmpty
                          ? Center(
                              child: Text(
                                'No passage plans imported yet.',
                                style: TextStyle(color: Colors.grey.shade600),
                              ),
                            )
                          : ListView.separated(
                              itemCount: _voyagePlans.length,
                              separatorBuilder: (_, __) => const Divider(height: 1),
                              itemBuilder: (context, index) {
                                final entry = _voyagePlans[index];
                                return Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 2),
                                  child: Row(
                                    children: [
                                      Checkbox(
                                        value: entry.displayEnabled,
                                        onChanged: (v) => setDialogState(() {
                                          setState(() => entry.displayEnabled = v ?? true);
                                          _saveState();
                                        }),
                                      ),
                                      Expanded(
                                        child: Text(
                                          entry.name.isEmpty ? 'Plan ${index + 1}' : entry.name,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      // Position/limit readout (2026-07-27
                                      // request: move the "(n/10)" count off
                                      // the Import CSV button and onto each
                                      // row instead, same as Edit CSV's
                                      // per-row "n/50").
                                      Text(
                                        '${index + 1}/$_maxVoyagePlans',
                                        style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                                      ),
                                      const SizedBox(width: 4),
                                      IconButton(
                                        tooltip: 'Edit',
                                        icon: const Icon(Icons.edit, size: 20),
                                        onPressed: () => runAndRefresh(() => _editVoyagePlanEntry(index)),
                                      ),
                                      IconButton(
                                        tooltip: 'Delete',
                                        icon: const Icon(Icons.delete_outline, size: 20),
                                        onPressed: () => runAndRefresh(() => _deleteVoyagePlanEntry(index)),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Close'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // Source-prefixed labels (2026-07-28), e.g. "JTWC12W (NOUL)"/"JMA13TS
  // (DOLPHIN)" — shared by both the map markers (_typhoonMarkers) and the
  // Range Ring popup menu (below) so the two never drift out of sync.
  // [fallback] lets the menu show a placeholder when nothing's parsed yet
  // for that source, while the map markers (which only build a marker at
  // all once there's track data — see _typhoonMarkers) just pass null.
  String? _jtwcMarkerLabel(_TyphoonSlot slot, {String? fallback}) =>
      slot.jtwcInfo.designation == null ? fallback : 'JTWC${slot.jtwcInfo.designation}';

  String? _jmaMarkerLabel(_TyphoonSlot slot, {String? fallback}) =>
      slot.jmaInfo.designation == null ? fallback : 'JMA${slot.jmaInfo.designation}';

  // Toggles a typhoon's 100nm/200nm rings when its red icon is tapped on the
  // map (2026-08-14 request: "台風アイコン赤丸をクリックで切り替え"). Called
  // from the GestureDetector wrapped around the map's CustomPaint in
  // build() — [scenePosition] is already in canvas/scene coordinates (the
  // same units as MapBounds.toOffset), since Flutter's hit-testing resolves
  // ancestor transforms (InteractiveViewer's pan/zoom) before delivering the
  // tap to this widget's local coordinate space. The hit radius is
  // converted from an on-screen pixel size to scene units via 1/_zoom so
  // the tappable area stays a consistent size regardless of zoom, matching
  // how the icon itself is drawn at a fixed on-screen size.
  void _handleMapTap(Offset scenePosition) {
    final hitRadiusScene = 14 / _zoom;
    for (var i = 0; i < _typhoonSlots.length; i++) {
      final slot = _typhoonSlots[i];
      // Checks both sources independently (2026-07-28: rings are now
      // per-source, not shared per slot — see _TyphoonSlot.jtwcRingsEnabled/
      // jmaRingsEnabled), toggling only the tapped icon's own source.
      final candidates = [
        if (slot.jtwcDisplayEnabled)
          (points: _jtwcTrackPointsForSlot(i), toggle: () => slot.jtwcRingsEnabled = !slot.jtwcRingsEnabled),
        if (slot.jmaDisplayEnabled)
          (points: _jmaTrackPointsForSlot(i), toggle: () => slot.jmaRingsEnabled = !slot.jmaRingsEnabled),
      ];
      for (final candidate in candidates) {
        final points = candidate.points;
        if (points == null || points.isEmpty) continue;
        final pos = positionAt(points, _currentTime);
        final offset = MapBounds.toOffset(pos.latitude, pos.longitude);
        if ((offset - scenePosition).distance <= hitRadiusScene) {
          setState(candidate.toggle);
          _saveState();
          return;
        }
      }
    }
  }

  // The next waypoint ahead of [time] in [track], or null once there's none
  // left (voyage complete) — used to point that ship's icon apex toward it
  // (2026-07-27 request). Takes an explicit track (rather than reading a
  // single shared field) since 2026-08-xx: multiple independent routes can
  // be on screen at once, each needing its own "next waypoint".
  TrackPoint? _nextWaypointAfterIn(List<TrackPoint> track, DateTime time) {
    for (final p in track) {
      if (p.time.isAfter(time)) return p;
    }
    return null;
  }

  // Palette for distinguishing multiple simultaneously-displayed routes
  // (2026-08-xx request: comparing route options departing the same port/
  // time all drew in the same blue, making the icons/labels hard to tell
  // apart right after departure). Assigned by position in _activeShipTracks
  // (cycling if there were ever more entries than colors — not expected,
  // since Passage Plan caps registered plans at 10). Index 0 (blue) matches
  // the single-ship color used before this feature existed, so the common
  // "just one plan" case looks unchanged.
  static const List<Color> _shipColors = [
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

  // Builds the actual [ShipMarker]s to draw: one per currently-active track
  // (see _activeShipTracks), each with its own interpolated position,
  // past/future split, next-waypoint heading, route color, and — one group
  // per currently-displayed typhoon *slot* (2026-07-29: previously a flat
  // per-typhoon-marker list that trailed further and further behind the
  // ship; now grouped by slot — see [_typhoonMarkerGroups] — so JTWC/JMA of
  // the *same* typhoon draw as a vertically-stacked pair at one shared
  // distance behind the ship instead of two separate stops, while Typhoon
  // 1/2/3 each still get their own, progressively-further-back position —
  // see ShipMarker.typhoonDistances/map_painter.dart's grouped stacking).
  //
  // [tracks] is passed in (rather than re-reading _activeShipTracks here)
  // so the caller (build()) can compute it once and share it with the
  // Passage Plan legend overlay, which needs the same plan-name/color
  // pairing to stay in sync with what's actually drawn on the map.
  //
  // 2026-08-xx: `label` is now the user-entered Ship's Name (_shipName),
  // the same on every marker (one physical ship, multiple route options) —
  // the plan's own name (`entry.label`) moved to the legend overlay instead
  // of being drawn next to the ship on the map, see ShipMarker's doc comment.
  List<ShipMarker> _buildShipMarkers(
    List<List<TyphoonMarker>> typhoonGroups,
    List<({List<TrackPoint> track, String label})> tracks,
  ) {
    final markers = <ShipMarker>[];
    for (var i = 0; i < tracks.length; i++) {
      final entry = tracks[i];
      final track = entry.track;
      final split = splitTrackAtTime(track, _currentTime);
      final position = positionAt(track, _currentTime);
      final next = _nextWaypointAfterIn(track, _currentTime);
      markers.add(ShipMarker(
        position: position,
        route: track.map((p) => LatLng(p.latitude, p.longitude)).toList(),
        pastRoute: split.past,
        futureRoute: split.future,
        nextWaypoint: next == null ? null : LatLng(next.latitude, next.longitude),
        label: _shipName,
        typhoonDistances: [
          for (final group in typhoonGroups)
            [
              for (final typhoon in group)
                ShipTyphoonDistance(
                  distanceNm: distanceNm(position, typhoon.currentPosition),
                  color: typhoon.color,
                ),
            ],
        ],
        color: _shipColors[i % _shipColors.length],
      ));
    }
    return markers;
  }

  // Passage Plan legend overlay (2026-08-xx request: the plan-name label that
  // used to sit next to each ship on the map is "not needed" there anymore —
  // instead, show one legend box, fixed to the top-left of the *screen* (not
  // the zoomable map canvas — it's a plain widget in the Stack, outside
  // InteractiveViewer, so it's already a constant on-screen size regardless
  // of zoom without any extra work), listing every currently Display-on
  // plan's name in its route's own color next to a matching color swatch.
  // The box's height grows automatically (Column with MainAxisSize.min) as
  // more plans are added. Colored to match [_shipColors] by position in
  // [tracks] — the same list/order/index _buildShipMarkers uses for its own
  // color assignment, so a legend row always matches the route it labels.
  // Null (nothing to show) when there are no Display-on plans, same as the
  // rest of this screen's "don't show empty chrome" pattern.
  Widget? _buildPassagePlanLegend(List<({List<TrackPoint> track, String label})> tracks) {
    if (tracks.isEmpty) return null;
    return Positioned(
      // 2026-07-29 adjustment: nudged right/down from the initial (12, 12)
      // — at (12, 12) this box could overlap the lon/lat grid-line labels
      // (_buildGridLabelOverlay), which sit right at the top edge (top:
      // margin=4) and can appear anywhere along the left edge too (lat
      // labels are pinned to left:margin=4 at whatever screen Y their grid
      // line falls at, so a label can land anywhere vertically, not just
      // near the top). 40/48 clears both: below the top-edge lon label row,
      // and past the widest lat label chip's width.
      left: 48,
      top: 40,
      child: IgnorePointer(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 240),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: const Color(0xFF0D2436), width: 2),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Passage Plan',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              for (var i = 0; i < tracks.length; i++) ...[
                if (i > 0) const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        tracks[i].label,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: _shipColors[i % _shipColors.length],
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Container(width: 36, height: 3, color: _shipColors[i % _shipColors.length]),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final typhoonGroups = _typhoonMarkerGroups;
    final typhoons = [for (final group in typhoonGroups) ...group];
    final activeTracks = _activeShipTracks;
    final ships = _buildShipMarkers(typhoonGroups, activeTracks);
    final passagePlanLegend = _buildPassagePlanLegend(activeTracks);
    // Whole playback bar (not just the timeline track inside it) is hidden
    // when there's nothing to scrub through — i.e. no Passage Plan and no
    // typhoon info registered (2026-07-27 request: since the sample ship/
    // typhoon fallbacks were removed, _maxOffsetHours legitimately reaches 0
    // in that case, and there's no useful reason to show play/speed
    // controls with nothing to play).
    final hasTimeline = _maxOffsetHours > 0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Typhoon & ship tracker'),
        actions: [
          IconButton(
            icon: const Icon(Icons.directions_boat),
            tooltip: 'Passage Plan',
            onPressed: _showPassagePlanDialog,
          ),
          // Range Ring menu (2026-07-28 redesign): one entry per currently-
          // displayed *source* (JTWC/JMA), not per slot — since rings are now
          // independently toggleable per source (see
          // _TyphoonSlot.jtwcRingsEnabled/jmaRingsEnabled), a slot showing
          // both at once needs two separate menu rows. PopupMenuButton<int>
          // only carries a single int per item, so the slot index and source
          // are packed into one value (`i * 2` = JTWC, `i * 2 + 1` = JMA) and
          // unpacked in onSelected — simpler than introducing a custom
          // record/enum type just for this one menu's selection value.
          PopupMenuButton<int>(
            icon: const Icon(Icons.track_changes),
            tooltip: 'Range Ring',
            onSelected: (encoded) {
              final slotIndex = encoded ~/ 2;
              final isJma = encoded.isOdd;
              final slot = _typhoonSlots[slotIndex];
              setState(() {
                if (isJma) {
                  slot.jmaRingsEnabled = !slot.jmaRingsEnabled;
                } else {
                  slot.jtwcRingsEnabled = !slot.jtwcRingsEnabled;
                }
              });
              _saveState();
            },
            itemBuilder: (context) {
              final entries = <PopupMenuEntry<int>>[];
              for (var i = 0; i < _typhoonSlots.length; i++) {
                final slot = _typhoonSlots[i];
                if (slot.jtwcDisplayEnabled && _jtwcTrackPointsForSlot(i) != null) {
                  entries.add(CheckedPopupMenuItem<int>(
                    value: i * 2,
                    checked: slot.jtwcRingsEnabled,
                    child: Text(_jtwcMarkerLabel(slot, fallback: 'JTWC Typhoon ${i + 1}')!),
                  ));
                }
                if (slot.jmaDisplayEnabled && _jmaTrackPointsForSlot(i) != null) {
                  entries.add(CheckedPopupMenuItem<int>(
                    value: i * 2 + 1,
                    checked: slot.jmaRingsEnabled,
                    child: Text(_jmaMarkerLabel(slot, fallback: 'JMA Typhoon ${i + 1}')!),
                  ));
                }
              }
              if (entries.isEmpty) {
                entries.add(const PopupMenuItem<int>(
                  enabled: false,
                  child: Text('No typhoon loaded'),
                ));
              }
              return entries;
            },
          ),
          IconButton(
            icon: const Icon(Icons.edit_note),
            tooltip: 'Information',
            onPressed: _showLabelSettingsDialog,
          ),
          // Temporary verification tool (2026-07-29) — see the doc comment
          // on _showMarineForecastDebugDialog for why this exists and why
          // it's deliberately separate from the Information dialog above.
          IconButton(
            icon: const Icon(Icons.waves),
            tooltip: 'Marine forecast (debug)',
            onPressed: _showMarineForecastDebugDialog,
          ),
          // Personal-build only (2026-07-29) — see build_flags.dart's
          // kPersonalBuild doc comment. This whole button (and everything it
          // calls) is compiled out of a mainline build via dead-code
          // elimination on the `if (kPersonalBuild)` const-false branch, not
          // merely hidden at runtime.
          if (kPersonalBuild)
            IconButton(
              icon: const Icon(Icons.water),
              tooltip: 'Open-Meteo marine (trial)',
              onPressed: _showOpenMeteoDebugDialog,
            ),
          // Map overlay toggle (2026-07-29 follow-up request: "地図上に波高
          // を色分け表示、Windy風のアニメーション、航路周辺のみ") — separate
          // from the text-only debug dialog above, which stays as-is for raw
          // data inspection. Highlighted (tinted) while on, spinner while a
          // fetch is in flight, same "disabled while loading" convention as
          // the debug dialog's own Fetch button.
          if (kPersonalBuild)
            IconButton(
              icon: _waveFieldLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.blur_on),
              color: _waveFieldEnabled ? Colors.blue : null,
              tooltip: 'Wave field overlay (trial)',
              onPressed: _waveFieldLoading ? null : () => _setWaveFieldEnabled(!_waveFieldEnabled),
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                _updateViewportSize(Size(constraints.maxWidth, constraints.maxHeight));
                return Stack(
              children: [
                MouseRegion(
                  onHover: _handleHover,
                  onExit: (_) => setState(() => _cursorLatLon = null),
                  // 2026-07-28 bug fix: this used to wrap InteractiveViewer
                  // in a Listener(onPointerSignal: ...) that duplicated
                  // mouse-wheel zoom handling alongside InteractiveViewer's
                  // own built-in wheel-to-zoom behavior — both independently
                  // computed a scale change and applied it to the same
                  // transformationController on every scroll tick, and their
                  // results diverged as zoom approached the minimum (the
                  // reported "settles into re-centering instead of zooming
                  // out further" symptom). Removed entirely: InteractiveViewer
                  // already zooms toward the cursor and clamps to
                  // minScale/maxScale on its own, which is exactly the
                  // desired behavior, so there's nothing left for a second
                  // handler to add — see _syncFromController's listener
                  // (registered in initState) for how (_zoom, _translation)
                  // stay in sync with whatever InteractiveViewer does.
                  child: InteractiveViewer(
                    transformationController: _transformationController,
                    minScale: _minZoom,
                    maxScale: _maxZoom,
                    constrained: false,
                    child: SizedBox(
                      width: MapBounds.canvasWidth,
                      height: MapBounds.canvasHeight,
                      // Tap-to-toggle rings (2026-08-14 request): opaque so
                      // taps register even over sea/empty canvas area (a
                      // bare CustomPaint with no child doesn't otherwise
                      // report hits there), same pattern already used for
                      // the playback bar's GestureDetector. A plain tap
                      // (no drag) coexists fine with InteractiveViewer's own
                      // pan/pinch gesture recognizers.
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTapUp: (details) => _handleMapTap(details.localPosition),
                        child: CustomPaint(
                          painter: MapPainter(
                            ships: ships,
                            coastlinePolygons: _coastline.polygons,
                            zoom: _zoom,
                            typhoons: typhoons,
                            shipIcon: _shipIcon,
                            typhoonIcon: _typhoonIcon,
                            // Always the empty default in a mainline build —
                            // see _currentWaveFieldSamples' doc comment and
                            // build_flags.dart's kPersonalBuild.
                            waveField: _currentWaveFieldSamples,
                            waveAnimSeconds: _waveAnimSeconds,
                            marineForecastAreas: _marineForecastAreaPolygons,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned.fill(child: _buildGridLabelOverlay()),
                if (passagePlanLegend != null) passagePlanLegend,
                Positioned(
                  right: 12,
                  top: 12,
                  bottom: 12,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      FloatingActionButton.small(
                        heroTag: 'zoom-in',
                        onPressed: () => _zoomBy(1.25),
                        child: const Icon(Icons.add),
                      ),
                      const SizedBox(height: 8),
                      Expanded(
                        child: RotatedBox(
                          quarterTurns: 3,
                          child: Slider(
                            min: _minZoom,
                            max: _maxZoom,
                            value: _zoom,
                            onChanged: _setZoom,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      FloatingActionButton.small(
                        heroTag: 'zoom-out',
                        onPressed: () => _zoomBy(0.8),
                        child: const Icon(Icons.remove),
                      ),
                    ],
                  ),
                ),
                // JST date/time + cursor lat/lon, stacked bottom-right
                // (2026-08-16 request): the date/time readout used to sit
                // top-left, where at some zoom levels it overlapped the
                // lat/lon grid labels (_buildGridLabelOverlay, also anchored
                // to the top edge). Moved here, directly above the cursor
                // lat/lon readout, so both share the same right-side column
                // clear of the grid labels and the zoom controls (right: 64
                // matches the cursor readout's previous position, chosen to
                // clear the zoom button/slider column at right: 12).
                Positioned(
                  right: 64,
                  bottom: 12,
                  child: IgnorePointer(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.85),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            _formatDateTime(_currentTime),
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                          ),
                        ),
                        if (_cursorLatLon != null) ...[
                          const SizedBox(height: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.85),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              _formatCursorLatLon(_cursorLatLon!.lat, _cursorLatLon!.lon),
                              style: const TextStyle(
                                fontSize: 12,
                                fontFeatures: [FontFeature.tabularFigures()],
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
                );
              },
            ),
          ),
          if (hasTimeline) SafeArea(top: false, child: _buildPlaybackBar()),
        ],
      ),
    );
  }

  // Windy-style playback bar (2026-07-25 request): a play button, an
  // "HH:MM" bubble that tracks the current time above the slider, and a
  // bottom row of day segments ("dd mmm") sized proportionally to how many
  // hours of each calendar day fall within the visible range.
  Widget _buildPlaybackBar() {
    return Container(
      color: Colors.blueGrey.shade900,
      height: 88,
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Playback speed button + play/pause, stacked vertically
          // (2026-07-27 request: move the speed control down from the
          // AppBar to sit directly above the play button, without widening
          // this column or the playback bar itself — both icons are shrunk
          // from their previous single-icon sizes to fit the same 52px
          // column within the bar's existing 88px height).
          SizedBox(
            width: 52,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  icon: const Icon(Icons.speed),
                  iconSize: 18,
                  color: Colors.white70,
                  tooltip: "Play Sp'd",
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 36, minHeight: 28),
                  onPressed: _showPlaybackSpeedDialog,
                ),
                IconButton(
                  icon: Icon(
                    _isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled,
                    size: 28,
                    color: Colors.orange.shade700,
                  ),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
                  onPressed: _togglePlay,
                ),
              ],
            ),
          ),
          Expanded(child: _buildTimelineTrack()),
        ],
      ),
    );
  }

  Widget _buildTimelineTrack() {
    final maxHours = _maxOffsetHours;
    if (maxHours <= 0) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final fraction = (_offsetHours / maxHours).clamp(0.0, 1.0);
        final thumbX = fraction * width;

        void handlePointer(Offset localPosition) {
          final f = (localPosition.dx / width).clamp(0.0, 1.0);
          setState(() => _offsetHours = f * maxHours);
        }

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (d) => handlePointer(d.localPosition),
          onHorizontalDragUpdate: (d) => handlePointer(d.localPosition),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // Day segments (bottom row), each spanning a width
              // proportional to the hours of that day within range. Tap a
              // segment to jump the slider to the start of that day.
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: 34,
                child: Row(children: _dayColumns(maxHours)),
              ),
              // Progress track, directly above the day row.
              Positioned(
                left: 6,
                right: 6,
                bottom: 40,
                height: 6,
                child: Stack(
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.blueGrey.shade600,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                    FractionallySizedBox(
                      widthFactor: fraction,
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              // Marker line from the time bubble down through the track and
              // into the day row, pinpointing the exact current time.
              Positioned(
                left: (thumbX - 1).clamp(0.0, math.max(0.0, width - 2)),
                top: 30,
                bottom: 0,
                width: 2,
                child: IgnorePointer(child: Container(color: Colors.red.shade400)),
              ),
              // "HH:MM" bubble above the marker line.
              Positioned(
                left: (thumbX - 24).clamp(0.0, math.max(0.0, width - 48)),
                top: 0,
                child: IgnorePointer(child: _timeBubble()),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _timeBubble() {
    final hh = _currentTime.hour.toString().padLeft(2, '0');
    final mm = _currentTime.minute.toString().padLeft(2, '0');
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.orange.shade700,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            '$hh:$mm',
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
          ),
        ),
        CustomPaint(size: const Size(10, 5), painter: _BubbleTailPainter(Colors.orange.shade700)),
      ],
    );
  }

  List<Widget> _dayColumns(double maxHours) {
    final rangeEnd = _startTime.add(Duration(minutes: (maxHours * 60).round()));
    final columns = <Widget>[];
    var dayStart = DateTime(_startTime.year, _startTime.month, _startTime.day);
    while (dayStart.isBefore(rangeEnd)) {
      final dayEnd = dayStart.add(const Duration(days: 1));
      final segStart = dayStart.isBefore(_startTime) ? _startTime : dayStart;
      final segEnd = dayEnd.isAfter(rangeEnd) ? rangeEnd : dayEnd;
      final minutes = segEnd.difference(segStart).inMinutes;
      if (minutes > 0) {
        final isCurrentDay = !_currentTime.isBefore(dayStart) && _currentTime.isBefore(dayEnd);
        final label = '${dayStart.day.toString().padLeft(2, '0')} ${_months[dayStart.month - 1]}';
        columns.add(Expanded(
          flex: minutes,
          child: GestureDetector(
            onTap: () => setState(() {
              final target = segStart.difference(_startTime).inMinutes / 60.0;
              _offsetHours = target.clamp(0.0, maxHours);
            }),
            child: Container(
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: isCurrentDay ? Colors.blueGrey.shade600 : Colors.blueGrey.shade900,
                border: Border(left: BorderSide(color: Colors.blueGrey.shade700, width: 0.5)),
              ),
              child: Text(
                label,
                style: TextStyle(
                  color: Colors.white.withOpacity(isCurrentDay ? 1.0 : 0.65),
                  fontSize: 12,
                  fontWeight: isCurrentDay ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ),
          ),
        ));
      }
      dayStart = dayEnd;
    }
    return columns;
  }
}

// One of up to 3 typhoon entry slots (2026-07-28 request). Mutable (not a
// TrackPoint/const model) since it's edited in place from
// _showLabelSettingsDialog's Save handler — pastedText is kept around so
// re-opening the dialog shows what was pasted last, separate from `info`
// (the parsed result actually used for drawing/labeling).
class _TyphoonSlot {
  // JTWC (pasted warning text) source.
  String pastedText = '';
  JtwcTyphoonInfo jtwcInfo = JtwcTyphoonInfo.empty;
  bool jtwcDisplayEnabled = true;

  // JMA (fetched VPTW60 bulletin via "Import from JMA") source (2026-07-28
  // addition: "気象庁と米軍の予報を両方表示、それぞれDisplayで単独表示可能
  // に"). Kept as the raw [JmaTyphoonInfo] rather than converted into
  // [JtwcTyphoonInfo] (an earlier version of this feature did that
  // conversion) — [JmaTyphoonInfo.toTrackPoints] carries each forecast
  // point's exact absolute JST time directly, avoiding the lossy "offset
  // hours from the observed time, truncated to a whole hour" representation
  // an Agent review flagged when this was first wired up as a single
  // JTWC-shaped override.
  //
  // 2026-07-29: now persisted as an offline cache (see [jmaRawXml] below) —
  // scope decided with the user: no periodic auto-fetch (data-usage concern
  // on a personal-use plan), the "Import from JMA" button stays manual, but
  // its result should survive an app restart and remain visible even with
  // no connectivity, rather than vanishing every time the app closes.
  JmaTyphoonInfo jmaInfo = JmaTyphoonInfo.empty;
  bool jmaDisplayEnabled = false;

  // The raw bulletin XML text [jmaInfo] was parsed from (2026-07-29
  // addition) — this, not [jmaInfo] itself, is what AppStateStorage
  // persists; _restoreState re-parses it with `parseJmaTyphoonXml` on
  // startup, mirroring the existing "store raw pasted JTWC text, re-parse on
  // load" convention (see AppStateStorage's class doc comment). Null until a
  // fetch has ever succeeded for this slot.
  String? jmaRawXml;

  // Device-local timestamp of the fetch that produced [jmaRawXml]/[jmaInfo]
  // (2026-07-29 addition) — shown next to the JMA status line so the user
  // can tell how old the cached data is (important once it can be looked at
  // offline, days after the fetch). Plain JST wall-clock DateTime, this
  // app's usual convention (see jtwc_parser.dart's issuedAtJst doc comment).
  DateTime? jmaFetchedAtJst;

  // 100nm/200nm distance rings (2026-08-14 request). Toggled from the
  // AppBar's Range Ring menu or by tapping a displayed typhoon icon on the
  // map (see _handleMapTap) — both act directly on these flags via setState,
  // no dialog/Save step needed ("メニューでのワンクリック...で切り替え").
  // Default changed to on (2026-07-27 request: "Range Ring：On" at app
  // launch) — previously defaulted off. Split into one flag per source
  // (2026-07-28 request: "Range Ringは双方表示している際に別々にOn/Offがで
  // きる" — a single shared flag, the original design when only one source
  // could ever be shown per slot, no longer made sense once JTWC/JMA could
  // both be displayed for the same slot at once). jmaRingsEnabled is
  // persisted by AppStateStorage same as jtwcRingsEnabled (2026-07-29: the
  // whole JMA source became persisted then — see jmaRawXml doc comment
  // above).
  bool jtwcRingsEnabled = true;
  bool jmaRingsEnabled = true;
}

// Downward-pointing tail under the playback bar's time bubble.
class _BubbleTailPainter extends CustomPainter {
  const _BubbleTailPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width / 2, size.height)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _BubbleTailPainter oldDelegate) => oldDelegate.color != color;
}
