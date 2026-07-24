/// A single dated position (typhoon forecast point or ship waypoint).
///
/// Both typhoon tracks and ship voyage plans are represented as a list of
/// [TrackPoint]s ordered by [time]. Positions between two points are found
/// by linear interpolation (see `lib/utils/interpolation.dart`).
class TrackPoint {
  final DateTime time;
  final double latitude;
  final double longitude;

  /// Optional label such as "+24h", "Waypoint 3", used for display only.
  final String? label;

  const TrackPoint({
    required this.time,
    required this.latitude,
    required this.longitude,
    this.label,
  });
}
