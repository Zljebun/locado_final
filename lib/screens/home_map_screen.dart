import 'dart:async';
import 'dart:math';
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
import '../services/onboarding_service.dart';
import 'package:locado_final/screens/task_input_screen.dart' show TaskInputScreenWithState;
// REMOVED: Provider and ThemeProvider - no more dark mode support
import 'ai_location_search_screen.dart';
import '../widgets/osm_map_widget.dart';
import '../services/task_location_cache.dart';

// REMOVED: MapProvider enum - OSM only now

// REMOVED: UniversalLatLng wrapper - using ll.LatLng directly

// REMOVED: UniversalMarker class - using OSMMarker directly

// HELPER CLASS for task distance calculations (unchanged)
class TaskWithDistance {
  final TaskLocation task;
  final double distance;

  TaskWithDistance(this.task, this.distance);
}

class HomeMapScreen extends StatefulWidget {
  final gmaps.LatLng? selectedLocation; // KEPT: For compatibility with MainNavigationScreen
  const HomeMapScreen({Key? key, this.selectedLocation}) : super(key: key);

  @override
  State<HomeMapScreen> createState() => _HomeMapScreenState();
}

class _HomeMapScreenState extends State<HomeMapScreen>
    with WidgetsBindingObserver, GeofencingScreenMixin {
    // REMOVED: TickerProviderStateMixin - no more animations

  // OpenStreetMap controllers and variables (now primary)
  osm.MapController? _osmMapController;
  Set<OSMMarker> _osmMarkers = {};

  // Simplified variables (OSM-focused)
  ll.LatLng? _currentLocation;
  bool _isLoading = true;
  int _notificationDistance = 100;
  final FlutterLocalNotificationsPlugin _flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

  // REMOVED: _nearbyTasks - no more pulsing animation
  List<TaskLocation> _savedLocations = [];
  // REMOVED: _pulseController - no more animations
  bool _isMapReady = false;
  static const platformLockScreen = MethodChannel('locado.lockscreen/channel');
  TaskLocation? _lastAddedTask;
  int _previousTaskCount = 0;

  // Smart geofencing variables
  bool _isAppInForeground = true;

  bool _autoFocusEnabled = true;
  StreamSubscription<Position>? _positionStream;
  bool _isTrackingLocation = false;

  // Search functionality variables (OSM only)
  Set<OSMMarker> _osmSearchMarkers = {};

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
    
    // SIMPLIFIED INITIALIZATION - No animations to setup
    _setupBasicUI();
    
    // Start simple initialization after UI is ready
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startSimpleInitialization();
    });
  }

  void _setupBasicUI() {
    // REMOVED: Animation controller setup - no more pulsing
    
    WidgetsBinding.instance.addObserver(this);
    LocadoBackgroundService.setGeofenceEventListener(_handleGeofenceEvent);
  }

  Future<void> _startSimpleInitialization() async {
    try {
      print('🚀 OSM-ONLY: Starting simple initialization...');
	  
	  await Future.delayed(Duration(milliseconds: 200));
      
      // Step 1: Load basic data quickly
      await _loadBasicData();
      
      // Step 2: Show the map with basic markers
      if (mounted) {
        setState(() {
          _isLoading = false; // Show map immediately
        });
      }
      
      // Step 3: Initialize remaining features in background
      _initializeBackgroundFeatures();
      
      print('✅ OSM-ONLY: Basic initialization completed');
      
    } catch (e) {
      print('❌ OSM-ONLY: Initialization error: $e');
      // Show empty map on error
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

	Future<void> _loadBasicData() async {
	  try {
		await Future.delayed(Duration(milliseconds: 50));
		
		// ✅ OPTIMIZED: Load locations from database (these are usually few)
		// and tasks from cache first, then refresh from database
		final locationsFuture = DatabaseHelper.instance.getAllLocations();
		
		// ✅ INSTANT: Load tasks from cache first
		print('🚀 MAP CACHE: Loading tasks from cache...');
		final cachedTasks = await TaskLocationCache.instance.getInstantTasks();
		
		// Load locations (usually small number, fast)
		final locations = await locationsFuture;
		
		if (cachedTasks.isNotEmpty) {
		  // ✅ INSTANT: Use cached tasks for immediate UI
		  _savedLocations = cachedTasks;
		  
		  await Future.delayed(Duration(milliseconds: 100));
		  
		  // Create markers with cached data
		  await _createBasicOSMMarkers(locations, cachedTasks);
		  
		  print('✅ MAP CACHE: Used cached data (${cachedTasks.length} tasks, ${locations.length} locations)');
		} else {
		  print('ℹ️ MAP CACHE: No cache available, loading from database...');
		  
		  // Fallback: Load from database if no cache
		  final taskLocations = await DatabaseHelper.instance.getAllTaskLocations();
		  _savedLocations = taskLocations;
		  
		  await Future.delayed(Duration(milliseconds: 100));
		  await _createBasicOSMMarkers(locations, taskLocations);
		  
		  // Update cache with fresh data
		  await TaskLocationCache.instance.updateCache(taskLocations);
		  
		  print('✅ MAP CACHE: Loaded from database (${taskLocations.length} tasks, ${locations.length} locations)');
		}
		
		// ✅ BACKGROUND: Refresh from database to ensure data is current
		Future.delayed(const Duration(milliseconds: 200), () async {
		  try {
			print('🔄 MAP CACHE: Refreshing from database in background...');
			final freshTasks = await DatabaseHelper.instance.getAllTaskLocations();
			
			// Check if data changed
			bool dataChanged = false;
			if (_savedLocations.length != freshTasks.length) {
			  dataChanged = true;
			} else {
			  // Check if any task IDs are different
			  final cachedIds = _savedLocations.map((t) => t.id).toSet();
			  final freshIds = freshTasks.map((t) => t.id).toSet();
			  dataChanged = !cachedIds.containsAll(freshIds) || !freshIds.containsAll(cachedIds);
			}
			
			if (dataChanged && mounted) {
			  _savedLocations = freshTasks;
			  await _createBasicOSMMarkers(locations, freshTasks);
			  
			  // Update cache
			  await TaskLocationCache.instance.updateCache(freshTasks);
			  
			  setState(() {
				// Trigger UI update with fresh data
			  });
			  
			  print('🔄 MAP CACHE: Updated with fresh data (${freshTasks.length} tasks)');
			} else {
			  print('✅ MAP CACHE: Cache is up to date');
			}
			
		  } catch (e) {
			print('❌ MAP CACHE: Error refreshing from database: $e');
		  }
		});
		
	  } catch (e) {
		print('❌ MAP CACHE: Error in _loadBasicData: $e');
	  }
	}

  // Create basic OSM markers without complex rendering
  Future<void> _createBasicOSMMarkers(List<Location> locations, List<TaskLocation> taskLocations) async {
    Set<OSMMarker> newMarkers = {};

    // Location markers - simple blue dots
    for (var location in locations) {
      newMarkers.add(
        OSMMarker(
          markerId: 'location_${location.id}',
          position: ll.LatLng(location.latitude!, location.longitude!),
          title: location.description ?? 'No Description',
          child: _createSimpleMarker(Colors.blue, Icons.place),
        ),
      );
    }

    // Task markers - simple colored dots (no custom Canvas rendering)
    for (var task in taskLocations) {
      final color = Color(int.parse(task.colorHex.replaceFirst('#', '0xff')));
      
      newMarkers.add(
        OSMMarker(
          markerId: 'task_${task.id}',
          position: ll.LatLng(task.latitude, task.longitude),
          title: task.title,
          child: _createSimpleMarker(color, Icons.location_on),
          onTap: () => _handleTaskTap(task),
        ),
      );
		  if (taskLocations.indexOf(task) % 5 == 0) {
		   await Future.delayed(Duration(milliseconds: 10));
		  }
    }

    // Add existing search markers
    newMarkers.addAll(_osmSearchMarkers);
	
	await Future.delayed(Duration(milliseconds: 50));

    // Don't call setState here - just set the variable
    _osmMarkers = newMarkers;
    
    print('✅ OSM-ONLY: Created ${newMarkers.length} basic markers');
  }

  // Create simple marker widget (much faster than Canvas rendering)
  Widget _createSimpleMarker(Color color, IconData icon) {
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 3,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Icon(
        icon,
        color: Colors.white,
        size: 16,
      ),
    );
  }

  void _initializeBackgroundFeatures() {
    // OPTIMIZED PHASE 3: Reduce blocking operations and increase delays
    print('🚀 PHASE 3: Starting optimized background features...');
    
    // TIER 1: Critical but fast operations (run immediately)
    final criticalTasks = [
      () async => await _loadSettings(),
      () async => await _initializePreviousTaskCount(),
    ];
    
    // TIER 2: Medium priority operations (delay 500ms)
    final mediumTasks = [
      () async => await _requestLocationPermission(),
      () async => await _requestNotificationPermission(), 
      () async => await _initializeNotifications(),
    ];
    
    // TIER 3: Low priority operations (delay 2s)
    final lowPriorityTasks = [
      () async => await _checkForTaskDetailFromNotification(),
      () async => await _checkBatteryOptimizationSmart(),
      () async => await _checkBatteryOptimizationForFAB(),
    ];
    
    // Execute critical tasks immediately
    _executeTasksSequentially(criticalTasks);
    
    // Execute medium tasks after 500ms
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) {
        _executeTasksSequentially(mediumTasks);
        _performInitialLocationFocus();
      }
    });
    
    // Execute low priority tasks after 2s
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        _executeTasksSequentially(lowPriorityTasks);
      }
    });
    
    // DELAY geofencing until much later (was 8s, now 10s)
    Future.delayed(const Duration(seconds: 10), () {
      if (mounted) {
        _initializeGeofencingDelayed();
      }
    });
    
    // Lowest priority tasks - delay even more
    Future.delayed(const Duration(seconds: 5), () {
      if (mounted) {
        DeleteTaskService.checkAndHandlePendingDeleteTask(context);
      }
    });
    
    print('✅ PHASE 3: Background features scheduling completed');
  }

  Future<void> _executeTasksSequentially(List<Future<void> Function()> tasks) async {
    for (int i = 0; i < tasks.length; i++) {
      try {
        // Execute task
        await tasks[i]();
        
        // INCREASED delay between tasks to keep UI even more responsive
        if (i < tasks.length - 1) {
          await Future.delayed(const Duration(milliseconds: 200)); // Was 100ms, now 200ms
        }
      } catch (e) {
        print('Background task $i failed: $e');
        // Continue with next task even if one fails
      }
      
      // Check if widget is still mounted
      if (!mounted) break;
    }
  }

  void _initializeGeofencingDelayed() {
    // FURTHER DELAYED geofencing initialization (was 8 seconds, now handled by caller)
    Future.delayed(const Duration(seconds: 2), () async { // Additional 2s delay
      if (!mounted) return;
      
      try {
        print('🎯 GEOFENCING: Starting delayed initialization...');
        
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
            await helper.initializeExistingTasks();
          }
        }

        print('✅ GEOFENCING: System fully initialized');

      } catch (e) {
        print('❌ GEOFENCING: Error: $e');
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
            // SIMPLIFIED: Convert Google LatLng to OSM LatLng if needed
            final focusLocation = result['focusLocation'];
            ll.LatLng osmLocation;
            if (focusLocation.runtimeType.toString().contains('LatLng')) {
              // Handle both Google and OSM LatLng types
              osmLocation = ll.LatLng(focusLocation.latitude, focusLocation.longitude);
            } else {
              osmLocation = focusLocation as ll.LatLng;
            }
            await _focusOnLocation(osmLocation);
          }
        } else if (result['action'] == 'openLocationSearchForEdit') {
          _pendingTaskState = result['taskState'];
          _isSearchingForTaskInput = true;
          setState(() {});
          
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

  Future<void> _checkBatteryOptimizationSmart() async {
    try {
      if (!_shouldShowBatteryWarning()) {
        return;
      }

      bool needsWhitelist = false;

      try {
        final result = await _geofenceChannel.invokeMethod('checkBatteryOptimization');
        final bool isWhitelisted = result['isWhitelisted'] ?? false;

        if (!isWhitelisted) {
          needsWhitelist = true;
        }

      } catch (e) {
        print('Battery optimization check failed: $e');
        return;
      }

      if (!needsWhitelist) {
        return;
      }

      if (!isGeofencingEnabled || _savedLocations.isEmpty) {
        return;
      }

      await Future.delayed(const Duration(seconds: 2));

      if (!mounted) return;

      _showBatteryOptimizationWarning();
      await _saveBatteryWarningShown();

    } catch (e) {
      print('Battery check error: $e');
    }
  }

  // Battery optimization check for FAB display
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
        _showBatteryFAB = !isWhitelisted && canRequest;
      });

    } catch (e) {
      setState(() => _isBatteryLoading = false);
      debugPrint('Error checking battery optimization for FAB: $e');
    }
  }

  Future<void> _requestBatteryOptimizationFromFAB() async {
    if (_isBatteryLoading) return;

    setState(() => _isBatteryLoading = true);

    try {
      await _geofenceChannel.invokeMethod('requestBatteryOptimizationWhitelist');

      setState(() {
        _showBatteryFAB = false;
      });

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
                        const Text(
                          'Why is this important?',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                        ),
                        const SizedBox(height: 16),

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

                      Expanded(
                        child: ElevatedButton(
                          onPressed: _isBatteryLoading ? null : () async {
                            Navigator.pop(context);
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
    if (_hasShownBatteryWarning) {
      return false;
    }

    final lastShown = _lastBatteryCheck;
    if (lastShown != null) {
      final daysSinceLastShown = DateTime.now().difference(lastShown).inDays;
      if (daysSinceLastShown < 3) {
        return false;
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

        await _navigateToTaskDetail(taskId, taskTitle);
      }
    } catch (e) {
      print('Error checking task detail from notification: $e');
    }
  }

  Future<void> _navigateToTaskDetail(String taskId, String taskTitle) async {
    try {
      final taskLocations = await DatabaseHelper.instance.getAllTaskLocations();
      final task = taskLocations.firstWhere(
            (task) => task.id.toString() == taskId,
        orElse: () => throw Exception('Task not found'),
      );

      final result = await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (ctx) => TaskDetailScreen(taskLocation: task),
        ),
      );

      if (result != null) {
        if (result == true) {
          await _loadSavedLocationsWithRefresh();
        } else if (result is Map && result['refresh'] == true) {
          await _loadSavedLocationsWithRefresh();
          if (result['focusLocation'] != null) {
            // Convert from Google Maps LatLng to OSM LatLng
            final focusLocation = result['focusLocation'];
            ll.LatLng osmLocation;
            
            if (focusLocation is gmaps.LatLng) {
              osmLocation = ll.LatLng(focusLocation.latitude, focusLocation.longitude);
            } else {
              osmLocation = ll.LatLng(focusLocation.latitude, focusLocation.longitude);
            }
            await _focusOnLocation(osmLocation);
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

  // REMOVED: createCustomMarker() - no more CPU-intensive Canvas rendering

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
    final locale = WidgetsBinding.instance.platformDispatcher.locale;
    final useImperialUnits = ['US', 'GB', 'MM'].contains(locale.countryCode);

    if (useImperialUnits) {
      final miles = distanceInMeters * 0.000621371;
      if (miles < 0.1) {
        final feet = distanceInMeters * 3.28084;
        return '${feet.round()} ft';
      } else {
        return '${miles.toStringAsFixed(1)} mi';
      }
    } else {
      if (distanceInMeters < 1000) {
        return '${distanceInMeters.round()} m';
      } else {
        final kilometers = distanceInMeters / 1000;
        return '${kilometers.toStringAsFixed(1)} km';
      }
    }
  }

  // SIMPLIFIED BUILD METHOD: OSM only, no dark mode, no animations
  @override
  Widget build(BuildContext context) {
    // REMOVED: All dark mode debugging prints
    print('🗺️ OSM-ONLY BUILD: Building OSM map');

    return Scaffold(
      body: Stack(
        children: [
          // OSM MAP WIDGET ONLY
          _buildOpenStreetMap(),

          // REMOVED: Pulse animation completely - no AnimatedBuilder, no _nearbyTasks

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

  // OPENSTREETMAP widget (now primary)
  Widget _buildOpenStreetMap() {
    // Convert Google Maps LatLng to OSM LatLng if needed
    ll.LatLng initialPosition = ll.LatLng(48.2082, 16.3738); // Default Vienna
    if (widget.selectedLocation != null) {
      initialPosition = ll.LatLng(widget.selectedLocation!.latitude, widget.selectedLocation!.longitude);
    }

    return OSMMapWidget(
      initialCameraPosition: OSMCameraPosition(
        target: initialPosition,
        zoom: 15.0,
      ),
      markers: _osmMarkers,
      onMapCreated: (controller) {
        _osmMapController = controller;
        _isMapReady = true;
        print('✅ OSM-ONLY: OSM Map controller ready');
      },
      myLocationEnabled: true,
      myLocationButtonEnabled: true,
		onLongPress: (ll.LatLng position) async {
		  // Convert OSM LatLng to Google Maps LatLng for TaskInputScreen compatibility
		  final gmapsLocation = gmaps.LatLng(position.latitude, position.longitude);
		  
		  final result = await Navigator.push(
			context,
			MaterialPageRoute(builder: (ctx) => TaskInputScreen(
			  location: gmapsLocation,
			)),
		  );
		  if (result == true) {
			await _loadSavedLocationsAndFocusNew(); // Will use cache first
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
          _centerCameraOnLocation(location);
        }
      },
    );
  }

  // REMAINING METHODS - simplified for OSM only
  
	Future<void> _loadSavedLocationsAndFocusNew() async {
	  print('🔄 MAP CACHE: _loadSavedLocationsAndFocusNew() called');
	  try {
		// ✅ OPTIMIZED: Load locations and use cache for tasks
		final locationsFuture = DatabaseHelper.instance.getAllLocations();
		final cachedTasks = await TaskLocationCache.instance.getInstantTasks();
		final locations = await locationsFuture;
		
		// Try to get fresh tasks to find new ones
		final freshTasks = await DatabaseHelper.instance.getAllTaskLocations();
		
		print('🔄 MAP CACHE: Loaded ${freshTasks.length} task locations');

		// Find new task (last in list)
		TaskLocation? newTask;
		if (freshTasks.isNotEmpty) {
		  if (_savedLocations.length < freshTasks.length) {
			newTask = freshTasks.last;
			_lastAddedTask = newTask;
			print('🔄 MAP CACHE: Found new task: ${newTask.title}');
		  }
		}

		_savedLocations = freshTasks;

		// ✅ CACHE SYNC: Update cache with fresh data (including new task)
		await TaskLocationCache.instance.updateCache(freshTasks);

		// Create OSM markers
		await _createOSMMarkersWithCustomStyling(locations, freshTasks);
		print('🔄 MAP CACHE: Created OSM markers');

		setState(() {
		  _isLoading = false;
		});
		
		print('🔄 MAP CACHE: setState() called');

		// FOCUS ON NEW LOCATION
		if (newTask != null) {
		  print('🔄 MAP CACHE: Focusing on new task: ${newTask.title}');
		  await _focusOnNewTask(newTask);
		}

		// Geofencing sync
		if (isGeofencingEnabled && _savedLocations.isNotEmpty) {
		  await syncTaskLocationsFromScreen(_savedLocations);
		}
	  } catch (e) {
		print('❌ MAP CACHE: Error in _loadSavedLocationsAndFocusNew: $e');
		setState(() {
		  _isLoading = false;
		});
	  }
	}

  // Create OSM markers with better styling
  Future<void> _createOSMMarkersWithCustomStyling(List<Location> locations, List<TaskLocation> taskLocations) async {
    Set<OSMMarker> newMarkers = {};

    // Location markers
    for (var location in locations) {
      newMarkers.add(
        OSMMarker(
          markerId: 'location_${location.id}',
          position: ll.LatLng(location.latitude!, location.longitude!),
          title: location.description ?? 'No Description',
          child: _createStyledMarker(Colors.blue, Icons.place, isLarge: false),
        ),
      );
    }

    // Task markers with colors
    for (var task in taskLocations) {
      final color = Color(int.parse(task.colorHex.replaceFirst('#', '0xff')));
      
      newMarkers.add(
        OSMMarker(
          markerId: 'task_${task.id}',
          position: ll.LatLng(task.latitude, task.longitude),
          title: task.title,
          child: _createStyledMarker(color, Icons.location_on, isLarge: true),
          onTap: () => _handleTaskTap(task),
        ),
      );
    }

    setState(() {
      _osmMarkers = newMarkers;
    });
  }

  // Create styled marker (better than simple markers)
  Widget _createStyledMarker(Color color, IconData icon, {bool isLarge = false}) {
    final size = isLarge ? 40.0 : 32.0;
    final iconSize = isLarge ? 20.0 : 16.0;
    
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 3),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Icon(
        icon,
        color: Colors.white,
        size: iconSize,
      ),
    );
  }

  Future<void> _focusOnNewTask(TaskLocation task) async {
    try {
      final newLocation = ll.LatLng(task.latitude, task.longitude);
      
      if (_osmMapController != null) {
        _osmMapController!.move(newLocation, 17.0);
        print('✅ OSM-ONLY: Focused on new task: ${task.title}');
      }
    } catch (e) {
      print('Error focusing on new task: $e');
    }
  }

  void _centerCameraOnLocation(ll.LatLng location) {
    if (_osmMapController != null) {
      _osmMapController!.move(location, 17.0);
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

  // OSM: Load saved locations with refresh
	Future<void> _loadSavedLocationsWithRefresh() async {
	  try {
		print('🔄 MAP CACHE: _loadSavedLocationsWithRefresh() called');
		
		// ✅ OPTIMIZED: Load locations and use cache for tasks first
		final locationsFuture = DatabaseHelper.instance.getAllLocations();
		
		// Try cache first for instant response
		final cachedTasks = await TaskLocationCache.instance.getInstantTasks();
		final locations = await locationsFuture;
		
		if (cachedTasks.isNotEmpty) {
		  // Use cached data for immediate UI update
		  _savedLocations = cachedTasks;
		  await _createOSMMarkersWithCustomStyling(locations, cachedTasks);
		  
		  setState(() {
			_isLoading = false;
		  });
		  
		  print('✅ MAP CACHE: Updated UI with cached data (${cachedTasks.length} tasks)');
		}
		
		// ✅ BACKGROUND: Refresh from database
		Future.delayed(const Duration(milliseconds: 100), () async {
		  try {
			final freshTasks = await DatabaseHelper.instance.getAllTaskLocations();
			
			// Check if data changed
			bool dataChanged = false;
			if (_savedLocations.length != freshTasks.length) {
			  dataChanged = true;
			} else {
			  final cachedIds = _savedLocations.map((t) => t.id).toSet();
			  final freshIds = freshTasks.map((t) => t.id).toSet();
			  dataChanged = !cachedIds.containsAll(freshIds) || !freshIds.containsAll(cachedIds);
			}
			
			if (dataChanged && mounted) {
			  _savedLocations = freshTasks;
			  await _createOSMMarkersWithCustomStyling(locations, freshTasks);
			  
			  // Update cache
			  await TaskLocationCache.instance.updateCache(freshTasks);
			  
			  setState(() {
				_isLoading = false;
			  });
			  
			  print('🔄 MAP CACHE: Updated with fresh data (${freshTasks.length} tasks)');
			} else {
			  print('✅ MAP CACHE: Cache is up to date');
			}
			
			// GEOFENCING AUTO-SYNC
			if (isGeofencingEnabled && _savedLocations.isNotEmpty) {
			  await syncTaskLocationsFromScreen(_savedLocations);
			}
			
		  } catch (e) {
			print('❌ MAP CACHE: Error refreshing: $e');
		  }
		});

	  } catch (e) {
		print('❌ MAP CACHE: Error in _loadSavedLocationsWithRefresh: $e');
		setState(() {
		  _isLoading = false;
		});
	  }
	}

  // OSM: Focus on updated task
  Future<void> _focusOnUpdatedTask(int taskId) async {
    try {
      final updatedTask = _savedLocations.firstWhere((task) => task.id == taskId);
      final location = ll.LatLng(updatedTask.latitude, updatedTask.longitude);

      if (_osmMapController != null) {
        _osmMapController!.move(location, 17.0);
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

  // OSM: Focus on location
  Future<void> _focusOnLocation(ll.LatLng location) async {
    try {
      if (_osmMapController != null) {
        _osmMapController!.move(location, 17.0);
      }
    } catch (e) {
      print('Error focusing on location: $e');
    }
  }

  // Sort tasks by distance from current location
  Future<List<TaskWithDistance>> _sortTasksByDistanceWithDetails(List<TaskLocation> tasks) async {
    print('🔍 SORT DEBUG: Starting sorting for ${tasks.length} tasks');

    final apiPosition = await LocationService.getCurrentLocation();
    print('🔍 SORT DEBUG: Fresh location = $apiPosition');

    if (apiPosition == null) {
      print('❌ SORT DEBUG: No fresh location! Returning all with 0.0 distance');
      return tasks.map((task) => TaskWithDistance(task, 0.0)).toList();
    }

    final currentPosition = ll.LatLng(apiPosition.latitude, apiPosition.longitude);
    print('✅ SORT DEBUG: Using fresh location (lat: ${currentPosition.latitude}, lng: ${currentPosition.longitude})');

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

    tasksWithDistance.sort((a, b) => a.distance.compareTo(b.distance));
    return tasksWithDistance;
  }

  void _showCalendar() async {
    try {
      final result = await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (ctx) => const CalendarScreen(),
        ),
      );

      if (result == true) {
        await _loadBasicData();
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

  Future<List<TaskLocation>> _sortTasksByDistance(List<TaskLocation> tasks) async {
    try {
      final currentPosition = await LocationService.getCurrentLocation();

      if (currentPosition == null) {
        return tasks;
      }

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

      tasksWithDistance.sort((a, b) => a.distance.compareTo(b.distance));
      return tasksWithDistance.map((twd) => twd.task).toList();

    } catch (e) {
      return tasks;
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

      const LocationSettings locationSettings = LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10,
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

  /// Handle location updates for auto focus (OSM)
  void _handleLocationUpdate(Position position) {
    if (_isManuallyFocusing) {
      print('⏸️ LOCATION UPDATE: Skipping because manually focusing on task');
      return;
    }

    print('🔍 LOCATION UPDATE: Received position = lat: ${position.latitude}, lng: ${position.longitude}');

    if (!_autoFocusEnabled || !_isMapReady) {
      print('❌ LOCATION UPDATE: Exiting due to conditions');
      return;
    }

    try {
      final newLocation = ll.LatLng(position.latitude, position.longitude);
      
      // Update map only if user has moved significantly
      if (_currentLocation == null ||
          _calculateDistance(
              _currentLocation!.latitude,
              _currentLocation!.longitude,
              newLocation.latitude,
              newLocation.longitude
          ) > 20) { // 20 meters threshold

        _currentLocation = newLocation;

        // OSM: Move camera to new location
        if (_osmMapController != null) {
          _osmMapController!.move(newLocation, 16.0);
        }

        print('✅ LOCATION UPDATE: Camera updated');
      }
    } catch (e) {
      print('❌ LOCATION UPDATE Error: $e');
    }
  }

  // OSM: Update map with search results
  Future<void> _updateMapWithSearchResults() async {
    print('🔍 UPDATE MARKERS DEBUG: Starting OSM markers update');
    
    print('🔍 UPDATE MARKERS: OSM - Before: ${_osmMarkers.length} markers');
    print('🔍 UPDATE MARKERS: OSM - Adding: ${_osmSearchMarkers.length} search markers');
    
    Set<OSMMarker> allMarkers = Set.from(_osmMarkers);

    // Remove old search markers
    int removedCount = 0;
    allMarkers.removeWhere((marker) {
      bool shouldRemove = marker.markerId.startsWith('search_');
      if (shouldRemove) removedCount++;
      return shouldRemove;
    });
    
    print('🔍 UPDATE MARKERS: OSM - Removed ${removedCount} old search markers');

    // Add new search markers
    allMarkers.addAll(_osmSearchMarkers);

    print('🔍 UPDATE MARKERS: OSM - After: ${allMarkers.length} total markers');

    setState(() {
      _osmMarkers = allMarkers;
    });
    
    print('🔍 UPDATE MARKERS: OSM - State updated');
  }

  // OSM: Focus on task location
  Future<void> focusOnTaskLocation(TaskLocation task) async {
    print('🗺️ MAP FOCUS DEBUG: Starting focus on task: ${task.title}');
    print('🗺️ MAP FOCUS DEBUG: Task coordinates: ${task.latitude}, ${task.longitude}');

    try {
      final location = ll.LatLng(task.latitude, task.longitude);
      
      if (_osmMapController != null && _isMapReady) {
        _isManuallyFocusing = true;
        print('🗺️ MAP FOCUS DEBUG: Set manual focusing flag = true');

        _osmMapController!.move(location, 18.0);

        print('✅ MAP FOCUS DEBUG: Camera moved to location');

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
              duration: const Duration(seconds: 5),
            ),
          );
        }

        // Clear flag after 5 seconds
        Future.delayed(const Duration(seconds: 5), () {
          print('🗺️ MAP FOCUS DEBUG: Clearing manual focusing flag');
          _isManuallyFocusing = false;
        });

      } else {
        print('❌ MAP FOCUS DEBUG: Map controller not ready!');
      }
    } catch (e) {
      print('❌ MAP FOCUS DEBUG: Error: $e');
      _isManuallyFocusing = false;
    }
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

      final position = await LocationService.getCurrentLocation();

      if (position != null) {
        final userLocation = ll.LatLng(position.latitude, position.longitude);
        _currentLocation = userLocation;

        if (_osmMapController != null) {
          _osmMapController!.move(userLocation, 16.0);
        }

        print('Initial camera focused on user location');
      }

    } catch (e) {
      print('Error during initial location focus: $e');
    }
  }

  // OSM search functionality
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
      ll.LatLng searchCenter = ll.LatLng(48.2082, 16.3738); // Default Vienna
      if (_currentLocation != null) {
        searchCenter = _currentLocation!;
      }

      await _performNominatimSearch(searchTerm, searchCenter);

    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Search error: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // Helper method to extract the best name from Nominatim result
  String _extractBestName(Map<String, dynamic> place) {
    if (place['namedetails'] != null) {
      final nameDetails = place['namedetails'];
      if (nameDetails['name:en'] != null) return nameDetails['name:en'];
      if (nameDetails['name'] != null) return nameDetails['name'];
    }
    
    if (place['name'] != null && place['name'].toString().isNotEmpty) {
      return place['name'];
    }
    
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
    
    return _createStyledMarker(markerColor, Icons.search, isLarge: false);
  }

  // REMOVED: Google Places API search - OSM only now uses Nominatim

  // Nominatim API search for OSM
  Future<void> _performNominatimSearch(String searchTerm, ll.LatLng searchCenter) async {
    print('🔍 OSM SEARCH DEBUG: Starting search for "$searchTerm"');
    print('🔍 OSM SEARCH DEBUG: Search center = ${searchCenter.latitude}, ${searchCenter.longitude}');
    
    // Create viewbox around search center (approximately 20km radius)
    final double radiusOffset = 0.2; // ~20km in degrees
    final double minLon = searchCenter.longitude - radiusOffset;
    final double maxLat = searchCenter.latitude + radiusOffset;
    final double maxLon = searchCenter.longitude + radiusOffset;
    final double minLat = searchCenter.latitude - radiusOffset;
    
    final url = 'https://nominatim.openstreetmap.org/search'
        '?q=${Uri.encodeComponent(searchTerm)}'
        '&format=json'
        '&limit=20'
        '&addressdetails=1'
        '&extratags=1'
        '&namedetails=1'
        '&viewbox=$minLon,$maxLat,$maxLon,$minLat'
        '&bounded=1';

    print('🔍 OSM SEARCH DEBUG: Request URL = $url');

    final response = await http.get(
      Uri.parse(url),
      headers: {
        'User-Agent': 'Locado/1.0 (Flutter App)',
      },
    );

    print('🔍 OSM SEARCH DEBUG: Response status = ${response.statusCode}');

    if (response.statusCode == 200) {
      final List rawResults = json.decode(response.body);
      print('🔍 OSM SEARCH DEBUG: Raw results count = ${rawResults.length}');

      if (rawResults.isEmpty) {
        print('🔍 OSM SEARCH DEBUG: No results found within viewbox - trying broader search...');
        
        // Fallback: Try broader search without bounded restriction
        final broadUrl = 'https://nominatim.openstreetmap.org/search'
            '?q=${Uri.encodeComponent(searchTerm)}'
            '&format=json'
            '&limit=20'
            '&addressdetails=1'
            '&extratags=1'
            '&namedetails=1'
            '&viewbox=$minLon,$maxLat,$maxLon,$minLat';
            
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
  Future<void> _processDistanceAndCreateMarkers(List rawResults, ll.LatLng searchCenter, String searchTerm) async {
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
					location: gmaps.LatLng(lat, lng), // Convert to Google Maps LatLng
					locationName: name,
				  ),
				),
			  );

			  if (result == true) {
				await _loadSavedLocationsAndFocusNew(); // Will use cache first
			  }
			},
		  ),
		);
    }

    print('🔍 OSM SEARCH DEBUG: Created ${searchMarkers.length} search markers');

    setState(() {
      _osmSearchMarkers = searchMarkers;
    });

    print('🔍 OSM SEARCH DEBUG: Set state - _osmSearchMarkers.length = ${_osmSearchMarkers.length}');

    await _updateMapWithSearchResults();

    if (_osmMapController != null && closestResults.isNotEmpty) {
      _osmMapController!.move(searchCenter, 14);
      print('🔍 OSM SEARCH DEBUG: Moved map to search center with zoom 14');
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

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // REMOVED: _pulseController.dispose() - no more animations
    _positionStream?.cancel();
    super.dispose();
  }
}