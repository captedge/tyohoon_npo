import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../models/track_point.dart';
import '../utils/interpolation.dart';
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
  static const double _minZoom = 1.0;
  static const double _maxZoom = 8.0;
  double _offsetHours = 24;
  bool _isPlaying = false;
  Timer? _playTimer;
  double _zoom = 1.0;

  DateTime get _currentTime => _startTime.add(Duration(minutes: (_offsetHours * 60).round()));

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

  // NOTE: zoom is tracked as a single absolute scale ([_minZoom].._maxZoom])
  // so the +/- buttons, the slider and the mouse wheel all agree on the
  // current level. Pan offset is not preserved across a zoom change yet
  // (TODO: zoom around the current viewport center instead of resetting it).
  void _setZoom(double value) {
    final clamped = value.clamp(_minZoom, _maxZoom).toDouble();
    setState(() => _zoom = clamped);
    _transformationController.value = Matrix4.identity()..scale(clamped, clamped);
  }

  void _zoomBy(double factor) => _setZoom(_zoom * factor);

  void _handlePointerScroll(PointerSignalEvent event) {
    if (event is PointerScrollEvent) {
      final zoomingIn = event.scrollDelta.dy < 0;
      _zoomBy(zoomingIn ? 1.1 : 0.9);
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
            child: Stack(
              children: [
                Listener(
                  onPointerSignal: _handlePointerScroll,
                  child: InteractiveViewer(
                    transformationController: _transformationController,
                    minScale: _minZoom,
                    maxScale: _maxZoom,
                    onInteractionEnd: (details) {
                      // Keep the slider/buttons in sync after a pinch gesture.
                      setState(() {
                        _zoom = _transformationController.value.getMaxScaleOnAxis();
                      });
                    },
                    child: SizedBox.expand(
                      child: CustomPaint(
                        painter: MapPainter(
                          shipPosition: ship,
                          shipRoute: shipRoute,
                          typhoonPosition: typhoon,
                          typhoonForecastTrack: forecastFromNow,
                          distanceNauticalMiles: distance,
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
