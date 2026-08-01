import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Base directory this app persists its own on-disk state under: saved
/// settings/registrations (`app_state_storage.dart`), the CSV library
/// (`csv_library.dart`), and the personal-build wave field cache
/// (`wave_field_cache.dart`).
///
/// **Windows** (2026-08 change — user request: portable Zip folder copied to
/// another PC should bring its accumulated data with it, which the previous
/// per-user "application support" location couldn't do): a `UserData` folder
/// next to the running executable, i.e. *inside* the portable Zip's
/// extracted folder. Copying that whole folder to another PC now brings the
/// data with it — no separate AppData copy step needed.
///
/// **Naming pitfall found and fixed (2026-08-01)**: this folder was
/// originally named `Data`, which collided with the `data` folder Flutter
/// itself always creates next to the exe (bundled engine assets —
/// `icudtl.dat`/`flutter_assets`, required just to launch). Windows
/// filenames are case-insensitive, so `Data` and `data` are the *same*
/// folder there — this app's own files ended up written straight into
/// Flutter's own required folder, and `build_release.bat`'s zip-exclusion
/// step (added the same day to keep local test data out of shipped
/// builds — see that file) then excluded that merged folder wholesale,
/// silently stripping the files Flutter needs to start at all. Symptom was
/// the app not launching (no window at all) after extracting a fresh zip.
/// Renamed to `UserData`, which doesn't collide with anything Flutter
/// creates, to fix this. See `docs/devlog-portable-data-dir.md`.
///
/// Trade-offs accepted (discussed with the user before making this change,
/// see `docs/devlog-portable-data-dir.md`):
/// - `clean_project.bat` (`flutter clean`) deletes the entire `build/`
///   folder, which wipes this `UserData` folder too during development. A
///   manual, infrequently-used command — not part of the normal build/run
///   loop (`build_release.bat`/`run_windows.bat` don't delete unrelated
///   files already sitting in the output folder).
/// - Debug (`run_windows.bat`, `build\windows\x64\runner\Debug\`) and
///   Release (`build_release.bat`, `...\Release\`) are separate folders, so
///   they no longer share one data store the way the old AppData location
///   did — each build variant now keeps its own `UserData` folder next to
///   its own exe.
///
/// **Other platforms** (Android/iOS, once mobile support lands): unchanged
/// — still the OS's per-app "application support" directory via
/// `path_provider`. There is no portable-folder concept on mobile; each
/// mobile app already has private, per-device storage, so this desktop-only
/// portability request doesn't apply there.
Future<Directory> appDataDir() async {
  if (Platform.isWindows) {
    final exeDir = File(Platform.resolvedExecutable).parent;
    final dir = Directory('${exeDir.path}${Platform.pathSeparator}UserData');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }
  return getApplicationSupportDirectory();
}

/// The pre-2026-08 storage location (OS "application support" directory).
/// Kept read-only, solely so each store can do a one-time, non-destructive
/// migration read on first launch after the change above — a device that
/// already had data saved there shouldn't see it silently vanish. Never
/// written to going forward; only meaningful to call this when
/// `Platform.isWindows` (on other platforms it's identical to [appDataDir],
/// so there is nothing to migrate from).
Future<Directory> legacyAppDataDir() => getApplicationSupportDirectory();
