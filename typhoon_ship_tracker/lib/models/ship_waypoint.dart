/// A single waypoint of a voyage plan (JRC ECDIS/NAVTOR route CSV, or
/// manually added/edited by the user).
///
/// Unlike [TrackPoint], this has no timestamp — arrival times are computed
/// separately (see `lib/utils/voyage_plan.dart`'s `shipTrackFromWaypoints`)
/// from the departure time plus each leg's distance and [speedKn], so that
/// editing a leg's speed or inserting a waypoint only requires recomputing
/// times, not re-entering them.
class ShipWaypoint {
  /// WPT No. from the source CSV (e.g. 0, 1, 2, ...). Manually added
  /// waypoints get a synthetic number reflecting their position in the list
  /// (see `renumbered()`); this is display-only and not used for ordering —
  /// list order is what matters.
  final int no;

  final double latitude;
  final double longitude;

  /// Speed [kn] for the leg arriving at this waypoint *from the previous
  /// one*. Null for the first waypoint (departure point / WP000 in the JRC
  /// ECDIS format), which has no incoming leg and thus no speed of its own.
  final double? speedKn;

  final String name;

  const ShipWaypoint({
    required this.no,
    required this.latitude,
    required this.longitude,
    this.speedKn,
    this.name = '',
  });

  ShipWaypoint copyWith({
    int? no,
    double? latitude,
    double? longitude,
    double? speedKn,
    bool clearSpeed = false,
    String? name,
  }) {
    return ShipWaypoint(
      no: no ?? this.no,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      speedKn: clearSpeed ? null : (speedKn ?? this.speedKn),
      name: name ?? this.name,
    );
  }
}

// See voyage_plan_entry.dart for the "multiple registered passage plans"
// model that wraps a List<ShipWaypoint> plus a name/departureTime/display
// toggle (2026-08-xx: Passage Plan menu supports up to 10 registered CSVs).

/// Returns [waypoints] with `no` reassigned to their list position
/// (0, 1, 2, ...), used after inserting/removing rows in the editor so the
/// displayed WPT No. stays consistent with the actual order.
List<ShipWaypoint> renumbered(List<ShipWaypoint> waypoints) {
  return [
    for (var i = 0; i < waypoints.length; i++) waypoints[i].copyWith(no: i),
  ];
}
