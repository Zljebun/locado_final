// lib/services/battery_optimization_service.dart

import 'package:flutter/services.dart';

class BatteryOptimizationService {
  // Koristi POSTOJEĆI channel iz MainActivity.kt
  static const MethodChannel _channel = MethodChannel('com.example.locado_final/geofence');

  /// Proverava da li je aplikacija battery optimized
  /// Returns:
  /// - true: Android UBIJA pozadinske procese (LOŠE - treba whitelist)
  /// - false: App JE na whitelisti (DOBRO - pozadinski procesi rade)
  /// - null: Greška ili nepoznat status
  static Future<bool?> isBatteryOptimized() async {
    try {
      // Poziva POSTOJEĆI method call iz MainActivity.kt
      final Map<dynamic, dynamic>? result = await _channel.invokeMethod('checkBatteryOptimization');

      if (result == null) return null;

      // MainActivity vraća: isWhitelisted = true/false
      // isWhitelisted = true  → app JE na whitelisti (DOBRO) → return false
      // isWhitelisted = false → app NIJE na whitelisti (LOŠE) → return true
      final bool isWhitelisted = result['isWhitelisted'] ?? false;

      return !isWhitelisted; // Obrnut rezultat za Flutter logiku

    } on PlatformException catch (e) {
      print('Battery optimization check error: ${e.message}');
      return null; // Greška - pretpostavimo da je OK
    } catch (e) {
      print('Unexpected battery optimization error: $e');
      return null;
    }
  }

  /// Otvara Android Battery Optimization Settings
  /// Koristi POSTOJEĆI method call iz MainActivity.kt
  static Future<bool> openBatteryOptimizationSettings() async {
    try {
      final String? result = await _channel.invokeMethod('requestBatteryOptimizationWhitelist');
      return result != null; // Uspešan poziv
    } on PlatformException catch (e) {
      print('Failed to open battery optimization settings: ${e.message}');
      return false;
    } catch (e) {
      print('Unexpected error opening settings: $e');
      return false;
    }
  }

  /// Kombinovana metoda - direktni request sa fallback
  static Future<bool> requestWhitelistWithFallback() async {
    return await openBatteryOptimizationSettings();
  }

  /// Utility metoda - user-friendly status poruka
  static Future<String> getBatteryOptimizationStatusMessage() async {
    final isOptimized = await isBatteryOptimized();

    switch (isOptimized) {
      case true:
        return 'Aplikacija je battery optimized - pozadinski procesi mogu biti ubijani';
      case false:
        return 'Aplikacija je na whitelisti - pozadinski procesi rade normalno';
      case null:
        return 'Status battery optimization-a nije dostupan';
    }
  }

  /// Debug metoda - detaljne informacije
  static Future<Map<String, dynamic>> getDetailedBatteryInfo() async {
    try {
      final Map<dynamic, dynamic>? result = await _channel.invokeMethod('checkBatteryOptimization');
      final isOptimized = await isBatteryOptimized();
      final statusMessage = await getBatteryOptimizationStatusMessage();

      return {
        'isOptimized': isOptimized,
        'rawResult': result,
        'statusMessage': statusMessage,
        'timestamp': DateTime.now().toIso8601String(),
      };
    } catch (e) {
      return {
        'error': e.toString(),
        'timestamp': DateTime.now().toIso8601String(),
      };
    }
  }
}