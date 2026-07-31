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

- **MVP順序**：デスクトップアプリから着手し、後にスマホへ展開する。
- **台風データソース**：気象庁の「防災情報XML」とJTWC（米軍）テキストは、フォールバック関係ではなく**両方を同時に独立表示**する設計（2026-07-28確定）。台風スロットごとにJTWC/JMA双方をDisplay ON/OFF・色分け（JTWC=赤／JMA=オレンジ）・Range Ringもソース別に独立ON/OFF可能。WNIは有料APIのため不採用、手動グリッド読み取りも誤差が大きく不採用（判断根拠は`docs/devlog-map-design.md`参照）。**取得方式**：JMA・JTWCとも「Import from JMA/JTWC」ボタンによる手動トリガー方式（自動定期取得は個人利用のデータ消費量への配慮から見送り）。取得結果はオフラインキャッシュ済み（次回起動時も再パースして復元）。複数台風が同時発表されている場合は「Import All (JMA/JTWC)」で見つかった数だけTyphoon 1〜3に一括反映可能（個別Importボタンも維持）。実装の経緯・詳細は`docs/completed-log.md`の該当日付エントリ参照。
- **オンライン/オフライン方針**：常時オンラインには依存しない。Wi-Fi接続時（出港前・寄港中）にJMA防災情報XML＋JTWCテキストをまとめて取得してキャッシュし、船上ではキャッシュデータをオフラインで利用するハイブリッド方式。
- **航海計画データ**：JRC ECDIS純正のルートCSVを、AppBarの船アイコンメニュー「Passage Plan」からインポート可能（2026-07-30実装済み）。パーサー・出発日時入力・WP追加/削除・区間速力編集は`VoyagePlanScreen`（`lib/screens/voyage_plan_screen.dart`）で実装済み。緯度経度の表示・入力は度分形式「DD-MM.MM」（N/S・E/Wは付けない、2026-07-31変更。地図画面のカーソル表示と共通の変換ロジックを`lib/utils/deg_min_format.dart`に集約）。列構成・時刻計算ロジックは`docs/data-format-notes.md`参照。**最大10件のCSVを登録・個別にEdit/Delete/Display ON/OFF可能（2026-08-xx実装済み）**：Display ONの各プランは連結せず、それぞれ独立したルートとして地図上に同時表示（同一出発港・同時刻からの複数ルート比較用途、`lib/widgets/map_painter.dart`の`ShipMarker`）。各ルートは10色パレットで自動色分け（色コード・経緯は`docs/devlog-passage-plan-multi.md`参照）。未登録時は何も表示しない（サンプルデータのフォールバックは2026-07-27に廃止、船・台風どちらの実データも無い場合は再生バー自体も非表示）。**CSVライブラリ機能（2026-07-27実装済み）**：Passage Planダイアログは「Import CSV／Select CSV／Edit CSV」の3段構成。取り込んだCSVはアプリ内（`path_provider`の application support ディレクトリ配下、上限50件）に蓄積され、Select CSVから再登録可能。Edit CSVでRename・Delete（Deleteは登録済みPassage Planがあれば英語で確認、道連れ削除）。設計判断は`docs/devlog-csv-library.md`参照。
- **時刻の扱い**：台風・船それぞれ独立に、直前後2点間で線形補間する。再生ボタン／スライダーで任意時刻を選択すると、その時刻の台風位置・船位置・両者間の距離を算出・表示する。再生バーの終点（上限時間）は「台風の最終予報時または航海計画の最終WP到着時刻のうち遅いほう」（2026-07-31変更。従来は航海終了時点のみだったが、台風の予報期間の方が長い場合もそこまで再生できるよう変更。どちらか短い方の情報は自身の最終点位置に留まったまま表示される）。
- **距離計算**：中分緯度法（Mid-Latitude Sailing）で海里表示。対象範囲が限定的（北海道〜フィリピン）なため大圏距離（Haversine）は不要と判断。
- **地図表示**：簡易プロット版（緯度経度グリッド＋海岸線をCustomPainterで自前描画、本物の地図タイルは使わない）。表示範囲は北緯5°〜50°・東経85°〜170°に固定（東西のみ東経115°〜150°から拡張・微調整、2026-07-25。北緯5°〜50°は変更なし。経緯は`docs/completed-log.md`・`docs/devlog-map-design.md`参照）。緯度・経度どちらもグリッド上に表示し、ラベルはズーム/パンしても画面端に追従表示（`docs/devlog-map-overlays.md`参照）。投影法はWeb Mercator（形の歪み防止、表示比率は固定）、起動時は日本付近（北緯30°・東経135°）を中心に表示。海岸線データはNaturalEarth 1:50mで確定（配色はナビチャート風の淡い青の海／ベージュの陸、ユーザー確認済み、`docs/devlog-map-design.md`参照）。東経85°〜170°への再クリップも同じ1:50mソース・手法（`typhoon_ship_tracker/assets/coastline/README.md`参照）。
- **船・台風の軌跡表示**：通過済み区間は実線、予定区間は点線（境界は現在時刻の補間点、2026-08-03確定）。船・台風アイコンは`assets/ship_icon01.png`／`typhoon_icon01.png`の実画像（2026-07-27差替え、船は左右中央・下から15%を座標にアンカー、台風は画像中心。詳細`docs/completed-log.md`参照）。各アイコン・ラベル・WPドット・線の太さ・点線パターンは、地図をズームしても画面上で常に一定の見た目になるよう`MapPainter`が`zoom`を受け取り補正する設計（実装方法・往復の教訓は`docs/devlog-map-zoom-rendering.md`参照）。
- **地図UI**：ズームはピンチ/ホイール＋＋／－ボタン＋スライダー、下限は3者で統一済み（詳細`docs/devlog-wheel-zoom.md`）。表示は英語表記。再生バーはWindy風（日付・時刻、速度1〜100%調整可、2026-07-27に25〜150%から変更）、Play Sp'dボタンは再生バー内の再生ボタン直上に配置（2026-07-27、AppBarから移動）。カーソル緯度経度・船アイコン向きは`docs/devlog-map-overlays.md`、距離表示（船の後方追従）は`docs/completed-log.md`参照。
- **メニュー構成（2026-07-31改称・再配置）**：AppBarは左から「Passage Plan」（船アイコン）「Forecast」（旧称「Information」、鉛筆アイコン）の2つのみ。Ship's Nameは「Information」から「Passage Plan」ダイアログ上部（プラン一覧より上）に移動済み。Range Ring（旧称「100/200nm rings」）はAppBarの独立メニューを廃止し、「Forecast」内の台風スロットごと・ソース（JTWC/JMA）ごとにチェックボックスでOn/Off（起動時デフォルトOn、2026-07-27確定の挙動は維持）。地図上のアイコンクリックによるOn/Off切替は従来通り。
- **船・台風のラベル**：船の進行方向の後方（distance表示と同じ「behind」方向）に、Display ON中の全ルートで共通のラベルとして常時表示（2026-07-29確定。同一船・複数ルート比較という設計のため全ルートで同じ名前を表示、未入力時は非表示）。Passage Plan各プランの名前は地図上のラベルとしては表示せず（2026-07-29変更）、代わりに画面左上固定（ズームしても同じ大きさ）の凡例ボックス（タイトル「Passage Plan」＋プラン名を色分け＋色見本線、プラン数に応じて縦に伸びる）に表示。台風側も同様の凡例ボックスを画面右上（緯度経度ラベル・ズームバーと干渉しない位置）に表示（タイトル「Typhoon」、2026-07-31追加）。台風はJTWC警報テキスト貼り付けで番号・名称・気圧・位置・予報点を自動抽出（抽出仕様は`docs/data-format-notes.md`参照。「TYPHOON」以外の発達段階＝TROPICAL STORM/DEPRESSION等も認識、2026-07-27拡大）、最大3つ登録可、船・台風とも個別にDisplay ON/OFF（起動時デフォルトはShip・Typhoon 1のみOn、Typhoon 2/3はOff、2026-07-27確定）。台風の軌跡上の各点には有効時刻（dd/HH、JST）ラベルを表示（2026-07-27追加）。再生開始時刻はTyphoon 1の発表時間（JST変換、月またぎでも正しく解決するようissuedAtJstを2026-07-27修正）。
- **船・台風アイコン及び軌跡の色**：デフォルトは自動色分け（船は10色パレット、台風はJTWC＝赤／JMA＝オレンジ）のまま変更なし。手動での色選択が可能：船は「Passage Plan」の「Edit CSV」（`VoyagePlanEntry.colorOverride`）、台風は「Forecast」内の各台風スロット（`jtwcColorOverride`/`jmaColorOverride`）で、それぞれ用意されたカラーパレットから選択できる（2026-07-31確認）。
- **登録情報の永続化**：船名・Passage Plan（複数CSV登録内容）・台風情報（JTWC貼り付けテキスト）・UI設定（Display/Range Ring/再生速度）は、次回起動時に自動で読み込まれる（2026-07-27実装済み）。`shared_preferences`でJSON化して保存（`lib/utils/app_state_storage.dart`）、入力変更のたびに自動保存。地図の位置・ズームや再生スライダーの現在位置は対象外（毎回リセットされる仕様）。
- **配布**：`build_release.bat`（プロジェクトルート）で`flutter build windows --release`＋ポータブルZip（`TyphoonShipTracker.zip`）作成が可能（2026-07-27追加）。展開してexeを起動するだけで動作し、受け取り側にFlutter SDKは不要。
- **今後の開発方針（仮・2026-07-28合意、変更可能性あり）**：オンライン化・スマホ対応とも同一プロジェクト・同一`main`ブランチで進め、複数の完成形を並行維持する運用は取らない。進める順序は①オンライン化→②モバイル対応。スマホ版UIはデスクトップ版と機能・デザインを極力共通化し横向き固定とする。**ブランチ運用は②モバイル対応（`feature/mobile`）着手時から適用し、①オンライン化はブランチを切らずmain上で直接進める（2026-07-29見直し、経緯は`docs/devlog-architecture-roadmap.md`参照）**。
- **オンライン化フェーズ①のスコープ（2026-07-29確定）**：JMA自動取得は定期バックグラウンド取得は行わず、既存の「Fetch from JMA」手動ボタンのままとする（個人利用でのデータ消費量への配慮）。代わりに、取得結果の永続化キャッシュ（アプリ再起動後もオフラインで直近の取得結果を表示できるようにする）を実装する。
- **地方海上予報（VPCY51）は不採用・全削除済み（2026-07-31）**：2026-07-30に本番実装まで進めていたが、ユーザーの仕様変更依頼「JMAの地方海上予報（波高）は不要なので全てから削除する」を受けて撤去。`lib/utils/marine_areas.dart`／`marine_area_codes.dart`／`jma_marine_xml_parser.dart`／`jma_marine_feed_fetcher.dart`・`MapPainter`の区域塗り分け描画・Informationダイアログの該当セクション・`AppStateStorage`の永続化フィールドは、いずれも本セッション開始時点で既にコード上から削除済み（未コミットの変更として撤去されていたと見られる）だったことを確認。孤立していた`assets/marine_areas/`一式と`pubspec.yaml`の該当行のみ本セッションで追加削除（2026-07-31）。海上気象データは②Open-Meteo波の場（個人用、下記）のみが残る。
- **git運用**：`git init`実行、`user.name`/`user.email`をグローバル設定済み（`Capt.Edge` / `captain.edge.management@gmail.com`）、リモート`https://github.com/captedge/tyohoon_npo.git`を`origin`として追加済み（2026-07-25）。直近のpush：2026-07-30、`main`ブランチ、commit `40b18e5`（Open-Meteo波の場オーバーレイ：取得範囲のビューポート方式化・グリッド密度改善・HTTP 414対策のバッチ分割）。詳細は `docs/operation-rules.md` のgit運用ルールに従う（commit/pushはユーザーが「コミットして」と発言したときのみ、`commit.bat`経由）。

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
