import 'dart:convert';
import 'dart:io';

import 'package:xml/xml.dart';

import 'jtwc_parser.dart' show parseJtwcWarningText;

/// Thrown for network/HTTP-layer failures while fetching the JTWC RSS feed
/// or an individual TC Warning Text product — distinct from any parse
/// failure of the *pasted-text-shaped* result this returns, which is
/// jtwc_parser.dart's existing concern (parseJtwcWarningText), not this
/// file's. Mirrors jma_feed_fetcher.dart's JmaFetchException.
class JtwcFetchException implements Exception {
  JtwcFetchException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// JTWC's "current systems" RSS feed (2026-07-29 addition) — the JTWC
/// equivalent of JMA's extra.xml list feed (see jma_feed_fetcher.dart).
/// Confirmed live 2026-07-29 by loading the JTWC site
/// (metoc.navy.mil/jtwc/jtwc.html) in a real browser and inspecting its
/// network requests: this is the URL the page's own JavaScript loads to
/// populate its "JTWC Tropical Warnings" section, grouped into <item>s by
/// region. A sample <item> (see [_relevantItemGuid] below) looks like:
///
///   <item>
///     <title>Current Northwest Pacific/North Indian Ocean* Tropical Systems</title>
///     <description><![CDATA[<p><b>Typhoon  12W (Dolphin) Warning #09 </b><br>
///   <b>Issued at 29/0300Z<b>
///   <ul>
///   <li><a href='https://www.metoc.navy.mil/jtwc/products/wp1226web.txt' target='newwin'>TC Warning Text </a></li>
///    <li><a href='.../wp1226.gif' ...>TC Warning Graphic</a></li>
///    ... (other product links: .tcw/.kmz/fix.txt/prog.txt)
///   <p><i>* Includes Bay of Bengal and Arabian Sea</i>
///   ]]></description>
///     <guid>NWPAC-NIO-WARNINGS</guid>
///   </item>
///
/// When more than one storm is active in a region at once, they're simply
/// concatenated one after another inside the same <description> (confirmed
/// 2026-07-29 by observing this for the feed's Central/Eastern Pacific
/// item, which had two storms back to back) — see
/// [_findWarningTextUrls]'s doc comment for how this file handles that.
const _rssFeedUrl = 'https://www.metoc.navy.mil/jtwc/rss/jtwc.rss';

/// The <guid> of the RSS <item> covering storms relevant to this app's
/// displayed map area (N5-50/E85-170): JTWC's "Northwest Pacific/North
/// Indian Ocean" category, which — per the feed's own footnote — "Includes
/// Bay of Bengal and Arabian Sea". The feed's other categories
/// (EPAC-CPAC-WARNINGS for Central/Eastern Pacific, SH-WARNINGS for the
/// Southern Hemisphere, TROPICAL-ADVISORIES for broader non-storm-specific
/// advisories) cover systems entirely outside this app's map area and are
/// simply never looked at — a coarser but much simpler filter than checking
/// each storm's own parsed position, and sufficient given the region is
/// visually distinct from this app's map bounds (the "Arabian Sea" part of
/// this category is the only sliver west of the app's 85°E edge; a storm
/// there would still parse and plot, just off the left edge of the map,
/// same as any other out-of-view position — no special-case rejection
/// needed).
const _relevantItemGuid = 'NWPAC-NIO-WARNINGS';

/// A browser-like User-Agent (2026-07-29 finding): unlike JMA's feed/
/// bulletin URLs (jma_feed_fetcher.dart, no special headers needed), the
/// individual JTWC warning-text files under /jtwc/products/ returned empty
/// responses when fetched with a plain/default HTTP client during
/// development, but loaded fine through an actual browser — suggesting
/// some bot-filtering keyed on User-Agent (the RSS feed itself worked
/// either way). Sent on every request in this file, including the RSS
/// fetch, as a blanket defensive measure rather than only on the request
/// that was observed to need it.
const _userAgent =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';

Future<String> _fetchText(String url) async {
  final client = HttpClient();
  client.connectionTimeout = const Duration(seconds: 15);
  try {
    final request = await client.getUrl(Uri.parse(url));
    request.headers.set(HttpHeaders.userAgentHeader, _userAgent);
    final response = await request.close();
    if (response.statusCode != 200) {
      throw JtwcFetchException('HTTP ${response.statusCode}（$url）');
    }
    return await response.transform(utf8.decoder).join();
  } on JtwcFetchException {
    rethrow;
  } on SocketException catch (e) {
    throw JtwcFetchException('ネットワークに接続できませんでした: ${e.message}');
  } on HttpException catch (e) {
    throw JtwcFetchException('HTTPエラー: ${e.message}');
  } finally {
    client.close();
  }
}

/// Finds every "TC Warning Text" product URL inside the NWPAC-NIO-WARNINGS
/// <item>'s HTML-in-CDATA <description>, in the order they appear there —
/// each one a plain-text bulletin, in exactly the format jtwc_parser.dart's
/// parseJtwcWarningText already parses from a manual paste. When more than
/// one product is active in the region at once, their entries are simply
/// concatenated one after another inside the same <description> (confirmed
/// 2026-07-29 by observing this shape for the feed's Central/Eastern
/// Pacific item, which had two storms back to back), so each product
/// contributes exactly one "web.txt" link here — no separate
/// de-duplication step is needed the way jma_feed_fetcher.dart's
/// extra.xml-based equivalent needs one (that feed lists individual
/// bulletins over time, not one entry per distinct storm; this RSS feed's
/// <description> already only ever lists *currently active* products).
///
/// Not every "web.txt" link found here is a numbered/named storm's warning
/// text — a "TROPICAL CYCLONE FORMATION ALERT" (TCFA, issued for a
/// pre-formation INVEST area with no number/name yet, e.g. "INVEST 94W")
/// shares the exact same product naming/link shape (2026-08-03 report: one
/// showed up here and got auto-filled into a Typhoon slot, which then
/// blocked Save with "couldn't find a designation" until the user manually
/// cleared the text). This function itself stays a dumb "every web.txt
/// link, in order" list — the designation-based filtering that excludes
/// TCFAs belongs in this file's callers (below), which already know how to
/// parse a candidate's text and can make that call per-candidate rather
/// than by guessing from the URL alone.
///
/// Returns an empty list if the category currently has no active storm at
/// all (its <description> is then just a "No Current Tropical Cyclone
/// Warnings" placeholder, the same shape the Southern Hemisphere item
/// always has when quiet — confirmed 2026-07-29) — a normal, expected
/// outcome, not an error. Also returns an empty list if the feed has no
/// NWPAC-NIO-WARNINGS <item> at all (shouldn't happen based on the samples
/// seen so far, but treated the same "nothing to fetch" way rather than as
/// an error).
Future<List<String>> _findWarningTextUrls() async {
  final feedXml = await _fetchText(_rssFeedUrl);
  final XmlDocument doc;
  try {
    doc = XmlDocument.parse(feedXml);
  } on XmlException catch (e) {
    throw JtwcFetchException('JTWC一覧フィード（RSS）のXMLが不正です: ${e.message}');
  }

  for (final item in doc.descendants.whereType<XmlElement>().where((e) => e.name.local == 'item')) {
    final guid = _firstChildText(item, 'guid');
    if (guid != _relevantItemGuid) continue;
    final description = _firstChildText(item, 'description') ?? '';
    // Single- or double-quoted href, ending in "web.txt" — the "TC Warning
    // Text" product's filename suffix, distinguishing it from the other
    // product links in the same <li> list (.gif/.tcw/.kmz/fix.txt/
    // prog.txt — see this file's class doc comment for a full sample).
    return RegExp(r'''href=['"]([^'"]+web\.txt)['"]''')
        .allMatches(description)
        .map((m) => m.group(1)!)
        .toList();
  }
  return [];
}

String? _firstChildText(XmlElement parent, String localName) {
  for (final c in parent.childElements) {
    if (c.name.local == localName) return c.innerText.trim();
  }
  return null;
}

/// Fetches the JTWC RSS feed, finds the first NWPAC/NIO-region storm's "TC
/// Warning Text" product (if any), and downloads it — returning the raw
/// text as-is, in exactly the shape a manual paste into the Information
/// dialog's JTWC text box already produces.
///
/// Deliberately returns plain text rather than a parsed [JtwcTyphoonInfo]
/// (unlike jma_feed_fetcher.dart's fetchLatestJmaTyphoon, which does parse):
/// JTWC only has this one representation in the app (pasted-or-fetched
/// text), so callers (map_screen.dart) feed this straight into the same
/// parseJtwcWarningText / typhoonControllers[i] text box a manual paste
/// already uses — no separate fetched-vs-pasted state to keep in sync, and
/// the existing persistence (AppStateStorage's pastedText field) already
/// covers a fetch result with no changes needed there.
///
/// Returns null (not an error) when the region currently has no active,
/// *numbered/named* storm — this includes both "nothing at all in the
/// feed" and "the feed only has a Tropical Cyclone Formation Alert for an
/// as-yet-unnumbered INVEST" (see [_hasDesignation]'s doc comment: a TCFA
/// is skipped the same as no product at all, rather than being returned as
/// if it were a usable warning). Throws [JtwcFetchException] for network/
/// HTTP failures fetching the *list* feed itself; a failure fetching one
/// individual candidate is skipped in favour of trying the next one (same
/// "one bad candidate shouldn't hide the others" choice
/// [fetchActiveJtwcWarningTexts] makes), capped at [maxCandidates] fetches.
Future<String?> fetchLatestJtwcWarningText({int maxCandidates = 10}) async {
  final urls = await _findWarningTextUrls();
  for (final url in urls.take(maxCandidates)) {
    String text;
    try {
      text = await _fetchText(url);
    } catch (_) {
      continue;
    }
    if (_hasDesignation(text)) return text;
  }
  return null;
}

/// Whether [text] parses as a numbered/named tropical cyclone warning
/// (jtwc_parser.dart's designation pattern — "TYPHOON/TROPICAL STORM/...
/// <number> (<name>)") rather than some other NWPAC-NIO-WARNINGS product
/// that happens to also end in "web.txt", most notably a "TROPICAL CYCLONE
/// FORMATION ALERT" (TCFA) issued for a pre-formation INVEST area, which
/// has no number/name to give (e.g. "INVEST 94W" — 94 is an invest slot
/// number, not a storm number, and never appears in the "<number>(<name>)"
/// shape this app tracks). Used by both fetch functions in this file to
/// skip such candidates the same way "no active storm" is already handled,
/// rather than letting one through to auto-fill a Typhoon slot with text
/// that Save-time validation (map_screen.dart) would then reject anyway —
/// 2026-08-03 report: that used to require the user to notice the red
/// error and manually clear the text box before Save would work again.
bool _hasDesignation(String text) => parseJtwcWarningText(text).designation != null;

/// Fetches up to [maxResults] currently-active storms' "TC Warning Text"
/// bulletins from the NWPAC-NIO-WARNINGS region (2026-07-29 addition, for
/// the Information dialog's "Fetch All" button — 複数台風が同時に発表され
/// ている場合に台風1/2/3へまとめて自動入力する機能、TASKS.md参照), in the
/// order [_findWarningTextUrls] returns them (i.e. the order they appear in
/// the feed's <description>, which had no particular documented ordering
/// guarantee beyond "however JTWC lists them" — good enough for filling
/// slots 1/2/3 in some stable order, without needing to rank them).
///
/// Unlike jma_feed_fetcher.dart's fetchActiveJmaTyphoons, no
/// de-duplication step is needed here — see [_findWarningTextUrls]'s doc
/// comment for why (this feed already only lists currently-active storms,
/// one entry per storm, not a rolling history of past bulletins).
///
/// Returns an empty list (not an error) if the region currently has no
/// active, numbered/named storm — a Tropical Cyclone Formation Alert (TCFA,
/// for a not-yet-numbered INVEST) is skipped rather than counted as a
/// result, same as [fetchLatestJtwcWarningText] (see [_hasDesignation]'s
/// doc comment — 2026-08-03 report: one used to get auto-filled into a
/// Typhoon slot and block Save until manually cleared). Throws
/// [JtwcFetchException] for network/HTTP failures fetching the *list* feed
/// itself; a failure fetching one individual candidate bulletin is skipped
/// rather than aborting the whole call, so one bad bulletin doesn't hide
/// the others (mirrors fetchActiveJmaTyphoons's same choice).
Future<List<String>> fetchActiveJtwcWarningTexts({int maxResults = 3, int maxCandidates = 10}) async {
  final urls = await _findWarningTextUrls();
  final results = <String>[];
  for (final url in urls.take(maxCandidates)) {
    if (results.length >= maxResults) break;
    String text;
    try {
      text = await _fetchText(url);
    } catch (_) {
      // Skip a single bad candidate (network hiccup for just this one
      // bulletin) rather than aborting the whole batch — see doc comment.
      continue;
    }
    if (!_hasDesignation(text)) {
      // Not a numbered/named storm's warning text (e.g. a TCFA) — see
      // _hasDesignation's doc comment. Skip it like any other
      // not-currently-a-trackable-storm candidate, rather than adding it
      // to results.
      continue;
    }
    results.add(text);
  }
  return results;
}
