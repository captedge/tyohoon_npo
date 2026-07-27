import '../models/ship_waypoint.dart';
import '../models/track_point.dart';
import 'interpolation.dart';

/// Thrown when [shipTrackFromWaypoints] can't compute an arrival time for a
/// leg — currently only when a non-first waypoint has no leg speed set.
/// Meant to be shown to the user as-is (e.g. from the voyage-plan editor's
/// Save action) so they can fill in the missing speed.
class VoyagePlanTimeException implements Exception {
  VoyagePlanTimeException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Builds the [TrackPoint] list `MapScreen`/`positionAt` use for the ship
/// track, from a voyage plan (departure point + waypoints, each carrying the
/// speed for the leg arriving at it) and a departure time for the first
/// waypoint.
///
/// Each waypoint's arrival time is the previous waypoint's time plus
/// (leg distance in nautical miles, via [distanceNm]'s mid-latitude sailing
/// calculation) ÷ (that leg's speed in knots) — i.e. distance/speed = time,
/// accumulated leg by leg from [departureTime]. This is what lets editing a
/// leg's speed, or inserting/removing a waypoint, be reflected just by
/// recomputing this list — no times are stored on [ShipWaypoint] itself.
List<TrackPoint> shipTrackFromWaypoints(
  List<ShipWaypoint> waypoints,
  DateTime departureTime,
) {
  if (waypoints.isEmpty) return [];

  final points = <TrackPoint>[
    TrackPoint(
      time: departureTime,
      latitude: waypoints.first.latitude,
      longitude: waypoints.first.longitude,
      label: waypoints.first.name.isEmpty ? null : waypoints.first.name,
    ),
  ];

  var time = departureTime;
  for (var i = 1; i < waypoints.length; i++) {
    final prev = waypoints[i - 1];
    final wp = waypoints[i];
    final legNm = distanceNm(
      LatLng(prev.latitude, prev.longitude),
      LatLng(wp.latitude, wp.longitude),
    );
    final speed = wp.speedKn;
    if (speed == null || speed <= 0) {
      final label = wp.name.isEmpty ? 'WPT ${wp.no}' : 'WPT ${wp.no} (${wp.name})';
      throw VoyagePlanTimeException('$label: 区間速力が未設定です。速力[kn]を入力してください。');
    }
    final hours = legNm / speed;
    time = time.add(Duration(minutes: (hours * 60).round()));
    points.add(TrackPoint(
      time: time,
      latitude: wp.latitude,
      longitude: wp.longitude,
      label: wp.name.isEmpty ? null : wp.name,
    ));
  }
  return points;
}
