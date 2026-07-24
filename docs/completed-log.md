# completed-log.md — 完了記録

宣言2（記録の4分割）の④を担当。1件につき日付・結論1〜2行。詳細は該当`docs/devlog-<テーマ>.md`にリンクする。

書式：
`**タイトル**（日付、コミットハッシュ、該当すればブランチ名）— 結論1〜2行。詳細は`docs/devlog-xxx.md`（devlogを作らない軽微な変更なら省略）。`

---

**プロジェクト運用の土台構築**（2026-07-25）— 5つの宣言（`docs/project-declarations.md`）に基づき、CLAUDE.md／TASKS.md／`docs/operation-rules.md`（本プロジェクト用に書き換え）／`docs/completed-log.md`を整備。技術スタック（Flutter、デスクトップ先行）、セッション構成（単一セッションで進行管理とコーディングを兼務）、Flutterプロジェクトパス（`typhoon_ship_tracker/`、英数字のみ）を決定。ブートストラップ用の`CLAUDE.md追記スニペット.md`は内容反映済みのため削除。

**Flutter×Windows環境メモの反映**（2026-07-25）— ユーザー提供の`flutter-windows-env-notes.md`（Flutter SDK/Android SDKパス、AVD名、`flutter analyze`クラッシュ問題、`.bat`/git操作の既知の落とし穴等）を`docs/`に保存し、CLAUDE.mdのセッション開始チェックリストと環境構成、`docs/operation-rules.md`の完了報告前チェック・git運用から参照するよう反映。

**地図表示・距離計算・データ取得方式の決定**（2026-07-25）— 以前のチャットでの検討内容（中分緯度法での距離計算、簡易プロット版の地図表示、表示範囲N20-50/E115-150固定、JMA防災情報XML＋JTWCテキストのWi-Fi時取得＋オフラインキャッシュのハイブリッド方式）をCLAUDE.mdの現状要約に反映し、詳細な経緯・判断根拠は`docs/devlog-map-design.md`に退避。TASKS.mdも実際の設計に合わせて更新。
