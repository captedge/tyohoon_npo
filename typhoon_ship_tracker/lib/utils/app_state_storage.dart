import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/ship_waypoint.dart';
import '../models/voyage_plan_entry.dart';

/// Persists/restores the user's registered-info state (2026-08-xx request:
/// "アプリを閉じてまた開いた場合に直前の入力済み登録情報が読み込まれるように
/// したい") so the ship name, registered Passage Plans, pasted typhoon
/// warning texts, and a couple of UI settings survive an app restart.
///
/// Deliberately narrow, mirroring the same "manual entry until the real
/// feed reader exists" scope as the rest of the map screen: this stores the
/// *raw pasted JTWC text* per typhoon slot (not the parsed [JtwcTyphoonInfo]
/// itself), and re-parses it on load with `parseJtwcWarningText` — the same
/// function `_showLabelSettingsDialog`'s Save handler already calls. That
/// keeps this module decoupled from jtwc_parser.dart's internals and means
/// any future improvement to the parser automatically applies to restored
/// state too, without a migration step.
///
/// Everything is stored as a single JSON blob under one SharedPreferences
/// key — this app has no need for querying individual fields, and a single
/// key keeps load/save atomic from this app's point of view (no risk of a
/// half-written set of keys after a crash mid-save).
class AppStateStorage {
  AppStateStorage._();

  static const _prefsKey = 'typhoon_ship_tracker.app_state.v1';

  /// Saves the current state. Fire-and-forget from the caller's point of
  /// view (callers don't `await` this — see map_screen.dart's `_saveState`
  /// call sites) since there's nothing the UI needs to block on; if it fails
  /// (e.g. disk full) the in-memory state the user is looking at is
  /// unaffected, only the next app restart won't see this particular change.
  static Future<void> save({
    required String shipName,
    required double playbackSpeed,
    required List<VoyagePlanEntry> voyagePlans,
    required List<TyphoonSlotSnapshot> typhoonSlots,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final json = <String, dynamic>{
      'shipName': shipName,
      'playbackSpeed': playbackSpeed,
      'voyagePlans': [
        for (final plan in voyagePlans)
          {
            'name': plan.name,
            'departureTime': plan.departureTime.toIso8601String(),
            'displayEnabled': plan.displayEnabled,
            'waypoints': [
              for (final wp in plan.waypoints)
                {
                  'no': wp.no,
                  'latitude': wp.latitude,
                  'longitude': wp.longitude,
                  'speedKn': wp.speedKn,
                  'name': wp.name,
                },
            ],
          },
      ],
      'typhoonSlots': [
        for (final slot in typhoonSlots)
          {
            'pastedText': slot.pastedText,
            'displayEnabled': slot.displayEnabled,
            'ringsEnabled': slot.ringsEnabled,
          },
      ],
    };
    await prefs.setString(_prefsKey, jsonEncode(json));
  }

  /// Loads previously-saved state, or null if nothing was saved yet (first
  /// launch) or the saved JSON couldn't be parsed (e.g. a future version
  /// changed the shape — fails safe by falling back to the built-in sample
  /// data, same as a fresh install, rather than crashing on launch).
  static Future<AppStateSnapshot?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null) return null;
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final voyagePlans = <VoyagePlanEntry>[];
      for (final planJson in (json['voyagePlans'] as List? ?? const [])) {
        final planMap = planJson as Map<String, dynamic>;
        final waypoints = <ShipWaypoint>[
          for (final wpJson in (planMap['waypoints'] as List? ?? const []))
            _waypointFromJson(wpJson as Map<String, dynamic>),
        ];
        voyagePlans.add(VoyagePlanEntry(
          name: planMap['name'] as String? ?? '',
          waypoints: waypoints,
          departureTime: DateTime.parse(planMap['departureTime'] as String),
          displayEnabled: planMap['displayEnabled'] as bool? ?? true,
        ));
      }
      final typhoonSlots = <TyphoonSlotSnapshot>[
        for (final slotJson in (json['typhoonSlots'] as List? ?? const []))
          TyphoonSlotSnapshot(
            pastedText: (slotJson as Map<String, dynamic>)['pastedText'] as String? ?? '',
            displayEnabled: slotJson['displayEnabled'] as bool? ?? true,
            ringsEnabled: slotJson['ringsEnabled'] as bool? ?? true,
          ),
      ];
      return AppStateSnapshot(
        shipName: json['shipName'] as String? ?? '',
        playbackSpeed: (json['playbackSpeed'] as num?)?.toDouble() ?? 0.5,
        voyagePlans: voyagePlans,
        typhoonSlots: typhoonSlots,
      );
    } catch (_) {
      // Malformed/unreadable saved state — treat as "nothing saved" rather
      // than surfacing a load error to the user (see class doc above).
      return null;
    }
  }

  static ShipWaypoint _waypointFromJson(Map<String, dynamic> json) {
    return ShipWaypoint(
      no: json['no'] as int,
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      speedKn: (json['speedKn'] as num?)?.toDouble(),
      name: json['name'] as String? ?? '',
    );
  }
}

/// Plain data snapshot of one `_TyphoonSlot`'s persisted fields (map_screen.dart
/// keeps `_TyphoonSlot` itself private, so this is a public stand-in map_screen.dart
/// can construct/read without exposing `_TyphoonSlot` itself).
class TyphoonSlotSnapshot {
  const TyphoonSlotSnapshot({
    required this.pastedText,
    required this.displayEnabled,
    required this.ringsEnabled,
  });

  final String pastedText;
  final bool displayEnabled;
  final bool ringsEnabled;
}

/// Result of [AppStateStorage.load]: everything map_screen.dart needs to
/// restore its state, including the raw pasted JTWC text per typhoon slot
/// (map_screen.dart re-parses these itself via `parseJtwcWarningText`, the
/// same call its own Save handler uses — see class doc above).
class AppStateSnapshot {
  const AppStateSnapshot({
    required this.shipName,
    required this.playbackSpeed,
    required this.voyagePlans,
    required this.typhoonSlots,
  });

  final String shipName;
  final double playbackSpeed;
  final List<VoyagePlanEntry> voyagePlans;
  final List<TyphoonSlotSnapshot> typhoonSlots;
}
