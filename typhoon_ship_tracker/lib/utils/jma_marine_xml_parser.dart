import 'package:xml/xml.dart';

/// Thrown when a fetched document doesn't look like a VPCY51（地方海上予報）
/// report, or is missing fields this parser relies on to make sense of the
/// data. [message] is meant to be shown to the user/logs as-is, mirroring
/// [JmaXmlParseException]'s style (see jma_xml_parser.dart).
class JmaMarineXmlParseException implements Exception {
  JmaMarineXmlParseException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// **Schema caveat (as of 2026-07-29): every field name/structure this
/// parser looks for comes from JMA's official "地方海上予報ＸＭＬの解説" PDF
/// and has NOT yet been cross-checked against a real VPCY51 bulletin — see
/// docs/data-format-notes.md "Cowork環境からのregular.xml取得の制約" for why
/// (this Cowork session couldn't fetch a fresh `regular.xml`, and the
/// Claude in Chrome extension wasn't connected either). Verify this parser
/// against an actual fetched bulletin (Windows実機、実際にImportして) before
/// trusting its output, the same way the JTWC/JMA typhoon fetchers were
/// verified. Where the doc comments below say "documented as" rather than
/// "confirmed", that's this caveat applying to that specific field.**
///
/// One 変化点 (Becoming) inside a [MarineWaveForecast]'s wave-height
/// timeline — VPCY51 expresses the forecast as a "現況からの変化" rather
/// than fixed "今日/明日"-style blocks (see docs/data-format-notes.md), so
/// each Becoming represents "at some point, the wave height changes to
/// [heightM]" rather than a fixed absolute time span.
///
/// [timeModifierText] is kept as JMA's raw Japanese phrase (documented as
/// the `TimeModifier` attribute, e.g. "１０日２１時までに") rather than
/// parsed into a DateTime — resolving this free-text expression into an
/// absolute JST time (for the playback-slider "階段状" rendering described
/// in docs/devlog-online-xml.md) needs a real sample to confirm the exact
/// phrasing patterns used (e.g. is it always "…までに", or are there
/// "…から" / date-crossing variants?) before it can be done reliably —
/// that resolution step is intentionally left for a follow-up once real
/// data is available, rather than guessed here.
class MarineWaveBecoming {
  const MarineWaveBecoming({this.timeModifierText, this.heightM, this.description});

  /// Raw `TimeModifier` attribute text, documented as being on the
  /// `Becoming` element itself. Null if not present/found.
  final String? timeModifierText;

  /// Wave height in meters (documented as a plain numeric value, not a
  /// classed/bucketed string — see [MarineWaveForecast.baseHeightM] doc
  /// comment). Null if this Becoming has no parseable height (e.g.
  /// `condition="予報なし"`).
  final double? heightM;

  /// JMA's human-readable height text (documented `description` attribute,
  /// e.g. "４メートル"), kept alongside the numeric value for display/
  /// logging purposes. Null if not present.
  final String? description;
}

/// One sea area's (地方海域) wave-height forecast for one period block
/// (`MeteorologicalInfo`, e.g. Name="今日から明日") out of a VPCY51 report —
/// i.e. one `Item/Kind/Property[@type="波"]` block, scoped to its `Area`.
///
/// A single VPCY51 document produces one of these per (period block × sea
/// area) combination that actually has a 波 (wave) property — see
/// [parseJmaMarineXml]'s doc comment for how these are collected.
class MarineWaveForecast {
  const MarineWaveForecast({
    required this.areaCode,
    this.areaName,
    this.periodLabel,
    this.baseHeightM,
    this.baseDescription,
    this.becoming = const [],
  });

  /// `Area/Code` (e.g. "4030") — matches the keys in
  /// assets/marine_areas/marine_areas.json / [marineAreaNames] (see
  /// marine_area_codes.dart), confirmed via the NII Geoshape code list
  /// (docs/data-format-notes.md "予報区一覧・GeoJSON入手方法（確定）").
  final String areaCode;

  /// `Area/Name` as given directly in this report (documented field; kept
  /// separately from [marineAreaNames] in case JMA's wording differs
  /// slightly from NII Geoshape's — callers wanting a guaranteed name
  /// should prefer `marineAreaNames[areaCode]`).
  final String? areaName;

  /// `MeteorologicalInfo/Name` — the period-block label this forecast came
  /// from (documented example: "今日から明日"). Null if not present.
  final String? periodLabel;

  /// Base (現況〜基準時点) wave height in meters — documented as a plain
  /// numeric value with a `type="波高" unit="m"` attribute (NOT one of
  /// JMA's 海上分布予報 class-string buckets — see
  /// docs/data-format-notes.md "波の高さの表現形式（重要な訂正）"). Null if
  /// unavailable (documented `condition="予報なし"` case, e.g. sea-ice
  /// areas).
  final double? baseHeightM;

  /// JMA's human-readable Base height text (documented `description`
  /// attribute, e.g. "４メートル"). Null if not present.
  final String? baseDescription;

  /// Up to 2 変化点 (see [MarineWaveBecoming] doc comment for why these
  /// aren't resolved to absolute times yet).
  final List<MarineWaveBecoming> becoming;
}

/// Parses a VPCY51 (地方海上予報) report XML — the document fetched from a
/// `<link type="application/xml">` URL out of the JMA `regular.xml` Atom
/// feed (mirroring how [parseJmaTyphoonXml] in jma_xml_parser.dart handles
/// `extra.xml`/VPTW60 — see docs/data-format-notes.md for the feed lookup
/// step; this function only handles the electronic-bulletin document
/// itself).
///
/// See this file's top-of-file doc comment for the "not yet verified
/// against real data" caveat that applies to every field this function
/// looks for.
///
/// Returns one [MarineWaveForecast] per (period block × sea area) that has
/// a 波 (wave) property, across every `MeteorologicalInfos[@type="地方海域
/// の予報"]` container in the document (documented as there being exactly
/// one such container per report, but this function doesn't assume that —
/// it collects across however many are present, the same "don't assume a
/// fixed shape beyond what's needed" approach [JmaTyphoonInfo.forecastTrack]
/// takes).
///
/// Throws [JmaMarineXmlParseException] if the document doesn't parse as XML
/// at all, or clearly isn't a 地方海上予報 report (wrong root element /
/// InfoKind), or has no 地方海域の予報 data whatsoever — those are cases
/// where returning a silently-empty list would hide a real problem (wrong
/// URL, feed format change, etc.).
List<MarineWaveForecast> parseJmaMarineXml(String xmlString) {
  final XmlDocument doc;
  try {
    doc = XmlDocument.parse(xmlString);
  } on XmlException catch (e) {
    throw JmaMarineXmlParseException('XMLとして解析できませんでした: ${e.message}');
  }

  final XmlElement report;
  try {
    report = doc.rootElement;
  } on StateError {
    throw JmaMarineXmlParseException('XML文書にルート要素が見つかりませんでした（空のレスポンス等の可能性）。');
  }
  if (report.name.local != 'Report') {
    throw JmaMarineXmlParseException(
      'ルート要素が<Report>ではありません（<${report.name.local}>）。VPCY51電文のURLか確認してください。',
    );
  }

  final head = _firstDescendant(report, 'Head');
  final body = _firstDescendant(report, 'Body');
  if (head == null || body == null) {
    throw JmaMarineXmlParseException('<Head>または<Body>要素が見つかりませんでした。');
  }

  final infoKind = _childText(head, 'InfoKind');
  if (infoKind == null || !infoKind.contains('地方海上予報')) {
    throw JmaMarineXmlParseException(
      '地方海上予報（VPCY51）ではないようです（InfoKind: ${infoKind ?? "不明"}）。',
    );
  }

  // MeteorologicalInfos（複数形）は@typeで"気象要因"/"観測実況"/"地方海域の予報"に
  // 分岐する（docs/data-format-notes.md参照）。ここでは"地方海域の予報"のコンテナ
  // だけを対象にする（bodyスコープ内、jma_xml_parser.dartと同じ探索範囲の方針）。
  final marineInfosContainers = body.descendants
      .whereType<XmlElement>()
      .where((e) => e.name.local == 'MeteorologicalInfos' && e.getAttribute('type') == '地方海域の予報')
      .toList();

  if (marineInfosContainers.isEmpty) {
    throw JmaMarineXmlParseException('「地方海域の予報」のブロックが見つかりませんでした。');
  }

  final results = <MarineWaveForecast>[];

  for (final container in marineInfosContainers) {
    // MeteorologicalInfo（単数形）1つ＝1つの期間ブロック（例"今日から明日"）。
    final infoBlocks = container.childElements.where((e) => e.name.local == 'MeteorologicalInfo');
    for (final info in infoBlocks) {
      final periodLabel = _emptyToNull(_childText(info, 'Name'));

      // このMeteorologicalInfo内のProperty[@type="波"]を全て拾う（Item/Kindの
      // 深さはドキュメント上"Item/Kind/Property"だが、正確なネスト段数が実データ
      // 未検証のため深さを問わずdescendantsで探す——jma_xml_parser.dartと同じ
      // 「タグ名の完全一致より属性値での識別を優先」方針）。
      final waveProperties = info.descendants
          .whereType<XmlElement>()
          .where((e) => e.name.local == 'Property' && e.getAttribute('type') == '波')
          .toList();

      for (final prop in waveProperties) {
        // Areaはドキュメント上"Item/Kind/Property" + "Area/Name+Code"という書き方
        // （"+"＝Itemの子としてKindとAreaが並ぶ、Propertyの子ではない）なので、
        // Property自身の下ではなく、その親であるItemから探す。
        final itemEl = _ancestor(prop, 'Item');
        final areaEl = itemEl == null ? null : _firstDescendant(itemEl, 'Area');
        final areaCode = _emptyToNull(_childText(areaEl, 'Code'));
        if (areaCode == null) {
          // Areaコードが無ければどの区域か特定できないため、このProperty自体を
          // 読み捨てる（他のparserの「読めないフィールドは省く」方針と同じ）。
          continue;
        }
        final areaName = _emptyToNull(_childText(areaEl, 'Name'));

        // WaveHeightPartの有無に関わらず探せるよう、Base/Becomingは
        // WaveHeightPart配下優先、無ければProperty直下を探すフォールバック。
        // Base/Becomingはドキュメント上WaveHeightPartの直接の子（兄弟同士）と
        // されているため、どちらも同じ深さ（直接の子）で探して扱いを揃える。
        final waveHeightPart = _firstDescendant(prop, 'WaveHeightPart') ?? prop;
        final baseEl = waveHeightPart.childElements.where((e) => e.name.local == 'Base').firstOrNull;
        final baseWaveHeightEl = baseEl == null ? null : _firstByAttribute(baseEl, 'type', '波高');
        final baseHeightM = baseWaveHeightEl == null ? null : _parseWaveHeight(baseWaveHeightEl.innerText.trim());
        final baseDescription = _emptyToNull(baseWaveHeightEl?.getAttribute('description'));

        final becomingEls = waveHeightPart.childElements.where((e) => e.name.local == 'Becoming');
        final becoming = <MarineWaveBecoming>[];
        for (final b in becomingEls) {
          final waveHeightEl = _firstByAttribute(b, 'type', '波高');
          becoming.add(MarineWaveBecoming(
            // TimeModifierはBecoming要素自身の属性と文書化されているが、稀に値側の
            // 要素に付く可能性も考慮し、無ければ値側の属性もフォールバックで見る。
            timeModifierText: _emptyToNull(b.getAttribute('TimeModifier')) ??
                _emptyToNull(waveHeightEl?.getAttribute('TimeModifier')),
            heightM: waveHeightEl == null ? null : _parseWaveHeight(waveHeightEl.innerText.trim()),
            description: _emptyToNull(waveHeightEl?.getAttribute('description')),
          ));
        }

        results.add(MarineWaveForecast(
          areaCode: areaCode,
          areaName: areaName,
          periodLabel: periodLabel,
          baseHeightM: baseHeightM,
          baseDescription: baseDescription,
          becoming: becoming,
        ));
      }
    }
  }

  return results;
}

/// Parses a wave-height value element's text content into meters. Returns
/// null for empty text (documented `condition="予報なし"` case leaves the
/// element's value empty) or text that doesn't parse as a number.
double? _parseWaveHeight(String text) {
  if (text.isEmpty) return null;
  return double.tryParse(text);
}

String? _emptyToNull(String? s) => (s == null || s.isEmpty) ? null : s;

/// Direct child element (not deep descendant) matching [localName], with any
/// namespace prefix ignored (see jma_xml_parser.dart's [_childText] doc
/// comment for why prefix stripping is used here too — this VPCY51 XML
/// mixes in `jmx_eb:`-prefixed elements the same way VPTW60 does).
String? _childText(XmlElement? parent, String localName) {
  if (parent == null) return null;
  for (final c in parent.childElements) {
    if (c.name.local == localName) return c.innerText.trim();
  }
  return null;
}

/// First element anywhere under [node] (any depth) whose tag matches
/// [localName], ignoring namespace prefix.
XmlElement? _firstDescendant(XmlNode node, String localName) {
  for (final e in node.descendants.whereType<XmlElement>()) {
    if (e.name.local == localName) return e;
  }
  return null;
}

/// First element anywhere under [node] whose [attrName] attribute equals
/// [attrValue].
XmlElement? _firstByAttribute(XmlNode node, String attrName, String attrValue) {
  for (final e in node.descendants.whereType<XmlElement>()) {
    if (e.getAttribute(attrName) == attrValue) return e;
  }
  return null;
}

/// Walks upward from [node]'s parent chain, returning the first ancestor
/// element whose tag matches [localName] (ignoring namespace prefix). Used
/// for [MarineWaveForecast]'s Area lookup, which needs to go *up* from a
/// `Property[@type="波"]` to its enclosing `Item` (Area is documented as a
/// sibling of Kind under Item, not a descendant of Property) — unlike this
/// file's other helpers, which only search downward.
XmlElement? _ancestor(XmlElement node, String localName) {
  for (XmlNode? n = node.parent; n != null; n = n.parent) {
    if (n is XmlElement && n.name.local == localName) return n;
  }
  return null;
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
