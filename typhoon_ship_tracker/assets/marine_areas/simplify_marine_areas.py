"""Regenerates marine_areas.json from the 48 raw per-area GeoJSON files
downloaded by download_marine_areas.ps1.

Not run automatically by anything (Dart/Flutter never calls this) — this is
a one-off/occasional data-prep script, kept here for reproducibility in case
the source boundaries are ever updated. See README.md for when/why this was
last run (2026-07-29) and the resulting stats.

Usage (after running download_marine_areas.ps1 in this same folder):
    pip install shapely
    python simplify_marine_areas.py

Requires: shapely (not a project/Flutter dependency — install separately,
this script is never bundled into the app or run by it).
"""

import glob
import json

from shapely.geometry import Polygon, box, shape

# Matches MapBounds (lib/utils/map_bounds.dart): N5-50, E85-170.
BBOX = box(85, 5, 170, 50)

# Coarser than coastline.json's 0.01 degree tolerance (see
# assets/coastline/README.md) since this layer is a colour wash under the
# coastline layer, not a precise land/sea boundary in its own right —
# raw area boundaries follow the coastline in very high detail (some areas
# had >1,000,000 points before simplification), which isn't needed here.
TOLERANCE = 0.02


def main():
    result = {}
    for path in sorted(glob.glob("*.geojson")):
        code = path.replace(".geojson", "")
        data = json.load(open(path, encoding="utf-8"))
        rings_out = []
        for feature in data["features"]:
            geom = shape(feature["geometry"])
            polys = (
                list(geom.geoms)
                if geom.geom_type == "MultiPolygon"
                else [geom] if geom.geom_type == "Polygon" else []
            )
            for polygon in polys:
                simplified = polygon.simplify(TOLERANCE, preserve_topology=True)
                # Exterior ring only — interior rings (holes, e.g. small
                # islands within a sea area) are dropped, same convention as
                # coastline.json: the coastline layer is drawn on top of this
                # one, so a hole here wouldn't be visible as land anyway.
                exterior_only = (
                    Polygon(simplified.exterior)
                    if simplified.geom_type == "Polygon"
                    else None
                )
                if exterior_only is None or exterior_only.is_empty:
                    continue
                clipped = exterior_only.intersection(BBOX)
                clipped_polys = (
                    list(clipped.geoms)
                    if clipped.geom_type == "MultiPolygon"
                    else [clipped] if clipped.geom_type == "Polygon" else []
                )
                for cp in clipped_polys:
                    if cp.is_empty or len(cp.exterior.coords) < 4:
                        continue
                    ring = [[round(x, 3), round(y, 3)] for x, y in cp.exterior.coords]
                    rings_out.append(ring)
        result[code] = rings_out
        print(f"{code}: {len(rings_out)} rings")

    with open("marine_areas.json", "w", encoding="utf-8") as out:
        json.dump(result, out, separators=(",", ":"))

    total_rings = sum(len(v) for v in result.values())
    total_pts = sum(len(r) for v in result.values() for r in v)
    print(f"\n{len(result)} areas, {total_rings} rings, {total_pts} points total")


if __name__ == "__main__":
    main()
