# データ形式・仕様メモ（実装時の参照資料）

外部データ形式（気象庁 防災情報XML、JRC ECDIS/NAVTORルートCSV、JTWC警報テキスト）について確認済みの仕様をまとめたもの。TASKS.mdは「次にやること」に絞るため、進行中タスクから参照する仕様資料はここに集約する。該当タスクに着手する際は必ずこのファイルを確認する。

## 気象庁 防災情報XML（VPTW60）

- 提供形式：PULL型のみ（PUSH型は2023年9月終了）。ユーザー登録不要、無認証・無料でアクセス可能。
- 台風情報の電文種類：**VPTW60**（台風解析・予報情報、5日先までの予報を含む）。
- 公式技術資料：`https://xml.kishou.go.jp/`（トップページ）、`https://xml.kishou.go.jp/tec_material.html`（技術資料一覧）。
- 次のステップ：実際のAtomフィードURL（`https://www.data.jma.go.jp/developer/xml/feed/`配下）からVPTW60電文のサンプルを取得し、XMLスキーマ（要素名・座標の単位表記など）を確認してからDartでのパーサー実装に入る。
- 公式保証のない電文フィードのため（正式な「台風API」ではない）、実データ構造を確認してから読み込みロジックを設計する。

## JRC ECDIS/NAVTOR ルートCSV

公式マニュアル調査（2026-07-26）とユーザー提供の実サンプル（`013K378NEG W-KII.csv`）確認（2026-07-26）の両方で裏付け済み。

- コメント行：`//`で始まる（見出し行も含む）。区切り文字はカンマ。
- 実サンプルでのデータ行の列構成（全17列）：
  `WPT No., LATdeg, LATmin, LAThemi(N/S), LONdeg, LONmin, LONhemi(E/W), PORT[NM], STBD[NM], Arr.Rad[NM], Speed[kn], Sail(RL/GC), ROT[deg/min], TurnRad[NM], TimeZone(HH:MM), TimeZoneHemi(E/W), Name`
- 最初のWP（No.000、出発点）は`PORT`〜`TurnRad`までの7列が`***`（該当なし）。パーサーは`***`をnull/未使用として扱う。
- 本アプリで実際に使う列は「WPT No., 緯度3列, 経度3列, Speed[kn], Name」のみ。`PORT`/`STBD`/`Arr.Rad`/`Sail`/`ROT`/`TurnRad`/`TimeZone`は距離・時刻計算に不要。
- **日時（ETA/ETD）列はこの純正ECDIS書式には含まれない**。CSVインポート直後に出発日時（WP000の時刻）を入力する画面を挟み、以降は区間距離（本アプリの中分緯度法で連続する2点から計算）÷その区間のSpeed[kn]で所要時間を積み上げて、各WPの到着時刻を算出する（2026-07-26ユーザー確認済み）。これにより`TrackPoint.time`を全WPについて確定でき、既存の線形補間ロジック（`positionAt`）がそのまま使える。
- 将来検討（今は詳細を詰めない、実装時に検討）：インポート後のWaypoint位置・区間速力をアプリ上で編集する機能。

## JTWC警報テキストの抽出パターン（実装済み：`lib/utils/jtwc_parser.dart`）

JTWCの英語警報テキストを貼り付けて、正規表現で以下を抽出する仕組みが実装済み（`JtwcTyphoonInfo`／`parseJtwcWarningText`）。将来、JTWCページの自動取得（定期フェッチ）を実装する際も、抽出仕様はこのままDartパーサー側で流用できる。

- 番号・名称：`TYPHOON\s+(\d+[A-Z])\s*\(([^)]+)\)` → 例「11W (NOUL)」
- 中心気圧：`MINIMUM CENTRAL PRESSURE AT ####Z IS ### MB`行から抽出（例：980）
- 現在位置：`REPEAT POSIT: 20.8N 118.3E`行から抽出（南緯・西経は符号反転）
- 発表時刻：`WARNING POSITION:`ブロックの`DDHHMMZ`行（日・時・分、UTC）。JTWC電文には年月が含まれないため、`issuedAtJst(reference)`が呼び出し時点（`reference`）の年月を補ってUTC DateTimeを組み立て、+9時間してJSTへ変換する。
- 予報点（12/24/36/48/60時間先）：「12 HRS, VALID AT: / 251200Z --- 22.0N 116.4E」のようなブロックから抽出（`EXTENDED OUTLOOK`配下の48/60時間も同一パターンでマッチ）。JTWC電文は絶対日時を持たないため、絶対時刻ではなく「読み込み時刻（`_startTime`）からの経過時間」としてオフセット化して扱う。
