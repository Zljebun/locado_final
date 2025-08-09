import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart'; // Still needed for AppBootstrapService
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
// REMOVED: theme_provider and app_theme imports - no more dark mode
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

// ✅ NOVO: Dodaj file intent handler
import 'helpers/file_intent_handler.dart';

// 🚀 NOVO: Import bootstrap service
import 'services/app_bootstrap_service.dart';

// ADDED: Static light theme definition (replaces dynamic theming)
class StaticAppTheme {
  static final ThemeData lightTheme = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: Colors.teal,
      brightness: Brightness.light,
    ),
    primarySwatch: Colors.teal,
    scaffoldBackgroundColor: Colors.grey.shade50,
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.teal,
      foregroundColor: Colors.white,
      elevation: 2,
    ),
    cardTheme: CardThemeData(
      elevation: 2,
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: Colors.teal,
      foregroundColor: Colors.white,
    ),
  );
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  print('🚀 MAIN: Starting instant initialization');
  
  // 🚀 ONLY ESSENTIAL: Load environment (must be synchronous)
  await dotenv.load(fileName: ".env");

  // 🚀 INSTANT: Initialize timezone in background
  _initializeTimezoneInBackground();

  // 🚀 INSTANT: Check lock screen mode quickly
  bool isLockScreenMode = await _detectLockScreenMode();

  if (isLockScreenMode) {
    print('🔒 LOCK SCREEN MODE: Launching TaskDetailApp');
    runApp(TaskDetailApp());
    return;
  }

  print('📱 NORMAL MODE: Launching main app with bootstrap service');

  // 🚀 INSTANT: Start bootstrap in background (don't await)
  _startBootstrapInBackground();

  // 🚀 INSTANT: Start the app immediately
  runApp(const MyApp());
}

/// Initialize timezone in background
void _initializeTimezoneInBackground() {
  Future.delayed(const Duration(milliseconds: 100), () async {
    try {
      tz.initializeTimeZones();
      final timeZoneName = await _getLocalTimeZone();
      tz.setLocalLocation(tz.getLocation(timeZoneName));
      print('✅ BACKGROUND: Timezone set to: $timeZoneName');
    } catch (e) {
      print('⚠️ BACKGROUND: Failed to set timezone: $e');
      tz.setLocalLocation(tz.getLocation('Europe/Belgrade'));
    }
  });
}

/// Start bootstrap in background
void _startBootstrapInBackground() {
  Future.delayed(const Duration(milliseconds: 200), () {
    AppBootstrapService.instance.initializeApp();
  });
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

/// 🆕 TASK DETAIL APP ZA LOCK SCREEN (simplified - light theme only)
class TaskDetailApp extends StatelessWidget {
  // ✅ NOVO: Navigator key za task detail app
  static final GlobalKey<NavigatorState> taskDetailNavigatorKey = GlobalKey<NavigatorState>();

  @override
  Widget build(BuildContext context) {
    // SIMPLIFIED: No theme provider, static light theme only
    return MaterialApp(
      navigatorKey: taskDetailNavigatorKey,
      debugShowCheckedModeBanner: false,
      title: 'Locado Task Detail',
      theme: StaticAppTheme.lightTheme, // Static theme
      home: TaskDetailBridge(),
    );
  }
}

/// 🔒 GLAVNA APLIKACIJA (normalni mode) - Optimized without theme provider
class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // ✅ NOVO: Global navigator key za file intent handler
  static final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  @override
  Widget build(BuildContext context) {
    // SIMPLIFIED: Only bootstrap service provider, no theme provider
    return ChangeNotifierProvider.value(
      value: AppBootstrapService.instance,
      builder: (context, child) {
        // SIMPLIFIED: No Consumer for theme, static theme only
        return MaterialApp(
          navigatorKey: navigatorKey,
          debugShowCheckedModeBanner: false,
          title: 'Locado',
          theme: StaticAppTheme.lightTheme, // Static light theme
          // REMOVED: darkTheme and themeMode - no dark mode support
          initialRoute: '/',
          routes: {
            '/': (context) => const BootstrapAwareMainScreen(),
            '/pick-location': (context) => const GooglePickLocationScreen(),
            '/onboarding': (context) => const BatteryOnboardingScreen(),
            '/settings': (context) => const SettingsScreen(),
          },
        );
      },
    );
  }
}

/// 🚀 OPTIMIZED: Bootstrap-aware main screen wrapper (no theme dependency)
class BootstrapAwareMainScreen extends StatefulWidget {
  const BootstrapAwareMainScreen({super.key});

  @override
  State<BootstrapAwareMainScreen> createState() => _BootstrapAwareMainScreenState();
}

class _BootstrapAwareMainScreenState extends State<BootstrapAwareMainScreen> {
  @override
  void initState() {
    super.initState();
    _initializeBackgroundServices();
  }

  /// Initialize services in background - COMPLETELY NON-BLOCKING
  Future<void> _initializeBackgroundServices() async {
    print('🚀 BACKGROUND: Starting non-blocking background services...');
    
    // 🚀 STRATEGY: Don't await anything - let everything run in parallel
    
    // Service 1: Notifications (don't await)
    _initializeNotificationsInBackground();
    
    // Service 2: Geofencing (don't await)  
    _initializeGeofencingInBackground();
    
    // Service 3: File intent (don't await)
    _initializeFileIntentInBackground();
    
    print('✅ BACKGROUND: All background services scheduled');
  }

  /// Initialize notifications in background
  void _initializeNotificationsInBackground() {
    Future.delayed(const Duration(seconds: 3), () async {
      try {
        await initializeNotifications();
        print('✅ BACKGROUND: Notifications initialized');
      } catch (e) {
        print('⚠️ BACKGROUND: Notification error: $e');
      }
    });
  }

  /// Initialize geofencing in background  
  void _initializeGeofencingInBackground() {
    Future.delayed(const Duration(seconds: 5), () async {
      try {
        await AppGeofencingController.instance.initializeApp();
        print('✅ BACKGROUND: App geofencing initialized');
      } catch (e) {
        print('⚠️ BACKGROUND: Geofencing error: $e');
      }
    });
  }

  /// Initialize file intent in background
  void _initializeFileIntentInBackground() {
    Future.delayed(const Duration(seconds: 1), () async {
      try {
        FileIntentHandler.initialize();
        print('✅ BACKGROUND: File intent handler initialized');
      } catch (e) {
        print('⚠️ BACKGROUND: File intent error: $e');
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // 🚀 INSTANT UI: Show MainNavigationScreen immediately!
    // Don't wait for ANY bootstrap phases to complete
    return const MainNavigationScreen();
    
    // REMOVED: All bootstrap checking and loading screens
    // Bootstrap continues in background without blocking UI
  }

  /// Build loading screen with bootstrap progress (static styling)
  /// KEPT FOR POTENTIAL FUTURE USE BUT NOT USED ANYMORE
  Widget _buildLoadingScreen(AppBootstrapService bootstrap) {
    return Scaffold(
      backgroundColor: Colors.white, // Static white background
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // App logo or icon
            const Icon(
              Icons.location_on,
              size: 64,
              color: Colors.teal, // Static teal color
            ),
            const SizedBox(height: 24),
            
            // App name
            const Text(
              'Locado',
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                color: Colors.teal, // Static teal color
              ),
            ),
            
            const SizedBox(height: 48),
            
            // Progress indicator
            SizedBox(
              width: 200,
              child: LinearProgressIndicator(
                value: bootstrap.progress,
                backgroundColor: Colors.grey, // Static colors
                valueColor: const AlwaysStoppedAnimation<Color>(Colors.teal),
              ),
            ),
            
            const SizedBox(height: 16),
            
            // Current step
            Text(
              bootstrap.currentStep,
              style: const TextStyle(
                fontSize: 14,
                color: Colors.grey, // Static color
              ),
              textAlign: TextAlign.center,
            ),
            
            // Error message if any
            if (bootstrap.errorMessage != null) ...[
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(16),
                margin: const EdgeInsets.symmetric(horizontal: 32),
                decoration: BoxDecoration(
                  color: Colors.red.shade50, // Static error styling
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: Column(
                  children: [
                    const Icon(Icons.error, color: Colors.red, size: 24),
                    const SizedBox(height: 8),
                    Text(
                      'Initialization Error',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.red.shade700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      bootstrap.errorMessage!,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.red.shade600,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ✅ OPTIMIZED: Navigation service (no theme dependency)
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
  
  /// Show snackbar message (static styling)
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