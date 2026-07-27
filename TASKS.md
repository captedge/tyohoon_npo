# TASKS.md — 進行中・次にやること

宣言2（記録の4分割）の②を担当。**このファイルは「未着手・進行中のタスク」と「決定待ち・要確認事項」だけを置く。** 完了したタスクはチェックを付けた時点でここから除去し、`docs/completed-log.md`に1〜2行で記録する（詳細な経緯・技術的な学びがある場合は該当`docs/devlog-<テーマ>.md`へ）。仕様調査結果（CSV/XML形式など）のような「参照資料」は`docs/data-format-notes.md`に集約する。

## 未着手・進行中

- [ ] （仮方針・変更可能性あり）オンライン化を先に完了・マージしてからモバイル対応に着手する進め方で合意（`feature/online-xml`→マージ→`feature/mobile`。詳細は`docs/devlog-architecture-roadmap.md`参照）
- [ ] 気象庁「防災情報XML」の詳細スキーマ調査・パース実装（電文種類VPTW60。仕様・次のステップは`docs/data-format-notes.md`参照。自動取得はアプリ内ON/OFF設定として実装し、OFF/取得不可時は既存のJTWC手動貼り付けにフォールバックする方針）
- [ ] JTWC（米軍）テキストページの読込・パース（日時・緯度経度を抽出。抽出パターンは既に`lib/utils/jtwc_parser.dart`に実装済み・仕様は`docs/data-format-notes.md`参照。今回追加するのはページ取得＝定期フェッチ部分）
- [ ] Wi-Fi時まとめ取得＋オフラインキャッシュの仕組み設計
- [ ] 台風データの実データ接続（JMA防災情報XML・JTWCページ取得）を`MapScreen`に反映（`lib/screens/map_screen.dart`の`_trackPointsForSlot`参照。サンプルフォールバックは2026-07-27に廃止済み）
- [ ] CSVライブラリの上限50件到達時のエラー表示のみ未確認（他の全項目はWindows実機で確認済み、`docs/completed-log.md`参照）。50件貯める機会があれば確認する

## 決定待ち・要確認事項

- スマホ対応（Android/iOS）は機能・デザインをデスクトップ版と極力共通にし、横向き固定・画面サイズ差分とタッチ操作のみ個別調整する方針（仮、`docs/devlog-architecture-roadmap.md`参照）。着手時に改めて確認
- より高精細な海岸線データ（1:10m相当）への差し替え（優先度低、`docs/devlog-map-design.md`参照）
- 航海計画編集画面の緯度経度入力は現在10進度（decimal degrees）。他画面の度分（deg-min）表記と揃えるかは今後ユーザーに確認
- Passage Plan「登録済みプラン」自体の名前は現状CSVファイル名固定（拡張子除く）で、後から改名するUIは未実装（Renameが可能なのはCSVライブラリ側のファイル名のみで、既に登録済みのプランの表示名には反映されない仕様でユーザー確認済み・現状維持でOK、2026-07-27）。将来的に改名したい場合は別途要望を
- 船アイコンを色ごとに10種類（専用PNG画像）用意したい、とのユーザー希望あり。現在は`assets/ship_icon01.png`を`ColorFilter`で機械的に着色しているだけなので、専用画像を用意する場合はカラーコード一覧（`docs/devlog-passage-plan-multi.md`参照）に合わせて作成し、画像が揃い次第、着色方式から画像切替方式へ変更するか相談する
