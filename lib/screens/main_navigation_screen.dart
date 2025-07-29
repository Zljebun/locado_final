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
import '../theme/theme_provider.dart';
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
	print('🔑 DEBUG: HTTP API Key = ${dotenv.env['GOOGLE_MAPS_API_KEY_HTTP']}');
    _loadTaskData();
    _setupSearchListeners();
	_loadMapProviderDisplay();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    _debounceTimer?.cancel();
    super.dispose();
  }

  // Load and cache task data
  Future<void> _loadTaskData() async {
    setState(() {
      _isLoadingTasks = true;
    });

    try {
      final tasks = await DatabaseHelper.instance.getAllTaskLocations();
      _cachedTasks = tasks;

      if (tasks.isNotEmpty) {
        setState(() {
          _isLoadingDistance = true;
        });

        final sortedTasks = await _sortTasksByDistanceWithDetails(tasks);
        _cachedSortedTasks = sortedTasks;
      } else {
        _cachedSortedTasks = [];
      }
    } catch (e) {
      _cachedTasks = [];
      _cachedSortedTasks = [];
    }

    setState(() {
      _isLoadingTasks = false;
      _isLoadingDistance = false;
    });
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
            setState(() {
              _currentIndex = 0; // Switch to map tab
            });
            // Reload task data when new tasks are created
            Future.delayed(const Duration(milliseconds: 100), () {
              if (mounted) {
                _loadTaskData();
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

  // Sort tasks by distance with details
  Future<List<TaskWithDistance>> _sortTasksByDistanceWithDetails(List<TaskLocation> tasks) async {
    try {
      final position = await LocationService.getCurrentLocation();

      if (position == null) {
        return tasks.map((task) => TaskWithDistance(task, 0.0)).toList();
      }

      List<TaskWithDistance> tasksWithDistance = [];

      for (final task in tasks) {
        final distance = _calculateDistance(
          position.latitude,
          position.longitude,
          task.latitude,
          task.longitude,
        );
        tasksWithDistance.add(TaskWithDistance(task, distance));
      }

      tasksWithDistance.sort((a, b) => a.distance.compareTo(b.distance));
      return tasksWithDistance;

    } catch (e) {
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
      // Delete all selected tasks
      for (final taskId in _selectedTaskIds) {
        await DatabaseHelper.instance.deleteTaskLocation(taskId);
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

      // Reload task data after deletion
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

  // Build task list page with enhanced functionality
// Build task list page with enhanced functionality
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
          ] else
            IconButton(
              icon: const Icon(Icons.checklist),
              onPressed: _toggleSelectionMode,
            ),
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
          Consumer<ThemeProvider>(
            builder: (context, themeProvider, child) {
              return _buildMoreOption(
                icon: themeProvider.themeIcon,
                title: 'Theme',
                subtitle: themeProvider.currentThemeDescription,
                onTap: () async {
                  await themeProvider.toggleTheme();

                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Row(
                        children: [
                          Icon(
                            themeProvider.isDarkMode ? Icons.dark_mode : Icons.light_mode,
                            color: Colors.white,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Text('${themeProvider.currentThemeDescription} activated!'),
                        ],
                      ),
                      backgroundColor: Colors.green,
                      duration: const Duration(seconds: 2),
                    ),
                  );
                },
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
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (ctx) => TaskDetailScreen(taskLocation: task),
      ),
    );

    if (result != null) {
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

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Task imported successfully'),
            backgroundColor: Colors.green,
          ),
        );

        await _loadTaskData();
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
          setState(() {
            _currentIndex = index;
          });

          // Refresh task data when switching to tasks tab
          if (index == 2 && _currentIndex != 2) {
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
          final userPosition = LatLng(48.2082, 16.3738); // Default Vienna coordinates
          final result = await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (ctx) => TaskInputScreen(location: userPosition),
            ),
          );

          if (result == true) {
            // Reload task data after new task is added
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
  
  // NEW METHODS for map provider setting
Future<void> _loadMapProviderDisplay() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final useOSM = prefs.getBool('use_openstreetmap') ?? false;
    
    setState(() {
      _currentMapProvider = useOSM ? 'OpenStreetMap' : 'Google Maps';
    });
  } catch (e) {
    setState(() {
      _currentMapProvider = 'Google Maps';
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
}