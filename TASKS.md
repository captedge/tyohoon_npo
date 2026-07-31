# TASKS.md — 進行中・次にやること

宣言2（記録の4分割）の②を担当。**このファイルは「未着手・進行中のタスク」と「決定待ち・要確認事項」だけを置く。** 完了したタスクはチェックを付けた時点でここから除去し、`docs/completed-log.md`に1〜2行で記録する（詳細な経緯・技術的な学びがある場合は該当`docs/devlog-<テーマ>.md`へ）。仕様調査結果（CSV/XML形式など）のような「参照資料」は`docs/data-format-notes.md`に集約する。

## 未着手・進行中

- [ ] 海上気象データソースの追加、①沿岸波浪予報（JMA地方海上予報＝VPCY51）から着手（2026-07-29着手）。表示範囲南側（フィリピン近海、北緯5〜19°）は地方海上予報区の対象外のため非表示のままとする方針を確認済み（2026-07-29）。予報区ポリゴンデータ・区域名定数・電文パーサー（`lib/utils/marine_areas.dart`／`marine_area_codes.dart`／`jma_marine_xml_parser.dart`）は実装済み。**実データ確認済み・①メインへの採用決定**（2026-07-30、ユーザーがWindows実機で「Marine forecast (debug)」ボタンにより実データ取得を確認）を受け、`MapPainter`への予報区ポリゴン塗り分け描画とInformationダイアログへの本番用取得UI（Display切替・Import from JMA・オフラインキャッシュ）を実装済み（2026-07-30、Agentレビュー実施済み——`shouldRepaint`比較がリスト位置ではなく区域コードで一致するよう1件修正）。詳細は`docs/completed-log.md`参照。**次にやること**：
  - [ ] （Windows実機確認待ち）上記の本番実装：`flutter run -d windows`で①Display ON/OFFと地図上の色分け表示、②Import from JMAでの取得・エラーメッセージ、③再起動後もCached表示・色分けが復元されること、を確認してほしい。
- [ ] **発表頻度の再確認が先に必要（2026-07-30発覚）**：当初想定していた「1日4回（6/12/18/24時JST）」は誤りの可能性が高い。ユーザーが12時台に`regular.xml`をブラウザで全文検索（Ctrl+A→Ctrl+F「地方海上予報」）したが0件（6時発表想定の時間帯も含む約10時間分の範囲で確認済み）。Web調査の結果、実際は1日2回（観測3時/15時→発表7時頃/19時頃）の可能性が高いと判明（詳細は`docs/data-format-notes.md`「気象庁 防災情報XML（VPCY51、地方海上予報）」参照）が断定はできていない。**次のステップ**：19時前後にもう一度ユーザーがブラウザで確認し、見つかるかどうかで次の対応を判断する。
  - [ ] Base値のみ表示で、`Becoming`（変化点）への再生スライダー連動（「階段状」表示）は未実装（2026-07-30時点の意図的なスコープ縮小）。`TimeModifier`（例「１０日２１時までに」）を絶対JST時刻へ解析するロジックが未確認のため（実データでの文言パターン確認が先に必要、`jma_marine_xml_parser.dart`の`MarineWaveBecoming`のdocコメント参照）、着手する場合は複数の実電文で`TimeModifier`の文言パターンを確認してから。
  - [ ] ②黒潮＝海しるAPI、③気圧配置図は未着手（`docs/devlog-online-xml.md`参照）。
- [ ] CSVライブラリの上限50件到達時のエラー表示のみ未確認（他の全項目はWindows実機で確認済み、`docs/completed-log.md`参照）。50件貯める機会があれば確認する
- [ ] （Windows実機確認待ち）複数台風同時発表対応・Import Allボタン（2026-07-29実装、1件のみの場合の動作は実機確認済み）：「Import All (JMA)」「Import All (JTWC)」で2件以上同時に見つかった場合、Typhoon 1/2/3それぞれ独立してDisplay On/Off切替できるか（コード上は独立していることを確認済みだが実機未確認）。あわせて完了メッセージ「Imported to Typhoon 1, 2」等の表記も確認。「Fetch」→「Import」への表記統一箇所（Import from JMA/JTWC、Import All）も見た目を確認。
- [ ] **Passage Planの「Edit Plan」でのRe-Nameが、登録済みプランの表示名に反映されない不具合を修正（2026-08-xxユーザー報告、実装は次回）**：CSVライブラリ側で「Edit Plan」からRe-Nameすると、「Edit Plan」内リスト・「Select Plan」内リストの表示名は更新されるが、①既に登録済みのPassage Plan自体の表示名、②地図左上固定の凡例ボックス（タイトル「Passage Plan」の下に表示される各プラン名）は旧名のまま反映されない。2026-07-27時点では「登録済みプランの表示名はCSVファイル名固定・別物」という仕様としてユーザー確認済み（現状維持でOKとされていた、旧TASKS.mdの「決定待ち」参照）だったが、実際に使ってみて不整合が気になったとのことで、次回改めて実装する（Re-Name時に登録済みプランの表示名にも反映させる方向で）。関連：`lib/utils/csv_library.dart`（Rename処理）・登録済みPassage Planの表示名を持つ構造体・`lib/screens/map_screen.dart`の凡例ボックス描画箇所。

## 決定待ち・要確認事項

- スマホ対応（Android/iOS）は機能・デザインをデスクトップ版と極力共通にし、横向き固定・画面サイズ差分とタッチ操作のみ個別調整する方針（仮、`docs/devlog-architecture-roadmap.md`参照）。着手時に改めて確認
- より高精細な海岸線データ（1:10m相当）への差し替え（優先度低、`docs/devlog-map-design.md`参照）
- 航海計画編集画面の緯度経度入力は現在10進度（decimal degrees）。他画面の度分（deg-min）表記と揃えるかは今後ユーザーに確認
- 船アイコンを色ごとに10種類（専用PNG画像）用意したい、とのユーザー希望あり。現在は`assets/ship_icon01.png`を`ColorFilter`で機械的に着色しているだけなので、専用画像を用意する場合はカラーコード一覧（`docs/devlog-passage-plan-multi.md`参照）に合わせて作成し、画像が揃い次第、着色方式から画像切替方式へ変更するか相談する
