import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:locado_final/screens/home_map_screen.dart';
import 'package:locado_final/screens/ai_location_search_screen.dart';
import 'package:locado_final/screens/task_input_screen.dart';
import 'package:locado_final/screens/debug_screen.dart';
import 'package:locado_final/screens/task_detail_screen.dart';
import 'package:locado_final/screens/delete_task_confirmation_screen.dart';
import 'package:locado_final/screens/calendar_screen.dart';
import 'package:provider/provider.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'dart:io';
import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import '../helpers/database_helper.dart';
import '../models/task_location.dart';
import '../location_service.dart';
import 'dart:math';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import 'package:geolocator/geolocator.dart';
import 'package:app_settings/app_settings.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'dart:io';
import '../services/app_bootstrap_service.dart';
import '../services/task_location_cache.dart';


// Helper class for task distance calculations
class TaskWithDistance {
  final TaskLocation task;
  final double distance;

  TaskWithDistance(this.task, this.distance);
}

// Autocomplete suggestion model
class AutocompleteSuggestion {
  final String placeId;
  final String description;
  final String mainText;
  final String? secondaryText;

  AutocompleteSuggestion({
    required this.placeId,
    required this.description,
    required this.mainText,
    this.secondaryText,
  });

  factory AutocompleteSuggestion.fromJson(Map<String, dynamic> json) {
    final structuredFormatting = json['structured_formatting'] ?? {};
    return AutocompleteSuggestion(
      placeId: json['place_id'] ?? '',
      description: json['description'] ?? '',
      mainText: structuredFormatting['main_text'] ?? json['description'] ?? '',
      secondaryText: structuredFormatting['secondary_text'],
    );
  }
}

class MainNavigationScreen extends StatefulWidget {
  final LatLng? selectedLocation;

  const MainNavigationScreen({Key? key, this.selectedLocation}) : super(key: key);

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  String _currentMapProvider = 'Loading...';
  int _currentIndex = 0;

  // Search functionality
  TextEditingController _searchController = TextEditingController();
  bool _isSearching = false;

  // Reference to map screen for communication
  final GlobalKey _mapKey = GlobalKey();

  // Bulk selection state variables
  bool _isSelectionMode = false;
  Set<int> _selectedTaskIds = <int>{};
  bool _isDeleting = false;

  // Task data state - to prevent rebuilding during selection
  List<TaskLocation>? _cachedTasks;
  List<TaskWithDistance>? _cachedSortedTasks;
  bool _isLoadingTasks = true;
  bool _isLoadingDistance = false;

  // Autocomplete functionality
  List<AutocompleteSuggestion> _suggestions = [];
  bool _showSuggestions = false;
  bool _isLoadingSuggestions = false;
  Timer? _debounceTimer;
  FocusNode _searchFocusNode = FocusNode();
  static String get googleApiKey => dotenv.env['GOOGLE_MAPS_API_KEY_HTTP'] ?? '';

	@override
	void initState() {
	  super.initState();
	  print('🚀 MAIN NAV: Fast initialization starting...');
	  
	  // ✅ INSTANT UI SETUP - no blocking operations
	  _setupSearchListeners();
	  _loadMapProviderDisplayFast();
	  
	  // ✅ START BACKGROUND DATA LOADING - don't wait for completion
	  _startAsyncInitialization();
	  
	  print('🚀 MAIN NAV: initState completed instantly');
	}
	
	/// Start async initialization without blocking UI
	void _startAsyncInitialization() {
	  // Use postFrameCallback to ensure UI renders first
	  WidgetsBinding.instance.addPostFrameCallback((_) async {
		print('🔄 MAIN NAV: Starting background data loading...');
		
		// Small delay to let UI render completely
		await Future.delayed(const Duration(milliseconds: 100));
		
		// Load data in background
		_loadTaskDataAsync();
	  });
	}

	/// Fast, non-blocking map provider loading
	Future<void> _loadMapProviderDisplayFast() async {
	  try {
		// Use cached data from bootstrap if available
		if (context.mounted) {
		  final bootstrap = Provider.of<AppBootstrapService>(context, listen: false);
		  if (bootstrap.isFeatureReady('map')) {
			final mapProvider = bootstrap.getData<String>('mapProvider');
			if (mapProvider != null) {
			  setState(() {
				_currentMapProvider = mapProvider == 'openStreetMap' ? 'OpenStreetMap' : 'Google Maps';
			  });
			  print('🗺️ MAIN NAV: Used cached map provider: $_currentMapProvider');
			  return;
			}
		  }
		}
		
		// Fallback to preferences (should be fast)
		final prefs = await SharedPreferences.getInstance();
		await prefs.setBool('use_openstreetmap', true); // Force OSM
		
		setState(() {
		  _currentMapProvider = 'OpenStreetMap';
		});
		print('🗺️ MAIN NAV: Set default map provider: $_currentMapProvider');
	  } catch (e) {
		setState(() {
		  _currentMapProvider = 'OpenStreetMap';
		});
		print('⚠️ MAIN NAV: Error loading map provider, using default: $e');
	  }
	}

	/// Async task data loading - doesn't block UI
	Future<void> _loadTaskDataAsync() async {
	  print('🚀 CACHE: Starting optimized task data loading...');
	  
	  try {
		// Step 1: Show loading state briefly
		if (mounted) {
		  setState(() {
			_isLoadingTasks = true;
		  });
		}
		
		// Step 2: INSTANT - Load from cache first (1-5ms)
		print('🚀 CACHE: Loading tasks from cache...');
		final cachedTasks = await TaskLocationCache.instance.getInstantTasks();
		
		if (cachedTasks.isNotEmpty && mounted) {
		  // INSTANT UI UPDATE with cached data
		  _cachedTasks = cachedTasks;
		  _cachedSortedTasks = cachedTasks.map((task) => TaskWithDistance(task, 0.0)).toList();
		  
		  setState(() {
			_isLoadingTasks = false;
			_isLoadingDistance = false;
		  });
		  
		  print('🚀 CACHE: UI updated instantly with ${cachedTasks.length} cached tasks');
		  
		  // Start distance calculation for cached tasks in background
		  _calculateDistancesInBackground(cachedTasks);
		} else {
		  print('ℹ️ CACHE: No cache available, will load from database');
		}
		
		// Step 3: BACKGROUND - Refresh from database (don't block UI)
		Future.delayed(const Duration(milliseconds: 100), () async {
		  try {
			print('🔄 CACHE: Refreshing from database in background...');
			final freshTasks = await DatabaseHelper.instance.getAllTaskLocations();
			
			// Update cache with fresh data
			await TaskLocationCache.instance.updateCache(freshTasks);
			
			// Check if data changed
			bool dataChanged = false;
			if (_cachedTasks == null || _cachedTasks!.length != freshTasks.length) {
			  dataChanged = true;
			} else {
			  // Check if any task IDs are different
			  final cachedIds = _cachedTasks!.map((t) => t.id).toSet();
			  final freshIds = freshTasks.map((t) => t.id).toSet();
			  dataChanged = !cachedIds.containsAll(freshIds) || !freshIds.containsAll(cachedIds);
			}
			
			// Only update UI if data actually changed
			if (dataChanged && mounted) {
			  _cachedTasks = freshTasks;
			  _cachedSortedTasks = freshTasks.map((task) => TaskWithDistance(task, 0.0)).toList();
			  
			  setState(() {
				_isLoadingTasks = false;
				_isLoadingDistance = false;
			  });
			  
			  print('🔄 CACHE: UI updated with fresh data (${freshTasks.length} tasks)');
			  
			  // Recalculate distances with fresh data
			  if (freshTasks.isNotEmpty) {
				_calculateDistancesInBackground(freshTasks);
			  }
			} else {
			  print('✅ CACHE: No data changes, cache is up to date');
			}
			
		  } catch (e) {
			print('❌ CACHE: Error refreshing from database: $e');
			// Don't update UI on error - keep showing cached data
		  }
		});
		
	  } catch (e) {
		print('❌ CACHE: Error in optimized loading: $e');
		if (mounted) {
		  _cachedTasks = [];
		  _cachedSortedTasks = [];
		  setState(() {
			_isLoadingTasks = false;
			_isLoadingDistance = false;
		  });
		}
	  }
	}
	
	/// Update cache when new task is added
	Future<void> _syncCacheAfterTaskAdd(TaskLocation newTask) async {
	  try {
		await TaskLocationCache.instance.addTaskToCache(newTask);
		print('✅ CACHE: Added new task to cache: ${newTask.title}');
	  } catch (e) {
		print('❌ CACHE: Error adding task to cache: $e');
	  }
	}

	/// Update cache when task is deleted
	Future<void> _syncCacheAfterTaskDelete(int taskId) async {
	  try {
		await TaskLocationCache.instance.removeTaskFromCache(taskId);
		print('✅ CACHE: Removed task from cache: $taskId');
	  } catch (e) {
		print('❌ CACHE: Error removing task from cache: $e');
	  }
	}

	/// Update cache when task is modified
	Future<void> _syncCacheAfterTaskUpdate(TaskLocation updatedTask) async {
	  try {
		await TaskLocationCache.instance.updateTaskInCache(updatedTask);
		print('✅ CACHE: Updated task in cache: ${updatedTask.title}');
	  } catch (e) {
		print('❌ CACHE: Error updating task in cache: $e');
	  }
	}

	/// Calculate distances in background without blocking UI
	Future<void> _calculateDistancesInBackground(List<TaskLocation> tasks) async {
	  print('🔄 MAIN NAV ASYNC: Starting background distance calculation...');
	  
	  try {
		// Show loading indicator for distances
		if (mounted) {
		  setState(() {
			_isLoadingDistance = true;
		  });
		}
		
		// Small delay to let UI update
		await Future.delayed(const Duration(milliseconds: 100));
		
		// Get location - use bootstrap cached location if available
		Position? position;
		
		// Try to get cached location from bootstrap first
		if (context.mounted) {
		  final bootstrap = Provider.of<AppBootstrapService>(context, listen: false);
		  final cachedLocation = bootstrap.getData<Map<String, dynamic>>('currentLocation');
		  if (cachedLocation != null) {
			position = Position(
			  latitude: cachedLocation['latitude'],
			  longitude: cachedLocation['longitude'],
			  timestamp: DateTime.now(),
			  accuracy: cachedLocation['accuracy'] ?? 0.0,
			  altitude: 0.0,
			  heading: 0.0,
			  speed: 0.0,
			  speedAccuracy: 0.0,
			  altitudeAccuracy: 0.0,
			  headingAccuracy: 0.0,
			);
			print('🔄 MAIN NAV ASYNC: Using cached location from bootstrap');
		  }
		}
		
		// If no cached location, try to get current location (with timeout)
		if (position == null) {
		  print('🔄 MAIN NAV ASYNC: Getting fresh location...');
		  try {
			position = await LocationService.getCurrentLocation()
				.timeout(const Duration(seconds: 5)); // Short timeout
		  } catch (e) {
			print('⚠️ MAIN NAV ASYNC: Location timeout, using fallback: $e');
			// Use Vienna coordinates as fallback
			position = Position(
			  latitude: 48.2082,
			  longitude: 16.3738,
			  timestamp: DateTime.now(),
			  accuracy: 0.0,
			  altitude: 0.0,
			  heading: 0.0,
			  speed: 0.0,
			  speedAccuracy: 0.0,
			  altitudeAccuracy: 0.0,
			  headingAccuracy: 0.0,
			);
		  }
		}
		
		// Calculate distances
		if (position != null) {
		  final tasksWithDistance = _calculateDistancesSync(tasks, position);
		  
		  // Update UI with sorted tasks
		  if (mounted) {
			_cachedSortedTasks = tasksWithDistance;
			setState(() {
			  _isLoadingDistance = false;
			});
			print('🔄 MAIN NAV ASYNC: Distance calculation completed');
		  }
		}
		
	  } catch (e) {
		print('❌ MAIN NAV ASYNC: Error in distance calculation: $e');
		if (mounted) {
		  setState(() {
			_isLoadingDistance = false;
		  });
		}
	  }
	}

	/// Synchronous distance calculation (no async operations)
	List<TaskWithDistance> _calculateDistancesSync(List<TaskLocation> tasks, Position position) {
	  final tasksWithDistance = <TaskWithDistance>[];
	  
	  for (final task in tasks) {
		try {
		  final distance = _calculateDistance(
			position.latitude,
			position.longitude,
			task.latitude,
			task.longitude,
		  );
		  tasksWithDistance.add(TaskWithDistance(task, distance));
		} catch (e) {
		  print('❌ Distance calc error for ${task.title}: $e');
		  tasksWithDistance.add(TaskWithDistance(task, 999999.0));
		}
	  }
	  
	  // Sort by distance
	  tasksWithDistance.sort((a, b) => a.distance.compareTo(b.distance));
	  
	  return tasksWithDistance;
	}

	  @override
	  void dispose() {
		_searchController.dispose();
		_searchFocusNode.dispose();
		_debounceTimer?.cancel();
		super.dispose();
	  }
  
	  void _testTaskListRefresh() {
	  print('🧪 TEST: Manual task list refresh test');
	  ScaffoldMessenger.of(context).showSnackBar(
		const SnackBar(
		  content: Text('Refreshing task list...'),
		  duration: Duration(seconds: 1),
		),
	  );
	  _loadTaskData();
	}

	Future<void> _loadTaskData() async {
	  print('🔄 MAIN NAV: _loadTaskData called - delegating to async loader');
	  await _loadTaskDataAsync();
	}

  // Setup search field listeners for autocomplete
  void _setupSearchListeners() {
    _searchController.addListener(_onSearchChanged);
    _searchFocusNode.addListener(_onFocusChanged);
  }

// Handle search text changes with debounce
  void _onSearchChanged() {
    final query = _searchController.text.trim();

    // Cancel previous timer
    _debounceTimer?.cancel();

    if (query.isEmpty) {
      setState(() {
        _suggestions.clear();
        _showSuggestions = false;
        _isLoadingSuggestions = false;
      });
      return;
    }

    // Show loading state immediately
    if (!_isLoadingSuggestions) {
      setState(() {
        _isLoadingSuggestions = true;
        _showSuggestions = true;
      });
    }

    // Debounce the API call
    _debounceTimer = Timer(const Duration(milliseconds: 300), () {
      _fetchAutocompleteSuggestions(query);
    });
  }

// Handle focus changes
  void _onFocusChanged() {
    if (!_searchFocusNode.hasFocus && _suggestions.isEmpty) {
      setState(() {
        _showSuggestions = false;
      });
    } else if (_searchFocusNode.hasFocus && _searchController.text.isNotEmpty) {
      setState(() {
        _showSuggestions = true;
      });
    }
  }

// Fetch autocomplete suggestions from Google Places API
	Future<void> _fetchAutocompleteSuggestions(String query) async {
	  if (query.isEmpty) return;

	  print('🔍 FETCH: Starting hybrid search for: $query');

	  try {
		// Get current user location for bias
		LatLng? userLocation;
		final position = await LocationService.getCurrentLocation();
		if (position != null) {
		  userLocation = LatLng(position.latitude, position.longitude);
		}

		// Check current map provider
		final prefs = await SharedPreferences.getInstance();
		final useOSM = prefs.getBool('use_openstreetmap') ?? false;

		print('🔍 FETCH: Using ${useOSM ? 'OSM' : 'Google'} suggestions API');

		if (useOSM) {
		  await _fetchNominatimSuggestions(query, userLocation);
		} else {
		  await _fetchGooglePlacesSuggestions(query, userLocation);
		}

	  } catch (e) {
		print('❌ FETCH: Exception: $e');
		if (mounted) {
		  setState(() {
			_suggestions.clear();
			_isLoadingSuggestions = false;
			_showSuggestions = false;
		  });
		}
	  }
	}

// Handle suggestion selection
	Future<void> _onSuggestionSelected(AutocompleteSuggestion suggestion) async {
	  // Hide suggestions and clear focus
	  setState(() {
		_showSuggestions = false;
		_suggestions.clear();
		_isLoadingSuggestions = false;
	  });

	  _searchFocusNode.unfocus();

	  // Update search field with selected text
	  _searchController.text = suggestion.mainText;

	  // Check if this is OSM or Google suggestion and handle accordingly
	  if (suggestion.placeId.startsWith('osm_')) {
		await _handleOSMSuggestionSelection(suggestion);
	  } else {
		await _getPlaceDetailsAndSearch(suggestion.placeId);
	  }
	}

// Get detailed place information and trigger map search
  Future<void> _getPlaceDetailsAndSearch(String placeId) async {
    setState(() {
      _isSearching = true;
    });

    try {
      final url = 'https://maps.googleapis.com/maps/api/place/details/json'
          '?place_id=$placeId'
          '&fields=name,geometry,formatted_address'
          '&key=$googleApiKey';

      final response = await http.get(Uri.parse(url));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final result = data['result'];

        if (result != null && result['geometry'] != null) {
          final location = result['geometry']['location'];
          final lat = location['lat'];
          final lng = location['lng'];
          final name = result['name'] ?? _searchController.text;

          // Trigger map search with specific location
          final mapState = _mapKey.currentState as dynamic;
          if (mapState != null) {
            await mapState.performSearch(_searchController.text);
          }

          // Show success message
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.location_on, color: Colors.white),
                  const SizedBox(width: 8),
                  Expanded(child: Text('Found: $name')),
                ],
              ),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 2),
            ),
          );
        }
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error finding location: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }

    if (mounted) {
      setState(() {
        _isSearching = false;
      });
    }
  }

  // Get current page widget based on selected tab
	  Widget _getCurrentPage() {
		switch (_currentIndex) {
		  case 0:
			return HomeMapScreen(
			  key: _mapKey,
			  selectedLocation: widget.selectedLocation,
			);
		case 1:
		  return AILocationSearchScreen(
			onTasksCreated: () {
			  print('🔄 AI SEARCH: Tasks created callback triggered');
			  
			  setState(() {
				_currentIndex = 0; // Switch to map tab
			  });
			  
			  // Reload task data when new tasks are created (will use cache first)
			  Future.delayed(const Duration(milliseconds: 100), () {
				if (mounted) {
				  print('🔄 AI SEARCH: Reloading task data after AI task creation');
				  _loadTaskData(); // Will use optimized cache loading
				}
			  });
			},
		  );
		  case 2:
			return _buildTaskListPage();
		  case 3:
			return const CalendarScreen();
		  case 4:
			return _buildMorePage();
		  default:
			return HomeMapScreen(
			  key: _mapKey,
			  selectedLocation: widget.selectedLocation,
			);
		}
	  }

  // Calculate distance between two points
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


	// Sort tasks by distance with details - optimized for Huawei devices
	Future<List<TaskWithDistance>> _sortTasksByDistanceWithDetails(List<TaskLocation> tasks) async {
	 print('🔄 DISTANCE: Starting distance calculation for ${tasks.length} tasks');
	 
	 try {
	   // Check location permission before accessing location
	   final locationPermission = await Permission.locationWhenInUse.status;
	   if (!locationPermission.isGranted) {
		 print('❌ DISTANCE: Location permission not granted');
		 final result = await Permission.locationWhenInUse.request();
		 if (!result.isGranted) {
		   print('❌ DISTANCE: Location permission denied by user');
		   return tasks.map((task) => TaskWithDistance(task, 0.0)).toList();
		 }
	   }

	   print('🔄 DISTANCE: Getting current location...');
	   
	   // Add timeout and retry logic for Huawei devices
	   Position? position;
	   int retryCount = 0;
	   const maxRetries = 3;
	   
	   while (position == null && retryCount < maxRetries) {
		 try {
		   position = await LocationService.getCurrentLocation()
			   .timeout(const Duration(seconds: 10));
		   
		   if (position != null) {
			 print('🔄 DISTANCE: Got location on attempt ${retryCount + 1}: ${position.latitude}, ${position.longitude}');
			 break;
		   }
		 } on TimeoutException {
		   retryCount++;
		   print('❌ DISTANCE: Timeout on attempt $retryCount/$maxRetries');
		   if (retryCount < maxRetries) {
			 print('🔄 DISTANCE: Retrying in 2 seconds...');
			 await Future.delayed(const Duration(seconds: 2));
		   }
		 } catch (e) {
		   retryCount++;
		   print('❌ DISTANCE: Error on attempt $retryCount/$maxRetries: $e');
		   if (retryCount < maxRetries) {
			 print('🔄 DISTANCE: Retrying in 2 seconds...');
			 await Future.delayed(const Duration(seconds: 2));
		   }
		 }
	   }

	   // If no location after all attempts
	   if (position == null) {
		 print('❌ DISTANCE: Failed to get location after $maxRetries attempts');
		 
		 // Fallback: use default Vienna coordinates or last known location
		 try {
		   final prefs = await SharedPreferences.getInstance();
		   final lastLat = prefs.getDouble('last_known_latitude');
		   final lastLng = prefs.getDouble('last_known_longitude');
		   
		   if (lastLat != null && lastLng != null) {
			 print('🔄 DISTANCE: Using last known location: $lastLat, $lastLng');
			 position = Position(
			   latitude: lastLat,
			   longitude: lastLng,
			   timestamp: DateTime.now(),
			   accuracy: 0.0,
			   altitude: 0.0,
			   heading: 0.0,
			   speed: 0.0,
			   speedAccuracy: 0.0,
			   altitudeAccuracy: 0.0,
			   headingAccuracy: 0.0,
			 );
		   } else {
			 print('🔄 DISTANCE: Using default Vienna coordinates');
			 position = Position(
			   latitude: 48.2082,
			   longitude: 16.3738,
			   timestamp: DateTime.now(),
			   accuracy: 0.0,
			   altitude: 0.0,
			   heading: 0.0,
			   speed: 0.0,
			   speedAccuracy: 0.0,
			   altitudeAccuracy: 0.0,
			   headingAccuracy: 0.0,
			 );
		   }
		 } catch (e) {
		   print('❌ DISTANCE: Error accessing SharedPreferences: $e');
		   // Return tasks without distance sorting
		   return tasks.map((task) => TaskWithDistance(task, 0.0)).toList();
		 }
	   } else {
		 // Save current location for future fallback
		 try {
		   final prefs = await SharedPreferences.getInstance();
		   await prefs.setDouble('last_known_latitude', position.latitude);
		   await prefs.setDouble('last_known_longitude', position.longitude);
		   print('🔄 DISTANCE: Saved current location as last known');
		 } catch (e) {
		   print('❌ DISTANCE: Failed to save last known location: $e');
		 }
	   }

	   print('🔄 DISTANCE: Calculating distances from ${position.latitude}, ${position.longitude}');
	   
	   List<TaskWithDistance> tasksWithDistance = [];

	   for (int i = 0; i < tasks.length; i++) {
		 final task = tasks[i];
		 try {
		   final distance = _calculateDistance(
			 position.latitude,
			 position.longitude,
			 task.latitude,
			 task.longitude,
		   );
		   
		   tasksWithDistance.add(TaskWithDistance(task, distance));
		   
		   // Debug first few tasks
		   if (i < 3) {
			 print('🔄 DISTANCE: Task "${task.title}": ${_formatDistance(distance)}');
		   }
		   
		 } catch (e) {
		   print('❌ DISTANCE: Error calculating distance for task "${task.title}": $e');
		   tasksWithDistance.add(TaskWithDistance(task, 999999.0)); // Put at end
		 }
	   }

	   // Sort by distance
	   tasksWithDistance.sort((a, b) => a.distance.compareTo(b.distance));
	   
	   print('🔄 DISTANCE: Successfully sorted ${tasksWithDistance.length} tasks by distance');
	   
	   // Debug first few sorted tasks
	   for (int i = 0; i < tasksWithDistance.length && i < 3; i++) {
		 final twd = tasksWithDistance[i];
		 print('🔄 DISTANCE: Sorted #${i + 1}: "${twd.task.title}" - ${_formatDistance(twd.distance)}');
	   }
	   
	   return tasksWithDistance;

	 } catch (e) {
	   print('❌ DISTANCE: Unexpected error in _sortTasksByDistanceWithDetails: $e');
	   print('❌ DISTANCE: Stack trace: ${StackTrace.current}');
	   
	   // Fallback: return tasks without sorting
	   return tasks.map((task) => TaskWithDistance(task, 0.0)).toList();
	 }
	}

  // Toggle selection mode - optimized to avoid unnecessary rebuilds
  void _toggleSelectionMode() {
    setState(() {
      _isSelectionMode = !_isSelectionMode;
      if (!_isSelectionMode) {
        _selectedTaskIds.clear();
      }
    });
  }

// Toggle task selection - optimized for smooth UX
  void _toggleTaskSelection(int taskId) {
    // Update selection state without triggering full rebuild
    if (_selectedTaskIds.contains(taskId)) {
      _selectedTaskIds.remove(taskId);
    } else {
      _selectedTaskIds.add(taskId);
    }

    // Only update UI, don't reload data
    setState(() {
      // This setState only triggers UI update for checkboxes and selection count
      // It does NOT trigger data reload because we're using cached data
    });
  }

// Select all tasks - optimized
  void _selectAllTasks(List<TaskWithDistance> tasks) {
    setState(() {
      if (_selectedTaskIds.length == tasks.length) {
        // If all are selected, deselect all
        _selectedTaskIds.clear();
      } else {
        // Select all tasks (filter out null IDs)
        _selectedTaskIds = tasks
            .where((twd) => twd.task.id != null)
            .map((twd) => twd.task.id!)
            .toSet();
      }
    });
  }

  // Delete selected tasks - with cache refresh
	Future<void> _deleteSelectedTasks() async {
	  if (_selectedTaskIds.isEmpty) return;

	  final selectedCount = _selectedTaskIds.length;

	  // Show confirmation dialog
	  final confirmed = await showDialog<bool>(
		context: context,
		builder: (context) => AlertDialog(
		  title: const Text('Delete Selected Tasks'),
		  content: Text(
			  'Are you sure you want to delete $selectedCount selected task${selectedCount > 1 ? 's' : ''}?'
		  ),
		  actions: [
			TextButton(
			  onPressed: () => Navigator.pop(context, false),
			  child: const Text('Cancel'),
			),
			ElevatedButton(
			  onPressed: () => Navigator.pop(context, true),
			  style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
			  child: const Text('Delete', style: TextStyle(color: Colors.white)),
			),
		  ],
		),
	  );

	  if (confirmed != true) return;

	  setState(() {
		_isDeleting = true;
	  });

	  try {
		// Delete all selected tasks from database AND cache
		for (final taskId in _selectedTaskIds) {
		  await DatabaseHelper.instance.deleteTaskLocation(taskId);
		  await _syncCacheAfterTaskDelete(taskId); // CACHE SYNC
		}

		// Show success message
		ScaffoldMessenger.of(context).showSnackBar(
		  SnackBar(
			content: Text('$selectedCount task${selectedCount > 1 ? 's' : ''} deleted successfully'),
			backgroundColor: Colors.green,
		  ),
		);

		// Exit selection mode and refresh data
		setState(() {
		  _isSelectionMode = false;
		  _selectedTaskIds.clear();
		  _isDeleting = false;
		});

		// Reload task data after deletion (will use cache first)
		await _loadTaskData();

	  } catch (e) {
		// Show error message
		ScaffoldMessenger.of(context).showSnackBar(
		  SnackBar(
			content: Text('Error deleting tasks: $e'),
			backgroundColor: Colors.red,
		  ),
		);

		setState(() {
		  _isDeleting = false;
		});
	  }
	}

	Widget _buildTaskListPage() {

	  return Scaffold(
		appBar: AppBar(
		  title: Text(_isSelectionMode
			  ? '${_selectedTaskIds.length} Selected'
			  : 'All Tasks'
		  ),
		  backgroundColor: Colors.teal,
		  foregroundColor: Colors.white,
		  automaticallyImplyLeading: false,
		  actions: [
			if (_isSelectionMode) ...[
			  if (_isDeleting)
				const Padding(
				  padding: EdgeInsets.all(16.0),
				  child: SizedBox(
					width: 20,
					height: 20,
					child: CircularProgressIndicator(
					  strokeWidth: 2,
					  color: Colors.white,
					),
				  ),
				)
			  else
				IconButton(
				  icon: const Icon(Icons.delete),
				  onPressed: _selectedTaskIds.isEmpty ? null : _deleteSelectedTasks,
				),
			  IconButton(
				icon: const Icon(Icons.close),
				onPressed: _toggleSelectionMode,
			  ),
			] else ...[
			  IconButton(
				icon: const Icon(Icons.refresh),
				onPressed: () {
				  print('🔄 TASKS LIST: Manual refresh button pressed');
				  _loadTaskData();
				},
				tooltip: 'Refresh Tasks',
			  ),
			  IconButton(
				icon: const Icon(Icons.checklist),
				onPressed: _toggleSelectionMode,
			  ),
			],
		  ],
		),
		body: _buildTaskListBody(),
	  );
	}

  Widget _buildTaskListBody() {
    // Show loading indicator
    if (_isLoadingTasks) {
      return const Center(child: CircularProgressIndicator());
    }

    // Show empty state
    if (_cachedTasks == null || _cachedTasks!.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.task_alt,
              size: 64,
              color: Colors.grey.shade400,
            ),
            const SizedBox(height: 16),
            Text(
              'No tasks found',
              style: TextStyle(
                fontSize: 18,
                color: Colors.grey.shade600,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Add your first task using the + button',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey.shade500,
              ),
            ),
          ],
        ),
      );
    }

    // Show loading for distance calculation
    if (_isLoadingDistance || _cachedSortedTasks == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final sortedTasksWithDistance = _cachedSortedTasks!;

    return Column(
      children: [
        // Task count header
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.teal.shade50,
            border: Border(
              bottom: BorderSide(color: Colors.teal.shade100, width: 1),
            ),
          ),
          child: Row(
            children: [
              Icon(Icons.task_alt, color: Colors.teal.shade600, size: 20),
              const SizedBox(width: 8),
              Text(
                '${sortedTasksWithDistance.length} Task${sortedTasksWithDistance.length != 1 ? 's' : ''}',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.teal.shade700,
                ),
              ),
              const Spacer(),
              if (_isSelectionMode && sortedTasksWithDistance.isNotEmpty)
                TextButton.icon(
                  onPressed: () => _selectAllTasks(sortedTasksWithDistance),
                  icon: Icon(
                    _selectedTaskIds.length == sortedTasksWithDistance.length
                        ? Icons.deselect
                        : Icons.select_all,
                    size: 16,
                    color: Colors.teal.shade600,
                  ),
                  label: Text(
                    _selectedTaskIds.length == sortedTasksWithDistance.length
                        ? 'Deselect All'
                        : 'Select All',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.teal.shade600,
                    ),
                  ),
                ),
            ],
          ),
        ),

        // Tips banner (only show when not in selection mode)
        if (!_isSelectionMode)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.teal.shade50,
              border: Border(
                bottom: BorderSide(color: Colors.teal.shade100, width: 1),
              ),
            ),
            child: Row(
              children: [
                Icon(Icons.lightbulb_outline, color: Colors.teal.shade600, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Tap to open • Long press to delete • Tap colored circle to focus on map',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.teal.shade600,
                    ),
                  ),
                ),
              ],
            ),
          ),

        // Task list
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: sortedTasksWithDistance.length,
            separatorBuilder: (context, index) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final taskWithDistance = sortedTasksWithDistance[index];
              final task = taskWithDistance.task;
              final color = Color(int.parse(task.colorHex.replaceFirst('#', '0xff')));
              final isSelected = task.id != null && _selectedTaskIds.contains(task.id!);

              return Container(
                decoration: BoxDecoration(
                  color: isSelected
                      ? Colors.teal.shade50
                      : Theme.of(context).cardColor,
                  borderRadius: BorderRadius.circular(12),
                  border: isSelected
                      ? Border.all(color: Colors.teal, width: 2)
                      : null,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.grey.shade200,
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () {
                      if (_isSelectionMode) {
                        if (task.id != null) {
                          _toggleTaskSelection(task.id!);
                        }
                      } else {
                        _openTaskDetail(task);
                      }
                    },
                    onLongPress: () {
                      if (!_isSelectionMode) {
                        _deleteTask(task);
                      }
                    },
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          // Checkbox (only show in selection mode)
                          if (_isSelectionMode) ...[
                            Checkbox(
                              value: isSelected,
                              onChanged: (value) {
                                if (task.id != null) {
                                  _toggleTaskSelection(task.id!);
                                }
                              },
                              activeColor: Colors.teal,
                            ),
                            const SizedBox(width: 8),
                          ],

                          // Color circle - focus on map when tapped (not in selection mode)
                          GestureDetector(
                            onTap: _isSelectionMode ? null : () => _focusOnTask(task),
                            child: Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: color,
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: color.withOpacity(0.3),
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
                            ),
                          ),

                          const SizedBox(width: 16),

                          // Task info
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  task.title,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 16,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    Icon(
                                      Icons.checklist,
                                      size: 14,
                                      color: Colors.grey.shade500,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      '${task.taskItems.length} items',
                                      style: TextStyle(
                                        color: Colors.grey.shade600,
                                        fontSize: 14,
                                      ),
                                    ),

                                    // Show distance
                                    const SizedBox(width: 16),
                                    Icon(
                                      Icons.location_on,
                                      size: 14,
                                      color: Colors.grey.shade500,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      _formatDistance(taskWithDistance.distance),
                                      style: TextStyle(
                                        color: Colors.grey.shade600,
                                        fontSize: 14,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),

                          // Arrow icon (only show when not in selection mode)
                          if (!_isSelectionMode)
                            Icon(
                              Icons.arrow_forward_ios,
                              color: Colors.grey.shade400,
                              size: 16,
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // Build more page with settings and options
  Widget _buildMorePage() {
    return Scaffold(
      appBar: AppBar(
        title: const Text('More'),
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
        automaticallyImplyLeading: false,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Theme toggle
			_buildMoreOption(
			  icon: Icons.palette,
			  title: 'Theme',
			  subtitle: 'Light theme (fixed)',
			  onTap: () {
				ScaffoldMessenger.of(context).showSnackBar(
				  const SnackBar(
					content: Text('Theme is set to light mode only'),
					backgroundColor: Colors.blue,
				  ),
				);
			  },
			),

          const SizedBox(height: 8),

          // Settings
          _buildMoreOption(
            icon: Icons.settings,
            title: 'Settings',
            subtitle: 'App preferences and configuration',
            onTap: () {
              Navigator.pushNamed(context, '/settings');
            },
          ),

          const SizedBox(height: 8),

          // Import Task
          _buildMoreOption(
            icon: Icons.file_upload,
            title: 'Import Task',
            subtitle: 'Import task from shared file',
            onTap: _showImportDialog,
          ),

          const SizedBox(height: 8),

          // Debug Panel
          _buildMoreOption(
            icon: Icons.bug_report,
            title: 'Debug Panel',
            subtitle: 'Development tools and diagnostics',
            iconColor: Colors.orange,
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => DebugScreen()),
              );
            },
          ),
		  
		  _buildMoreOption(
			  icon: Icons.refresh,
			  title: 'Test Task Refresh',
			  subtitle: 'Debug: manually refresh task list',
			  iconColor: Colors.purple,
			  onTap: _testTaskListRefresh,
			),
			
		_buildMoreOption(
		  icon: Icons.notifications_off,
		  title: 'Fix Pop-up Notifications',
		  subtitle: 'Turn off annoying notification pop-ups (Huawei)',
		  iconColor: Colors.orange,
		  onTap: _showHuaweiNotificationHelp,
		),
		  
		  //const SizedBox(height: 8),

        ],
      ),
    );
  }

  Widget _buildMoreOption({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    Color? iconColor,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.shade200,
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: (iconColor ?? Theme.of(context).primaryColor).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    icon,
                    color: iconColor ?? Theme.of(context).primaryColor,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.arrow_forward_ios,
                  color: Colors.grey.shade400,
                  size: 16,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Helper methods for task operations
	void _openTaskDetail(TaskLocation task) async {
	  print('🔄 OPEN TASK DETAIL: Opening task: ${task.title}');
	  
	  final result = await Navigator.push(
		context,
		MaterialPageRoute(
		  builder: (ctx) => TaskDetailScreen(taskLocation: task),
		),
	  );

	  print('🔄 OPEN TASK DETAIL: Returned with result: $result');

	  if (result != null) {
		print('🔄 OPEN TASK DETAIL: Result is not null, reloading task data...');
		// Reload task data instead of just calling setState
		await _loadTaskData();
	  }
	}

  void _deleteTask(TaskLocation task) {
    HapticFeedback.mediumImpact();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Task'),
        content: Text('Are you sure you want to delete "${task.title}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);

              final result = await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (ctx) => DeleteTaskConfirmationScreen(
                    taskLocation: task,
                  ),
                ),
              );

				if (result == true) {
				  print('🔄 DELETE TASK: Task deleted, reloading data...');
				  // Reload task data instead of just calling setState
				  await _loadTaskData();

				  ScaffoldMessenger.of(context).showSnackBar(
					SnackBar(
					  content: Text('Task "${task.title}" deleted'),
					  backgroundColor: Colors.red,
					),
				  );
				}
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
  
  void _focusOnTask(TaskLocation task) {
    // Switch to map tab first
    setState(() {
      _currentIndex = 0;
    });

    // Add longer delay to ensure map is fully built and ready
    Future.delayed(const Duration(milliseconds: 500), () {
      print('🎯 MAIN DEBUG: Attempting to focus on task: ${task.title}');
      print('🎯 MAIN DEBUG: _mapKey.currentState: ${_mapKey.currentState}');

      final mapState = _mapKey.currentState as dynamic;
      if (mapState != null) {
        print('🎯 MAIN DEBUG: Found map state, calling focusOnTaskLocation');
        mapState.focusOnTaskLocation(task);
      } else {
        print('❌ MAIN DEBUG: Map state is null!');
      }
    });
  }

  void _showImportDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.file_upload, color: Colors.teal),
            SizedBox(width: 8),
            Text('Import Task'),
          ],
        ),
        content: const Text(
          'Import allows you to add tasks that were shared with you by other Locado users.\n\n'
              'You need a .json file that was exported from another Locado app.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _performFileImport();
            },
            child: const Text('Choose File'),
          ),
        ],
      ),
    );
  }

	Future<void> _performFileImport() async {
	  try {
		final status = await Permission.storage.request();
		if (!status.isGranted) {
		  ScaffoldMessenger.of(context).showSnackBar(
			const SnackBar(content: Text('Storage permission denied')),
		  );
		  return;
		}

		FilePickerResult? result = await FilePicker.platform.pickFiles(
		  type: FileType.any,
		);

		if (result != null && result.files.single.path != null) {
		  final path = result.files.single.path!;

		  if (!path.toLowerCase().endsWith('.json')) {
			ScaffoldMessenger.of(context).showSnackBar(
			  const SnackBar(content: Text('Please select a .json file')),
			);
			return;
		  }

		  final file = File(path);
		  final jsonString = await file.readAsString();
		  final Map<String, dynamic> data = jsonDecode(jsonString);

		  final task = TaskLocation.fromMap(data);
		  await DatabaseHelper.instance.addTaskLocation(task);
		  
		  // CACHE SYNC: Add to cache immediately
		  await _syncCacheAfterTaskAdd(task);

		  ScaffoldMessenger.of(context).showSnackBar(
			const SnackBar(
			  content: Text('Task imported successfully'),
			  backgroundColor: Colors.green,
			),
		  );

		  print('🔄 FILE IMPORT: Task imported, reloading data...');
		  await _loadTaskData(); // Will use cache first
		}
	  } catch (e) {
		ScaffoldMessenger.of(context).showSnackBar(
		  SnackBar(content: Text('Import error: $e')),
		);
	  }
	}

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          // Search bar at top (only show on map tab)
          if (_currentIndex == 0) _buildSearchBar(),

          // Main content
          Expanded(child: _getCurrentPage()),
        ],
      ),

      // Bottom Navigation Bar
		bottomNavigationBar: BottomNavigationBar(
		  currentIndex: _currentIndex,
		  onTap: (index) {
			// ✅ ZAPAMTI staru vrednost PRE setState
			final int previousIndex = _currentIndex;
			
			setState(() {
			  _currentIndex = index;
			});

			// ✅ ISPRAVKA - koristi previousIndex umesto _currentIndex
			if (index == 2 && previousIndex != 2) {
			  print('🔄 MAIN NAV: Switching to Tasks tab, refreshing data...');
			  _loadTaskData();
			}
		  },
		  type: BottomNavigationBarType.fixed,
		  selectedItemColor: Colors.teal,
		  unselectedItemColor: Colors.grey,
		  items: const [
			BottomNavigationBarItem(
			  icon: Icon(Icons.map),
			  label: 'Map',
			),
			BottomNavigationBarItem(
			  icon: Icon(Icons.smart_toy),
			  label: 'AI Search',
			),
			BottomNavigationBarItem(
			  icon: Icon(Icons.format_list_bulleted),
			  label: 'Tasks',
			),
			BottomNavigationBarItem(
			  icon: Icon(Icons.calendar_today),
			  label: 'Calendar',
			),
			BottomNavigationBarItem(
			  icon: Icon(Icons.more_horiz),
			  label: 'More',
			),
		  ],
		),

      // Floating Action Button (only show on map tab)
		floatingActionButton: _currentIndex == 0 ? FloatingActionButton(
		  onPressed: () async {
			print('🔄 FAB: FloatingActionButton pressed, opening TaskInputScreen...');
			
			final userPosition = LatLng(48.2082, 16.3738); // Default Vienna coordinates
			final result = await Navigator.push(
			  context,
			  MaterialPageRoute(
				builder: (ctx) => TaskInputScreen(location: userPosition),
			  ),
			);

			print('🔄 FAB: TaskInputScreen returned with result: $result');

			if (result == true) {
			  print('🔄 FAB: Result is true, reloading task data...');
			  // Reload task data after new task is added (will use cache first)
			  await _loadTaskData();
			}
		  },
		  backgroundColor: Colors.teal,
		  foregroundColor: Colors.white,
		  child: const Icon(Icons.add),
		) : null,

      floatingActionButtonLocation: FloatingActionButtonLocation.startFloat,
    );
  }

  Widget _buildSearchBar() {
    return Container(
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top + 8,
        left: 16,
        right: 16,
        bottom: 8,
      ),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        boxShadow: [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          // Search input row
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchController,
                  focusNode: _searchFocusNode,
                  decoration: InputDecoration(
                    hintText: 'Search places (Hofer, pharmacy, restaurant...)',
                    prefixIcon: const Icon(Icons.search, size: 20),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                      icon: const Icon(Icons.clear, size: 20),
                      onPressed: () {
                        _searchController.clear();
                        setState(() {
                          _suggestions.clear();
                          _showSuggestions = false;
                        });
                      },
                    )
                        : null,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    filled: true,
                    fillColor: Theme.of(context).cardColor,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                  ),
                  onSubmitted: (_) => _performSearch(),
                ),
              ),
              if (_searchController.text.isNotEmpty) ...[
                const SizedBox(width: 8),
                Container(
                  height: 48,
                  child: ElevatedButton(
                    onPressed: _isSearching ? null : _performSearch,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.teal,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: _isSearching
                        ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                        : const Icon(Icons.search),
                  ),
                ),
              ],
            ],
          ),

          // Autocomplete suggestions dropdown
          if (_showSuggestions) ...[
            const SizedBox(height: 8),
            Container(
              constraints: const BoxConstraints(maxHeight: 200),
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black12,
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: _isLoadingSuggestions
                  ? const Padding(
                padding: EdgeInsets.all(16),
                child: Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      SizedBox(width: 8),
                      Text('Searching...'),
                    ],
                  ),
                ),
              )
                  : _suggestions.isEmpty
                  ? const Padding(
                padding: EdgeInsets.all(16),
                child: Center(
                  child: Text(
                    'No suggestions found',
                    style: TextStyle(color: Colors.grey),
                  ),
                ),
              )
                  : ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.all(8),
                itemCount: _suggestions.length,
                separatorBuilder: (context, index) => const Divider(
                  height: 1,
                  color: Color(0xFFE0E0E0),
                ),
                itemBuilder: (context, index) {
                  final suggestion = _suggestions[index];
                  return ListTile(
                    dense: true,
                    leading: const Icon(
                      Icons.location_on,
                      color: Color(0xFF4DB6AC),
                      size: 20,
                    ),
                    title: Text(
                      suggestion.mainText,
                      style: const TextStyle(fontWeight: FontWeight.w500),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: suggestion.secondaryText != null
                        ? Text(
                      suggestion.secondaryText!,
                      style: const TextStyle(
                        color: Color(0xFF757575),
                        fontSize: 12,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    )
                        : null,
                    onTap: () => _onSuggestionSelected(suggestion),
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _performSearch() {
    final searchTerm = _searchController.text.trim();
    if (searchTerm.isEmpty) return;

    setState(() {
      _isSearching = true;
    });

    // Access the map screen and perform search
    final mapState = _mapKey.currentState as dynamic;
    if (mapState != null) {
      mapState.performSearch(searchTerm).then((_) {
        if (mounted) {
          setState(() {
            _isSearching = false;
          });
        }
      });
    } else {
      setState(() {
        _isSearching = false;
      });
    }
  }
 
Future<void> _loadMapProviderDisplay() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    
    // ✅ FORSIRAJ OSM
    await prefs.setBool('use_openstreetmap', true);
    
    setState(() {
      _currentMapProvider = 'OpenStreetMap';
    });
  } catch (e) {
    setState(() {
      _currentMapProvider = 'OpenStreetMap';
    });
  }
}

void _showMapProviderDialog() {
  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.layers, color: Colors.blue),
          SizedBox(width: 8),
          Text('Choose Map Provider'),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Select which map service to use in the app:'),
          const SizedBox(height: 16),
          
          // Google Maps option
          ListTile(
            leading: const Icon(Icons.map, color: Colors.red),
            title: const Text('Google Maps'),
            subtitle: const Text('Satellite imagery, detailed POI data'),
            trailing: _currentMapProvider == 'Google Maps' 
                ? const Icon(Icons.check, color: Colors.green) 
                : null,
            onTap: () => _selectMapProvider('Google Maps'),
          ),
          
          // OpenStreetMap option
          ListTile(
            leading: const Icon(Icons.layers, color: Colors.green),
            title: const Text('OpenStreetMap'),
            subtitle: const Text('Open source, no API costs'),
            trailing: _currentMapProvider == 'OpenStreetMap' 
                ? const Icon(Icons.check, color: Colors.green) 
                : null,
            onTap: () => _selectMapProvider('OpenStreetMap'),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
      ],
    ),
  );
}

Future<void> _selectMapProvider(String provider) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final useOSM = provider == 'OpenStreetMap';
    
    await prefs.setBool('use_openstreetmap', useOSM);
    
    setState(() {
      _currentMapProvider = provider;
    });
    
    Navigator.pop(context);
    
    // Show confirmation and restart hint
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              useOSM ? Icons.layers : Icons.map,
              color: Colors.white,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text('$provider selected! Go to Map tab to see changes.'),
            ),
          ],
        ),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 4),
        action: SnackBarAction(
          label: 'Go to Map',
          textColor: Colors.white,
          onPressed: () {
            setState(() {
              _currentIndex = 0; // Switch to map tab
            });
          },
        ),
      ),
    );
    
  } catch (e) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Error saving setting: $e'),
        backgroundColor: Colors.red,
      ),
    );
  }
}

  // Google Places Autocomplete (existing functionality)
	Future<void> _fetchGooglePlacesSuggestions(String query, LatLng? userLocation) async {
	  // Build API URL with location bias
	  String url = 'https://maps.googleapis.com/maps/api/place/autocomplete/json'
		  '?input=${Uri.encodeComponent(query)}'
		  '&key=${dotenv.env['GOOGLE_MAPS_API_KEY_HTTP'] ?? ''}'
		  '&language=en';

	  // Add location bias if available
	  if (userLocation != null) {
		url += '&location=${userLocation.latitude},${userLocation.longitude}'
			'&radius=5000'; // 5km radius
	  }

	  print('🔍 FETCH: Google API URL: $url');

	  final response = await http.get(Uri.parse(url));

	  print('🔍 FETCH: Google response status: ${response.statusCode}');
	  print('🔍 FETCH: Google response body: ${response.body}');

	  if (response.statusCode == 200) {
		final data = json.decode(response.body);
		final List<dynamic> predictions = data['predictions'] ?? [];

		print('🔍 FETCH: Found ${predictions.length} Google predictions');

		final suggestions = predictions
			.map((prediction) => AutocompleteSuggestion.fromJson(prediction))
			.toList();

		if (mounted) {
		  setState(() {
			_suggestions = suggestions;
			_isLoadingSuggestions = false;
			_showSuggestions = suggestions.isNotEmpty;
		  });
		  print('🔍 FETCH: Updated UI with ${suggestions.length} Google suggestions');
		}
	  } else {
		print('❌ FETCH: Google error response: ${response.statusCode}');
		if (mounted) {
		  setState(() {
			_suggestions.clear();
			_isLoadingSuggestions = false;
			_showSuggestions = false;
		  });
		}
	  }
	}

	// NEW: Nominatim-based autocomplete suggestions for OpenStreetMap
	Future<void> _fetchNominatimSuggestions(String query, LatLng? userLocation) async {
	  // Default to Vienna if no user location
	  final double centerLat = userLocation?.latitude ?? 48.2082;
	  final double centerLng = userLocation?.longitude ?? 16.3738;

	  // Create viewbox around current location (approximately 10km radius)
	  final double radiusOffset = 0.1; // ~10km in degrees
	  final double minLon = centerLng - radiusOffset;
	  final double maxLat = centerLat + radiusOffset;
	  final double maxLon = centerLng + radiusOffset;
	  final double minLat = centerLat - radiusOffset;

	  final url = 'https://nominatim.openstreetmap.org/search'
		  '?q=${Uri.encodeComponent(query)}'
		  '&format=json'
		  '&limit=8' // Fewer results for autocomplete
		  '&addressdetails=1'
		  '&namedetails=1'
		  '&viewbox=$minLon,$maxLat,$maxLon,$minLat'
		  '&bounded=1'; // Restrict to viewbox for relevant results

	  print('🔍 FETCH: Nominatim API URL: $url');

	  final response = await http.get(
		Uri.parse(url),
		headers: {
		  'User-Agent': 'Locado/1.0 (Flutter App)', // Required by Nominatim
		},
	  );

	  print('🔍 FETCH: Nominatim response status: ${response.statusCode}');

	  if (response.statusCode == 200) {
		final List<dynamic> results = json.decode(response.body);
		print('🔍 FETCH: Found ${results.length} Nominatim results');

		// Convert Nominatim results to AutocompleteSuggestion format
		final List<AutocompleteSuggestion> suggestions = [];

		for (final result in results) {
		  final displayName = result['display_name'] ?? '';
		  final parts = displayName.split(',');
		  
		  // Extract main text (place name)
		  String mainText = _extractBestNameFromNominatim(result);
		  
		  // Extract secondary text (address/location info)
		  String? secondaryText;
		  if (parts.length > 1) {
			// Take next 2-3 parts for context
			final contextParts = parts.skip(1).take(3).map((s) => s.trim()).toList();
			secondaryText = contextParts.join(', ');
		  }

		  suggestions.add(
			AutocompleteSuggestion(
			  placeId: 'osm_${result['osm_type']}_${result['osm_id']}', // Create unique ID
			  description: displayName,
			  mainText: mainText,
			  secondaryText: secondaryText,
			),
		  );
		}

		print('🔍 FETCH: Converted to ${suggestions.length} OSM suggestions');

		if (mounted) {
		  setState(() {
			_suggestions = suggestions;
			_isLoadingSuggestions = false;
			_showSuggestions = suggestions.isNotEmpty;
		  });
		  print('🔍 FETCH: Updated UI with ${suggestions.length} Nominatim suggestions');
		}
	  } else {
		print('❌ FETCH: Nominatim error response: ${response.statusCode}');
		if (mounted) {
		  setState(() {
			_suggestions.clear();
			_isLoadingSuggestions = false;
			_showSuggestions = false;
		  });
		}
	  }
	}

	// Helper method to extract best name from Nominatim result
	String _extractBestNameFromNominatim(Map<String, dynamic> result) {
	  // Try different name fields in order of preference
	  if (result['namedetails'] != null) {
		final nameDetails = result['namedetails'];
		if (nameDetails['name:en'] != null && nameDetails['name:en'].toString().isNotEmpty) {
		  return nameDetails['name:en'];
		}
		if (nameDetails['name'] != null && nameDetails['name'].toString().isNotEmpty) {
		  return nameDetails['name'];
		}
	  }
	  
	  if (result['name'] != null && result['name'].toString().isNotEmpty) {
		return result['name'];
	  }
	  
	  // Fallback to first part of display_name
	  final displayName = result['display_name'] ?? '';
	  final parts = displayName.split(',');
	  return parts.isNotEmpty ? parts.first.trim() : 'Unknown Location';
	}
	
	// NEW: Handle OSM suggestion selection
	Future<void> _handleOSMSuggestionSelection(AutocompleteSuggestion suggestion) async {
	  setState(() {
		_isSearching = true;
	  });

	  try {
		// For OSM suggestions, we can directly trigger the search
		// since we already have the location info in the description
		
		// Trigger map search with the suggestion text
		final mapState = _mapKey.currentState as dynamic;
		if (mapState != null) {
		  await mapState.performSearch(suggestion.mainText);
		}

		// Show success message
		ScaffoldMessenger.of(context).showSnackBar(
		  SnackBar(
			content: Row(
			  children: [
				const Icon(Icons.location_on, color: Colors.white),
				const SizedBox(width: 8),
				Expanded(child: Text('Found: ${suggestion.mainText}')),
			  ],
			),
			backgroundColor: Colors.green,
			duration: const Duration(seconds: 2),
		  ),
		);

	  } catch (e) {
		ScaffoldMessenger.of(context).showSnackBar(
		  SnackBar(
			content: Text('Error finding location: $e'),
			backgroundColor: Colors.red,
		  ),
		);
	  }

	  if (mounted) {
		setState(() {
		  _isSearching = false;
		});
	  }
	}
	
	Future<bool> _isHuaweiDevice() async {
	  try {
		DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();
		AndroidDeviceInfo androidInfo = await deviceInfo.androidInfo;
		final manufacturer = androidInfo.manufacturer.toLowerCase();
		final brand = androidInfo.brand.toLowerCase();
		
		return manufacturer.contains('huawei') || 
			   brand.contains('huawei') ||
			   manufacturer.contains('honor') ||
			   brand.contains('honor');
	  } catch (e) {
		return false;
	  }
	}

	Future<void> _showHuaweiNotificationHelp() async {
	  final isHuawei = await _isHuaweiDevice();
	  
	  if (!isHuawei) {
		ScaffoldMessenger.of(context).showSnackBar(
		  const SnackBar(content: Text('This feature is for Huawei devices only')),
		);
		return;
	  }

	  showDialog(
		context: context,
		builder: (context) => AlertDialog(
		  title: Text('Turn Off Pop-ups'),
		  content: Container(
			height: 200,
			child: Column(
			  children: [
				Text('1. Settings → Apps → Locado'),
				Text('2. Tap "Notifications"'),
				Text('3. Turn off "Banner notifications"'),
				Text('4. Keep "Status bar" ON'),
			  ],
			),
		  ),
		  actions: [
			TextButton(
			  onPressed: () => Navigator.pop(context),
			  child: Text('Cancel'),
			),
			ElevatedButton(
			  onPressed: () {
				Navigator.pop(context);
				AppSettings.openAppSettings(type: AppSettingsType.notification);
			  },
			  child: Text('Open Settings'),
			),
		  ],
		),
	  );
	}

	// Helper widget za instrukcije
	Widget _buildInstructionStep(String number, String title, String description, IconData icon) {
	  return Row(
		crossAxisAlignment: CrossAxisAlignment.start,
		children: [
		  Container(
			width: 24,
			height: 24,
			decoration: BoxDecoration(
			  color: Colors.orange,
			  shape: BoxShape.circle,
			),
			child: Center(
			  child: Text(
				number,
				style: TextStyle(
				  color: Colors.white,
				  fontSize: 12,
				  fontWeight: FontWeight.bold,
				),
			  ),
			),
		  ),
		  SizedBox(width: 12),
		  Icon(icon, color: Colors.orange, size: 20),
		  SizedBox(width: 8),
		  Expanded(
			child: Column(
			  crossAxisAlignment: CrossAxisAlignment.start,
			  children: [
				Text(
				  title,
				  style: TextStyle(
					fontWeight: FontWeight.w600,
					fontSize: 14,
				  ),
				),
				SizedBox(height: 2),
				Text(
				  description,
				  style: TextStyle(
					color: Colors.grey.shade600,
					fontSize: 12,
				  ),
				),
			  ],
			),
		  ),
		],
	  );
	}

	// Otvara notification settings
	Future<void> _openNotificationSettings() async {
	  try {
		await AppSettings.openAppSettings(type: AppSettingsType.notification);
		
		// Prikaži success message nakon kratke pauze
		Future.delayed(Duration(seconds: 1), () {
		  if (mounted) {
			ScaffoldMessenger.of(context).showSnackBar(
			  SnackBar(
				content: Row(
				  children: [
					Icon(Icons.info, color: Colors.white),
					SizedBox(width: 8),
					Text('Look for notification categories and turn off pop-ups'),
				  ],
				),
				backgroundColor: Colors.orange,
				duration: Duration(seconds: 4),
			  ),
			);
		  }
		});
		
	  } catch (e) {
		ScaffoldMessenger.of(context).showSnackBar(
		  SnackBar(
			content: Text('Could not open settings: $e'),
			backgroundColor: Colors.red,
		  ),
		);
	  }
	}
}