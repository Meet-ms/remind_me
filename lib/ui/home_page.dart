import 'dart:async';

import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../models/condition.dart';
import '../models/reminder.dart';
import '../services/background_service.dart';
import '../services/evaluation_service.dart';
import '../services/geofence_service.dart';
import '../services/notification_service.dart';
import '../services/permission_service.dart';
import '../services/reminder_store.dart';
import 'condition_editors.dart';
import 'edit_reminder_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  final _store = ReminderStore();
  List<Reminder> _reminders = [];
  bool _loaded = false;
  bool _missingBackgroundLocation = false;
  StreamSubscription<Object?>? _serviceSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _serviceSub = MonitorService.onUpdated.listen((_) => _reload());
    _reload().then((_) => _syncRuntime(_reminders));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _serviceSub?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _reload();
  }

  Future<void> _reload() async {
    final list = await _store.load();
    final needsLocation = list.any(
      (r) =>
          r.enabled &&
          r.conditions.any((c) => c.type == ConditionType.location),
    );
    final missing =
        needsLocation && !await PermissionService.hasBackgroundLocation();
    if (!mounted) return;
    setState(() {
      _reminders = list;
      _loaded = true;
      _missingBackgroundLocation = missing;
    });
  }

  Future<void> _persist(List<Reminder> list) async {
    await _store.save(list);
    await _reload();
    await _syncRuntime(list);
  }

  /// Brings geofences, the polling service and notification channels in step
  /// with the saved reminders, then evaluates once so new reminders get a
  /// baseline.
  Future<void> _syncRuntime(List<Reminder> list) async {
    final geofencesOk = await GeofenceService.sync(list);
    await MonitorService.sync(list);
    await NotificationService.instance.pruneChannels(list);
    if (!mounted) return;
    final usesLocation = list.any(
      (r) => r.enabled && r.locationConditions.isNotEmpty,
    );
    if (!geofencesOk && usesLocation) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Could not register location triggers. Allow location “all the time”.',
          ),
        ),
      );
    }
    unawaited(runEvaluationPass().then((_) => _reload()));
  }

  Future<void> _addOrEdit([Reminder? existing]) async {
    final result = await Navigator.push<Reminder>(
      context,
      MaterialPageRoute(builder: (_) => EditReminderPage(initial: existing)),
    );
    if (result == null) return;
    await PermissionService.requestFor({
      for (final c in result.conditions) c.type,
    });
    final current = await _store.load();
    final idx = current.indexWhere((r) => r.id == result.id);
    if (idx >= 0) {
      await dismissDelivery(current[idx]);
      current[idx] = result;
    } else {
      current.insert(0, result);
    }
    await _persist(current);
  }

  Future<void> _toggle(Reminder r, bool enabled) async {
    if (enabled) {
      await PermissionService.requestFor({
        for (final c in r.conditions) c.type,
      });
    } else {
      await dismissDelivery(r);
    }
    final current = await _store.load();
    final idx = current.indexWhere((x) => x.id == r.id);
    if (idx < 0) return;
    // Re-enabling resets state so it doesn't fire for an already-true state.
    current[idx] = Reminder(
      id: r.id,
      title: r.title,
      note: r.note,
      conditions: r.conditions,
      combinator: r.combinator,
      repeat: r.repeat,
      delivery: r.delivery,
      sound: r.sound,
      enabled: enabled,
      lastTriggeredAt: r.lastTriggeredAt,
    );
    await _persist(current);
  }

  Future<void> _delete(Reminder r) async {
    await dismissDelivery(r);
    final current = await _store.load();
    current.removeWhere((x) => x.id == r.id);
    await _persist(current);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Remind Me')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _addOrEdit(),
        icon: const Icon(Icons.add),
        label: const Text('New reminder'),
      ),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                if (_missingBackgroundLocation)
                  MaterialBanner(
                    content: const Text(
                      'Location reminders need “Allow all the time” location access to work when the app is closed.',
                    ),
                    actions: [
                      TextButton(
                        onPressed: PermissionService.openSettings,
                        child: const Text('Open settings'),
                      ),
                    ],
                  ),
                Expanded(
                  child: _reminders.isEmpty
                      ? const _EmptyState()
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
                          itemCount: _reminders.length,
                          itemBuilder: (_, i) => _ReminderCard(
                            reminder: _reminders[i],
                            onTap: () => _addOrEdit(_reminders[i]),
                            onToggle: (v) => _toggle(_reminders[i], v),
                            onDelete: () => _delete(_reminders[i]),
                          ),
                        ),
                ),
              ],
            ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.notifications_active_outlined,
              size: 64,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text(
              'No reminders yet',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            const Text(
              'Create reminders triggered by time, location, Wi-Fi or battery — alone or combined.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _ReminderCard extends StatelessWidget {
  const _ReminderCard({
    required this.reminder,
    required this.onTap,
    required this.onToggle,
    required this.onDelete,
  });

  final Reminder reminder;
  final VoidCallback onTap;
  final ValueChanged<bool> onToggle;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final r = reminder;
    final theme = Theme.of(context);
    final joiner = r.combinator == Combinator.all ? 'AND' : 'OR';
    return Dismissible(
      key: ValueKey(r.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        margin: const EdgeInsets.symmetric(vertical: 4),
        decoration: BoxDecoration(
          color: theme.colorScheme.errorContainer,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(Icons.delete, color: theme.colorScheme.onErrorContainer),
      ),
      onDismissed: (_) => onDelete(),
      child: Card(
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        r.title,
                        style: theme.textTheme.titleMedium?.copyWith(
                          decoration: r.enabled
                              ? null
                              : TextDecoration.lineThrough,
                        ),
                      ),
                    ),
                    Switch(value: r.enabled, onChanged: onToggle),
                  ],
                ),
                if (r.note.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(r.note, style: theme.textTheme.bodyMedium),
                  ),
                for (var i = 0; i < r.conditions.length; i++)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      children: [
                        Icon(iconFor(r.conditions[i].type), size: 18),
                        const SizedBox(width: 8),
                        Expanded(child: Text(r.conditions[i].describe())),
                        if (i < r.conditions.length - 1)
                          Text(joiner, style: theme.textTheme.labelSmall),
                      ],
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Row(
                    children: [
                      Icon(
                        r.delivery == Delivery.alarm
                            ? Icons.alarm
                            : Icons.notifications_outlined,
                        size: 16,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          '${r.delivery == Delivery.alarm ? 'Alarm' : 'Notification'}'
                          '${r.sound.isDefault ? '' : ' • ${r.sound.label}'}',
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                ),
                if (r.lastTriggeredAt != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      'Last triggered ${DateFormat.MMMd().add_jm().format(r.lastTriggeredAt!)}',
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                if (!r.repeat)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text('One-time', style: theme.textTheme.bodySmall),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
