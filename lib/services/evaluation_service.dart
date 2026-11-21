import '../engine/reminder_engine.dart';
import '../models/reminder.dart';
import 'alarm_service.dart';
import 'geofence_service.dart';
import 'notification_service.dart';
import 'reminder_store.dart';
import 'sensor_service.dart';

Future<void> deliver(Reminder r) => r.delivery == Delivery.alarm
    ? AlarmService.ring(r)
    : NotificationService.instance.show(r);

/// Stops anything still showing or pending for [r] (deleted/disabled).
Future<void> dismissDelivery(Reminder r) async {
  await NotificationService.instance.cancelFor(r.id);
  await AlarmService.stop(r.id);
}

/// Reads the stored reminders, evaluates them against the current device
/// state and delivers those that triggered. Safe to call from the UI, the
/// background service or a geofence callback.
Future<List<Reminder>> runEvaluationPass() async {
  final store = ReminderStore();
  final sensors = SensorService();
  final reminders = await store.load();
  if (!reminders.any((r) => r.enabled)) return reminders;

  await GeofenceService.seedUnknown(reminders, sensors);
  final snapshot = await sensors.read(SensorService.neededTypes(reminders));
  final result = evaluateReminders(reminders, snapshot);

  // Re-load right before saving so edits, deletions and toggles made in the
  // UI while sensors were being read are not overwritten; only runtime state
  // is merged in, and only for reminders whose definition is unchanged.
  final before = {for (final r in reminders) r.id: r.definitionKey};
  final evaluated = {for (final r in result.reminders) r.id: r};
  final merged = await store.update(
    (current) => [
      for (final c in current)
        if (evaluated[c.id] case final e? when before[c.id] == c.definitionKey)
          c.copyWith(
            lastState: e.lastState,
            lastTriggeredAt: e.lastTriggeredAt,
            enabled: c.enabled && e.enabled,
          )
        else
          c,
    ],
  );

  for (final r in result.fired) {
    await deliver(r);
  }
  // One-time reminders just disabled themselves; drop their geofences.
  if (result.fired.any((r) => !r.repeat)) {
    await GeofenceService.sync(merged);
  }
  return merged;
}
