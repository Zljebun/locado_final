import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:locado_final/helpers/database_helper.dart';
import 'package:locado_final/models/task_location.dart';
import 'package:locado_final/models/calendar_event.dart';
import 'package:locado_final/screens/notification_service.dart';
import 'search_location_screen.dart';
import '../services/geofencing_integration_helper.dart';
import 'package:locado_final/models/calendar_event.dart';
import 'package:locado_final/screens/notification_service.dart';
import '../services/geofencing_integration_helper.dart';

class TaskInputScreen extends StatefulWidget {
  final LatLng location;
  final String? locationName;

  const TaskInputScreen({Key? key, required this.location, this.locationName,}) : super(key: key);

  @override
  State<TaskInputScreen> createState() => _TaskInputScreenState();
}

class _TaskInputScreenState extends State<TaskInputScreen> {
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _itemController = TextEditingController();
  List<String> _taskItems = [];
  Color _selectedColor = Colors.teal;
  LatLng? _selectedLocation;
  String? _selectedLocationName;
  bool _isLoading = false;

  // 🆕 SCHEDULING STATE VARIABLES
  DateTime? _scheduledDate;
  TimeOfDay? _scheduledTime;
  bool _enableScheduling = false;

  final GlobalKey _addButtonKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _selectedLocation = widget.location;

    _selectedLocationName = widget.locationName; // Set location name from parameter

    // Auto-fill task title if location name is provided
    if (widget.locationName != null && widget.locationName!.isNotEmpty) {
      _titleController.text = widget.locationName!;
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _itemController.dispose();
    super.dispose();
  }

  void _addItem() {
    final text = _itemController.text.trim();
    if (text.isNotEmpty) {
      setState(() {
        _taskItems.add(text);
        _itemController.clear();
      });
    }
  }

  void _removeItem(int index) {
    setState(() {
      _taskItems.removeAt(index);
    });
  }

  // 🆕 DATE/TIME PICKER METHODS
  Future<void> _selectScheduledDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _scheduledDate ?? DateTime.now().add(Duration(hours: 1)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(Duration(days: 365)),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: Theme.of(context).colorScheme.copyWith(
              primary: Colors.teal,
            ),
          ),
          child: child!,
        );
      },
    );

    if (date != null) {
      setState(() {
        _scheduledDate = date;
        // Set default time if not set
        if (_scheduledTime == null) {
          final now = DateTime.now();
          _scheduledTime = TimeOfDay(hour: now.hour + 1, minute: 0);
        }
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
            colorScheme: Theme.of(context).colorScheme.copyWith(
              primary: Colors.teal,
            ),
          ),
          child: child!,
        );
      },
    );

    if (time != null) {
      setState(() {
        _scheduledTime = time;
        // Set default date if not set
        if (_scheduledDate == null) {
          _scheduledDate = DateTime.now().add(Duration(hours: 1));
        }
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

  // 🆕 SCHEDULE DIALOG
  void _showScheduleDialog() {
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Row(
            children: [
              Icon(Icons.schedule, color: Colors.teal),
              const SizedBox(width: 8),
              const Text('Task Schedule'),
            ],
          ),
          content: SizedBox(
            width: 300,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Enable/disable toggle
                SwitchListTile(
                  title: const Text('Schedule this task'),
                  value: _enableScheduling,
                  activeColor: Colors.teal,
                  onChanged: (value) {
                    setDialogState(() {
                      _enableScheduling = value;
                      if (!value) {
                        _scheduledDate = null;
                        _scheduledTime = null;
                      }
                    });
                    setState(() {
                      _enableScheduling = value;
                      if (!value) {
                        _scheduledDate = null;
                        _scheduledTime = null;
                      }
                    });
                  },
                ),

                if (_enableScheduling) ...[
                  const Divider(),

                  // Date picker
                  ListTile(
                    leading: Icon(Icons.calendar_today, color: Colors.teal),
                    title: Text(_scheduledDate != null
                        ? '${_scheduledDate!.day}/${_scheduledDate!.month}/${_scheduledDate!.year}'
                        : 'Select Date'),
                    trailing: Icon(Icons.arrow_forward_ios, size: 16),
                    onTap: () async {
                      Navigator.pop(context);
                      await _selectScheduledDate();
                      _showScheduleDialog();
                    },
                  ),

                  // Time picker
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

                  // Schedule summary
                  if (_scheduledDate != null && _scheduledTime != null) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.teal.shade50,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: Colors.teal.shade200),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.event, color: Colors.teal, size: 16),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'Scheduled: ${_formatScheduledDateTime()}',
                              style: TextStyle(
                                color: Colors.teal.shade700,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Done'),
            ),
          ],
        ),
      ),
    );
  }

  // 🎨 Color picker dialog
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
                onTap: () {
                  setState(() {
                    _selectedColor = color;
                  });
                  Navigator.pop(context);
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

  void _selectLocation() async {
    FocusScope.of(context).unfocus();

    // Prepare current task state for saving
    final Map<String, dynamic> taskState = {
      'title': _titleController.text.trim(),
      'items': List<String>.from(_taskItems),
      'selectedColor': _selectedColor.value,
      'scheduledDate': _scheduledDate?.toIso8601String(),
      'scheduledTime': _scheduledTime != null ?
      {'hour': _scheduledTime!.hour, 'minute': _scheduledTime!.minute} : null,
      'enableScheduling': _enableScheduling,
      'originalLocation': {
        'latitude': widget.location.latitude,
        'longitude': widget.location.longitude,
      },
      'selectedLocation': _selectedLocation != null ? {
        'latitude': _selectedLocation!.latitude,
        'longitude': _selectedLocation!.longitude,
      } : null,
      'selectedLocationName': _selectedLocationName,
    };

    // Close TaskInputScreen and go to HomeMapScreen with search mode
    Navigator.pop(context, {
      'action': 'openLocationSearch',
      'taskState': taskState,
    });
  }

  // 💡 Tips dialog
  void _showTips() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Row(
            children: [
              Icon(Icons.lightbulb, color: Colors.teal),
              const SizedBox(width: 8),
              const Text('Quick Tips'),
            ],
          ),
          content: SizedBox(
            width: 300,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildTipItem(Icons.title, 'Task titles are optional',
                    'Leave empty for auto-generated names'),
                const SizedBox(height: 12),
                _buildTipItem(Icons.list, 'Add multiple items',
                    'Break down your task into smaller steps'),
                const SizedBox(height: 12),
                _buildTipItem(Icons.schedule, 'Schedule your tasks',
                    'Set a date and time to get calendar reminders'),
                const SizedBox(height: 12),
                _buildTipItem(Icons.location_on, 'Search specific places',
                    'Find stores, addresses, or landmarks'),
                const SizedBox(height: 12),
                _buildTipItem(Icons.palette, 'Organize with colors',
                    'Use different colors to categorize tasks'),
                const SizedBox(height: 12),
                _buildTipItem(Icons.notifications, 'Smart notifications',
                    'Get alerted when you\'re near your task location'),
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

  // 🆕 AŽURIRANI _saveTask() METOD
  Future<void> _saveTask() async {
    final usedLocation = _selectedLocation ?? widget.location;
    final title = _titleController.text.trim();
    TaskLocation taskLocation;
    DateTime? scheduledDateTime;

    setState(() => _isLoading = true);

    // Create scheduled datetime if enabled
    if (_enableScheduling && _scheduledDate != null && _scheduledTime != null) {
      scheduledDateTime = DateTime(
        _scheduledDate!.year,
        _scheduledDate!.month,
        _scheduledDate!.day,
        _scheduledTime!.hour,
        _scheduledTime!.minute,
      );
    }

    // Kreiraj TaskLocation na osnovu inputa
    if (title.isEmpty && _taskItems.isEmpty) {
      final defaultTitle = _selectedLocationName ?? 'Task at ${usedLocation.latitude.toStringAsFixed(4)}, ${usedLocation.longitude.toStringAsFixed(4)}';

      taskLocation = TaskLocation(
        latitude: usedLocation.latitude,
        longitude: usedLocation.longitude,
        title: defaultTitle,
        taskItems: ['Visit this location'],
        colorHex: '#${_selectedColor.value.toRadixString(16).substring(2)}',
        scheduledDateTime: scheduledDateTime,
      );
    } else if (title.isNotEmpty && _taskItems.isEmpty) {
      taskLocation = TaskLocation(
        latitude: usedLocation.latitude,
        longitude: usedLocation.longitude,
        title: title,
        taskItems: ['Complete task'],
        colorHex: '#${_selectedColor.value.toRadixString(16).substring(2)}',
        scheduledDateTime: scheduledDateTime,
      );
    } else if (title.isEmpty && _taskItems.isNotEmpty) {
      final defaultTitle = _selectedLocationName ?? 'Task at location';

      taskLocation = TaskLocation(
        latitude: usedLocation.latitude,
        longitude: usedLocation.longitude,
        title: defaultTitle,
        taskItems: _taskItems,
        colorHex: '#${_selectedColor.value.toRadixString(16).substring(2)}',
        scheduledDateTime: scheduledDateTime,
      );
    } else {
      // Normal case - both title and items
      taskLocation = TaskLocation(
        latitude: usedLocation.latitude,
        longitude: usedLocation.longitude,
        title: title,
        taskItems: _taskItems,
        colorHex: '#${_selectedColor.value.toRadixString(16).substring(2)}',
        scheduledDateTime: scheduledDateTime,
      );
    }

    try {
      // 1. Sačuvaj task u bazu
      final taskId = await DatabaseHelper.instance.addTaskLocation(taskLocation);
      taskLocation = taskLocation.copyWith(id: taskId);
      debugPrint('Task saved to database: ${taskLocation.title}');

      // 2. 🆕 NOVO: Kreiraj calendar event ako je zadato vreme
      if (scheduledDateTime != null) {
        final calendarEvent = CalendarEvent(
          title: taskLocation.generateCalendarEventTitle(),
          description: taskLocation.generateCalendarEventDescription(),
          dateTime: scheduledDateTime,
          reminderMinutes: [15], // Default 15min reminder
          colorHex: taskLocation.colorHex,
          linkedTaskLocationId: taskId,
        );

        final eventId = await DatabaseHelper.instance.addCalendarEvent(calendarEvent);

        // Link task to calendar event
        await DatabaseHelper.instance.linkTaskToCalendarEvent(taskId, eventId);

        // Schedule notifications
        final eventWithId = calendarEvent.copyWith(id: eventId);
        await NotificationService.scheduleEventReminders(eventWithId);

        debugPrint('✅ Created linked calendar event: ${calendarEvent.title}');

        // Show scheduling success message
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.event, color: Colors.white),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text('Task scheduled for ${_formatScheduledDateTime()}'),
                  ),
                ],
              ),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 3),
            ),
          );
        }
      }

      // 3. ✅ AUTOMATSKI GEOFENCING ZA NOVI TASK
      final helper = GeofencingIntegrationHelper.instance;
      if (helper.isInitialized && helper.isServiceRunning) {
        final success = await helper.addTaskLocationGeofence(taskLocation);
        if (success) {
          debugPrint('✅ Auto-added geofencing for new task: ${taskLocation.title}');
        } else {
          debugPrint('⚠️ Failed to auto-add geofencing for: ${taskLocation.title}');
        }
      } else {
        debugPrint('⚠️ Geofencing service not running - task saved without geofencing');
      }
    } catch (e) {
      debugPrint('❌ Error saving task or adding geofencing: $e');
    }

    setState(() => _isLoading = false);
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Add Task'),
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
        actions: [
          // Save button u app bar-u
          IconButton(
            onPressed: _isLoading ? null : _saveTask,
            icon: _isLoading
                ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
                : const Icon(Icons.save),
          ),
        ],
      ),
      resizeToAvoidBottomInset: true,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            // 🎯 MAIN CARD - All-in-one container
            Card(
              elevation: 4,
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header sa action buttons
                    Row(
                      children: [
                        Icon(Icons.task_alt, color: Colors.teal, size: 32),
                        const Spacer(),

                        // 📅 Schedule button
                        IconButton(
                          onPressed: _showScheduleDialog,
                          icon: Icon(
                            _enableScheduling ? Icons.event : Icons.schedule,
                            color: _enableScheduling ? Colors.green : Colors.orange,
                          ),
                          tooltip: _enableScheduling ? 'Edit Schedule' : 'Add Schedule',
                        ),

                        // 📍 Location button
                        IconButton(
                          onPressed: _selectLocation,
                          icon: const Icon(Icons.location_on, color: Colors.blue),
                          tooltip: 'Search Location',
                        ),

                        // 🎨 Color button
                        IconButton(
                          onPressed: _showColorPicker,
                          icon: Icon(Icons.palette, color: _selectedColor),
                          tooltip: 'Choose Color',
                        ),

                        // 💡 Tips button
                        IconButton(
                          onPressed: _showTips,
                          icon: const Icon(Icons.lightbulb_outline, color: Colors.orange),
                          tooltip: 'Show Tips',
                        ),
                      ],
                    ),

                    const SizedBox(height: 20),

                    if (_selectedLocationName != null) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.green.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.green.shade200),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.location_on, color: Colors.green, size: 20),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Selected Location:',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.green.shade700,
                                    ),
                                  ),
                                  Text(
                                    _selectedLocationName!,
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: Colors.green.shade600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              onPressed: _selectLocation,
                              icon: Icon(Icons.edit, color: Colors.green, size: 16),
                              tooltip: 'Change Location',
                              constraints: BoxConstraints(),
                              padding: EdgeInsets.zero,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],


                    // Task title
                    TextField(
                      controller: _titleController,
                      decoration: const InputDecoration(
                        labelText: 'Task Title (Optional)',
                        hintText: 'What do you need to do here?',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.title),
                      ),
                    ),

                    const SizedBox(height: 16),

                    // Add task item sekcija
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _itemController,
                            decoration: const InputDecoration(
                              labelText: 'Add Task Item',
                              hintText: 'e.g. Buy milk, Check schedule',
                              border: OutlineInputBorder(),
                              prefixIcon: Icon(Icons.add_task),
                            ),
                            onSubmitted: (_) => _addItem(),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          key: _addButtonKey,
                          child: FloatingActionButton.small(
                            heroTag: "add_item_button",
                            onPressed: _addItem,
                            backgroundColor: Colors.teal,
                            foregroundColor: Colors.white,
                            child: const Icon(Icons.add, size: 20),
                          ),
                        ),
                      ],
                    ),

                    // Task items list
                    if (_taskItems.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      // Task items list container
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 200),
                        child: ListView.builder(
                          shrinkWrap: true,
                          physics: const BouncingScrollPhysics(),
                          itemCount: _taskItems.length,
                          itemBuilder: (context, index) {
                            return Card(
                              margin: const EdgeInsets.only(bottom: 8),
                              color: Colors.grey.shade50,
                              child: ListTile(
                                leading: Icon(Icons.check_box_outline_blank,
                                    color: _selectedColor),
                                title: Text(_taskItems[index]),
                                trailing: IconButton(
                                  icon: const Icon(Icons.close, color: Colors.red, size: 20),
                                  onPressed: () => _removeItem(index),
                                ),
                                dense: true,
                                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                              ),
                            );
                          },
                        ),
                      ),
                    ],

                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Bottom save button (alternative)
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isLoading ? null : _saveTask,
                icon: _isLoading
                    ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
                    : const Icon(Icons.save),
                label: Text(_isLoading ? 'Saving...' : 'Save Task'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.teal,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  textStyle: const TextStyle(fontSize: 18),
                ),
              ),
            ),

            // Bottom padding za keyboard space
            SizedBox(height: MediaQuery.of(context).viewInsets.bottom > 0 ? 20 : 80),
          ],
        ),
      ),
    );
  }
}

class TaskInputScreenWithState extends StatefulWidget {
  final LatLng originalLocation;
  final LatLng selectedLocation;
  final String selectedLocationName;
  final Map<String, dynamic> savedState;

  const TaskInputScreenWithState({
    Key? key,
    required this.originalLocation,
    required this.selectedLocation,
    required this.selectedLocationName,
    required this.savedState,
  }) : super(key: key);

  @override
  State<TaskInputScreenWithState> createState() => _TaskInputScreenWithStateState();
}

class _TaskInputScreenWithStateState extends State<TaskInputScreenWithState> {
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _itemController = TextEditingController();
  List<String> _taskItems = [];
  Color _selectedColor = Colors.teal;
  LatLng? _selectedLocation;
  String? _selectedLocationName;
  bool _isLoading = false;

  // Scheduling state variables
  DateTime? _scheduledDate;
  TimeOfDay? _scheduledTime;
  bool _enableScheduling = false;

  final GlobalKey _addButtonKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _restoreStateFromSavedData();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _itemController.dispose();
    super.dispose();
  }

  void _restoreStateFromSavedData() {
    final savedState = widget.savedState;

    // Restore basic fields
    _titleController.text = savedState['title'] ?? '';
    _taskItems = List<String>.from(savedState['items'] ?? []);
    _selectedColor = Color(savedState['selectedColor'] ?? Colors.teal.value);
    _enableScheduling = savedState['enableScheduling'] ?? false;

    // Restore scheduling data
    if (savedState['scheduledDate'] != null) {
      _scheduledDate = DateTime.parse(savedState['scheduledDate']);
    }
    if (savedState['scheduledTime'] != null) {
      final timeData = savedState['scheduledTime'];
      _scheduledTime = TimeOfDay(
        hour: timeData['hour'],
        minute: timeData['minute'],
      );
    }

    // Set the new selected location
    _selectedLocation = widget.selectedLocation;
    _selectedLocationName = widget.selectedLocationName;

    // Auto-fill task title if empty and we have location name
    if (_titleController.text.trim().isEmpty &&
        widget.selectedLocationName.isNotEmpty) {
      _titleController.text = widget.selectedLocationName;
    }
  }

  // Copy all the methods from TaskInputScreen (same implementation)
  void _addItem() {
    final text = _itemController.text.trim();
    if (text.isNotEmpty) {
      setState(() {
        _taskItems.add(text);
        _itemController.clear();
      });
    }
  }

  void _removeItem(int index) {
    setState(() {
      _taskItems.removeAt(index);
    });
  }

  Future<void> _selectScheduledDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _scheduledDate ?? DateTime.now().add(Duration(hours: 1)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(Duration(days: 365)),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: Theme.of(context).colorScheme.copyWith(
              primary: Colors.teal,
            ),
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
            colorScheme: Theme.of(context).colorScheme.copyWith(
              primary: Colors.teal,
            ),
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

  void _showScheduleDialog() {
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Row(
            children: [
              Icon(Icons.schedule, color: Colors.teal),
              const SizedBox(width: 8),
              const Text('Task Schedule'),
            ],
          ),
          content: SizedBox(
            width: 300,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SwitchListTile(
                  title: const Text('Schedule this task'),
                  value: _enableScheduling,
                  activeColor: Colors.teal,
                  onChanged: (value) {
                    setDialogState(() {
                      _enableScheduling = value;
                      if (!value) {
                        _scheduledDate = null;
                        _scheduledTime = null;
                      }
                    });
                    setState(() {
                      _enableScheduling = value;
                      if (!value) {
                        _scheduledDate = null;
                        _scheduledTime = null;
                      }
                    });
                  },
                ),

                if (_enableScheduling) ...[
                  const Divider(),
                  ListTile(
                    leading: Icon(Icons.calendar_today, color: Colors.teal),
                    title: Text(_scheduledDate != null
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

                  if (_scheduledDate != null && _scheduledTime != null) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.teal.shade50,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: Colors.teal.shade200),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.event, color: Colors.teal, size: 16),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'Scheduled: ${_formatScheduledDateTime()}',
                              style: TextStyle(
                                color: Colors.teal.shade700,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Done'),
            ),
          ],
        ),
      ),
    );
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
                onTap: () {
                  setState(() {
                    _selectedColor = color;
                  });
                  Navigator.pop(context);
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

  // Modified _selectLocation to allow changing location again
  void _selectLocation() async {
    FocusScope.of(context).unfocus();

    // Prepare current task state for saving
    final Map<String, dynamic> taskState = {
      'title': _titleController.text.trim(),
      'items': List<String>.from(_taskItems),
      'selectedColor': _selectedColor.value,
      'scheduledDate': _scheduledDate?.toIso8601String(),
      'scheduledTime': _scheduledTime != null ?
      {'hour': _scheduledTime!.hour, 'minute': _scheduledTime!.minute} : null,
      'enableScheduling': _enableScheduling,
      'originalLocation': {
        'latitude': widget.originalLocation.latitude,
        'longitude': widget.originalLocation.longitude,
      },
      'selectedLocation': _selectedLocation != null ? {
        'latitude': _selectedLocation!.latitude,
        'longitude': _selectedLocation!.longitude,
      } : null,
      'selectedLocationName': _selectedLocationName,
    };

    // Close TaskInputScreen and go to HomeMapScreen with search mode
    Navigator.pop(context, {
      'action': 'openLocationSearch',
      'taskState': taskState,
    });
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
              const Text('Quick Tips'),
            ],
          ),
          content: SizedBox(
            width: 300,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildTipItem(Icons.title, 'Task titles are optional',
                    'Leave empty for auto-generated names'),
                const SizedBox(height: 12),
                _buildTipItem(Icons.list, 'Add multiple items',
                    'Break down your task into smaller steps'),
                const SizedBox(height: 12),
                _buildTipItem(Icons.schedule, 'Schedule your tasks',
                    'Set a date and time to get calendar reminders'),
                const SizedBox(height: 12),
                _buildTipItem(Icons.location_on, 'Search specific places',
                    'Find stores, addresses, or landmarks'),
                const SizedBox(height: 12),
                _buildTipItem(Icons.palette, 'Organize with colors',
                    'Use different colors to categorize tasks'),
                const SizedBox(height: 12),
                _buildTipItem(Icons.notifications, 'Smart notifications',
                    'Get alerted when you\'re near your task location'),
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

  // Copy the _saveTask method from original TaskInputScreen (same implementation)
  Future<void> _saveTask() async {
    final usedLocation = _selectedLocation ?? widget.originalLocation;
    final title = _titleController.text.trim();
    TaskLocation taskLocation;
    DateTime? scheduledDateTime;

    setState(() => _isLoading = true);

    // Create scheduled datetime if enabled
    if (_enableScheduling && _scheduledDate != null && _scheduledTime != null) {
      scheduledDateTime = DateTime(
        _scheduledDate!.year,
        _scheduledDate!.month,
        _scheduledDate!.day,
        _scheduledTime!.hour,
        _scheduledTime!.minute,
      );
    }

    // Create TaskLocation based on input
    if (title.isEmpty && _taskItems.isEmpty) {
      final defaultTitle = _selectedLocationName ?? 'Task at ${usedLocation.latitude.toStringAsFixed(4)}, ${usedLocation.longitude.toStringAsFixed(4)}';

      taskLocation = TaskLocation(
        latitude: usedLocation.latitude,
        longitude: usedLocation.longitude,
        title: defaultTitle,
        taskItems: ['Visit this location'],
        colorHex: '#${_selectedColor.value.toRadixString(16).substring(2)}',
        scheduledDateTime: scheduledDateTime,
      );
    } else if (title.isNotEmpty && _taskItems.isEmpty) {
      taskLocation = TaskLocation(
        latitude: usedLocation.latitude,
        longitude: usedLocation.longitude,
        title: title,
        taskItems: ['Complete task'],
        colorHex: '#${_selectedColor.value.toRadixString(16).substring(2)}',
        scheduledDateTime: scheduledDateTime,
      );
    } else if (title.isEmpty && _taskItems.isNotEmpty) {
      final defaultTitle = _selectedLocationName ?? 'Task at location';

      taskLocation = TaskLocation(
        latitude: usedLocation.latitude,
        longitude: usedLocation.longitude,
        title: defaultTitle,
        taskItems: _taskItems,
        colorHex: '#${_selectedColor.value.toRadixString(16).substring(2)}',
        scheduledDateTime: scheduledDateTime,
      );
    } else {
      // Normal case - both title and items
      taskLocation = TaskLocation(
        latitude: usedLocation.latitude,
        longitude: usedLocation.longitude,
        title: title,
        taskItems: _taskItems,
        colorHex: '#${_selectedColor.value.toRadixString(16).substring(2)}',
        scheduledDateTime: scheduledDateTime,
      );
    }

    try {
      // Save task to database
      final taskId = await DatabaseHelper.instance.addTaskLocation(taskLocation);
      taskLocation = taskLocation.copyWith(id: taskId);
      debugPrint('Task saved to database: ${taskLocation.title}');

      // Create calendar event if scheduled
      if (scheduledDateTime != null) {
        final calendarEvent = CalendarEvent(
          title: taskLocation.generateCalendarEventTitle(),
          description: taskLocation.generateCalendarEventDescription(),
          dateTime: scheduledDateTime,
          reminderMinutes: [15],
          colorHex: taskLocation.colorHex,
          linkedTaskLocationId: taskId,
        );

        final eventId = await DatabaseHelper.instance.addCalendarEvent(calendarEvent);
        await DatabaseHelper.instance.linkTaskToCalendarEvent(taskId, eventId);

        final eventWithId = calendarEvent.copyWith(id: eventId);
        await NotificationService.scheduleEventReminders(eventWithId);

        debugPrint('✅ Created linked calendar event: ${calendarEvent.title}');

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.event, color: Colors.white),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text('Task scheduled for ${_formatScheduledDateTime()}'),
                  ),
                ],
              ),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 3),
            ),
          );
        }
      }

      // Auto-add geofencing
      final helper = GeofencingIntegrationHelper.instance;
      if (helper.isInitialized && helper.isServiceRunning) {
        final success = await helper.addTaskLocationGeofence(taskLocation);
        if (success) {
          debugPrint('✅ Auto-added geofencing for new task: ${taskLocation.title}');
        } else {
          debugPrint('⚠️ Failed to auto-add geofencing for: ${taskLocation.title}');
        }
      } else {
        debugPrint('⚠️ Geofencing service not running - task saved without geofencing');
      }
    } catch (e) {
      debugPrint('❌ Error saving task or adding geofencing: $e');
    }

    setState(() => _isLoading = false);
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Add Task'),
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            onPressed: _isLoading ? null : _saveTask,
            icon: _isLoading
                ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
                : const Icon(Icons.save),
          ),
        ],
      ),
      resizeToAvoidBottomInset: true,
      body: SingleChildScrollView(
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
                    // Header with action buttons
                    Row(
                      children: [
                        Icon(Icons.task_alt, color: Colors.teal, size: 32),
                        const Spacer(),

                        // Schedule button
                        IconButton(
                          onPressed: _showScheduleDialog,
                          icon: Icon(
                            _enableScheduling ? Icons.event : Icons.schedule,
                            color: _enableScheduling ? Colors.green : Colors.orange,
                          ),
                          tooltip: _enableScheduling ? 'Edit Schedule' : 'Add Schedule',
                        ),

                        // Location button
                        IconButton(
                          onPressed: _selectLocation,
                          icon: const Icon(Icons.location_on, color: Colors.blue),
                          tooltip: 'Search Location',
                        ),

                        // Color button
                        IconButton(
                          onPressed: _showColorPicker,
                          icon: Icon(Icons.palette, color: _selectedColor),
                          tooltip: 'Choose Color',
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

                    // Location info banner (NEW)
                    if (_selectedLocationName != null) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.green.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.green.shade200),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.location_on, color: Colors.green, size: 20),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Selected Location:',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.green.shade700,
                                    ),
                                  ),
                                  Text(
                                    _selectedLocationName!,
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: Colors.green.shade600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              onPressed: _selectLocation,
                              icon: Icon(Icons.edit, color: Colors.green, size: 16),
                              tooltip: 'Change Location',
                              constraints: BoxConstraints(),
                              padding: EdgeInsets.zero,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],

                    // Task title
                    TextField(
                      controller: _titleController,
                      decoration: const InputDecoration(
                        labelText: 'Task Title (Optional)',
                        hintText: 'What do you need to do here?',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.title),
                      ),
                    ),

                    const SizedBox(height: 16),

                    // Add task item section
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _itemController,
                            decoration: const InputDecoration(
                              labelText: 'Add Task Item',
                              hintText: 'e.g. Buy milk, Check schedule',
                              border: OutlineInputBorder(),
                              prefixIcon: Icon(Icons.add_task),
                            ),
                            onSubmitted: (_) => _addItem(),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          key: _addButtonKey,
                          child: FloatingActionButton.small(
                            heroTag: "add_item_button_with_state",
                            onPressed: _addItem,
                            backgroundColor: Colors.teal,
                            foregroundColor: Colors.white,
                            child: const Icon(Icons.add, size: 20),
                          ),
                        ),
                      ],
                    ),

                    // Task items list
                    if (_taskItems.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 200),
                        child: ListView.builder(
                          shrinkWrap: true,
                          physics: const BouncingScrollPhysics(),
                          itemCount: _taskItems.length,
                          itemBuilder: (context, index) {
                            return Card(
                              margin: const EdgeInsets.only(bottom: 8),
                              color: Colors.grey.shade50,
                              child: ListTile(
                                leading: Icon(Icons.check_box_outline_blank,
                                    color: _selectedColor),
                                title: Text(_taskItems[index]),
                                trailing: IconButton(
                                  icon: const Icon(Icons.close, color: Colors.red, size: 20),
                                  onPressed: () => _removeItem(index),
                                ),
                                dense: true,
                                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                              ),
                            );
                          },
                        ),
                      ),
                    ],

                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Bottom save button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isLoading ? null : _saveTask,
                icon: _isLoading
                    ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
                    : const Icon(Icons.save),
                label: Text(_isLoading ? 'Saving...' : 'Save Task'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.teal,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  textStyle: const TextStyle(fontSize: 18),
                ),
              ),
            ),

            // Bottom padding
            SizedBox(height: MediaQuery.of(context).viewInsets.bottom > 0 ? 20 : 80),
          ],
        ),
      ),
    );
  }
}