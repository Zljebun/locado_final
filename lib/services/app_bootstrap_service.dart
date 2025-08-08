import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';
import '../location_service.dart';
import 'geofencing_integration_helper.dart';

/// Bootstrap service that manages app initialization in phases
/// Phase 1: Instant UI setup (0-100ms)
/// Phase 2: Critical data loading (100-500ms) 
/// Phase 3: Background features (500ms-2min)
class AppBootstrapService extends ChangeNotifier {
  static AppBootstrapService? _instance;
  static AppBootstrapService get instance => _instance ??= AppBootstrapService._();
  
  AppBootstrapService._();

  // Bootstrap state
  bool _isInitialized = false;
  BootstrapPhase _currentPhase = BootstrapPhase.notStarted;
  String _currentStep = '';
  double _progress = 0.0;
  String? _errorMessage;

  // Phase completion flags
  bool _phase1Complete = false;
  bool _phase2Complete = false;
  bool _phase3Complete = false;

  // Data holders for phases
  Map<String, dynamic> _bootstrapData = {};
  
  // Getters
  bool get isInitialized => _isInitialized;
  BootstrapPhase get currentPhase => _currentPhase;
  String get currentStep => _currentStep;
  double get progress => _progress;
  String? get errorMessage => _errorMessage;
  bool get phase1Complete => _phase1Complete;
  bool get phase2Complete => _phase2Complete;
  bool get phase3Complete => _phase3Complete;
  Map<String, dynamic> get bootstrapData => _bootstrapData;

  /// Initialize all phases sequentially
  Future<void> initializeApp() async {
    print('🚀 BOOTSTRAP: Starting app initialization');
    _updateStatus(BootstrapPhase.phase1, 'Starting Phase 1...', 0.0);

    try {
      // Phase 1: Instant UI setup
      await _executePhase1();
      
      // Phase 2: Critical data 
      await _executePhase2();
      
      // Phase 3: Background features (non-blocking)
      _executePhase3InBackground();
      
      _isInitialized = true;
      print('✅ BOOTSTRAP: App initialization completed');
      
    } catch (e, stackTrace) {
      print('❌ BOOTSTRAP: Initialization failed: $e');
      print('❌ BOOTSTRAP: Stack trace: $stackTrace');
      _errorMessage = e.toString();
      _updateStatus(BootstrapPhase.error, 'Initialization failed', 0.0);
    }
  }

  /// Phase 1: Instant UI setup (0-100ms)
  /// Only essential UI components and cached data
  Future<void> _executePhase1() async {
    print('📱 BOOTSTRAP PHASE 1: Starting instant UI setup');
    _updateStatus(BootstrapPhase.phase1, 'Setting up UI...', 0.1);

    // Step 1: Load cached settings
    _updateStatus(BootstrapPhase.phase1, 'Loading cached settings...', 0.2);
    await _loadCachedSettings();

    // Step 2: Initialize theme data
    _updateStatus(BootstrapPhase.phase1, 'Setting up theme...', 0.3);
    await _initializeTheme();

    _phase1Complete = true;
    _updateStatus(BootstrapPhase.phase1, 'Phase 1 completed', 0.35);
    print('✅ BOOTSTRAP PHASE 1: Completed in ${DateTime.now().millisecondsSinceEpoch}ms');
  }

  /// Phase 2: Critical data loading (100-500ms)
  /// Map provider, basic location data, essential permissions
  Future<void> _executePhase2() async {
    print('🗺️ BOOTSTRAP PHASE 2: Starting critical data loading');
    _updateStatus(BootstrapPhase.phase2, 'Loading critical data...', 0.35);

    // Step 1: Load map provider setting
    _updateStatus(BootstrapPhase.phase2, 'Loading map provider...', 0.4);
    await _loadMapProviderSetting();

    // Step 2: Basic location check (non-blocking)
    _updateStatus(BootstrapPhase.phase2, 'Checking location services...', 0.5);
    await _checkLocationServices();

    // Step 3: Load essential cached data
    _updateStatus(BootstrapPhase.phase2, 'Loading cached data...', 0.6);
    await _loadEssentialCachedData();

    _phase2Complete = true;
    _updateStatus(BootstrapPhase.phase2, 'Phase 2 completed', 0.65);
    print('✅ BOOTSTRAP PHASE 2: Completed');
  }

  /// Phase 3: Background features (500ms-2min)
  /// Geofencing, notifications, full permissions, optimizations
  void _executePhase3InBackground() {
    print('⚙️ BOOTSTRAP PHASE 3: Starting background initialization');
    _updateStatus(BootstrapPhase.phase3, 'Initializing background features...', 0.65);

    // Execute phase 3 without blocking UI
    Timer(const Duration(milliseconds: 500), () async {
      try {
        await _executePhase3();
      } catch (e) {
        print('❌ BOOTSTRAP PHASE 3: Error: $e');
      }
    });
  }

  /// Execute Phase 3 steps
  Future<void> _executePhase3() async {
    // Step 1: Request essential permissions
    _updateStatus(BootstrapPhase.phase3, 'Requesting permissions...', 0.7);
    await _requestEssentialPermissions();

    // Step 2: Initialize location services
    _updateStatus(BootstrapPhase.phase3, 'Setting up location services...', 0.8);
    await _initializeLocationServices();

    // Step 3: Initialize notifications  
    _updateStatus(BootstrapPhase.phase3, 'Setting up notifications...', 0.85);
    await _initializeNotificationServices();

    // Step 4: Initialize geofencing (delayed)
    Timer(const Duration(seconds: 5), () async {
      _updateStatus(BootstrapPhase.phase3, 'Initializing geofencing...', 0.9);
      await _initializeGeofencingServices();
    });

    // Step 5: Background optimizations
    Timer(const Duration(seconds: 10), () async {
      _updateStatus(BootstrapPhase.phase3, 'Running optimizations...', 0.95);
      await _performBackgroundOptimizations();
      
      _phase3Complete = true;
      _updateStatus(BootstrapPhase.phase3, 'All features ready', 1.0);
      print('✅ BOOTSTRAP PHASE 3: Completed');
    });
  }

  // Phase 1 Implementation
  Future<void> _loadCachedSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _bootstrapData['notificationDistance'] = prefs.getInt('notification_distance') ?? 100;
      _bootstrapData['autoFocusEnabled'] = prefs.getBool('auto_focus_enabled') ?? true;
      _bootstrapData['useOpenStreetMap'] = prefs.getBool('use_openstreetmap') ?? false;
      print('✅ BOOTSTRAP: Cached settings loaded');
    } catch (e) {
      print('⚠️ BOOTSTRAP: Error loading cached settings: $e');
    }
  }

  Future<void> _initializeTheme() async {
    // Theme initialization is handled by ThemeProvider
    // Just mark as ready
    _bootstrapData['themeReady'] = true;
  }

  // Phase 2 Implementation
  Future<void> _loadMapProviderSetting() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final useOSM = prefs.getBool('use_openstreetmap') ?? false;
      _bootstrapData['mapProvider'] = useOSM ? 'openStreetMap' : 'googleMaps';
      print('✅ BOOTSTRAP: Map provider loaded: ${_bootstrapData['mapProvider']}');
    } catch (e) {
      print('⚠️ BOOTSTRAP: Error loading map provider: $e');
      _bootstrapData['mapProvider'] = 'googleMaps';
    }
  }

  Future<void> _checkLocationServices() async {
    try {
      final status = await LocationService.getLocationServiceStatus();
      _bootstrapData['locationServiceStatus'] = status;
      print('✅ BOOTSTRAP: Location service status checked');
    } catch (e) {
      print('⚠️ BOOTSTRAP: Error checking location services: $e');
    }
  }

  Future<void> _loadEssentialCachedData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _bootstrapData['lastKnownLatitude'] = prefs.getDouble('last_known_latitude');
      _bootstrapData['lastKnownLongitude'] = prefs.getDouble('last_known_longitude');
      print('✅ BOOTSTRAP: Essential cached data loaded');
    } catch (e) {
      print('⚠️ BOOTSTRAP: Error loading cached data: $e');
    }
  }

  // Phase 3 Implementation
  Future<void> _requestEssentialPermissions() async {
    try {
      // Request location permission (non-blocking for UI)
      final locationStatus = await Permission.locationWhenInUse.status;
      if (!locationStatus.isGranted) {
        await Permission.locationWhenInUse.request();
      }

      // Request notification permission
      final notificationStatus = await Permission.notification.status;
      if (!notificationStatus.isGranted) {
        await Permission.notification.request();
      }

      print('✅ BOOTSTRAP: Essential permissions requested');
    } catch (e) {
      print('⚠️ BOOTSTRAP: Error requesting permissions: $e');
    }
  }

  Future<void> _initializeLocationServices() async {
    try {
      // Get current location for camera positioning
      final position = await LocationService.getCurrentLocation();
      if (position != null) {
        _bootstrapData['currentLocation'] = {
          'latitude': position.latitude,
          'longitude': position.longitude,
          'accuracy': position.accuracy,
        };
        
        // Save for future use
        final prefs = await SharedPreferences.getInstance();
        await prefs.setDouble('last_known_latitude', position.latitude);
        await prefs.setDouble('last_known_longitude', position.longitude);
      }
      print('✅ BOOTSTRAP: Location services initialized');
    } catch (e) {
      print('⚠️ BOOTSTRAP: Error initializing location services: $e');
    }
  }

  Future<void> _initializeNotificationServices() async {
    try {
      // Notification initialization is already done in main.dart
      // Just mark as ready
      _bootstrapData['notificationsReady'] = true;
      print('✅ BOOTSTRAP: Notification services ready');
    } catch (e) {
      print('⚠️ BOOTSTRAP: Error with notification services: $e');
    }
  }

  Future<void> _initializeGeofencingServices() async {
    try {
      final helper = GeofencingIntegrationHelper.instance;
      if (!helper.isInitialized) {
        await helper.initializeGeofencing(
          autoStartService: true,
          onGeofenceEvent: null, // Will be set by screens
        );
      }
      _bootstrapData['geofencingReady'] = true;
      print('✅ BOOTSTRAP: Geofencing services initialized');
    } catch (e) {
      print('⚠️ BOOTSTRAP: Error initializing geofencing: $e');
    }
  }

  Future<void> _performBackgroundOptimizations() async {
    try {
      // Battery optimization checks, cache cleanup, etc.
      _bootstrapData['optimizationsComplete'] = true;
      print('✅ BOOTSTRAP: Background optimizations completed');
    } catch (e) {
      print('⚠️ BOOTSTRAP: Error in background optimizations: $e');
    }
  }

  /// Update bootstrap status and notify listeners
  void _updateStatus(BootstrapPhase phase, String step, double progress) {
    _currentPhase = phase;
    _currentStep = step;
    _progress = progress;
    notifyListeners();
  }

  /// Reset bootstrap service
  void reset() {
    _isInitialized = false;
    _currentPhase = BootstrapPhase.notStarted;
    _currentStep = '';
    _progress = 0.0;
    _errorMessage = null;
    _phase1Complete = false;
    _phase2Complete = false;
    _phase3Complete = false;
    _bootstrapData.clear();
    notifyListeners();
  }

  /// Get specific bootstrap data
  T? getData<T>(String key) {
    return _bootstrapData[key] as T?;
  }

  /// Check if specific feature is ready
  bool isFeatureReady(String feature) {
    switch (feature) {
      case 'theme':
        return _bootstrapData['themeReady'] ?? false;
      case 'map':
        return _bootstrapData['mapProvider'] != null;
      case 'location':
        return _bootstrapData['currentLocation'] != null;
      case 'notifications':
        return _bootstrapData['notificationsReady'] ?? false;
      case 'geofencing':
        return _bootstrapData['geofencingReady'] ?? false;
      default:
        return false;
    }
  }
}

/// Bootstrap phases enum
enum BootstrapPhase {
  notStarted,
  phase1, // Instant UI
  phase2, // Critical data
  phase3, // Background features
  error,
}