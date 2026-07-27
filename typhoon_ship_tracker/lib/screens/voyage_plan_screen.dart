import 'package:flutter/material.dart';

import '../models/ship_waypoint.dart';
import '../utils/voyage_plan.dart';

/// What `VoyagePlanScreen` returns via `Navigator.pop` when the user saves
/// (null if they cancel).
class VoyagePlanResult {
  const VoyagePlanResult({required this.waypoints, required this.departureTime});
  final List<ShipWaypoint> waypoints;
  final DateTime departureTime;
}

/// Table editor for the voyage plan: shows every waypoint (imported from a
/// CSV, or entered from scratch) with editable lat/lon/leg-speed/name, lets
/// the user insert or delete waypoints, and collects the departure date/time
/// used to compute each waypoint's arrival time (see
/// `lib/utils/voyage_plan.dart`'s `shipTrackFromWaypoints`).
///
/// Latitude/longitude are edited as decimal degrees here (rather than the
/// deg-min format used elsewhere in the app) to keep the editor simple for
/// the first version — see TASKS.md for a possible future deg-min input.
class VoyagePlanScreen extends StatefulWidget {
  const VoyagePlanScreen({
    super.key,
    required this.initialWaypoints,
    required this.initialDepartureTime,
  });

  final List<ShipWaypoint> initialWaypoints;
  final DateTime initialDepartureTime;

  @override
  State<VoyagePlanScreen> createState() => _VoyagePlanScreenState();
}

class _VoyagePlanScreenState extends State<VoyagePlanScreen> {
  late List<_Row> _rows;
  late DateTime _departureTime;
  String? _error;

  @override
  void initState() {
    super.initState();
    _departureTime = widget.initialDepartureTime;
    _rows = widget.initialWaypoints.isEmpty
        ? [_Row.empty()]
        : [for (final wp in widget.initialWaypoints) _Row.fromWaypoint(wp)];
  }

  @override
  void dispose() {
    for (final row in _rows) {
      row.dispose();
    }
    super.dispose();
  }

  void _insertAfter(int index) {
    setState(() {
      _rows.insert(index + 1, _Row.empty());
      _error = null;
    });
  }

  void _removeAt(int index) {
    if (_rows.length <= 1) return;
    setState(() {
      _rows.removeAt(index).dispose();
      _error = null;
    });
  }

  Future<void> _pickDepartureTime() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _departureTime,
      firstDate: DateTime(_departureTime.year - 2),
      lastDate: DateTime(_departureTime.year + 2),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_departureTime),
    );
    if (time == null) return;
    setState(() {
      _departureTime = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    });
  }

  String _formatDepartureTime(DateTime dt) {
    final dd = dt.day.toString().padLeft(2, '0');
    final mm = dt.month.toString().padLeft(2, '0');
    final hh = dt.hour.toString().padLeft(2, '0');
    final mi = dt.minute.toString().padLeft(2, '0');
    return '${dt.year}-$mm-$dd $hh:$mi';
  }

  void _save() {
    // Parse every row up front so a single bad cell reports one clear error
    // instead of a generic "couldn't save".
    final waypoints = <ShipWaypoint>[];
    for (var i = 0; i < _rows.length; i++) {
      final row = _rows[i];
      final lat = double.tryParse(row.latController.text.trim());
      final lon = double.tryParse(row.lonController.text.trim());
      if (lat == null || lat < -90 || lat > 90) {
        setState(() => _error = 'WP${i + 1}行目: 緯度が不正です（-90〜90の数値で入力してください）。');
        return;
      }
      if (lon == null || lon < -180 || lon > 180) {
        setState(() => _error = 'WP${i + 1}行目: 経度が不正です（-180〜180の数値で入力してください）。');
        return;
      }
      final speedText = row.speedController.text.trim();
      double? speedKn;
      if (speedText.isNotEmpty) {
        speedKn = double.tryParse(speedText);
        if (speedKn == null) {
          setState(() => _error = 'WP${i + 1}行目: 速力[kn]が数値として読み取れません。');
          return;
        }
      }
      waypoints.add(ShipWaypoint(
        no: i,
        latitude: lat,
        longitude: lon,
        speedKn: speedKn,
        name: row.nameController.text.trim(),
      ));
    }

    try {
      // Validates that every leg after the first has a usable speed by
      // actually running the same time-computation the map screen will use.
      shipTrackFromWaypoints(waypoints, _departureTime);
    } on VoyagePlanTimeException catch (e) {
      setState(() => _error = e.message);
      return;
    }

    Navigator.pop(context, VoyagePlanResult(waypoints: waypoints, departureTime: _departureTime));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Passage Plan'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: Colors.white)),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilledButton(onPressed: _save, child: const Text('Save')),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                const Text('Departure date/time (WP0):', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: _pickDepartureTime,
                  icon: const Icon(Icons.schedule, size: 18),
                  label: Text(_formatDepartureTime(_departureTime)),
                ),
                const Spacer(),
                Text('${_rows.length} waypoints', style: TextStyle(color: Colors.grey.shade600)),
              ],
            ),
          ),
          if (_error != null)
            Container(
              width: double.infinity,
              color: Colors.red.shade50,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Text(_error!, style: TextStyle(color: Colors.red.shade900)),
            ),
          _buildHeaderRow(),
          const Divider(height: 1),
          Expanded(
            child: ListView.separated(
              itemCount: _rows.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) => _buildDataRow(index),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderRow() {
    const style = TextStyle(fontWeight: FontWeight.bold, fontSize: 12);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Row(
        children: const [
          SizedBox(width: 40, child: Text('No.', style: style)),
          Expanded(flex: 2, child: Text('Lat (deg)', style: style)),
          Expanded(flex: 2, child: Text('Lon (deg)', style: style)),
          Expanded(flex: 2, child: Text('Speed [kn]', style: style)),
          Expanded(flex: 3, child: Text('Name', style: style)),
          SizedBox(width: 96, child: Text('', style: style)),
        ],
      ),
    );
  }

  Widget _buildDataRow(int index) {
    final row = _rows[index];
    final isFirst = index == 0;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          SizedBox(width: 40, child: Text('$index')),
          Expanded(flex: 2, child: _cellField(row.latController, 'e.g. 35.4093')),
          const SizedBox(width: 4),
          Expanded(flex: 2, child: _cellField(row.lonController, 'e.g. 139.6505')),
          const SizedBox(width: 4),
          Expanded(
            flex: 2,
            child: _cellField(
              row.speedController,
              isFirst ? '(n/a)' : 'e.g. 12.0',
              enabled: !isFirst,
            ),
          ),
          const SizedBox(width: 4),
          Expanded(flex: 3, child: _cellField(row.nameController, 'Waypoint name')),
          SizedBox(
            width: 96,
            child: Row(
              children: [
                IconButton(
                  tooltip: 'Insert waypoint after this row',
                  icon: const Icon(Icons.add, size: 18),
                  onPressed: () => _insertAfter(index),
                ),
                IconButton(
                  tooltip: 'Delete this row',
                  icon: const Icon(Icons.delete_outline, size: 18),
                  onPressed: _rows.length <= 1 ? null : () => _removeAt(index),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _cellField(TextEditingController controller, String hint, {bool enabled = true}) {
    return TextField(
      controller: controller,
      enabled: enabled,
      style: const TextStyle(fontSize: 13),
      decoration: InputDecoration(
        hintText: hint,
        isDense: true,
        border: const OutlineInputBorder(),
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      ),
    );
  }
}

/// One editable row's controllers. Kept alive for the row's lifetime (not
/// rebuilt from `ShipWaypoint` on every `setState`) so in-progress typing
/// isn't lost when other rows are inserted/deleted.
class _Row {
  _Row.fromWaypoint(ShipWaypoint wp)
      : latController = TextEditingController(text: wp.latitude.toStringAsFixed(4)),
        lonController = TextEditingController(text: wp.longitude.toStringAsFixed(4)),
        speedController = TextEditingController(text: wp.speedKn?.toStringAsFixed(1) ?? ''),
        nameController = TextEditingController(text: wp.name);

  _Row.empty()
      : latController = TextEditingController(),
        lonController = TextEditingController(),
        speedController = TextEditingController(),
        nameController = TextEditingController();

  final TextEditingController latController;
  final TextEditingController lonController;
  final TextEditingController speedController;
  final TextEditingController nameController;

  void dispose() {
    latController.dispose();
    lonController.dispose();
    speedController.dispose();
    nameController.dispose();
  }
}
