# devlog: 保存先をzip内（exe相対のDataフォルダ）に変更

## 発端（2026-08-01）

ユーザーから「生成したzipインストーラーで、データ取得し『Data』に情報が蓄積した状態で他のデバイスPCへフォルダごとコピーしても、データが反映されず取り直しになる。そういう仕様か？」という質問。

## 原因調査

実装（`app_state_storage.dart`・`csv_library.dart`・`wave_field_cache.dart`）を確認したところ、いずれも保存先はWindowsの「そのユーザーのAppDataフォルダ」（`shared_preferences_windows`および`path_provider_windows`の`getApplicationSupportDirectory()`が解決する場所）であることを確認。実際のパスは`windows/runner/Runner.rc`の`CompanyName`（`"com.example"`、Flutterのデフォルトプレースホルダのまま未変更）と`ProductName`（`"typhoon_ship_tracker"`）から`C:\Users\<ユーザー名>\AppData\Roaming\com.example\typhoon_ship_tracker\`に解決される。zipを展開したフォルダの外側にあるため、フォルダごとコピーしても付いてこない。

この設計は事故ではなく、`csv_library.dart`の既存doc commentに明記の通り「zipを新しいビルドに差し替えてもデータが消えないように」という意図的な選択だった（2026-07-27時点の判断）。

なお、解凍したフォルダ内に見える「data」フォルダ（小文字）はFlutterエンジン本体・アセットの出力であり、ユーザーが蓄積した台風情報やCSVはここには入っていない（紛らわしいが無関係）。

## 検討したトレードオフ（ユーザーに事前説明し合意を得た内容）

保存先をexe相対の`Data`フォルダに変更する場合、次の2点を許容する前提で進めることをユーザーに確認済み：

1. **`clean_project.bat`（`flutter clean`）を実行するとデータが消える**：`build`フォルダごと削除するため。ただし普段の`build_release.bat`/`run_windows.bat`は出力フォルダの不要ファイルを消さないので、この時だけの影響（手動・低頻度の操作）。
2. **Debug版とRelease版でデータが別になる**：`build\windows\x64\runner\Debug\`と`...\Release\`は別フォルダのため、それぞれが自分の`Data`フォルダを持つ。これまではAppData経由でDebug/Release間もデータを共有していたが、今後は共有されない。

ユーザー回答：「では一度『保存先をzip内に変更する』にします」（2026-08-01）。

## 実装内容

新設: `lib/utils/portable_storage_dir.dart`
- `appDataDir()`：Windowsでは実行ファイル（`Platform.resolvedExecutable`）と同じフォルダ内の`Data`サブフォルダ（なければ作成）。Windows以外（将来のモバイル対応時）は従来通り`path_provider`の`getApplicationSupportDirectory()`（モバイルには「ポータブルフォルダ」という概念が存在せず、各アプリは既にデバイスごとの専用ストレージを持つため、この変更の対象外）。
- `legacyAppDataDir()`：変更前の保存先（`getApplicationSupportDirectory()`）を返すだけの薄いラッパー。以下の一度きりの移行読み込みのためだけに残す。

変更した3箇所（いずれも`appDataDir()`を使うよう切替）：
- `app_state_storage.dart`：`SharedPreferences`経由の保存をやめ、`Data/app_state.v1.json`への直接ファイル書き込みに変更。`load()`は新ファイルが無い場合（Windowsのみ）、旧`SharedPreferences`キー（`typhoon_ship_tracker.app_state.v1`）を一度だけ読み、成功したらそのJSON文字列をそのまま新ファイルにも書き込む（コピーフォワード）。
- `csv_library.dart`：保存先を`Data/csv_library/`に変更。新フォルダが空、かつ旧`csv_library`フォルダにファイルがある場合、一度だけファイルをコピー（移動ではなくコピー——旧ファイルは残置、安全側に倒した）。`_migrationChecked`静的フラグでアプリ起動中1回だけ実際にチェックする。
- `wave_field_cache.dart`（個人用ビルドのみ）：保存先を`Data/wave_field_cache.json`に変更。新ファイルが無ければ旧ファイルを一度だけ読み、コピーフォワード。

いずれも「移行に失敗してもその場のセッションでは読み込んだ内容をそのまま使う」設計（コピーフォワードの書き込み自体が失敗しても、読み込みは成功していれば動作に支障がない）。

**`pubspec.yaml`**：`shared_preferences`パッケージ自体は削除せず維持（上記の一度きりの移行読み込みで引き続き使うため）。コメントを更新し、現在の役割が「移行読み込み専用」であることを明記。

**`build_release.bat`／`build_release_personal.bat`の見落とし防止（実装中に発見・対応）**：`Data`フォルダはアプリ初回起動時にexeの隣に作られるため、素のビルド直後は存在しないが、開発者自身が`build\windows\x64\runner\Release\`のexeをローカルで一度でも実行してテストデータを溜めていた場合、そのまま`Compress-Archive -Path 'Release\*'`でzip化すると**開発者自身のテストデータが配布用zipに混入する**リスクがあった。両バッチとも`Get-ChildItem -Path 'Release' -Exclude 'Data' | Compress-Archive ...`に変更し、`Data`フォルダを常にzipから除外するよう修正。

## 教訓

- ポータブルEXE配布（zip展開してそのまま動かす形）では、永続化先を「exe相対」にするか「OSのユーザープロファイル配下」にするかは、①別デバイスへのフォルダコピーで持ち運びたいか、②アプリ更新（フォルダ差し替え）でデータを保持したいか、の優先順位で決まるトレードオフであり、着手前にどちらを優先するかをユーザーに確認してから実装するのが良い（今回は事後に気づいて仕様として説明→変更の順になったが、次回同種のポータブルアプリでは最初の設計時点でこの二択を明示的に確認する）。
- 保存先をexe相対に変えると、**配布用ビルドスクリプトが開発者自身のローカルデータを誤って同梱してしまわないか**を必ず確認する。今回は`build_release.bat`のzip化コマンドが単純な`-Path 'Release\*'`だったため、対策が漏れていれば個人情報混入のリスクがあった（実際に発見し対応済み）。
- 保存先を変更する際は、既存ユーザー／既存の開発環境に既にデータが溜まっている場合の「一度きりの移行読み込み」を、需要が小さくてもコストが低いなら入れておくと、情報が理由なく消えたように見える事態を避けられる（今回は3箇所ともコピー方式で対応、削除は行わずコピーのみで安全側に倒した）。

## Agentレビュー（実装直後、複数ファイル・非同期フローにまたがる変更のため）

`docs/operation-rules.md`項目5の方針通り、実装完了時点でAgentツール（general-purpose）による独立レビューを実施。指摘2件を反映済み：

1. **（重大）`build_release.bat`／`build_release_personal.bat`のzip除外が効いていなかった**：PowerShellの`Get-ChildItem -Exclude`は`-Path`にワイルドカード（`\*`）が無いと機能しないという既知の挙動があり、当初の`-Path 'Release'`のままでは`Data`フォルダが除外されずzipに混入する状態だった。`-Path 'Release\*'`に修正して対応。今回の変更の目的そのものに関わる指摘だったため優先度高。
2. **（軽微）`app_state_storage.dart`の`load()`で、ファイル読み込み・移行処理がtry/catchの外にあった**：IO例外（権限エラー等）が発生した場合、doc commentが約束する「fails safe（クラッシュせずnullを返す）」が保証されていなかった。ファイル読み込み・移行処理を既存のtry/catchの内側に含めるよう修正し、メソッド全体を1つのtry/catchで覆う形に統一。

Coworkサンドボックス（Dart SDKなし・PowerShellなし）のため、修正後の実行検証は未実施——下記のWindows実機確認が必要な項目でカバーする。

## 命名衝突バグの発覚と修正（2026-08-01、ユーザーのWindows実機テストで発覚）

Agentレビュー後、ユーザーが実際に`build_release_personal.bat`でビルド・zip化・展開・exe起動を行ったところ、「アプリが立ち上がらないです windows11」と報告（ウィンドウ自体が一切表示されない）。

**調査**：`run_windows.bat`のコンソール出力を確認してもらったところ、ビルド自体（`flutter build windows --release`）は`Built build\windows\x64\runner\Release\typhoon_ship_tracker.exe`と正常完了しzipも生成されていた——つまりDartのコンパイルエラーではない。ビルドは通るのに、生成されたzipを展開して実行すると起動しないという事実から、**zip化の過程で何か必須ファイルが欠落している**可能性を検討し、コードを見直した。

**根本原因**：`portable_storage_dir.dart`の保存先フォルダ名を当初`Data`（大文字始まり）にしていたが、Flutterはビルドのたびにexeと同じフォルダに`data`（小文字）という名前のフォルダを自動生成し、そこに`icudtl.dat`・`flutter_assets`一式などアプリの起動に必須なファイルを格納する。**Windowsのファイルシステムは大文字小文字を区別しない**ため、`Data`と`data`は同じフォルダとして扱われる。つまり：
1. アプリ実行時、`appDataDir()`が「`Data`フォルダを作る」つもりで実際にはFlutter自身の`data`フォルダ（既に存在）を掴み、CSVライブラリ・設定JSON・波の場キャッシュをその中に書き込んでいた（実害としては起動可能な状態ではまだ表面化しない）。
2. `build_release.bat`／`build_release_personal.bat`に追加した`-Exclude 'Data'`（開発者のローカルテストデータをzipに混入させないための対策）が、大文字小文字を区別しないマッチングにより、この`data`フォルダ（Flutter本体が必要とする一式を含む、実質同一フォルダ）ごとzipから除外してしまっていた。
3. 結果、配布用zipから起動に必須なファイルが丸ごと消え、展開後にexeを実行してもアプリが起動しない（ウィンドウが一切表示されない）状態になっていた。

**対策**：保存先フォルダ名を`Data`から`UserData`に変更（Flutterが使う`data`と衝突しない名前）。`portable_storage_dir.dart`・`app_state_storage.dart`・`csv_library.dart`・`wave_field_cache.dart`のコメント、`build_release.bat`／`build_release_personal.bat`の`-Exclude`パターン、`CLAUDE.md`／`TASKS.md`をあわせて更新。

**教訓**：
- **ポータブルアプリで独自の保存フォルダ名を決める際は、ビルドツール（今回はFlutter）が同じ場所に自動生成する既存フォルダ名と、大文字小文字を区別しない前提で衝突しないか必ず確認する**。今回は「わかりやすさ」だけで`Data`という名前を選び、Flutter自身の`data`フォルダの存在を見落としていた。
- **ビルドが成功する（コンパイルが通る）ことと、生成された配布物が実際に動作することは別物**。特に今回のようにビルド後処理（zip化・ファイル除外）で問題が起きるケースは、Dartコードの静的チェックだけでは発見できない。Coworkのサンドボックスでは配布物の実行検証ができないため、この種の変更は特に「実際にビルド→展開→起動」まで一度実機で確認してもらうまでは未検証であるという前提で報告すべきだった。
- ユーザーからの「アプリが立ち上がらない」という報告に対し、まずrun_windows.bat（コンパイルエラーの有無を確認する目的）のコンソール出力を求めたのは正しい切り分けだったが、実際にはビルドスクリプト自体の副作用（zip除外）が原因だったため、「コンパイルは通っている」と分かった時点で、ビルド後処理（zip化・パッケージング）側も疑う判断に切り替える必要があった。

## zip化でdataフォルダが欠落する2件目の不具合（2026-08-01、ユーザーの追加検証で発覚）

`UserData`への改名後も、生成された`TyphoonShipTrackerPersonal.zip`を展開したexeが起動しない状態が続いた。ユーザーに切り分けを依頼した結果：

- `build\windows\x64\runner\Release\`のexeを直接（zipを介さず）実行すると**正常に起動する**。
- そのフォルダには`data`（Flutter本体、小文字）と`UserData`（本アプリの保存先）が別々のフォルダとして共存しており、名前の衝突は解消済みと確認できた（スクリーンショットで確認）。
- しかし生成されたzipの中身を確認すると、`data`フォルダが**入っていない**（`UserData`は正しく除外されていたが、`data`まで一緒に失われていた）。

**原因（推定）**：`Get-ChildItem -Path 'Release\*' -Exclude 'UserData' | Compress-Archive ...`のパイプライン構成には、フォルダ名の衝突とは別に、PowerShellの`Compress-Archive`が**ファイル数の多い・階層の深いフォルダ**（Flutterの`data\flutter_assets\`配下は数百ファイル規模になりうる）で不安定になる既知の弱点がある。加えて、このプロジェクトの絶対パス自体が長め（`C:\Users\KOTA\Desktop\Claude Code\Thphoon NPO\typhoon_ship_tracker\build\windows\x64\runner\Release\data\flutter_assets\...`）なため、Windowsの`MAX_PATH`（260文字）制限に近づいている可能性がある。`.bat`側は`if errorlevel 1`でしかエラーを検知しておらず、`Compress-Archive`が一部ファイルの取りこぼしを非致命的エラーとして扱った場合、`errorlevel`が0のまま「Done.」と表示されてしまい、失敗が全く見えない状態だった。

**対策**：`Get-ChildItem | Compress-Archive`の直接パイプラインをやめ、次の2段階に変更：
1. `robocopy`（Windows標準、長いパス・大量ファイルに強い）で`Release`フォルダを`%TEMP%`配下の短いパスのステージングフォルダへミラーコピーしつつ`UserData`のみ除外（`/XD UserData`）。
2. その短いパスのステージングフォルダに対して`Compress-Archive`を実行（`$ErrorActionPreference = 'Stop'`を設定し、以後は失敗時に確実にエラーとして検知・停止するようにした）。

`robocopy`の終了コードは0〜7が正常（1は「ファイルをコピーした」という意味で異常ではない）という独自仕様のため、`.bat`側の判定も`if errorlevel 8 goto :zipfailed`（8以上のみ失敗扱い）に変更した。

**この場ではWindows実機での再実行結果を見るまで、この対策が実際に効いているかは未確定**。効かない場合は、`Compress-Archive`自体を使わず`.NET`の`System.IO.Compression.ZipFile`を直接呼ぶ、または`tar.exe`（Windows 10 1803以降に標準搭載、zip作成にも対応）に切り替える等の代替手段を検討する。

## Windows実機確認が必要な項目（TASKS.md参照）

0. **まず、展開したexeが正常に起動すること**（`UserData`への改名で命名衝突バグを修正済みだが、実機での再確認が必須）。
1. 既存のAppDataにある登録済みデータ（Ship's Name・Passage Plan・台風情報等）が、更新後の初回起動時に自動で新しい`UserData`フォルダへ移行され、そのまま表示されること。
2. 新規に取得・登録したデータが、zipを展開したフォルダ内の`UserData`フォルダに保存されること。
3. その`UserData`フォルダを含めてzipフォルダごと別PC（または同一PC内の別フォルダ）にコピーし、コピー先でそのまま同じ内容が表示されること。
4. `build_release.bat`を実行して生成されるzipに`UserData`フォルダが含まれておらず、かつ`data`フォルダ（Flutter本体、小文字）は含まれていること（Explorerで展開して確認）。
5. （余裕があれば）`clean_project.bat`実行後にDebug版を起動するとデータが空に戻ることの確認。
