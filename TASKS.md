# TASKS.md — 進行中・次にやること

宣言2（記録の4分割）の②を担当。**このファイルは「未着手・進行中のタスク」と「決定待ち・要確認事項」だけを置く。** 完了したタスクはチェックを付けた時点でここから除去し、`docs/completed-log.md`に1〜2行で記録する（詳細な経緯・技術的な学びがある場合は該当`docs/devlog-<テーマ>.md`へ）。仕様調査結果（CSV/XML形式など）のような「参照資料」は`docs/data-format-notes.md`に集約する。

## 未着手・進行中

- [ ] （Windows実機確認待ち）「Forecast」アイコンを台風の渦巻き（`Icons.cyclone`、Flutter標準Material Icons）に変更（2026-08-04実装）：`lib/screens/map_screen.dart`のAppBar。表示・視認性を確認する。
- [ ] （Windows実機確認待ち）Range Ringに300nmを追加＋配色変更＋線を太く＋ラベル黒に変更（2026-08-04実装）：`lib/widgets/map_painter.dart`の`_drawTyphoonRings`/`_drawRing`。300nmは100nm/200nmと同じ描画パターンで追加。色はユーザー指定により100nm＝深紅(`0xFFB71C1C`)・200nm＝濃いオレンジ(`0xFFE65100`)・300nm＝紫(`0xFF6A1B9A`)。線の太さは1.5px→2.2pxに変更、ラベル文字色はリング色→黒(`Colors.black`)固定に変更。Range RingチェックボックスをOnにした状態で3本のリング（100/200/300nm）が正しい半径・配色・太さ・黒文字ラベルで表示されることを確認する。
- [ ] （Windows実機確認待ち）台風アイコンの後ろに表示していた台風番号・名称ラベル（例："11W (NOUL)"）を削除（2026-08-04実装）：`lib/widgets/map_painter.dart`の`_drawTyphoonMarker`からラベル描画部分を削除、位置計算用の未使用関数`_typhoonBehindDirection`も削除。地図左上/右上固定の凡例ボックス側の台風名表示には影響なし（そちらは別経路で描画）。アイコンのみになり凡例ボックスと重複しないこと・地図が見やすくなったことを確認する。
- [ ] （Windows実機確認待ち）台風初期（読み込み時）の気圧表示の文字色を台風の色（JTWC赤/JMAオレンジ寄りの濃色）→黒に変更（2026-08-04実装）：`lib/widgets/map_painter.dart`の`_drawTyphoonMarker`内`pressureLabel`描画部分。トラック開始点に固定表示される気圧の文字が黒で見やすいか確認する。

- [ ] （Windows実機確認待ち）「Help」（取扱説明）画面：4章とも日本語版・英語版を実装完了（2026-08-04）。新規4つ目のAppBarアイコン（`Icons.help_outline`）から開く専用画面`lib/screens/help_screen.dart`。方針（ユーザー確認済み）：①配置＝独立した4つ目のAppBarアイコン、②対応言語＝日本語／英語のみ（画面右上のボタンで切替、デフォルト日本語）、③PC/Mobileの操作差分＝ユーザーに選ばせず`_isMobileUi`相当の判定で自動的に該当する方だけ表示。4章の内容：①地図の基本操作、②再生バー、③Passage Planメニュー、④Forecastメニュー（`_showPassagePlanDialog`/`_showLabelSettingsDialog`の実装を確認しながら執筆、ボタン名・挙動の実装との整合を確認済み）。日本語を先に執筆・ユーザー確認（複数回の文言修正を反映）した上で、確定した内容を英語に翻訳（2026-08-04、未使用になった`_translationPendingRow`プレースホルダーは削除済み）。日本語/EN切り替えボタンは右上→左上（AppBarの`leading`、戻る矢印の右隣）に移動済み（2026-08-04、`leadingWidth`でRow内に戻るボタンと並べて配置）。確認済み：括弧・引用符の対応、コメント除去後の括弧バランス（pythonでの機械チェック）。**2026-08-05追記・修正済み**：この左上配置後、英語表示時（ラベルが`'日本語'`になり`'EN'`より横幅が大きい）にRenderFlexオーバーフロー（Debug限定の黄黒斜め縞警告）が発生する不具合が発覚、`leadingWidth`を148→172に拡大して解消・ユーザーがWindows実機で確認済み（詳細`docs/devlog-help-screen-overflow-watermark.md`）。**残作業**：4章・日英とも実機で見た目とスクロールを確認する（切り替えボタンの左上配置・オーバーフロー自体は解消確認済みのため対象から除く）。
- [ ] （Windows実機確認待ち）アプリ全体のフォント変更（2026-08-04実装、地図上のラベルにも同日追加対応）：日本語＝Zen Maru Gothic・英数字＝Comic Mono（いずれも`assets/fonts/`に同梱済みのフォントファイルを使用、Google Fonts等のオンライン取得はしない）。`pubspec.yaml`に`fonts:`セクションを追加。フォント名は新設の`lib/utils/app_fonts.dart`（`kLabelFontFamily`/`kLabelFontFamilyFallback`）に一元化し、`lib/main.dart`のThemeData（通常のダイアログ・メニュー等、ウィジェットツリー全体に自動適用）と、`lib/widgets/map_painter.dart`のCustomPainterが直接Canvasに描画する船名・距離ラベル（"N nm"）・Range Ringラベル（100/200/300nm）・台風気圧ラベルの計7箇所のTextStyle（CustomPainterはThemeDataを継承しないため個別適用が必要だった）の両方から参照する形に統一。例外：JTWC警報文貼り付け欄（`map_screen.dart`）は元々`fontFamily: 'monospace'`を明示指定しており、この変更の対象外で意図通り。**残作業**：UI全体・地図上のラベル双方でフォントが実際に切り替わっているか（日本語＝Zen Maru Gothic・英数字＝Comic Mono）を見た目で確認する（`run_windows.bat`／`build_apk.bat`の起動確認・Open-Source Licensesへのフォントライセンス追記はユーザー確認済み、`docs/completed-log.md`参照）。
- [ ] （次回コミット待ち）今回の`.gitignore`修正（個人用ビルド生成物の除外追加）・関連ドキュメント更新をcommit.batでコミット・push（`cleanup_git_history.bat`実行時に作業ツリーがリセットされ一度失われたため再編集した分、2026-08-02）。

- [ ] （Windows実機確認待ち、一部確認済み）JMA自動取得が予報無しの暫定電文を掴む不具合の修正（2026-08-04実装、Agentレビュー済み）：`lib/utils/jma_feed_fetcher.dart`の`fetchLatestJmaTyphoon`／`fetchActiveJmaTyphoons`に、最新電文に予報が無い場合は同一台風のより新しい予報付き電文を探して優先する処理を追加。**2613TY（DOLPHIN）で予報軌跡が復活することはユーザー確認済み。** 残り確認事項：①もう1つの台風（Typhoon 2枠）や「Import All (JMA)」でも同様に予報が正しく反映されること、②予報が本当に存在しない弱い熱帯低気圧等では従来どおり実況のみ（0件）で問題なく表示されること。

- [ ] `android/app/build.gradle.kts`に本流／個人用の`productFlavors`を追加（別`applicationId`・別アプリ名で同一端末に両方インストール可能に、Windows版の別zip/別exeに相当）。それまでは`--dart-define=PERSONAL_BUILD=true`のみで本流／個人を分岐（デスクトップ版と同じ機構、現状のまま）
- [ ] （Android実機確認待ち）`build_apk.bat`／`build_apk_personal.bat`によるリリースAPKビルド自体の動作確認（`run_android.bat`系の開発実行は一連の実機テスト——ダブルタップ・凡例・カーソル機能等——が行えたことから動作確認済みと判断できるが、リリースAPKビルドは別のGradleパス・minify設定のため未確認のまま）
- [ ] （Android実機確認待ち）ボタン・スライダー等のタップ領域サイズが操作しやすいか確認（Material既定サイズのままで十分か、実物を見ないと判断できない部分）
- [ ] （Android実機確認待ち）`file_picker`によるPassage Plan CSVインポートの動作確認
- [ ] （Windows実機確認待ち、一部確認済み）保存先をzip内（exe相対の`UserData`フォルダ）に変更（2026-08-01実装）**：フォルダ名衝突（`Data`→`UserData`）・zip化での`data`フォルダ欠落（`robocopy`ステージング方式へ変更）の2件のバグを修正し、**展開したexeが起動することは確認済み**。残り確認項目：①既存AppData内データが初回起動時に新しい`UserData`フォルダへ自動移行され表示されること、②新規登録データが`UserData`フォルダに保存されること、③`UserData`フォルダごと別PC（別フォルダ）にコピーして同じ内容が表示されること、④`build_release.bat`（mainline版）実行後のzipにも`UserData`が含まれておらず`data`フォルダは含まれていること。詳細・原因・教訓は`docs/devlog-portable-data-dir.md`参照。
- [ ] （Windows実機確認待ち）台風との距離表示（"N nm"ボックス）の文字色を白→黒に変更（2026-07-31）：台風の色（塗り）の上で黒文字が見やすいか確認する
- [ ] （Windows実機確認待ち）船アイコンを色別10種の専用画像（`assets/ship_01.png`〜`ship_10.png`）に切替（2026-07-31、旧`ship_icon01.png`＋`ColorFilter`着色方式を廃止）：①各Passage Plan（自動色分け・手動色選択いずれも）で対応する色の船体画像が表示されること、②船の見た目の大きさ（長さ）が変更前と同程度であること、③船の座標アンカー位置（船体上のどのあたりに乗るか）が変更前と同程度に見えること、の3点を確認する。詳細・数値根拠は`docs/devlog-2026-07-31-ui-polish-and-wave-field-design.md`参照。
- [ ] （Windows実機確認待ち）波の場オーバーレイの流れ方向表現をシェブロン方式（">"が流れて動く）に変更（2026-07-31、`_drawWaveStreaks`）。矢じり付き直線ストリーク・波高等高線（1m刻み）はいずれもユーザー確認の上で撤回済み。実機で見やすさを確認する。
- [ ] （Windows実機確認待ち）波の場オーバーレイの波高カラーバー凡例（2026-07-31追加、`_buildWaveHeightLegend`。色スケールは0-8m・6段階「青→緑→黄→橙→紫→赤」に変更済み）：Display On時に右下（日時表示の上）へ自動表示されること、メモリ（8/7/6/5/4/3/2/1/0m）と実際の色分けが対応していること、日時／カーソル緯度経度表示と重ならないこと、0-8m全域で隣接区間の見分けやすさが改善したことを確認する。
- [ ] （Windows実機確認待ち）再生バー終点の定義変更（2026-07-31、「台風の最終予報時または航海終了時のうち遅いほう」）：台風予報の方が航海終了より長いケース・短いケース両方で、再生バーが正しい終点まで伸びること、短い方の船or台風が終点で位置に留まったまま表示されることを確認する。
- [ ] （Windows実機確認待ち）Passage Plan編集画面の緯度経度入力を10進度から度分（"DD-MM.MM"、例: 35-24.56）形式に変更（2026-07-31、`lib/utils/deg_min_format.dart`新設）：既存WPの表示・新規入力・不正値エラー表示、CSVインポート直後のWPを編集画面で開いた際の表示が正しく度分に変換されることを確認する。
- [ ] CSVライブラリの上限50件到達時のエラー表示のみ未確認（他の全項目はWindows実機で確認済み、`docs/completed-log.md`参照）。50件貯める機会があれば確認する
- [ ] （Windows実機確認待ち）複数台風同時発表対応・Import Allボタン（2026-07-29実装、1件のみの場合の動作は実機確認済み）：「Import All (JMA)」「Import All (JTWC)」で2件以上同時に見つかった場合、Typhoon 1/2/3それぞれ独立してDisplay On/Off切替できるか（コード上は独立していることを確認済みだが実機未確認）。あわせて完了メッセージ「Imported to Typhoon 1, 2」等の表記も確認。「Fetch」→「Import」への表記統一箇所（Import from JMA/JTWC、Import All）も見た目を確認。
- [ ] （Windows実機確認待ち）Passage Planの「Edit CSV」でのRe-Nameが、登録済みプランの表示名に反映されない不具合の修正（2026-08-04実装、Agentレビュー済み）：`lib/screens/map_screen.dart`の`_renameCsvLibraryEntry`に、リネーム後`_voyagePlans`内で`sourceCsvFileName`が一致するプランの`name`・`sourceCsvFileName`を更新する処理を追加（表示中でも即座にPassage Planメニュー・地図凡例ボックスへ反映される設計、2026-07-27の「現状維持でOK」判断を撤回）。本流／個人用・PC/Mobile共通の単一コードベースのため全ビルドに適用済み。確認事項：①表示中のPassage PlanをEdit CSVでRe-Nameし、メニュー・凡例ボックスの名前が即座に切り替わること、②Re-Name後にDeleteしても正しく登録済みプランごとカスケード削除されること。

## 決定待ち・要確認事項

- [ ] **本流公開に向けた法務系項目：5点の方針決定・3つの実装（プライバシーポリシー本文・About画面・README）・コミット/`feature/mobile`→`main`マージ/push・GitHub Pages公開まで全て完了**（2026-08-04、`https://captedge.github.io/tyohoon_npo/privacy-policy.html`をユーザーがブラウザで閲覧確認済み。経緯・詳細は`docs/release-checklist.md`・`docs/completed-log.md`参照）。**残るのは以下のみ**：
  - [ ] （Windows実機確認待ち）About画面の英日併記2箇所（Data Sources注記・Disclaimer）の表示崩れがないか確認
  - [ ] （Android実機確認待ち）モバイル版でも同じAboutダイアログが開くこと（`_buildAppBar`はデスクトップ/モバイル共用のため理論上は自動反映される想定、未確認）
  - [ ] プライバシーポリシーURL（上記）をGoogle Play Console／Microsoft Partner Centerのストア管理画面に登録（申請時）

- **「Open-Meteo marine (trial)」メニュー削除の要望（2026-07-31仕様変更で依頼）について、対象となる独立メニュー項目がコード上に見当たらないことを確認**：2026-07-29時点では船の現在位置で試し取得するだけの独立ダイアログ（AppBarの専用ボタン）として存在したが、2026-07-30の「固定エリア・手動Import方式」への全面再設計時に、この独立ダイアログ自体が廃止され、Display切替・Importボタンとも「Forecast」（旧Information）ダイアログ内の「Wave Field (Open-Meteo, personal build)」セクション1つに統合済みだった（`_showLabelSettingsDialog`、AppBarには対応するボタンなし）。ユーザーが「取得はInformationからできるため不要」と説明した独立メニューは、この統合により既に存在しない状態と見られる。Wave Field機能本体・個人用ビルドの仕組み（`kPersonalBuild`）はユーザー指示により削除せず維持。次回セッションでWindows実機の実際のメニュー表示を見ながら、削除すべき項目が本当に残っていないか再確認する。
- より高精細な海岸線データ（1:10m相当）への差し替え（優先度低、`docs/devlog-map-design.md`参照）
- **デザイン・仕様は2026-07-31時点でユーザー判断によりほぼ完了**（本人発言：「デザイン、仕様、ほぼ完了と思っています」）。アプリ名称は今後変更の可能性あり（未着手、着手時期未定）。上記「未着手・進行中」に残るWindows実機確認待ち項目群の消化が次の主な作業。
- （Windows実機確認待ち）アプリアイコン（`assets/app_icon_05.png`ベース）のWindows側表示確認：タスクバー／エクスプローラーでの見え方。Android側（エミュレータ/実機、ホーム画面）は視認性問題なしと確認済み（2026-08-02、`docs/completed-log.md`参照）。
- アプリアイコンの正方形の枠に対する絵柄の大きさ（スケール）調整（2026-08-02、Android実機確認後にユーザーより依頼）：視認性自体は問題ないが、枠に対する船・台風の大きさを調整したいとの要望。具体的な倍率・方向（拡大／縮小）は未指定のため、着手時に確認する。
