import '../models/ship_waypoint.dart';

/// Thrown when a voyage-plan CSV can't be parsed (wrong column count on a
/// data row, unrecognized hemisphere letter, etc.). [message] is meant to be
/// shown to the user as-is (see the import dialog).
class VoyagePlanParseException implements Exception {
  VoyagePlanParseException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Parses a JRC ECDIS/NAVTOR route CSV export into a list of [ShipWaypoint]s.
///
/// Format (confirmed against a real export, `NEG AW-KII.csv`, and
/// documented in `docs/data-format-notes.md`):
/// - Comment lines start with `//` (including the header row); blank lines
///   are also skipped.
/// - Data rows have 17 comma-separated columns:
///   `WPT No., LATdeg, LATmin, LAThemi(N/S), LONdeg, LONmin, LONhemi(E/W),
///   PORT[NM], STBD[NM], Arr.Rad[NM], Speed[kn], Sail(RL/GC), ROT[deg/min],
///   TurnRad[NM], TimeZone(HH:MM), TimeZoneHemi(E/W), Name`.
/// - Only WPT No./lat/lon/Speed/Name are used by this app; the distance,
///   radius, sail-mode, ROT, turn-radius, and timezone columns are ignored.
/// - The first waypoint (No. 000, the departure point) has `***` in place
///   of Speed (and the other unused columns) since there's no leg before
///   it — this is parsed as `speedKn: null`.
List<ShipWaypoint> parseVoyagePlanCsv(String csvText) {
  final waypoints = <ShipWaypoint>[];

  final lines = csvText.split(RegExp(r'\r\n|\r|\n'));
  for (var lineNo = 0; lineNo < lines.length; lineNo++) {
    final line = lines[lineNo].trim();
    if (line.isEmpty || line.startsWith('//')) continue;

    final fields = line.split(',');
    if (fields.length < 17) {
      throw VoyagePlanParseException(
        '${lineNo + 1}行目: 列数が足りません（${fields.length}列、17列必要）。'
        'JRC ECDISのルートCSV形式か確認してください。',
      );
    }

    final no = int.tryParse(fields[0].trim());
    final latDeg = double.tryParse(fields[1].trim());
    final latMin = double.tryParse(fields[2].trim());
    final latHemi = fields[3].trim().toUpperCase();
    final lonDeg = double.tryParse(fields[4].trim());
    final lonMin = double.tryParse(fields[5].trim());
    final lonHemi = fields[6].trim().toUpperCase();

    if (no == null || latDeg == null || latMin == null || lonDeg == null || lonMin == null) {
      throw VoyagePlanParseException('${lineNo + 1}行目: WPT No.または緯度経度を読み取れません。');
    }
    if (latHemi != 'N' && latHemi != 'S') {
      throw VoyagePlanParseException('${lineNo + 1}行目: 緯度の南北(N/S)が不正です: "$latHemi"');
    }
    if (lonHemi != 'E' && lonHemi != 'W') {
      throw VoyagePlanParseException('${lineNo + 1}行目: 経度の東西(E/W)が不正です: "$lonHemi"');
    }

    final latitude = (latDeg + latMin / 60) * (latHemi == 'S' ? -1 : 1);
    final longitude = (lonDeg + lonMin / 60) * (lonHemi == 'W' ? -1 : 1);

    final speedRaw = fields[10].trim();
    final speedKn = speedRaw == '***' || speedRaw.isEmpty ? null : double.tryParse(speedRaw);

    // Name is the last column; join any extra comma-split pieces back in
    // case a waypoint name itself contains a comma.
    final name = fields.sublist(16).join(',').trim();

    waypoints.add(ShipWaypoint(
      no: no,
      latitude: latitude,
      longitude: longitude,
      speedKn: speedKn,
      name: name,
    ));
  }

  if (waypoints.isEmpty) {
    throw VoyagePlanParseException('有効なウェイポイント行が見つかりませんでした。');
  }
  return waypoints;
}
