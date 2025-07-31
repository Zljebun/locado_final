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
import 'package:google_maps_flutter/google_maps_flutter.dart';

// ✅ NOVO: Dodaj file intent handler
import 'helpers/file_intent_handler.dart';

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

  // ✅ NOVO: Initialize file intent handler for .locado files
  try {
    FileIntentHandler.initialize();
    print('✅ MAIN: File intent handler initialized');
  } catch (e) {
    print('⚠️ MAIN: File intent handler initialization failed: $e');
  }

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
  // ✅ NOVO: Navigator key za task detail app
  static final GlobalKey<NavigatorState> taskDetailNavigatorKey = GlobalKey<NavigatorState>();

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (context) => ThemeProvider(),
      builder: (context, child) {
        return Consumer<ThemeProvider>(
          builder: (context, themeProvider, child) {
            return MaterialApp(
              navigatorKey: taskDetailNavigatorKey, // ✅ NOVO: Dodano
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

  // ✅ NOVO: Global navigator key za file intent handler
  static final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (context) => ThemeProvider(),
      builder: (context, child) {
        return Consumer<ThemeProvider>(
          builder: (context, themeProvider, child) {
            return MaterialApp(
              navigatorKey: navigatorKey, // ✅ NOVO: Dodano za file intent handling
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

// ✅ NOVO: Navigation service za file intent handler
class NavigationService {
  static GlobalKey<NavigatorState> navigatorKey = MyApp.navigatorKey;
  
  static BuildContext? get currentContext => navigatorKey.currentContext;
  
  static NavigatorState? get navigator => navigatorKey.currentState;
  
  /// Navigate to main screen with optional selected location
  static Future<void> navigateToMainScreen({LatLng? selectedLocation}) async {
    final context = currentContext;
    if (context != null) {
      print('🔗 NAVIGATION: Navigating to main screen with location: $selectedLocation');
      
      await Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(
          builder: (context) => MainNavigationScreen(
            selectedLocation: selectedLocation,
          ),
        ),
        (route) => false, // Remove all previous routes
      );
    } else {
      print('❌ NAVIGATION: No context available for navigation');
    }
  }
  
  /// Navigate to home route
  static Future<void> navigateToHome() async {
    final context = currentContext;
    if (context != null) {
      await Navigator.pushNamedAndRemoveUntil(
        context,
        '/',
        (route) => false,
      );
    }
  }
  
  /// Show snackbar message
  static void showSnackBar({
    required String message,
    Color? backgroundColor,
    IconData? icon,
    Duration? duration,
    SnackBarAction? action,
  }) {
    final context = currentContext;
    if (context != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              if (icon != null) ...[
                Icon(icon, color: Colors.white, size: 20),
                const SizedBox(width: 8),
              ],
              Expanded(child: Text(message)),
            ],
          ),
          backgroundColor: backgroundColor ?? Colors.green,
          duration: duration ?? const Duration(seconds: 3),
          action: action,
        ),
      );
    }
  }
  
  /// Show error message
  static void showError(String message) {
    showSnackBar(
      message: message,
      backgroundColor: Colors.red,
      icon: Icons.error,
      duration: const Duration(seconds: 5),
    );
  }
  
  /// Show success message
  static void showSuccess(String message, {SnackBarAction? action}) {
    showSnackBar(
      message: message,
      backgroundColor: Colors.green,
      icon: Icons.check_circle,
      action: action,
    );
  }
  
  /// Show info message
  static void showInfo(String message) {
    showSnackBar(
      message: message,
      backgroundColor: Colors.blue,
      icon: Icons.info,
    );
  }
}