import 'dart:async';
import 'dart:math';
import 'dart:ui' as ui;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:locado_final/helpers/database_helper.dart';
import 'package:locado_final/models/location_model.dart';
import 'package:locado_final/models/task_location.dart';
import 'package:locado_final/screens/task_detail_screen.dart';
import 'package:locado_final/screens/task_input_screen.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'dart:io';
import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import '../services/geofencing_integration_helper.dart';
import '../services/locado_background_service.dart';
import 'debug_screen.dart';
import 'package:locado_final/models/calendar_event.dart';
import 'package:locado_final/screens/calendar_screen.dart';
import '../location_service.dart';
import 'package:locado_final/services/delete_task_service.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:locado_final/screens/delete_task_confirmation_screen.dart';
import 'package:flutter/services.dart';
import '../services/onboarding_service.dart';
import 'package:locado_final/screens/task_input_screen.dart' show TaskInputScreenWithState;
import 'package:provider/provider.dart';
import '../theme/theme_provider.dart';
import 'ai_location_search_screen.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

// HELPER KLASA za sortiranje task-ova po udaljenosti
class TaskWithDistance {
  final TaskLocation task;
  final double distance;

  TaskWithDistance(this.task, this.distance);
}

class HomeMapScreen extends StatefulWidget {
  final LatLng? selectedLocation;
  const HomeMapScreen({Key? key, this.selectedLocation}) : super(key: key);

  @override
  State<HomeMapScreen> createState() => _HomeMapScreenState();
}

class _HomeMapScreenState extends State<HomeMapScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver, GeofencingScreenMixin {

  late GoogleMapController _mapController;
  Set<Marker> _markers = {};
  LatLng? _currentLocation;
  bool _isLoading = true;
  int _notificationDistance = 100;
  final FlutterLocalNotificationsPlugin _flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

  List<TaskLocation> _nearbyTasks = [];
  List<TaskLocation> _savedLocations = [];
  late AnimationController _pulseController;
  bool _isMapReady = false;
  static const platformLockScreen = MethodChannel('locado.lockscreen/channel');
  TaskLocation? _lastAddedTask;
  int _previousTaskCount = 0;

  // Smart geofencing variables
  bool _isAppInForeground = true;

  bool _autoFocusEnabled = true;
  StreamSubscription<Position>? _positionStream;
  bool _isTrackingLocation = false;

  // Search functionality variables
  Set<Marker> _searchMarkers = {};
  static String get googleApiKey => dotenv.env['GOOGLE_MAPS_API_KEY'] ?? '';

  bool _hasShownBatteryWarning = false;
  DateTime? _lastBatteryCheck;
  static const MethodChannel _geofenceChannel = MethodChannel('com.example.locado_final/geofence');

  Map<String, dynamic>? _pendingTaskState;
  bool _isSearchingForTaskInput = false;

  bool _isManuallyFocusing = false;

  // Battery optimization FAB state variables
  bool _isBatteryWhitelisted = false;
  bool _canRequestWhitelist = false;
  bool _isBatteryLoading = false;
  bool _showBatteryFAB = false;

  @override
  void initState() {
    super.initState();

    _setupImmediateUI();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeEverythingAsync();
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      DeleteTaskService.checkAndHandlePendingDeleteTask(context);
    });
  }

  void _setupImmediateUI() {
    // SAMO stvari potrebne da UI radi ODMAH
    WidgetsBinding.instance.addObserver(this);
    LocadoBackgroundService.setGeofenceEventListener(_handleGeofenceEvent);

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat(reverse: true);

    // KRITIČNO - odmah ukloni loading spinner
    setState(() {
      _isLoading = false;
    });
  }

  Future<void> _initializeEverythingAsync() async {
    try {
      final List<Future> parallelOperations = [
        _fastLoadBasicLocations(),
        _requestLocationPermission(),
        _requestNotificationPermission(),
        _initializeNotifications(),
        _loadSettings(),
        _initializePreviousTaskCount(),
        _checkForTaskDetailFromNotification(),
        _checkBatteryOptimizationSmart(),
        _checkBatteryOptimizationForFAB(),
      ];

      await Future.wait(parallelOperations);

      _performInitialLocationFocus();

      _initializeGeofencingSystemFast();

    } catch (e) {
      // Uklanjamo debugPrint u production
    }
  }

  Future<void> _checkBatteryOptimizationSmart() async {
    try {
      // 1. Check timing - don't show too frequently
      if (!_shouldShowBatteryWarning()) {
        return;
      }

      // 2. Check battery optimization status
      bool needsWhitelist = false;

      try {
        final result = await _geofenceChannel.invokeMethod('checkBatteryOptimization');
        final bool isWhitelisted = result['isWhitelisted'] ?? false;

        if (!isWhitelisted) {
          needsWhitelist = true; // App is battery optimized - needs whitelist
        }

      } catch (e) {
        // If Android check fails, don't show dialog (fail silently)
        print('Battery optimization check failed: $e');
        return;
      }

      // 3. Only show if app needs whitelist
      if (!needsWhitelist) {
        return; // App is already whitelisted
      }

      // 4. Check if geofencing is being used
      if (!isGeofencingEnabled || _savedLocations.isEmpty) {
        return; // Geofencing not used - warning not needed
      }

      // 5. Wait for UI to load - don't interrupt startup
      await Future.delayed(const Duration(seconds: 2));

      // 6. Check if screen is still active
      if (!mounted) return;

      // 7. Show warning dialog
      _showBatteryOptimizationWarning();

      // 8. Remember it was shown
      await _saveBatteryWarningShown();

    } catch (e) {
      // Silent fail - don't interrupt startup
      print('Battery check error: $e');
    }
  }

  // Battery optimization check specifically for FAB display
  Future<void> _checkBatteryOptimizationForFAB() async {
    if (_isBatteryLoading) return;

    setState(() => _isBatteryLoading = true);

    try {
      final result = await _geofenceChannel.invokeMethod('checkBatteryOptimization');

      final isWhitelisted = result['isWhitelisted'] as bool? ?? false;
      final canRequest = result['canRequestWhitelist'] as bool? ?? false;

      setState(() {
        _isBatteryWhitelisted = isWhitelisted;
        _canRequestWhitelist = canRequest;
        _isBatteryLoading = false;
        // Show FAB only if app is NOT whitelisted and can request whitelist and has tasks
        _showBatteryFAB = !isWhitelisted && canRequest;
      });

      debugPrint('Battery FAB check: isWhitelisted=$isWhitelisted, canRequest=$canRequest, showFAB=$_showBatteryFAB');

    } catch (e) {
      setState(() => _isBatteryLoading = false);
      debugPrint('Error checking battery optimization for FAB: $e');
    }


  }

  // Request battery optimization whitelist from FAB
  Future<void> _requestBatteryOptimizationFromFAB() async {
    if (_isBatteryLoading) return;

    setState(() => _isBatteryLoading = true);

    try {
      final result = await _geofenceChannel.invokeMethod('requestBatteryOptimizationWhitelist');

      // Immediately hide FAB when user goes to system settings
      setState(() {
        _showBatteryFAB = false;
      });

      // Wait a bit then check status again
      await Future.delayed(const Duration(seconds: 2));
      await _checkBatteryOptimizationForFAB();

    } catch (e) {
      setState(() => _isBatteryLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error requesting battery optimization: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // Show battery optimization dialog when FAB is tapped
  void _showBatteryOptimizationDialog() {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (BuildContext context) {
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Container(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.75,
              maxWidth: MediaQuery.of(context).size.width * 0.9,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.orange,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(16),
                      topRight: Radius.circular(16),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.battery_saver, color: Colors.white, size: 28),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          'Background App Activity',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // Content
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Why is this important section
                        const Text(
                          'Why is this important?',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                        ),
                        const SizedBox(height: 16),

                        // Current status info
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.orange.shade50,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.orange.shade200),
                          ),
                          child: Text(
                            'Current Status: Your app is not optimized and may experience delayed notifications.',
                            style: TextStyle(
                              color: Colors.orange.shade800,
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Optimized benefits
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.check_circle, color: Colors.green, size: 20),
                            const SizedBox(width: 12),
                            const Expanded(
                              child: Text(
                                'When Optimized (Recommended):',
                                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        const Padding(
                          padding: EdgeInsets.only(left: 32),
                          child: Text(
                            '• Location notifications work 24/7\n'
                                '• Alerts appear even when app is closed\n'
                                '• Geofencing works reliably',
                            style: TextStyle(fontSize: 14, height: 1.5),
                          ),
                        ),

                        const SizedBox(height: 20),

                        // Not optimized warnings
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.warning, color: Colors.orange, size: 20),
                            const SizedBox(width: 12),
                            const Expanded(
                              child: Text(
                                'When Not Optimized:',
                                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        const Padding(
                          padding: EdgeInsets.only(left: 32),
                          child: Text(
                            '• Notifications may be delayed\n'
                                '• Alerts might not appear when phone is locked\n'
                                '• Location tracking may pause',
                            style: TextStyle(fontSize: 14, height: 1.5),
                          ),
                        ),

                        const SizedBox(height: 20),

                        // Info box
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.blue.shade50,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.blue.shade200),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(Icons.info_outline, color: Colors.blue.shade600, size: 24),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  'This setting helps ensure you never miss important location-based reminders.',
                                  style: TextStyle(
                                    color: Colors.blue.shade700,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // Action buttons
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  child: Row(
                    children: [
                      // Cancel button
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(context),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            side: BorderSide(color: Colors.grey.shade400),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Text(
                            'Cancel',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(width: 16),

                      // Optimize button
                      Expanded(
                        child: ElevatedButton(
                          onPressed: _isBatteryLoading ? null : () async {
                            Navigator.pop(context); // Close dialog first
                            await _requestBatteryOptimizationFromFAB();
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.orange,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: 2,
                          ),
                          child: _isBatteryLoading
                              ? const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              ),
                              SizedBox(width: 8),
                              Text('Processing...'),
                            ],
                          )
                              : const Text(
                            'Optimize',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  bool _shouldShowBatteryWarning() {
    // Don't show if already shown in this session
    if (_hasShownBatteryWarning) {
      return false;
    }

    // Check if shown in last 3 days
    final lastShown = _lastBatteryCheck;
    if (lastShown != null) {
      final daysSinceLastShown = DateTime.now().difference(lastShown).inDays;
      if (daysSinceLastShown < 3) {
        return false; // Shown recently, skip
      }
    }

    return true;
  }

  Future<void> _saveBatteryWarningShown() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('last_battery_warning', DateTime.now().toIso8601String());

      setState(() {
        _hasShownBatteryWarning = true;
        _lastBatteryCheck = DateTime.now();
      });
    } catch (e) {
      // Silent fail
    }
  }

  void _showBatteryOptimizationWarning() {
    if (!mounted) return;

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.battery_alert, color: Colors.orange, size: 24),
              SizedBox(width: 8),
              Expanded(child: Text('Battery Optimization')),
            ],
          ),
          content: const Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Android is currently killing background processes to save battery. This may affect geofencing functionality.',
                style: TextStyle(fontSize: 16),
              ),
              SizedBox(height: 12),
              Text(
                '🔋 Add app to whitelist\n'
                    '📍 Guaranteed precise location tracking\n'
                    '🔔 Reliable task notifications',
                style: TextStyle(fontSize: 14, color: Colors.grey),
              ),
              SizedBox(height: 8),
              Text(
                'You can configure this in the Settings section.',
                style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: Colors.grey),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: const Text('Maybe Later'),
            ),
            ElevatedButton.icon(
              onPressed: () {
                Navigator.of(context).pop();
                Navigator.of(context).pushNamed('/settings');
              },
              icon: const Icon(Icons.settings),
              label: const Text('Open Settings'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _fastLoadBasicLocations() async {
    try {
      // PARALELNI database pozivi
      final List<Future> dbOperations = [
        DatabaseHelper.instance.getAllLocations(),
        DatabaseHelper.instance.getAllTaskLocations(),
      ];

      final results = await Future.wait(dbOperations);
      final locations = results[0] as List<Location>;
      final taskLocations = results[1] as List<TaskLocation>;

      _savedLocations = taskLocations;

      // OSNOVNI MARKERI PRVO - bez custom ikona (brže)
      await _createBasicMarkers(locations, taskLocations);

      // CUSTOM MARKERI - kreiraj u background-u
      _upgradeToCustomMarkersLater(taskLocations);

      // GEOFENCING SYNC - samo ako je enabled
      if (isGeofencingEnabled && _savedLocations.isNotEmpty) {
        // Ne čekaj - pokreni u background-u
        syncTaskLocationsFromScreen(_savedLocations);
      }

      // Check FAB status after loading tasks
      await _checkBatteryOptimizationForFAB();

    } catch (e) {
      // Uklanjamo debugPrint u production
    }
  }

  Future<void> _createBasicMarkers(List<Location> locations, List<TaskLocation> taskLocations) async {
    Set<Marker> newMarkers = {};

    // Location markeri - isti kao pre
    for (var location in locations) {
      newMarkers.add(
        Marker(
          markerId: MarkerId('location_${location.id}'),
          position: LatLng(location.latitude!, location.longitude!),
          infoWindow: InfoWindow(
            title: location.description ?? 'No Description',
            snippet: location.type ?? 'No Type',
          ),
        ),
      );
    }

    // Task markeri - OSNOVNI (default ikone za brzinu)
    for (var task in taskLocations) {
      newMarkers.add(
        Marker(
          markerId: MarkerId('task_${task.id}'),
          position: LatLng(task.latitude, task.longitude),
          infoWindow: InfoWindow(title: task.title),
          onTap: () => _handleTaskTap(task),
        ),
      );
    }

    // Search markeri - dodaj ih u osnovne markere
    newMarkers.addAll(_searchMarkers);

    setState(() {
      _markers = newMarkers;
    });
  }


  // Background upgrade - ne blokira UI
  void _upgradeToCustomMarkersLater(List<TaskLocation> taskLocations) {
    // Kratka pauza da se UI stabilizuje
    Future.delayed(Duration(milliseconds: 300), () async {
      try {
        Set<Marker> updatedMarkers = Set.from(_markers);

        // Kreiraj custom markere POSTUPNO - ne sve odjednom
        for (var task in taskLocations) {
          final color = Color(int.parse(task.colorHex.replaceFirst('#', '0xff')));
          final icon = await createCustomMarker(task.title, color);

          // Zameni basic marker sa custom
          updatedMarkers.removeWhere((marker) =>
          marker.markerId.value == 'task_${task.id}');

          updatedMarkers.add(
            Marker(
              markerId: MarkerId('task_${task.id}'),
              position: LatLng(task.latitude, task.longitude),
              icon: icon,
              infoWindow: InfoWindow(title: task.title),
              onTap: () => _handleTaskTap(task), // ISTA funkcionalnost
            ),
          );

          // Update UI postepeno
          if (mounted) {
            setState(() {
              _markers = updatedMarkers;
            });
          }

          // Kratka pauza između markera
          await Future.delayed(Duration(milliseconds: 50));
        }
      } catch (e) {
        // Uklanjamo debugPrint u production
      }
    });
  }

  Future<void> _handleTaskTap(TaskLocation task) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (ctx) => TaskDetailScreen(taskLocation: task),
      ),
    );

    if (result != null) {
      if (result == true) {
        await _loadSavedLocationsWithRefresh();
      } else if (result is Map) {
        if (result['refresh'] == true) {
          await _loadSavedLocationsWithRefresh();
          if (result['focusLocation'] != null) {
            await _focusOnNewLocation(result['focusLocation'] as LatLng);
          }
        } else if (result['action'] == 'openLocationSearchForEdit') {
          // User wants to search for location from TaskDetail

          // RESET previous state first
          _pendingTaskState = null;
          _isSearchingForTaskInput = false;

          // Set new state
          _pendingTaskState = result['taskState'];
          _isSearchingForTaskInput = true;

          // Open search mode
          setState(() {

          });

          // Show helpful message
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Search for a new location to update your task'),
              backgroundColor: Colors.blue,
              duration: Duration(seconds: 3),
            ),
          );
        }
      }
    }
  }

  // OPTIMIZOVANA geofencing inicijalizacija
  void _initializeGeofencingSystemFast() {
    // POKRENI U BACKGROUND-U - ne čekaj
    Future.delayed(Duration(milliseconds: 500), () async {
      try {
        // GEOFENCING INITIALIZATION - ista logika, ali BEZ dugih delay-a
        initializeScreenGeofencing(
          onGeofenceEvent: _handleGeofenceEvent,
        );

        final helper = GeofencingIntegrationHelper.instance;

        if (!helper.isInitialized) {
          final initialized = await helper.initializeGeofencing(
            autoStartService: true,
            onGeofenceEvent: _handleGeofenceEvent,
          );

          if (initialized) {
            // LOAD EXISTING TASKS - optimizovana verzija (već uklonili delay-e)
            await helper.initializeExistingTasks();
          }
        }

      } catch (e) {
        // Uklanjamo debugPrint u production
      }
    });
  }

  Future<void> _initializePreviousTaskCount() async {
    final taskLocations = await DatabaseHelper.instance.getAllTaskLocations();
    _previousTaskCount = taskLocations.length;
  }

  Future<void> _checkForTaskDetailFromNotification() async {
    try {
      const platform = MethodChannel('com.example.locado_final/task_detail');
      final result = await platform.invokeMethod('checkPendingTaskDetail');

      if (result != null && result['hasTaskDetail'] == true) {
        final taskId = result['taskId'] as String;
        final taskTitle = result['taskTitle'] as String;
        final fromNotification = result['fromNotification'] as bool;

        // Load task from database and navigate
        await _navigateToTaskDetail(taskId, taskTitle);
      }
    } catch (e) {
      // Uklanjamo debugPrint u production
    }
  }

  Future<void> _navigateToTaskDetail(String taskId, String taskTitle) async {
    try {
      // Find task in database
      final taskLocations = await DatabaseHelper.instance.getAllTaskLocations();
      final task = taskLocations.firstWhere(
            (task) => task.id.toString() == taskId,
        orElse: () => throw Exception('Task not found'),
      );

      // Navigate to TaskDetailScreen
      final result = await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (ctx) => TaskDetailScreen(taskLocation: task),
        ),
      );

      // Handle result
      if (result != null) {
        if (result == true) {
          await _loadSavedLocationsWithRefresh();
        } else if (result is Map && result['refresh'] == true) {
          await _loadSavedLocationsWithRefresh();
          if (result['focusLocation'] != null) {
            await _focusOnNewLocation(result['focusLocation'] as LatLng);
          }
        }
      }

    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error opening task: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _showViberStyleAlert(GeofenceEvent event) async {
    try {
      await platformLockScreen.invokeMethod('showLockScreenAlert', {
        'taskTitle': event.title ?? 'Task Location',
        'taskMessage': 'You are near: ${event.title ?? "a task location"}',
        'taskId': event.taskId ?? 'unknown',
      });
    } catch (e) {
      // Fallback na postojeću metodu
      await _showRegularWakeNotification(event);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    switch (state) {
      case AppLifecycleState.resumed:
        _isAppInForeground = true;
        if (_autoFocusEnabled) {
          _startLocationTracking();
        }
        break;
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
        _isAppInForeground = false;
        break;
      case AppLifecycleState.hidden:
        break;
    }
  }

  Future<void> _initializeNotifications() async {
    const AndroidInitializationSettings initializationSettingsAndroid =
    AndroidInitializationSettings('@mipmap/ic_launcher');
    final InitializationSettings initializationSettings =
    InitializationSettings(android: initializationSettingsAndroid);
    await _flutterLocalNotificationsPlugin.initialize(initializationSettings,
      onDidReceiveNotificationResponse: _onNotificationTapped,);

    // Main location notification channel
    const AndroidNotificationChannel locationChannel = AndroidNotificationChannel(
      'location_channel',
      'Location Notifications',
      description: 'Smart geofencing notifications',
      importance: Importance.max,
      enableVibration: true,
      playSound: true,
      showBadge: true,
      enableLights: true,
      ledColor: const Color.fromARGB(255, 255, 0, 0),
    );

    const AndroidNotificationChannel wakeChannel = AndroidNotificationChannel(
      'geofence_wake_channel',
      'Geofence Wake Alerts',
      description: 'Location alerts that wake the screen',
      importance: Importance.max,
      enableVibration: true,
      playSound: true,
      showBadge: true,
      enableLights: true,
      ledColor: const Color.fromARGB(255, 0, 255, 0),
    );

    const AndroidNotificationChannel testChannel = AndroidNotificationChannel(
      'test_channel',
      'Test Notifications',
      description: 'For testing notification settings',
      importance: Importance.max,
      enableVibration: true,
      playSound: true,
    );

    final androidPlugin = _flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

    if (androidPlugin != null) {
      await androidPlugin.createNotificationChannel(locationChannel);
      await androidPlugin.createNotificationChannel(testChannel);
      await androidPlugin.createNotificationChannel(wakeChannel);
    }
  }

  Future<void> _requestNotificationPermission() async {
    final status = await Permission.notification.status;
    if (!status.isGranted) {
      await Permission.notification.request();
    }
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final distance = prefs.getInt('notification_distance') ?? 100;
    final autoFocus = prefs.getBool('auto_focus_enabled') ?? true; // ✅ DODANO

    setState(() {
      _notificationDistance = distance;
      _autoFocusEnabled = autoFocus; // ✅ DODANO
    });

    final lastWarningStr = prefs.getString('last_battery_warning');
    if (lastWarningStr != null) {
      _lastBatteryCheck = DateTime.parse(lastWarningStr);
      print('🔋 Loaded last battery warning: $_lastBatteryCheck');
    }

    // ✅ POKRENI/ZAUSTAVI LOCATION TRACKING PREMA POSTAVCI
    if (_autoFocusEnabled) {
      _startLocationTracking();
    } else {
      _stopLocationTracking();
    }
  }

  Future<BitmapDescriptor> createCustomMarker(String title, Color color) async {
    final ui.PictureRecorder recorder = ui.PictureRecorder();
    final Canvas canvas = Canvas(recorder);
    const double size = 150.0;

    final Paint shadowPaint = Paint()
      ..color = Colors.black.withOpacity(0.25)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);

    final Paint markerPaint = Paint()..color = color;
    canvas.drawCircle(const Offset(size / 2 + 2, size / 2 - 8), size / 2 - 10, shadowPaint);
    canvas.drawCircle(const Offset(size / 2, size / 2 - 10), size / 2 - 10, markerPaint);

    final Path triangle = Path();
    triangle.moveTo(size / 2 - 25, size / 2 + 10);
    triangle.lineTo(size / 2 + 25, size / 2 + 10);
    triangle.lineTo(size / 2, size + 30);
    triangle.close();
    canvas.drawPath(triangle, markerPaint);

    final TextPainter textPainter = TextPainter(textDirection: TextDirection.ltr);
    String shortTitle = title.length > 10 ? '${title.substring(0, 10)}...' : title;
    textPainter.text = TextSpan(
      text: shortTitle,
      style: const TextStyle(fontSize: 24, color: Colors.white, fontWeight: FontWeight.bold),
    );
    textPainter.layout();
    textPainter.paint(canvas, Offset((size - textPainter.width) / 2, (size / 2 - 10 - textPainter.height / 2)));

    final img = await recorder.endRecording().toImage(size.toInt(), (size + 30).toInt());
    final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
    return BitmapDescriptor.fromBytes(byteData!.buffer.asUint8List());
  }

  double _calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    const earthRadius = 6371000;
    final dLat = _degreesToRadians(lat2 - lat1);
    final dLon = _degreesToRadians(lon2 - lon1);
    final a = (sin(dLat / 2) * sin(dLat / 2)) +
        cos(_degreesToRadians(lat1)) * cos(_degreesToRadians(lat2)) *
            (sin(dLon / 2) * sin(dLon / 2));
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return earthRadius * c;
  }

  double _degreesToRadians(double degrees) {
    return degrees * pi / 180;
  }

  String _formatDistance(double distanceInMeters) {
    // Proveri da li uređaj koristi imperijalne jedinice (SAD, UK, Burma)
    final locale = WidgetsBinding.instance.platformDispatcher.locale;
    final useImperialUnits = ['US', 'GB', 'MM'].contains(locale.countryCode);

    if (useImperialUnits) {
      // Konvertuj u milje (1 metar = 0.000621371 milja)
      final miles = distanceInMeters * 0.000621371;
      if (miles < 0.1) {
        final feet = distanceInMeters * 3.28084; // Konvertuj u stope
        return '${feet.round()} ft';
      } else {
        return '${miles.toStringAsFixed(1)} mi';
      }
    } else {
      // Koristi metrički sistem
      if (distanceInMeters < 1000) {
        return '${distanceInMeters.round()} m';
      } else {
        final kilometers = distanceInMeters / 1000;
        return '${kilometers.toStringAsFixed(1)} km';
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    print('🎨 BUILD DEBUG: brightness = ${Theme.of(context).brightness}');
    print('🎨 BUILD DEBUG: cardColor = ${Theme.of(context).cardColor}');
    print('🎨 BUILD DEBUG: primaryColor = ${Theme.of(context).primaryColor}');
    print('🎨 BUILD DEBUG: scaffoldBackgroundColor = ${Theme.of(context).scaffoldBackgroundColor}');

    return Scaffold(
      body: Stack(
        children: [
          GoogleMap(
            onMapCreated: (controller) {
              _mapController = controller;
              _isMapReady = true;
            },
            initialCameraPosition: CameraPosition(
              target: widget.selectedLocation ?? LatLng(48.2082, 16.3738),
              zoom: 15,
            ),
            markers: _markers,
            myLocationEnabled: true,
            myLocationButtonEnabled: true,
            onLongPress: (LatLng position) async {
              final result = await Navigator.push(
                context,
                MaterialPageRoute(builder: (ctx) => TaskInputScreen(location: position)),
              );
              if (result == true) {
                _fastLoadBasicLocations();
              }
            },
            onTap: (LatLng location) {
              // Clear search results when tapping on map
              if (_searchMarkers.isNotEmpty) {
                setState(() {
                  _searchMarkers.clear();
                });
                _updateMapWithSearchResults();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Search results cleared'),
                    backgroundColor: Colors.blue,
                    duration: Duration(seconds: 2),
                  ),
                );
              } else {
                _centerCameraOnLocation(location);
              }
            },
          ),
          AnimatedBuilder(
            animation: _pulseController,
            builder: (context, child) {
              return Stack(
                children: _nearbyTasks.map((task) {
                  final animation = Tween(begin: 20.0, end: 40.0).animate(_pulseController);
                  return FutureBuilder<ScreenCoordinate>(
                    future: _mapController.getScreenCoordinate(LatLng(task.latitude, task.longitude)),
                    builder: (context, snapshot) {
                      if (!snapshot.hasData) return const SizedBox.shrink();
                      final screenPoint = snapshot.data!;
                      return Positioned(
                        left: screenPoint.x.toDouble() - animation.value / 2,
                        top: screenPoint.y.toDouble() - animation.value / 2,
                        child: GestureDetector(
                          onTap: () async {
                            final result = await Navigator.push(
                              context,
                              MaterialPageRoute(builder: (ctx) => TaskDetailScreen(taskLocation: task)),
                            );
                            if (result == true) {
                              _fastLoadBasicLocations();
                            }
                          },
                          child: Column(
                            children: [
                              Container(
                                width: animation.value,
                                height: animation.value,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Colors.teal.withOpacity(0.3),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(4),
                                  boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 2)],
                                ),
                                child: Text(
                                  task.title,
                                  style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
                                ),
                              )
                            ],
                          ),
                        ),
                      );
                    },
                  );
                }).toList(),
              );
            },
          ),
          if (_isLoading)
            const Center(child: CircularProgressIndicator()),

        ],
      ),

      // Battery Optimization FAB
      floatingActionButton: _showBatteryFAB ? FloatingActionButton(
        onPressed: _showBatteryOptimizationDialog,
        backgroundColor: Colors.orange,
        foregroundColor: Colors.white,
        child: const Icon(Icons.battery_alert, size: 28),
        elevation: 6,
        heroTag: "battery_fab",
      ) : null,

      //floatingActionButtonLocation: FloatingActionButtonLocation.startTop,
      //floatingActionButtonLocation: FloatingActionButtonLocation.startFloat,
      //floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      floatingActionButtonLocation: FloatingActionButtonLocation.startTop,
    );
  }

  Future<void> _loadSavedLocationsAndFocusNew() async {
    try {
      List<Location> locations = await DatabaseHelper.instance.getAllLocations();
      List<TaskLocation> taskLocations = await DatabaseHelper.instance.getAllTaskLocations();

      // Pronađi novi task (poslednji u listi)
      TaskLocation? newTask;
      if (taskLocations.isNotEmpty) {
        if (_savedLocations.length < taskLocations.length) {
          // Ima novi task
          newTask = taskLocations.last;
          _lastAddedTask = newTask;
        }
      }

      _savedLocations = taskLocations;

      Set<Marker> newMarkers = {};

      // Dodaj location markere
      for (var location in locations) {
        newMarkers.add(
          Marker(
            markerId: MarkerId('location_${location.id}'),
            position: LatLng(location.latitude!, location.longitude!),
            infoWindow: InfoWindow(
              title: location.description ?? 'No Description',
              snippet: location.type ?? 'No Type',
            ),
          ),
        );
      }

      // Dodaj task markere
      for (var task in taskLocations) {
        final color = Color(int.parse(task.colorHex.replaceFirst('#', '0xff')));
        final icon = await createCustomMarker(task.title, color);

        newMarkers.add(
          Marker(
            markerId: MarkerId('task_${task.id}'),
            position: LatLng(task.latitude, task.longitude),
            icon: icon,
            infoWindow: InfoWindow(title: task.title),
            onTap: () async {
              final result = await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (ctx) => TaskDetailScreen(taskLocation: task),
                ),
              );

              if (result != null) {
                if (result == true) {
                  // Obični refresh bez fokusiranja
                  await _loadSavedLocationsWithRefresh();
                } else if (result is Map && result['refresh'] == true) {
                  // Refresh sa fokusiranjem na novu lokaciju
                  await _loadSavedLocationsWithRefresh();

                  if (result['focusLocation'] != null) {
                    await _focusOnNewLocation(result['focusLocation'] as LatLng);
                  }
                }
              }
            },
          ),
        );
      }

      setState(() {
        _markers = newMarkers;
        _isLoading = false;
      });

      // FOKUS NA NOVU LOKACIJU
      if (newTask != null && _mapController != null) {
        await _focusOnNewTask(newTask);
      }

      // Geofencing sync
      if (isGeofencingEnabled && _savedLocations.isNotEmpty) {
        await syncTaskLocationsFromScreen(_savedLocations);
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  // Nova metoda za fokus na task:
  Future<void> _focusOnNewTask(TaskLocation task) async {
    try {
      // Animate camera to new task location
      await _mapController!.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(
            target: LatLng(task.latitude, task.longitude),
            zoom: 17.0, // Close zoom level to see the task clearly
            bearing: 0,
            tilt: 0,
          ),
        ),
      );
    } catch (e) {
      // Uklanjamo debugPrint u production
    }
  }

  void _centerCameraOnLocation(LatLng location) {
    if (_mapController != null) {
      _mapController!.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(
            target: location,
            zoom: 17,
            bearing: 0,
            tilt: 0,
          ),
        ),
      );
    }
  }

  // GEOFENCING EVENT HANDLER
  void _handleGeofenceEvent(GeofenceEvent event) {
    if (event.eventType == GeofenceEventType.enter && mounted) {
      _showViberStyleAlert(event);
    }
  }

  Future<void> _showRegularWakeNotification(GeofenceEvent event) async {
    try {
      await _createWakeScreenNotificationChannel();

      final androidDetails = AndroidNotificationDetails(
        'geofence_wake_channel',
        'Geofence Wake Alerts',
        channelDescription: 'Location alerts that wake the screen',
        importance: Importance.max,
        priority: Priority.max,
        fullScreenIntent: true,
        category: AndroidNotificationCategory.alarm,
        visibility: NotificationVisibility.public,
        showWhen: true,
        when: DateTime.now().millisecondsSinceEpoch,
        autoCancel: true,
        enableLights: true,
        ledColor: const Color.fromARGB(255, 0, 255, 0),
        ledOnMs: 1000,
        ledOffMs: 500,
        enableVibration: true,
        vibrationPattern: Int64List.fromList([0, 1000, 500, 1000]),
        playSound: true,
        sound: const RawResourceAndroidNotificationSound('notification'),
        color: const Color.fromARGB(255, 0, 255, 0),
        colorized: true,
        timeoutAfter: 20000,
        largeIcon: const DrawableResourceAndroidBitmap('@mipmap/ic_launcher'),
      );

      final platformDetails = NotificationDetails(android: androidDetails);
      final notificationId = DateTime.now().millisecondsSinceEpoch ~/ 1000;

      await _flutterLocalNotificationsPlugin.show(
        notificationId,
        '🚨 LOCADO ALERT 🚨',
        'You are near: ${event.title ?? "a task location"}',
        platformDetails,
        payload: jsonEncode({
          'type': 'fullscreen_geofence',
          'taskId': event.taskId,
          'taskTitle': event.title,
          'geofenceId': event.geofenceId,
        }),
      );
    } catch (e) {
      // Uklanjamo debugPrint u production
    }
  }

  Future<void> _createWakeScreenNotificationChannel() async {
    const AndroidNotificationChannel wakeChannel = AndroidNotificationChannel(
      'geofence_wake_channel',
      'Geofence Wake Alerts',
      description: 'Location alerts that wake the screen and appear on lock screen',
      importance: Importance.max,
      enableVibration: true,
      playSound: true,
      showBadge: true,
      enableLights: true,
      ledColor: const Color.fromARGB(255, 0, 255, 0),
    );

    final androidPlugin = _flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

    if (androidPlugin != null) {
      await androidPlugin.createNotificationChannel(wakeChannel);
    }
  }

  Future<void> _requestLocationPermission() async {
    final whenInUseStatus = await Permission.locationWhenInUse.status;
    if (!whenInUseStatus.isGranted) {
      await Permission.locationWhenInUse.request();
    }

    final backgroundStatus = await Permission.locationAlways.status;
    if (!backgroundStatus.isGranted) {
      await Permission.locationAlways.request();
    }
  }

  // NOVA METODA ZA OSVEŽAVANJE SA FOKUSIRANJEM
  Future<void> _loadSavedLocationsWithRefresh() async {
    try {
      List<Location> locations = await DatabaseHelper.instance.getAllLocations();
      List<TaskLocation> taskLocations = await DatabaseHelper.instance.getAllTaskLocations();
      _savedLocations = taskLocations;

      Set<Marker> newMarkers = {};

      // Dodaj location markere
      for (var location in locations) {
        newMarkers.add(
          Marker(
            markerId: MarkerId('location_${location.id}'),
            position: LatLng(location.latitude!, location.longitude!),
            infoWindow: InfoWindow(
              title: location.description ?? 'No Description',
              snippet: location.type ?? 'No Type',
            ),
          ),
        );
      }

      // Dodaj task markere sa novim pozicijama
      for (var task in taskLocations) {
        final color = Color(int.parse(task.colorHex.replaceFirst('#', '0xff')));
        final icon = await createCustomMarker(task.title, color);

        newMarkers.add(
          Marker(
            markerId: MarkerId('task_${task.id}'),
            position: LatLng(task.latitude, task.longitude),
            icon: icon,
            infoWindow: InfoWindow(title: task.title),
            onTap: () async {
              final result = await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (ctx) => TaskDetailScreen(taskLocation: task),
                ),
              );

              if (result != null) {
                if (result == true) {
                  // Obični refresh bez fokusiranja
                  await _loadSavedLocationsWithRefresh();
                } else if (result is Map && result['refresh'] == true) {
                  // Refresh sa fokusiranjem na novu lokaciju
                  await _loadSavedLocationsWithRefresh();

                  if (result['focusLocation'] != null) {
                    await _focusOnNewLocation(result['focusLocation'] as LatLng);
                  }
                }
              }
            },
          ),
        );
      }

      setState(() {
        _markers = newMarkers;
        _isLoading = false;
      });

      // GEOFENCING AUTO-SYNC
      if (isGeofencingEnabled && _savedLocations.isNotEmpty) {
        await syncTaskLocationsFromScreen(_savedLocations);
      }

    } catch (e) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  // DODATNO - METODA ZA FOKUSIRANJE NA PROMENJEN TASK
  Future<void> _focusOnUpdatedTask(int taskId) async {
    try {
      final updatedTask = _savedLocations.firstWhere((task) => task.id == taskId);

      if (_mapController != null) {
        await _mapController!.animateCamera(
          CameraUpdate.newCameraPosition(
            CameraPosition(
              target: LatLng(updatedTask.latitude, updatedTask.longitude),
              zoom: 17.0,
              bearing: 0,
              tilt: 0,
            ),
          ),
        );
      }
    } catch (e) {
      // Uklanjamo debugPrint u production
    }
  }

  void _onNotificationTapped(NotificationResponse notificationResponse) {
    final payload = notificationResponse.payload;

    if (payload != null && payload.startsWith('geofence_')) {
      final geofenceId = payload.replaceFirst('geofence_', '');
      // TODO: Implementiraj navigaciju do task detail screen-a
    }
  }

  Future<void> _returnToTaskInputWithLocation(LatLng selectedLocation, String locationName) async {
    if (_pendingTaskState == null) return;

    // Clear search state
    setState(() {
      _searchMarkers.clear();
      _isSearchingForTaskInput = false;
    });
    await _updateMapWithSearchResults();

    // Navigate to TaskInputScreen with restored state and new location
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (ctx) => TaskInputScreenWithState(
          originalLocation: LatLng(
            _pendingTaskState!['originalLocation']['latitude'],
            _pendingTaskState!['originalLocation']['longitude'],
          ),
          selectedLocation: selectedLocation,
          selectedLocationName: locationName,
          savedState: _pendingTaskState!,
        ),
      ),
    );

    // Clear pending state
    _pendingTaskState = null;

    // Handle result
    if (result == true) {
      await _loadSavedLocationsAndFocusNew();
    }
  }

  // NOVA METODA ZA FOKUSIRANJE NA NOVU LOKACIJU
  Future<void> _focusOnNewLocation(LatLng newLocation) async {
    try {
      if (_mapController != null) {
        await _mapController!.animateCamera(
          CameraUpdate.newCameraPosition(
            CameraPosition(
              target: newLocation,
              zoom: 17.0, // Close zoom to see the new location clearly
              bearing: 0,
              tilt: 0,
            ),
          ),
        );
      }
    } catch (e) {
      // Uklanjamo debugPrint u production
    }
  }

// Replace the _sortTasksByDistanceWithDetails method with this optimized version:

  /// Optimizovana verzija - koristi cached lokaciju (MNOGO BRŽE!)
  Future<List<TaskWithDistance>> _sortTasksByDistanceWithDetails(List<TaskLocation> tasks) async {
    print('🔍 SORT DEBUG: Pokrećem sortiranje za ${tasks.length} taskova');

    // UVEK dobij fresh lokaciju - korisnik se kreće!
    print('🔍 SORT DEBUG: Dobijam fresh lokaciju...');
    final apiPosition = await LocationService.getCurrentLocation();
    print('🔍 SORT DEBUG: Fresh lokacija = $apiPosition');

    if (apiPosition == null) {
      print('❌ SORT DEBUG: Nema fresh lokacije! Vraćam sve sa 0.0 distance');
      return tasks.map((task) => TaskWithDistance(task, 0.0)).toList();
    }

    final currentPosition = LatLng(apiPosition.latitude, apiPosition.longitude);
    print('✅ SORT DEBUG: Koristim fresh lokaciju (lat: ${currentPosition.latitude}, lng: ${currentPosition.longitude})');

    // Koristi fresh lokaciju za kalkulacije
    List<TaskWithDistance> tasksWithDistance = [];

    for (int i = 0; i < tasks.length && i < 3; i++) {  // Debug samo prva 3 taska
      final task = tasks[i];
      final distance = _calculateDistance(
        currentPosition.latitude,
        currentPosition.longitude,
        task.latitude,
        task.longitude,
      );

      print('🔍 SORT DEBUG: Task "${task.title}" (lat: ${task.latitude}, lng: ${task.longitude}) -> Distance = ${distance}m');
      tasksWithDistance.add(TaskWithDistance(task, distance));
    }

    // Dodaj ostatak taskova bez debug-a
    for (int i = 3; i < tasks.length; i++) {
      final task = tasks[i];
      final distance = _calculateDistance(
        currentPosition.latitude,
        currentPosition.longitude,
        task.latitude,
        task.longitude,
      );
      tasksWithDistance.add(TaskWithDistance(task, distance));
    }

    tasksWithDistance.sort((a, b) => a.distance.compareTo(b.distance));
    print('✅ SORT DEBUG: Sortiranje završeno, prvi task = ${tasksWithDistance.first.distance}m');
    return tasksWithDistance;
  }




  void _showCalendar() async {
    try {
      // Navigiraj na CalendarScreen
      final result = await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (ctx) => const CalendarScreen(),
        ),
      );

      // Refresh data ako je potrebno (za buduće funkcionalnosti)
      if (result == true) {
        await _fastLoadBasicLocations();
      }

    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.error, color: Colors.white),
              const SizedBox(width: 8),
              Expanded(
                child: Text('Error opening calendar: $e'),
              ),
            ],
          ),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  // Sortira task-ove po udaljenosti od trenutne lokacije
  Future<List<TaskLocation>> _sortTasksByDistance(List<TaskLocation> tasks) async {
    try {
      // Pokušaj da dobiješ trenutnu lokaciju
      final currentPosition = await LocationService.getCurrentLocation();

      if (currentPosition == null) {
        // Ako nema lokacije, vrati originalni redosled
        return tasks;
      }

      // Kreiraj listu sa udaljenostima
      List<TaskWithDistance> tasksWithDistance = [];

      for (final task in tasks) {
        final distance = _calculateDistance(
          currentPosition.latitude,
          currentPosition.longitude,
          task.latitude,
          task.longitude,
        );

        tasksWithDistance.add(TaskWithDistance(task, distance));
      }

      // Sortiraj po udaljenosti (najbliži prvi)
      tasksWithDistance.sort((a, b) => a.distance.compareTo(b.distance));

      // Vrati samo task-ove
      final sortedTasks = tasksWithDistance.map((twd) => twd.task).toList();

      return sortedTasks;

    } catch (e) {
      return tasks; // Fallback na originalni redosled
    }
  }


  /// Pokreće praćenje lokacije za auto focus funkcionalnost
  Future<void> _startLocationTracking() async {
    if (_isTrackingLocation) return;

    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        debugPrint('❌ Location services are disabled');
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          debugPrint('❌ Location permissions are denied');
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        debugPrint('❌ Location permissions are permanently denied');
        return;
      }

      _isTrackingLocation = true;
      debugPrint('✅ Auto focus location tracking started');

      // Konfiguracija za location stream
      const LocationSettings locationSettings = LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10, // Update every 10 meters
      );

      _positionStream = Geolocator.getPositionStream(
        locationSettings: locationSettings,
      ).listen(
            (Position position) {
          _handleLocationUpdate(position);
        },
        onError: (error) {
          debugPrint('❌ Location stream error: $error');
          _stopLocationTracking();
        },
      );

    } catch (e) {
      debugPrint('❌ Error starting location tracking: $e');
      _isTrackingLocation = false;
    }
  }

  /// Zaustavlja praćenje lokacije
  void _stopLocationTracking() {
    if (!_isTrackingLocation) return;

    try {
      _positionStream?.cancel();
      _positionStream = null;
      _isTrackingLocation = false;
      debugPrint('🛑 Auto focus location tracking stopped');
    } catch (e) {
      debugPrint('❌ Error stopping location tracking: $e');
    }
  }

  /// Rukuje ažuriranjem lokacije za auto focus
  void _handleLocationUpdate(Position position) {
    if (_isManuallyFocusing) {
      print('⏸️ LOCATION UPDATE: Skipping because manually focusing on task');
      return;
    }

    print('🔍 LOCATION UPDATE: Dobijen position = lat: ${position.latitude}, lng: ${position.longitude}');
    print('🔍 LOCATION UPDATE: _autoFocusEnabled = $_autoFocusEnabled');
    print('🔍 LOCATION UPDATE: _isMapReady = $_isMapReady');
    print('🔍 LOCATION UPDATE: _mapController != null = ${_mapController != null}');

    if (!_autoFocusEnabled || !_isMapReady || _mapController == null) {
      print('❌ LOCATION UPDATE: Izlazim zbog uslova - neću ažurirati _currentLocation!');
      return;
    }

    try {
      final newLocation = LatLng(position.latitude, position.longitude);
      print('🔍 LOCATION UPDATE: Nova lokacija = $newLocation');
      print('🔍 LOCATION UPDATE: Stara _currentLocation = $_currentLocation');

      // Ažuriraj mapu samo ako je korisnik značajno pomjerio
      if (_currentLocation == null ||
          _calculateDistance(
              _currentLocation!.latitude,
              _currentLocation!.longitude,
              newLocation.latitude,
              newLocation.longitude
          ) > 20) { // 20 metara threshold

        print('✅ LOCATION UPDATE: Postavljam _currentLocation = $newLocation');
        _currentLocation = newLocation;

        // Animiraj kameru na novu lokaciju
        _mapController!.animateCamera(
          CameraUpdate.newCameraPosition(
            CameraPosition(
              target: newLocation,
              zoom: 16.0, // Optimalni zoom za praćenje
              bearing: position.heading, // Prati smjer kretanja
              tilt: 30.0, // Lagani tilt za bolje praćenje
            ),
          ),
        );

        print('✅ LOCATION UPDATE: Kamera ažurirana');
      } else {
        print('⏭️ LOCATION UPDATE: Premala promena distance, ne ažuriram');
      }
    } catch (e) {
      print('❌ LOCATION UPDATE Error: $e');
    }
  }


  Future<void> _updateMapWithSearchResults() async {
    Set<Marker> allMarkers = Set.from(_markers);

    // Remove old search markers
    allMarkers.removeWhere((marker) => marker.markerId.value.startsWith('search_'));

    // Add new search markers
    allMarkers.addAll(_searchMarkers);

    setState(() {
      _markers = allMarkers;
    });
  }

  Future<void> _returnToTaskDetailWithLocation(LatLng selectedLocation, String locationName) async {
    if (_pendingTaskState == null) return;

    // Clear search state
    setState(() {
      _searchMarkers.clear();
      _isSearchingForTaskInput = false;
    });
    await _updateMapWithSearchResults();

    // Store the pending state before clearing it
    final currentPendingState = _pendingTaskState!;
    _pendingTaskState = null; // Clear immediately after storing

    // Navigate to TaskDetailScreenWithState with restored state and new location
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (ctx) => TaskDetailScreenWithState(
          taskLocation: _createTaskLocationFromState(currentPendingState!),
          selectedLocation: selectedLocation,
          selectedLocationName: locationName,
          savedState: currentPendingState!,
        ),
      ),
    );

    // Clear pending state
    _pendingTaskState = null;

    // Handle result
    if (result != null) {
      if (result == true) {
        await _loadSavedLocationsWithRefresh();
      } else if (result is Map && result['refresh'] == true) {
        await _loadSavedLocationsWithRefresh();
        if (result['focusLocation'] != null) {
          await _focusOnNewLocation(result['focusLocation'] as LatLng);
        }
      }
    }
  }

  // Helper method to create TaskLocation from saved state:
  TaskLocation _createTaskLocationFromState(Map<String, dynamic> state) {
    DateTime? scheduledDateTime;
    if (state['scheduledDate'] != null && state['scheduledTime'] != null) {
      final date = DateTime.parse(state['scheduledDate']);
      final timeData = state['scheduledTime'];
      scheduledDateTime = DateTime(
        date.year,
        date.month,
        date.day,
        timeData['hour'],
        timeData['minute'],
      );
    }

    return TaskLocation(
      id: state['taskId'],
      latitude: state['originalLocation']['latitude'],
      longitude: state['originalLocation']['longitude'],
      title: state['title'] ?? '',
      taskItems: List<String>.from(state['items'] ?? []),
      colorHex: '#${(state['selectedColor'] ?? Colors.teal.value).toRadixString(16).substring(2)}',
      scheduledDateTime: scheduledDateTime,
      linkedCalendarEventId: state['linkedCalendarEventId'],
    );
  }

  Future<void> _performInitialLocationFocus() async {
    try {
      // Wait for map to be ready
      int waitAttempts = 0;
      while (!_isMapReady && waitAttempts < 30) {
        await Future.delayed(const Duration(milliseconds: 100));
        waitAttempts++;
      }

      if (!_isMapReady || _mapController == null) {
        print('Map not ready for initial focus');
        return;
      }

      // Get current location using existing service
      final position = await LocationService.getCurrentLocation();

      if (position != null) {
        final userLocation = LatLng(position.latitude, position.longitude);

        // Update current location variable
        _currentLocation = userLocation;

        // Focus camera on user location
        await _mapController!.animateCamera(
          CameraUpdate.newCameraPosition(
            CameraPosition(
              target: userLocation,
              zoom: 16.0,
              bearing: 0,
              tilt: 0,
            ),
          ),
        );

        print('Initial camera focused on user location');

      } else {
        print('Could not get initial location, keeping default');
      }

    } catch (e) {
      print('Error during initial location focus: $e');
    }
  }

  // PUBLIC METHODS for MainNavigationScreen communication
  Future<void> performSearch(String searchTerm) async {
    if (searchTerm.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a search term'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    try {
      LatLng searchCenter = LatLng(48.2082, 16.3738); // Default Vienna
      if (_currentLocation != null) {
        searchCenter = _currentLocation!;
      }

      final url = 'https://maps.googleapis.com/maps/api/place/nearbysearch/json'
          '?location=${searchCenter.latitude},${searchCenter.longitude}'
          '&radius=5000'
          '&keyword=${Uri.encodeComponent(searchTerm)}'
          '&key=$googleApiKey';

      final response = await http.get(Uri.parse(url));

      if (response.statusCode == 200) {
        final body = json.decode(response.body);
        final List results = body['results'];

        Set<Marker> searchMarkers = {};

        for (final place in results) {
          final lat = place['geometry']['location']['lat'];
          final lng = place['geometry']['location']['lng'];
          final name = place['name'];

          searchMarkers.add(
            Marker(
              markerId: MarkerId('search_${place['place_id']}'),
              position: LatLng(lat, lng),
              icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
              infoWindow: InfoWindow(
                title: name,
                snippet: 'Tap to create task here',
              ),
              onTap: () async {
                setState(() {
                  _searchMarkers.clear();
                });
                await _updateMapWithSearchResults();

                final result = await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (ctx) => TaskInputScreen(
                      location: LatLng(lat, lng),
                      locationName: name,
                    ),
                  ),
                );

                if (result == true) {
                  await _loadSavedLocationsAndFocusNew();
                }
              },
            ),
          );
        }

        setState(() {
          _searchMarkers = searchMarkers;
        });

        await _updateMapWithSearchResults();

        if (_mapController != null && results.isNotEmpty) {
          _mapController!.animateCamera(
            CameraUpdate.newLatLngZoom(searchCenter, 14),
          );
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              results.isEmpty
                  ? 'No locations found for "$searchTerm"'
                  : 'Found ${results.length} locations',
            ),
            backgroundColor: results.isEmpty ? Colors.blue : Colors.green,
          ),
        );

      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to search locations'),
            backgroundColor: Colors.red,
          ),
        );
      }

    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Search error: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

// Fokusira mapu na određeni task
  Future<void> _focusOnTaskLocation(TaskLocation task) async {
    try {
      if (_mapController != null) {
        await _mapController!.animateCamera(
          CameraUpdate.newCameraPosition(
            CameraPosition(
              target: LatLng(task.latitude, task.longitude),
              zoom: 17.0,
              bearing: 0,
              tilt: 0,
            ),
          ),
        );

        // Pošalji potvrdu korisniku
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.location_on, color: Colors.white),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('Focused on: ${task.title}'),
                ),
              ],
            ),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      // Silent fail in production
    }
  }

  // PUBLIC wrapper for MainNavigationScreen communication
  Future<void> focusOnTaskLocation(TaskLocation task) async {
    print('🗺️ MAP FOCUS DEBUG: Starting focus on task: ${task.title}');
    print('🗺️ MAP FOCUS DEBUG: Task coordinates: ${task.latitude}, ${task.longitude}');

    try {
      if (_mapController != null && _isMapReady) {
        // POSTAVITI FLAG DA SPREČIMO AUTO FOCUS
        _isManuallyFocusing = true;
        print('🗺️ MAP FOCUS DEBUG: Set manual focusing flag = true');

        print('🗺️ MAP FOCUS DEBUG: Animating camera to task location');

        await _mapController!.animateCamera(
          CameraUpdate.newCameraPosition(
            CameraPosition(
              target: LatLng(task.latitude, task.longitude),
              zoom: 18.0,
              bearing: 0,
              tilt: 45.0,
            ),
          ),
        );

        print('✅ MAP FOCUS DEBUG: Camera animation completed');

        // Snackbar potvrda
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.location_on, color: Colors.white),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text('Focused on: ${task.title}'),
                  ),
                ],
              ),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 5), // Povećano na 5 sekundi
            ),
          );
        }

        // SAČEKAJ 5 SEKUNDI PA UKLONI FLAG
        Future.delayed(const Duration(seconds: 5), () {
          print('🗺️ MAP FOCUS DEBUG: Clearing manual focusing flag');
          _isManuallyFocusing = false;
        });

      } else {
        print('❌ MAP FOCUS DEBUG: Map controller not ready!');
      }
    } catch (e) {
      print('❌ MAP FOCUS DEBUG: Error during camera animation: $e');
      _isManuallyFocusing = false; // Ukloni flag u slučaju greške
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pulseController.dispose();
    super.dispose();
  }
}