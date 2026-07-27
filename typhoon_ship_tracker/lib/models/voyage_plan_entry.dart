import 'ship_waypoint.dart';

/// One registered passage-plan CSV, shown as a row in `MapScreen`'s Passage
/// Plan dialog (2026-08-xx request: up to 10 plans can be registered at
/// once — e.g. separate legs of a voyage with a port call in between, each
/// imported as its own CSV with its own departure time — rather than only a
/// single voyage plan as before).
///
/// Mutable — edited in place from the Passage Plan dialog's Import/Edit/
/// Delete/Display actions in `MapScreen`, the same pattern `_TyphoonSlot`
/// uses for the up-to-3 typhoon slots.
class VoyagePlanEntry {
  VoyagePlanEntry({
    required this.name,
    required this.waypoints,
    required this.departureTime,
    this.displayEnabled = true,
  });

  /// Defaults to the imported CSV's filename (without extension) when first
  /// registered. Purely a label for the Passage Plan list — not used in any
  /// position/distance calculation.
  String name;

  List<ShipWaypoint> waypoints;

  /// Departure time for `waypoints.first` (WP0). Entered in
  /// `VoyagePlanScreen` since the JRC ECDIS/NAVTOR CSV format carries no
  /// date/time columns (see `docs/data-format-notes.md`).
  DateTime departureTime;

  /// Whether this plan is currently drawn on the map as its own independent
  /// ship/route (`MapScreen._activeShipTracks`/`_buildShipMarkers`).
  /// Multiple plans can be Display-on at the same time and are drawn fully
  /// independently — e.g. comparing several destination options from the
  /// same departure port/time (2026-08-xx request) — *not* concatenated
  /// into one combined track (an earlier design for a different, since
  /// abandoned, port-call use case; see docs/devlog-passage-plan-multi.md).
  bool displayEnabled;
}
