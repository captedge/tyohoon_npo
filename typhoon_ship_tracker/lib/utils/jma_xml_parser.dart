import 'package:xml/xml.dart';

import '../models/track_point.dart';
import 'interpolation.dart' show LatLng;

/// Thrown when a fetched document doesn't look like a VPTW60 (台風解析・予報
///情報) report, or is missing fields this parser relies on to make sense of
/// the data (e.g. no MeteorologicalInfo at all). [message] is meant to be
/// shown to the user/logs as-is, mirroring [VoyagePlanParseException]'s style
/// (see voyage_plan_parser.dart).
class JmaXmlParseException implements Exception {
  JmaXmlParseException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// One forecast point from a VPTW60 report's "予報" MeteorologicalInfo block.
///
/// Unlike JTWC's [JtwcForecastPoint] (see jtwc_parser.dart), this carries an
/// absolute JST timestamp rather than an "hours from now" offset — JMA's XML
/// gives full year/month/day for every timestamp (`ReportDateTime` and each
/// MeteorologicalInfo's own `DateTime`), so there's no JTWC-style "day number
/// only, which month?" ambiguity to resolve against a reference "now". This
/// also means [JmaTyphoonInfo.toTrackPoints] can build [TrackPoint]s directly
/// without any reference-time disambiguation step.
class JmaForecastPoint {
  const JmaForecastPoint({
    required this.validAtJst,
    required this.position,
    this.classification,
    this.centralPressureHpa,
  });

  /// Plain (non-UTC-tagged) JST wall-clock DateTime, built the same way as
  /// the rest of this app's DateTimes (see jtwc_parser.dart's issuedAtJst
  /// doc comment for why: this app never calls toUtc()/toLocal(), so every
  /// DateTime must directly represent JST wall-clock fields rather than being
  /// tagged as UTC/local and relying on the OS timezone for correct display).
  final DateTime validAtJst;
  final LatLng position;

  /// e.g. "台風(TS)", "熱帯低気圧(TD)" — the 熱帯擾乱種類 (TyphoonClass) text
  /// at this forecast time. Null if the source XML didn't have one.
  final String? classification;

  final int? centralPressureHpa;
}

/// Parsed-out fields from one VPTW60 (台風解析・予報情報) report XML.
///
/// Scope is deliberately narrow, matching what this app currently needs (台
/// 風・船の位置と距離のみ, TASKS.md): current position/pressure/classification
/// plus the forecast track. Wind-radii fields (暴風域/強風域/暴風警戒域 and
/// their 予報円/警戒域 radii) are present in the source XML (see
/// docs/data-format-notes.md) but intentionally not parsed here — add them
/// if/when a feature (e.g. a JMA-native "forecast cone" overlay) needs them.
class JmaTyphoonInfo {
  const JmaTyphoonInfo({
    this.eventId,
    this.name,
    this.nameKana,
    this.number,
    this.reportDateTimeJst,
    this.observedAtJst,
    this.classification,
    this.centralPressureHpa,
    this.position,
    this.forecastTrack = const [],
  });

  static const empty = JmaTyphoonInfo();

  /// Head/EventID — identifies one low/typhoon system across its successive
  /// bulletins (e.g. "TC2613"). Useful later for detecting "is this still
  /// the same storm as last fetch" without comparing name/number (both of
  /// which can be empty before a system is named/numbered).
  final String? eventId;

  /// Head/Body 呼称(TyphoonNamePart): Name/NameKana/Number. All three are
  /// empty strings (parsed here as null) before the system has been named
  /// and numbered — a VPTW60 report can be issued for a plain "熱帯低気圧
  /// (TD)" forecast to become a typhoon, in which case there's nothing to
  /// show here yet (see docs/data-format-notes.md 2026-07-28 entry).
  final String? name;
  final String? nameKana;
  final String? number;

  /// Head/ReportDateTime — when this bulletin was issued (JST, plain
  /// wall-clock DateTime, see [JmaForecastPoint.validAtJst] doc comment).
  final DateTime? reportDateTimeJst;

  /// The 実況 (current-conditions) MeteorologicalInfo's own DateTime — the
  /// time [position]/[classification]/[centralPressureHpa] are valid for.
  /// Usually very close to [reportDateTimeJst] but kept separate since
  /// they're distinct fields in the source XML.
  final DateTime? observedAtJst;

  /// 実況時点の熱帯擾乱種類 (e.g. "台風(TS)", "熱帯低気圧(TD)").
  final String? classification;
  final int? centralPressureHpa;

  /// 実況位置 (current position). Null if the report had no 実況 block or
  /// its coordinate couldn't be parsed — in which case there's nothing to
  /// plot for "now", even if a forecast track parsed fine.
  final LatLng? position;

  /// 予報 (forecast) points, sorted by [JmaForecastPoint.validAtJst]
  /// ascending. How many are present (12/24/48/72/96/120h) varies by report
  /// — this app doesn't assume a fixed set of offsets, unlike the JTWC
  /// parser's fixed 12/24/36/48/60h pattern.
  final List<JmaForecastPoint> forecastTrack;

  bool get isEmpty => position == null && forecastTrack.isEmpty;

  /// The English stage-abbreviation JMA embeds in [classification] — e.g.
  /// "TD" out of "熱帯低気圧(TD)", "TS" out of "台風(TS)" — the same code
  /// shown on JMA's own official weather charts (Asia-Pacific surface
  /// analysis etc.). 2026-07-28 user request: use this code as-is for the
  /// map label rather than inventing a separate stage indicator, including
  /// *before* a 号/name is assigned (熱帯低気圧 forecast stage) — see
  /// [designation]. Null if [classification] is null or doesn't end in a
  /// parenthesized code.
  String? get classCode {
    final c = classification;
    if (c == null) return null;
    return RegExp(r'\(([A-Z]+)\)\s*$').firstMatch(c)?.group(1);
  }

  /// Combined "<number><stage code>"-style label for display, e.g. "13TS"
  /// (号13、現在の段階TS — see [classCode]) or, before a 号 is assigned
  /// (熱帯低気圧 forecast stage — see [name]/[number] doc comment), just the
  /// stage code alone, e.g. "TD". Format confirmed with the user 2026-07-28:
  /// number first, then the official stage code (no separator, matching how
  /// this is prefixed with the source name, e.g. "JMA13TS", by the caller —
  /// see map_screen.dart), then the name in parentheses if assigned. Null
  /// only if there's neither a number nor a recognizable stage code (should
  /// be rare — every real VPTW60 report seen so far has a classification).
  String? get designation {
    final head = '${number ?? ''}${classCode ?? ''}';
    if (head.isEmpty) return null;
    return name == null ? head : '$head ($name)';
  }

  /// Converts this into the same [TrackPoint] list shape the rest of the app
  /// (interpolation, MapPainter) already works with — the 実況 position (if
  /// any) followed by the forecast track, both carrying absolute JST times
  /// directly (no reference-time offset math needed, unlike
  /// JtwcTyphoonInfo's forecastTrack). Returns an empty list if there's
  /// nothing to plot ([isEmpty]).
  List<TrackPoint> toTrackPoints() {
    final points = <TrackPoint>[];
    if (position != null && observedAtJst != null) {
      points.add(TrackPoint(
        time: observedAtJst!,
        latitude: position!.latitude,
        longitude: position!.longitude,
        label: classification,
      ));
    }
    for (final f in forecastTrack) {
      points.add(TrackPoint(
        time: f.validAtJst,
        latitude: f.position.latitude,
        longitude: f.position.longitude,
        label: f.classification,
      ));
    }
    return points;
  }
}

/// Parses a VPTW60 (台風解析・予報情報) report XML — the document fetched
/// directly from a `<link type="application/xml">` URL out of the JMA
/// `extra.xml` Atom feed (see docs/data-format-notes.md for the feed lookup
/// step; this function only handles the electronic-bulletin document itself,
/// not fetching the feed or resolving which entry is the latest one).
///
/// Throws [JmaXmlParseException] if the document doesn't parse as XML at
/// all, or clearly isn't a 台風解析・予報情報 report (wrong root element /
/// InfoKind, or no MeteorologicalInfo blocks whatsoever) — those are cases
/// where returning a silently-empty [JmaTyphoonInfo] would hide a real
/// problem (wrong URL, feed format change, etc.) rather than "this bulletin
/// just doesn't mention a named storm yet", which is the normal/expected
/// case handled by leaving individual fields null (see [JmaTyphoonInfo.name]
/// doc comment).
JmaTyphoonInfo parseJmaTyphoonXml(String xmlString) {
  final XmlDocument doc;
  try {
    doc = XmlDocument.parse(xmlString);
  } on XmlException catch (e) {
    throw JmaXmlParseException('XMLとして解析できませんでした: ${e.message}');
  }

  final XmlElement report;
  try {
    // rootElement throws a StateError (not XmlException) if the parsed
    // document has no element node at all (e.g. an empty/whitespace-only
    // input that still parses as valid XML) — caught here alongside the
    // parse-failure case above so both surface as the same kind of error to
    // callers instead of an uncaught StateError.
    report = doc.rootElement;
  } on StateError {
    throw JmaXmlParseException('XML文書にルート要素が見つかりませんでした（空のレスポンス等の可能性）。');
  }
  if (report.name.local != 'Report') {
    throw JmaXmlParseException(
      'ルート要素が<Report>ではありません（<${report.name.local}>）。VPTW60電文のURLか確認してください。',
    );
  }

  final head = _firstDescendant(report, 'Head');
  final body = _firstDescendant(report, 'Body');
  if (head == null || body == null) {
    throw JmaXmlParseException('<Head>または<Body>要素が見つかりませんでした。');
  }

  final infoKind = _childText(head, 'InfoKind');
  if (infoKind == null || !infoKind.contains('台風')) {
    throw JmaXmlParseException(
      '台風解析・予報情報（VPTW60）ではないようです（InfoKind: ${infoKind ?? "不明"}）。',
    );
  }

  final eventId = _emptyToNull(_childText(head, 'EventID'));
  final reportDateTimeJst = _parseJstIsoDateTime(_childText(head, 'ReportDateTime'));

  final namePart = _firstDescendant(body, 'TyphoonNamePart');
  final name = _emptyToNull(_childText(namePart, 'Name'));
  final nameKana = _emptyToNull(_childText(namePart, 'NameKana'));
  final number = _emptyToNull(_childText(namePart, 'Number'));

  final infos = _descendants(body, 'MeteorologicalInfo');
  if (infos.isEmpty) {
    throw JmaXmlParseException('<MeteorologicalInfo>（実況・予報）が見つかりませんでした。');
  }

  DateTime? observedAtJst;
  String? classification;
  int? centralPressureHpa;
  LatLng? position;
  final forecastTrack = <JmaForecastPoint>[];

  for (final info in infos) {
    final dtEl = info.childElements.where((e) => e.name.local == 'DateTime').firstOrNull;
    final dtType = dtEl?.getAttribute('type') ?? '';
    final validAt = _parseJstIsoDateTime(dtEl?.innerText.trim());

    final classEl = _firstDescendant(info, 'TyphoonClass');
    final infoClassification = _emptyToNull(classEl?.innerText.trim());

    final coordEl = _firstByAttribute(info, 'type', '中心位置（度）');
    final infoPosition = coordEl == null ? null : _parseJmaCoordinate(coordEl.innerText.trim());

    final pressureEl = _firstDescendant(info, 'Pressure');
    final infoPressure = pressureEl == null ? null : int.tryParse(pressureEl.innerText.trim());

    if (dtType == '実況') {
      observedAtJst = validAt;
      classification = infoClassification;
      centralPressureHpa = infoPressure;
      position = infoPosition;
    } else if (dtType.startsWith('予報')) {
      if (infoPosition != null && validAt != null) {
        forecastTrack.add(JmaForecastPoint(
          validAtJst: validAt,
          position: infoPosition,
          classification: infoClassification,
          centralPressureHpa: infoPressure,
        ));
      }
    }
    // Other DateTime types (if any future report variant has them) are
    // ignored rather than treated as an error — matches the JTWC parser's
    // "fields that don't match are simply left out" philosophy.
  }

  forecastTrack.sort((a, b) => a.validAtJst.compareTo(b.validAtJst));

  return JmaTyphoonInfo(
    eventId: eventId,
    name: name,
    nameKana: nameKana,
    number: number,
    reportDateTimeJst: reportDateTimeJst,
    observedAtJst: observedAtJst,
    classification: classification,
    centralPressureHpa: centralPressureHpa,
    position: position,
    forecastTrack: forecastTrack,
  );
}

/// Parses one of this XML's `+<lat>+<lon>/`-style coordinate strings (e.g.
/// "+5.6+153.8/", south/west given as "-"), as seen in `jmx_eb:Coordinate`/
/// `jmx_eb:BasePoint` elements with `type="中心位置（度）"` (the decimal-degree
/// variant; the degree-minute variant, `type="中心位置（度分）"`, is a
/// duplicate of the same position and not parsed by this app — see
/// docs/data-format-notes.md). Returns null if [text] doesn't match (e.g. an
/// empty element for an unavailable position).
LatLng? _parseJmaCoordinate(String text) {
  final m = RegExp(r'^([+-]\d+(?:\.\d+)?)([+-]\d+(?:\.\d+)?)/$').firstMatch(text);
  if (m == null) return null;
  return LatLng(double.parse(m.group(1)!), double.parse(m.group(2)!));
}

/// Parses this XML's ISO-8601-with-offset DateTime text (e.g.
/// "2026-07-17T04:05:00+09:00") into a plain (non-UTC-tagged) DateTime whose
/// fields are read directly off the string — deliberately not
/// `DateTime.parse`, which would tag the result as UTC and normalize it to
/// the UTC instant, shifting the wall-clock fields away from the JST values
/// actually written in the XML. This app's convention (see
/// jtwc_parser.dart's issuedAtJst doc comment) is that every DateTime is a
/// plain value directly representing JST wall-clock time; this keeps that
/// convention regardless of the device's OS timezone.
///
/// Every timestamp seen in a VPTW60 report uses a "+09:00" offset (this app
/// only ever talks to the JMA feed for JST-region typhoons), so a non-"+09:00"
/// offset is treated as a schema surprise worth failing loudly on rather than
/// silently mis-displaying — throws [JmaXmlParseException] in that case. A
/// missing offset entirely (regex group not matched, e.g. a hypothetical
/// "2026-07-17T04:05:00" with no suffix) is treated the same as "+09:00" —
/// there's nothing to reject, just nothing to double-check either — rather
/// than as an error.
/// Returns null if [text] is null or doesn't match the expected pattern at
/// all (missing/malformed element, not a wrong-offset one).
DateTime? _parseJstIsoDateTime(String? text) {
  if (text == null) return null;
  final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(Z|[+-]\d{2}:\d{2})?$')
      .firstMatch(text);
  if (m == null) return null;
  final offset = m.group(7);
  if (offset != null && offset != '+09:00') {
    throw JmaXmlParseException(
      '日時のタイムゾーンが想定外です（"$offset"、+09:00のみ対応）: $text',
    );
  }
  return DateTime(
    int.parse(m.group(1)!),
    int.parse(m.group(2)!),
    int.parse(m.group(3)!),
    int.parse(m.group(4)!),
    int.parse(m.group(5)!),
    int.parse(m.group(6)!),
  );
}

String? _emptyToNull(String? s) => (s == null || s.isEmpty) ? null : s;

/// Direct child element (not deep descendant) matching [localName], with any
/// namespace prefix ignored — this XML redeclares its default namespace
/// separately on `<Head>`/`<Body>` and mixes in `jmx_eb:`-prefixed elements,
/// so matching on `.name.local` (prefix-stripped tag name) rather than doing
/// full namespace-URI resolution is the pragmatic choice here, mirroring how
/// jtwc_parser.dart takes a "good enough for this app's needs" approach
/// rather than a fully general one.
String? _childText(XmlElement? parent, String localName) {
  if (parent == null) return null;
  for (final c in parent.childElements) {
    if (c.name.local == localName) return c.innerText.trim();
  }
  return null;
}

/// First element anywhere under [node] (any depth) whose tag matches
/// [localName], ignoring namespace prefix (see [_childText] doc comment for
/// why prefix stripping is used instead of full namespace resolution).
XmlElement? _firstDescendant(XmlNode node, String localName) {
  for (final e in node.descendants.whereType<XmlElement>()) {
    if (e.name.local == localName) return e;
  }
  return null;
}

/// All elements anywhere under [node] whose tag matches [localName].
List<XmlElement> _descendants(XmlNode node, String localName) {
  return node.descendants.whereType<XmlElement>().where((e) => e.name.local == localName).toList();
}

/// First element anywhere under [node] whose [attrName] attribute equals
/// [attrValue] — used to find the "中心位置（度）" coordinate regardless of
/// whether it's a `Coordinate` element (実況's CenterPart) or a `BasePoint`
/// element (forecast's ProbabilityCircle), since both use the same `type`
/// attribute value for the decimal-degree position (see
/// docs/data-format-notes.md).
XmlElement? _firstByAttribute(XmlNode node, String attrName, String attrValue) {
  for (final e in node.descendants.whereType<XmlElement>()) {
    if (e.getAttribute(attrName) == attrValue) return e;
  }
  return null;
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
