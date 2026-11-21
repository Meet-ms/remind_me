import 'dart:async';

import 'package:alarm/alarm.dart';
import 'package:alarm/utils/alarm_set.dart';
import 'package:material_ui/material_ui.dart';

import '../services/alarm_service.dart';
import '../services/notification_service.dart';

/// Full-screen page shown while an alarm-type reminder is ringing.
class RingPage extends StatefulWidget {
  const RingPage({super.key, required this.alarm});
  final AlarmSettings alarm;

  @override
  State<RingPage> createState() => _RingPageState();
}

class _RingPageState extends State<RingPage> {
  StreamSubscription<AlarmSet>? _sub;
  bool _busy = false;
  bool _closed = false;

  @override
  void initState() {
    super.initState();
    // The alarm notification's own Stop/Snooze buttons also end the ring.
    _sub = Alarm.ringing.listen((set) {
      if (!set.containsId(widget.alarm.id)) _close();
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  void _close() {
    if (_closed || !mounted) return;
    _closed = true;
    Navigator.of(context).pop();
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } finally {
      _close();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final n = widget.alarm.notificationSettings;
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: theme.colorScheme.primaryContainer,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                const Spacer(),
                Icon(
                  Icons.alarm,
                  size: 96,
                  color: theme.colorScheme.onPrimaryContainer,
                ),
                const SizedBox(height: 24),
                Text(
                  n.title,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineMedium?.copyWith(
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  n.body,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                ),
                const Spacer(),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.tonalIcon(
                    onPressed: _busy
                        ? null
                        : () => _run(() => AlarmService.snooze(widget.alarm)),
                    icon: const Icon(Icons.snooze),
                    label: Text('Snooze ${snoozeDuration.inMinutes} min'),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _busy
                        ? null
                        : () => _run(() => Alarm.stop(widget.alarm.id)),
                    icon: const Icon(Icons.check),
                    label: const Text('Done'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
