import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';

class AndroidBridgeTest {
  static const MethodChannel _channel = MethodChannel('com.locado/background_service');

  /// Test basic communication with Android layer
  static Future<bool> testConnection() async {
    try {
      final result = await _channel.invokeMethod('testConnection');
      debugPrint('✅ Android Bridge Test: $result');
      return true;
    } catch (e) {
      debugPrint('❌ Android Bridge Test failed: $e');
      return false;
    }
  }

  /// Test service startup
  static Future<bool> testServiceStart() async {
    try {
      final result = await _channel.invokeMethod('startForegroundService');
      debugPrint('✅ Service Start Test: $result');

      // Check if service is actually running
      await Future.delayed(const Duration(seconds: 2));
      final isRunning = await _channel.invokeMethod('isServiceRunning');
      debugPrint('✅ Service Running: $isRunning');

      return result == true && isRunning == true;
    } catch (e) {
      debugPrint('❌ Service Start Test failed: $e');
      return false;
    }
  }

  /// Test service shutdown
  static Future<bool> testServiceStop() async {
    try {
      final result = await _channel.invokeMethod('stopForegroundService');
      debugPrint('✅ Service Stop Test: $result');

      // Check if service is actually stopped
      await Future.delayed(const Duration(seconds: 2));
      final isRunning = await _channel.invokeMethod('isServiceRunning');
      debugPrint('✅ Service Running after stop: $isRunning');

      return result == true && isRunning == false;
    } catch (e) {
      debugPrint('❌ Service Stop Test failed: $e');
      return false;
    }
  }

  /// Run all tests
  static Future<void> runAllTests() async {
    debugPrint('🧪 Starting Android Bridge Tests...');

    final connectionTest = await testConnection();
    final serviceStartTest = await testServiceStart();
    final serviceStopTest = await testServiceStop();

    if (connectionTest && serviceStartTest && serviceStopTest) {
      debugPrint('🎉 All Android Bridge Tests PASSED!');
    } else {
      debugPrint('❌ Some Android Bridge Tests FAILED!');
      debugPrint('   Connection: $connectionTest');
      debugPrint('   Service Start: $serviceStartTest');
      debugPrint('   Service Stop: $serviceStopTest');
    }
  }
}