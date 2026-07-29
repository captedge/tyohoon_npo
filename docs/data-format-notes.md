# データ形式・仕様メモ（実装時の参照資料）

外部データ形式（気象庁 防災情報XML、JRC ECDIS/NAVTORルートCSV、JTWC警報テキスト）について確認済みの仕様をまとめたもの。TASKS.mdは「次にやること」に絞るため、進行中タスクから参照する仕様資料はここに集約する。該当タスクに着手する際は必ずこのファイルを確認する。

## 気象庁 防災情報XML（VPTW60）

- 提供形式：PULL型のみ（PUSH型は2023年9月終了）。ユーザー登録不要、無認証・無料でアクセス可能。
- 台風情報の電文種類：**VPTW60**（台風解析・予報情報、5日先までの予報を含む）。
- 公式技術資料：`https://xml.kishou.go.jp/`（トップページ）、`https://xml.kishou.go.jp/tec_material.html`（技術資料一覧）。
- 公式保証のない電文フィードのため（正式な「台風API」ではない）、実データ構造を確認してから読み込みロジックを設計する。

### フィード構成・電文取得の流れ（2026-07-28確認済み）

1. **一覧フィード（Atom）**：`https://www.data.jma.go.jp/developer/xml/feed/extra.xml`（随時発表の情報。VPTW60はここに載る。`regular.xml`＝定時発表の方には載らない）。フィードは直近の発表を`<entry>`として複数含む（1エントリ＝1回の発表）。
   - 該当エントリの`<title>`は「台風解析・予報情報（５日予報）（Ｈ３０）」。
   - `<id>`と`<link type="application/xml" href="...">`が実電文のURL（例：`https://www.data.jma.go.jp/developer/xml/data/20260716190017_0_VPTW60_010000.xml`）。ファイル名の先頭14桁が発表日時（UTC、`YYYYMMDDHHMMSS`）、続く`_0_VPTW60_010000`が電文種類の固定部分。
   - **実装方針**：`extra.xml`を定期的に取得し、`<title>`が「台風解析・予報情報」を含む最新エントリのURLを都度取り直す（電文URL自体は発表のたびに変わるため固定URLで直接ポーリングはできない）。
2. **実電文（VPTW60本体）**：上記URLへGETすると台風解析・予報情報のXMLが直接返る（認証不要）。
3. **複数台風の見分け方（2026-07-29確認済み、実装済み：`fetchActiveJmaTyphoons`）**：`extra.xml`は「発表1回＝1エントリ」の一覧であり「台風1つ＝1エントリ」ではない。アクティブな台風は約3時間おきに新しい電文を発表するため、同じ台風の連続する発表が複数エントリとして並ぶ（実データで確認：同一タイトルのエントリが3時間差で連続していた）。異なる台風を見分けるには、各候補を実際に取得・パースした上で`JmaTyphoonInfo.eventId`（無ければ号数＋名称、それも無ければ電文URL自体）で重複排除する必要がある。一覧の並び順（新しい順）を保ったまま重複排除後の最初のN件を採用すれば、各台風の最新発表を過不足なく拾える。

### 実電文のスキーマ（2026-07-28、`20260716190017_0_VPTW60_010000.xml`で確認）

XML名前空間：`Report`（ルート）/`Control`/`Head`（`informationBasis1`名前空間）/`Body`（`meteorology1`名前空間、要素の多くは`jmx_eb:`接頭辞＝`elementBasis1`名前空間）。

- `Head/EventID`：台風（低気圧）1つを表す識別子（例：`TC2613`）。同一台風の複数回の発表を追跡するキーとして使える。
- `Head/ReportDateTime`：発表時刻（JST、`+09:00`付きISO8601）。JTWC電文と違い年月日付きでタイムゾーンも明示されているため、既存の`issuedAtJst`のような月またぎ推定ロジックは不要。
- `Head/TargetDateTime`：実況の基準時刻（JST）。
- `Head/TargetDuration`：予報期間（例：`PT120H`＝120時間＝5日）。
- `Head/Serial`：発表回次（連番）。
- `Body/MeteorologicalInfos/MeteorologicalInfo`：実況1つ＋予報複数（12/24/48/72/96/120時間後など、台風の階級によって存在する予報時刻数が変わる）の繰り返し。各要素の`DateTime`属性`type`が「実況」「予報　１２時間後」のように区別、値（本文）はJSTのISO8601。
  - `Item/Kind/Property[Type=呼称]/TyphoonNamePart`：`Name`（例：ドルフィン、未命名時は空）／`NameKana`／`Number`（台風番号、未採番時は空）／`Remark`（例：「台風発生予想」）。**台風発生前（熱帯低気圧予想段階）はName/Numberとも空文字**になりうるため、パーサーは空文字を許容する。
  - `Item/Kind/Property[Type=階級]/ClassPart/jmx_eb:TyphoonClass`（`type="熱帯擾乱種類"`）：`熱帯低気圧(TD)` / `台風(TS)` 等の分類文字列。JTWC同様、この文字列で発達段階を判定できる。
  - `Item/Kind/Property[Type=中心]/CenterPart`（実況の場合）：
    - `jmx_eb:Coordinate[type=中心位置（度）]`：本文が`+5.6+153.8/`のような**符号付き10進度2つを連結しスラッシュで終端する独自フォーマット**（緯度→経度の順、南緯・西経は`-`）。正規表現例：`^([+-]\d+(?:\.\d+)?)([+-]\d+(?:\.\d+)?)/$`。
    - `jmx_eb:Coordinate[type=中心位置（度分）]`：度分表記版（例：`+535+15350/`＝北緯5度35分・東経153度50分、10進度版と役割重複のためパーサーは度版のみ使えば十分）。
    - `Location`：地名（日本語、例：「トラック諸島近海」）、`jmx_eb:Direction`（16方位漢字）、`jmx_eb:Speed`（ノット／km/h、複数`unit`で並記）、`jmx_eb:Pressure`（hPa）。
  - `Item/Kind/Property[Type=中心]/CenterPart/ProbabilityCircle`（予報の場合）：中心座標を持つ`BasePoint`（実況と同じ`+緯度+経度/`フォーマット）＋`Axes/Axis/jmx_eb:Radius`（予報円の70%確率半径、海里／km）。
  - `Item/Kind/Property[Type=風]/WindPart`：`jmx_eb:WindSpeed`（最大風速・最大瞬間風速、ノット／m/s）。
  - `Item/Kind/Property[Type=風]/WarningAreaPart`（`type="暴風域"`/`強風域`/`暴風警戒域`）：風速域の半径（`jmx_eb:Circle/jmx_eb:Axes/jmx_eb:Axis/jmx_eb:Radius`、海里／km）。**方向・半径が「全域」「なし」の場合は`Radius`の本文が空**（=全周同一半径、または未設定）になりうるため、パーサーは空文字を許容する。方位が限定される場合は`Axis`が複数入り、方向ごとに異なる半径を持つ（今回のサンプルでは全て「全域」だったため複数`Axis`の実例は未確認、次に方向限定の実例が手に入った時点で追記）。
- **既存の距離計算（`docs/data-format-notes.md`冒頭の中分緯度法）にそのまま使えるのは中心位置（度）のみ**。予報円の半径・風速域半径は今回のTASKS（台風・船の位置と距離のみ）では未使用だが、将来Range Ring的な「予報円」表示に流用できる可能性あり。
- **パース実装済み（2026-07-28）**：`lib/utils/jma_xml_parser.dart`（`xml: ^7.0.1`パッケージ使用、純Dart・ネイティブビルド要件なし）。`parseJmaTyphoonXml(String)`が電文XML文字列を`JmaTyphoonInfo`に変換する。JTWCの`JtwcTyphoonInfo`と異なり、JMA電文は`ReportDateTime`・各`MeteorologicalInfo/DateTime`とも年月日付きJST（`+09:00`固定）のため、JTWCの`issuedAtJst`のような月またぎ推定は不要（`+09:00`以外のオフセットは`JmaXmlParseException`で検出）。座標は`+緯度+経度/`独自フォーマット（正規表現でパース）。`JmaTyphoonInfo.toTrackPoints()`で既存の`TrackPoint`リストへ直接変換可能（実況＋予報点、絶対時刻のまま）。台風発生前（熱帯低気圧予想段階）は名称・番号が空文字→nullとして扱う設計。要素の名前空間はHead/Body自身がデフォルト名前空間を再宣言し`jmx_eb:`接頭辞も混在するため、フルの名前空間解決はせず要素名（ローカル名）ベースでマッチする実装（JTWCパーサー同様の「実用上十分」な割り切り）。Pythonでの再現検証（実際にJMAから取得した`20260716190017_0_VPTW60_010000.xml`サンプル）で、実況位置(5.6N,153.8E)・気圧1006hPa・分類・予報3点（12/24/48h）の値がXML本文と一致することを確認済み。**フィード取得・MapScreen接続 実装済み（2026-07-28）**：`lib/utils/jma_feed_fetcher.dart`の`fetchLatestJmaTyphoon()`が`extra.xml`一覧フィードを`dart:io HttpClient`で取得し、「台風解析・予報情報」を含む最初の`<entry>`の電文URLを取得・再フェッチして`parseJmaTyphoonXml`に渡す（該当エントリが無ければエラーではなく`JmaTyphoonInfo.empty`を返す）。`MapScreen`の「Information」ダイアログに台風スロットごとの「Fetch from JMA」ボタンを追加し、取得結果を既存の`JtwcTyphoonInfo`（地図描画コードが前提とする型）に変換して、テキスト貼り付けと同じSave経路に流し込む設計（`JmaForecastPoint`の絶対時刻`validAtJst`を、実況時刻からの差分時間`hoursFromNow`に変換して`JtwcForecastPoint`へ詰め替え）。現状は**ボタンを押した時だけ取得する手動トリガー方式**（自動定期取得・Wi-Fi時オフラインキャッシュはTASKS.md参照、未実装）。取得結果はセッション内メモリのみに保持し、次回起動時には残らない（`pastedText`が空のまま保存されるため）。次のステップ：ON/OFF自動取得設定、オフラインキャッシュ、複数台風同時発表時の区別（TASKS.md参照）。

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

## JTWC自動取得のURL構造（実装済み：`lib/utils/jtwc_feed_fetcher.dart`、2026-07-29調査）

実際にJTWCサイト（`https://www.metoc.navy.mil/jtwc/jtwc.html`）をブラウザで開き、通信内容（Networkタブ）を確認して判明した構造。憶測ではなく実機確認済み。

- **一覧フィード**：`https://www.metoc.navy.mil/jtwc/rss/jtwc.rss`（RSS 2.0、プレーンHTTPで取得可・JS不要）。JMAの`extra.xml`に相当する「現在発表中の系統一覧」。`<item>`が地域ごとに分かれており、`<guid>`で判別する：
  - `NWPAC-NIO-WARNINGS`：北西太平洋／北インド洋（ベンガル湾・アラビア海含む）——本アプリの地図範囲（N5-50/E85-170）に該当するのはこれのみ。
  - `EPAC-CPAC-WARNINGS`：中部・東太平洋（地図範囲外、対象外）
  - `SH-WARNINGS`：南半球（地図範囲外、対象外）
  - `TROPICAL-ADVISORIES`：個別台風ではない広域の熱帯擾乱情報（対象外）
- 該当`<item>`の`<description>`はCDATA内のHTMLで、`<a href='https://www.metoc.navy.mil/jtwc/products/wp1226web.txt' target='newwin'>TC Warning Text</a>`のような形で警報テキスト本文（`***web.txt`）のリンクを含む。同じHTML内に`.gif`（警報図）・`.tcw`（JMV3.0データ）・`.kmz`（Google Earthオーバーレイ）・`fix.txt`（衛星フィックス報）・`prog.txt`（予報根拠）等の関連リンクも並ぶため、`web.txt`で終わるリンクだけを正規表現で拾う。同時に複数系統が発表中の場合、同じ`<description>`内に系統ごとの見出し・リンク一式がそのまま連結される（実データで確認済み）——複数系統を区別する対応はTASKS.mdの別項目として未着手のまま。
- `***web.txt`（TC Warning Text）の中身は、既存の`parseJtwcWarningText`が想定する手貼り付けテキストと完全に同一の書式（JTWC公式の警報書式仕様書とも一致確認済み）。取得したテキストはそのまま既存パーサーに渡せる。
- **既知の注意点**：`/jtwc/products/`配下の個別テキストファイルは、汎用のHTTPクライアント（本調査時のCowork検証環境）からは空応答が返ったが、実ブラウザ経由では問題なく取得できた。User-Agentによるフィルタリングの可能性があるため、`jtwc_feed_fetcher.dart`はブラウザ相当のUser-Agentヘッダーを全リクエストに付与している（一覧フィード自体はUser-Agent無しでも取得できていた）。Windows実機でのネットワークからの動作確認が必要（TASKS.md参照）。
