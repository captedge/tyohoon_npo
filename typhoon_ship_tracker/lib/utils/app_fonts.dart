/// Shared font-family constants (2026-08-04 addition, user request): the
/// app-wide fonts declared in `pubspec.yaml`'s `fonts:` section — Comic
/// Mono for alphanumeric text, with Zen Maru Gothic as the fallback font
/// for any Japanese characters Comic Mono has no glyphs for (see
/// `main.dart`'s `ThemeData` doc comment for the full rationale/mechanism).
///
/// `ThemeData.fontFamily`/`fontFamilyFallback` (set once in `main.dart`)
/// only applies to widget-tree `Text` — it has no effect on text drawn
/// directly on a `Canvas` via `TextPainter`/`TextStyle`, since a
/// `CustomPainter` (see `widgets/map_painter.dart`, which draws every
/// on-map label: ship names, typhoon pressure, Range Ring labels, "N nm"
/// distance boxes) has no `BuildContext`/`Theme` to inherit from. Those
/// call sites need these same two values applied explicitly to every
/// `TextStyle` they construct. Kept in one shared place, rather than the
/// font family name/fallback list being duplicated as string literals in
/// both `main.dart` and `map_painter.dart`, so the two can't silently
/// drift apart if the font ever changes.
const String kLabelFontFamily = 'Comic Mono';
const List<String> kLabelFontFamilyFallback = ['Zen Maru Gothic'];
