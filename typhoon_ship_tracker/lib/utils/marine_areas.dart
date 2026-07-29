import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

import 'interpolation.dart';
import 'marine_area_codes.dart';

/// Local-marine-forecast area (地方海上予報区) boundary polygons, keyed by
/// area code (e.g. "1000") — the same codes VPCY51's `Area/Code` uses (see
/// docs/data-format-notes.md "気象庁 防災情報XML（VPCY51、地方海上予報）").
/// Loaded once from a bundled asset, same pattern as [CoastlineData].
///
/// Source: NII Geoshape (CC BY 4.0), simplified/clipped to MapBounds and
/// combined into a single file. See assets/marine_areas/README.md for how
/// it was generated (tolerance, clipping, interior rings dropped — same
/// "exterior only" convention as coastline.json, since this layer is meant
/// to be drawn as a colour wash under the coastline layer, not as a precise
/// land/sea boundary in its own right).
class MarineAreaData {
  final Map<String, List<List<LatLng>>> areaPolygons;

  const MarineAreaData(this.areaPolygons);

  static const empty = MarineAreaData({});

  /// Polygons for [code], or an empty list if this code has no bundled
  /// boundary (shouldn't happen for any of the 48 known codes — see
  /// [marineAreaNames] — but callers dealing with a code parsed fresh out of
  /// a VPCY51 report should still treat an unknown code as "nothing to draw"
  /// rather than throwing, in case JMA adds/renumbers area codes in the
  /// future).
  List<List<LatLng>> forCode(String code) => areaPolygons[code] ?? const [];

  static Future<MarineAreaData> load() async {
    final raw = await rootBundle.loadString('assets/marine_areas/marine_areas.json');
    final decoded = json.decode(raw) as Map<String, dynamic>;
    final areaPolygons = decoded.map((code, rings) {
      final polygons = (rings as List<dynamic>).map((ring) {
        return (ring as List<dynamic>).map((point) {
          final p = point as List<dynamic>;
          final lon = (p[0] as num).toDouble();
          final lat = (p[1] as num).toDouble();
          return LatLng(lat, lon);
        }).toList();
      }).toList();
      return MapEntry(code, polygons);
    });

    // Consistency check referenced by marine_area_codes.dart's doc comment:
    // every code in the bundled asset should have a name, and vice versa.
    // A mismatch would mean the asset and the name list drifted apart (e.g.
    // marine_areas.json regenerated from an updated NII Geoshape source
    // without marine_area_codes.dart being updated to match) — worth
    // failing loudly on in debug builds rather than silently showing
    // unlabeled areas or dead name entries.
    assert(() {
      final assetOnly = areaPolygons.keys.toSet().difference(marineAreaNames.keys.toSet());
      final namesOnly = marineAreaNames.keys.toSet().difference(areaPolygons.keys.toSet());
      if (assetOnly.isNotEmpty || namesOnly.isNotEmpty) {
        throw StateError(
          'marine_areas.json と marineAreaNames の区域コードが一致しません。'
          'asset側のみ: $assetOnly / marineAreaNames側のみ: $namesOnly',
        );
      }
      return true;
    }());

    return MarineAreaData(areaPolygons);
  }
}
