import 'package:flutter_test/flutter_test.dart';
import 'package:remind_me/engine/reminder_engine.dart';
import 'package:remind_me/models/condition.dart';
import 'package:remind_me/models/reminder.dart';
import 'package:remind_me/models/reminder_sound.dart';
import 'package:remind_me/utils/stable_hash.dart';

SensorSnapshot snap({
  DateTime? now,
  double? lat,
  double? lon,
  String? ssid,
  int? battery,
  bool? charging,
}) => SensorSnapshot(
  now: now ?? DateTime(2026, 1, 5, 10, 0), // a Monday
  latitude: lat,
  longitude: lon,
  wifiSsid: ssid,
  batteryLevel: battery,
  isCharging: charging,
);

void main() {
  const office = LocationCondition(latitude: 12.9716, longitude: 77.5946);
  const workHours = TimeCondition(startMinutes: 9 * 60, endMinutes: 17 * 60);

  test('combined time AND location needs both', () {
    final r = Reminder(
      id: '1',
      title: 'Submit report',
      conditions: const [workHours, office],
    );
    expect(r.evaluate(snap(lat: 12.9716, lon: 77.5946)), isTrue);
    expect(r.evaluate(snap()), isFalse); // location unknown
    expect(
      r.evaluate(
        snap(now: DateTime(2026, 1, 5, 20, 0), lat: 12.9716, lon: 77.5946),
      ),
      isFalse,
    ); // outside time window
    expect(r.evaluate(snap(lat: 13.5, lon: 77.5946)), isFalse); // far away
  });

  test('ANY combinator needs one match', () {
    final r = Reminder(
      id: '1',
      title: 'Charge phone',
      combinator: Combinator.any,
      conditions: const [
        BatteryCondition(level: 15),
        WifiCondition(ssid: 'Home'),
      ],
    );
    expect(r.evaluate(snap(battery: 10)), isTrue);
    expect(r.evaluate(snap(ssid: 'home', battery: 80)), isTrue);
    expect(r.evaluate(snap(ssid: 'Cafe', battery: 80)), isFalse);
  });

  test('weekday and specific date matching', () {
    const weekdays = TimeCondition(startMinutes: 600, weekdays: {1, 3});
    expect(weekdays.isSatisfied(snap()), isTrue); // Monday 10:00
    expect(
      weekdays.isSatisfied(snap(now: DateTime(2026, 1, 6, 10, 0))),
      isFalse,
    );
    final onDate = TimeCondition(startMinutes: 600, date: DateTime(2026, 1, 5));
    expect(onDate.isSatisfied(snap()), isTrue);
    expect(
      onDate.isSatisfied(snap(now: DateTime(2026, 1, 12, 10, 0))),
      isFalse,
    );
  });

  test('fires once on false -> true edge, re-arms, baselines first run', () {
    var r = Reminder(
      id: '1',
      title: 't',
      conditions: const [BatteryCondition(level: 20)],
    );
    // First evaluation only records state, even if already true.
    var res = evaluateReminders([r], snap(battery: 10));
    expect(res.fired, isEmpty);
    r = res.reminders.single;

    res = evaluateReminders([r], snap(battery: 50));
    expect(res.fired, isEmpty);
    r = res.reminders.single;

    res = evaluateReminders([r], snap(battery: 10));
    expect(res.fired, hasLength(1));
    r = res.reminders.single;
    expect(r.enabled, isTrue);

    res = evaluateReminders([r], snap(battery: 9)); // still true: no re-fire
    expect(res.fired, isEmpty);
  });

  test('one-time reminders disable themselves after firing', () {
    final r = Reminder(
      id: '1',
      title: 't',
      repeat: false,
      lastState: false,
      conditions: const [BatteryCondition(mode: BatteryMode.charging)],
    );
    final res = evaluateReminders([r], snap(charging: true));
    expect(res.fired, hasLength(1));
    expect(res.reminders.single.enabled, isFalse);
  });

  test('JSON round trip preserves all condition types', () {
    final r = Reminder(
      id: '1',
      title: 'All',
      combinator: Combinator.any,
      delivery: Delivery.alarm,
      sound: const ReminderSound(
        kind: SoundKind.file,
        uri: 'content://media/1',
        path: '/data/x.mp3',
        name: 'x.mp3',
      ),
      conditions: [
        TimeCondition(
          startMinutes: 60,
          endMinutes: 120,
          weekdays: const {2, 4},
          date: DateTime(2026, 3, 1),
        ),
        const LocationCondition(
          latitude: 1,
          longitude: 2,
          radiusMeters: 300,
          trigger: LocationTrigger.leave,
          label: 'Home',
        ),
        const WifiCondition(ssid: 'X', trigger: WifiTrigger.disconnected),
        const BatteryCondition(mode: BatteryMode.above, level: 90),
      ],
    );
    final back = Reminder.fromJson(r.toJson());
    expect(back.definitionKey, r.definitionKey);
    expect(back.delivery, Delivery.alarm);
    expect(back.sound.path, '/data/x.mp3');
    expect(
      back.conditions.map((c) => c.describe()),
      r.conditions.map((c) => c.describe()),
    );
  });

  test('reminders saved before alarm/sound existed still load', () {
    final json = Reminder(
      id: '1',
      title: 'Old',
      conditions: const [BatteryCondition()],
    ).toJson()..removeWhere((k, _) => k == 'delivery' || k == 'sound');
    final r = Reminder.fromJson(json);
    expect(r.delivery, Delivery.notification);
    expect(r.sound.isDefault, isTrue);
  });

  test('geofence state drives location conditions and defers unknowns', () {
    const home = LocationCondition(latitude: 19.07, longitude: 72.87);
    final key = home.geofenceKey;
    SensorSnapshot withGeofence(Map<String, bool> m) =>
        SensorSnapshot(now: DateTime(2026, 1, 5, 10), geofenceInside: m);

    expect(home.isKnown(withGeofence({})), isFalse);
    expect(home.isSatisfied(withGeofence({key: true})), isTrue);
    expect(home.isSatisfied(withGeofence({key: false})), isFalse);
    const leave = LocationCondition(
      latitude: 19.07,
      longitude: 72.87,
      trigger: LocationTrigger.leave,
    );
    expect(leave.isSatisfied(withGeofence({key: false})), isTrue);

    // An unknown location must not record a baseline, so entering the
    // geofence later still counts as a false -> true edge.
    var r = Reminder(
      id: '1',
      title: 't',
      conditions: const [home, TimeCondition(startMinutes: 0)],
    );
    var res = evaluateReminders([r], withGeofence({}));
    expect(res.reminders.single.lastState, isNull);
    res = evaluateReminders(res.reminders, withGeofence({key: false}));
    expect(res.reminders.single.lastState, isFalse);
    res = evaluateReminders(res.reminders, withGeofence({key: true}));
    expect(res.fired, hasLength(1));
  });

  test('stableHash is deterministic and positive', () {
    expect(stableHash('abc'), stableHash('abc'));
    expect(stableHash('abc'), isNot(stableHash('abd')));
    expect(stableHash('x'), inInclusiveRange(1, 0x7fffffff));
  });
}
