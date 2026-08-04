# CLAUDE.md — 台風進路・船位置プロジェクト

## プロジェクト概要

日本近海で発生した台風の予想進路（気象庁の防災情報XMLと米軍JTWCテキストを両方独立表示）と、船の航海計画（CSV/Excel）を地図上に表示し、任意時刻における台風・船の位置と距離（海里）を算出・表示するデスクトップ＋スマホアプリ（Flutter、非Webアプリ）。デスクトップから着手し、後にスマホへ展開する。船上でのオフライン利用を前提とし、Wi-Fi接続時にまとめて取得したデータをキャッシュして使う設計。

## 本プロジェクトの基本ルール

本プロジェクトは `docs/project-declarations.md` の5つの宣言（①確認の自動化／②記録の4分割／③レビュー分離／④繰り返し検知／⑤コスト意識）に基づいて運用する。詳細・背景はそちらを参照し、このファイルには要約のみを置く。運用ルールの詳細（記録ルール・完了報告前チェック等）は `docs/operation-rules.md` を参照。

## 環境構成

- **技術スタック**：Flutter（デスクトップアプリ優先、後にAndroid/iOSへ展開。Webアプリではない）
- **Flutterプロジェクトのパス**：`typhoon_ship_tracker/`（このフォルダ直下。英数字・アンダースコアのみのサブフォルダ名とし、日本語・アポストロフィを含む祖先パスの問題を回避する。過去プロジェクトの教訓は `docs/project-setup-lessons.md` 参照）
- **セッション構成**：単一セッション（このCoworkセッション）で進行管理とコーディングの両方を担当する。Blenderプロジェクトのような複数セッション分業は行わない（Flutterのコードはテキストファイルであり、専用GUIアプリの操作が不要なため）。
- **ビルド・実機/エミュレータでの動作確認**：Coworkのサンドボックスは Linux のため、Windows/Android向けのFlutterビルド実行はできない。実装が一区切りついたら、ユーザーのWindows機でのビルド・動作確認を依頼する。
- **プロジェクト雛形の現状（2026-07-27更新）**：`pubspec.yaml`／`lib/`／`windows/`（プラットフォーム雛形、ユーザーが`flutter create --platforms=windows .`で生成済み）が揃い、Windows実機で`flutter run -d windows`が動作する状態。起動は`run_windows.bat`（プロジェクトルート、ダブルクリック）を使う。
- **このWindows機のFlutter環境・既知の癖**：`docs/flutter-windows-env-notes.md` に集約（Flutter SDK/Android SDKのパス、AVD名、`flutter analyze`がクラッシュする既知の問題、`.bat`納品時の注意、git操作はcommit.bat経由等）。技術的なつまずきが起きたら着手前に必ずこのファイルを確認する。

## 現状の要約（今後の判断に必要な最重要事項のみ）

**索引（詳細の置き場所）**：データソース選定・地図表示・距離計算の経緯・却下案＝`docs/devlog-map-design.md`／地図オーバーレイ（グリッド追従・カーソル座標・船向き）＝`docs/devlog-map-overlays.md`／ズーム時の描画固定＝`docs/devlog-map-zoom-rendering.md`／ホイールズーム不具合＝`docs/devlog-wheel-zoom.md`／Passage Plan複数CSV対応＝`docs/devlog-passage-plan-multi.md`／CSVライブラリ＝`docs/devlog-csv-library.md`／オンライン化・海上気象データ検討＝`docs/devlog-online-xml.md`／今後の開発方針＝`docs/devlog-architecture-roadmap.md`／2026-07-31のUI微調整・波の場設計・AppBar構成の詳細＝`docs/devlog-2026-07-31-ui-polish-and-wave-field-design.md`／再生位置リセットバグ＝`docs/devlog-playback-anchor-reset.md`／保存先のexe相対Data化＝`docs/devlog-portable-data-dir.md`／外部データ形式（JMA/JTWC/CSV）＝`docs/data-format-notes.md`／実装ごとの完了記録＝`docs/completed-log.md`／モバイル対応（Android先行）着手経緯＝`docs/devlog-mobile-flutter.md`／アプリアイコンのデザイン検討＝`docs/devlog-app-icon-design.md`／JMA自動取得が予報無し暫定電文を掴むバグ＝`docs/devlog-jma-forecast-missing-bulletin.md`。

- **MVP順序**：デスクトップアプリから着手し、後にスマホへ展開する。
- **台風データソース**：JMA防災情報XMLとJTWC（米軍）テキストを、フォールバックではなく両方同時・独立表示（2026-07-28確定、台風スロットごとにDisplay/色/Range Ringを両ソース独立設定可）。取得は両ソースとも「Import」ボタンの手動トリガー方式でオフラインキャッシュ、複数台風同時発表時は「Import All」で一括反映可。WNI（有料API）・手動グリッド読み取りは却下。詳細は`docs/devlog-map-design.md`・`docs/completed-log.md`参照。**JMA自動取得は「最新電文」を無条件採用せず、予報が無い場合は同一台風のより新しい予報付き電文を遡って優先する**（2026-08-04、実況専用の暫定電文を掴むバグ対応、`docs/devlog-jma-forecast-missing-bulletin.md`参照）。JTWC自動取得はTCFA（番号未確定のINVEST）を除外（2026-08-03）。
- **オンライン/オフライン方針**：Wi-Fi接続時にJMA＋JTWCをまとめて取得しキャッシュ、船上ではオフラインで利用するハイブリッド方式（`docs/devlog-map-design.md`参照）。
- **航海計画データ**：JRC ECDIS純正ルートCSVを「Passage Plan」からインポート（`VoyagePlanScreen`）、緯度経度は度分形式「DD-MM.MM」（`lib/utils/deg_min_format.dart`）。最大10件を登録し個別Edit/Delete/Display可能、Display ON分は連結せず独立ルートとして同時表示（10色パレット自動色分け）。CSVはアプリ内ライブラリ（上限50件、Import/Select/Edit CSVの3段構成）に蓄積。列構成は`docs/data-format-notes.md`、複数CSV設計は`docs/devlog-passage-plan-multi.md`、CSVライブラリは`docs/devlog-csv-library.md`参照。
- **時刻の扱い**：台風・船それぞれ独立に前後2点間で線形補間し、再生バーで任意時刻の位置・距離を表示。再生バー終点は「台風の最終予報時または航海計画の最終WP到着時刻のうち遅いほう」（2026-07-31変更、詳細`docs/devlog-2026-07-31-ui-polish-and-wave-field-design.md`）。
- **距離計算**：中分緯度法（対象範囲が限定的なため大圏距離は不要と判断、`docs/devlog-map-design.md`参照）。
- **地図表示**：簡易プロット版（CustomPainter自前描画、地図タイルは使わない）。表示範囲は北緯5°〜50°・東経85°〜170°固定、Web Mercator投影、起動時は日本付近（N30/E135）中心。海岸線データはNatural Earth 1:50m確定。経緯・却下案は`docs/devlog-map-design.md`、グリッドラベル追従等は`docs/devlog-map-overlays.md`参照。
- **船・台風の軌跡表示**：通過済みは実線・予定は点線（境界は現在時刻の補間点、2026-08-03確定）。台風アイコンは`typhoon_icon01.png`、船アイコンは`ship_01`〜`10.png`（10色パレット対応、2026-07-31差替え）。全要素がズームしても画面上一定サイズ（`MapPainter`の`zoom`補正）。詳細・数値根拠は`docs/devlog-map-zoom-rendering.md`・`docs/devlog-2026-07-31-ui-polish-and-wave-field-design.md`、実装記録は`docs/completed-log.md`参照。
- **地図UI**：ズームはピンチ/ホイール＋＋／－ボタン＋スライダー（下限統一済み、`docs/devlog-wheel-zoom.md`）。表示は英語表記（例外：Aboutダイアログの「Typhoon positions and forecasts...」注記・Disclaimerの2箇所のみ、主な利用者が日本近海の日本人船長と想定されるため2026-08-04に英日併記化、`lib/screens/map_screen.dart`の`_showAboutDialog`参照）。再生バーはWindy風、速度1〜100%調整可。カーソル緯度経度・船アイコン向きは`docs/devlog-map-overlays.md`参照。
- **メニュー構成**（2026-08-04更新）：AppBarは「Passage Plan」「Forecast」「About」の3つ（2026-07-31時点は2つ固定の方針だったが、本流公開準備でAboutを追加し方針変更、`docs/release-checklist.md`参照）。Range Ringは「Forecast」内で台風スロット・ソースごとにOn/Off。詳細（アイコン種別・Ship's Name移動先等）は`docs/devlog-2026-07-31-ui-polish-and-wave-field-design.md`参照。
- **船・台風のラベル**：船名は進行方向後方に常時表示、Passage Plan名・台風情報は画面左上／右上の固定凡例ボックスに表示（2026-07-29〜31確定）。台風はJTWC警報テキスト貼り付けで番号・名称・気圧・位置・予報点を自動抽出（TYPHOON以外の発達段階も認識）、最大3つ登録可（起動時デフォルトはShip・Typhoon 1のみOn）。詳細は`docs/data-format-notes.md`・`docs/completed-log.md`参照。
- **船・台風アイコン及び軌跡の色**：デフォルトは自動色分け（船10色パレット、台風JTWC＝赤／JMA＝オレンジ）。手動色選択も可能（船：Passage Plan「Edit CSV」の`colorOverride`、台風：Forecast内の`jtwcColorOverride`/`jmaColorOverride`、2026-07-31確認、詳細`docs/devlog-2026-07-31-ui-polish-and-wave-field-design.md`）。
- **アプリアイコン**：4案の反復フィードバックを経て船＋台風マークのベタ塗りシルエット構図に確定後、姉妹アプリ「Ship's Time」に合わせ背景`#0D3B3E`・船を真鍮色＋クリーム輪郭線に配色変更した`assets/app_icon_05.png`で確定、2026-08-02にWindows/Androidの両アイコンファイルへ実装済み（Android実機確認済み・視認性は問題なし、Windows未確認、枠に対するスケール調整の要望あり）。経緯は`docs/devlog-app-icon-design.md`参照。
- **登録情報の永続化**：船名・Passage Plan・台風情報・UI設定はJSON永続化し次回起動時に自動復元（2026-07-27実装、`lib/utils/app_state_storage.dart`）。**保存先はWindowsではexe相対の`UserData`フォルダ（ポータブルzip内、2026-08-01変更）**：以前はOSのper-user AppDataフォルダで、zipフォルダをコピーしても別デバイスに引き継がれなかったため変更。CSVライブラリ・波の場キャッシュも同様（`lib/utils/portable_storage_dir.dart`）。当初フォルダ名を`Data`にしていたところFlutter自身の必須フォルダ`data`とWindowsの大文字小文字非区別で衝突し起動不能になる不具合が発生、`UserData`に改名して解消（教訓含め`docs/devlog-portable-data-dir.md`参照）。トレードオフ（`flutter clean`で消える、Debug/Releaseで別データ）・旧保存先からの移行処理も同ファイル参照。地図位置・ズーム・再生位置は対象外。
- **配布**：`build_release.bat`で`flutter build windows --release`＋ポータブルZip作成（2026-07-27追加）。Flutter SDK不要で起動可能。
- **今後の開発方針**（仮・2026-07-28合意）：オンライン化→モバイル対応の順で同一プロジェクト・`main`ブランチで進める。ブランチ運用は②モバイル対応着手時から適用。詳細・判断基準は`docs/devlog-architecture-roadmap.md`参照。
- **モバイル対応（Android先行）**（2026-08-02）：機能・デザインはデスクトップ版と共通、横向き固定、画面サイズ差分とタッチ操作のみ個別調整する方針。`android/`雛形生成済み、コア機能・モバイル専用UI一式（全画面地図・ダブルタップでのメニュー表示・凡例位置等）・長押しクロスヘアでの緯度経度表示（トラックパッド式相対移動、2本指ピンチと競合なし）を実装し、実機テストをユーザーが完了（「モバイルもほぼ完了です」）。残りは`productFlavors`（本流／個人の別アプリ化）等一部確認項目のみ（`TASKS.md`参照）。`feature/mobile`ブランチ運用。詳細は`docs/devlog-mobile-flutter.md`参照。
- **オンライン化フェーズ①のスコープ**（2026-07-29確定）：JMA自動取得は手動ボタンのまま、取得結果の永続化キャッシュのみ実装。
- **地方海上予報（VPCY51）は不採用・全削除済み**（2026-07-31）：ユーザーの仕様変更依頼を受けて撤去。削除済みファイル一覧・確認経緯は`docs/devlog-2026-07-31-ui-polish-and-wave-field-design.md`参照。海上気象データはOpen-Meteo波の場（個人用）のみ残存。
- **git運用**：`git init`済み、リモート`origin`（`https://github.com/captedge/tyohoon_npo.git`、**公開リポジトリ**）追加済み（2026-07-25、詳細`docs/completed-log.md`）。commit/pushはユーザーが「コミットして」と発言した時のみ`commit.bat`経由（`docs/operation-rules.md`のgit運用ルールに従う）。**新しいビルド出力・保存先フォルダを追加する際は都度`.gitignore`除外を確認する**（2026-08-02、個人用ビルド生成物・UserDataが公開履歴に残っていた件で追加、`docs/operation-rules.md`参照）。**git履歴を書き換えるスクリプト（`cleanup_git_history.bat`等）を使う前は、未コミットの変更を必ず先にコミットする**（同日、この教訓自体を記録する編集が history rewrite で失われた実例あり）。

## セッション開始チェックリスト

1. このCLAUDE.mdを読む
2. `docs/project-declarations.md`（5つの宣言）を確認する
3. `docs/operation-rules.md`（運用ルール詳細）を確認する
4. `docs/flutter-windows-env-notes.md`（このWindows機のFlutter環境・既知の癖）を確認する
5. `TASKS.md` で進行中タスクを確認する
6. `docs/completed-log.md` で直近の完了項目を確認する

## セッション終了チェックリスト

1. `TASKS.md` を更新する（完了／新規タスクを反映）
2. 完了したタスクを `docs/completed-log.md` に記録する
3. 同じテーマで3往復以上のやり取りがあれば `docs/devlog-<テーマ名>.md` に退避したか確認する
4. このCLAUDE.mdが肥大化していないか自己チェックする（目安：150行 or 8,000文字。文字数は`wc -c`ではなくPythonの`len()`等、文字数ベースでカウントする——`wc -c`はバイト数でありUTF-8の日本語1文字は3バイトのため過大に出る。詳細は`docs/operation-rules.md`参照）
