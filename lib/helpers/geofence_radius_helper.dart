import 'package:shared_preferences/shared_preferences.dart';

Future<double> getGeofenceRadiusFromSettings() async {
  final prefs = await SharedPreferences.getInstance();
  // ISPRAVLJEN KLJUČ - isti kao u settings_screen.dart
  return prefs.getInt('notification_distance')?.toDouble() ?? 100.0;
}