import 'dart:io';

import 'portable_storage_dir.dart';

/// On-disk library of previously-imported Passage Plan CSVs (2026-07-27
/// request: "同じファイルを毎回外部から選び直すのではなく、取り込んだCSVを
/// 蓄積して後から選べるようにしたい"). Every CSV brought in via "Import CSV"
/// in map_screen.dart is copied here (same filename overwrites the existing
/// entry, after the caller confirms with the user — see
/// `_MapScreenState._confirmCsvOverwrite`), and "Select CSV"/"Edit CSV" read
/// this library back.
///
/// Deliberately separate from the registered Passage Plan list
/// (`_voyagePlans` in map_screen.dart, capped at 10 *currently displayed*
/// routes): this library is the full archive of CSV files ever imported
/// (capped at [maxEntries]), independent of which ones are currently
/// registered/displayed on the map — a registration copies the parsed
/// waypoint data at the time it's created, it doesn't keep a live link back
/// to the library file it came from (except the one-way
/// `VoyagePlanEntry.sourceCsvFileName` tag used only to find matching
/// registered plans when a library file is deleted — see
/// `_MapScreenState._deleteCsvLibraryEntry`).
///
/// Renaming a library entry also updates the name (and
/// `sourceCsvFileName` link) of any already-registered Passage Plan(s)
/// sourced from it, so the Passage Plan menu/legend label stays in sync
/// (2026-08-04, reversing the original 2026-07-27 decision to leave
/// registered plans untouched on rename — see
/// `_MapScreenState._renameCsvLibraryEntry` in map_screen.dart for the
/// sync logic; this class itself only renames the file). Deleting a
/// library entry
/// *does* cascade to any currently-registered plan(s) sourced from it
/// (2026-07-27, revised same day at the user's request — the first version
/// left the plan behind, which was confusing): the caller confirms first
/// when there's at least one such plan, and deletes silently when there
/// isn't (`_deleteCsvLibraryEntry` implements this policy — this class
/// itself has no opinion on it, it just deletes the file it's told to).
///
/// Stored under [appDataDir] (`portable_storage_dir.dart`) — on Windows a
/// `UserData/csv_library` folder next to the running exe (2026-08 change, see
/// `docs/devlog-portable-data-dir.md`: previously this was the OS's per-user
/// "application support" directory, which didn't travel with a copy of the
/// portable Zip's folder to another PC).
class CsvLibrary {
  CsvLibrary._();

  /// Upper bound on the number of files kept in the library (2026-07-27
  /// request: "50個" — user's own sizing based on individual CSV files
  /// being small, so 50 doesn't meaningfully affect disk usage or the app's
  /// performance). Enforced only for *new* filenames — overwriting an
  /// existing entry never increases the count, so it's always allowed.
  static const int maxEntries = 50;

  /// Guards [_migrateFromLegacyIfNeeded] to at most one actual check per
  /// app launch (it's called from every [_libraryDir] resolution, which
  /// itself is not cached — see below).
  static bool _migrationChecked = false;

  // Not cached (2026-07-27): re-resolved on every call rather than caching
  // the Directory after first use. This is only ever called from dialog
  // open/action handlers (not a hot path), and always re-creating if
  // missing keeps it robust against the folder being removed out from
  // under the app (e.g. an antivirus quarantine or the user poking around
  // in Explorer) instead of silently failing on a stale cached reference.
  static Future<Directory> _libraryDir() async {
    final base = await appDataDir();
    final dir = Directory('${base.path}${Platform.pathSeparator}csv_library');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    await _migrateFromLegacyIfNeeded(dir);
    return dir;
  }

  /// One-time, non-destructive migration (2026-08 change — see
  /// `portable_storage_dir.dart`'s doc comment): if this is a Windows build,
  /// the new library folder is still empty, and CSV files exist in the old
  /// per-user location, copy them across so a device that already had a CSV
  /// library doesn't appear to lose it after upgrading to a build with this
  /// change. The old files are left in place (copy, not move) — harmless
  /// leftover disk usage is a safer failure mode than a destructive move.
  static Future<void> _migrateFromLegacyIfNeeded(Directory newDir) async {
    if (_migrationChecked || !Platform.isWindows) return;
    _migrationChecked = true;
    final newDirIsEmpty = await newDir.list().isEmpty;
    if (!newDirIsEmpty) return;
    final legacyBase = await legacyAppDataDir();
    final legacyDir = Directory('${legacyBase.path}${Platform.pathSeparator}csv_library');
    if (!await legacyDir.exists()) return;
    final legacyFiles = await legacyDir.list().toList();
    for (final entry in legacyFiles.whereType<File>()) {
      final name = entry.uri.pathSegments.last;
      try {
        await entry.copy('${newDir.path}${Platform.pathSeparator}$name');
      } catch (_) {
        // Best-effort: one unreadable/locked legacy file shouldn't block
        // migrating the rest.
      }
    }
  }

  /// Filenames (including the `.csv` extension) currently in the library,
  /// sorted alphabetically (case-insensitive) for a stable, predictable
  /// order in the Select CSV / Edit CSV lists.
  static Future<List<String>> listFileNames() async {
    final dir = await _libraryDir();
    final entries = await dir.list().toList();
    final names = entries
        .whereType<File>()
        .map((f) => f.uri.pathSegments.last)
        .where((n) => n.toLowerCase().endsWith('.csv'))
        .toList();
    names.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return names;
  }

  static Future<int> count() async => (await listFileNames()).length;

  static Future<bool> exists(String fileName) async {
    final dir = await _libraryDir();
    return File('${dir.path}${Platform.pathSeparator}$fileName').exists();
  }

  /// Copies [sourcePath] into the library under its own filename,
  /// overwriting any existing entry with the same name. Callers are
  /// expected to have already checked [exists] and confirmed an overwrite
  /// with the user first (2026-07-27 request: "上書き保存（確認テロップ出ると
  /// 良いY/N）") and to have checked [maxEntries] against [count] for a
  /// genuinely new filename — this method itself doesn't re-check either,
  /// so it never blocks or prompts on its own.
  static Future<void> importFrom(String sourcePath) async {
    final dir = await _libraryDir();
    final fileName = sourcePath.split(RegExp(r'[\\/]')).last;
    await File(sourcePath).copy('${dir.path}${Platform.pathSeparator}$fileName');
  }

  static Future<String> readText(String fileName) async {
    final dir = await _libraryDir();
    return File('${dir.path}${Platform.pathSeparator}$fileName').readAsString();
  }

  /// Renames a library entry in place. [newFileName] must already include
  /// the `.csv` extension — callers (the Rename dialog) are responsible for
  /// validating the name and appending the extension before calling this.
  static Future<void> rename(String oldFileName, String newFileName) async {
    final dir = await _libraryDir();
    await File('${dir.path}${Platform.pathSeparator}$oldFileName')
        .rename('${dir.path}${Platform.pathSeparator}$newFileName');
  }

  static Future<void> delete(String fileName) async {
    final dir = await _libraryDir();
    final file = File('${dir.path}${Platform.pathSeparator}$fileName');
    if (await file.exists()) {
      await file.delete();
    }
  }
}
