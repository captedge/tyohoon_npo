import 'dart:ui' as ui;

import 'package:flutter/services.dart' show rootBundle;

/// Loads a bundled PNG asset as a decoded [ui.Image] for drawing on a
/// [Canvas] with `drawImageRect` (2026-08-xx request: replace the
/// placeholder triangle/circle ship & typhoon markers with real icon
/// images). Mirrors the loading style of `CoastlineData.load()`
/// (lib/utils/coastline.dart) — load once, keep the decoded result around,
/// don't reload on every paint.
Future<ui.Image> loadUiImage(String assetPath) async {
  final data = await rootBundle.load(assetPath);
  final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
  final frame = await codec.getNextFrame();
  return frame.image;
}
