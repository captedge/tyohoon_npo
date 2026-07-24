import 'package:flutter/material.dart';

import 'screens/map_screen.dart';

void main() {
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
