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

  Future<({double lat, double lon})?> currentPosition() async {
    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 20),
        ),
      );
      return (lat: pos.latitude, lon: pos.longitude);
    } catch (_) {
      return null;
    }
  }

  Future<String?> currentWifiName() async {
    try {
      return _cleanSsid(await _network.getWifiName());
    } catch (_) {
      return null;
    }
  }
}
