import 'dart:convert';
import 'dart:io';

import 'package:xml/xml.dart';

import 'jma_xml_parser.dart';

/// Thrown for network/HTTP-layer failures while fetching the JMA feed or a
/// bulletin XML — distinct from [JmaXmlParseException] (jma_xml_parser.dart),
/// which is about the *content* of a document that was successfully
/// downloaded. Kept separate so callers/UI can tell "couldn't reach the
/// server" apart from "reached it, but the document was unexpected".
class JmaFetchException implements Exception {
  JmaFetchException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// The 随時 (as-issued) Atom feed — VPTW60 bulletins show up here, not in
/// `regular.xml` (定時, scheduled reports only) — confirmed 2026-07-28, see
/// docs/data-format-notes.md.
const _extraFeedUrl = 'https://www.data.jma.go.jp/developer/xml/feed/extra.xml';

Future<String> _fetchText(String url) async {
  final client = HttpClient();
  client.connectionTimeout = const Duration(seconds: 15);
  try {
    final request = await client.getUrl(Uri.parse(url));
    final response = await request.close();
    if (response.statusCode != 200) {
      throw JmaFetchException('HTTP ${response.statusCode}（$url）');
    }
    return await response.transform(utf8.decoder).join();
  } on JmaFetchException {
    rethrow;
  } on SocketException catch (e) {
    throw JmaFetchException('ネットワークに接続できませんでした: ${e.message}');
  } on HttpException catch (e) {
    throw JmaFetchException('HTTPエラー: ${e.message}');
  } finally {
    client.close();
  }
}

/// Finds every VPTW60 (台風解析・予報情報) bulletin URL currently in the
/// `extra.xml` Atom feed, in feed order (newest first, per JMA's own feed
/// ordering). The feed lists individual *bulletins*, not distinct storms —
/// an active typhoon publishes a fresh VPTW60 roughly every 3 hours, so
/// several consecutive entries returned here can belong to the very same
/// storm (2026-07-29 finding, see [fetchActiveJmaTyphoons]'s doc comment
/// for how a caller wanting *distinct* storms handles that). Each
/// bulletin's own URL changes on every publish (its filename embeds the
/// publish timestamp — see docs/data-format-notes.md), so this lookup has
/// to be redone on every fetch rather than pointing at fixed data URLs.
///
/// Returns an empty list if the feed currently has no such entry at all
/// (e.g. no typhoon activity right now) — a normal, expected outcome, not
/// an error worth throwing over.
Future<List<String>> _findVptw60Urls() async {
  final feedXml = await _fetchText(_extraFeedUrl);
  final XmlDocument doc;
  try {
    doc = XmlDocument.parse(feedXml);
  } on XmlException catch (e) {
    throw JmaFetchException('一覧フィード（extra.xml）のXMLが不正です: ${e.message}');
  }

  final urls = <String>[];
  for (final entry in doc.descendants.whereType<XmlElement>().where((e) => e.name.local == 'entry')) {
    final title = _firstChildText(entry, 'title') ?? '';
    // "台風解析・予報情報（５日予報）（Ｈ３０）" is the title seen in the feed
    // (2026-07-28 sample); matching on the shorter "台風解析・予報情報" prefix
    // is deliberately loose so a future title-suffix change (the "（Ｈ３０）"
    // form-number part) doesn't silently break this lookup.
    if (!title.contains('台風解析・予報情報')) continue;
    final href = _firstChildAttribute(entry, 'link', 'href');
    if (href != null && href.isNotEmpty) urls.add(href);
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

/// Result of [fetchLatestJmaTyphoon]: the parsed [info] plus the raw bulletin
/// XML it came from (2026-08 offline-cache addition — the raw text is what
/// gets persisted, mirroring the existing "store raw JTWC paste text, re-parse
/// on load" convention in app_state_storage.dart, so a future improvement to
/// [parseJmaTyphoonXml] automatically applies to a restored cache too, without
/// a migration step). [rawXml] is null exactly when [info] is
/// [JmaTyphoonInfo.empty] because the feed had no bulletin at all (nothing
/// was downloaded to keep) — see [fetchLatestJmaTyphoon]'s doc comment.
class JmaFetchResult {
  const JmaFetchResult({required this.info, required this.rawXml});
  final JmaTyphoonInfo info;
  final String? rawXml;
}

/// Fetches the `extra.xml` feed, finds the latest VPTW60 bulletin (if any),
/// downloads it, and parses it with [parseJmaTyphoonXml].
///
/// Returns a result with [JmaTyphoonInfo.empty]/null [JmaFetchResult.rawXml]
/// (not an error) when the feed currently has no typhoon bulletin at all —
/// the normal "nothing active right now" case. Throws [JmaFetchException]
/// for network/HTTP failures, or [JmaXmlParseException] if a bulletin that
/// *was* found doesn't parse as expected (see jma_xml_parser.dart).
Future<JmaFetchResult> fetchLatestJmaTyphoon() async {
  final urls = await _findVptw60Urls();
  if (urls.isEmpty) return const JmaFetchResult(info: JmaTyphoonInfo.empty, rawXml: null);
  final xmlText = await _fetchText(urls.first);
  final info = parseJmaTyphoonXml(xmlText);
  return JmaFetchResult(info: info, rawXml: xmlText);
}

/// Fetches up to [maxResults] *distinct* currently-active typhoons from the
/// extra.xml feed (2026-07-29 addition, for the Information dialog's "Fetch
/// All" button — 複数台風が同時に発表されている場合に台風1/2/3へまとめて自
/// 動入力する機能、TASKS.md参照).
///
/// As [_findVptw60Urls]'s doc comment explains, the feed lists individual
/// *bulletins*, not distinct storms — several consecutive entries can
/// belong to the same storm. This function tells storms apart by fetching
/// each candidate bulletin (in feed order, newest first — capped at
/// [maxCandidates] fetches so a feed full of old/stale entries can't cause
/// unbounded work) and de-duplicating by [JmaTyphoonInfo.eventId] — the
/// field that doc comment itself describes as existing precisely to detect
/// "is this still the same storm" — falling back to the number+name pair,
/// or (if a bulletin has neither, e.g. a very early unnamed/unnumbered
/// system) the bulletin's own URL, which is always unique per fetch and so
/// never collides with anything: when identity can't be determined, this
/// function errs toward treating a candidate as a *new* storm rather than
/// silently merging it into another one. Keeps only the first (i.e.
/// newest) bulletin seen for each distinct identity, stopping once
/// [maxResults] distinct storms have been found or [maxCandidates]
/// bulletins have been checked, whichever comes first.
///
/// Deliberately does not filter by how old/stale a bulletin's own issue
/// time is — same trust model [fetchLatestJmaTyphoon] already has today
/// (whatever's first/found in the feed is trusted as-is); adding a
/// staleness cutoff would be a separate, more subjective judgment call this
/// function isn't trying to make.
///
/// Returns an empty list (not an error) if the feed currently has no
/// typhoon bulletin at all. Throws [JmaFetchException] for network/HTTP
/// failures fetching the *list* feed itself; a failure fetching/parsing one
/// individual candidate bulletin is skipped rather than aborting the whole
/// call, so one bad bulletin doesn't hide the others.
Future<List<JmaFetchResult>> fetchActiveJmaTyphoons({int maxResults = 3, int maxCandidates = 10}) async {
  final urls = await _findVptw60Urls();
  final results = <JmaFetchResult>[];
  final seenIdentities = <String>{};
  for (final url in urls.take(maxCandidates)) {
    if (results.length >= maxResults) break;
    final String xmlText;
    final JmaTyphoonInfo info;
    try {
      xmlText = await _fetchText(url);
      info = parseJmaTyphoonXml(xmlText);
    } catch (_) {
      // Skip a single bad candidate (network hiccup or unexpected XML
      // shape for just this one bulletin) rather than aborting the whole
      // batch — see this function's doc comment.
      continue;
    }
    final identity = info.eventId ??
        ((info.number != null || info.name != null) ? '${info.number ?? ''}/${info.name ?? ''}' : url);
    if (!seenIdentities.add(identity)) continue;
    results.add(JmaFetchResult(info: info, rawXml: xmlText));
  }
  return results;
}
