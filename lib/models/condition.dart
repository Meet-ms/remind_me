import 'dart:math' as math;

/// A snapshot of everything a condition might need. A null value means
/// "unknown" (sensor unavailable / permission missing) and never satisfies
/// a condition.
class SensorSnapshot {
  const SensorSnapshot({
    required this.now,
    this.latitude,
    this.longitude,
    this.geofenceInside = const {},
    this.wifiSsid,
    this.batteryLevel,
    this.isCharging,
  });

  final DateTime now;
  final double? latitude;
  final double? longitude;

  /// Inside/outside state per [LocationCondition.geofenceKey], maintained by
  /// native geofence events.
  final Map<String, bool> geofenceInside;
  final String? wifiSsid;
  final int? batteryLevel;
  final bool? isCharging;

  bool get hasLocation => latitude != null && longitude != null;
}

enum ConditionType { time, location, wifi, battery }

sealed class Condition {
  const Condition();

  ConditionType get type;

  /// False when the data needed to judge this condition is not available yet.
  /// Reminders with unknown conditions are not evaluated, so they cannot
  /// record a misleading baseline state.
  bool isKnown(SensorSnapshot s) => true;

  bool isSatisfied(SensorSnapshot s);

  String describe();

  Map<String, dynamic> toJson();

  static Condition fromJson(Map<String, dynamic> json) {
    final type = ConditionType.values.byName(json['type'] as String);
    switch (type) {
      case ConditionType.time:
        return TimeCondition.fromJson(json);
      case ConditionType.location:
        return LocationCondition.fromJson(json);
      case ConditionType.wifi:
        return WifiCondition.fromJson(json);
      case ConditionType.battery:
        return BatteryCondition.fromJson(json);
    }
  }
}

String formatMinutes(int m) {
  final h = (m ~/ 60).toString().padLeft(2, '0');
  final mm = (m % 60).toString().padLeft(2, '0');
  return '$h:$mm';
}

const dayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

/// Satisfied from [startMinutes] until [endMinutes] (or the end of the day if
/// null) on the chosen weekdays (1 = Monday ... 7 = Sunday; empty = every
/// day) or on one specific [date].
class TimeCondition extends Condition {
  const TimeCondition({
    required this.startMinutes,
    this.endMinutes,
    this.weekdays = const {},
    this.date,
  });

  final int startMinutes;
  final int? endMinutes;
  final Set<int> weekdays;
  final DateTime? date;

  @override
  ConditionType get type => ConditionType.time;

  @override
  bool isSatisfied(SensorSnapshot s) {
    final now = s.now;
    if (date != null) {
      if (now.year != date!.year ||
          now.month != date!.month ||
          now.day != date!.day) {
        return false;
      }
    } else if (weekdays.isNotEmpty && !weekdays.contains(now.weekday)) {
      return false;
    }
    final current = now.hour * 60 + now.minute;
    if (current < startMinutes) return false;
    final end = endMinutes;
    if (end == null) return true;
    return current <= end;
  }

  @override
  String describe() {
    final range = endMinutes == null
        ? 'From ${formatMinutes(startMinutes)}'
        : '${formatMinutes(startMinutes)}–${formatMinutes(endMinutes!)}';
    if (date != null) {
      final d = date!;
      return '$range on ${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    }
    if (weekdays.isEmpty || weekdays.length == 7) return '$range, every day';
    final days = (weekdays.toList()..sort()).map((d) => dayNames[d - 1]);
    return '$range on ${days.join(', ')}';
  }

  @override
  Map<String, dynamic> toJson() => {
    'type': type.name,
    'startMinutes': startMinutes,
    'endMinutes': endMinutes,
    'weekdays': weekdays.toList(),
    'date': date?.toIso8601String(),
  };

  factory TimeCondition.fromJson(Map<String, dynamic> j) => TimeCondition(
    startMinutes: j['startMinutes'] as int,
    endMinutes: j['endMinutes'] as int?,
    weekdays: ((j['weekdays'] as List?) ?? const []).cast<int>().toSet(),
    date: j['date'] == null ? null : DateTime.parse(j['date'] as String),
  );
}

enum LocationTrigger { arrive, leave }

class LocationCondition extends Condition {
  const LocationCondition({
    required this.latitude,
    required this.longitude,
    this.radiusMeters = 150,
    this.trigger = LocationTrigger.arrive,
    this.label = '',
  });

  final double latitude;
  final double longitude;
  final double radiusMeters;
  final LocationTrigger trigger;
  final String label;

  @override
  ConditionType get type => ConditionType.location;

  static double distanceMeters(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const r = 6371000.0;
    double rad(double d) => d * math.pi / 180;
    final dLat = rad(lat2 - lat1);
    final dLon = rad(lon2 - lon1);
    final a =
        math.pow(math.sin(dLat / 2), 2) +
        math.cos(rad(lat1)) *
            math.cos(rad(lat2)) *
            math.pow(math.sin(dLon / 2), 2);
    return 2 * r * math.asin(math.sqrt(a));
  }

  @override
  bool isKnown(SensorSnapshot s) =>
      s.geofenceInside.containsKey(geofenceKey) || s.hasLocation;

  /// Identifies the native geofence region; reminders watching the same
  /// place share one region.
  String get geofenceKey =>
      'g_${latitude.toStringAsFixed(5)}_${longitude.toStringAsFixed(5)}_${radiusMeters.round()}';

  @override
  bool isSatisfied(SensorSnapshot s) {
    final inside =
        s.geofenceInside[geofenceKey] ??
        (s.hasLocation
            ? distanceMeters(latitude, longitude, s.latitude!, s.longitude!) <=
                  radiusMeters
            : null);
    if (inside == null) return false;
    return trigger == LocationTrigger.arrive ? inside : !inside;
  }

  @override
  String describe() {
    final place = label.isEmpty
        ? '${latitude.toStringAsFixed(4)}, ${longitude.toStringAsFixed(4)}'
        : label;
    final verb = trigger == LocationTrigger.arrive ? 'Within' : 'Away from';
    return '$verb ${radiusMeters.round()} m of $place';
  }

  @override
  Map<String, dynamic> toJson() => {
    'type': type.name,
    'latitude': latitude,
    'longitude': longitude,
    'radiusMeters': radiusMeters,
    'trigger': trigger.name,
    'label': label,
  };

  factory LocationCondition.fromJson(Map<String, dynamic> j) =>
      LocationCondition(
        latitude: (j['latitude'] as num).toDouble(),
        longitude: (j['longitude'] as num).toDouble(),
        radiusMeters: (j['radiusMeters'] as num).toDouble(),
        trigger: LocationTrigger.values.byName(j['trigger'] as String),
        label: (j['label'] as String?) ?? '',
      );
}

enum WifiTrigger { connected, disconnected }

/// Matches on the connected Wi-Fi network name. An empty [ssid] means "any
/// network".
class WifiCondition extends Condition {
  const WifiCondition({this.ssid = '', this.trigger = WifiTrigger.connected});

  final String ssid;
  final WifiTrigger trigger;

  @override
  ConditionType get type => ConditionType.wifi;

  @override
  bool isSatisfied(SensorSnapshot s) {
    final current = s.wifiSsid;
    final matches = ssid.isEmpty
        ? current != null
        : current != null && current.toLowerCase() == ssid.toLowerCase();
    return trigger == WifiTrigger.connected ? matches : !matches;
  }

  @override
  String describe() {
    final name = ssid.isEmpty ? 'any Wi-Fi' : '"$ssid"';
    return trigger == WifiTrigger.connected
        ? 'Connected to $name'
        : 'Not connected to $name';
  }

  @override
  Map<String, dynamic> toJson() => {
    'type': type.name,
    'ssid': ssid,
    'trigger': trigger.name,
  };

  factory WifiCondition.fromJson(Map<String, dynamic> j) => WifiCondition(
    ssid: (j['ssid'] as String?) ?? '',
    trigger: WifiTrigger.values.byName(j['trigger'] as String),
  );
}

enum BatteryMode { below, above, charging, notCharging }

class BatteryCondition extends Condition {
  const BatteryCondition({this.mode = BatteryMode.below, this.level = 20});

  final BatteryMode mode;
  final int level;

  @override
  ConditionType get type => ConditionType.battery;

  @override
  bool isSatisfied(SensorSnapshot s) {
    switch (mode) {
      case BatteryMode.below:
        return s.batteryLevel != null && s.batteryLevel! <= level;
      case BatteryMode.above:
        return s.batteryLevel != null && s.batteryLevel! >= level;
      case BatteryMode.charging:
        return s.isCharging == true;
      case BatteryMode.notCharging:
        return s.isCharging == false;
    }
  }

  @override
  String describe() {
    switch (mode) {
      case BatteryMode.below:
        return 'Battery at or below $level%';
      case BatteryMode.above:
        return 'Battery at or above $level%';
      case BatteryMode.charging:
        return 'Charging';
      case BatteryMode.notCharging:
        return 'Not charging';
    }
  }

  @override
  Map<String, dynamic> toJson() => {
    'type': type.name,
    'mode': mode.name,
    'level': level,
  };

  factory BatteryCondition.fromJson(Map<String, dynamic> j) => BatteryCondition(
    mode: BatteryMode.values.byName(j['mode'] as String),
    level: j['level'] as int,
  );
}
