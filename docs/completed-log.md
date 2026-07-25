# completed-log.md — 完了記録

宣言2（記録の4分割）の④を担当。1件につき日付・結論1〜2行。詳細は該当`docs/devlog-<テーマ>.md`にリンクする。

書式：
`**タイトル**（日付、コミットハッシュ、該当すればブランチ名）— 結論1〜2行。詳細は`docs/devlog-xxx.md`（devlogを作らない軽微な変更なら省略）。`

---

**プロジェクト運用の土台構築**（2026-07-25）— 5つの宣言（`docs/project-declarations.md`）に基づき、CLAUDE.md／TASKS.md／`docs/operation-rules.md`（本プロジェクト用に書き換え）／`docs/completed-log.md`を整備。技術スタック（Flutter、デスクトップ先行）、セッション構成（単一セッションで進行管理とコーディングを兼務）、Flutterプロジェクトパス（`typhoon_ship_tracker/`、英数字のみ）を決定。ブートストラップ用の`CLAUDE.md追記スニペット.md`は内容反映済みのため削除。

**Flutter×Windows環境メモの反映**（2026-07-25）— ユーザー提供の`flutter-windows-env-notes.md`（Flutter SDK/Android SDKパス、AVD名、`flutter analyze`クラッシュ問題、`.bat`/git操作の既知の落とし穴等）を`docs/`に保存し、CLAUDE.mdのセッション開始チェックリストと環境構成、`docs/operation-rules.md`の完了報告前チェック・git運用から参照するよう反映。

**地図表示・距離計算・データ取得方式の決定**（2026-07-25）— 以前のチャットでの検討内容（中分緯度法での距離計算、簡易プロット版の地図表示、表示範囲N20-50/E115-150固定、JMA防災情報XML＋JTWCテキストのWi-Fi時取得＋オフラインキャッシュのハイブリッド方式）をCLAUDE.mdの現状要約に反映し、詳細な経緯・判断根拠は`docs/devlog-map-design.md`に退避。TASKS.mdも実際の設計に合わせて更新。

**初回git commit/push完了**（2026-07-25、`main`ブランチ、root-commit `279b179`）— `commit.bat`経由でユーザーが実行。10ファイル・396行をリモート`https://github.com/captedge/tyohoon_npo.git`にpush。LF→CRLF変換の警告は無害（内容には影響なし）。

**地図モックアップレビュー・表示範囲の見直し**（2026-07-26）— 簡易プロット版モックアップを提示しフィードバックを反映。表示範囲をN20-50からN5-50/E115-150へ拡張（フィリピン全域を含めるため）、緯度経度両方のグリッド表示、ズームUI（＋／－ボタン＋スライダー追加）、UIラベル全て英語表記、再生ボタンのトグル動作を決定。経緯・教訓は`docs/devlog-map-design.md`に追記。

**第一段階のコミット/プッシュ完了**（2026-07-26、`main`ブランチ、commit `5935e4f`）— `commit.bat`経由でユーザーが実行。地図画面の初期実装一式と調査結果をリモートにpush。以後`git add .`は使わず、変更ファイル/新規フォルダを明示列挙する方式に変更済み。`windows/`配下でCRLF差分のみのノイズが出ることを確認、実害なしのため`docs/flutter-windows-env-notes.md`に記録のみ。

**投影法・表示比率の見直し（メルカトル図法化）**（2026-07-26）— 実機レビューで「日本の形が縦に縮んで見える」との指摘を受け、原因（等角経緯度図法での経度方向の未補正＋ウィンドウ形状に応じた地図の伸縮）を特定し対応。`lib/utils/map_bounds.dart`をWeb Mercator投影に変更し、表示範囲の正しい縦横比を持つ固定論理キャンバス（`MapBounds.canvasSize`）を導入。起動時は日本付近（N30/E135）を中心に表示するよう変更（`MapBounds.defaultCenterLat/Lon`）。あわせて、より高精細な海岸線データ取得の技術検証（Natural Earth 1:50m等）を行い、Coworkのファイル取得サイズ制限により今回は取得不可と判明。回避策（ユーザーが直接ダウンロードしてプロジェクトフォルダに置く）を`TASKS.md`に記録。

**海岸線データの実データ化・ズーム操作性の改善**（2026-07-26）— 仮の海岸線ポリゴンをNatural Earth 1:110m land data（TopoJSON経由）由来の実データに差し替え（`typhoon_ship_tracker/assets/coastline/coastline.json`、生成手順は同フォルダのREADME参照）。あわせてズーム処理を書き直し、マウスホイールはカーソル位置、ボタン/スライダーは画面中心を軸にズームするよう変更してパン位置リセット問題を解消。自己レビューで型エラー（`clamp`が`num`を返す問題）と`shouldRepaint`が海岸線読込完了を検知できていない不具合を発見・修正。海岸線データの詳細は`docs/devlog-map-design.md`参照。

**Windows実機初回動作確認・レビュー反映**（2026-07-26）— `flutter run -d windows`がVisual Studio導入後に成功。操作性・台風表示は好評。フィードバックを受けて航海計画の点線＋Waypointマーカー（`_drawShipRoute`）と、画面上部固定の日時表示（`dd mmm. yyyy HH:MM (JST)`形式）を追加実装。海岸線の陸海配色・船アイコンのデザインは今後相談として`TASKS.md`に記録。

**航海計画CSVの実サンプル確認**（2026-07-26）— ユーザー提供の実ファイル（`013K378NEG W-KII.csv`）で列構成を確認。公式マニュアル通りJRC ECDIS純正フォーマットで、日時列は無し。出発日時1回入力＋区間距離÷速力での到着時刻積算という設計方針を決定。詳細は`docs/data-format-notes.md`参照。

**マウスホイールズーム・縦スライダーの追加、JRC ECDIS/NAVTOR CSV調査**（2026-07-26）— ユーザーからの操作性の質問を受け、`map_screen.dart`にマウスホイールでのズームと縦方向のズームスライダーを追加（＋／－ボタンと同じ`_zoom`状態で同期）。あわせて型エラー（`clamp`が`num`を返す問題）を修正。JRC ECDIS純正ルートCSV書式を公式マニュアルで調査し、列構成（WP No/Lat/Lon/Prt/Stb/Arr Rad/Speed/Sail）を確認。ただしETA/ETD列は純正書式に含まれないため、実サンプル確認が必要と判明（詳細は`docs/data-format-notes.md`参照）。

**Flutterプロジェクト雛形＋地図画面の初期実装**（2026-07-26）— `typhoon_ship_tracker/`に`pubspec.yaml`と`lib/`（models/track_point.dart、utils/interpolation.dart・map_bounds.dart、widgets/map_painter.dart、screens/map_screen.dart、main.dart）を作成。中分緯度法での距離計算、前後2点の線形補間、グリッド＋仮海岸線の描画、InteractiveViewer＋＋／－ズームボタン、再生／一時停止トグル付き時刻スライダーを実装。海岸線は実データ未選定のため仮ポリゴン（`TODO(map-data)`）。自己レビューで`Path.extractPath`への引数型エラー（`num`→`double`）を発見・修正済み。OSプラットフォーム雛形（`windows/`等）は`flutter create`が必要でサンドボックスでは生成不可のため、ユーザー側での実行待ち。気象庁「防災情報XML」の電文種類（VPTW60）と提供形態（PULL型・無認証）を調査、詳細は`docs/data-format-notes.md`参照。

**海岸線データの1:50m化・配色の暫定変更**（2026-07-27）— 前回セッションでは取得不可と判断していたNatural Earth 1:50mデータを、`registry.npmjs.org`経由（`world-atlas@1.1.4`）で取得できることを発見し、`coastline.json`を1:110m（14ポリゴン/約300点）から1:50m（123ポリゴン/約3,000点）に差し替え。差し替え前にmatplotlibで描画して形状を目視確認済み。あわせて陸海の配色を仮の白／灰色から、ナビチャート風（淡い青の海／ベージュの陸）へ暫定変更（`map_painter.dart`の`_seaColor`等）。詳細・データ取得の教訓は`docs/devlog-map-design.md`参照。

**海岸線・配色のユーザー確認完了、グリッドラベルの追従表示化**（2026-07-27）— 上記の海岸線1:50m化・配色変更をユーザーが実機で確認し「とても良い」と確定。あわせて新規フィードバック（緯度経度グリッドラベルがズーム/パンで画面外に出る）に対応：`map_painter.dart`の`_drawGrid`からラベル描画を削除しグリッド線のみに変更、`map_screen.dart`に`_buildGridLabelOverlay`を新設し、`TransformationController`を直接listenする`AnimatedBuilder`でラベルを画面端（緯度＝左端、経度＝上端）に追従表示するオーバーレイ方式に変更。ドラッグ中もリアルタイムに追従するよう、既存の`_zoom`/`_translation`状態（interaction終了時のみ更新）ではなくコントローラー自体を直接参照する設計にした。詳細は`docs/devlog-map-overlays.md`参照。

**カーソル位置緯度経度の表示・船アイコンの向き変更**（2026-07-27）— `MapBounds`に`toOffset`の逆変換`fromOffset`（Web Mercator逆変換）を追加し往復精度をPythonで事前検証。`map_screen.dart`に`MouseRegion`を追加し、カーソル位置の緯度経度を画面右下（ズームボタン列と重ならない位置）に「31-15.5N 140-23.4E」形式（度-分.小数、秒は分の小数へ換算）で追従表示。船アイコンは、`MapPainter`に`nextWaypoint`を追加し、現在の船位置から次のWPへの方位角をキャンバス座標上で計算して三角形を回転させる方式に変更（三角形の形自体は現状維持、頂点が常に次のWPを向く）。詳細は`docs/devlog-map-overlays.md`参照。

**起動用batファイルの作成**（2026-07-27）— プロジェクトルートに`run_windows.bat`を新規作成。ダブルクリックで`typhoon_ship_tracker/`に移動し`flutter run -d windows`を実行、終了後は`pause`でウィンドウを保持。`.bat`納品前チェックリスト（CRLF変換／括弧ネストなし／日本語直書きなし）を確認済み。あわせて`commit.bat`の`git add`対象に`run_windows.bat`を追加し、`typhoon_ship_tracker`丸ごと追加から今回変更した個別ファイル列挙に変更（`windows/`配下等のCRLFノイズを巻き込まないため）。

**CLAUDE.mdの記録漏れ修正**（2026-07-27）— セッション終了前の確認で、「プロジェクト雛形の現状」（`windows/`未生成のまま止まっていた記載）と「海岸線データ」（1:110mのまま止まっていた記載）が実態と食い違っていることを発見し修正。`windows/`は2026-07-26に生成・コミット済み（commit `5935e4f`）であることをgit logで確認、海岸線は本セッションで1:50mに更新済みであることを反映。

**本セッション分のコミット/プッシュ完了**（2026-07-27、`main`ブランチ、commit `070c3d6`）— `commit.bat`経由でユーザーが実行。1回目はCoworkサンドボックス側で残った`.git/index.lock`が原因で失敗（`allow_cowork_file_delete`で削除許可を得て解消）、2回目で成功。海岸線1:50m化・配色確定・グリッドラベル/カーソル座標の追従表示・船アイコンの向き変更・`run_windows.bat`・CLAUDE.md記録修正の11ファイルをpush。LF→CRLF変換の警告は無害（過去のコミットと同様）。

**index.lock残留の原因調査・再発防止ルール策定**（2026-07-27）— 上記の`commit.bat`失敗の根本原因をユーザー依頼で追及。原因は、Coworkサンドボックスから確認目的で実行した読み取り専用の`git status`が、終了時に自分で作った`.git/index.lock`を削除しようとして権限エラーで失敗し（サンドボックスからのファイル削除失敗という既知の癖と同根）、その警告を「コミットしていないから無関係」と誤って軽視・放置したこと。Agentツール（general-purpose）による独立レビューで、対象を`index.lock`だけでなく`.git`配下の`*.lock`全般に広げるべき、警告の有無に関わらず機械的に確認すべき、という指摘を得て反映。再発防止ルールを`docs/operation-rules.md`「サンドボックスからのgitコマンド実行によるロックファイル残留」と`docs/flutter-windows-env-notes.md`（一般的な注意7）に記載。

**時刻スライダー上限のデータ駆動化・再生バーのWindy風デザイン化**（2026-07-25）— 時刻スライダーの上限を72hのハードコードから台風予報データ（`_typhoonTrack`）の最後の点から算出するデータ駆動方式に変更（JMA VPTW60の5日＝120h予報にそのまま対応、将来のJTWCデータ追加時もコード変更不要）。あわせて再生バーをWindyアプリ風のデザイン（オレンジ色の「HH:MM」バブル追従表示、最下段に「dd mmm」形式の日付セグメント行、当日ハイライト、タップでジャンプ）に刷新。

**距離表示を船の後方へ追従表示化**（2026-07-28）— 船・台風間の距離ラベルを、中間点表示→船の左側固定表示（第1段階）を経て、最終的に船の進行方向の逆側（後方）に追従表示するよう変更（濃い青灰色の塗りつぶし＋白文字の囲み付きで海・陸どちらの背景でも視認可能）。西進時に「左側固定」だと不自然になりうるとの気づきを受けての再変更。

**サンプル航海計画にWP追加**（2026-07-28）— 変針後の船アイコン向き・距離表示追従（上記）を確認できるよう、仮の航海計画データ（`_shipTrack`）を1レグ（2点）から5レグ（6点・+120hまで）に拡張。西向きのレグも含め、複数方向での見た目を確認できるようにした。

**船名・台風ラベルの追加**（2026-07-28）— 船のラベルをユーザー入力の「Ship's Name」で表示できるAppBarダイアログを追加（NAVTOR規格CSVに船名列が無いための代替入力）。あわせて`lib/utils/jtwc_parser.dart`を新規作成し、JTWC警報テキストから正規表現で番号・名称（例：「11W (NOUL)」）を抽出して台風ラベルに反映する仕組みを追加。`MapPainter`に`shipLabel`/`typhoonLabel`パラメータを追加。抽出仕様は`docs/data-format-notes.md`参照。

**複数台風対応・気圧表示・Displayトグル**（2026-07-28）— Menuダイアログを最大3台風分の貼り付け欄に拡張し、それぞれ独立にJTWC警報テキストから番号・名称・中心気圧（例：「980hPa」）・現在位置を抽出する仕組みに拡張（`jtwc_parser.dart`の`JtwcTyphoonInfo`/`parseJtwcWarningText`に統合）。台風1は従来通りサンプル予報進路で時刻追従、台風2・3は予報進路を持たない静的マーカー（`ExtraTyphoon`、`map_painter.dart`）として表示。あわせて船・台風（最大3）それぞれにDisplay ON/OFFチェックボックスを追加し、`MapPainter`の`showShip`/`showPrimaryTyphoon`/`extraTyphoons`で表示制御。抽出仕様は`docs/data-format-notes.md`参照。

**台風軌跡の常時表示化・予報点抽出**（2026-07-28）— 上記へのフィードバックを受け、台風の軌跡を船のルートと同様に過去〜未来の全区間を常時表示するよう刷新。読み込み時の最低気圧ラベルは軌跡の最初の点に固定し、再生で時刻が進んでも番号・名称ラベルのみが現在位置に追従する仕様に変更。あわせてJTWCテキストの12/24/36/48/60時間予報点を正規表現で抽出（`JtwcForecastPoint`）し、静的マーカーだった台風2・3にも実際の軌跡を持たせられるように拡張。`ExtraTyphoon`と主台風専用フィールドを`TyphoonMarker`に統合。予報点の抽出仕様は`docs/data-format-notes.md`参照。

**再生開始時刻の発表時間化**（2026-07-28）— 再生開始時刻（`_startTime`）を「現在時刻」固定から「読み込んだTyphoon 1の発表時間」（JTWC警報の`WARNING POSITION`行の`DDHHMMZ`をJSTへ変換）に変更。`jtwc_parser.dart`に`issuedAtJst`を追加し、`map_screen.dart`の`_startTime`を可変化、依存する`_shipTrack`/`_typhoonTrackFallback`をゲッター化して再計算されるようにした。発表時刻の解決仕様は`docs/data-format-notes.md`参照。

**再生スピード調整**（2026-07-28）— 再生スピードを25%〜150%（デフォルト50%）でAppBarから調整できるダイアログを追加。

**clean_project.batの作成**（2026-07-25）— Androidアプリ開発での既存の習慣（ビルド肥大化対策）を踏襲し、プロジェクトフォルダ直下に`clean_project.bat`を新設。`typhoon_ship_tracker/`で`flutter clean`を実行し`build/`・`.dart_tool/`を削除する。作成時点で実測`build/`228MB・`.dart_tool/`42MBだったが、ユーザーが実行後に両フォルダとも削除されていることを確認済み。実行タイミングはユーザーの任意（習慣化済みのため定期実行の仕組み化は不要と判断）。

**マウスホイールズームの不具合修正**（2026-07-28、3往復）— マウスホイールでのズームアウトが最小まで届かない不具合を調査。1回目（`PointerSignalResolver`経由での登録）は効果なし、2回目で独自のホイール処理を撤去し`InteractiveViewer`本来の処理に一本化（副作用対応として`_transformationController`への永続リスナーを追加）、3回目でズーム最小値を「cover」フィット基準（新設`_coverFitScale`）に変更しホイール・ボタン・スライダーの限界を統一。経緯・原因・教訓は`docs/devlog-wheel-zoom.md`に集約。

**表示エリアの東西範囲拡張（東経70°〜180°、後に85°〜170°へ微調整）**（2026-07-25）— TASKS.mdで決定待ちだった東西表示範囲拡張が決定し対応。`MapBounds`（`lib/utils/map_bounds.dart`）の`minLon`/`maxLon`を115/150から70/180に変更（緯度N5-50は変更なし）。海岸線データも同じNatural Earth 1:50mソース・手法（`registry.npmjs.org`経由でworld-atlas取得→TopoJSON手動デコード→shapelyでunion・クリップ・簡略化）でE70-180に再クリップ。その後ユーザーの好み（技術的理由ではなく見た目の好み）で東経85°〜170°に絞り込み確定（緯度は変更なし）。最終的な海岸線データは198ポリゴン・約4,510点・~73KB。クリップ後にmatplotlibで形状を目視確認済み。グリッド線・グリッドラベルオーバーレイは`MapBounds.minLon/maxLon`を動的参照する設計だったため、コード変更不要で表示範囲変更に追従することを確認済み。詳細は`typhoon_ship_tracker/assets/coastline/README.md`参照。

**航海計画CSVインポート・出発日時入力・WP追加/区間速力編集の実装**（2026-07-30）— `docs/data-format-notes.md`で確定済みだったJRC ECDIS/NAVTORルートCSV形式（17列、`//`コメント行、WP000の`***`列）のパーサーを実装。ユーザー提供の実サンプル`NEG AW-KII.csv`（24 WP、コメント3行含む28行）で列数・緯度経度換算・区間距離÷速力の時刻積算ロジックをPythonで再現検証済み（総距離約599.6NM、WP0発9:00→WP23着9:52、約48.9時間、速力欠落なし）。実装内容：`lib/models/ship_waypoint.dart`（`ShipWaypoint`、時刻を持たず区間速力`speedKn`のみ保持）、`lib/utils/voyage_plan_parser.dart`（CSV→`ShipWaypoint`リスト、列数不足や東西南北不正値は`VoyagePlanParseException`）、`lib/utils/voyage_plan.dart`（`shipTrackFromWaypoints`：既存の中分緯度法`distanceNm`で区間距離を算出し区間速力で除算、`TrackPoint`リストへ変換。速力未設定は`VoyagePlanTimeException`）、`lib/screens/voyage_plan_screen.dart`（WP一覧の表形式編集画面：緯度経度・速力・名称の直接編集、行の追加/削除、出発日時ピッカー、Save時に変換ロジックで検証してから確定）。`map_screen.dart`のAppBarに船アイコンのメニュー（Import CSV.../Edit voyage plan...）を追加し、`file_picker`パッケージ（pubspec.yamlに追加、`^8.1.2`）でファイル選択→パース→編集画面→保存の流れを実装。既存のサンプル航海計画（`_shipTrackSample`）はCSV未取込時のフォールバックとして維持。緯度経度は現版では10進度で編集（他画面の度分表記と揃えるかは要確認、TASKS.md参照）。CoworkサンドボックスがLinuxのためビルド未実施——ユーザーのWindows機での`flutter pub get`＋`flutter run -d windows`での動作確認が必要。

**再生バーの日付ずれバグ修正**（2026-07-30）— 台風情報（JTWC警報テキスト）読込時、再生開始時刻の「時刻」（HH:MM）は正しいのに再生バー下段の日付区切り（例：25 Jul/26 Jul）が1日ずれる不具合をユーザー報告により修正。原因は`jtwc_parser.dart`の`issuedAtJst()`が`DateTime.utc(...).add(Duration(hours:9))`でUTCタグ付きの日時オブジェクトを生成していたこと。アプリの他の箇所（`map_screen.dart`の`_dayColumns`が使う`DateTime(_startTime.year, _startTime.month, _startTime.day)`等）はすべてタグなしの素の日時として扱う設計のため、実行環境（PC）のタイムゾーン設定によっては同じ数値でも「実際の瞬間」が数時間ずれ、日付境界の判定がおかしくなっていた。修正は`DateTime.utc`を使わず、UTC→JST（+9h）の日またぎを手計算（`day + dayCarry`）して素のDateTimeを組み立てる方式に変更。Pythonでの再現計算（250600Z→25日15:00、250000Z→25日9:00、252200Z→26日7:00）で検証済み。

**軌跡の実線/点線分割・オブジェクトのズーム固定サイズ化**（2026-08-03）— 2点の見た目改善要望に対応。①船・台風とも、現在時刻より前（通過済み）の軌跡を実線、後（予定）を点線で描き分け。`lib/utils/interpolation.dart`に`splitTrackAtTime`を新設（現在時刻の補間点を境界として past/future の2リストに分割、境界点を両方に含めて線がつながるようにする）。Python側で境界点の連続性を検証済み。②船アイコン・台風アイコン・各ラベル（船名、台風番号、気圧、距離nm）・航路上の小さな丸マーカーが、地図をズームすると画面上でも大きく/小さくなってしまう問題を修正。`MapPainter`に`zoom`パラメータを追加し、各マーカー/ラベル描画箇所を`canvas.translate`+`canvas.scale(1/zoom)`で囲むことで、地図のズーム倍率を打ち消し画面上のサイズを常に一定に保つようにした（航路・軌跡の線自体は従来通り地図と一緒にズームする仕様を維持）。`map_screen.dart`から`MapPainter`へ`zoom: _zoom`・`shipPastRoute`/`shipFutureRoute`・台風スロットごとの`pastTrack`/`futureTrack`を渡すよう連携。

**実線/点線の太さもズーム固定化・船と台風で太さ統一**（2026-08-03）— 前回の軌跡実線/点線分割・オブジェクトのズーム固定サイズ化に続き、線の太さもズームで変わらないよう修正。`MapPainter._drawPolyline`のPaintの`strokeWidth`を「画面上で見せたい太さ×(1/zoom)」で設定する方式に変更（マーカー/ラベルと同じ「1/zoomを打ち消す」考え方だが、線は始点終点がシーン座標のままズーム/パンに追従する必要があるため、canvas.scaleではなくstrokeWidth自体をスケール）。あわせて船ルート（従来1.5）と台風軌跡（従来2）で別々だった太さを`_trackStrokeWidthPx = 2.0`に統一。

**点線パターン（長さ・間隔）の統一・細かく調整**（2026-08-03）— 船ルート（従来: 長さ4/間隔3）と台風軌跡（従来: 長さ6/間隔4、デフォルト値のまま個別調整されていなかった）で異なっていた点線パターンを、`_trackDashLengthPx=3.0`/`_trackGapLengthPx=2.0`（従来の船より少し細かい）に統一。`MapPainter._drawPolyline`のデフォルト引数化により両者が自動的に同じ値を使うようにした。

**再生バーの終点を航海計画の最終WPに変更**（2026-08-10）— `map_screen.dart`の`_maxOffsetHours`（再生バー・スライダーの上限時間）を、台風スロット0の最終予報点基準から船の航海計画の最終WP到着時刻基準に変更。台風データの予報期間が船の航海より短くても、再生バーは船が到着地に着くまで進めるようにした（台風マーカーは自身の軌跡の最終点を過ぎると、`positionAt`のクランプ挙動によりそこで静止表示される）。サンプルデータ（未インポート時）は船・台風とも従来通り+120hで揃っているため見た目上の変化はない。

**船名・台風名ラベルの後方表示化**（2026-08-14）— 船名・台風番号（designation）ラベルが常にアイコンの右横固定だった見た目を、進行方向の後方（distance表示と同じ「behind」方向）に常時追従するよう変更。船側は既存の距離表示（distance box）と重ならないよう、船名を内側・距離を外側にスタック配置（`_drawShip`内で共通の`behind`方向を使い、`_drawDistanceLabel`を独自translate不要な形に書き換えて呼び出す方式に統合）。台風側は`futureTrack`の直後の点（無ければ`pastTrack`の直近区間）から進行方向を推定する`_typhoonBehindDirection`を新設。気圧ラベル（track.first固定）は対象外・変更なし。文字サイズ・色・太さは既存のまま。`typhoon_ship_tracker/lib/widgets/map_painter.dart`のみ変更。確認済み：コメント除く括弧・波括弧の対応が0で一致（構文上の破綻なし）。Coworkサンドボックス（Linux）のためビルド未実施——Windows機での`flutter run -d windows`での見た目確認が必要。

**gitサブコマンドのホワイトリスト化（誤操作対応）**（2026-08-14）— 上記の確認作業中、サンドボックスから禁止対象の`git stash`を誤って実行（直前の`git diff`が残した`index.lock`により偶然失敗、実害なし）。ユーザーから「失敗＝実害なしは結果論」「『つもり』は機械的基準でない」と指摘を受け、`docs/operation-rules.md`のgit運用ルールを「add/commit/pushを禁止」という書き方から「サンドボックスで実行してよいのは`status`/`diff`/`log`のみ」というホワイトリスト方式に強化。詳細・教訓は同ファイルの「サンドボックスから実行してよいgitサブコマンドのホワイトリスト」参照。

**台風の100nm/200nm距離同心円の追加**（2026-08-14）— 台風中心（赤丸）から100nm・200nmの同心円を表示できる機能を追加。`TyphoonMarker`に`showRings`フラグを追加し、`MapPainter`に円（塗りなし・アウトラインのみ、100nm=ティール／200nm=パープル、いったんお任せ配色）とラベル（円の外側・真上、フォントサイズ9・ズームで固定サイズ）の描画を実装。円自体は地理的な距離を表すため地図と一緒にズーム/パンする一方、線の太さとラベルは他の要素と同じ`1/zoom`補正で画面上一定サイズを維持。ラベル位置は前回の同心円追加確認時のユーザー指示「情報→上方」を反映し円の真上（12時位置）に統一。距離→キャンバスpx換算は`MapBounds`のWeb Mercatorが等角図法である性質を利用し、緯度に応じた単一のスケール係数`_pxPerNm(lat)`で算出（PythonでのMercator微分検証は行わず、コード内コメントで導出過程を明記）。切り替えはAppBarに追加した`100/200nm rings`メニュー（`CheckedPopupMenuItem`でワンクリックON/OFF）と、地図上の台風アイコン（赤丸）タップの両方から可能（`_handleMapTap`、地図キャンバスを`GestureDetector(behavior: opaque)`で包み、タップ位置とアイコン位置の距離を`1/zoom`補正した許容半径で判定）。`_TyphoonSlot.ringsEnabled`（既定false）で状態管理。確認済み：`map_screen.dart`・`map_painter.dart`ともコメント除く括弧・波括弧の対応が0で一致。Coworkサンドボックス（Linux）のためビルド未実施——Windows機での実機確認（同心円の見た目・タップ判定・メニュー切り替え）が必要。

**JST日時表示を右下（カーソル緯度経度の上）へ移動**（2026-08-16）— 左上固定だった日時表示が、拡大率によっては左上の緯度経度グリッドラベルと重なる不具合をユーザー報告により修正。`map_screen.dart`のPositioned（left:12,top:12）を削除し、右下のカーソル緯度経度表示（right:64,bottom:12）と同じColumnにまとめて、日時を上・カーソル緯度経度を下に縦積み表示するよう変更（カーソル非表示時は日時のみ表示）。確認済み：コメント除く括弧・波括弧の対応が0で一致。Windows機での実機確認が必要。
