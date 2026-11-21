import 'dart:convert';

import 'condition.dart';
import 'reminder_sound.dart';

/// How multiple conditions are combined into one trigger.
enum Combinator { all, any }

/// How a fired reminder is presented.
enum Delivery { notification, alarm }

class Reminder {
  Reminder({
    required this.id,
    required this.title,
    this.note = '',
    required this.conditions,
    this.combinator = Combinator.all,
    this.repeat = true,
    this.delivery = Delivery.notification,
    this.sound = ReminderSound.defaultSound,
    this.enabled = true,
    this.lastState,
    this.lastTriggeredAt,
  });

  final String id;
  final String title;
  final String note;
  final List<Condition> conditions;
  final Combinator combinator;

  /// If false the reminder disables itself after firing once.
  final bool repeat;
  final Delivery delivery;
  final ReminderSound sound;
  final bool enabled;

  /// Whether the conditions held at the previous evaluation. Null until the
  /// first evaluation, so a reminder never fires for a state that was already
  /// true when it was created. A reminder fires on the false -> true edge.
  final bool? lastState;
  final DateTime? lastTriggeredAt;

  /// Identifies what the user configured, ignoring runtime state.
  String get definitionKey => jsonEncode({
    'title': title,
    'note': note,
    'conditions': conditions.map((c) => c.toJson()).toList(),
    'combinator': combinator.name,
    'repeat': repeat,
    'delivery': delivery.name,
    'sound': sound.toJson(),
  });

  Iterable<LocationCondition> get locationConditions =>
      conditions.whereType<LocationCondition>();

  /// True if a periodic check is needed (anything besides location, which is
  /// driven by geofence events).
  bool get needsPolling =>
      conditions.any((c) => c.type != ConditionType.location);

  bool evaluate(SensorSnapshot snapshot) {
    if (conditions.isEmpty) return false;
    return combinator == Combinator.all
        ? conditions.every((c) => c.isSatisfied(snapshot))
        : conditions.any((c) => c.isSatisfied(snapshot));
  }

  Reminder copyWith({
    String? title,
    String? note,
    List<Condition>? conditions,
    Combinator? combinator,
    bool? repeat,
    Delivery? delivery,
    ReminderSound? sound,
    bool? enabled,
    bool? lastState,
    DateTime? lastTriggeredAt,
  }) => Reminder(
    id: id,
    title: title ?? this.title,
    note: note ?? this.note,
    conditions: conditions ?? this.conditions,
    combinator: combinator ?? this.combinator,
    repeat: repeat ?? this.repeat,
    delivery: delivery ?? this.delivery,
    sound: sound ?? this.sound,
    enabled: enabled ?? this.enabled,
    lastState: lastState ?? this.lastState,
    lastTriggeredAt: lastTriggeredAt ?? this.lastTriggeredAt,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'note': note,
    'conditions': conditions.map((c) => c.toJson()).toList(),
    'combinator': combinator.name,
    'repeat': repeat,
    'delivery': delivery.name,
    'sound': sound.toJson(),
    'enabled': enabled,
    'lastState': lastState,
    'lastTriggeredAt': lastTriggeredAt?.toIso8601String(),
  };

  factory Reminder.fromJson(Map<String, dynamic> j) => Reminder(
    id: j['id'] as String,
    title: j['title'] as String,
    note: (j['note'] as String?) ?? '',
    conditions: (j['conditions'] as List)
        .map((c) => Condition.fromJson(Map<String, dynamic>.from(c as Map)))
        .toList(),
    combinator: Combinator.values.byName(j['combinator'] as String),
    repeat: (j['repeat'] as bool?) ?? true,
    delivery:
        Delivery.values.asNameMap()[j['delivery']] ?? Delivery.notification,
    sound: ReminderSound.fromJson(
      j['sound'] == null ? null : Map<String, dynamic>.from(j['sound'] as Map),
    ),
    enabled: (j['enabled'] as bool?) ?? true,
    lastState: j['lastState'] as bool?,
    lastTriggeredAt: j['lastTriggeredAt'] == null
        ? null
        : DateTime.parse(j['lastTriggeredAt'] as String),
  );
}
