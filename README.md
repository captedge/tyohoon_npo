# Typhoon & Ship Tracker

A desktop and mobile app (Flutter) that overlays typhoon forecast tracks with
a ship's Passage Plan on a map, and calculates the ship–typhoon distance
(nautical miles) at any point in time. Typhoon data comes from two
independent sources — the Japan Meteorological Agency (JMA) and the Joint
Typhoon Warning Center (JTWC, U.S. Navy) — shown side by side rather than as
a fallback. Designed for offline use at sea: data fetched over Wi-Fi is
cached locally and the app works without a connection thereafter.

台風の予想進路（気象庁＝JMAの防災情報XMLと、米軍JTWCの警報テキストを、どちらか
一方ではなく両方独立に表示）と、船の航海計画（Passage Plan）を地図上に重ねて表示し、
任意時刻における船と台風の位置・距離（海里）を計算するデスクトップ／スマホアプリ
（Flutter製）です。船上でのオフライン利用を想定し、Wi-Fi接続時に取得したデータを
端末内にキャッシュして、以降はオフラインで使えます。

The Flutter project itself lives in [`typhoon_ship_tracker/`](typhoon_ship_tracker/).

## Data Sources

- Typhoon forecasts: [Japan Meteorological Agency (JMA)](https://www.jma.go.jp/)
- Typhoon warnings: [Joint Typhoon Warning Center (JTWC)](https://www.metoc.navy.mil/jtwc/jtwc.html), U.S. Navy
- Coastline data: [Natural Earth](https://www.naturalearthdata.com/) (public domain)

Typhoon positions and forecasts shown in this app are for reference and
voyage planning only, and are not an official real-time feed guaranteed by
JMA or JTWC. Always base actual navigation decisions on official sources.

## Privacy Policy

<https://captedge.github.io/tyohoon_npo/privacy-policy.html>

## License

© 2026 Capt.Edge. All rights reserved.

This repository's source code is published for transparency, but it is
**not** open source: no part of it may be copied, modified, or redistributed
without the author's prior permission.

本リポジトリのソースコードは透明性のために公開していますが、オープンソースでは
ありません。著者の許可なく複製・改変・再配布することはできません。
