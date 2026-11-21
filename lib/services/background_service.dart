import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter_background_service/flutter_background_service.dart';

import '../models/reminder.dart';
import 'evaluation_service.dart';
import 'notification_service.dart';

const _checkInterval = Duration(seconds: 60);

@pragma('vm:entry-point')
Future<void> onServiceStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();
  await NotificationService.instance.init();

  var running = false;
  Future<void> tick() async {
    if (running) return;
    running = true;
    try {
      await runEvaluationPass();
      service.invoke('updated');
    } catch (e, st) {
      debugPrint('Evaluation failed: $e\n$st');
    } finally {
      running = false;
    }
  }

  service.on('stop').listen((_) => service.stopSelf());
  service.on('evaluate').listen((_) => tick());

  Timer.periodic(_checkInterval, (_) => tick());
  unawaited(tick());
}

/// Controls the Android foreground service that polls time, Wi-Fi and
/// battery triggers while the app is closed. Location triggers do not need
/// it: they are driven by native geofence events.
class MonitorService {
  static final _service = FlutterBackgroundService();

  static Future<void> configure() async {
    await NotificationService.instance.init();
    await _service.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: onServiceStart,
        autoStart: false,
        isForegroundMode: true,
        notificationChannelId: NotificationService.serviceChannelId,
        initialNotificationTitle: 'Remind Me',
        initialNotificationContent: 'Watching your reminder triggers',
        foregroundServiceNotificationId: 888,
        foregroundServiceTypes: [AndroidForegroundType.specialUse],
      ),
      iosConfiguration: IosConfiguration(autoStart: false),
    );
  }

  static Stream<Map<String, dynamic>?> get onUpdated => _service.on('updated');

  /// Starts the service when an enabled reminder needs polling, stops it
  /// otherwise, and asks a running service to re-check straight away.
  static Future<void> sync(List<Reminder> reminders) async {
    final shouldRun = reminders.any((r) => r.enabled && r.needsPolling);
    final running = await _service.isRunning();
    if (shouldRun && !running) {
      await _service.startService();
    } else if (shouldRun) {
      _service.invoke('evaluate');
    } else if (running) {
      _service.invoke('stop');
    }
  }
}
