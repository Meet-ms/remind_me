import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Inside/outside state per geofence key, written by geofence events and
/// read by the evaluation pass (possibly in another isolate).
class GeofenceStateStore {
  static const _key = 'geofence_state_v1';

  Future<Map<String, bool>> load() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final raw = prefs.getString(_key);
    if (raw == null) return {};
    try {
      return (jsonDecode(raw) as Map).map((k, v) => MapEntry('$k', v == true));
    } catch (_) {
      return {};
    }
  }

  Future<void> _save(Map<String, bool> state) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(state));
  }

  Future<void> set(String key, bool inside) async {
    final state = await load();
    state[key] = inside;
    await _save(state);
  }

  /// Records [key] only if no event has set it in the meantime.
  Future<void> setIfMissing(String key, bool inside) async {
    final state = await load();
    if (state.containsKey(key)) return;
    state[key] = inside;
    await _save(state);
  }

  Future<void> retainOnly(Set<String> keys) async {
    final state = await load();
    final before = state.length;
    state.removeWhere((k, _) => !keys.contains(k));
    if (state.length != before) await _save(state);
  }
}
