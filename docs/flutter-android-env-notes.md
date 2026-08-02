# Flutter × Android × Cowork 技術メモ（持ち運び用）

**位置づけ**：`flutter-windows-env-notes.md`のAndroid版。「Flutterアプリ開発」かつ「このWindows機」かつ「Android向けビルド」の組み合わせに固有の技術的な事実・回避策をまとめたもの。共通の環境情報（Flutter SDK/Android SDKパス、Android Studio、AVD名）は重複させず`flutter-windows-env-notes.md`側を参照する。

**出典**：この機で先に作られた別プロジェクト「ShipsTime」（`C:\Users\KOTA\Desktop\Claude Code\ShipsTime`）が同じWindows機・同じCowork運用でAndroidビルドを一通り経験済みだったため、2026-08-02にその`docs/devlog-setup-issues.md`・`android/`設定一式を調査し、本プロジェクトに関係する部分を移植・記録した（`docs/devlog-mobile-flutter.md`参照）。

## 本プロジェクトに直接影響する既知の問題・対策

1. **`file_picker`プラグイン（本プロジェクトが使用中、`^8.1.2`指定・実解決版`8.3.7`）のAndroidビルドで既知の不具合が起きる可能性が高い**：`file_picker`自身の`android/build.gradle`が`com.android.library`は適用するがKotlin Androidプラグインを適用しておらず、`.kt`ファイルがコンパイルされないため`GeneratedPluginRegistrant.java`が`cannot find symbol FilePickerPlugin`で失敗する（[flutter_file_picker#1973](https://github.com/miguelpruivo/flutter_file_picker/issues/1973)・[#1952](https://github.com/miguelpruivo/flutter_file_picker/issues/1952)、ShipsTimeでは`11.0.2`時点でも再現を確認済み）。バージョンを跨いだ長期未修正の不具合と見られ、`android/`生成直後・実際のビルド前に予防的に対策コードを追加済み（`android/build.gradle.kts`、内容は下記1bの隣に実装）。

1b. **`file_picker`の別の既知の問題（compileSdk要求）を2026-08-02に実際に確認・修正**：`build_apk_personal.bat`実行で`:file_picker:checkReleaseAarMetadata`が`FAILURE`——「`file_picker`の依存`flutter_plugin_android_lifecycle`はcompileSdk 36以降を要求するが、`file_picker`自体はandroid-34でコンパイルされている」というエラーで失敗した。これは上記1（Kotlinプラグイン未適用問題）とは別の問題で、ShipsTimeが`alarm`パッケージの依存`flutter_fgbg`で踏んだのと同種の「プラグインのcompileSdk要求」パターン（`docs/devlog-setup-issues.md`＠ShipsTime項目12）。
   **対策（適用済み）**：
   - `android/app/build.gradle.kts`：`compileSdk = flutter.compileSdkVersion` → `compileSdk = maxOf(flutter.compileSdkVersion, 36)`
   - `android/build.gradle.kts`：`:app`以外の全サブプロジェクト（＝プラグインモジュール）のcompileSdkを36に強制する`subprojects`ブロックを追加（`:app`自体は`evaluationDependsOn`との競合を避けるため除外——`Cannot run Project.afterEvaluate(Action) when the project is already evaluated`エラーになるため）：
   ```kotlin
   subprojects {
       if (project.path != ":app") {
           afterEvaluate {
               extensions.findByType<com.android.build.gradle.BaseExtension>()?.let { android ->
                   android.compileSdkVersion(36)
               }
           }
       }
   }
   ```
   アプリ側のcompileSdk引き上げだけでは不十分で（`file_picker`自身のモジュールのAARメタデータチェックは別）、この`subprojects`ブロックも合わせて必要だった。

   **上記1の対策コード（`android/build.gradle.kts`に実装済み）**：
   ```kotlin
   // Workaround for a known upstream bug in the file_picker Android plugin
   // (see https://github.com/miguelpruivo/flutter_file_picker/issues/1973 and
   // .../issues/1952). Safe to remove once file_picker ships a real fix.
   subprojects {
       plugins.whenPluginAdded {
           if (this is com.android.build.gradle.LibraryPlugin) {
               if (!project.plugins.hasPlugin("org.jetbrains.kotlin.android")) {
                   project.plugins.apply("org.jetbrains.kotlin.android")
               }
               project.extensions.findByType(org.jetbrains.kotlin.gradle.dsl.KotlinAndroidProjectExtension::class.java)
                   ?.compilerOptions {
                       jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
                   }
           }
       }
   }
   ```
   **教訓**：1（Kotlinプラグイン未適用）は予防的に対策できたが、1b（compileSdk要求）はShipsTimeの記録に無い新規パターンで、実際にエラーを踏んでから特定した。同じ`file_picker`でも複数の独立した既知問題が重なりうるため、1つ対策しても別のエラーが出ることがある——1回のビルド失敗で「全部潰した」と判断せず、次のビルドも注意深く見る。

2. **`.bat`から`flutter`コマンド（実体は`flutter.bat`）を呼ぶときは必ず`call`を付ける**：`call`を付けずに呼ぶと、そのコマンドが終わった時点で呼び出し元`.bat`の残りの行が一切実行されずに終了する（エラー表示なし、成功したように見えて後続処理だけ静かにスキップされるのが特徴）。本プロジェクトの`build_release.bat`は元々`call`を使っており問題なし。新設した`build_apk.bat`／`build_apk_personal.bat`／`run_android.bat`／`run_android_personal.bat`／`create_mobile_branch.bat`も全て`call`済み。

3. **NDK（Native Development Kit）は本プロジェクトでは不要**：使用中のパッケージ（`file_picker`／`shared_preferences`／`path_provider`／`xml`／`cupertino_icons`）はいずれもネイティブ（NDK）コードを含まない。`flutter create`が生成する`android/app/build.gradle.kts`に`ndkVersion = flutter.ndkVersion`の行が入っていたら、明示的な理由がない限り削除を検討する——NDKの自動ダウンロードは約750MBと重く、前問でお伝えした「大きなダウンロード」の主要因になりうる（回線が不安定だと`sdkmanager`経由のダウンロードがタイムアウトしやすいこともShipsTimeで確認済み）。

4. **`android/gradle.properties`の`android.overridePathCheck=true`は候補的な対策として記録（原因未確定）**：ShipsTimeの`gradle.properties`にこの設定が入っていたが、なぜ追加したかを示すdevlog記録が見つからなかった（`flutter create`が自動追加した可能性もある）。ShipsTimeのプロジェクトパスも本プロジェクトと同様に祖先パスに空白を含む（`C:\Users\KOTA\Desktop\Claude Code\...`）。もしAndroidビルドでパス関連のエラーが出た場合、この設定を候補として試す価値はあるが、確証がないため予防的な追加はせず、実際に問題が起きてから検討する（宣言1の「確認できることは事前に」に対し、これは「確認できない/根拠不明」に該当するため）。

5. **`gradle.properties`のJVMメモリ設定はそのまま流用可能**（このマシンでのGradleビルドで確認済みの値）：
   ```
   org.gradle.jvmargs=-Xmx8G -XX:MaxMetaspaceSize=4G -XX:ReservedCodeCacheSize=512m -XX:+HeapDumpOnOutOfMemoryError
   ```

6. **リリース署名は当面デバッグ鍵のままでよい**：ShipsTimeも`signingConfig = signingConfigs.getByName("debug")`（TODOコメント付き）のまま運用している。Google Play正式配布の段階になったら本番用の署名鍵を別途用意する（`docs/completed-log.md`の「今後」参照）。

## 参考：ShipsTimeで確認済みだが今のところ本プロジェクトに直接関係しない事項

（`docs/devlog-setup-issues.md`＠ShipsTimeより。該当する場面が来たら参照する）

- `sdkmanager --licenses`の対話プロンプトが不安定 → `%LOCALAPPDATA%\Android\Sdk\licenses\`配下にライセンスハッシュファイルを直接作成する方法がある（このマシンは既にライセンス承諾・SDK導入済みのため、通常は再発しない見込み）
- 回線が不安定な環境でのダウンロードは`curl.exe --retry --retry-all-errors -C -`（レジューム可能）が確実
- エミュレータのスナップショットが壊れて操作不能になることがある → `-no-snapshot`起動＋`snapshots\default_boot`削除で対策済み（`run_android.bat`に反映済み）
- エミュレータウィンドウが画面外に開くことがある → `fix_emulator_window.ps1`（本プロジェクトにも移植済み、共有AVD`ShipsTime_Test`のウィンドウタイトルにそのままマッチする）
- Coworkサンドボックスから既存のバイナリアセット（画像等）を同名で上書き・削除できないことがある → 新規ファイル名で保存し参照側を向け直す方式で回避（本プロジェクトの`docs/operation-rules.md`の削除関連の教訓と同種）
