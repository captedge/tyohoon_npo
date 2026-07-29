import 'dart:convert';
import 'dart:io';

import 'package:xml/xml.dart';

import 'jma_marine_xml_parser.dart';

/// Thrown for network/HTTP-layer failures while fetching the JMA `regular.xml`
/// feed itself — mirrors [JmaFetchException] in jma_feed_fetcher.dart (kept
/// as a separate type, not reused, so callers can tell a VPTW60/typhoon fetch
/// failure apart from a VPCY51/marine failure if both are ever surfaced in
/// the same UI). A failure fetching/parsing one individual bulletin (as
/// opposed to the feed itself) does not throw this — see
/// [fetchLatestMarineForecast]'s doc comment.
class JmaMarineFetchException implements Exception {
  JmaMarineFetchException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// The 定時 (scheduled) Atom feed — VPCY51 (地方海上予報) bulletins are
/// documented as showing up here, not in `extra.xml` (随時, as-issued only) —
/// see docs/data-format-notes.md "気象庁 防災情報XML（VPCY51、地方海上予報）".
/// **Not yet confirmed against a live fetch** (2026-07-29 Cowork-side
/// attempts returned a stale ~1-month-old cached copy — see that same doc
/// section's "Cowork環境からのregular.xml取得の制約"); this fetcher exists so
/// that confirmation can be done from the real app on the Windows machine
/// instead.
const _regularFeedUrl = 'https://www.data.jma.go.jp/developer/xml/feed/regular.xml';

Future<String> _fetchText(String url) async {
  final client = HttpClient();
  client.connectionTimeout = const Duration(seconds: 15);
  try {
    final request = await client.getUrl(Uri.parse(url));
    final response = await request.close();
    if (response.statusCode != 200) {
      throw JmaMarineFetchException('HTTP ${response.statusCode}（$url）');
    }
    return await response.transform(utf8.decoder).join();
  } on JmaMarineFetchException {
    rethrow;
  } on SocketException catch (e) {
    throw JmaMarineFetchException('ネットワークに接続できませんでした: ${e.message}');
  } on HttpException catch (e) {
    throw JmaMarineFetchException('HTTPエラー: ${e.message}');
  } finally {
    client.close();
  }
}

/// Finds every 地方海上予報 (VPCY51) bulletin URL currently in the
/// `regular.xml` Atom feed, in feed order. `regular.xml` is documented as a
/// high-volume feed dominated by warnings/advisories (docs/data-format-notes.md
/// — "警報・注意報系エントリ（1情報につき数十〜百件規模）に押し流され"), so
/// this only keeps entries whose `<title>` contains "地方海上予報" (same loose
/// substring-match style [jma_feed_fetcher.dart]'s `_findVptw60Urls` uses for
/// VPTW60, deliberately not matching the full "地方海上予報（Ｈ２８）" form
/// number suffix so a future JMA form-number change doesn't silently break
/// this lookup).
///
/// [docs/data-format-notes.md] notes that multiple regional offices（管区気象台
/// 等）can each publish their own 地方海上予報 covering different sea areas, so
/// this deliberately returns *every* matching entry rather than just the
/// first — a caller wanting nationwide coverage needs to fetch and merge all
/// of them (see [fetchLatestMarineForecast]).
///
/// Returns an empty list if the feed currently has no such entry at all —
/// not necessarily an error; per docs/data-format-notes.md, VPCY51 is only
/// issued 4x/day (around 6/12/18/24 JST), so most of the time this feed
/// won't have a fresh one at all.
Future<List<String>> _findVpcy51Urls() async {
  final feedXml = await _fetchText(_regularFeedUrl);
  final XmlDocument doc;
  try {
    doc = XmlDocument.parse(feedXml);
  } on XmlException catch (e) {
    throw JmaMarineFetchException('一覧フィード（regular.xml）のXMLが不正です: ${e.message}');
  }

  final urls = <String>[];
  for (final entry in doc.descendants.whereType<XmlElement>().where((e) => e.name.local == 'entry')) {
    final title = _firstChildText(entry, 'title') ?? '';
    if (!title.contains('地方海上予報')) continue;
    final href = _firstChildAttribute(entry, 'link', 'href');
    if (href != null && href.isNotEmpty && !urls.contains(href)) urls.add(href);
  }
  return urls;
}

String? _firstChildText(XmlElement parent, String localName) {
  for (final c in parent.childElements) {
    if (c.name.local == localName) return c.innerText.trim();
  }
  return null;
}

String? _firstChildAttribute(XmlElement parent, String localName, String attrName) {
  for (final c in parent.childElements) {
    if (c.name.local == localName) return c.getAttribute(attrName);
  }
  return null;
}

/// One fetched-and-parsed VPCY51 bulletin. [parseError] is non-null when the
/// bulletin downloaded fine but [parseJmaMarineXml] rejected its content
/// (e.g. schema mismatch against the real data — the exact scenario this
/// whole fetcher exists to surface for verification, so this is deliberately
/// *kept* in the result rather than silently skipped the way a network-level
/// failure is — see [fetchLatestMarineForecast]'s doc comment).
class JmaMarineBulletin {
  const JmaMarineBulletin({
    required this.sourceUrl,
    required this.rawXml,
    this.forecasts = const [],
    this.parseError,
  });

  final String sourceUrl;
  final String rawXml;
  final List<MarineWaveForecast> forecasts;
  final String? parseError;
}

/// Result of [fetchLatestMarineForecast]: every bulletin that was found and
/// downloaded ([bulletins], one per matching `regular.xml` entry — see
/// [_findVpcy51Urls] for why there can be more than one), plus all of their
/// [MarineWaveForecast]s flattened into one list ([forecasts]) for callers
/// that don't care which office issued which area's forecast.
class JmaMarineFetchResult {
  const JmaMarineFetchResult({required this.bulletins, required this.forecasts});
  final List<JmaMarineBulletin> bulletins;
  final List<MarineWaveForecast> forecasts;
}

/// Fetches the `regular.xml` feed, finds every current VPCY51 (地方海上予報)
/// bulletin, downloads and parses each with [parseJmaMarineXml].
///
/// Returns an empty result (not an error) when the feed currently has no
/// matching bulletin at all — normal outside the 6/12/18/24 JST issue
/// windows (docs/data-format-notes.md). Throws [JmaMarineFetchException] only
/// for a failure fetching the *feed itself*; a failure fetching one
/// individual bulletin is skipped (same "one bad candidate shouldn't hide the
/// others" policy [jma_feed_fetcher.dart]'s `fetchActiveJmaTyphoons` uses),
/// but a bulletin that *downloaded* fine and failed only to *parse* is kept
/// in the result with [JmaMarineBulletin.parseError] set — that's the
/// signal this fetcher exists to surface (parser schema mismatch against
/// real data, see jma_marine_xml_parser.dart's top-of-file caveat) and
/// hiding it here would defeat the point.
Future<JmaMarineFetchResult> fetchLatestMarineForecast({int maxBulletins = 10}) async {
  final urls = await _findVpcy51Urls();
  final bulletins = <JmaMarineBulletin>[];
  final allForecasts = <MarineWaveForecast>[];
  for (final url in urls.take(maxBulletins)) {
    final String xmlText;
    try {
      xmlText = await _fetchText(url);
    } catch (_) {
      // Couldn't even download this one bulletin — skip it, don't abort the
      // whole batch (same policy as fetchActiveJmaTyphoons).
      continue;
    }
    try {
      final forecasts = parseJmaMarineXml(xmlText);
      bulletins.add(JmaMarineBulletin(sourceUrl: url, rawXml: xmlText, forecasts: forecasts));
      allForecasts.addAll(forecasts);
    } on JmaMarineXmlParseException catch (e) {
      bulletins.add(JmaMarineBulletin(sourceUrl: url, rawXml: xmlText, parseError: e.message));
    } catch (e) {
      // Broader catch-all deliberately kept alongside the
      // JmaMarineXmlParseException branch above (Agent review, 2026-07-29):
      // parseJmaMarineXml's schema is explicitly unverified against real
      // data (see jma_marine_xml_parser.dart's top-of-file caveat), so an
      // unexpected real bulletin shape could throw something other than
      // JmaMarineXmlParseException (e.g. a null-check/type error). Without
      // this branch such an error would propagate out of this function
      // entirely and abort the whole batch — defeating the "one bad
      // bulletin shouldn't hide the others" policy this loop otherwise
      // follows, and hiding exactly the kind of real-data surprise this
      // fetcher exists to surface.
      bulletins.add(JmaMarineBulletin(sourceUrl: url, rawXml: xmlText, parseError: 'Unexpected error: $e'));
    }
  }
  return JmaMarineFetchResult(bulletins: bulletins, forecasts: allForecasts);
}
