import 'dart:io';

import 'package:alarm/alarm.dart';

import '../models/reminder.dart';
import '../models/reminder_sound.dart';
import '../utils/stable_hash.dart';
import 'notification_service.dart';

/// Rings reminders as full-screen, looping alarms (via the `alarm` package).
class AlarmService {
  static Future<void>? _init;

  /// Safe to call from any isolate; initializes once per isolate.
  static Future<void> ensureInit() => _init ??= Alarm.init();

  static int idFor(String reminderId) => stableHash(reminderId);

  static AlarmSettings settingsFor({
    required String reminderId,
    required String title,
    required String note,
    required ReminderSound sound,
    required DateTime at,
  }) {
    final path = sound.path;
    final usable = !sound.isDefault && path != null && File(path).existsSync();
    return AlarmSettings(
      id: idFor(reminderId),
      dateTime: at,
      assetAudioPath: usable ? path : null,
      loopAudio: true,
      vibrate: true,
      warningNotificationOnKill: false,
      androidFullScreenIntent: true,
      volumeSettings: VolumeSettings.fade(
        volume: 0.9,
        fadeDuration: const Duration(seconds: 3),
        volumeEnforced: false,
      ),
      notificationSettings: NotificationSettings(
        title: title,
        body: note.isEmpty ? 'Reminder triggered' : note,
        stopButton: 'Done',
        androidSnoozeButton: 'Snooze ${snoozeDuration.inMinutes} min',
      ),
      androidSnoozeDuration: snoozeDuration,
      payload: reminderId,
    );
  }

  static Future<void> ring(Reminder r) async {
    await ensureInit();
    await Alarm.set(
      alarmSettings: settingsFor(
        reminderId: r.id,
        title: r.title,
        note: r.note,
        sound: r.sound,
        at: DateTime.now().add(const Duration(seconds: 2)),
      ),
    );
  }

  /// Stops a ringing alarm and cancels any pending (snoozed) one.
  static Future<void> stop(String reminderId) async {
    await ensureInit();
    await Alarm.stop(idFor(reminderId));
  }

  /// Stops the alarm [settings] and re-arms it after the snooze duration.
  static Future<void> snooze(AlarmSettings settings) async {
    await ensureInit();
    await Alarm.stop(settings.id);
    await Alarm.set(
      alarmSettings: settings.copyWith(
        dateTime: DateTime.now().add(snoozeDuration),
      ),
    );
  }
}
