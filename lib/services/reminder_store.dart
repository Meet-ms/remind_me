import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/reminder.dart';

/// Persists reminders as JSON. Shared between the UI isolate and the
/// background service isolate, so every read first reloads from disk.
class ReminderStore {
  static const _key = 'reminders_v1';

  Future<List<Reminder>> load() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final raw = prefs.getString(_key);
    if (raw == null) return [];
    try {
      return (jsonDecode(raw) as List)
          .map((e) => Reminder.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> save(List<Reminder> reminders) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode(reminders.map((r) => r.toJson()).toList()),
    );
  }

  /// Read-modify-write helper to keep the window for lost updates small.
  Future<List<Reminder>> update(
    List<Reminder> Function(List<Reminder> current) change,
  ) async {
    final next = change(await load());
    await save(next);
    return next;
  }
}
