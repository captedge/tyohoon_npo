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

**Windows実機初回動作確認・レビュー反映**（2026-07-26）— `flutter run -d windows`がVisual Studio導入後に成功。操作性・台風表示は好評。フィードバックを受けて航海計画の点線＋Waypointマーカー（`_drawShipRoute`）と、画面上部固定の日時表示（`dd mmm. yyyy HH:MM (JST)`形式）を追加実装。海岸線の陸海配色・船アイコンのデザインは今後相談として`TASKS.md`に記録。

**航海計画CSVの実サンプル確認**（2026-07-26）— ユーザー提供の実ファイル（`013K378NEG W-KII.csv`）で列構成を確認。公式マニュアル通りJRC ECDIS純正フォーマットで、日時列は無し。出発日時1回入力＋区間距離÷速力での到着時刻積算という設計方針を決定。詳細は`TASKS.md`「実サンプルで確認できた列構成」参照。

**マウスホイールズーム・縦スライダーの追加、JRC ECDIS/NAVTOR CSV調査**（2026-07-26）— ユーザーからの操作性の質問を受け、`map_screen.dart`にマウスホイールでのズームと縦方向のズームスライダーを追加（＋／－ボタンと同じ`_zoom`状態で同期）。あわせて型エラー（`clamp`が`num`を返す問題）を修正。JRC ECDIS純正ルートCSV書式を公式マニュアルで調査し、列構成（WP No/Lat/Lon/Prt/Stb/Arr Rad/Speed/Sail）を確認。ただしETA/ETD列は純正書式に含まれないため、実サンプル確認が必要と判明（詳細は`TASKS.md`参照）。

**Flutterプロジェクト雛形＋地図画面の初期実装**（2026-07-26）— `typhoon_ship_tracker/`に`pubspec.yaml`と`lib/`（models/track_point.dart、utils/interpolation.dart・map_bounds.dart、widgets/map_painter.dart、screens/map_screen.dart、main.dart）を作成。中分緯度法での距離計算、前後2点の線形補間、グリッド＋仮海岸線の描画、InteractiveViewer＋＋／－ズームボタン、再生／一時停止トグル付き時刻スライダーを実装。海岸線は実データ未選定のため仮ポリゴン（`TODO(map-data)`）。自己レビューで`Path.extractPath`への引数型エラー（`num`→`double`）を発見・修正済み。OSプラットフォーム雛形（`windows/`等）は`flutter create`が必要でサンドボックスでは生成不可のため、ユーザー側での実行待ち。気象庁「防災情報XML」の電文種類（VPTW60）と提供形態（PULL型・無認証）を調査、詳細は`TASKS.md`参照。
