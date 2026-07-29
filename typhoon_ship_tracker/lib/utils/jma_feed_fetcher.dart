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

/// Finds the most recent VPTW60 (台風解析・予報情報) bulletin's XML URL out
/// of the `extra.xml` Atom feed. The bulletin's own URL changes on every
/// publish (its filename embeds the publish timestamp — see
/// docs/data-format-notes.md), so this lookup has to be redone on every
/// fetch rather than pointing at one fixed data URL.
///
/// Returns null if the feed currently has no such entry at all (e.g. no
/// typhoon activity right now) — that's a normal, expected outcome, not an
/// error worth throwing over.
Future<String?> _findLatestVptw60Url() async {
  final feedXml = await _fetchText(_extraFeedUrl);
  final XmlDocument doc;
  try {
    doc = XmlDocument.parse(feedXml);
  } on XmlException catch (e) {
    throw JmaFetchException('一覧フィード（extra.xml）のXMLが不正です: ${e.message}');
  }

  for (final entry in doc.descendants.whereType<XmlElement>().where((e) => e.name.local == 'entry')) {
    final title = _firstChildText(entry, 'title') ?? '';
    // "台風解析・予報情報（５日予報）（Ｈ３０）" is the title seen in the feed
    // (2026-07-28 sample); matching on the shorter "台風解析・予報情報" prefix
    // is deliberately loose so a future title-suffix change (the "（Ｈ３０）"
    // form-number part) doesn't silently break this lookup.
    if (!title.contains('台風解析・予報情報')) continue;
    final href = _firstChildAttribute(entry, 'link', 'href');
    if (href != null && href.isNotEmpty) return href;
  }
  return null;
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

/// Fetches the `extra.xml` feed, finds the latest VPTW60 bulletin (if any),
/// downloads it, and parses it with [parseJmaTyphoonXml].
///
/// Returns [JmaTyphoonInfo.empty] (not an error) when the feed currently has
/// no typhoon bulletin at all — the normal "nothing active right now" case.
/// Throws [JmaFetchException] for network/HTTP failures, or
/// [JmaXmlParseException] if a bulletin that *was* found doesn't parse as
/// expected (see jma_xml_parser.dart).
Future<JmaTyphoonInfo> fetchLatestJmaTyphoon() async {
  final url = await _findLatestVptw60Url();
  if (url == null) return JmaTyphoonInfo.empty;
  final xmlText = await _fetchText(url);
  return parseJmaTyphoonXml(xmlText);
}
