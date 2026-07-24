# coastline assets

`coastline.json` — coastline polygons for the fixed map area (`MapBounds`:
N5-50, E115-150), generated 2026-07-26, upgraded to 1:50m 2026-07-27.

## Source and generation

- Source data: [Natural Earth](https://www.naturalearthdata.com/) 1:50m
  land data (public domain), via the `world-atlas` npm package v1.1.4's
  `world/50m.json` (TopoJSON, `land` object), fetched directly from
  `registry.npmjs.org` (this host was reachable from the sandbox even
  though `naturalearthdata.com`/`raw.githubusercontent.com` were not —
  worth trying `registry.npmjs.org` first next time before asking the
  user to download data manually).
- Processing (done once, outside the Flutter project, using Python +
  shapely): decode TopoJSON arcs to polygons, filter to polygons whose
  bounding box could plausibly touch the map area, `union` them (fixing
  invalid geometries with `buffer(0)` first — the raw data has some
  self-intersections), clip to the map's bounding box, simplify (tolerance
  0.01 degrees, tighter than the previous 0.02 since the source detail
  supports it), round coordinates to 3 decimal places.
- Result: 123 polygons, ~3,000 points total, ~50KB (previously 14
  polygons/~300 points/~5KB at 1:110m).
- Visual check: rendered the clipped polygons with matplotlib before
  replacing the asset — Japan (incl. Kyushu/Shikoku), Korea, Taiwan, the
  Chinese coast, and the Philippine islands are all clearly recognizable,
  a large step up from the 1:110m version.

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

- 1:50m resolution is a solid mid-tier level of detail (islands and bays
  are recognizable) but still simplified compared to 1:10m. Natural
  Earth's 1:10m data is not bundled in the `world-atlas` npm package and
  was not attempted this session; revisit only if the user wants finer
  detail than this.
- No political borders, rivers, or place names — land/no-land only.
- Land/sea colors are placeholders pending the color discussion in
  `TASKS.md`.
