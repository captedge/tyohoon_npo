# coastline assets

`coastline.json` — coastline polygons for the fixed map area (`MapBounds`:
N5-50, E115-150), generated 2026-07-26.

## Source and generation

- Source data: [Natural Earth](https://www.naturalearthdata.com/) 1:110m
  land data (public domain), via the `world-atlas` npm package's
  `land-110m.json` (TopoJSON).
- Processing (done once, outside the Flutter project, using Python +
  shapely): decode TopoJSON arcs to polygons, clip to the map's bounding
  box, simplify (tolerance 0.02 degrees) to keep the file small and fast to
  parse, round coordinates to 3 decimal places.
- Result: 14 polygons, ~300 points total, ~5KB.

## Format

A plain JSON array (not full GeoJSON) — simpler to parse in Dart without a
GeoJSON library:

```json
[
  [[lon, lat], [lon, lat], ...],  // polygon 1 (closed ring)
  [[lon, lat], [lon, lat], ...],  // polygon 2
  ...
]
```

Loaded by `lib/utils/coastline.dart` (`CoastlineData.load()`) and drawn by
`lib/widgets/map_painter.dart` (`_drawCoastline`).

## Known limitations

- 1:110m resolution is coarse (suited to whole-world maps) — coastlines are
  recognizable but not detailed. Natural Earth's finer 1:50m/1:10m data
  would look better but could not be fetched in one piece in this session
  (file too large for the fetch tool available at the time); worth
  revisiting if a future session has a way to download it directly.
- No political borders, rivers, or place names — land/no-land only.
- Land/sea colors are placeholders pending the color discussion in
  `TASKS.md`.
