import 'dart:async';
import 'dart:math';
import 'dart:ui' as ui;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' as gmaps;
import 'package:flutter_map/flutter_map.dart' as osm;
import 'package:latlong2/latlong.dart' as ll;
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
import '../widgets/osm_map_widget.dart';

// Enum for map provider selection
enum MapProvider { googleMaps, openStreetMap }

// Universal coordinate class that works with both providers
class UniversalLatLng {
  final double latitude;
  final double longitude;

  UniversalLatLng(this.latitude, this.longitude);

  // Convert to Google Maps LatLng
  gmaps.LatLng toGoogleMaps() => gmaps.LatLng(latitude, longitude);
  
  // Convert to OpenStreetMap LatLng
  ll.LatLng toOpenStreetMap() => ll.LatLng(latitude, longitude);

  // Create from Google Maps LatLng
  factory UniversalLatLng.fromGoogleMaps(gmaps.LatLng gLatLng) {
    return UniversalLatLng(gLatLng.latitude, gLatLng.longitude);
  }

  // Create from OpenStreetMap LatLng
  factory UniversalLatLng.fromOpenStreetMap(ll.LatLng osmLatLng) {
    return UniversalLatLng(osmLatLng.latitude, osmLatLng.longitude);
  }

  @override
  String toString() => 'UniversalLatLng($latitude, $longitude)';
}

// Universal marker class
class UniversalMarker {
  final String markerId;
  final UniversalLatLng position;
  final String? title;
  final String? snippet;
  final VoidCallback? onTap;
  final gmaps.BitmapDescriptor? googleIcon;
  final Widget? osmWidget;

  UniversalMarker({
    required this.markerId,
    required this.position,
    this.title,
    this.snippet,
    this.onTap,
    this.googleIcon,
    this.osmWidget,
  });
}

// HELPER CLASS for task distance calculations (unchanged)
class TaskWithDistance {
  final TaskLocation task;
  final double distance;

  TaskWithDistance(this.task, this.distance);
}

class HomeMapScreen extends StatefulWidget {
  final gmaps.LatLng? selectedLocation;
  const HomeMapScreen({Key? key, this.selectedLocation}) : super(key: key);

  @override
  State<HomeMapScreen> createState() => _HomeMapScreenState();
}

class _HomeMapScreenState extends State<HomeMapScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver, GeofencingScreenMixin {

  // Map provider selection
  MapProvider _currentMapProvider = MapProvider.googleMaps;
  
  // Google Maps controllers and variables
  gmaps.GoogleMapController? _googleMapController;
  Set<gmaps.Marker> _googleMarkers = {};
  
  // OpenStreetMap controllers and variables  
  osm.MapController? _osmMapController;
  Set<OSMMarker> _osmMarkers = {};

  // Universal variables (work with both providers)
  UniversalLatLng? _currentLocation;
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

  // Search functionality variables (universal)
  Set<gmaps.Marker> _googleSearchMarkers = {};
  Set<OSMMarker> _osmSearchMarkers = {};
  static String get googleApiKey => dotenv.env['GOOGLE_MAPS_API_KEY_ANDROID'] ?? '';

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
    // Setup things needed for immediate UI response
    WidgetsBinding.instance.addObserver(this);
    LocadoBackgroundService.setGeofenceEventListener(_handleGeofenceEvent);

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat(reverse: true);

    // CRITICAL - remove loading spinner immediately
    setState(() {
      _isLoading = false;
    });
  }

  Future<void> _initializeEverythingAsync() async {
    try {
      final List<Future> parallelOperations = [
        _loadMapProviderSetting(), // NEW: Load map provider preference
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
      print('Initialization error: $e');
    }
  }

  // NEW METHOD: Load map provider setting
  Future<void> _loadMapProviderSetting() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final useOSM = prefs.getBool('use_openstreetmap') ?? false;
      
      setState(() {
        _currentMapProvider = useOSM ? MapProvider.openStreetMap : MapProvider.googleMaps;
      });

      print('🗺️ HYBRID: Loaded map provider: ${_currentMapProvider.name}');
    } catch (e) {
      print('Error loading map provider setting: $e');
      // Default to Google Maps on error
      _currentMapProvider = MapProvider.googleMaps;
    }
  }

  // NEW METHOD: Save map provider setting
  Future<void> _saveMapProviderSetting(MapProvider provider) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('use_openstreetmap', provider == MapProvider.openStreetMap);
      
      setState(() {
        _currentMapProvider = provider;
      });

      print('🗺️ HYBRID: Saved map provider: ${provider.name}');
    } catch (e) {
      print('Error saving map provider setting: $e');
    }
  }

  // CONTINUE WITH EXISTING METHODS (unchanged)...
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

  // HYBRID METHOD: Load basic locations for both providers
  Future<void> _fastLoadBasicLocations() async {
    try {
      // Parallel database calls
      final List<Future> dbOperations = [
        DatabaseHelper.instance.getAllLocations(),
        DatabaseHelper.instance.getAllTaskLocations(),
      ];

      final results = await Future.wait(dbOperations);
      final locations = results[0] as List<Location>;
      final taskLocations = results[1] as List<TaskLocation>;

      _savedLocations = taskLocations;

      // Create markers for current provider
      if (_currentMapProvider == MapProvider.googleMaps) {
        await _createGoogleMarkers(locations, taskLocations);
        _upgradeGoogleMarkersLater(taskLocations);
      } else {
        await _createOSMMarkers(locations, taskLocations);
      }

      // GEOFENCING SYNC - only if enabled
      if (isGeofencingEnabled && _savedLocations.isNotEmpty) {
        // Don't wait - run in background
        syncTaskLocationsFromScreen(_savedLocations);
      }

      // Check FAB status after loading tasks
      await _checkBatteryOptimizationForFAB();

    } catch (e) {
      print('Error loading locations: $e');
    }
  }

  // GOOGLE MAPS: Create basic markers
  Future<void> _createGoogleMarkers(List<Location> locations, List<TaskLocation> taskLocations) async {
    Set<gmaps.Marker> newMarkers = {};

    // Location markers
    for (var location in locations) {
      newMarkers.add(
        gmaps.Marker(
          markerId: gmaps.MarkerId('location_${location.id}'),
          position: gmaps.LatLng(location.latitude!, location.longitude!),
          infoWindow: gmaps.InfoWindow(
            title: location.description ?? 'No Description',
            snippet: location.type ?? 'No Type',
          ),
        ),
      );
    }

    // Task markers - BASIC (default icons for speed)
    for (var task in taskLocations) {
      newMarkers.add(
        gmaps.Marker(
          markerId: gmaps.MarkerId('task_${task.id}'),
          position: gmaps.LatLng(task.latitude, task.longitude),
          infoWindow: gmaps.InfoWindow(title: task.title),
          onTap: () => _handleTaskTap(task),
        ),
      );
    }

    // Search markers - add them to basic markers
    newMarkers.addAll(_googleSearchMarkers);

    setState(() {
      _googleMarkers = newMarkers;
    });

    print('✅ HYBRID: Created ${newMarkers.length} Google markers');
  }

  // OPENSTREETMAP: Create OSM markers
  Future<void> _createOSMMarkers(List<Location> locations, List<TaskLocation> taskLocations) async {
    Set<OSMMarker> newMarkers = {};

    // Location markers
    for (var location in locations) {
      newMarkers.add(
        OSMMarker(
          markerId: 'location_${location.id}',
          position: ll.LatLng(location.latitude!, location.longitude!),
          title: location.description ?? 'No Description',
          child: OSMConverter.createDefaultMarker(color: Colors.blue),
        ),
      );
    }

    // Task markers
    for (var task in taskLocations) {
      final color = Color(int.parse(task.colorHex.replaceFirst('#', '0xff')));
      
      newMarkers.add(
        OSMMarker(
          markerId: 'task_${task.id}',
          position: ll.LatLng(task.latitude, task.longitude),
          title: task.title,
          child: _createOSMCustomMarker(task.title, color),
          onTap: () => _handleTaskTap(task),
        ),
      );
    }

    // Search markers
    newMarkers.addAll(_osmSearchMarkers);

    setState(() {
      _osmMarkers = newMarkers;
    });

    print('✅ HYBRID: Created ${newMarkers.length} OSM markers');
  }

  // Create custom OSM marker widget
  Widget _createOSMCustomMarker(String title, Color color) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: const Icon(
        Icons.location_on,
        color: Colors.white,
        size: 20,
      ),
    );
  }

  // Background upgrade - Google Maps custom markers (unchanged logic)
  void _upgradeGoogleMarkersLater(List<TaskLocation> taskLocations) {
    // Short pause to let UI stabilize
    Future.delayed(Duration(milliseconds: 300), () async {
      try {
        Set<gmaps.Marker> updatedMarkers = Set.from(_googleMarkers);

        // Create custom markers GRADUALLY - not all at once
        for (var task in taskLocations) {
          final color = Color(int.parse(task.colorHex.replaceFirst('#', '0xff')));
          final icon = await createCustomMarker(task.title, color);

          // Replace basic marker with custom
          updatedMarkers.removeWhere((marker) =>
          marker.markerId.value == 'task_${task.id}');

          updatedMarkers.add(
            gmaps.Marker(
              markerId: gmaps.MarkerId('task_${task.id}'),
              position: gmaps.LatLng(task.latitude, task.longitude),
              icon: icon,
              infoWindow: gmaps.InfoWindow(title: task.title),
			onTap: () => _handleTaskTap(task), // SAME functionality
					   ),
					 );

					 // Update UI gradually
					 if (mounted && _currentMapProvider == MapProvider.googleMaps) {
					   setState(() {
						 _googleMarkers = updatedMarkers;
					   });
					 }

					 // Short pause between markers
					 await Future.delayed(Duration(milliseconds: 50));
				   }
				 } catch (e) {
				   print('Error upgrading Google markers: $e');
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
					   await _focusOnNewLocation(UniversalLatLng.fromGoogleMaps(result['focusLocation'] as gmaps.LatLng));
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

			 // OPTIMIZED geofencing initialization (unchanged)
			 void _initializeGeofencingSystemFast() {
			   // RUN IN BACKGROUND - don't wait
			   Future.delayed(Duration(milliseconds: 500), () async {
				 try {
				   // GEOFENCING INITIALIZATION - same logic, but WITHOUT long delays
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
					   // LOAD EXISTING TASKS - optimized version (already removed delays)
					   await helper.initializeExistingTasks();
					 }
				   }

				 } catch (e) {
				   print('Geofencing initialization error: $e');
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
				 print('Error checking task detail from notification: $e');
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
					   await _focusOnNewLocation(UniversalLatLng.fromGoogleMaps(result['focusLocation'] as gmaps.LatLng));
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
				 // Fallback to existing method
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
			   final autoFocus = prefs.getBool('auto_focus_enabled') ?? true;

			   setState(() {
				 _notificationDistance = distance;
				 _autoFocusEnabled = autoFocus;
			   });

			   final lastWarningStr = prefs.getString('last_battery_warning');
			   if (lastWarningStr != null) {
				 _lastBatteryCheck = DateTime.parse(lastWarningStr);
				 print('🔋 Loaded last battery warning: $_lastBatteryCheck');
			   }

			   // START/STOP LOCATION TRACKING ACCORDING TO SETTING
			   if (_autoFocusEnabled) {
				 _startLocationTracking();
			   } else {
				 _stopLocationTracking();
			   }
			 }

			 Future<gmaps.BitmapDescriptor> createCustomMarker(String title, Color color) async {
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
			   return gmaps.BitmapDescriptor.fromBytes(byteData!.buffer.asUint8List());
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
			   // Check if device uses imperial units (US, UK, Burma)
			   final locale = WidgetsBinding.instance.platformDispatcher.locale;
			   final useImperialUnits = ['US', 'GB', 'MM'].contains(locale.countryCode);

			   if (useImperialUnits) {
				 // Convert to miles (1 meter = 0.000621371 miles)
				 final miles = distanceInMeters * 0.000621371;
				 if (miles < 0.1) {
				   final feet = distanceInMeters * 3.28084; // Convert to feet
				   return '${feet.round()} ft';
				 } else {
				   return '${miles.toStringAsFixed(1)} mi';
				 }
			   } else {
				 // Use metric system
				 if (distanceInMeters < 1000) {
				   return '${distanceInMeters.round()} m';
				 } else {
				   final kilometers = distanceInMeters / 1000;
				   return '${kilometers.toStringAsFixed(1)} km';
				 }
			   }
			 }

			 // HYBRID BUILD METHOD: Choose correct map widget based on provider
			 @override
			 Widget build(BuildContext context) {
			   print('🎨 BUILD DEBUG: brightness = ${Theme.of(context).brightness}');
			   print('🎨 BUILD DEBUG: cardColor = ${Theme.of(context).cardColor}');
			   print('🎨 BUILD DEBUG: primaryColor = ${Theme.of(context).primaryColor}');
			   print('🎨 BUILD DEBUG: scaffoldBackgroundColor = ${Theme.of(context).scaffoldBackgroundColor}');
			   print('🗺️ HYBRID BUILD: Using ${_currentMapProvider.name}');

			   return Scaffold(
				 body: Stack(
				   children: [
					 // HYBRID MAP WIDGET - choose based on provider
					 if (_currentMapProvider == MapProvider.googleMaps)
					   _buildGoogleMap()
					 else
					   _buildOpenStreetMap(),

					 // Animated builder for nearby tasks (works with both providers)
					 AnimatedBuilder(
					   animation: _pulseController,
					   builder: (context, child) {
						 return Stack(
						   children: _nearbyTasks.map((task) {
							 final animation = Tween(begin: 20.0, end: 40.0).animate(_pulseController);
							 
							 if (_currentMapProvider == MapProvider.googleMaps) {
							   return FutureBuilder<gmaps.ScreenCoordinate>(
								 future: _googleMapController?.getScreenCoordinate(gmaps.LatLng(task.latitude, task.longitude)),
								 builder: (context, snapshot) {
								   if (!snapshot.hasData) return const SizedBox.shrink();
								   final screenPoint = snapshot.data!;
								   return _buildPulseWidget(animation, screenPoint.x.toDouble(), screenPoint.y.toDouble(), task);
								 },
							   );
							 } else {
							   // For OSM, we'll need to implement screen coordinate conversion
							   // For now, return empty widget
							   return const SizedBox.shrink();
							 }
						   }).toList(),
						 );
					   },
					 ),

					 // Loading indicator
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

				 floatingActionButtonLocation: FloatingActionButtonLocation.startTop,
			   );
			 }

			 // GOOGLE MAPS widget
			 Widget _buildGoogleMap() {
			   return gmaps.GoogleMap(
				 onMapCreated: (controller) {
				   _googleMapController = controller;
				   _isMapReady = true;
				   print('✅ HYBRID: Google Map controller ready');
				 },
				 initialCameraPosition: gmaps.CameraPosition(
				   target: widget.selectedLocation ?? gmaps.LatLng(48.2082, 16.3738),
				   zoom: 15,
				 ),
				 markers: _googleMarkers,
				 myLocationEnabled: true,
				 myLocationButtonEnabled: true,
				 onLongPress: (gmaps.LatLng position) async {
				   final result = await Navigator.push(
					 context,
					 MaterialPageRoute(builder: (ctx) => TaskInputScreen(location: position)),
				   );
				   if (result == true) {
					 _fastLoadBasicLocations();
				   }
				 },
				 onTap: (gmaps.LatLng location) {
				   // Clear search results when tapping on map
				   if (_googleSearchMarkers.isNotEmpty) {
					 setState(() {
					   _googleSearchMarkers.clear();
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
					 _centerCameraOnLocation(UniversalLatLng.fromGoogleMaps(location));
				   }
				 },
			   );
			 }

			 // OPENSTREETMAP widget
			 Widget _buildOpenStreetMap() {
			   return OSMMapWidget(
				 initialCameraPosition: OSMCameraPosition(
				   target: widget.selectedLocation != null 
					   ? ll.LatLng(widget.selectedLocation!.latitude, widget.selectedLocation!.longitude)
					   : ll.LatLng(48.2082, 16.3738),
				   zoom: 15.0,
				 ),
				 markers: _osmMarkers,
				 onMapCreated: (controller) {
				   _osmMapController = controller;
				   _isMapReady = true;
				   print('✅ HYBRID: OSM Map controller ready');
				 },
				 myLocationEnabled: true,
				 myLocationButtonEnabled: true,
				 onLongPress: (ll.LatLng position) async {
				   final result = await Navigator.push(
					 context,
					 MaterialPageRoute(builder: (ctx) => TaskInputScreen(location: gmaps.LatLng(position.latitude, position.longitude))),
				   );
				   if (result == true) {
					 _fastLoadBasicLocations();
				   }
				 },
				 onTap: (ll.LatLng location) {
				   // Clear search results when tapping on map
				   if (_osmSearchMarkers.isNotEmpty) {
					 setState(() {
					   _osmSearchMarkers.clear();
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
					 _centerCameraOnLocation(UniversalLatLng.fromOpenStreetMap(location));
				   }
				 },
			   );
			 }

			 // Build pulse widget for nearby tasks
			 Widget _buildPulseWidget(Animation<double> animation, double x, double y, TaskLocation task) {
			   return Positioned(
				 left: x - animation.value / 2,
				 top: y - animation.value / 2,
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
			 }

			 // REMAINING METHODS (continue with existing methods but make them provider-aware)
			 
			 Future<void> _loadSavedLocationsAndFocusNew() async {
			   try {
				 List<Location> locations = await DatabaseHelper.instance.getAllLocations();
				 List<TaskLocation> taskLocations = await DatabaseHelper.instance.getAllTaskLocations();

				 // Find new task (last in list)
				 TaskLocation? newTask;
				 if (taskLocations.isNotEmpty) {
				   if (_savedLocations.length < taskLocations.length) {
					 // Has new task
					 newTask = taskLocations.last;
					 _lastAddedTask = newTask;
				   }
				 }

				 _savedLocations = taskLocations;

				 // Create markers for current provider
				 if (_currentMapProvider == MapProvider.googleMaps) {
				   await _createGoogleMarkersWithCustomIcons(locations, taskLocations);
				 } else {
				   await _createOSMMarkers(locations, taskLocations);
				 }

				 setState(() {
				   _isLoading = false;
				 });

				 // FOCUS ON NEW LOCATION
				 if (newTask != null) {
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

			 // Create Google markers with custom icons (for focus new functionality)
			 Future<void> _createGoogleMarkersWithCustomIcons(List<Location> locations, List<TaskLocation> taskLocations) async {
			   Set<gmaps.Marker> newMarkers = {};

			   // Add location markers
			   for (var location in locations) {
				 newMarkers.add(
				   gmaps.Marker(
					 markerId: gmaps.MarkerId('location_${location.id}'),
					 position: gmaps.LatLng(location.latitude!, location.longitude!),
					 infoWindow: gmaps.InfoWindow(
					   title: location.description ?? 'No Description',
					   snippet: location.type ?? 'No Type',
					 ),
				   ),
				 );
			   }

			   // Add task markers with custom icons
			   for (var task in taskLocations) {
				 final color = Color(int.parse(task.colorHex.replaceFirst('#', '0xff')));
				 final icon = await createCustomMarker(task.title, color);

				 newMarkers.add(
				   gmaps.Marker(
					 markerId: gmaps.MarkerId('task_${task.id}'),
					 position: gmaps.LatLng(task.latitude, task.longitude),
					 icon: icon,
					 infoWindow: gmaps.InfoWindow(title: task.title),
					 onTap: () => _handleTaskTap(task),
				   ),
				 );
			   }

			   setState(() {
				 _googleMarkers = newMarkers;
			   });
			 }

			 // HYBRID: Focus on new task
			 Future<void> _focusOnNewTask(TaskLocation task) async {
			   try {
				 final universalLocation = UniversalLatLng(task.latitude, task.longitude);
				 
				 if (_currentMapProvider == MapProvider.googleMaps && _googleMapController != null) {
				   // Animate camera to new task location
				   await _googleMapController!.animateCamera(
					 gmaps.CameraUpdate.newCameraPosition(
					   gmaps.CameraPosition(
						 target: universalLocation.toGoogleMaps(),
						 zoom: 17.0, // Close zoom level to see the task clearly
						 bearing: 0,
						 tilt: 0,
					   ),
					 ),
				   );
				 } else if (_currentMapProvider == MapProvider.openStreetMap && _osmMapController != null) {
				   // Move OSM camera to new task location
				   _osmMapController!.move(universalLocation.toOpenStreetMap(), 17.0);
				 }

				 print('✅ HYBRID: Focused on new task: ${task.title}');
			   } catch (e) {
				 print('Error focusing on new task: $e');
			   }
			 }

			 // HYBRID: Center camera on location
			 void _centerCameraOnLocation(UniversalLatLng location) {
			   if (_currentMapProvider == MapProvider.googleMaps && _googleMapController != null) {
				 _googleMapController!.animateCamera(
				   gmaps.CameraUpdate.newCameraPosition(
					 gmaps.CameraPosition(
					   target: location.toGoogleMaps(),
					   zoom: 17,
					   bearing: 0,
					   tilt: 0,
					 ),
				   ),
				 );
			   } else if (_currentMapProvider == MapProvider.openStreetMap && _osmMapController != null) {
				 _osmMapController!.move(location.toOpenStreetMap(), 17.0);
			   }
			 }

			 // GEOFENCING EVENT HANDLER (unchanged)
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
				 print('Error showing wake notification: $e');
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

			 // HYBRID: Load saved locations with refresh
			 Future<void> _loadSavedLocationsWithRefresh() async {
			   try {
				 List<Location> locations = await DatabaseHelper.instance.getAllLocations();
				 List<TaskLocation> taskLocations = await DatabaseHelper.instance.getAllTaskLocations();
				 _savedLocations = taskLocations;

				 // Create markers for current provider
				 if (_currentMapProvider == MapProvider.googleMaps) {
				   await _createGoogleMarkersWithCustomIcons(locations, taskLocations);
				 } else {
				   await _createOSMMarkers(locations, taskLocations);
				 }

				 setState(() {
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

			 // HYBRID: Focus on updated task
			 Future<void> _focusOnUpdatedTask(int taskId) async {
			   try {
				 final updatedTask = _savedLocations.firstWhere((task) => task.id == taskId);
				 final universalLocation = UniversalLatLng(updatedTask.latitude, updatedTask.longitude);

				 if (_currentMapProvider == MapProvider.googleMaps && _googleMapController != null) {
				   await _googleMapController!.animateCamera(
					 gmaps.CameraUpdate.newCameraPosition(
					   gmaps.CameraPosition(
						 target: universalLocation.toGoogleMaps(),
						 zoom: 17.0,
						 bearing: 0,
						 tilt: 0,
					   ),
					 ),
				   );
				 } else if (_currentMapProvider == MapProvider.openStreetMap && _osmMapController != null) {
				   _osmMapController!.move(universalLocation.toOpenStreetMap(), 17.0);
				 }
			   } catch (e) {
				print('Error focusing on updated task: $e');
				   }
				 }

				 void _onNotificationTapped(NotificationResponse notificationResponse) {
				   final payload = notificationResponse.payload;

				   if (payload != null && payload.startsWith('geofence_')) {
					 final geofenceId = payload.replaceFirst('geofence_', '');
					 // TODO: Implement navigation to task detail screen
				   }
				 }

				 Future<void> _returnToTaskInputWithLocation(gmaps.LatLng selectedLocation, String locationName) async {
				   if (_pendingTaskState == null) return;

				   // Clear search state
				   setState(() {
					 if (_currentMapProvider == MapProvider.googleMaps) {
					   _googleSearchMarkers.clear();
					 } else {
					   _osmSearchMarkers.clear();
					 }
					 _isSearchingForTaskInput = false;
				   });
				   await _updateMapWithSearchResults();

				   // Navigate to TaskInputScreen with restored state and new location
				   final result = await Navigator.push(
					 context,
					 MaterialPageRoute(
					   builder: (ctx) => TaskInputScreenWithState(
						 originalLocation: gmaps.LatLng(
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

				 // HYBRID: Focus on new location
				 Future<void> _focusOnNewLocation(UniversalLatLng newLocation) async {
				   try {
					 if (_currentMapProvider == MapProvider.googleMaps && _googleMapController != null) {
					   await _googleMapController!.animateCamera(
						 gmaps.CameraUpdate.newCameraPosition(
						   gmaps.CameraPosition(
							 target: newLocation.toGoogleMaps(),
							 zoom: 17.0, // Close zoom to see the new location clearly
							 bearing: 0,
							 tilt: 0,
						   ),
						 ),
					   );
					 } else if (_currentMapProvider == MapProvider.openStreetMap && _osmMapController != null) {
					   _osmMapController!.move(newLocation.toOpenStreetMap(), 17.0);
					 }
				   } catch (e) {
					 print('Error focusing on new location: $e');
				   }
				 }

				 /// Optimized version - uses cached location (MUCH FASTER!)
				 Future<List<TaskWithDistance>> _sortTasksByDistanceWithDetails(List<TaskLocation> tasks) async {
				   print('🔍 SORT DEBUG: Starting sorting for ${tasks.length} tasks');

				   // ALWAYS get fresh location - user is moving!
				   print('🔍 SORT DEBUG: Getting fresh location...');
				   final apiPosition = await LocationService.getCurrentLocation();
				   print('🔍 SORT DEBUG: Fresh location = $apiPosition');

				   if (apiPosition == null) {
					 print('❌ SORT DEBUG: No fresh location! Returning all with 0.0 distance');
					 return tasks.map((task) => TaskWithDistance(task, 0.0)).toList();
				   }

				   final currentPosition = UniversalLatLng(apiPosition.latitude, apiPosition.longitude);
				   print('✅ SORT DEBUG: Using fresh location (lat: ${currentPosition.latitude}, lng: ${currentPosition.longitude})');

				   // Use fresh location for calculations
				   List<TaskWithDistance> tasksWithDistance = [];

				   for (int i = 0; i < tasks.length && i < 3; i++) {  // Debug only first 3 tasks
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

				   // Add rest of tasks without debug
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
				   print('✅ SORT DEBUG: Sorting completed, first task = ${tasksWithDistance.first.distance}m');
				   return tasksWithDistance;
				 }

				 void _showCalendar() async {
				   try {
					 // Navigate to CalendarScreen
					 final result = await Navigator.push(
					   context,
					   MaterialPageRoute(
						 builder: (ctx) => const CalendarScreen(),
					   ),
					 );

					 // Refresh data if needed (for future functionality)
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

				 // Sort tasks by distance from current location
				 Future<List<TaskLocation>> _sortTasksByDistance(List<TaskLocation> tasks) async {
				   try {
					 // Try to get current location
					 final currentPosition = await LocationService.getCurrentLocation();

					 if (currentPosition == null) {
					   // If no location, return original order
					   return tasks;
					 }

					 // Create list with distances
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

					 // Sort by distance (closest first)
					 tasksWithDistance.sort((a, b) => a.distance.compareTo(b.distance));

					 // Return only tasks
					 final sortedTasks = tasksWithDistance.map((twd) => twd.task).toList();

					 return sortedTasks;

				   } catch (e) {
					 return tasks; // Fallback to original order
				   }
				 }

				 /// Start location tracking for auto focus functionality
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

					 // Configuration for location stream
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

				 /// Stop location tracking
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

				 /// Handle location updates for auto focus (HYBRID)
				 void _handleLocationUpdate(Position position) {
				   if (_isManuallyFocusing) {
					 print('⏸️ LOCATION UPDATE: Skipping because manually focusing on task');
					 return;
				   }

				   print('🔍 LOCATION UPDATE: Received position = lat: ${position.latitude}, lng: ${position.longitude}');
				   print('🔍 LOCATION UPDATE: _autoFocusEnabled = $_autoFocusEnabled');
				   print('🔍 LOCATION UPDATE: _isMapReady = $_isMapReady');
				   print('🔍 LOCATION UPDATE: Map controller available = ${(_currentMapProvider == MapProvider.googleMaps ? _googleMapController != null : _osmMapController != null)}');

				   if (!_autoFocusEnabled || !_isMapReady) {
					 print('❌ LOCATION UPDATE: Exiting due to conditions - won\'t update _currentLocation!');
					 return;
				   }

				   try {
					 final newLocation = UniversalLatLng(position.latitude, position.longitude);
					 print('🔍 LOCATION UPDATE: New location = $newLocation');
					 print('🔍 LOCATION UPDATE: Old _currentLocation = $_currentLocation');

					 // Update map only if user has moved significantly
					 if (_currentLocation == null ||
						 _calculateDistance(
							 _currentLocation!.latitude,
							 _currentLocation!.longitude,
							 newLocation.latitude,
							 newLocation.longitude
						 ) > 20) { // 20 meters threshold

					   print('✅ LOCATION UPDATE: Setting _currentLocation = $newLocation');
					   _currentLocation = newLocation;

					   // HYBRID: Animate camera to new location based on provider
					   if (_currentMapProvider == MapProvider.googleMaps && _googleMapController != null) {
						 _googleMapController!.animateCamera(
						   gmaps.CameraUpdate.newCameraPosition(
							 gmaps.CameraPosition(
							   target: newLocation.toGoogleMaps(),
							   zoom: 16.0, // Optimal zoom for tracking
							   bearing: position.heading, // Follow movement direction
							   tilt: 30.0, // Slight tilt for better tracking
							 ),
						   ),
						 );
					   } else if (_currentMapProvider == MapProvider.openStreetMap && _osmMapController != null) {
						 _osmMapController!.move(newLocation.toOpenStreetMap(), 16.0);
					   }

					   print('✅ LOCATION UPDATE: Camera updated');
					 } else {
					   print('⏭️ LOCATION UPDATE: Too small distance change, not updating');
					 }
				   } catch (e) {
					 print('❌ LOCATION UPDATE Error: $e');
				   }
				 }

				 // HYBRID: Update map with search results
				// DEBUG VERSION: Update map with search results - HYBRID support
				Future<void> _updateMapWithSearchResults() async {
				  print('🔍 UPDATE MARKERS DEBUG: Starting update for ${_currentMapProvider.name}');
				  
				  if (_currentMapProvider == MapProvider.googleMaps) {
					print('🔍 UPDATE MARKERS: Google Maps - Before: ${_googleMarkers.length} markers');
					print('🔍 UPDATE MARKERS: Google Maps - Adding: ${_googleSearchMarkers.length} search markers');
					
					Set<gmaps.Marker> allMarkers = Set.from(_googleMarkers);

					// Remove old search markers
					int removedCount = 0;
					allMarkers.removeWhere((marker) {
					  bool shouldRemove = marker.markerId.value.startsWith('search_');
					  if (shouldRemove) removedCount++;
					  return shouldRemove;
					});
					
					print('🔍 UPDATE MARKERS: Google Maps - Removed ${removedCount} old search markers');

					// Add new search markers
					allMarkers.addAll(_googleSearchMarkers);

					print('🔍 UPDATE MARKERS: Google Maps - After: ${allMarkers.length} total markers');

					setState(() {
					  _googleMarkers = allMarkers;
					});
					
					print('🔍 UPDATE MARKERS: Google Maps - State updated with ${_googleMarkers.length} markers');
					
				  } else {
					print('🔍 UPDATE MARKERS: OSM - Before: ${_osmMarkers.length} markers');
					print('🔍 UPDATE MARKERS: OSM - Adding: ${_osmSearchMarkers.length} search markers');
					
					// Debug current OSM markers
					print('🔍 UPDATE MARKERS: OSM - Current marker IDs:');
					for (final marker in _osmMarkers) {
					  print('  - ${marker.markerId}');
					}
					
					// Debug search markers
					print('🔍 UPDATE MARKERS: OSM - Search marker IDs:');
					for (final marker in _osmSearchMarkers) {
					  print('  - ${marker.markerId} at ${marker.position}');
					}
					
					Set<OSMMarker> allMarkers = Set.from(_osmMarkers);

					// Remove old search markers
					int removedCount = 0;
					allMarkers.removeWhere((marker) {
					  bool shouldRemove = marker.markerId.startsWith('search_');
					  if (shouldRemove) {
						removedCount++;
						print('🔍 UPDATE MARKERS: OSM - Removing old search marker: ${marker.markerId}');
					  }
					  return shouldRemove;
					});
					
					print('🔍 UPDATE MARKERS: OSM - Removed ${removedCount} old search markers');

					// Add new search markers
					allMarkers.addAll(_osmSearchMarkers);

					print('🔍 UPDATE MARKERS: OSM - After: ${allMarkers.length} total markers');
					
					// Debug final markers
					print('🔍 UPDATE MARKERS: OSM - Final marker IDs:');
					for (final marker in allMarkers) {
					  print('  - ${marker.markerId} at ${marker.position}');
					}

					setState(() {
					  _osmMarkers = allMarkers;
					});
					
					print('🔍 UPDATE MARKERS: OSM - State updated with ${_osmMarkers.length} markers');
				  }
				  
				  print('🔍 UPDATE MARKERS DEBUG: Update completed');
				}

				 Future<void> _returnToTaskDetailWithLocation(gmaps.LatLng selectedLocation, String locationName) async {
				   if (_pendingTaskState == null) return;

				   // Clear search state
				   setState(() {
					 if (_currentMapProvider == MapProvider.googleMaps) {
					   _googleSearchMarkers.clear();
					 } else {
					   _osmSearchMarkers.clear();
					 }
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
						 await _focusOnNewLocation(UniversalLatLng.fromGoogleMaps(result['focusLocation'] as gmaps.LatLng));
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

					 if (!_isMapReady) {
					   print('Map not ready for initial focus');
					   return;
					 }

					 // Get current location using existing service
					 final position = await LocationService.getCurrentLocation();

					 if (position != null) {
					   final userLocation = UniversalLatLng(position.latitude, position.longitude);

					   // Update current location variable
					   _currentLocation = userLocation;

					   // HYBRID: Focus camera on user location
					   if (_currentMapProvider == MapProvider.googleMaps && _googleMapController != null) {
						 await _googleMapController!.animateCamera(
						   gmaps.CameraUpdate.newCameraPosition(
							 gmaps.CameraPosition(
							   target: userLocation.toGoogleMaps(),
							   zoom: 16.0,
							   bearing: 0,
							   tilt: 0,
							 ),
						   ),
						 );
					   } else if (_currentMapProvider == MapProvider.openStreetMap && _osmMapController != null) {
						 _osmMapController!.move(userLocation.toOpenStreetMap(), 16.0);
					   }

					   print('Initial camera focused on user location');

					 } else {
					   print('Could not get initial location, keeping default');
					 }

				   } catch (e) {
					 print('Error during initial location focus: $e');
				   }
				 }

				 // PUBLIC METHODS for MainNavigationScreen communication (HYBRID)
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
					UniversalLatLng searchCenter = UniversalLatLng(48.2082, 16.3738); // Default Vienna
					if (_currentLocation != null) {
					  searchCenter = _currentLocation!;
					}

					// HYBRID: Choose API based on current map provider
					if (_currentMapProvider == MapProvider.googleMaps) {
					  await _performGooglePlacesSearch(searchTerm, searchCenter);
					} else {
					  await _performNominatimSearch(searchTerm, searchCenter);
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

				 // HYBRID: Focus on task location
				 Future<void> _focusOnTaskLocation(TaskLocation task) async {
				   try {
					 final universalLocation = UniversalLatLng(task.latitude, task.longitude);
					 
					 if (_currentMapProvider == MapProvider.googleMaps && _googleMapController != null) {
					   await _googleMapController!.animateCamera(
						 gmaps.CameraUpdate.newCameraPosition(
						   gmaps.CameraPosition(
							 target: universalLocation.toGoogleMaps(),
							 zoom: 17.0,
							 bearing: 0,
							 tilt: 0,
						   ),
						 ),
					   );
					 } else if (_currentMapProvider == MapProvider.openStreetMap && _osmMapController != null) {
					   _osmMapController!.move(universalLocation.toOpenStreetMap(), 17.0);
					 }

					 // Send confirmation to user
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
				   } catch (e) {
					 // Silent fail in production
				   }
				 }

				 // PUBLIC wrapper for MainNavigationScreen communication (HYBRID)
				 Future<void> focusOnTaskLocation(TaskLocation task) async {
				   print('🗺️ MAP FOCUS DEBUG: Starting focus on task: ${task.title}');
				   print('🗺️ MAP FOCUS DEBUG: Task coordinates: ${task.latitude}, ${task.longitude}');
				   print('🗺️ MAP FOCUS DEBUG: Current provider: ${_currentMapProvider.name}');

				   try {
					 final universalLocation = UniversalLatLng(task.latitude, task.longitude);
					 bool hasController = (_currentMapProvider == MapProvider.googleMaps ? _googleMapController != null : _osmMapController != null);
					 
					 if (hasController && _isMapReady) {
					   // SET FLAG TO PREVENT AUTO FOCUS
					   _isManuallyFocusing = true;
					   print('🗺️ MAP FOCUS DEBUG: Set manual focusing flag = true');

					   print('🗺️ MAP FOCUS DEBUG: Animating camera to task location');

					   if (_currentMapProvider == MapProvider.googleMaps) {
						 await _googleMapController!.animateCamera(
						   gmaps.CameraUpdate.newCameraPosition(
							 gmaps.CameraPosition(
							   target: universalLocation.toGoogleMaps(),
							   zoom: 18.0,
							   bearing: 0,
							   tilt: 45.0,
							 ),
						   ),
						 );
					   } else {
						 _osmMapController!.move(universalLocation.toOpenStreetMap(), 18.0);
					   }

					   print('✅ MAP FOCUS DEBUG: Camera animation completed');

					   // Snackbar confirmation
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
							 duration: const Duration(seconds: 5), // Increased to 5 seconds
						   ),
						 );
					   }

					   // WAIT 5 SECONDS THEN REMOVE FLAG
					   Future.delayed(const Duration(seconds: 5), () {
						 print('🗺️ MAP FOCUS DEBUG: Clearing manual focusing flag');
						 _isManuallyFocusing = false;
					   });

					 } else {
					   print('❌ MAP FOCUS DEBUG: Map controller not ready!');
					 }
				   } catch (e) {
					 print('❌ MAP FOCUS DEBUG: Error during camera animation: $e');
					 _isManuallyFocusing = false; // Remove flag in case of error
				   }
				 }
				 
				 // Helper method to extract the best name from Nominatim result
					String _extractBestName(Map<String, dynamic> place) {
					  // Try different name fields in order of preference
					  if (place['namedetails'] != null) {
						final nameDetails = place['namedetails'];
						if (nameDetails['name:en'] != null) return nameDetails['name:en'];
						if (nameDetails['name'] != null) return nameDetails['name'];
					  }
					  
					  if (place['name'] != null && place['name'].toString().isNotEmpty) {
						return place['name'];
					  }
					  
					  // Fallback to first part of display_name
					  final displayName = place['display_name'] ?? '';
					  final parts = displayName.split(',');
					  return parts.isNotEmpty ? parts.first.trim() : 'Unknown Location';
					}

					// Helper method to create distance-based marker colors
					Widget _createDistanceMarker(double distanceInMeters) {
					  Color markerColor;
					  
					  if (distanceInMeters <= 500) {
						markerColor = Colors.green; // Very close
					  } else if (distanceInMeters <= 1000) {
						markerColor = Colors.orange; // Nearby
					  } else {
						markerColor = Colors.red; // Far
					  }
					  
					  return OSMConverter.createDefaultMarker(color: markerColor);
					}

				 @override
				 void dispose() {
				   WidgetsBinding.instance.removeObserver(this);
				   _pulseController.dispose();
				   _positionStream?.cancel();
				   super.dispose();
				 }
				 
				 // Google Places API search (existing functionality)
					Future<void> _performGooglePlacesSearch(String searchTerm, UniversalLatLng searchCenter) async {
					  final url = 'https://maps.googleapis.com/maps/api/place/nearbysearch/json'
						  '?location=${searchCenter.latitude},${searchCenter.longitude}'
						  '&radius=5000'
						  '&keyword=${Uri.encodeComponent(searchTerm)}'
						  '&key=$googleApiKey';

					  final response = await http.get(Uri.parse(url));

					  if (response.statusCode == 200) {
						final body = json.decode(response.body);
						final List results = body['results'];

						Set<gmaps.Marker> searchMarkers = {};

						for (final place in results) {
						  final lat = place['geometry']['location']['lat'];
						  final lng = place['geometry']['location']['lng'];
						  final name = place['name'];

						  searchMarkers.add(
							gmaps.Marker(
							  markerId: gmaps.MarkerId('search_${place['place_id']}'),
							  position: gmaps.LatLng(lat, lng),
							  icon: gmaps.BitmapDescriptor.defaultMarkerWithHue(gmaps.BitmapDescriptor.hueRed),
							  infoWindow: gmaps.InfoWindow(
								title: name,
								snippet: 'Tap to create task here',
							  ),
							  onTap: () async {
								setState(() {
								  _googleSearchMarkers.clear();
								});
								await _updateMapWithSearchResults();

								final result = await Navigator.push(
								  context,
								  MaterialPageRoute(
									builder: (ctx) => TaskInputScreen(
									  location: gmaps.LatLng(lat, lng),
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
						  _googleSearchMarkers = searchMarkers;
						});

						await _updateMapWithSearchResults();

						if (_googleMapController != null && results.isNotEmpty) {
						  _googleMapController!.animateCamera(
							gmaps.CameraUpdate.newLatLngZoom(searchCenter.toGoogleMaps(), 14),
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
					}

					// FIXED: Nominatim API search - back to viewbox approach with distance sorting
					Future<void> _performNominatimSearch(String searchTerm, UniversalLatLng searchCenter) async {
					  print('🔍 OSM SEARCH DEBUG: Starting search for "$searchTerm"');
					  print('🔍 OSM SEARCH DEBUG: Search center = ${searchCenter.latitude}, ${searchCenter.longitude}');
					  
					  // HYBRID APPROACH: Use viewbox (which worked before) + distance sorting (new feature)
					  // Create larger viewbox around Vienna/current location (approximately 20km radius)
					  final double radiusOffset = 0.2; // ~20km in degrees
					  final double minLon = searchCenter.longitude - radiusOffset;
					  final double maxLat = searchCenter.latitude + radiusOffset;
					  final double maxLon = searchCenter.longitude + radiusOffset;
					  final double minLat = searchCenter.latitude - radiusOffset;
					  
					  final url = 'https://nominatim.openstreetmap.org/search'
						  '?q=${Uri.encodeComponent(searchTerm)}'
						  '&format=json'
						  '&limit=20' // Get more results for distance sorting
						  '&addressdetails=1'
						  '&extratags=1'
						  '&namedetails=1'
						  // BACK TO VIEWBOX - this worked before!
						  '&viewbox=$minLon,$maxLat,$maxLon,$minLat'
						  '&bounded=1'; // Important: restrict to viewbox

					  print('🔍 OSM SEARCH DEBUG: Request URL = $url');
					  print('🔍 OSM SEARCH DEBUG: ViewBox = minLon:$minLon, maxLat:$maxLat, maxLon:$maxLon, minLat:$minLat');

					  final response = await http.get(
						Uri.parse(url),
						headers: {
						  'User-Agent': 'Locado/1.0 (Flutter App)', // Required by Nominatim
						},
					  );

					  print('🔍 OSM SEARCH DEBUG: Response status = ${response.statusCode}');

					  if (response.statusCode == 200) {
						final List rawResults = json.decode(response.body);
						print('🔍 OSM SEARCH DEBUG: Raw results count = ${rawResults.length}');

						if (rawResults.isEmpty) {
						  print('🔍 OSM SEARCH DEBUG: No results found within viewbox - trying broader search...');
						  
						  // FALLBACK: Try broader search without bounded restriction
						  final broadUrl = 'https://nominatim.openstreetmap.org/search'
							  '?q=${Uri.encodeComponent(searchTerm)}'
							  '&format=json'
							  '&limit=20'
							  '&addressdetails=1'
							  '&extratags=1'
							  '&namedetails=1'
							  '&viewbox=$minLon,$maxLat,$maxLon,$minLat'; // No bounded=1
							  
						  print('🔍 OSM SEARCH DEBUG: Fallback URL = $broadUrl');
						  
						  final fallbackResponse = await http.get(
							Uri.parse(broadUrl),
							headers: {'User-Agent': 'Locado/1.0 (Flutter App)'},
						  );
						  
						  if (fallbackResponse.statusCode == 200) {
							final List fallbackResults = json.decode(fallbackResponse.body);
							print('🔍 OSM SEARCH DEBUG: Fallback results count = ${fallbackResults.length}');
							
							if (fallbackResults.isNotEmpty) {
							  await _processDistanceAndCreateMarkers(fallbackResults, searchCenter, searchTerm);
							  return;
							}
						  }
						} else {
						  await _processDistanceAndCreateMarkers(rawResults, searchCenter, searchTerm);
						  return;
						}

						// If we get here, no results found at all
						ScaffoldMessenger.of(context).showSnackBar(
						  SnackBar(
							content: Text('No locations found for "$searchTerm" in this area'),
							backgroundColor: Colors.blue,
						  ),
						);

					  } else {
						print('🔍 OSM SEARCH DEBUG: HTTP Error ${response.statusCode}');
						ScaffoldMessenger.of(context).showSnackBar(
						  const SnackBar(
							content: Text('Failed to search locations'),
							backgroundColor: Colors.red,
						  ),
						);
					  }
					}

					// Helper method to process results and create markers
					Future<void> _processDistanceAndCreateMarkers(List rawResults, UniversalLatLng searchCenter, String searchTerm) async {
					  // Calculate distance for each result and create enriched list
					  List<Map<String, dynamic>> resultsWithDistance = [];
					  
					  for (int i = 0; i < rawResults.length; i++) {
						final place = rawResults[i];
						final lat = double.parse(place['lat']);
						final lng = double.parse(place['lon']);
						
						// Calculate distance from user location
						final distance = _calculateDistance(
						  searchCenter.latitude,
						  searchCenter.longitude,
						  lat,
						  lng,
						);
						
						resultsWithDistance.add({
						  'place': place,
						  'distance': distance,
						  'lat': lat,
						  'lng': lng,
						});
						
						if (i < 3) { // Debug first 3 results
						  print('🔍 OSM RESULT $i: ${place['display_name']} - Distance: ${distance.toStringAsFixed(0)}m');
						}
					  }

					  // Sort by distance (closest first)
					  resultsWithDistance.sort((a, b) => a['distance'].compareTo(b['distance']));
					  print('🔍 OSM SEARCH DEBUG: Sorted by distance, closest = ${resultsWithDistance.first['distance'].toStringAsFixed(0)}m');
					  
					  // Take only closest 10 results
					  final closestResults = resultsWithDistance.take(10).toList();
					  print('🔍 OSM SEARCH DEBUG: Taking closest ${closestResults.length} results');

					  Set<OSMMarker> searchMarkers = {};

					  for (int i = 0; i < closestResults.length; i++) {
						final item = closestResults[i];
						final place = item['place'];
						final lat = item['lat'] as double;
						final lng = item['lng'] as double;
						final distance = item['distance'] as double;
						
						// Extract better name from different fields
						String name = _extractBestName(place);
						final fullAddress = place['display_name'];
						
						// Format distance for display
						final distanceText = _formatDistance(distance);

						print('🔍 OSM MARKER $i: Creating marker for "$name" at $lat,$lng (${distanceText})');

						searchMarkers.add(
						  OSMMarker(
							markerId: 'search_${place['osm_id']}',
							position: ll.LatLng(lat, lng),
							title: '$name ($distanceText)',
							child: _createDistanceMarker(distance),
							onTap: () async {
							  print('🔍 OSM MARKER TAP: ${name}');
							  setState(() {
								_osmSearchMarkers.clear();
							  });
							  await _updateMapWithSearchResults();

							  final result = await Navigator.push(
								context,
								MaterialPageRoute(
								  builder: (ctx) => TaskInputScreen(
									location: gmaps.LatLng(lat, lng),
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

					  print('🔍 OSM SEARCH DEBUG: Created ${searchMarkers.length} search markers');
					  for (final marker in searchMarkers) {
						print('🔍 OSM MARKER: ${marker.markerId} at ${marker.position}');
					  }

					  setState(() {
						_osmSearchMarkers = searchMarkers;
					  });

					  print('🔍 OSM SEARCH DEBUG: Set state - _osmSearchMarkers.length = ${_osmSearchMarkers.length}');

					  await _updateMapWithSearchResults();

					  print('🔍 OSM SEARCH DEBUG: Called _updateMapWithSearchResults()');

					  if (_osmMapController != null && closestResults.isNotEmpty) {
						_osmMapController!.move(searchCenter.toOpenStreetMap(), 14);
						print('🔍 OSM SEARCH DEBUG: Moved map to search center with zoom 14');
					  } else {
						print('🔍 OSM SEARCH DEBUG: Map controller is null or no results');
					  }

					  ScaffoldMessenger.of(context).showSnackBar(
						SnackBar(
						  content: Text(
							closestResults.isEmpty
								? 'No locations found for "$searchTerm"'
								: 'Found ${closestResults.length} nearby locations',
						  ),
						  backgroundColor: closestResults.isEmpty ? Colors.blue : Colors.green,
						),
					  );

					  print('🔍 OSM SEARCH DEBUG: Search completed successfully');
					}
				 
				}