// lib/services/onboarding_service.dart

import 'package:shared_preferences/shared_preferences.dart';

class OnboardingService {
  static const String _batteryOnboardingKey = 'battery_onboarding_completed';
  static const String _firstLaunchKey = 'first_app_launch';

  /// Check if this is the first time the app is launched
  static Future<bool> isFirstLaunch() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return !prefs.containsKey(_firstLaunchKey);
    } catch (e) {
      print('Error checking first launch: $e');
      return false; // Safe default
    }
  }

  /// Mark that the app has been launched
  static Future<void> markFirstLaunchCompleted() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_firstLaunchKey, true);
      print('✅ First launch marked as completed');
    } catch (e) {
      print('Error marking first launch: $e');
    }
  }

  /// Check if battery onboarding has been completed
  static Future<bool> isBatteryOnboardingCompleted() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final completed = prefs.getBool(_batteryOnboardingKey) ?? false;
      print('Battery onboarding completed: $completed');
      return completed;
    } catch (e) {
      print('Error checking battery onboarding: $e');
      return false; // Safe default
    }
  }

  /// Mark battery onboarding as completed
  static Future<void> markBatteryOnboardingCompleted() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_batteryOnboardingKey, true);
      print('✅ Battery onboarding marked as completed');
    } catch (e) {
      print('Error marking battery onboarding: $e');
    }
  }

  /// Check if battery onboarding should be shown
  /// Returns true if:
  /// - First launch OR
  /// - Battery onboarding never completed
  static Future<bool> shouldShowBatteryOnboarding() async {
    try {
      final isFirst = await isFirstLaunch();
      final isCompleted = await isBatteryOnboardingCompleted();

      final shouldShow = isFirst || !isCompleted;
      print('Should show battery onboarding: $shouldShow (first: $isFirst, completed: $isCompleted)');

      return shouldShow;
    } catch (e) {
      print('Error checking if should show onboarding: $e');
      return false; // Safe default
    }
  }

  /// Reset onboarding state (for testing)
  static Future<void> resetOnboarding() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_batteryOnboardingKey);
      await prefs.remove(_firstLaunchKey);
      print('🔄 Onboarding state reset');
    } catch (e) {
      print('Error resetting onboarding: $e');
    }
  }

  /// Get onboarding debug info
  static Future<Map<String, dynamic>> getDebugInfo() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      return {
        'isFirstLaunch': await isFirstLaunch(),
        'isBatteryOnboardingCompleted': await isBatteryOnboardingCompleted(),
        'shouldShowBatteryOnboarding': await shouldShowBatteryOnboarding(),
        'firstLaunchKeyExists': prefs.containsKey(_firstLaunchKey),
        'batteryOnboardingKeyExists': prefs.containsKey(_batteryOnboardingKey),
      };
    } catch (e) {
      return {'error': e.toString()};
    }
  }
}