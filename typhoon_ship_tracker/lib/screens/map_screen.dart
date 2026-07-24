import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../models/track_point.dart';
import '../utils/coastline.dart';
import '../utils/interpolation.dart';
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
  late final DateTime _startTime = DateTime.now();
  late final List<TrackPoint> _shipTrack = [
    TrackPoint(time: _startTime, latitude: 25.0, longitude: 121.0, label: 'Departure'),
    TrackPoint(time: _startTime.add(const Duration(hours: 72)), latitude: 20.0, longitude: 124.0, label: 'Waypoint 1'),
  ];
  late final List<TrackPoint> _typhoonTrack = [
    TrackPoint(time: _startTime, latitude: 13.0, longitude: 126.0, label: 'Now'),
    TrackPoint(time: _startTime.add(const Duration(hours: 24)), latitude: 17.0, longitude: 124.0, label: '+24h'),
    TrackPoint(time: _startTime.add(const Duration(hours: 48)), latitude: 22.0, longitude: 123.0, label: '+48h'),
    TrackPoint(time: _startTime.add(const Duration(hours: 72)), latitude: 28.0, longitude: 124.0, label: '+72h'),
  ];

  static const int _maxOffsetHours = 72;
  double _offsetHours = 24;
  bool _isPlaying = false;
  Timer? _playTimer;

  // _zoom/_translation are in MapBounds.canvasSize units (a fixed logical
  // size — see MapBounds for why). _fitScale is the zoom level at which the
  // whole canvas exactly fits the current viewport; it's the practical
  // "zoomed all the way out" limit and depends on the window size, so it's
  // recomputed on every layout rather than being a constant.
  double _zoom = 1.0;
  Offset _translation = Offset.zero;
  Size _viewportSize = Size.zero;
  double _fitScale = 1.0;
  bool _initializedView = false;

  double get _minZoom => _fitScale;
  double get _maxZoom => _fitScale * 12;

  CoastlineData _coastline = CoastlineData.empty;

  DateTime get _currentTime => _startTime.add(Duration(minutes: (_offsetHours * 60).round()));

  @override
  void initState() {
    super.initState();
    CoastlineData.load().then((data) {
      if (mounted) setState(() => _coastline = data);
    });
  }

  @override
  void dispose() {
    _playTimer?.cancel();
    _transformationController.dispose();
    super.dispose();
  }

  void _togglePlay() {
    setState(() => _isPlaying = !_isPlaying);
    if (_isPlaying) {
      _playTimer = Timer.periodic(const Duration(milliseconds: 200), (_) {
        setState(() {
          _offsetHours += 1;
          if (_offsetHours >= _maxOffsetHours) {
            _offsetHours = _maxOffsetHours.toDouble();
            _isPlaying = false;
            _playTimer?.cancel();
          }
        });
      });
    } else {
      _playTimer?.cancel();
    }
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

  void _handlePointerScroll(PointerSignalEvent event) {
    if (event is PointerScrollEvent) {
      final zoomingIn = event.scrollDelta.dy < 0;
      _zoomAtViewportPoint(event.localPosition, zoomingIn ? 1.1 : 0.9);
    }
  }

  // Keep (_zoom, _translation) in sync after the user drags/pinches the map
  // directly via InteractiveViewer (which writes into the controller itself
  // during those gestures).
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
    _fitScale = math.min(
      viewportSize.width / MapBounds.canvasWidth,
      viewportSize.height / MapBounds.canvasHeight,
    );
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

  @override
  Widget build(BuildContext context) {
    final ship = positionAt(_shipTrack, _currentTime);
    final typhoon = positionAt(_typhoonTrack, _currentTime);
    final forecastFromNow = _typhoonTrack
        .where((p) => p.time.isAfter(_currentTime))
        .map((p) => LatLng(p.latitude, p.longitude))
        .toList();
    final shipRoute = _shipTrack.map((p) => LatLng(p.latitude, p.longitude)).toList();
    final distance = distanceNm(ship, typhoon);

    return Scaffold(
      appBar: AppBar(title: const Text('Typhoon & ship tracker')),
      body: Column(
        children: [
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                _updateViewportSize(Size(constraints.maxWidth, constraints.maxHeight));
                return Stack(
              children: [
                Listener(
                  onPointerSignal: _handlePointerScroll,
                  child: InteractiveViewer(
                    transformationController: _transformationController,
                    minScale: _minZoom,
                    maxScale: _maxZoom,
                    onInteractionEnd: (details) => _syncFromController(),
                    constrained: false,
                    child: SizedBox(
                      width: MapBounds.canvasWidth,
                      height: MapBounds.canvasHeight,
                      child: CustomPaint(
                        painter: MapPainter(
                          shipPosition: ship,
                          shipRoute: shipRoute,
                          typhoonPosition: typhoon,
                          typhoonForecastTrack: forecastFromNow,
                          distanceNauticalMiles: distance,
                          coastlinePolygons: _coastline.polygons,
                        ),
                      ),
                    ),
                  ),
                ),
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
              ],
                );
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  IconButton(
                    icon: Icon(_isPlaying ? Icons.pause : Icons.play_arrow),
                    onPressed: _togglePlay,
                  ),
                  Expanded(
                    child: Slider(
                      min: 0,
                      max: _maxOffsetHours.toDouble(),
                      value: _offsetHours,
                      onChanged: (v) => setState(() => _offsetHours = v),
                    ),
                  ),
                  SizedBox(
                    width: 56,
                    child: Text('+${_offsetHours.round()}h', textAlign: TextAlign.right),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
