import 'dart:async';

import 'package:alarm/alarm.dart';
import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';

import 'services/alarm_service.dart';
import 'services/background_service.dart';
import 'ui/home_page.dart';
import 'ui/ring_page.dart';

final navigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (defaultTargetPlatform == TargetPlatform.android) {
    await MonitorService.configure();
    await AlarmService.ensureInit();
    _showRingPageWhileRinging();
  }
  runApp(const RemindMeApp());
}

/// Opens [RingPage] whenever an alarm starts ringing (including when the app
/// was launched by the alarm's full-screen notification).
void _showRingPageWhileRinging() {
  int? showing;

  void present(AlarmSettings alarm) {
    final nav = navigatorKey.currentState;
    if (nav == null) {
      // Launched by the alarm: the navigator doesn't exist until the first frame.
      WidgetsBinding.instance.addPostFrameCallback((_) => present(alarm));
      return;
    }
    nav.push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => RingPage(alarm: alarm),
      ),
    );
  }

  Alarm.ringing.listen((set) {
    if (showing != null && !set.containsId(showing!)) showing = null;
    if (showing != null || set.alarms.isEmpty) return;
    final alarm = set.alarms.first;
    showing = alarm.id;
    present(alarm);
  });
}

class RemindMeApp extends StatelessWidget {
  const RemindMeApp({super.key});

  static const _seedColor = Color(0xFF9B5CF6);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      title: 'Remind Me',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: _seedColor),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: _seedColor,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const HomePage(),
    );
  }
}
