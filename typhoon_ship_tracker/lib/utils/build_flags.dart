/// Personal-build compile-time feature flag.
///
/// See docs/devlog-online-xml.md "本流／個人の分岐方法（決定）" for the full
/// background. Summary: the app has two build "flavors" that share one
/// codebase and one `main` branch (no separate git branch) —
///   - **Mainline** (distributable): `run_windows.bat` / `build_release.bat`,
///     unchanged, this flag stays `false`.
///   - **Personal** (Capt.Edge's own use only, never redistributed):
///     `run_windows_personal.bat` / `build_release_personal.bat`, which pass
///     `--dart-define=PERSONAL_BUILD=true` to `flutter run`/`flutter build`.
///
/// [kPersonalBuild] gates any feature that must not ship in the
/// distributable mainline build — currently the Open-Meteo Marine Weather
/// API integration (open_meteo_marine_fetcher.dart and its UI). Why: Open-
/// Meteo's free tier is documented as limited to genuinely non-commercial,
/// personal use (see docs/devlog-online-xml.md "Open-Meteoとの比較" —
/// "無料でも広告表示があれば商用扱い"); Capt.Edge's own single-user use
/// qualifies, but an app built for wider distribution would not.
///
/// Because this is a `const` resolved at compile time (via
/// `bool.fromEnvironment`, the same mechanism Flutter's own `kDebugMode`
/// uses), an `if (kPersonalBuild)` branch is dead code the compiler can
/// (and does, under tree-shaking/AOT) eliminate entirely when the flag is
/// off — so a mainline build built via `build_release.bat` has none of the
/// gated code's behavior reachable at runtime, not just "present but
/// switched off". A *plain* `bool` (e.g. read from shared_preferences at
/// runtime) could not offer that same guarantee, which is why this feature
/// is gated by a build flag rather than an in-app settings toggle like the
/// JMA/JTWC fetch buttons.
const bool kPersonalBuild = bool.fromEnvironment('PERSONAL_BUILD');
