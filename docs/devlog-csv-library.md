# devlog: CSVライブラリ機能（Import/Select/Edit CSV）

## 経緯

Passage PlanのCSVインポート機能は当初「毎回OSのファイルピッカーで選び直す」仕様だった。ユーザーから「一度読み込んだCSVが、Clearや削除後もどこかに残っているのか」という質問があり、コード確認の結果「保存されているのは解析済みのウェイポイント数値データのみで、CSVファイル自体はコピーされない」ことが判明。そこから「同じファイルを蓄積して後から選べるようにできないか」という要望に発展した。

## 要件（ユーザーとのやり取りで確定した仕様）

1. **同名ファイルのImport時**：上書き保存。実行前に確認ダイアログ（Yes/No）を出す。Noなら何もしない（登録も行わない）。
2. **ライブラリの上限**：50件。Passage Planダイアログのボタン自体には件数表記を出さない（Import CSVボタンの`(n/10)`は登録済みPassage Planの上限であり別物、そのまま維持）。代わりに「Edit CSV」の一覧で各行に`位置/50`（例：`3/50`）を表示。
3. **メニュー構成**：Passage Planダイアログの上部を「Import CSV」「Select CSV」「Edit CSV」の3段構成にする（上からこの順）。
   - Import CSV：既存のOSファイルピッカー経由の取り込み（今回からライブラリへの蓄積を伴う）。
   - Select CSV：ライブラリから選んで新規Passage Planとして登録。
   - Edit CSV：ライブラリの一覧を表示し、行ごとに「Rename」（新規機能）と「Delete」（完全削除）。

## 設計判断

- **「CSVライブラリ」と「登録済みPassage Plan（最大10件、Display管理）」は別概念として実装**：ライブラリは「過去に取り込んだCSVファイルの控え」、Passage Planは「今地図に表示している航路」。ライブラリ側でRename/Deleteしても、既に登録済みのPassage Planの表示名・データには影響しない（登録時に数値データをコピーして保持するため、ファイルへの生きた参照を持たない）。この決定は、ユーザーの要求（蓄積・再選択・整理）を素直に満たしつつ、既存の「登録済みプラン最大10件」の仕組みに手を入れずに済むという理由で採用。
- **保存先**：`path_provider`の`getApplicationSupportDirectory()`配下の`csv_library`フォルダ。Zipを展開したフォルダの外にあるため、Zipの差し替え（アップデート）でも消えない。`shared_preferences_windows`が使っているのと同じ系統のディレクトリ。
- **新規パッケージ`path_provider`の追加リスクは低いと判断**：`pubspec.lock`を確認したところ、`path_provider_windows`（Windows向けのネイティブ実装）は既に`file_picker`等の依存関係から間接的に解決済みで、このプロジェクトのビルドに既に組み込まれている。そのため新規のネイティブビルド要件（symlink/Developer Mode等、`file_picker`追加時に発生したような問題）は発生しない見込み。
- **ファイル名の一意性はファイル名（拡張子込み）で判定**：ライブラリ内は同名ファイルを許可しない設計（同名Importは上書き、Renameも同名衝突はエラー）。
- **Renameのバリデーション**：空文字・パス区切り文字（`/`・`\`）を含む入力は拒否、既存ファイルとの重複はエラー表示（`_showLabelSettingsDialog`のparseErrorsと同じ「インラインエラー表示→Save再押下」のパターンを踏襲）。
- **上限50件は新規ファイル名にのみ適用**：同名上書きはカウントを増やさないため常に許可。上限到達時は`_showVoyagePlanError`（既存のスナックバー）でメッセージ表示し、Import自体を中断。

## 実機確認後の追加修正（同日）

Windows実機確認（AskUserQuestionで4項目を個別確認、いずれもOK）の直後、追加で2件のフィードバックがあった。

### 修正1：Select CSVで登録してもPassage Plan一覧にすぐ反映されない（バグ）

**症状**：Select CSVで既存CSVを選び、VoyagePlanScreenでSaveしても、Passage Planダイアログの一覧にすぐ表示されない。ダイアログを閉じて開き直す、または他のメニュー（Edit等）を触ってから戻ると表示される。

**原因**：`_showSelectCsvDialog`の一覧行の`onTap`が`async`ではなく、`Navigator.pop(dialogContext)`で一覧ダイアログを閉じた直後に`_selectCsvFromLibrary(name)`を**awaitせず**呼んでいた。そのため`_showSelectCsvDialog`の`await showDialog(...)`は一覧ダイアログが閉じた時点で完了してしまい、`_selectCsvFromLibrary`内のVoyagePlanScreen遷移・Save・`_voyagePlans`への追加が終わる前に、呼び出し元の`_showPassagePlanDialog`側`runAndRefresh`の`setDialogState`が実行されていた（＝早すぎるリフレッシュ）。

**対策**：一覧ダイアログを`showDialog<String>`にし、行タップで`Navigator.pop(dialogContext, name)`として選択結果を返す方式に変更。ダイアログが閉じた**後**に`_selectCsvFromLibrary`をawaitすることで、`_showSelectCsvDialog`全体のFutureが登録完了まで完了しないようにした。

### 修正2：Edit CSVでの削除がPassage Planに反映されない（仕様変更）

**当初の実装**：ライブラリと登録済みPassage Planは完全に独立という設計とし、ユーザーにも一度確認して了承を得ていた。しかし実際に触ってみると「Edit CSVで削除してもPassage Planには残っている、Passage Planで改めて削除して初めて完全削除のよう」という点が直感に反していたため、方針を変更。

**変更後の仕様**（ユーザー指定）：
1. 登録済みのPassage Planがそのファイルから作られている場合：英語で確認ダイアログ「This CSV is currently registered as a Passage Plan. Delete it anyway?」Yes/No。Yesなら登録済みプランも道連れで削除。
2. 登録済みのPassage Planが無い場合：確認なしで即削除（従来通り）。

**実装**：`VoyagePlanEntry`に`sourceCsvFileName`（登録元のライブラリファイル名、nullable）を追加し、Import CSV／Select CSVで登録する際にセット。`_deleteCsvLibraryEntry`は削除対象ファイル名と一致する`sourceCsvFileName`を持つ`_voyagePlans`のエントリを検索し、上記の分岐で処理する。Renameは引き続き登録済みプランに影響しない仕様のまま（`sourceCsvFileName`は更新しない＝リネーム後は紐付けが切れる「孤児」状態になるが、これは意図した仕様）。

## 教訓

- 「保存されているデータの実体は何か」というユーザーからの素朴な質問がきっかけで、後から見ると自然な機能追加（蓄積・再選択）につながった。実装時は既存の永続化の仕組み（`shared_preferences`まわりの保存先ディレクトリ）を素直に流用することで、新規リスクを最小限に抑えられた。
- 新規パッケージ追加の是非を判断する際、`pubspec.lock`で「実は既に間接的に解決済みか」を確認するのは有効な事前チェック（`docs/operation-rules.md`完了報告前チェック7の実践例）。
- ダイアログを閉じる操作（`Navigator.pop`）と、その後に続く非同期処理（別の非同期メソッド呼び出し）を同じ同期的コールバック内に書く場合、後者を`await`し忘れると「呼び出し元は完了したと思っているが実際の処理はまだ終わっていない」というタイミングバグになりやすい。教訓：ダイアログのonTap等で「閉じる→後続処理」の順で書く場合は、閉じる際に選択結果を`Navigator.pop(context, result)`で返し、後続処理は呼び出し元（`await showDialog(...)`の後）で行う設計にすると、Future の完了タイミングを素直に扱える。
- 「独立した設計」が机上では合理的でも、実際に触ってみると直感に反することがある（Edit CSVでの削除がPassage Planに影響しない件）。事前の確認（AskUserQuestion）で一度OKをもらっていても、実機で触った後に方針転換の申し出があれば、その場で再度仕様を確認し直す（宣言4：繰り返し検知の実践）。
