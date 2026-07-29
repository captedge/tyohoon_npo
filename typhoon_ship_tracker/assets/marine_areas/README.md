# marine_areas assets

地方海上予報（気象庁XML電文コードVPCY51）の予報区ポリゴン境界データ置き場。台風の
海岸線データ（`assets/coastline/`）と同じ役割だが、こちらは区域ごとの境界を
1つのファイル（`marine_areas.json`）にまとめてある。

## 現状（2026-07-29、取得・簡略化済み）

`marine_areas.json`（全48区域、2,060リング・27,041点、約447KB）を生成済み。
アプリからはこのファイルだけを読み込む（`lib/utils/marine_areas.dart`）。

生成の経緯：ユーザーのWindows機で`download_marine_areas.ps1`を実行し、NII
Geoshapeから48区域分の生GeoJSON（実測、合計約213MB——1区域あたり最大で数百万点
規模の座標を含む、コースラインに沿った非常に高精細なデータだった）をダウンロード。
これをCoworkのサンドボックス側（マウントされた同じフォルダ経由）でPython+Shapely
により簡略化・結合し、`marine_areas.json`を生成した。処理後、生GeoJSON（48ファイル・
213MB）はリポジトリに含める意味が無いため削除済み（大きすぎる・簡略化後のデータで
十分なため）。

## 再生成する場合（データソースが更新された場合など）

1. `download_marine_areas.ps1`をユーザーのWindows機のPowerShellで実行し、このフォルダに
   48個の生GeoJSONをダウンロードする：
   ```powershell
   cd "typhoon_ship_tracker\assets\marine_areas"
   Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
   .\download_marine_areas.ps1
   ```
2. `simplify_marine_areas.py`を実行し、`marine_areas.json`を再生成する（`pip install
   shapely`が別途必要、Flutter/Dart側の依存には含まれない）：
   ```
   pip install shapely
   python simplify_marine_areas.py
   ```
3. 生GeoJSON（`*.geojson`）は`marine_areas.json`生成後は不要なので削除してよい。

## データソース・ライセンス

- 提供元：[NII Geoshape「気象庁防災情報発表区域データセット」](https://geoshape.ex.nii.ac.jp/jma/resource/AreaMarineAJ/)
- 元データ：気象庁「予報区等GISデータ」
- ライセンス：CC BY 4.0。利用時のクレジット表示（気象庁XML電文の出典表示とは別に必要）：
  > 『気象庁防災情報発表区域データセット』（NII作成）「GISデータ」（気象庁）を加工
- URLパターン：`https://geoshape.ex.nii.ac.jp/jma/resource/AreaMarineAJ/20190125/{コード}.geojson`

## 対象区域（全48、コード1000〜6030）

地方海上予報区の全区域。表示範囲（N5-50/E85-170）にすべて収まると判断済み
（`docs/data-format-notes.md`参照）のためフィルタリングなし。区域名・コードの
一覧は`lib/utils/marine_area_codes.dart`（Dartコード側の定数）、
`download_marine_areas.ps1`内、または上記NII Geoshapeページ参照。

## marine_areas.json の形式

`coastline.json`（プレーンな配列、`assets/coastline/README.md`参照）と違い、
区域コードをキーにしたオブジェクト（区域ごとに個別のポリゴン集合を引けるように
するため）：

```json
{
  "1000": [[[lon, lat], [lon, lat], ...], ...],
  "1010": [...],
  ...
}
```

`lib/utils/marine_areas.dart`（`MarineAreaData.load()`）が読み込む。内部リング
（穴、小島など）は持たない——外周のみ（coastline.jsonと同じ方針、理由は
`simplify_marine_areas.py`のコメント参照）。

## 今後の使い方（未実装）

`lib/utils/jma_marine_xml_parser.dart`（想定、未実装）がVPCY51電文から予報区
コード（`Area/Code`）ごとの波高予報を抽出し、`MarineAreaData.forCode()`で対応する
ポリゴンを引いて`MapPainter`で塗り分け表示する予定（TASKS.md参照）。

## 既知の制約

- 簡略化の許容誤差は0.02度（coastline.jsonの0.01度より粗い）。このレイヤーは
  波高予報の色分け表示用であり、海岸線そのものの精度は`assets/coastline/`側が
  担うため、多少の粗さは許容している。
- `regular.xml`の実データでのVPCY51スキーマ裏取りはまだ完了していない
  （`docs/data-format-notes.md`「Cowork環境からのregular.xml取得の制約」参照）。
  この境界データ自体（NII Geoshape由来）はVPCY51電文のスキーマとは無関係の
  別ソースなので、この制約の影響は受けない。
