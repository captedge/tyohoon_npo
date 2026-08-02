import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'screens/map_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
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

class TyphoonShipTrackerApp extends StatelessWidget {
  const TyphoonShipTrackerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Typhoon & ship tracker',
      theme: ThemeData(colorSchemeSeed: Colors.blueGrey, useMaterial3: true),
      home: const MapScreen(),
    );
  }
}
