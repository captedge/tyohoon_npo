import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../models/track_point.dart';
import '../utils/coastline.dart';
import '../utils/interpolation.dart';
import '../utils/jtwc_parser.dart';
import '../utils/map_bounds.dart';
import '../widgets/map_painter.dart';

/// Main screen: map view with zoom controls and a time slider/play button.
///
/// Ship and typhoon tracks are placeholder sample data for now (see
/// TODO(data) below) — real data will come from the CSV/Excel voyage plan
/// and the JMA/JTWC typhoon feeds once those readers are implemented.
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

  // Several legs with varying headings (including a westward one, WP2→WP3
  // below) so the heading-dependent ship icon rotation and "behind the
  // ship" distance label (2026-07-28) can actually be exercised across a
  // course change — a single-leg route can't show that.
  //
  // A getter (not `late final`) so it re-anchors to _startTime if that
  // changes after this is first read (see above) instead of freezing at
  // whatever _startTime was on first access.
  List<TrackPoint> get _shipTrack => [
        TrackPoint(time: _startTime, latitude: 25.0, longitude: 121.0, label: 'Departure'),
        TrackPoint(time: _startTime.add(const Duration(hours: 20)), latitude: 24.0, longitude: 123.5, label: 'Waypoint 1'),
        TrackPoint(time: _startTime.add(const Duration(hours: 45)), latitude: 21.5, longitude: 124.0, label: 'Waypoint 2'),
        TrackPoint(time: _startTime.add(const Duration(hours: 70)), latitude: 19.0, longitude: 122.0, label: 'Waypoint 3'),
        TrackPoint(time: _startTime.add(const Duration(hours: 95)), latitude: 17.5, longitude: 124.5, label: 'Waypoint 4'),
        TrackPoint(time: _startTime.add(const Duration(hours: 120)), latitude: 16.0, longitude: 127.0, label: 'Waypoint 5'),
      ];
  // Derived from slot 0's last track point (sample fallback, or the last
  // parsed forecast point once real JTWC text is pasted for it — see
  // _trackPointsForSlot) instead of a fixed constant, so the timeline
  // always reaches exactly as far as the available data goes (2026-07-25
  // request: "provided data の最後まで表示したい").
  double get _maxOffsetHours {
    final points = _trackPointsForSlot(0);
    if (points == null || points.isEmpty) return 0;
    final hours = points.last.time.difference(_startTime).inMinutes / 60.0;
    return hours > 0 ? hours : 0;
  }

  double _offsetHours = 24;
  bool _isPlaying = false;
  Timer? _playTimer;

  // Playback speed as a multiplier of the original fixed-speed behavior
  // (1.0 = "1 simulated hour per 200ms tick", which is what this screen
  // always did before). 2026-07-28 request: default to 50% (half as fast
  // as before), adjustable from 25% to 150% — see _showPlaybackSpeedDialog.
  double _playbackSpeed = 0.5;
  static const double _minPlaybackSpeed = 0.25;
  static const double _maxPlaybackSpeed = 1.5;

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

  // User-entered ship name (2026-07-28 request: NAVTOR-format voyage-plan
  // CSVs don't carry a ship name field, so it's entered here instead), plus
  // a Display on/off toggle for the ship (also 2026-07-28). See
  // _shipLabel below and _showLabelSettingsDialog for entry.
  String _shipName = '';
  bool _shipDisplayEnabled = true;

  String get _shipLabel => _shipName.trim().isEmpty ? 'Ship' : _shipName.trim();

  // Up to 3 typhoons (2026-07-28 request: "this area can have more than one
  // typhoon active at once"), each entered by pasting a JTWC warning text.
  // Slot 0 falls back to a sample forecast track (_typhoonTrackFallback
  // below) when nothing's been pasted yet, so the app still has something
  // to demo; slots 1-2 only appear once real data is pasted for them. All
  // 3 are otherwise treated the same — see _typhoonMarkers below.
  final List<_TyphoonSlot> _typhoonSlots = List.generate(3, (_) => _TyphoonSlot());

  // Sample forecast for slot 0 when no JTWC text has been pasted for it yet
  // (renamed from _typhoonTrack, 2026-07-28, now that real pasted data can
  // also drive slot 0 — see _trackPointsForSlot). Out to +120h (5 days),
  // matching the JMA VPTW60 feed's forecast horizon (see TASKS.md). A
  // getter for the same _startTime-re-anchoring reason as _shipTrack above.
  List<TrackPoint> get _typhoonTrackFallback => [
        TrackPoint(time: _startTime, latitude: 13.0, longitude: 126.0, label: 'Now'),
        TrackPoint(time: _startTime.add(const Duration(hours: 24)), latitude: 17.0, longitude: 124.0, label: '+24h'),
        TrackPoint(time: _startTime.add(const Duration(hours: 48)), latitude: 22.0, longitude: 123.0, label: '+48h'),
        TrackPoint(time: _startTime.add(const Duration(hours: 72)), latitude: 28.0, longitude: 124.0, label: '+72h'),
        TrackPoint(time: _startTime.add(const Duration(hours: 96)), latitude: 32.0, longitude: 126.0, label: '+96h'),
        TrackPoint(time: _startTime.add(const Duration(hours: 120)), latitude: 35.0, longitude: 129.0, label: '+120h'),
      ];

  // Builds the TrackPoint list a slot's track/current-position/timeline
  // math should use: the sample fallback for slot 0 when it's empty, the
  // parsed JTWC data (current position + forecast points, offset from
  // _startTime — see JtwcForecastPoint) otherwise, or null when there's
  // nothing to plot at all (empty non-primary slot, or a slot whose pasted
  // text had no REPEAT POSIT line to anchor a position on).
  List<TrackPoint>? _trackPointsForSlot(int index) {
    final slot = _typhoonSlots[index];
    if (index == 0 && slot.info.position == null && slot.info.forecastTrack.isEmpty) {
      return _typhoonTrackFallback;
    }
    final position = slot.info.position;
    if (position == null) return null;
    return [
      TrackPoint(time: _startTime, latitude: position.latitude, longitude: position.longitude),
      for (final point in slot.info.forecastTrack)
        TrackPoint(
          time: _startTime.add(Duration(hours: point.hoursFromNow)),
          latitude: point.position.latitude,
          longitude: point.position.longitude,
        ),
    ];
  }

  // Builds the actual [TyphoonMarker]s to draw: one per Display-enabled
  // slot that has track data (see _trackPointsForSlot). The slider-time
  // interpolation and "whole track drawn persistently" behavior mirror the
  // ship's (positionAt / full-route rendering) — 2026-07-28 request: "台風
  // の軌跡：船のように残してください".
  List<TyphoonMarker> get _typhoonMarkers {
    final markers = <TyphoonMarker>[];
    for (var i = 0; i < _typhoonSlots.length; i++) {
      final slot = _typhoonSlots[i];
      if (!slot.displayEnabled) continue;
      final points = _trackPointsForSlot(i);
      if (points == null || points.isEmpty) continue;
      markers.add(TyphoonMarker(
        track: points.map((p) => LatLng(p.latitude, p.longitude)).toList(),
        currentPosition: positionAt(points, _currentTime),
        label: slot.info.designation ?? 'Typhoon',
        pressureLabel: slot.info.centralPressureHpa == null ? null : '${slot.info.centralPressureHpa}hPa',
      ));
    }
    return markers;
  }

  // Lat/lon under the mouse cursor, shown bottom-right (2026-07-27 request).
  // Null when the cursor isn't over the map (or on touch-only devices,
  // where hover events never fire — the readout just stays hidden there).
  ({double lat, double lon})? _cursorLatLon;

  DateTime get _currentTime => _startTime.add(Duration(minutes: (_offsetHours * 60).round()));

  @override
  void initState() {
    super.initState();
    CoastlineData.load().then((data) {
      if (mounted) setState(() => _coastline = data);
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
    _transformationController.removeListener(_syncFromController);
    _transformationController.dispose();
    super.dispose();
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
  // 遅くする、または再生スピードを調整できるようにする"), 25%-150% of the
  // original fixed speed, defaulting to 50%. Takes effect immediately —
  // _togglePlay's timer reads _playbackSpeed fresh on every tick, so
  // changing it mid-playback doesn't require a restart.
  Future<void> _showPlaybackSpeedDialog() async {
    var speedLocal = _playbackSpeed;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            return AlertDialog(
              title: const Text('Playback speed'),
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
                      divisions: ((_maxPlaybackSpeed - _minPlaybackSpeed) / 0.05).round(),
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
  // N5-50/E115-150 range zoomed all the way out.
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
    var shipDisplayLocal = _shipDisplayEnabled;
    final typhoonControllers = [
      for (final slot in _typhoonSlots) TextEditingController(text: slot.pastedText),
    ];
    final typhoonDisplayLocal = [for (final slot in _typhoonSlots) slot.displayEnabled];
    final parseErrors = List<String?>.filled(_typhoonSlots.length, null);

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            Widget displayCheckbox(bool value, ValueChanged<bool?> onChanged) {
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Checkbox(value: value, onChanged: onChanged),
                  const Text('Display'),
                ],
              );
            }

            return AlertDialog(
              title: const Text("Ship's Name / Typhoons"),
              content: SizedBox(
                width: 460,
                height: 560,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Expanded(
                            child: Text("Ship's Name", style: TextStyle(fontWeight: FontWeight.bold)),
                          ),
                          displayCheckbox(
                            shipDisplayLocal,
                            (v) => setDialogState(() => shipDisplayLocal = v ?? true),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      TextField(
                        controller: shipController,
                        decoration: const InputDecoration(
                          hintText: 'e.g. MV Example',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                      for (var i = 0; i < _typhoonSlots.length; i++) ...[
                        const Divider(height: 28),
                        Row(
                          children: [
                            Expanded(
                              child: Text('Typhoon ${i + 1}',
                                  style: const TextStyle(fontWeight: FontWeight.bold)),
                            ),
                            displayCheckbox(
                              typhoonDisplayLocal[i],
                              (v) => setDialogState(() => typhoonDisplayLocal[i] = v ?? true),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Paste the JTWC warning text below; the number/name '
                          '(e.g. "11W (NOUL)") and central pressure (e.g. "980hPa") '
                          'are extracted automatically. Leave blank and Save to clear.',
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
                        if (!_typhoonSlots[i].info.isEmpty) ...[
                          const SizedBox(height: 6),
                          Text('Current: ${_typhoonSlots[i].info.summary}',
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
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () {
                    // Validate every slot before applying anything, so a
                    // typo in one box doesn't silently discard the others —
                    // fix the error(s) shown and press Save again.
                    final parsed = List<JtwcTyphoonInfo?>.filled(_typhoonSlots.length, null);
                    var hasError = false;
                    for (var i = 0; i < _typhoonSlots.length; i++) {
                      final pastedText = typhoonControllers[i].text;
                      if (pastedText.trim().isEmpty) {
                        parsed[i] = JtwcTyphoonInfo.empty;
                        continue;
                      }
                      final info = parseJtwcWarningText(pastedText);
                      if (info.designation == null) {
                        hasError = true;
                        parseErrors[i] = "Couldn't find a \"TYPHOON <number> (<name>)\" "
                            'line in the pasted text.';
                        continue;
                      }
                      parsed[i] = info;
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
                    // same text repeatedly doesn't drift the year/month.
                    final newStartTime = parsed[0]?.issuedAtJst(DateTime.now());
                    setState(() {
                      _shipName = shipController.text;
                      _shipDisplayEnabled = shipDisplayLocal;
                      if (newStartTime != null) {
                        _startTime = newStartTime;
                        // Slider position 0 = _startTime itself, so "start
                        // of playback" actually lands on the announced time
                        // rather than wherever the slider happened to be
                        // left from a previous session/track.
                        _offsetHours = 0;
                      }
                      for (var i = 0; i < _typhoonSlots.length; i++) {
                        _typhoonSlots[i].pastedText = typhoonControllers[i].text;
                        _typhoonSlots[i].info = parsed[i]!;
                        _typhoonSlots[i].displayEnabled = typhoonDisplayLocal[i];
                      }
                    });
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

  // The next waypoint ahead of [time] in the voyage plan, or null once
  // there's none left (voyage complete) — used to point the ship icon's
  // apex toward it (2026-07-27 request).
  TrackPoint? _nextWaypointAfter(DateTime time) {
    for (final p in _shipTrack) {
      if (p.time.isAfter(time)) return p;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final ship = positionAt(_shipTrack, _currentTime);
    final shipRoute = _shipTrack.map((p) => LatLng(p.latitude, p.longitude)).toList();
    final typhoons = _typhoonMarkers;
    final distance = typhoons.isEmpty ? 0.0 : distanceNm(ship, typhoons.first.currentPosition);
    final nextWpPoint = _nextWaypointAfter(_currentTime);
    final nextWaypoint =
        nextWpPoint == null ? null : LatLng(nextWpPoint.latitude, nextWpPoint.longitude);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Typhoon & ship tracker'),
        actions: [
          IconButton(
            icon: const Icon(Icons.speed),
            tooltip: 'Playback speed',
            onPressed: _showPlaybackSpeedDialog,
          ),
          IconButton(
            icon: const Icon(Icons.edit_note),
            tooltip: "Ship's Name / Typhoon label",
            onPressed: _showLabelSettingsDialog,
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
                      child: CustomPaint(
                        painter: MapPainter(
                          shipPosition: ship,
                          shipRoute: shipRoute,
                          distanceNauticalMiles: distance,
                          coastlinePolygons: _coastline.polygons,
                          nextWaypoint: nextWaypoint,
                          shipLabel: _shipLabel,
                          showShip: _shipDisplayEnabled,
                          typhoons: typhoons,
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned.fill(child: _buildGridLabelOverlay()),
                Positioned(
                  left: 12,
                  top: 12,
                  child: IgnorePointer(
                    child: Container(
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
                  ),
                ),
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
                if (_cursorLatLon != null)
                  Positioned(
                    right: 64,
                    bottom: 12,
                    child: IgnorePointer(
                      child: Container(
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
                    ),
                  ),
              ],
                );
              },
            ),
          ),
          SafeArea(top: false, child: _buildPlaybackBar()),
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
          SizedBox(
            width: 52,
            child: Center(
              child: IconButton(
                icon: Icon(
                  _isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled,
                  size: 34,
                  color: Colors.orange.shade700,
                ),
                onPressed: _togglePlay,
              ),
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
  String pastedText = '';
  JtwcTyphoonInfo info = JtwcTyphoonInfo.empty;
  bool displayEnabled = true;
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
