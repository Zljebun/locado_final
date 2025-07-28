// screens/task_detail_screen.dart - HYBRID VERSION

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' as gmaps;
import 'package:flutter_map/flutter_map.dart' as osm;
import 'package:latlong2/latlong.dart' as ll;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:locado_final/models/task_location.dart';
import 'package:locado_final/models/calendar_event.dart';
import 'package:locado_final/helpers/database_helper.dart';
import 'package:locado_final/screens/notification_service.dart';
import 'package:share_plus/share_plus.dart';
import 'dart:io';
import 'dart:convert';
import 'package:path_provider/path_provider.dart';
import '../screens/search_location_screen.dart';
import '../screens/event_details_screen.dart';
import 'package:flutter/services.dart';
import '../widgets/osm_map_widget.dart';

// Enum for map provider selection
enum MapProvider { googleMaps, openStreetMap }

// Universal coordinate class
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

class TaskDetailScreen extends StatefulWidget {
  final TaskLocation taskLocation;
  final bool isLockScreenMode;

  const TaskDetailScreen({Key? key, required this.taskLocation, this.isLockScreenMode = false,}) : super(key: key);

  @override
  State<TaskDetailScreen> createState() => _TaskDetailScreenState();
}

class _TaskDetailScreenState extends State<TaskDetailScreen> {
  late List<bool> _checkedItems;
  late TextEditingController _titleController;
  final TextEditingController _newItemController = TextEditingController();
  final FocusNode _newItemFocusNode = FocusNode();
  UniversalLatLng? _selectedLocation;
  String? _selectedLocationName;
  Color _selectedColor = Colors.teal;
  bool _hasChanges = false;

  // Map provider selection
  MapProvider _currentMapProvider = MapProvider.googleMaps;

  // Google Maps controllers
  gmaps.GoogleMapController? _googleMapController;
  Set<gmaps.Marker> _googleMarkers = {};
  
  // OpenStreetMap controllers  
  osm.MapController? _osmMapController;
  Set<OSMMarker> _osmMarkers = {};

  // Scheduling state variables
  DateTime? _scheduledDate;
  TimeOfDay? _scheduledTime;
  CalendarEvent? _linkedCalendarEvent;

  @override
  void initState() {
    super.initState();
    _loadMapProviderSetting();
    _titleController = TextEditingController(text: widget.taskLocation.title);
    _selectedLocation = UniversalLatLng(widget.taskLocation.latitude, widget.taskLocation.longitude);
    _selectedColor = _taskColor;

    // Initialize scheduling data
    if (widget.taskLocation.hasScheduledTime) {
      _scheduledDate = DateTime(
        widget.taskLocation.scheduledDateTime!.year,
        widget.taskLocation.scheduledDateTime!.month,
        widget.taskLocation.scheduledDateTime!.day,
      );
      _scheduledTime = TimeOfDay.fromDateTime(widget.taskLocation.scheduledDateTime!);
    }

    _syncCheckedItems();
    _loadLinkedCalendarEvent();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _newItemController.dispose();
    _newItemFocusNode.dispose();
    super.dispose();
  }

  // Load map provider setting
  Future<void> _loadMapProviderSetting() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final useOSM = prefs.getBool('use_openstreetmap') ?? false;
      
      setState(() {
        _currentMapProvider = useOSM ? MapProvider.openStreetMap : MapProvider.googleMaps;
      });

      // Initialize markers after loading provider
      _createMapMarkers();

      print('🗺️ TASK DETAIL: Loaded map provider: ${_currentMapProvider.name}');
    } catch (e) {
      print('Error loading map provider setting: $e');
      _currentMapProvider = MapProvider.googleMaps;
      _createMapMarkers();
    }
  }

  // Create markers for current provider
  void _createMapMarkers() {
    if (_selectedLocation == null) return;

    if (_currentMapProvider == MapProvider.googleMaps) {
      _createGoogleMarkers();
    } else {
      _createOSMMarkers();
    }
  }

  // Create Google Maps markers
  void _createGoogleMarkers() {
    if (_selectedLocation == null) return;

    final marker = gmaps.Marker(
      markerId: const gmaps.MarkerId('task_location'),
      position: _selectedLocation!.toGoogleMaps(),
      infoWindow: gmaps.InfoWindow(
        title: widget.taskLocation.title,
        snippet: 'Task location',
      ),
      icon: gmaps.BitmapDescriptor.defaultMarkerWithHue(_getGoogleHueFromColor(_selectedColor)),
    );

    setState(() {
      _googleMarkers = {marker};
    });
  }

  // Create OpenStreetMap markers
  void _createOSMMarkers() {
    if (_selectedLocation == null) return;

    final marker = OSMMarker(
      markerId: 'task_location',
      position: _selectedLocation!.toOpenStreetMap(),
      title: widget.taskLocation.title,
      child: OSMConverter.createDefaultMarker(color: _selectedColor),
    );

    setState(() {
      _osmMarkers = {marker};
    });
  }

  // Convert Flutter Color to Google Maps hue
  double _getGoogleHueFromColor(Color color) {
    if (color == Colors.red) return gmaps.BitmapDescriptor.hueRed;
    if (color == Colors.green) return gmaps.BitmapDescriptor.hueGreen;
    if (color == Colors.blue) return gmaps.BitmapDescriptor.hueBlue;
    if (color == Colors.orange) return gmaps.BitmapDescriptor.hueOrange;
    if (color == Colors.yellow) return gmaps.BitmapDescriptor.hueYellow;
    if (color == Colors.purple) return gmaps.BitmapDescriptor.hueViolet;
    if (color == Colors.cyan) return gmaps.BitmapDescriptor.hueCyan;
    return gmaps.BitmapDescriptor.hueRed; // Default
  }

  void _syncCheckedItems() {
    _checkedItems = List<bool>.filled(widget.taskLocation.taskItems.length, false);
  }

  // Load linked calendar event
  Future<void> _loadLinkedCalendarEvent() async {
    if (widget.taskLocation.hasLinkedCalendarEvent) {
      try {
        final events = await DatabaseHelper.instance.getCalendarEventsForTask(widget.taskLocation.id!);
        if (events.isNotEmpty) {
          setState(() {
            _linkedCalendarEvent = events.first;
          });
        }
      } catch (e) {
        debugPrint('❌ Error loading linked calendar event: $e');
      }
    }
  }

  Color get _taskColor {
    try {
      return Color(int.parse(widget.taskLocation.colorHex.replaceFirst('#', '0xff')));
    } catch (e) {
      return Colors.teal;
    }
  }

  // Date/Time picker methods
  Future<void> _selectScheduledDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _scheduledDate ?? DateTime.now().add(Duration(hours: 1)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(Duration(days: 365)),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: Theme.of(context).colorScheme.copyWith(primary: Colors.teal),
          ),
          child: child!,
        );
      },
    );

    if (date != null) {
      setState(() {
        _scheduledDate = date;
        if (_scheduledTime == null) {
          final now = DateTime.now();
          _scheduledTime = TimeOfDay(hour: now.hour + 1, minute: 0);
        }
        _hasChanges = true;
      });
    }
  }

  Future<void> _selectScheduledTime() async {
    final time = await showTimePicker(
      context: context,
      initialTime: _scheduledTime ?? TimeOfDay(hour: DateTime.now().hour + 1, minute: 0),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: Theme.of(context).colorScheme.copyWith(primary: Colors.teal),
          ),
          child: child!,
        );
      },
    );

    if (time != null) {
      setState(() {
        _scheduledTime = time;
        if (_scheduledDate == null) {
          _scheduledDate = DateTime.now().add(Duration(hours: 1));
        }
        _hasChanges = true;
      });
    }
  }

  String _formatScheduledDateTime() {
    if (_scheduledDate == null || _scheduledTime == null) return 'Not scheduled';

    const months = ['', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

    final hour = _scheduledTime!.hour;
    final minute = _scheduledTime!.minute.toString().padLeft(2, '0');
    final period = hour < 12 ? 'AM' : 'PM';
    final displayHour = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour);

    return '${months[_scheduledDate!.month]} ${_scheduledDate!.day} at $displayHour:$minute $period';
  }

  // Save/update scheduling
  Future<void> _saveScheduling() async {
    DateTime? scheduledDateTime;

    if (_scheduledDate != null && _scheduledTime != null) {
      scheduledDateTime = DateTime(
        _scheduledDate!.year,
        _scheduledDate!.month,
        _scheduledDate!.day,
        _scheduledTime!.hour,
        _scheduledTime!.minute,
      );
    }

    try {
      await DatabaseHelper.instance.updateTaskScheduledTime(widget.taskLocation.id!, scheduledDateTime);
      widget.taskLocation.scheduledDateTime = scheduledDateTime;
      if (scheduledDateTime != null) {
        widget.taskLocation.linkedCalendarEventId = _linkedCalendarEvent?.id;
      }

      if (scheduledDateTime != null) {
        if (_linkedCalendarEvent != null) {
          final updatedEvent = _linkedCalendarEvent!.copyWith(
            title: widget.taskLocation.generateCalendarEventTitle(),
            description: widget.taskLocation.generateCalendarEventDescription(),
            dateTime: scheduledDateTime,
            colorHex: widget.taskLocation.colorHex,
          );

          await DatabaseHelper.instance.updateCalendarEvent(updatedEvent);
          await NotificationService.scheduleEventReminders(updatedEvent);

          setState(() {
            _linkedCalendarEvent = updatedEvent;
          });

          debugPrint('✅ Updated linked calendar event');
        } else {
          final calendarEvent = CalendarEvent(
            title: widget.taskLocation.generateCalendarEventTitle(),
            description: widget.taskLocation.generateCalendarEventDescription(),
            dateTime: scheduledDateTime,
            reminderMinutes: [15],
            colorHex: widget.taskLocation.colorHex,
            linkedTaskLocationId: widget.taskLocation.id,
          );

          final eventId = await DatabaseHelper.instance.addCalendarEvent(calendarEvent);
          await DatabaseHelper.instance.linkTaskToCalendarEvent(widget.taskLocation.id!, eventId);

          final eventWithId = calendarEvent.copyWith(id: eventId);
          await NotificationService.scheduleEventReminders(eventWithId);

          setState(() {
            _linkedCalendarEvent = eventWithId;
          });

          debugPrint('✅ Created new linked calendar event');
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Task scheduled for ${_formatScheduledDateTime()}'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        if (_linkedCalendarEvent != null) {
          await DatabaseHelper.instance.deleteCalendarEvent(_linkedCalendarEvent!.id!);
          await DatabaseHelper.instance.unlinkTaskFromCalendarEvent(widget.taskLocation.id!);

          setState(() {
            _linkedCalendarEvent = null;
          });

          debugPrint('✅ Removed scheduling and linked calendar event');
        }

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Scheduling removed'),
            backgroundColor: Colors.orange,
          ),
        );
      }

      _hasChanges = true;
    } catch (e) {
      debugPrint('❌ Error saving scheduling: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error saving scheduling: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // Navigate to calendar event
  Future<void> _navigateToCalendarEvent() async {
    if (_linkedCalendarEvent != null) {
      try {
        final result = await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => EventDetailsScreen(
              event: _linkedCalendarEvent!,
              taskLocations: [widget.taskLocation],
            ),
          ),
        );

        if (result == true) {
          _loadLinkedCalendarEvent();
        }
      } catch (e) {
        debugPrint('❌ Error navigating to calendar event: $e');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error opening calendar event: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // Schedule dialog
  void _showScheduleDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.schedule, color: Colors.teal),
            const SizedBox(width: 8),
            Text((_scheduledDate != null && _scheduledTime != null) ? 'Edit Schedule' : 'Add Schedule'),
          ],
        ),
        content: SizedBox(
          width: 300,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_scheduledDate != null && _scheduledTime != null) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.teal.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.teal.shade200),
                  ),
                  child: Column(
                    children: [
                      Text(
                        'Current Schedule:',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _formatScheduledDateTime(),
                        style: TextStyle(color: Colors.teal.shade700),
                      ),
                      if (_linkedCalendarEvent != null) ...[
                        const SizedBox(height: 8),
                        InkWell(
                          onTap: () {
                            Navigator.pop(context);
                            _navigateToCalendarEvent();
                          },
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.green.shade50,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: Colors.green.shade200),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.event, color: Colors.green, size: 16),
                                const SizedBox(width: 6),
                                Text(
                                  'Open Calendar Event',
                                  style: TextStyle(
                                    color: Colors.green.shade700,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Icon(Icons.arrow_forward_ios, size: 10, color: Colors.green),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],

              ListTile(
                leading: Icon(Icons.calendar_today, color: Colors.teal),
                title: Text(_scheduledDate?.day != null
                    ? '${_scheduledDate!.day}/${_scheduledDate!.month}/${_scheduledDate!.year}'
                    : 'Select Date'),
                trailing: Icon(Icons.arrow_forward_ios, size: 16),
                onTap: () async {
                  Navigator.pop(context);
                  await _selectScheduledDate();
                  _showScheduleDialog();
                },
              ),

              ListTile(
                leading: Icon(Icons.access_time, color: Colors.teal),
                title: Text(_scheduledTime != null
                    ? _formatScheduledDateTime().split(' at ').last
                    : 'Select Time'),
                trailing: Icon(Icons.arrow_forward_ios, size: 16),
                onTap: () async {
                  Navigator.pop(context);
                  await _selectScheduledTime();
                  _showScheduleDialog();
                },
              ),
            ],
          ),
        ),
        actions: [
          if (_scheduledDate != null && _scheduledTime != null)
            TextButton(
              onPressed: () async {
                Navigator.pop(context);
                setState(() {
                  _scheduledDate = null;
                  _scheduledTime = null;
                });
                await _saveScheduling();
              },
              child: Text('Remove', style: TextStyle(color: Colors.red)),
            ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          if (_scheduledDate != null && _scheduledTime != null)
            TextButton(
              onPressed: () async {
                Navigator.pop(context);
                await _saveScheduling();
              },
              child: const Text('Save'),
            ),
        ],
      ),
    );
  }

  void _saveTitle() async {
    await DatabaseHelper.instance.updateTaskLocation(
      TaskLocation(
        id: widget.taskLocation.id,
        latitude: _selectedLocation?.latitude ?? widget.taskLocation.latitude,
        longitude: _selectedLocation?.longitude ?? widget.taskLocation.longitude,
        title: _titleController.text.trim(),
        taskItems: widget.taskLocation.taskItems,
        colorHex: '#${_selectedColor.value.toRadixString(16).substring(2)}',
        scheduledDateTime: widget.taskLocation.scheduledDateTime,
        linkedCalendarEventId: widget.taskLocation.linkedCalendarEventId,
      ),
    );
    Navigator.pop(context, true);
  }

  void _deleteCompletedTasks() async {
    setState(() {
      final newTaskItems = <String>[];

      for (int i = 0; i < widget.taskLocation.taskItems.length; i++) {
        if (!_checkedItems[i]) {
          newTaskItems.add(widget.taskLocation.taskItems[i]);
        }
      }

      widget.taskLocation.taskItems
        ..clear()
        ..addAll(newTaskItems);
      _syncCheckedItems();
    });

    await DatabaseHelper.instance.updateTaskLocation(
      TaskLocation(
        id: widget.taskLocation.id,
        latitude: widget.taskLocation.latitude,
        longitude: widget.taskLocation.longitude,
        title: _titleController.text.trim(),
        taskItems: widget.taskLocation.taskItems,
        colorHex: widget.taskLocation.colorHex,
        scheduledDateTime: widget.taskLocation.scheduledDateTime,
        linkedCalendarEventId: widget.taskLocation.linkedCalendarEventId,
      ),
    );

    _hasChanges = true;
  }

  void _addNewItem() async {
    final newItem = _newItemController.text.trim();
    if (newItem.isNotEmpty) {
      widget.taskLocation.taskItems.add(newItem);
      _newItemController.clear();
      _syncCheckedItems();

      setState(() {});

      await DatabaseHelper.instance.updateTaskLocation(
        TaskLocation(
          id: widget.taskLocation.id,
          latitude: widget.taskLocation.latitude,
          longitude: widget.taskLocation.longitude,
          title: _titleController.text.trim(),
          taskItems: widget.taskLocation.taskItems,
          colorHex: widget.taskLocation.colorHex,
          scheduledDateTime: widget.taskLocation.scheduledDateTime,
          linkedCalendarEventId: widget.taskLocation.linkedCalendarEventId,
        ),
      );

      _hasChanges = true;
      FocusScope.of(context).requestFocus(_newItemFocusNode);
    }
  }

  void _deleteEntireTask() async {
    await DatabaseHelper.instance.deleteTaskLocation(widget.taskLocation.id!);
    Navigator.pop(context, true);
  }

  void _shareTask() {
    final items = widget.taskLocation.taskItems;
    final taskText = StringBuffer();
    taskText.writeln("📝 Task: ${_titleController.text.trim()}");
    taskText.writeln("📍 Location: ${widget.taskLocation.latitude}, ${widget.taskLocation.longitude}");

    if (widget.taskLocation.hasScheduledTime) {
      taskText.writeln("⏰ Scheduled: ${widget.taskLocation.formattedScheduledTime}");
    }

    taskText.writeln("✅ Items:");
    for (var item in items) {
      taskText.writeln("• $item");
    }

    Share.share(taskText.toString());
  }

  Future<void> _exportTaskAsFile() async {
    try {
      final task = widget.taskLocation;

      final exportMap = {
        "id": task.id,
        "title": task.title,
        "latitude": task.latitude,
        "longitude": task.longitude,
        "colorHex": task.colorHex,
        "taskItems": task.taskItems,
        "scheduledDateTime": task.scheduledDateTime?.toIso8601String(),
        "linkedCalendarEventId": task.linkedCalendarEventId,
      };

      final jsonString = jsonEncode(exportMap);
      final directory = await getTemporaryDirectory();
      final safeTitle = task.title.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
      final filePath = '${directory.path}/$safeTitle.json';

      final file = File(filePath);
      await file.writeAsString(jsonString);

      final xfile = XFile(file.path, mimeType: 'application/json');

      await Share.shareXFiles([xfile], text: 'Exported task: ${task.title}');
    } catch (e) {
      print("Export error: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error exporting task: $e')),
      );
    }
  }

  void _selectLocation() async {
    FocusScope.of(context).unfocus();

    final Map<String, dynamic> taskState = {
      'taskId': widget.taskLocation.id,
      'title': _titleController.text.trim(),
      'items': List<String>.from(widget.taskLocation.taskItems),
      'selectedColor': _selectedColor.value,
      'scheduledDate': _scheduledDate?.toIso8601String(),
      'scheduledTime': _scheduledTime != null ?
      {'hour': _scheduledTime!.hour, 'minute': _scheduledTime!.minute} : null,
      'originalLocation': {
        'latitude': widget.taskLocation.latitude,
        'longitude': widget.taskLocation.longitude,
      },
      'selectedLocation': _selectedLocation != null ? {
        'latitude': _selectedLocation!.latitude,
        'longitude': _selectedLocation!.longitude,
      } : null,
      'selectedLocationName': _selectedLocationName,
      'linkedCalendarEventId': widget.taskLocation.linkedCalendarEventId,
      'isEditMode': true,
    };

    Navigator.pop(context, {
      'action': 'openLocationSearchForEdit',
      'taskState': taskState,
    });
  }

  void _showColorPicker() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Choose Task Color'),
          content: SizedBox(
            width: 280,
            child: Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                Colors.red,
                Colors.green,
                Colors.blue,
                Colors.orange,
                Colors.purple,
                Colors.teal,
                Colors.pink,
                Colors.amber,
                Colors.indigo,
                Colors.cyan,
                Colors.lime,
                Colors.deepOrange,
              ].map((color) => GestureDetector(
                onTap: () async {
                  setState(() {
                    _selectedColor = color;
                  });
                  Navigator.pop(context);

                  await _updateTaskLocation();
                  _hasChanges = true;
                  _createMapMarkers();

                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Row(
                        children: [
                          Icon(Icons.palette, color: Colors.white),
                          SizedBox(width: 8),
                          Text('Task color updated'),
                          SizedBox(width: 8),
                          Container(
                            width: 16,
                            height: 16,
                            decoration: BoxDecoration(
                              color: color,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 1),
                            ),
                          ),
                        ],
                      ),
                      backgroundColor: Colors.blue,
                      duration: Duration(seconds: 2),
                    ),
                  );
                },
                child: Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: _selectedColor == color ? Colors.black : Colors.grey.shade300,
                      width: _selectedColor == color ? 3 : 1,
                    ),
                  ),
                  child: _selectedColor == color
                      ? const Icon(Icons.check, color: Colors.white, size: 24)
                      : null,
                ),
              )).toList(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
          ],
        );
      },
    );
  }

  void _showTips() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Row(
            children: [
              Icon(Icons.lightbulb, color: Colors.teal),
              const SizedBox(width: 8),
              const Text('Task Tips'),
            ],
          ),
          content: SizedBox(
            width: 300,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildTipItem(Icons.edit, 'Edit task title',
                    'Change the task name at any time'),
                const SizedBox(height: 12),
                _buildTipItem(Icons.add_task, 'Add more items',
                    'Break down your task into smaller steps'),
                const SizedBox(height: 12),
                _buildTipItem(Icons.schedule, 'Schedule your task',
                    'Set a date and time to get calendar reminders'),
                const SizedBox(height: 12),
                _buildTipItem(Icons.location_on, 'Update location',
                    'Move task to a different location'),
                const SizedBox(height: 12),
                _buildTipItem(Icons.palette, 'Change colors',
                    'Use colors to categorize your tasks'),
                const SizedBox(height: 12),
                _buildTipItem(Icons.check_box, 'Mark completed',
                    'Check off items as you complete them'),
                const SizedBox(height: 12),
                _buildTipItem(Icons.delete_forever, 'Clean up',
                    'Delete completed items to keep list clean'),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Got it!'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildTipItem(IconData icon, String title, String description) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: Colors.teal, size: 20),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              Text(description, style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _updateTaskLocation() async {
    final updatedTask = TaskLocation(
      id: widget.taskLocation.id,
      latitude: _selectedLocation?.latitude ?? widget.taskLocation.latitude,
      longitude: _selectedLocation?.longitude ?? widget.taskLocation.longitude,
      title: _titleController.text.trim(),
      taskItems: widget.taskLocation.taskItems,
      colorHex: '#${_selectedColor.value.toRadixString(16).substring(2)}',
     scheduledDateTime: widget.taskLocation.scheduledDateTime,
     linkedCalendarEventId: widget.taskLocation.linkedCalendarEventId,
   );

   await DatabaseHelper.instance.updateTaskLocation(updatedTask);
 }

 // HYBRID MAP PREVIEW - choose correct widget based on provider
 Widget _buildMapPreview() {
   if (_currentMapProvider == MapProvider.googleMaps) {
     return _buildGoogleMapPreview();
   } else {
     return _buildOSMMapPreview();
   }
 }

 // Google Maps preview
 Widget _buildGoogleMapPreview() {
   return gmaps.GoogleMap(
     onMapCreated: (controller) {
       _googleMapController = controller;
       print('✅ TASK DETAIL: Google Map controller ready');
     },
     initialCameraPosition: gmaps.CameraPosition(
       target: _selectedLocation?.toGoogleMaps() ?? gmaps.LatLng(widget.taskLocation.latitude, widget.taskLocation.longitude),
       zoom: 15,
     ),
     markers: _googleMarkers,
     myLocationEnabled: false,
     myLocationButtonEnabled: false,
     zoomControlsEnabled: false,
     mapToolbarEnabled: false,
     compassEnabled: false,
     rotateGesturesEnabled: false,
     scrollGesturesEnabled: true,
     zoomGesturesEnabled: true,
     tiltGesturesEnabled: false,
     mapType: gmaps.MapType.normal,
   );
 }

 // OpenStreetMap preview  
 Widget _buildOSMMapPreview() {
   return OSMMapWidget(
     initialCameraPosition: OSMCameraPosition(
       target: _selectedLocation?.toOpenStreetMap() ?? 
               ll.LatLng(widget.taskLocation.latitude, widget.taskLocation.longitude),
       zoom: 15.0,
     ),
     markers: _osmMarkers,
     onMapCreated: (controller) {
       _osmMapController = controller;
       print('✅ TASK DETAIL: OSM Map controller ready');
     },
     myLocationEnabled: false,
     myLocationButtonEnabled: false,
   );
 }

 @override
 Widget build(BuildContext context) {
   List<Widget> activeTasks = [];
   List<Widget> completedTasks = [];

   for (int i = 0; i < widget.taskLocation.taskItems.length; i++) {
     final itemWidget = Card(
       margin: const EdgeInsets.only(bottom: 8),
       color: _checkedItems[i] ? Colors.grey.shade100 : Colors.grey.shade50,
       child: CheckboxListTile(
         value: _checkedItems[i],
         title: Text(
           widget.taskLocation.taskItems[i],
           style: _checkedItems[i]
               ? const TextStyle(decoration: TextDecoration.lineThrough)
               : const TextStyle(decoration: TextDecoration.none),
         ),
         activeColor: _taskColor,
         onChanged: (bool? value) {
           setState(() {
             _checkedItems[i] = value ?? false;
           });
           _hasChanges = true;
         },
       ),
     );

     if (_checkedItems[i]) {
       completedTasks.add(itemWidget);
     } else {
       activeTasks.add(itemWidget);
     }
   }

   return WillPopScope(
     onWillPop: () async {
       if (widget.isLockScreenMode) {
         SystemNavigator.pop();
         return false;
       } else {
         if (_hasChanges) {
           Navigator.pop(context, true);
         } else {
           Navigator.pop(context, false);
         }
         return false;
       }
     },
     child: Scaffold(
       appBar: AppBar(
         title: Text('Task Details (${_currentMapProvider.name})'),
         backgroundColor: Colors.teal,
         foregroundColor: Colors.white,
         leading: IconButton(
           icon: const Icon(Icons.arrow_back),
           onPressed: () {
             if (_hasChanges) {
               Navigator.pop(context, true);
             } else {
               Navigator.pop(context, false);
             }
           },
         ),
         actions: [
           IconButton(
             icon: const Icon(Icons.ios_share),
             onPressed: _exportTaskAsFile,
             tooltip: 'Export as File',
           ),
           IconButton(
             icon: const Icon(Icons.share),
             onPressed: _shareTask,
             tooltip: 'Share Task',
           ),
           IconButton(
             icon: const Icon(Icons.save),
             onPressed: _saveTitle,
             tooltip: 'Save Changes',
           ),
           IconButton(
             icon: const Icon(Icons.delete),
             onPressed: _deleteEntireTask,
             tooltip: 'Delete Task',
           ),
         ],
       ),
       body: Column(
         children: [
           // HYBRID MAP PREVIEW - show current provider
           Container(
             height: 200,
             child: _buildMapPreview(),
           ),

           // Task detail form
           Expanded(
             child: Padding(
               padding: const EdgeInsets.all(16.0),
               child: Column(
                 children: [
                   // Main card container
                   Card(
                     elevation: 4,
                     child: Padding(
                       padding: const EdgeInsets.all(20.0),
                       child: Column(
                         crossAxisAlignment: CrossAxisAlignment.start,
                         children: [
                           // Header with task icon and action buttons
                           Row(
                             children: [
                               Icon(Icons.task_alt, color: _taskColor, size: 32),
                               const Spacer(),

                               // Calendar/Schedule button
                               IconButton(
                                 onPressed: () {
                                   if (widget.taskLocation.hasScheduledTime || _linkedCalendarEvent != null) {
                                     if (_linkedCalendarEvent != null) {
                                       _navigateToCalendarEvent();
                                     } else {
                                       _showScheduleDialog();
                                     }
                                   } else {
                                     _showScheduleDialog();
                                   }
                                 },
                                 icon: Icon(
                                   widget.taskLocation.hasScheduledTime
                                       ? Icons.event
                                       : Icons.schedule,
                                   color: widget.taskLocation.hasScheduledTime
                                       ? Colors.green
                                       : Colors.orange,
                                 ),
                                 tooltip: widget.taskLocation.hasScheduledTime
                                     ? 'View Schedule'
                                     : 'Add Schedule',
                               ),

                               // Location button
                               IconButton(
                                 onPressed: _selectLocation,
                                 icon: const Icon(Icons.location_on, color: Colors.blue),
                                 tooltip: 'Change Location',
                               ),

                               // Color picker button
                               IconButton(
                                 onPressed: _showColorPicker,
                                 icon: Icon(Icons.palette, color: _taskColor),
                                 tooltip: 'Change Color',
                               ),

                               // Tips button
                               IconButton(
                                 onPressed: _showTips,
                                 icon: const Icon(Icons.lightbulb_outline, color: Colors.orange),
                                 tooltip: 'Show Tips',
                               ),
                             ],
                           ),

                           const SizedBox(height: 20),

                           // Task title
                           TextField(
                             controller: _titleController,
                             decoration: InputDecoration(
                               labelText: 'Task Title',
                               border: const OutlineInputBorder(),
                               prefixIcon: const Icon(Icons.title),
                               filled: true,
                               fillColor: Colors.grey.shade50,
                               focusedBorder: OutlineInputBorder(
                                 borderSide: BorderSide(color: _taskColor, width: 2),
                               ),
                             ),
                             onChanged: (value) {
                               _hasChanges = true;
                             },
                           ),

                           const SizedBox(height: 20),

                           // Add new item section
                           Row(
                             children: [
                               Expanded(
                                 child: TextField(
                                   controller: _newItemController,
                                   focusNode: _newItemFocusNode,
                                   decoration: const InputDecoration(
                                     labelText: 'Add New Item',
                                     hintText: 'Enter new task item',
                                     border: OutlineInputBorder(),
                                     prefixIcon: Icon(Icons.add_task),
                                   ),
                                   onSubmitted: (_) => _addNewItem(),
                                 ),
                               ),
                               const SizedBox(width: 8),
                               FloatingActionButton.small(
                                 onPressed: _addNewItem,
                                 backgroundColor: Colors.teal,
                                 child: const Icon(Icons.add, color: Colors.white),
                               ),
                             ],
                           ),

                           const SizedBox(height: 20),
                         ],
                       ),
                     ),
                   ),

                   const SizedBox(height: 16),

                   // Task items section
                   Expanded(
                     child: SingleChildScrollView(
                       child: Column(
                         crossAxisAlignment: CrossAxisAlignment.start,
                         children: [
                           // Active tasks
                           if (activeTasks.isNotEmpty) ...[
                             Text(
                               'Active Tasks (${activeTasks.length})',
                               style: const TextStyle(
                                 fontWeight: FontWeight.bold,
                                 fontSize: 18,
                               ),
                             ),
                             const SizedBox(height: 12),
                             ...activeTasks,
                           ],

                           // Completed tasks
                           if (completedTasks.isNotEmpty) ...[
                             const SizedBox(height: 24),
                             Text(
                               'Completed Tasks (${completedTasks.length})',
                               style: const TextStyle(
                                 fontWeight: FontWeight.bold,
                                 fontSize: 18,
                               ),
                             ),
                             const SizedBox(height: 12),
                             ...completedTasks,

                             const SizedBox(height: 20),
                             SizedBox(
                               width: double.infinity,
                               child: ElevatedButton.icon(
                                 onPressed: _deleteCompletedTasks,
                                 icon: const Icon(Icons.delete_forever),
                                 label: const Text('Delete Completed Tasks'),
                                 style: ElevatedButton.styleFrom(
                                   backgroundColor: Colors.red.shade600,
                                   foregroundColor: Colors.white,
                                   padding: const EdgeInsets.symmetric(vertical: 16),
                                   textStyle: const TextStyle(fontSize: 16),
                                 ),
                               ),
                             ),
                           ],

                           // Empty state
                           if (activeTasks.isEmpty && completedTasks.isEmpty) ...[
                             Center(
                               child: Column(
                                 children: [
                                   const SizedBox(height: 40),
                                   Icon(
                                     Icons.task_alt,
                                     size: 64,
                                     color: Colors.grey.shade400,
                                   ),
                                   const SizedBox(height: 16),
                                   Text(
                                     'No task items yet',
                                     style: TextStyle(
                                       fontSize: 18,
                                       color: Colors.grey.shade600,
                                     ),
                                   ),
                                   const SizedBox(height: 8),
                                   Text(
                                     'Add your first task item above',
                                     style: TextStyle(
                                       fontSize: 14,
                                       color: Colors.grey.shade500,
                                     ),
                                   ),
                                 ],
                               ),
                             ),
                           ],
                         ],
                       ),
                     ),
                   ),
                 ],
               ),
             ),
           ),
         ],
       ),
     ),
   );
 }
}

// TaskDetailScreenWithState class - simplified version for edited tasks
class TaskDetailScreenWithState extends StatefulWidget {
 final TaskLocation taskLocation;
 final gmaps.LatLng selectedLocation;
 final String selectedLocationName;
 final Map<String, dynamic> savedState;
 final bool isLockScreenMode;

 const TaskDetailScreenWithState({
   Key? key,
   required this.taskLocation,
   required this.selectedLocation,
   required this.selectedLocationName,
   required this.savedState,
   this.isLockScreenMode = false,
 }) : super(key: key);

 @override
 State<TaskDetailScreenWithState> createState() => _TaskDetailScreenWithStateState();
}

class _TaskDetailScreenWithStateState extends State<TaskDetailScreenWithState> {
 late List<bool> _checkedItems;
 late TextEditingController _titleController;
 final TextEditingController _newItemController = TextEditingController();
 final FocusNode _newItemFocusNode = FocusNode();
 UniversalLatLng? _selectedLocation;
 String? _selectedLocationName;
 Color _selectedColor = Colors.teal;
 bool _hasChanges = false;

 // Map provider selection
 MapProvider _currentMapProvider = MapProvider.googleMaps;

 // Google Maps controllers
 gmaps.GoogleMapController? _googleMapController;
 Set<gmaps.Marker> _googleMarkers = {};
 
 // OpenStreetMap controllers  
 osm.MapController? _osmMapController;
 Set<OSMMarker> _osmMarkers = {};

 @override
 void initState() {
   super.initState();
   _loadMapProviderSetting();
   _restoreStateFromSavedData();
   _syncCheckedItems();
 }

 @override
 void dispose() {
   _titleController.dispose();
   _newItemController.dispose();
   _newItemFocusNode.dispose();
   super.dispose();
 }

 // Load map provider setting
 Future<void> _loadMapProviderSetting() async {
   try {
     final prefs = await SharedPreferences.getInstance();
     final useOSM = prefs.getBool('use_openstreetmap') ?? false;
     
     setState(() {
       _currentMapProvider = useOSM ? MapProvider.openStreetMap : MapProvider.googleMaps;
     });

     // Initialize markers after loading provider
     Future.delayed(Duration(milliseconds: 300), () {
       _createMapMarkers();
     });

     print('🗺️ TASK DETAIL WITH STATE: Loaded map provider: ${_currentMapProvider.name}');
   } catch (e) {
     print('Error loading map provider setting: $e');
     _currentMapProvider = MapProvider.googleMaps;
     Future.delayed(Duration(milliseconds: 300), () {
       _createMapMarkers();
     });
   }
 }

 void _createMapMarkers() {
   if (_selectedLocation == null) return;

   if (_currentMapProvider == MapProvider.googleMaps) {
     _createGoogleMarkers();
   } else {
     _createOSMMarkers();
   }
 }

 void _createGoogleMarkers() {
   if (_selectedLocation == null) return;

   final marker = gmaps.Marker(
     markerId: const gmaps.MarkerId('task_location'),
     position: _selectedLocation!.toGoogleMaps(),
     infoWindow: gmaps.InfoWindow(
       title: widget.taskLocation.title,
       snippet: 'Updated task location',
     ),
     icon: gmaps.BitmapDescriptor.defaultMarkerWithHue(gmaps.BitmapDescriptor.hueGreen),
   );

   setState(() {
     _googleMarkers = {marker};
   });
 }

 void _createOSMMarkers() {
   if (_selectedLocation == null) return;

   final marker = OSMMarker(
     markerId: 'task_location',
     position: _selectedLocation!.toOpenStreetMap(),
     title: widget.taskLocation.title,
     child: OSMConverter.createDefaultMarker(color: _selectedColor),
   );

   setState(() {
     _osmMarkers = {marker};
   });
 }

 void _restoreStateFromSavedData() {
   final savedState = widget.savedState;

   _titleController = TextEditingController(text: savedState['title'] ?? widget.taskLocation.title);
   _selectedLocation = UniversalLatLng.fromGoogleMaps(widget.selectedLocation);
   _selectedLocationName = widget.selectedLocationName;
   _selectedColor = Color(savedState['selectedColor'] ?? Colors.teal.value);
   _hasChanges = true;
 }

 void _syncCheckedItems() {
   _checkedItems = List<bool>.filled(widget.taskLocation.taskItems.length, false);
 }

 // HYBRID MAP PREVIEW
 Widget _buildMapPreview() {
   if (_currentMapProvider == MapProvider.googleMaps) {
     return _buildGoogleMapPreview();
   } else {
     return _buildOSMMapPreview();
   }
 }

 Widget _buildGoogleMapPreview() {
   return gmaps.GoogleMap(
     onMapCreated: (controller) {
       _googleMapController = controller;
     },
     initialCameraPosition: gmaps.CameraPosition(
       target: _selectedLocation?.toGoogleMaps() ?? widget.selectedLocation,
       zoom: 15,
     ),
     markers: _googleMarkers,
     myLocationEnabled: false,
     myLocationButtonEnabled: false,
     zoomControlsEnabled: false,
     mapToolbarEnabled: false,
     compassEnabled: false,
     rotateGesturesEnabled: false,
     scrollGesturesEnabled: true,
     zoomGesturesEnabled: true,
     tiltGesturesEnabled: false,
     mapType: gmaps.MapType.normal,
   );
 }

 Widget _buildOSMMapPreview() {
   return OSMMapWidget(
     initialCameraPosition: OSMCameraPosition(
       target: _selectedLocation?.toOpenStreetMap() ?? 
               ll.LatLng(widget.selectedLocation.latitude, widget.selectedLocation.longitude),
       zoom: 15.0,
     ),
     markers: _osmMarkers,
     onMapCreated: (controller) {
       _osmMapController = controller;
     },
     myLocationEnabled: false,
     myLocationButtonEnabled: false,
   );
 }

 void _addNewItem() async {
   final newItem = _newItemController.text.trim();
   if (newItem.isNotEmpty) {
     widget.taskLocation.taskItems.add(newItem);
     _newItemController.clear();
     _syncCheckedItems();
     setState(() {});
     await _updateTaskLocation();
     _hasChanges = true;
     FocusScope.of(context).requestFocus(_newItemFocusNode);
   }
 }

 Future<void> _updateTaskLocation() async {
   final updatedTask = TaskLocation(
     id: widget.taskLocation.id,
     latitude: _selectedLocation?.latitude ?? widget.taskLocation.latitude,
     longitude: _selectedLocation?.longitude ?? widget.taskLocation.longitude,
     title: _titleController.text.trim(),
     taskItems: widget.taskLocation.taskItems,
     colorHex: '#${_selectedColor.value.toRadixString(16).substring(2)}',
     scheduledDateTime: widget.taskLocation.scheduledDateTime,
     linkedCalendarEventId: widget.taskLocation.linkedCalendarEventId,
   );

   await DatabaseHelper.instance.updateTaskLocation(updatedTask);
 }

 @override
 Widget build(BuildContext context) {
   List<Widget> activeTasks = [];
   List<Widget> completedTasks = [];

   for (int i = 0; i < widget.taskLocation.taskItems.length; i++) {
     final itemWidget = Card(
       margin: const EdgeInsets.only(bottom: 8),
       color: _checkedItems[i] ? Colors.grey.shade100 : Colors.grey.shade50,
       child: CheckboxListTile(
         value: _checkedItems[i],
         title: Text(
           widget.taskLocation.taskItems[i],
           style: _checkedItems[i]
               ? const TextStyle(decoration: TextDecoration.lineThrough)
               : const TextStyle(decoration: TextDecoration.none),
         ),
         activeColor: _selectedColor,
         onChanged: (bool? value) {
           setState(() {
             _checkedItems[i] = value ?? false;
           });
           _hasChanges = true;
         },
       ),
     );

     if (_checkedItems[i]) {
       completedTasks.add(itemWidget);
     } else {
       activeTasks.add(itemWidget);
     }
   }

   return WillPopScope(
     onWillPop: () async {
       if (widget.isLockScreenMode) {
         SystemNavigator.pop();
         return false;
       } else {
         if (_hasChanges) {
           Navigator.pop(context, {
             'refresh': true,
             'focusLocation': _selectedLocation?.toGoogleMaps(),
           });
         } else {
           Navigator.pop(context, false);
         }
         return false;
       }
     },
     child: Scaffold(
       appBar: AppBar(
         title: Text('Task Details (${_currentMapProvider.name})'),
         backgroundColor: Colors.teal,
         foregroundColor: Colors.white,
         leading: IconButton(
           icon: const Icon(Icons.arrow_back),
           onPressed: () {
             if (_hasChanges) {
               Navigator.pop(context, {
                 'refresh': true,
                 'focusLocation': _selectedLocation?.toGoogleMaps(),
               });
             } else {
               Navigator.pop(context, false);
             }
           },
         ),
         actions: [
           IconButton(
             icon: const Icon(Icons.save),
             onPressed: () async {
               await _updateTaskLocation();
               Navigator.pop(context, {
                 'refresh': true,
                 'focusLocation': _selectedLocation?.toGoogleMaps(),
               });
             },
             tooltip: 'Save Changes',
           ),
         ],
       ),
       body: Column(
         children: [
           // HYBRID MAP PREVIEW
           Container(
             height: 200,
             child: _buildMapPreview(),
           ),

           // Task detail form with location banner
           Expanded(
             child: Padding(
               padding: const EdgeInsets.all(16.0),
               child: Column(
                 children: [
                   // Location info banner
                   if (_selectedLocationName != null) ...[
                     Container(
                       padding: const EdgeInsets.all(12),
                       decoration: BoxDecoration(
                         color: Colors.blue.shade50,
                         borderRadius: BorderRadius.circular(8),
                         border: Border.all(color: Colors.blue.shade200),
                       ),
                       child: Row(
                         children: [
                           Icon(Icons.location_on, color: Colors.blue, size: 20),
                           const SizedBox(width: 8),
                           Expanded(
                             child: Column(
                               crossAxisAlignment: CrossAxisAlignment.start,
                               children: [
                                 Text(
                                   'Updated Location:',
                                   style: TextStyle(
                                     fontSize: 12,
                                     fontWeight: FontWeight.bold,
                                     color: Colors.blue.shade700,
                                   ),
                                 ),
                                 Text(
                                   _selectedLocationName!,
                                   style: TextStyle(
                                     fontSize: 14,
                                     color: Colors.blue.shade600,
                                   ),
                                 ),
                               ],
                             ),
                           ),
                         ],
                       ),
                     ),
                     const SizedBox(height: 16),
                   ],

                   // Simplified main card
                   Card(
                     elevation: 4,
                     child: Padding(
                       padding: const EdgeInsets.all(20.0),
                       child: Column(
                         crossAxisAlignment: CrossAxisAlignment.start,
                         children: [
                           // Task title
                           TextField(
                             controller: _titleController,
                             decoration: InputDecoration(
                               labelText: 'Task Title',
                               border: const OutlineInputBorder(),
                               prefixIcon: const Icon(Icons.title),
                               filled: true,
                               fillColor: Colors.grey.shade50,
                               focusedBorder: OutlineInputBorder(
                                 borderSide: BorderSide(color: _selectedColor, width: 2),
                               ),
                             ),
                             onChanged: (value) {
                               _hasChanges = true;
                             },
                           ),

                           const SizedBox(height: 20),

                           // Add new item section
                           Row(
                             children: [
                               Expanded(
                                 child: TextField(
                                   controller: _newItemController,
                                   focusNode: _newItemFocusNode,
                                   decoration: const InputDecoration(
                                     labelText: 'Add New Item',
                                     hintText: 'Enter new task item',
                                     border: OutlineInputBorder(),
                                     prefixIcon: Icon(Icons.add_task),
                                   ),
                                   onSubmitted: (_) => _addNewItem(),
                                 ),
                               ),
                               const SizedBox(width: 8),
                               FloatingActionButton.small(
                                 onPressed: _addNewItem,
                                 backgroundColor: Colors.teal,
                                 child: const Icon(Icons.add, color: Colors.white),
                               ),
                             ],
                           ),
                         ],
                       ),
                     ),
                   ),

                   const SizedBox(height: 16),

                   // Task items
                   Expanded(
                     child: SingleChildScrollView(
                       child: Column(
                         crossAxisAlignment: CrossAxisAlignment.start,
                         children: [
                           if (activeTasks.isNotEmpty) ...[
                             Text(
                               'Active Tasks (${activeTasks.length})',
                               style: const TextStyle(
                                 fontWeight: FontWeight.bold,
                                 fontSize: 18,
                               ),
                             ),
                             const SizedBox(height: 12),
                             ...activeTasks,
                           ],

                           if (completedTasks.isNotEmpty) ...[
                             const SizedBox(height: 24),
                             Text(
                               'Completed Tasks (${completedTasks.length})',
                               style: const TextStyle(
                                 fontWeight: FontWeight.bold,
                                 fontSize: 18,
                               ),
                             ),
                             const SizedBox(height: 12),
                             ...completedTasks,
                           ],

                           if (activeTasks.isEmpty && completedTasks.isEmpty) ...[
                             Center(
                               child: Column(
                                 children: [
                                   const SizedBox(height: 40),
                                   Icon(
                                     Icons.task_alt,
                                     size: 64,
                                     color: Colors.grey.shade400,
                                   ),
                                   const SizedBox(height: 16),
                                   Text(
                                     'No task items yet',
                                     style: TextStyle(
                                       fontSize: 18,
                                       color: Colors.grey.shade600,
                                     ),
                                   ),
                                 ],
                               ),
                             ),
                           ],
                         ],
                       ),
                     ),
                   ),
                 ],
               ),
             ),
           ),
         ],
       ),
     ),
   );
 }
}