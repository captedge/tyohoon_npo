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
    this.sourceCsvFileName,
  });

  /// Defaults to the imported CSV's filename (without extension) when first
  /// registered. Purely a label for the Passage Plan list — not used in any
  /// position/distance calculation.
  String name;

  /// The CSV library filename (with extension — see `CsvLibrary`) this plan
  /// was registered from via "Import CSV" or "Select CSV", or null for
  /// plans registered before this field existed (2026-07-27 addition).
  /// Used only to find which registered plan(s) to cascade-delete when the
  /// same file is deleted from the library via "Edit CSV" (2026-07-27
  /// request: "Editで削除：Passage Planに残っている場合は...削除して良いですか
  /// Y/N、残っていない場合は質問なしで削除") — not read anywhere else.
  /// Deliberately *not* kept in sync when the library file is renamed (the
  /// user separately confirmed renaming should not affect an already-
  /// registered plan's own name/data) — so renaming a source file after
  /// registering from it "orphans" this link; the plan itself is
  /// unaffected, it just won't be found for cascade-delete against its new
  /// filename.
  String? sourceCsvFileName;

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
