# TASKS.md — 進行中・次にやること

宣言2（記録の4分割）の②を担当。**このファイルは「未着手・進行中のタスク」と「決定待ち・要確認事項」だけを置く。** 完了したタスクはチェックを付けた時点でここから除去し、`docs/completed-log.md`に1〜2行で記録する（詳細な経緯・技術的な学びがある場合は該当`docs/devlog-<テーマ>.md`へ）。仕様調査結果（CSV/XML形式など）のような「参照資料」は`docs/data-format-notes.md`に集約する。

## 未着手・進行中

- [ ] 海上気象データソースの追加、①沿岸波浪予報（JMA地方海上予報＝VPCY51）から着手（2026-07-29着手）。表示範囲南側（フィリピン近海、北緯5〜19°）は地方海上予報区の対象外のため非表示のままとする方針を確認済み（2026-07-29）。予報区ポリゴンデータ・区域名定数・電文パーサー（`lib/utils/marine_areas.dart`／`marine_area_codes.dart`／`jma_marine_xml_parser.dart`）は実装済み——経緯・詳細は`docs/completed-log.md`と`docs/devlog-online-xml.md`参照。**次にやること**：
  - [ ] `regular.xml`の実データ裏取り・パーサーの実データ確認（最優先）：Coworkサンドボックスからは古いキャッシュしか取得できず未達成（`docs/data-format-notes.md`「Cowork環境からのregular.xml取得の制約」参照）。Windows実機でアプリ自身がHTTPリクエストする形（「Import」相当の機能を作って）で確認する。パーサーは公式PDFの記載のみに基づく未検証実装で、Agentレビューで一度実バグ（Area要素の探索方向の誤り）が見つかっている（`docs/devlog-online-xml.md`「Dartパーサー実装・Agentレビューで発見したバグ」参照）——他にも同種の見落としが無いか、実データでの確認時に注意する。
  - [ ] `MapPainter`への予報区ポリゴン塗り分け描画追加、Informationダイアログへの取得UI追加（上記の実データ確認が済んでから着手するのが望ましい）。
  - [ ] ②黒潮＝海しるAPI、③気圧配置図は未着手（`docs/devlog-online-xml.md`参照）。
  - 本流（配布可能・Open-Meteo機能無し）と個人用（Open-Meteo機能あり・配布しない）は`--dart-define`のコンパイル時フラグで分岐し、ブランチは分けない。
- [ ] CSVライブラリの上限50件到達時のエラー表示のみ未確認（他の全項目はWindows実機で確認済み、`docs/completed-log.md`参照）。50件貯める機会があれば確認する
- [ ] （Windows実機確認待ち）複数台風同時発表対応・Import Allボタン（2026-07-29実装、1件のみの場合の動作は実機確認済み）：「Import All (JMA)」「Import All (JTWC)」で2件以上同時に見つかった場合、Typhoon 1/2/3それぞれ独立してDisplay On/Off切替できるか（コード上は独立していることを確認済みだが実機未確認）。あわせて完了メッセージ「Imported to Typhoon 1, 2」等の表記も確認。「Fetch」→「Import」への表記統一箇所（Import from JMA/JTWC、Import All）も見た目を確認。

## 決定待ち・要確認事項

- スマホ対応（Android/iOS）は機能・デザインをデスクトップ版と極力共通にし、横向き固定・画面サイズ差分とタッチ操作のみ個別調整する方針（仮、`docs/devlog-architecture-roadmap.md`参照）。着手時に改めて確認
- より高精細な海岸線データ（1:10m相当）への差し替え（優先度低、`docs/devlog-map-design.md`参照）
- 航海計画編集画面の緯度経度入力は現在10進度（decimal degrees）。他画面の度分（deg-min）表記と揃えるかは今後ユーザーに確認
- Passage Plan「登録済みプラン」自体の名前は現状CSVファイル名固定（拡張子除く）で、後から改名するUIは未実装（Renameが可能なのはCSVライブラリ側のファイル名のみで、既に登録済みのプランの表示名には反映されない仕様でユーザー確認済み・現状維持でOK、2026-07-27）。将来的に改名したい場合は別途要望を
- 船アイコンを色ごとに10種類（専用PNG画像）用意したい、とのユーザー希望あり。現在は`assets/ship_icon01.png`を`ColorFilter`で機械的に着色しているだけなので、専用画像を用意する場合はカラーコード一覧（`docs/devlog-passage-plan-multi.md`参照）に合わせて作成し、画像が揃い次第、着色方式から画像切替方式へ変更するか相談する
