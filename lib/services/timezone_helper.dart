// lib/services/timezone_helper.dart
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'dart:developer' as developer;

class TimezoneHelper {
  static bool _isInitialized = false;

  /// Initialize timezone data
  static Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      tz.initializeTimeZones();

      // Set local timezone
      final timeZoneName = await _getLocalTimeZone();
      tz.setLocalLocation(tz.getLocation(timeZoneName));

      _isInitialized = true;
      developer.log('✅ Timezone initialized: $timeZoneName');
    } catch (e) {
      developer.log('❌ Error initializing timezone: $e');
      // Fallback to UTC if local timezone fails
      try {
        tz.setLocalLocation(tz.UTC);
        _isInitialized = true;
        developer.log('⚠️ Fallback to UTC timezone');
      } catch (fallbackError) {
        developer.log('❌ Failed to set fallback timezone: $fallbackError');
      }
    }
  }

  /// Get local timezone name
  static Future<String> _getLocalTimeZone() async {
    try {
      // Try to get system timezone
      final now = DateTime.now();
      final offset = now.timeZoneOffset;

      // Common timezone mappings based on offset
      final offsetHours = offset.inHours;

      switch (offsetHours) {
        case 1: return 'Europe/Belgrade'; // CET (Serbia/Bosnia/Croatia)
        case 0: return 'Europe/London';   // GMT
        case -5: return 'America/New_York'; // EST
        case -8: return 'America/Los_Angeles'; // PST
        case 8: return 'Asia/Shanghai';   // CST
        case 9: return 'Asia/Tokyo';      // JST
        default:
        // Default to Europe/Belgrade for Balkan region
          return 'Europe/Belgrade';
      }
    } catch (e) {
      developer.log('⚠️ Could not determine local timezone, using Europe/Belgrade');
      return 'Europe/Belgrade';
    }
  }

  /// Convert DateTime to TZDateTime
  static tz.TZDateTime convertToTZDateTime(DateTime dateTime) {
    if (!_isInitialized) {
      developer.log('⚠️ Timezone not initialized, using UTC');
      return tz.TZDateTime.from(dateTime, tz.UTC);
    }

    return tz.TZDateTime.from(dateTime, tz.local);
  }

  /// Get current TZDateTime
  static tz.TZDateTime now() {
    if (!_isInitialized) {
      developer.log('⚠️ Timezone not initialized, using UTC');
      return tz.TZDateTime.now(tz.UTC);
    }

    return tz.TZDateTime.now(tz.local);
  }

  /// Check if timezone is initialized
  static bool get isInitialized => _isInitialized;
}