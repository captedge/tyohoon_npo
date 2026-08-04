import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../utils/build_flags.dart';

/// "Help" screen (2026-08-04 addition, user request): explains on-screen
/// map operations (pan/zoom/playback/Range Ring) and each AppBar menu's
/// contents (Passage Plan/Forecast), since this app is meant to be used
/// offline by a ship captain with no one else around to ask. Opened from a
/// 4th AppBar icon (see `MapScreen._buildAppBar`), same "push a full
/// screen rather than a dialog" pattern `VoyagePlanScreen` uses — chosen
/// over a dialog because the eventual full content (all sections) is too
/// long to sit comfortably in a constrained-height AlertDialog the way
/// `_showAboutDialog`'s shorter content does.
///
/// Two axes of content variation, each resolved *automatically* rather
/// than asked of the user (2026-08-04 discussion — the user considered
/// separate Android/Windows manuals "面倒" (a hassle) to maintain; this
/// keeps to one shared content model with per-axis branches instead of a
/// user-facing PC/Mobile switch):
/// - **Language**: Japanese/English only, toggled by a button in this
///   screen's own AppBar. Defaults to Japanese — this screen's primary
///   audience is the same "Japanese captains navigating near Japan" group
///   `_showAboutDialog`'s two bilingual notices already target (see that
///   method's doc comment in map_screen.dart), unlike the rest of the
///   app's English-first UI (CLAUDE.md: "表示は英語表記"). Content is
///   written out in full per language rather than side-by-side, since the
///   amount of text here would make side-by-side translation unreadably
///   long (unlike the About dialog's two short notices).
/// - **Platform (PC vs Mobile)**: resolved via [_isMobileUi] below — the
///   same check `MapScreen._isMobileUi` uses (desktop mouse/keyboard
///   operations vs. mobile touch gestures genuinely differ, e.g.
///   pinch-zoom vs. mouse wheel, long-press-drag crosshair vs. hover).
///   Duplicated here as a private getter rather than importing
///   `MapScreen`'s private field — screens don't share private state
///   across files in this codebase, and this is a one-line check.
///
/// **Status (2026-08-04): all four sections (Map Basics, Playback Bar,
/// Passage Plan, Forecast) written in both Japanese and English.** Japanese
/// was written and iterated on first per user request ("まずは日本語で進めて
/// みてください" — verify content before translating something that might
/// still change), then English was added once the Japanese content was
/// confirmed correct against the actual dialog implementations.
class HelpScreen extends StatefulWidget {
  const HelpScreen({super.key});

  @override
  State<HelpScreen> createState() => _HelpScreenState();
}

class _HelpScreenState extends State<HelpScreen> {
  // Same definition as MapScreen._isMobileUi (map_screen.dart) — kept in
  // sync manually since it's a single line; see this file's doc comment.
  bool get _isMobileUi => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  bool _japanese = true;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        // Language toggle moved to the leading (top-left) slot, next to the
        // back arrow (2026-08-04 request: "左上に配置してください" — it
        // previously sat in `actions` on the right). Overriding `leading`
        // replaces Flutter's automatic back arrow, so it's rebuilt here
        // manually (`BackButton()`) alongside the toggle inside a Row —
        // `leadingWidth` is widened from the AppBar default (56, sized for
        // a single icon button) so both fit without clipping/overflowing.
        // 148 fit the 'EN' label (Japanese mode) but was a few pixels too
        // narrow once switched to English, where the label becomes '日本語'
        // (3 full-width characters, wider than 'EN') — this caused a debug-
        // only RenderFlex overflow (the yellow/black striped warning banner;
        // invisible in Release builds since overflow painting is asserts-
        // only) reported 2026-08-05. Widened to 172 to comfortably fit the
        // longer label in both language states.
        leadingWidth: 172,
        leading: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const BackButton(),
            // Language toggle — shows the *other* language's name, same
            // convention as a typical "EN / 日本語" language switcher (tap
            // to switch TO that language, not a label of the current one).
            // Outlined icon+label button (2026-08-04 fix: previously a
            // plain TextButton with a hardcoded white text color was easy
            // to miss — the user reported "日本語しかない、切り替えができ
            // るの？" — since this app's Material 3 AppBar (colorSchemeSeed:
            // Colors.blueGrey) defaults to a *light* background, so white
            // text had very low contrast). No hardcoded color — it inherits
            // the AppBar's own automatic (contrast-correct) foreground
            // color, the same way the plain-icon buttons on MapScreen's
            // AppBar do — and the translate icon plus visible outline make
            // it read as an obviously-tappable control rather than floating
            // text.
            OutlinedButton.icon(
              onPressed: () => setState(() => _japanese = !_japanese),
              icon: const Icon(Icons.translate, size: 18),
              label: Text(_japanese ? 'EN' : '日本語'),
            ),
          ],
        ),
        title: Text(_japanese ? '取扱説明' : 'Help'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _mapBasicsSection(),
          _sectionDivider(),
          _playbackSection(),
          _sectionDivider(),
          _passagePlanSection(),
          _sectionDivider(),
          _forecastSection(),
        ],
      ),
    );
  }

  Widget _sectionDivider() => const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Divider(height: 1),
      );

  Widget _sectionTitle(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(text, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
      );

  Widget _bulletRow(IconData icon, String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 18, color: Colors.black54),
            const SizedBox(width: 8),
            Expanded(child: Text(text, style: const TextStyle(fontSize: 14, height: 1.4))),
          ],
        ),
      );

  // First (and currently only) section: basic map operations — pan, zoom,
  // checking a position's lat/lon, and (mobile only) showing/hiding the
  // menu bar. Desktop and Mobile rows are written out separately in full
  // rather than derived from one shared template — the wording differs
  // enough (e.g. mobile's long-press-drag crosshair has no desktop
  // equivalent, desktop has no menu show/hide gesture at all since its
  // AppBar is always visible) that a shared template would need as many
  // branches as just writing both out plainly.
  Widget _mapBasicsSection() {
    final title = _japanese ? '地図の基本操作' : 'Map Basics';
    final rows = _isMobileUi ? _mapBasicsMobileRows() : _mapBasicsDesktopRows();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle(title),
        ...rows,
      ],
    );
  }

  List<Widget> _mapBasicsDesktopRows() {
    if (_japanese) {
      return [
        _bulletRow(Icons.open_with, '地図の移動：地図上を左クリックしたままドラッグ'),
        _bulletRow(Icons.zoom_in, 'ズーム：マウスホイール、画面上の＋／－ボタン、またはズームスライダー'),
        _bulletRow(Icons.my_location, 'カーソル位置の確認：地図上にカーソルを合わせると緯度経度が表示される'),
      ];
    }
    return [
      _bulletRow(Icons.open_with, 'Pan the map: click and drag anywhere on the map'),
      _bulletRow(Icons.zoom_in, 'Zoom: mouse wheel, the on-screen +/- buttons, or the zoom slider'),
      _bulletRow(Icons.my_location, 'Check a position: hover over the map to see its latitude/longitude'),
    ];
  }

  List<Widget> _mapBasicsMobileRows() {
    if (_japanese) {
      return [
        _bulletRow(Icons.open_with, '地図の移動：1本指でドラッグ'),
        _bulletRow(Icons.zoom_in, 'ズーム：2本指でピンチ（＋／－ボタン・ズームスライダーはモバイル版にはなし）'),
        _bulletRow(
          Icons.add_location_alt,
          '緯度経度の確認：地図を長押ししたままドラッグすると十字カーソルが表示され、その位置の緯度経度が確認できる'
          '（トラックパッドのような相対移動で、2本指のピンチ操作とは干渉しない）',
        ),
        _bulletRow(
          Icons.menu,
          'メニューバー・再生バーの表示／非表示：画面をダブルタップすると両方表示される。'
          '2秒以上何も操作しないと自動的に隠れる（表示中にバー内のボタン等を操作すれば、その'
          'たびに2秒延長される）',
        ),
      ];
    }
    return [
      _bulletRow(Icons.open_with, 'Pan the map: drag with one finger'),
      _bulletRow(Icons.zoom_in, 'Zoom: pinch with two fingers (no on-screen +/- buttons or zoom slider on mobile)'),
      _bulletRow(
        Icons.add_location_alt,
        'Check a position: long-press and drag to show a crosshair — this moves like a '
        'trackpad (relative movement) and does not interfere with two-finger pinch-zoom',
      ),
      _bulletRow(
        Icons.menu,
        'Show/hide the menu bar and playback bar: double-tap the screen to show both. '
        "They hide again automatically after 2 seconds of no interaction (tapping a "
        "button inside either bar resets that 2-second timer).",
      ),
    ];
  }

  // Second section: the Windy-style playback bar (map_screen.dart's
  // _buildPlaybackBar) — same on PC/Mobile (it's the same widget, only
  // shown/hidden differently — see the mobile double-tap note in Map
  // Basics above), so this section has no PC/Mobile branch, unlike Map
  // Basics.
  Widget _playbackSection() {
    if (!_japanese) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle('Playback Bar'),
          _bulletRow(Icons.play_circle_outline,
              'Play/Pause: the ▶ button. Starts advancing time — the typhoon and ship move to their interpolated position at the current time.'),
          _bulletRow(Icons.speed,
              'Adjust playback speed: tap the speed icon (above the ▶ button) to open a dialog for adjusting speed from 1-100%.'),
          _bulletRow(Icons.touch_app,
              'Jump to a specific time: tap or drag the bar (track) to jump directly to that time.'),
          _bulletRow(Icons.calendar_today,
              'Jump by date: tap a date divider along the bottom of the bar to jump to the start of that day.'),
          _bulletRow(
            Icons.info_outline,
            'The playback end (the right edge of the bar) is set automatically to whichever is '
            'later: the last registered typhoon forecast time, or the last Passage Plan arrival time.',
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('再生バー'),
        _bulletRow(Icons.play_circle_outline, '再生／一時停止：▶ボタン。押すと時間が進み、台風・船が現在時刻の補間位置に移動する'),
        _bulletRow(Icons.speed, '再生速度の調整：速度計アイコン（▶ボタンの上）をタップすると、1〜100%の範囲で速度を調整するダイアログが開く'),
        _bulletRow(Icons.touch_app, '時刻を直接指定：バー（トラック）をタップ、またはドラッグすると、その時刻に直接ジャンプする'),
        _bulletRow(Icons.calendar_today, '日付から指定：バー下段の日付区切りをタップすると、その日の開始時刻にジャンプする'),
        _bulletRow(
          Icons.info_outline,
          '再生の終点（バーの右端）は、登録されている台風予報の最終時刻と、Passage Planの最終到着時刻のうち'
          '遅い方に自動的に設定される',
        ),
      ],
    );
  }

  // Third section: the "Passage Plan" AppBar dialog (map_screen.dart's
  // _showPassagePlanDialog) — ship's name, the three-tier CSV workflow
  // (Import/Select/Edit CSV), and the registered-plan list's per-row
  // controls. Unlike Forecast below, every action in this dialog applies
  // immediately (no Save/Cancel gate), which is itself worth telling the
  // user explicitly since Forecast works differently.
  Widget _passagePlanSection() {
    if (!_japanese) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle('Passage Plan Menu'),
          _bulletRow(Icons.directions_boat,
              "Ship's Name: enter the ship's name. Reflected in the on-map label and the legend."),
          _bulletRow(Icons.upload_file,
              'Import CSV...: pick a CSV file on your computer/device (a JRC ECDIS-format route CSV), enter its departure time, and register it (up to 10 plans).'),
          _bulletRow(Icons.folder_open,
              "Select CSV...: register a plan from a CSV you've already imported before (stored in the CSV library below)."),
          _bulletRow(Icons.library_books,
              'Edit CSV...: manage the list of previously imported CSV files (up to 50). You can rename or delete files here.'),
          _bulletRow(
            Icons.warning_amber,
            'Warning: deleting a file with Edit CSV\'s Delete permanently removes it from the CSV '
            "library — this can't be undone. Even if a Passage Plan sourced from that file is "
            'currently shown on the map (Display On), deleting the file here removes that Passage '
            'Plan too, after a confirmation message.',
          ),
          _bulletRow(Icons.checklist,
              'Registered plan list: use the checkbox to toggle map display on/off, the pencil icon to edit waypoints/departure time/route color, and the trash icon to delete.'),
          _bulletRow(Icons.layers,
              'Plans with Display on are shown on the map at the same time, each as an independent route.'),
          _bulletRow(Icons.check_circle_outline,
              "Every action on this screen applies as soon as you tap it (there's no Save button — Close simply closes the screen)."),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('Passage Planメニュー'),
        _bulletRow(Icons.directions_boat, "Ship's Name：船名を入力。地図上のラベルや凡例に反映される"),
        _bulletRow(Icons.upload_file,
            'Import CSV...：パソコン/端末内のCSVファイル（JRC ECDIS形式のルートCSV）を選んで取り込み、出港日時を入力して登録する（最大10件まで）'),
        _bulletRow(Icons.folder_open, 'Select CSV...：一度取り込んだことのあるCSV（下記CSVライブラリに蓄積済みのもの）を選んで登録する'),
        _bulletRow(Icons.library_books,
            'Edit CSV...：これまでに取り込んだCSVファイル一覧（最大50件）の管理画面。ファイル名の変更（Rename）・削除（Delete）ができる'),
        _bulletRow(Icons.warning_amber,
            '注意：Edit CSVでのDeleteはCSVライブラリから完全に削除され、元に戻せない。地図に表示（Display On）して使用中のPassage Planであっても、その元になったCSVファイルをここで削除すると、確認メッセージの後にそのPassage Planごと消えてしまう'),
        _bulletRow(Icons.checklist,
            '登録済みプラン一覧：チェックボックスで地図表示のOn/Off、鉛筆アイコンでウェイポイント・出港日時・ルート色の編集、ゴミ箱アイコンで削除ができる'),
        _bulletRow(Icons.layers, '表示（Display）Onにしたプランは、それぞれ独立した航路として同時に地図上へ表示される'),
        _bulletRow(Icons.check_circle_outline, 'この画面内の操作はボタンを押した時点で即座に反映される（Saveボタンはなく、Closeで画面を閉じるのみ）'),
      ],
    );
  }

  // Fourth section: the "Forecast" AppBar dialog (map_screen.dart's
  // _showLabelSettingsDialog) — up to 3 typhoon slots, each with an
  // independent JMA/JTWC source. Explicitly calls out the Save/Cancel
  // gate (unlike Passage Plan) since Range Ring/track-color are the one
  // exception that *does* apply immediately even inside this dialog — a
  // real gotcha (forgetting to press Save loses an otherwise-successful
  // Import) worth stating plainly rather than leaving the user to
  // discover it.
  Widget _forecastSection() {
    if (!_japanese) {
      final rows = <Widget>[
        _sectionTitle('Forecast Menu'),
        _bulletRow(Icons.filter_3,
            'Up to 3 slots (Typhoon 1-3) can be registered. Each slot can independently Display On/Off and register JMA (Japan Meteorological Agency) and JTWC (U.S. Navy) — both can be shown at once.'),
        _bulletRow(Icons.cloud_download,
            "Import from JMA: automatically fetches the latest JMA disaster-prevention XML bulletin for that slot."),
        _bulletRow(
          Icons.cloud_download,
          "Import from JTWC: automatically fetches the U.S. Navy's warning text. If the automatic "
          'fetch doesn\'t work, you can instead paste the warning text (containing a "TYPHOON '
          '<number> (<name>)..." line) directly into the text box below.',
        ),
        _bulletRow(Icons.playlist_add_check,
            'Import All (JMA) / Import All (JTWC): fetches every typhoon currently active for that source at once, filling Typhoon 1-3.'),
        _bulletRow(
          Icons.radio_button_checked,
          'Range Ring checkbox and color swatches: apply as soon as you tap them (the Save button '
          "below isn't needed for these). Tapping a typhoon icon on the map also toggles that "
          "typhoon's Range Ring on/off (JTWC/JMA independently).",
        ),
        _bulletRow(
          Icons.save,
          "Note: everything else (Display On/Off, and the typhoon data actually fetched via Import/"
          'Import All) is not applied to the map until you press the "Save" button below (Cancel '
          'discards it).',
        ),
      ];
      if (kPersonalBuild) {
        rows.add(_bulletRow(Icons.waves,
            "Wave Field: fetches wave height for a fixed area from Open-Meteo and displays it color-coded. It isn't re-fetched when you pan/zoom the map — only when you press Import."));
        rows.add(_bulletRow(Icons.warning_amber,
            'Note: the data source (Open-Meteo) has an hourly fetch limit, so it is recommended to wait at least an hour between re-fetches using the Import button.'));
      }
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: rows);
    }
    final rows = <Widget>[
      _sectionTitle('Forecastメニュー'),
      _bulletRow(Icons.filter_3, 'Typhoon 1〜3として最大3個まで登録可能。各枠でJMA（気象庁）とJTWC（米軍）を独立してDisplay On/Off・登録できる（複数同時表示も可）'),
      _bulletRow(Icons.cloud_download, 'Import from JMA：その枠に対応する最新の気象庁 防災情報XMLを自動取得する'),
      _bulletRow(Icons.cloud_download,
          'Import from JTWC：米軍の警報テキストを自動取得する。うまく取得できない場合は、下のテキスト欄に警報文（"TYPHOON <番号> (<名称>)..."を含むもの）を直接貼り付けても登録できる'),
      _bulletRow(Icons.playlist_add_check,
          'Import All (JMA) / Import All (JTWC)：同時に発表されている複数の台風を、Typhoon 1〜3へ一括で取り込む'),
      _bulletRow(Icons.radio_button_checked,
          'Range Ringチェックボックス・色のスウォッチ：押した時点で即座に反映される（下記Saveボタンは不要）。地図上の台風アイコンをタップしても、その台風（JTWC/JMAそれぞれ独立）のRange RingのOn/Offができる'),
      _bulletRow(Icons.save,
          'それ以外の操作（Display On/Off、Import/Import Allで取り込んだ台風データ本体）は、画面下の「Save」ボタンを押すまで地図に反映されない点に注意（Cancelで取り消せる）'),
    ];
    if (kPersonalBuild) {
      rows.add(_bulletRow(Icons.waves,
          'Wave Field：固定エリアの波高をOpen-Meteoから取得して色分け表示する。地図のパン・ズームでは再取得されず、Importボタンを押した時だけ通信する'));
      rows.add(_bulletRow(Icons.warning_amber,
          '注意：データ取得元（Open-Meteo）には1時間あたりの取得回数上限があるため、Importボタンでの再取得は1時間以上間隔をあけることを推奨する'));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: rows);
  }
}
