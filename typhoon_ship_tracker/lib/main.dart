import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb, LicenseEntryWithLineBreaks, LicenseRegistry;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'screens/map_screen.dart';
import 'utils/app_fonts.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  _registerFontLicenses();
  // Mobile UI policy (confirmed 2026-08-02, docs/devlog-mobile-flutter.md):
  // reuse the desktop screens as-is in landscape rather than redesign for
  // portrait, so lock orientation to landscape on phones/tablets only.
  // Desktop (Windows) keeps free window resizing — unaffected by this.
  if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    // Full-screen map (2026-08-02 request): let the map draw edge-to-edge,
    // behind the system status bar. The system bars stay visible
    // (translucent) rather than fully hidden — MapScreen's own mobile-only
    // top/bottom overlay bars (map_screen.dart) already account for the
    // status bar via SafeArea, so this doesn't need immersive/sticky mode.
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }
  runApp(const TyphoonShipTrackerApp());
}

// Registers the two bundled fonts' license texts (2026-08-04 addition,
// user request) so they show up in the existing "Open-Source Licenses"
// page (map_screen.dart's `_showAboutDialog`, via Flutter's built-in
// `showLicensePage`) alongside the licenses Flutter already auto-collects
// from pub packages. Auto-collection only covers pub dependencies —
// LicenseRegistry has no way to discover arbitrary bundled asset files on
// its own, so these two need registering explicitly here. The .txt files
// themselves are declared under pubspec.yaml's `assets:` (separately from
// their `fonts:` entry, which only bundles the .ttf as a font asset) so
// `rootBundle.loadString` can read them at runtime.
void _registerFontLicenses() {
  LicenseRegistry.addLicense(() async* {
    final comicMono = await rootBundle.loadString('assets/fonts/ComicMono-LICENSE.txt');
    yield LicenseEntryWithLineBreaks(const ['Comic Mono'], comicMono);
    final zenMaru = await rootBundle.loadString('assets/fonts/ZenMaruGothic-OFL.txt');
    yield LicenseEntryWithLineBreaks(const ['Zen Maru Gothic'], zenMaru);
  });
}

class TyphoonShipTrackerApp extends StatelessWidget {
  const TyphoonShipTrackerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Typhoon & ship tracker',
      theme: ThemeData(
        colorSchemeSeed: Colors.blueGrey,
        useMaterial3: true,
        // App-wide font (2026-08-04 request): Japanese text in Zen Maru
        // Gothic, alphanumeric text in Comic Mono — both bundled as assets
        // (pubspec.yaml's `fonts:` section) rather than fetched from Google
        // Fonts at runtime, matching this app's offline-first design (see
        // CLAUDE.md's "船上でのオフライン利用を前提"). Achieved with a
        // single fontFamily + fontFamilyFallback pair rather than tagging
        // every individual Text widget by language: Comic Mono (an ASCII-
        // focused monospace font) has no Japanese glyphs, so Flutter's text
        // shaper automatically falls back to Zen Maru Gothic character-by-
        // character for any Japanese text — e.g. a single string mixing
        // "Typhoon 1" and "台風１" renders each part in the right font
        // without any manual splitting. Setting this once here on ThemeData
        // applies everywhere by default (AppBar titles, dialogs, this app's
        // many inline TextStyle overrides that don't set their own
        // fontFamily, etc.) — a TextStyle that explicitly sets its own
        // fontFamily still overrides this, as intended for the one existing
        // exception: map_screen.dart's JTWC warning-text paste box uses
        // fontFamily: 'monospace' deliberately (fixed-width alignment for
        // reading raw pasted warning text), which stays as-is. Canvas-drawn
        // map labels (widgets/map_painter.dart) don't inherit this Theme at
        // all — see utils/app_fonts.dart's doc comment, which this and
        // that file both reference for the same two values.
        fontFamily: kLabelFontFamily,
        fontFamilyFallback: kLabelFontFamilyFallback,
      ),
      home: const MapScreen(),
    );
  }
}
