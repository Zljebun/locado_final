import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:locado_final/screens/notification_service.dart';
import 'package:locado_final/screens/main_navigation_screen.dart';
import 'package:locado_final/screens/settings_screen.dart';
import 'package:locado_final/screens/home_map_screen.dart';
import 'package:locado_final/screens/pick_location_screen.dart';
import 'package:locado_final/screens/task_detail_bridge.dart';
import 'services/geofencing_integration_helper.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:locado_final/screens/notification_service.dart';
import 'screens/battery_onboarding_screen.dart';
import 'services/onboarding_service.dart';
import 'theme/theme_provider.dart';
import 'theme/app_theme.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: ".env");

  tz.initializeTimeZones();

  // Try to set local timezone, fallback to Europe/Belgrade
  try {
    final timeZoneName = await _getLocalTimeZone();
    tz.setLocalLocation(tz.getLocation(timeZoneName));
    print('✅ Timezone set to: $timeZoneName');
  } catch (e) {
    print('⚠️ Failed to set timezone, using Europe/Belgrade: $e');
    tz.setLocalLocation(tz.getLocation('Europe/Belgrade'));
  }

  // 🆕 DETEKTUJ LOCK SCREEN MODE
  bool isLockScreenMode = await _detectLockScreenMode();

  if (isLockScreenMode) {
    print('🔒 LOCK SCREEN MODE: Launching TaskDetailApp');
    runApp(TaskDetailApp());
    return;
  }

  print('📱 NORMAL MODE: Launching main app');

  // Inicijalizuj notifikacije
  await initializeNotifications();

  // Initialize app-level geofencing
  await AppGeofencingController.instance.initializeApp();

  runApp(const MyApp());
}

/// 🆕 DETEKTUJ DA LI JE POKRENUT IZ TASK DETAIL FLUTTER ACTIVITY
Future<bool> _detectLockScreenMode() async {
  try {
    const channel = MethodChannel('com.example.locado_final/task_detail_channel');
    final result = await channel.invokeMethod('getTaskData');

    if (result != null && result is Map) {
      final isLockScreen = result['isLockScreen'] as bool? ?? false;
      print('🔍 Lock screen detection result: $isLockScreen');
      return isLockScreen;
    }

    return false;
  } catch (e) {
    print('🔍 Lock screen detection failed (normal mode): $e');
    return false;
  }
}

Future<String> _getLocalTimeZone() async {
  try {
    final now = DateTime.now();
    final offset = now.timeZoneOffset;
    final offsetHours = offset.inHours;

    switch (offsetHours) {
      case 1: return 'Europe/Belgrade'; // CET (Serbia/Bosnia/Croatia)
      case 0: return 'Europe/London';   // GMT
      case -5: return 'America/New_York'; // EST
      case -8: return 'America/Los_Angeles'; // PST
      case 8: return 'Asia/Shanghai';   // CST
      case 9: return 'Asia/Tokyo';      // JST
      default: return 'Europe/Belgrade'; // Default za Balkan
    }
  } catch (e) {
    return 'Europe/Belgrade';
  }
}

/// 🆕 TASK DETAIL APP ZA LOCK SCREEN (with theme support)
class TaskDetailApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (context) => ThemeProvider(),
      builder: (context, child) {
        return Consumer<ThemeProvider>(
          builder: (context, themeProvider, child) {
            return MaterialApp(
              debugShowCheckedModeBanner: false,
              title: 'Locado Task Detail',
              theme: AppTheme.lightTheme,
              darkTheme: AppTheme.darkTheme,
              themeMode: themeProvider.isInitialized ? themeProvider.themeMode : ThemeMode.light,
              home: TaskDetailBridge(),
            );
          },
        );
      },
    );
  }
}

/// 🔒 GLAVNA APLIKACIJA (normalni mode)
class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (context) => ThemeProvider(),
      builder: (context, child) {
        return Consumer<ThemeProvider>(
          builder: (context, themeProvider, child) {
            return MaterialApp(
              debugShowCheckedModeBanner: false,
              title: 'Locado',
              theme: AppTheme.lightTheme,
              darkTheme: AppTheme.darkTheme,
              themeMode: themeProvider.isInitialized ? themeProvider.themeMode : ThemeMode.light,
              initialRoute: '/',
              routes: {
                //'/': (context) => const HomeMapScreen(),
                '/': (context) => const MainNavigationScreen(),
                '/pick-location': (context) => const GooglePickLocationScreen(),
                '/onboarding': (context) => const BatteryOnboardingScreen(),
                '/settings': (context) => const SettingsScreen(),
              },
            );
          },
        );
      },
    );
  }
}