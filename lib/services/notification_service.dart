import 'dart:convert';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

import '../models/reminder.dart';
import '../models/reminder_sound.dart';
import '../utils/stable_hash.dart';

const snoozeDuration = Duration(minutes: 10);

const _snoozeActionId = 'snooze';
const _doneActionId = 'done';

/// Compact copy of what is needed to show a reminder again (snooze), kept in
/// the notification payload so it works even if the reminder was deleted.
class _Payload {
  _Payload(this.id, this.title, this.note, this.sound);

  final String id;
  final String title;
  final String note;
  final ReminderSound sound;

  factory _Payload.of(Reminder r) => _Payload(r.id, r.title, r.note, r.sound);

  String encode() => jsonEncode({
    'id': id,
    'title': title,
    'note': note,
    'sound': sound.toJson(),
  });

  static _Payload? decode(String? raw) {
    if (raw == null) return null;
    try {
      final j = jsonDecode(raw) as Map<String, dynamic>;
      return _Payload(
        j['id'] as String,
        j['title'] as String,
        j['note'] as String,
        ReminderSound.fromJson(Map<String, dynamic>.from(j['sound'] as Map)),
      );
    } catch (_) {
      return null;
    }
  }
}

Future<void> _handleResponse(NotificationResponse response) async {
  if (response.actionId != _snoozeActionId) return;
  final payload = _Payload.decode(response.payload);
  if (payload == null) return;
  await NotificationService.instance.init();
  await NotificationService.instance._scheduleSnooze(payload);
}

@pragma('vm:entry-point')
Future<void> notificationBackgroundHandler(NotificationResponse response) =>
    _handleResponse(response);

class NotificationService {
  NotificationService._();
  static final instance = NotificationService._();

  static const defaultChannelId = 'reminders';
  static const serviceChannelId = 'remind_me_service';
  static const _soundChannelPrefix = 'reminders_';

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;

  static int idFor(String reminderId) => stableHash(reminderId);

  Future<void> init() async {
    if (_ready) return;
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
      onDidReceiveNotificationResponse: _handleResponse,
      onDidReceiveBackgroundNotificationResponse: notificationBackgroundHandler,
    );
    final android = _android;
    await android?.createNotificationChannel(
      const AndroidNotificationChannel(
        defaultChannelId,
        'Reminders',
        description: 'Notifications when a reminder triggers',
        importance: Importance.high,
      ),
    );
    await android?.createNotificationChannel(
      const AndroidNotificationChannel(
        serviceChannelId,
        'Background monitoring',
        description: 'Keeps Remind Me watching your triggers',
        importance: Importance.low,
      ),
    );
    _ready = true;
  }

  AndroidFlutterLocalNotificationsPlugin? get _android => _plugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >();

  Future<void> requestPermission() async {
    await init();
    await _android?.requestNotificationsPermission();
    // Needed to schedule exact snoozes; falls back to inexact if refused.
    await _android?.requestExactAlarmsPermission();
  }

  /// Android 8+ fixes the sound per channel, so each distinct sound gets its
  /// own channel.
  NotificationDetails _details(ReminderSound sound) {
    final custom = !sound.isDefault;
    final channelId = custom
        ? '$_soundChannelPrefix${sound.channelSuffix}'
        : defaultChannelId;
    return NotificationDetails(
      android: AndroidNotificationDetails(
        channelId,
        custom ? 'Reminders (${sound.label})' : 'Reminders',
        importance: Importance.high,
        priority: Priority.high,
        category: AndroidNotificationCategory.reminder,
        sound: custom ? UriAndroidNotificationSound(sound.uri!) : null,
        actions: const [
          AndroidNotificationAction(
            _snoozeActionId,
            'Snooze 10 min',
            cancelNotification: true,
          ),
          AndroidNotificationAction(
            _doneActionId,
            'Done',
            cancelNotification: true,
          ),
        ],
      ),
    );
  }

  Future<void> show(Reminder reminder) async {
    await init();
    final payload = _Payload.of(reminder);
    await _plugin.show(
      id: idFor(reminder.id),
      title: reminder.title,
      body: reminder.note.isEmpty ? 'Reminder triggered' : reminder.note,
      notificationDetails: _details(reminder.sound),
      payload: payload.encode(),
    );
  }

  Future<void> _scheduleSnooze(_Payload p) async {
    // An absolute instant, so no local time zone database is needed.
    final when = tz.TZDateTime.now(tz.UTC).add(snoozeDuration);

    Future<void> schedule(AndroidScheduleMode mode) => _plugin.zonedSchedule(
      id: idFor(p.id),
      title: p.title,
      body: p.note.isEmpty ? 'Reminder (snoozed)' : p.note,
      scheduledDate: when,
      notificationDetails: _details(p.sound),
      androidScheduleMode: mode,
      payload: p.encode(),
    );

    try {
      await schedule(AndroidScheduleMode.exactAllowWhileIdle);
    } catch (_) {
      await schedule(AndroidScheduleMode.inexactAllowWhileIdle);
    }
  }

  /// Removes a pending or shown notification, e.g. when its reminder is
  /// deleted or disabled.
  Future<void> cancelFor(String reminderId) async {
    await init();
    await _plugin.cancel(id: idFor(reminderId));
  }

  /// Deletes per-sound channels no reminder uses any more.
  Future<void> pruneChannels(Iterable<Reminder> reminders) async {
    await init();
    final keep = {
      for (final r in reminders)
        if (r.delivery == Delivery.notification && !r.sound.isDefault)
          '$_soundChannelPrefix${r.sound.channelSuffix}',
    };
    final channels = await _android?.getNotificationChannels() ?? [];
    for (final c in channels) {
      if (c.id.startsWith(_soundChannelPrefix) && !keep.contains(c.id)) {
        await _android?.deleteNotificationChannel(channelId: c.id);
      }
    }
  }
}
