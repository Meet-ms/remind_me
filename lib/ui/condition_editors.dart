import 'package:material_ui/material_ui.dart';

import '../models/condition.dart';
import '../services/sensor_service.dart';
import 'map_picker_page.dart';

IconData iconFor(ConditionType t) => switch (t) {
  ConditionType.time => Icons.schedule,
  ConditionType.location => Icons.place,
  ConditionType.wifi => Icons.wifi,
  ConditionType.battery => Icons.battery_5_bar,
};

String labelFor(ConditionType t) => switch (t) {
  ConditionType.time => 'Time',
  ConditionType.location => 'Location',
  ConditionType.wifi => 'Wi-Fi',
  ConditionType.battery => 'Battery',
};

/// Opens the editor for [type], pre-filled from [initial] when editing.
Future<Condition?> showConditionEditor(
  BuildContext context,
  ConditionType type, {
  Condition? initial,
}) {
  if (type == ConditionType.location) {
    return Navigator.push<Condition>(
      context,
      MaterialPageRoute(
        builder: (_) => MapPickerPage(
          initial: initial is LocationCondition ? initial : null,
        ),
      ),
    );
  }
  return showDialog<Condition>(
    context: context,
    builder: (_) => switch (type) {
      ConditionType.time => _TimeEditor(
        initial: initial is TimeCondition ? initial : null,
      ),
      ConditionType.location => throw StateError('handled above'),
      ConditionType.wifi => _WifiEditor(
        initial: initial is WifiCondition ? initial : null,
      ),
      ConditionType.battery => _BatteryEditor(
        initial: initial is BatteryCondition ? initial : null,
      ),
    },
  );
}

class _EditorShell extends StatelessWidget {
  const _EditorShell({
    required this.type,
    required this.child,
    required this.onSave,
  });

  final ConditionType type;
  final Widget child;
  final VoidCallback? onSave;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          Icon(iconFor(type)),
          const SizedBox(width: 8),
          Text(labelFor(type)),
        ],
      ),
      content: SingleChildScrollView(child: child),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: onSave, child: const Text('Done')),
      ],
    );
  }
}

// ---------------------------------------------------------------- Time

class _TimeEditor extends StatefulWidget {
  const _TimeEditor({this.initial});
  final TimeCondition? initial;

  @override
  State<_TimeEditor> createState() => _TimeEditorState();
}

class _TimeEditorState extends State<_TimeEditor> {
  late int _start;
  int? _end;
  late Set<int> _days;
  DateTime? _date;

  @override
  void initState() {
    super.initState();
    final i = widget.initial;
    final now = TimeOfDay.now();
    _start = i?.startMinutes ?? now.hour * 60 + now.minute;
    _end = i?.endMinutes;
    _days = {...?i?.weekdays};
    _date = i?.date;
  }

  Future<int?> _pickTime(int initial) async {
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: initial ~/ 60, minute: initial % 60),
    );
    return t == null ? null : t.hour * 60 + t.minute;
  }

  @override
  Widget build(BuildContext context) {
    return _EditorShell(
      type: ConditionType.time,
      onSave: (_end != null && _end! < _start)
          ? null
          : () => Navigator.pop(
              context,
              TimeCondition(
                startMinutes: _start,
                endMinutes: _end,
                weekdays: _date == null ? _days : {},
                date: _date,
              ),
            ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('From'),
            trailing: Text(
              formatMinutes(_start),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            onTap: () async {
              final v = await _pickTime(_start);
              if (v != null) setState(() => _start = v);
            },
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Until a set time'),
            subtitle: Text(
              _end == null
                  ? 'Open-ended: stays true for the rest of the day'
                  : 'Ends at ${formatMinutes(_end!)}',
            ),
            value: _end != null,
            onChanged: (on) async {
              if (!on) {
                setState(() => _end = null);
                return;
              }
              final v = await _pickTime((_start + 60) % 1440);
              if (v != null) setState(() => _end = v);
            },
          ),
          if (_end != null && _end! < _start)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                'End must be after the start time.',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          const Divider(),
          const Text('Repeat on'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 4,
            children: [
              for (var d = 1; d <= 7; d++)
                FilterChip(
                  label: Text(dayNames[d - 1]),
                  selected: _date == null && _days.contains(d),
                  onSelected: (on) => setState(() {
                    _date = null;
                    on ? _days.add(d) : _days.remove(d);
                  }),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              TextButton.icon(
                icon: const Icon(Icons.event),
                label: Text(
                  _date == null
                      ? 'Specific date…'
                      : '${_date!.year}-${_date!.month.toString().padLeft(2, '0')}-${_date!.day.toString().padLeft(2, '0')}',
                ),
                onPressed: () async {
                  final now = DateTime.now();
                  final d = await showDatePicker(
                    context: context,
                    initialDate: _date ?? now,
                    firstDate: DateTime(now.year, now.month, now.day),
                    lastDate: now.add(const Duration(days: 3650)),
                  );
                  if (d != null) setState(() => _date = d);
                },
              ),
              if (_date != null)
                IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () => setState(() => _date = null),
                ),
            ],
          ),
          if (_date == null && _days.isEmpty)
            Text(
              'No days selected = every day',
              style: Theme.of(context).textTheme.bodySmall,
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- Wifi

class _WifiEditor extends StatefulWidget {
  const _WifiEditor({this.initial});
  final WifiCondition? initial;

  @override
  State<_WifiEditor> createState() => _WifiEditorState();
}

class _WifiEditorState extends State<_WifiEditor> {
  late final TextEditingController _ssid;
  late WifiTrigger _trigger;

  @override
  void initState() {
    super.initState();
    _ssid = TextEditingController(text: widget.initial?.ssid ?? '');
    _trigger = widget.initial?.trigger ?? WifiTrigger.connected;
  }

  @override
  void dispose() {
    _ssid.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _EditorShell(
      type: ConditionType.wifi,
      onSave: () => Navigator.pop(
        context,
        WifiCondition(ssid: _ssid.text.trim(), trigger: _trigger),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SegmentedButton<WifiTrigger>(
            segments: const [
              ButtonSegment(
                value: WifiTrigger.connected,
                label: Text('Connects'),
              ),
              ButtonSegment(
                value: WifiTrigger.disconnected,
                label: Text('Disconnects'),
              ),
            ],
            selected: {_trigger},
            onSelectionChanged: (s) => setState(() => _trigger = s.first),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _ssid,
            decoration: const InputDecoration(
              labelText: 'Network name (SSID)',
              helperText: 'Leave empty for any Wi-Fi network',
            ),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              icon: const Icon(Icons.wifi_find),
              label: const Text('Use current network'),
              onPressed: () async {
                final messenger = ScaffoldMessenger.of(context);
                final name = await SensorService().currentWifiName();
                if (!mounted) return;
                if (name == null) {
                  messenger.showSnackBar(
                    const SnackBar(
                      content: Text(
                        'No Wi-Fi network detected (needs location permission).',
                      ),
                    ),
                  );
                } else {
                  setState(() => _ssid.text = name);
                }
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------- Battery

class _BatteryEditor extends StatefulWidget {
  const _BatteryEditor({this.initial});
  final BatteryCondition? initial;

  @override
  State<_BatteryEditor> createState() => _BatteryEditorState();
}

class _BatteryEditorState extends State<_BatteryEditor> {
  late BatteryMode _mode;
  late double _level;

  @override
  void initState() {
    super.initState();
    _mode = widget.initial?.mode ?? BatteryMode.below;
    _level = (widget.initial?.level ?? 20).toDouble();
  }

  bool get _usesLevel =>
      _mode == BatteryMode.below || _mode == BatteryMode.above;

  @override
  Widget build(BuildContext context) {
    return _EditorShell(
      type: ConditionType.battery,
      onSave: () => Navigator.pop(
        context,
        BatteryCondition(mode: _mode, level: _level.round()),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DropdownButtonFormField<BatteryMode>(
            initialValue: _mode,
            decoration: const InputDecoration(labelText: 'When'),
            items: const [
              DropdownMenuItem(
                value: BatteryMode.below,
                child: Text('Battery is low'),
              ),
              DropdownMenuItem(
                value: BatteryMode.above,
                child: Text('Battery is high'),
              ),
              DropdownMenuItem(
                value: BatteryMode.charging,
                child: Text('Charging'),
              ),
              DropdownMenuItem(
                value: BatteryMode.notCharging,
                child: Text('Not charging'),
              ),
            ],
            onChanged: (v) => setState(() => _mode = v ?? _mode),
          ),
          if (_usesLevel) ...[
            const SizedBox(height: 12),
            Text(
              _mode == BatteryMode.below
                  ? 'At or below ${_level.round()}%'
                  : 'At or above ${_level.round()}%',
            ),
            Slider(
              min: 1,
              max: 100,
              divisions: 99,
              value: _level,
              onChanged: (v) => setState(() => _level = v),
            ),
          ],
        ],
      ),
    );
  }
}
