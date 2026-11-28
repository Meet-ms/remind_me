import 'package:battery_plus/battery_plus.dart';
import 'package:geolocator/geolocator.dart';
import 'package:network_info_plus/network_info_plus.dart';

import '../models/condition.dart';
import '../models/reminder.dart';
import 'geofence_state_store.dart';

/// Reads device state. Only sensors required by [needed] are queried.
/// Location is not polled: it comes from geofence events recorded in
/// [GeofenceStateStore].
class SensorService {
  final _battery = Battery();
  final _network = NetworkInfo();

  static Set<ConditionType> neededTypes(Iterable<Reminder> reminders) => {
    for (final r in reminders.where((r) => r.enabled))
      for (final c in r.conditions) c.type,
  };

  Future<SensorSnapshot> read(Set<ConditionType> needed) async {
    Map<String, bool> geofences = const {};
    String? ssid;
    int? level;
    bool? charging;

    if (needed.contains(ConditionType.location)) {
      geofences = await GeofenceStateStore().load();
    }
    if (needed.contains(ConditionType.wifi)) {
      try {
        ssid = _cleanSsid(await _network.getWifiName());
      } catch (_) {}
    }

    if (needed.contains(ConditionType.battery)) {
      try {
        level = await _battery.batteryLevel;
        final state = await _battery.batteryState;
        charging = state == BatteryState.charging || state == BatteryState.full;
      } catch (_) {}
    }

    return SensorSnapshot(
      now: DateTime.now(),
      geofenceInside: geofences,
      wifiSsid: ssid,
      batteryLevel: level,
      isCharging: charging,
    );
  }

  static String? _cleanSsid(String? raw) {
    if (raw == null) return null;
    var s = raw.trim();
    if (s.length >= 2 && s.startsWith('"') && s.endsWith('"')) {
      s = s.substring(1, s.length - 1);
    }
    if (s.isEmpty || s == '<unknown ssid>' || s == '0x') return null;
    return s;
  }

  /// Why a location fix is unavailable, or null if one should be obtainable.
  /// Pass [requestPermission] only from the foreground UI.
  static Future<String?> locationProblem({
    bool requestPermission = false,
  }) async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      return 'Turn on Location in your phone settings.';
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied && requestPermission) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return 'Location permission is needed. Allow it in app settings.';
    }
    return null;
  }

  /// Returns a fresh fix, trying high accuracy first (can be slow indoors)
  /// and then falling back to a coarser or the last known position.
  Future<({double lat, double lon})?> currentPosition() async {
    for (final accuracy in [LocationAccuracy.high, LocationAccuracy.low]) {
      try {
        final pos = await Geolocator.getCurrentPosition(
          locationSettings: LocationSettings(
            accuracy: accuracy,
            timeLimit: const Duration(seconds: 15),
          ),
        );
        return (lat: pos.latitude, lon: pos.longitude);
      } catch (_) {}
    }
    try {
      final last = await Geolocator.getLastKnownPosition();
      if (last != null) return (lat: last.latitude, lon: last.longitude);
    } catch (_) {}
    return null;
  }

  Future<String?> currentWifiName() async {
    try {
      return _cleanSsid(await _network.getWifiName());
    } catch (_) {
      return null;
    }
  }
}
