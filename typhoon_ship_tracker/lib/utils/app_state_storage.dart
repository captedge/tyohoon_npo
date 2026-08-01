import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'portable_storage_dir.dart';
import '../models/ship_waypoint.dart';
import '../models/voyage_plan_entry.dart';

/// Persists/restores the user's registered-info state (2026-07-27 request:
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
/// state too, without a migration step. The JMA source (2026-07-29 addition)
/// follows the same "store raw, re-parse on load" pattern: the last
/// successfully-fetched bulletin's *raw XML text* is stored, re-parsed with
/// `parseJmaTyphoonXml` on load — this is an offline-use cache of a manual
/// fetch, not a periodic background fetch (scope decided with the user
/// 2026-07-29: data-usage concerns rule out auto-fetching on a schedule).
///
/// Everything is stored as a single JSON blob in one file under [appDataDir]
/// (`portable_storage_dir.dart`) — this app has no need for querying
/// individual fields, and a single file keeps load/save atomic from this
/// app's point of view (no risk of a half-written set of keys after a crash
/// mid-save).
///
/// **2026-08 change**: this used to go through `SharedPreferences` (which on
/// Windows stores its own JSON file under the OS's per-user "application
/// support" directory). Moved to a plain file under [appDataDir] instead so
/// that on Windows it lives in a `UserData` folder next to the exe — inside the
/// portable Zip's extracted folder — and travels with a copy of that folder
/// to another PC (see `docs/devlog-portable-data-dir.md`). [load] still
/// falls back to the old `SharedPreferences` key once, as a one-time,
/// non-destructive migration for a device that already had state saved
/// there — see its doc comment.
class AppStateStorage {
  AppStateStorage._();

  static const _fileName = 'app_state.v1.json';

  /// Pre-2026-08 storage key — read-only now, kept solely for the one-time
  /// migration fallback in [load].
  static const _legacyPrefsKey = 'typhoon_ship_tracker.app_state.v1';

  static Future<File> _file() async {
    final dir = await appDataDir();
    return File('${dir.path}${Platform.pathSeparator}$_fileName');
  }

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
    final json = <String, dynamic>{
      'shipName': shipName,
      'playbackSpeed': playbackSpeed,
      'voyagePlans': [
        for (final plan in voyagePlans)
          {
            'name': plan.name,
            'departureTime': plan.departureTime.toIso8601String(),
            'displayEnabled': plan.displayEnabled,
            'sourceCsvFileName': plan.sourceCsvFileName,
            // Route Color override (2026-08-xx addition, kShipColorPalette —
            // see color_palette.dart): stored as the 32-bit ARGB int
            // Color.value round-trips through, null/absent when this plan is
            // still on the automatic per-plan color (see
            // VoyagePlanEntry.colorOverride's doc comment).
            'colorOverride': plan.colorOverride?.value,
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
            // JSON key kept as "displayEnabled" (2026-07-28: field renamed to
            // jtwcDisplayEnabled on the Dart side when the JMA source was
            // added, but the stored key is left unchanged for backward
            // compatibility with already-saved state — this app has no
            // migration step, and there's no reason to force one here).
            'displayEnabled': slot.jtwcDisplayEnabled,
            // JSON key kept as "ringsEnabled" (2026-07-28: field renamed to
            // jtwcRingsEnabled when rings became per-source — same backward
            // -compatibility reasoning as "displayEnabled" above).
            'ringsEnabled': slot.jtwcRingsEnabled,
            // Track color override (2026-08-xx addition, kTyphoonColorPalette
            // — see color_palette.dart), same "store the ARGB int, null when
            // still on the source's default color" convention as
            // voyagePlans' colorOverride above.
            'jtwcColorOverride': slot.jtwcColorOverride?.value,
            // JMA offline cache (2026-07-29 addition): the raw bulletin XML
            // from the last successful "Fetch from JMA" press, re-parsed on
            // load — same "store raw, re-parse" convention as pastedText
            // above (see AppStateStorage class doc). Null/absent when
            // nothing has ever been successfully fetched for this slot.
            'jmaRawXml': slot.jmaRawXml,
            // Device-local timestamp of that successful fetch (plain JST
            // wall-clock DateTime, this app's usual convention — see
            // jtwc_parser.dart's issuedAtJst doc comment). Stored via
            // toIso8601String()/DateTime.parse() the same way
            // VoyagePlanEntry.departureTime already is below: for a
            // non-UTC-tagged DateTime, that round-trip preserves the
            // wall-clock fields exactly with no UTC conversion involved.
            'jmaFetchedAtJst': slot.jmaFetchedAtJst?.toIso8601String(),
            'jmaDisplayEnabled': slot.jmaDisplayEnabled,
            'jmaRingsEnabled': slot.jmaRingsEnabled,
            'jmaColorOverride': slot.jmaColorOverride?.value,
          },
      ],
    };
    final file = await _file();
    await file.writeAsString(jsonEncode(json));
  }

  /// Loads previously-saved state, or null if nothing was saved yet (first
  /// launch) or the saved JSON couldn't be parsed (e.g. a future version
  /// changed the shape — fails safe by falling back to the built-in sample
  /// data, same as a fresh install, rather than crashing on launch).
  static Future<AppStateSnapshot?> load() async {
    // Whole method (file I/O + parsing) is one try/catch — a read/exists
    // check throwing (e.g. a permissions error, a half-written file) must
    // fail safe the same way a JSON parse error already does, not propagate
    // and crash the app on launch (see doc comment above).
    try {
      final file = await _file();
      String? raw;
      if (await file.exists()) {
        raw = await file.readAsString();
      } else if (Platform.isWindows) {
        // One-time migration (2026-08 change, see class doc above): the new
        // file doesn't exist yet — check the old SharedPreferences-backed
        // location so a device that already had saved state doesn't see it
        // vanish after upgrading to a build with this change. Copies the raw
        // JSON straight into the new file (best-effort) so this only has to
        // happen once; the parse below is shared with the normal path.
        final prefs = await SharedPreferences.getInstance();
        raw = prefs.getString(_legacyPrefsKey);
        if (raw != null) {
          try {
            await file.writeAsString(raw);
          } catch (_) {
            // Best-effort: still use the just-read legacy value for this
            // session even if the copy-forward write failed.
          }
        }
      }
      if (raw == null) return null;
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
          // Absent for plans saved before this field existed (2026-07-27) —
          // null is the correct "unknown source" value for those, same as
          // a freshly-constructed VoyagePlanEntry with no source given.
          sourceCsvFileName: planMap['sourceCsvFileName'] as String?,
          // Absent for plans saved before this field existed (2026-08-xx) —
          // null is the correct "still on the automatic color" value, same
          // treatment as sourceCsvFileName above.
          colorOverride: planMap['colorOverride'] == null ? null : Color(planMap['colorOverride'] as int),
        ));
      }
      final typhoonSlots = <TyphoonSlotSnapshot>[
        for (final slotJson in (json['typhoonSlots'] as List? ?? const []))
          TyphoonSlotSnapshot(
            pastedText: (slotJson as Map<String, dynamic>)['pastedText'] as String? ?? '',
            jtwcDisplayEnabled: slotJson['displayEnabled'] as bool? ?? true,
            jtwcRingsEnabled: slotJson['ringsEnabled'] as bool? ?? true,
            // Absent for state saved before this field existed (2026-08-xx) —
            // null is the correct "still on the default color" value.
            jtwcColorOverride:
                slotJson['jtwcColorOverride'] == null ? null : Color(slotJson['jtwcColorOverride'] as int),
            // Absent for state saved before this field existed (2026-07-29) —
            // null is the correct "nothing cached yet" value, same treatment
            // as VoyagePlanEntry.sourceCsvFileName above.
            jmaRawXml: slotJson['jmaRawXml'] as String?,
            jmaFetchedAtJst: (slotJson['jmaFetchedAtJst'] as String?) == null
                ? null
                : DateTime.parse(slotJson['jmaFetchedAtJst'] as String),
            jmaDisplayEnabled: slotJson['jmaDisplayEnabled'] as bool? ?? false,
            jmaRingsEnabled: slotJson['jmaRingsEnabled'] as bool? ?? true,
            jmaColorOverride:
                slotJson['jmaColorOverride'] == null ? null : Color(slotJson['jmaColorOverride'] as int),
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
    required this.jtwcDisplayEnabled,
    required this.jtwcRingsEnabled,
    this.jtwcColorOverride,
    this.jmaRawXml,
    this.jmaFetchedAtJst,
    required this.jmaDisplayEnabled,
    required this.jmaRingsEnabled,
    this.jmaColorOverride,
  });

  final String pastedText;
  final bool jtwcDisplayEnabled;
  final bool jtwcRingsEnabled;

  /// Track/marker color override (2026-08-xx addition, Forecast dialog's
  /// per-source color swatches — see color_palette.dart's
  /// `kTyphoonColorPalette`) — null means "use the source's usual fixed
  /// default color" (map_screen.dart's `_jtwcColor`).
  final Color? jtwcColorOverride;

  /// Offline cache of the last successful "Fetch from JMA" (2026-07-29
  /// addition — scope decided with the user: no periodic auto-fetch, manual
  /// button stays as-is, but its result should survive an app restart/be
  /// usable offline rather than being session-only as before). [jmaRawXml]
  /// is the raw bulletin XML text (re-parsed on load, not stored pre-parsed —
  /// see map_screen.dart's `_TyphoonSlot.jmaRawXml` doc comment), null if
  /// nothing has ever been successfully fetched for this slot.
  final String? jmaRawXml;

  /// Device-local timestamp of that fetch, shown to the user as "how old is
  /// this cached data" — see map_screen.dart.
  final DateTime? jmaFetchedAtJst;
  final bool jmaDisplayEnabled;
  final bool jmaRingsEnabled;

  /// Same as [jtwcColorOverride], for the JMA source (map_screen.dart's
  /// `_jmaColor` default).
  final Color? jmaColorOverride;
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
