import '../models/condition.dart';
import '../models/reminder.dart';

class EvaluationResult {
  const EvaluationResult(this.reminders, this.fired);

  /// Updated reminders (state, enabled flag, trigger time).
  final List<Reminder> reminders;

  /// Reminders that fired in this pass.
  final List<Reminder> fired;
}

/// Pure evaluation logic: given reminders and a sensor snapshot, decide which
/// reminders fire. A reminder fires when its combined condition turns true
/// (false -> true edge) and re-arms once it turns false again.
EvaluationResult evaluateReminders(
  List<Reminder> reminders,
  SensorSnapshot snapshot,
) {
  final updated = <Reminder>[];
  final fired = <Reminder>[];
  for (final r in reminders) {
    if (!r.enabled) {
      updated.add(r);
      continue;
    }
    // Wait for data (e.g. the first geofence event) before judging, so the
    // baseline state recorded below is real.
    if (r.conditions.any((c) => !c.isKnown(snapshot))) {
      updated.add(r);
      continue;
    }
    final state = r.evaluate(snapshot);
    if (r.lastState == false && state) {
      fired.add(r);
      updated.add(
        r.copyWith(
          lastState: state,
          lastTriggeredAt: snapshot.now,
          enabled: r.repeat,
        ),
      );
    } else if (r.lastState != state) {
      updated.add(r.copyWith(lastState: state));
    } else {
      updated.add(r);
    }
  }
  return EvaluationResult(updated, fired);
}
