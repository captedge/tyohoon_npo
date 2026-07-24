# Flutter × Windows × Cowork 技術メモ（持ち運び用）

**位置づけ**：`project-declarations.md`（汎用の運用宣言）・`project-setup-lessons.md`（汎用のセッティング教訓）とは別に、「Flutterアプリ開発」かつ「このWindows機」かつ「Cowork」という組み合わせに固有の技術的な事実・回避策だけをまとめたもの。

**使い方**：次のプロジェクトが同じ組み合わせ（Flutter × このWindows機 × Cowork）の場合のみ渡す。技術スタックが違う（Web・note・動画編集等）プロジェクトでは無関係なので渡す必要はない。

---

## 環境構成（このWindows機での実績）

- **Flutter SDK**: `C:\Users\KOTA\flutter_sdk\flutter`（PATHはユーザー環境変数に追加済み。新しいPowerShellセッションでは反映されないことがあるため、その場合は `$env:Path += ";$env:USERPROFILE\flutter_sdk\flutter\bin"` を都度実行）
- **Android SDK**: `%LOCALAPPDATA%\Android\Sdk`（`ANDROID_SDK_ROOT` / `ANDROID_HOME` 環境変数に設定済み）
- **Android Studio**: `C:\Program Files\Android\Android Studio`（JDKもここに同梱。`JAVA_HOME` はここの `jbr` を指す）
- **AVD名**: `ShipsTime_Test`（Pixel 6 / Android 15 / google_apis / x86_64。複数プロジェクトで共用可）

## Flutter固有の既知の癖・回避策

1. **プロジェクトパスは常に半角英数字のみ**（日本語・アポストロフィ禁止）。Dart解析サーバーやaaptが壊れる。新規プロジェクトは英数字名のフォルダ（サブフォルダで可）を用意する。
2. **`flutter analyze`はクラッシュする既知の問題**（無害）。スキップして`flutter run`/`flutter build`の実行確認で代替する。
3. **`build/`・`.dart_tool/`など大量の小ファイルの削除はCoworkのサンドボックスから失敗する**（`rm -rf`が"Operation not permitted"で1バイトも消せないことがある）。ユーザーがPowerShellで`Remove-Item -Recurse -Force build, .dart_tool`を実行する（どちらもビルド時に自動再生成される）。肥大化していたらセッション開始時にユーザーへ整理を提案する。
4. **サードパーティAndroidプラグイン追加時は`pubspec.lock`で実際に解決されたバージョンとchangelogを確認する**（`^`指定でもマイナーバージョンでpublic APIのエクスポート先が変わることがある）。
5. **エミュレータのHome/Back操作はcomputer-useから効かない**。ホーム画面ウィジェット等「ランチャーのホーム画面に置く」検証は、ユーザーが実機に`build_apk.bat`等でインストールして確認する。

## このWindows機・Cowork運用での一般的な注意（Flutter固有ではないが同じ組み合わせで毎回発生する）

1. **PowerShell/ターミナルアプリはcomputer-useから「click」権限までしか付与されない**。キー入力・貼り付け・Ctrl+Cは不可。コマンド実行やコンソール強制終了は必ずユーザー本人が行う（Claudeは「これを貼り付けてEnterを押してください」と依頼する形になる）。
2. **ファイル内容の検証は必ずReadツール（Windowsパス）を使う**。サンドボックスの`bash`経由の読み取り（`cat`/`grep`/Pythonの`open`、`git diff`/`git status`も含む）は、無傷なファイルが途中で切れて見えたり、触っていないファイルまで大量差分ありと出ることがあり信頼できない。`bash`はビルド・画像処理などの実行専用と割り切る。
   - **画像ファイルで特に注意**：上書き保存直後はサンドボックス側が古い内容をキャッシュすることがある（Readでは正常なのにbashで開けない状態が目印）。対策：別名保存。
3. **バッチファイル(.bat)内には日本語を一切書かない**（echoメッセージだけでなく`git add`のファイルパスなど引数に含めた場合も同様に文字化けしてコマンド誤認識を起こす）。日本語が必要な内容は別ファイル（例：`commit_message.txt`）に逃がし、`.bat`側はASCIIのファイル名・引数だけを渡す。括弧`( )`ブロックの中にラベルと`goto`を両方置かない（ループ用ラベルは必ず括弧の外に置く）。
4. **サンドボックスからの単一ファイル削除も「Operation not permitted」で失敗することがある**（大量削除に限らない）。`allow_cowork_file_delete`ツールで削除許可を得てから再実行する。
5. **git操作（add/commit/push）はプロジェクト直下の`commit.bat`経由でユーザーが実行する**（サンドボックスからの直接書き込みは`.git/index.lock`エラー等で信頼できない）。`commit.bat`は`git add`→`git commit -F commit_message.txt`→`git push`まで1本にまとめる。日本語のコミットメッセージは`commit_message.txt`（`.gitignore`済み）に分離する。`git add`の対象は初回コミット以外`git add .`を使わず、Claudeが毎回変更ファイルを明示的に列挙する。**ファイル名に日本語が含まれる場合は`.bat`の引数に書けない（ルール3）ため、`git add -u`（追跡済みファイルの変更・削除のみをステージ、日本語ファイル名でも安全）＋新規ファイルのみASCIIパスで個別に`git add`する組み合わせを使う。**
6. **新規リポジトリの初回コミットでは`git config --global user.name`/`user.email`が未設定でエラーになることがある**。エラーが出たら設定してから再実行する。
