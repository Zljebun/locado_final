import 'package:geolocator/geolocator.dart';
import 'dart:io';
import 'dart:async';

class LocationService {
  static Future<Position?> getCurrentLocation() async {
    print('🔄 LOCATION: Starting location request...');
    
    // Detect if this is a Huawei device and optimize accordingly
    final isHuawei = _isHuaweiDevice();
    if (isHuawei) {
      print('🔄 LOCATION: Huawei device detected - using optimized settings');
    }
    
    try {
      // Check if location services are enabled
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        print('❌ LOCATION: Location services are disabled');
        return null;
      }
      print('✅ LOCATION: Location services enabled');

      // Check permission
      LocationPermission permission = await Geolocator.checkPermission();
      print('🔄 LOCATION: Current permission: $permission');
      
      if (permission == LocationPermission.denied) {
        print('🔄 LOCATION: Requesting permission...');
        permission = await Geolocator.requestPermission();
        print('🔄 LOCATION: Permission after request: $permission');
        
        if (permission == LocationPermission.denied || 
            permission == LocationPermission.deniedForever) {
          print('❌ LOCATION: Permission denied');
          return null;
        }
      }

      print('🔄 LOCATION: Getting current position...');
      
      // Get current position with timeout and retry logic
      Position? position;
      int retryCount = 0;
      final maxRetries = isHuawei ? 2 : 3; // Fewer retries for Huawei
      LocationAccuracy currentAccuracy = isHuawei ? LocationAccuracy.medium : LocationAccuracy.high; // Start with medium for Huawei
      final timeoutDuration = isHuawei ? const Duration(seconds: 20) : const Duration(seconds: 15); // Longer timeout for Huawei
      
      while (position == null && retryCount < maxRetries) {
        try {
          // Use the older API format for compatibility
          position = await Geolocator.getCurrentPosition(
            desiredAccuracy: currentAccuracy,
            forceAndroidLocationManager: isHuawei, // Force Android Location Manager ONLY for Huawei
          ).timeout(timeoutDuration);
          
          if (position != null) {
            print('✅ LOCATION: Got position on attempt ${retryCount + 1}: ${position.latitude}, ${position.longitude}');
            print('✅ LOCATION: Accuracy: ${position.accuracy}m, Provider: ${position.isMocked ? "Mocked" : "Real"}');
            break;
          }
        } on TimeoutException {
          retryCount++;
          print('❌ LOCATION: Timeout on attempt $retryCount/$maxRetries');
          
          if (retryCount < maxRetries) {
            print('🔄 LOCATION: Trying with lower accuracy...');
            // Try with lower accuracy for next attempt
            if (isHuawei) {
              currentAccuracy = LocationAccuracy.low; // Go straight to low for Huawei
            } else {
              currentAccuracy = retryCount == 1 ? LocationAccuracy.medium : LocationAccuracy.low;
            }
            await Future.delayed(Duration(seconds: isHuawei ? 3 : 2)); // Longer delay for Huawei
          }
        } on LocationServiceDisabledException {
          print('❌ LOCATION: Location service disabled during request');
          return null;
        } on PermissionDeniedException {
          print('❌ LOCATION: Permission denied during request');
          return null;
        } catch (e) {
          retryCount++;
          print('❌ LOCATION: Error on attempt $retryCount/$maxRetries: $e');
          
          if (retryCount < maxRetries) {
            await Future.delayed(const Duration(seconds: 2));
          }
        }
      }

      // If still no position, try last known location
      if (position == null) {
        print('🔄 LOCATION: Trying last known position...');
        try {
          position = await Geolocator.getLastKnownPosition();
          if (position != null) {
            print('✅ LOCATION: Got last known position: ${position.latitude}, ${position.longitude}');
            print('⚠️ LOCATION: Position age: ${DateTime.now().difference(position.timestamp!).inMinutes} minutes');
          }
        } catch (e) {
          print('❌ LOCATION: Error getting last known position: $e');
        }
      }

      return position;

    } catch (e) {
      print('❌ LOCATION: Unexpected error in getCurrentLocation: $e');
      print('❌ LOCATION: Stack trace: ${StackTrace.current}');
      return null;
    }
  }

  // Helper method to check if device is likely Huawei
  static bool _isHuaweiDevice() {
    try {
      return Platform.isAndroid && 
             (Platform.operatingSystemVersion.toLowerCase().contains('huawei') ||
              Platform.operatingSystemVersion.toLowerCase().contains('emui') ||
              Platform.operatingSystemVersion.toLowerCase().contains('harmonyos'));
    } catch (e) {
      return false;
    }
  }

  // Additional method for checking location service status
  static Future<Map<String, dynamic>> getLocationServiceStatus() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      final permission = await Geolocator.checkPermission();
      
      return {
        'serviceEnabled': serviceEnabled,
        'permission': permission.toString(),
        'isHuawei': _isHuaweiDevice(),
        'platform': Platform.operatingSystem,
      };
    } catch (e) {
      return {
        'error': e.toString(),
        'serviceEnabled': false,
        'permission': 'unknown',
        'isHuawei': _isHuaweiDevice(),
        'platform': Platform.operatingSystem,
      };
    }
  }
}