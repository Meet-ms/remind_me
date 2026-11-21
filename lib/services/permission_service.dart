import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/condition.dart';
import 'notification_service.dart';

/// Requests only the permissions the given condition types need.
class PermissionService {
  static Future<void> requestFor(Set<ConditionType> types) async {
    await NotificationService.instance.requestPermission();

    final needsLocation =
        types.contains(ConditionType.location) ||
        types.contains(ConditionType.wifi); // Android hides SSID without it
    if (needsLocation) {
      final whenInUse = await Permission.locationWhenInUse.request();
      if (whenInUse.isGranted) {
        // Needed so triggers keep working while the app is closed.
        await Permission.locationAlways.request();
      }
    }
  }

  static Future<bool> hasLocation() async {
    final p = await Geolocator.checkPermission();
    return p == LocationPermission.always || p == LocationPermission.whileInUse;
  }

  static Future<bool> hasBackgroundLocation() async =>
      (await Geolocator.checkPermission()) == LocationPermission.always;

  static Future<void> openSettings() => openAppSettings();
}
