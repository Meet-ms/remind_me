import 'package:flutter/foundation.dart';
import 'package:native_geofence/native_geofence.dart';

import '../models/condition.dart';
import '../models/reminder.dart';
import 'evaluation_service.dart';
import 'geofence_state_store.dart';
import 'sensor_service.dart';

// Android geofences are unreliable below roughly this radius.
const minGeofenceRadius = 100.0;

/// Called by the OS when a registered geofence is entered or exited, even if
/// the app is not running. Records the new state and re-evaluates reminders.
@pragma('vm:entry-point')
Future<void> geofenceTriggered(GeofenceCallbackParams params) async {
  final inside = params.event != GeofenceEvent.exit;
  final store = GeofenceStateStore();
  for (final g in params.geofences) {
    await store.set(g.id, inside);
  }
  try {
    await runEvaluationPass();
  } catch (e, st) {
    debugPrint('Evaluation after geofence event failed: $e\n$st');
  }
}

/// Keeps native geofences in step with the enabled location conditions.
class GeofenceService {
  static bool _initialized = false;

  static Map<String, LocationCondition> desired(Iterable<Reminder> reminders) =>
      {
        for (final r in reminders.where((r) => r.enabled))
          for (final c in r.locationConditions) c.geofenceKey: c,
      };

  /// Registers missing geofences, removes stale ones. Returns false if
  /// registration failed (usually missing background location permission).
  static Future<bool> sync(List<Reminder> reminders) async {
    if (defaultTargetPlatform != TargetPlatform.android) return true;
    final wanted = desired(reminders);
    try {
      final manager = NativeGeofenceManager.instance;
      if (!_initialized) {
        await manager.initialize();
        _initialized = true;
      }
      final registered = (await manager.getRegisteredGeofenceIds()).toSet();
      final state = await GeofenceStateStore().load();

      for (final id in registered.difference(wanted.keys.toSet())) {
        await manager.removeGeofenceById(id);
      }
      for (final entry in wanted.entries) {
        final key = entry.key;
        final c = entry.value;
        // Without recorded state the geofence is re-created so the OS
        // reports the current inside/outside status again.
        if (registered.contains(key) && state.containsKey(key)) continue;
        await manager.createGeofence(
          Geofence(
            id: key,
            location: Location(latitude: c.latitude, longitude: c.longitude),
            radiusMeters: c.radiusMeters < minGeofenceRadius
                ? minGeofenceRadius
                : c.radiusMeters,
            triggers: {GeofenceEvent.enter, GeofenceEvent.exit},
            iosSettings: const IosGeofenceSettings(initialTrigger: true),
            androidSettings: const AndroidGeofenceSettings(
              initialTriggers: {GeofenceEvent.enter, GeofenceEvent.exit},
            ),
          ),
          geofenceTriggered,
        );
      }
      await GeofenceStateStore().retainOnly(wanted.keys.toSet());
      return true;
    } catch (e, st) {
      debugPrint('Geofence sync failed: $e\n$st');
      return false;
    }
  }

  /// Fallback for devices that skip the initial geofence trigger: judge the
  /// geofences that still have no state from a single location fix.
  static Future<void> seedUnknown(
    Iterable<Reminder> reminders,
    SensorService sensors,
  ) async {
    final wanted = desired(reminders);
    if (wanted.isEmpty) return;
    final store = GeofenceStateStore();
    final state = await store.load();
    final missing = wanted.entries.where((e) => !state.containsKey(e.key));
    if (missing.isEmpty) return;
    final pos = await sensors.currentPosition();
    if (pos == null) return;
    for (final e in missing) {
      final c = e.value;
      final d = LocationCondition.distanceMeters(
        c.latitude,
        c.longitude,
        pos.lat,
        pos.lon,
      );
      await store.setIfMissing(e.key, d <= c.radiusMeters);
    }
  }
}
