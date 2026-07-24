import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

import 'interpolation.dart';

/// Coastline polygons for the fixed map area (MapBounds), loaded once from
/// a bundled asset.
///
/// Source: Natural Earth 1:50m land data (public domain), clipped to
/// MapBounds and simplified. See assets/coastline/README.md for how it was
/// generated. This is a real coastline, not the placeholder shapes that
/// used to be hard-coded in map_painter.dart.
class CoastlineData {
  final List<List<LatLng>> polygons;

  const CoastlineData(this.polygons);

  static const empty = CoastlineData([]);

  static Future<CoastlineData> load() async {
    final raw = await rootBundle.loadString('assets/coastline/coastline.json');
    final decoded = json.decode(raw) as List<dynamic>;
    final polygons = decoded.map((polygon) {
      return (polygon as List<dynamic>).map((point) {
        final p = point as List<dynamic>;
        final lon = (p[0] as num).toDouble();
        final lat = (p[1] as num).toDouble();
        return LatLng(lat, lon);
      }).toList();
    }).toList();
    return CoastlineData(polygons);
  }
}
