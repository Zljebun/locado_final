// screens/general_task_detail_screen.dart

import 'package:flutter/material.dart';
import 'package:locado_final/models/general_task.dart';
import 'package:locado_final/models/calendar_event.dart';
import 'package:locado_final/helpers/database_helper.dart';
import 'package:locado_final/screens/notification_service.dart';
import 'package:share_plus/share_plus.dart';
import 'dart:io';
import 'dart:convert';
import 'package:path_provider/path_provider.dart';
import '../screens/event_details_screen.dart';
import 'package:flutter/services.dart';
import 'package:locado_final/models/task_location.dart';
import 'package:locado_final/services/geofencing_integration_helper.dart';
import 'package:flutter_map/flutter_map.dart' as osm;
import 'package:latlong2/latlong.dart' as ll;
import '../widgets/osm_map_widget.dart';

class GeneralTaskDetailScreen extends StatefulWidget {
  final GeneralTask generalTask;
  final bool isLockScreenMode;

  const GeneralTaskDetailScreen({
    Key? key, 
    required this.generalTask, 
    this.isLockScreenMode = false,
  }) : super(key: key);

  @override
  State<GeneralTaskDetailScreen> createState() => _GeneralTaskDetailScreenState();
}

class _GeneralTaskDetailScreenState extends State<GeneralTaskDetailScreen> {
  late List<bool> _checkedItems;
  late TextEditingController _titleController;
  final TextEditingController _newItemController = TextEditingController();
  final FocusNode _newItemFocusNode = FocusNode();
  Color _selectedColor = Colors.teal;
  bool _hasChanges = false;

  // Scheduling state variables
  DateTime? _scheduledDate;
  TimeOfDay? _scheduledTime;
  CalendarEvent? _linkedCalendarEvent;
  
  // Map interaction state
  bool _isLocationSelectionMode = false;
  bool _mapExpanded = false;
  
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.generalTask.title);
    _selectedColor = _taskColor;

    // Initialize scheduling data
    if (widget.generalTask.hasScheduledTime) {
      _scheduledDate = DateTime(
        widget.generalTask.scheduledDateTime!.year,
        widget.generalTask.scheduledDateTime!.month,
        widget.generalTask.scheduledDateTime!.day,
      );
      _scheduledTime = TimeOfDay.fromDateTime(widget.generalTask.scheduledDateTime!);
    }

    _syncCheckedItems();
    _loadLinkedCalendarEvent();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _titleController.dispose();
    _newItemController.dispose();
    _newItemFocusNode.dispose();
    super.dispose();
  }

  void _syncCheckedItems() {
    _checkedItems = List<bool>.filled(widget.generalTask.taskItems.length, false);
  }

  // Load linked calendar event
  Future<void> _loadLinkedCalendarEvent() async {
    if (widget.generalTask.hasLinkedCalendarEvent) {
      try {
        final events = await DatabaseHelper.instance.getCalendarEventsForTask(widget.generalTask.id!);
        if (events.isNotEmpty) {
          setState(() {
            _linkedCalendarEvent = events.first;
          });
        }
      } catch (e) {
        debugPrint('⚠️ Error loading linked calendar event: $e');
      }
    }
  }

  Color get _taskColor {
    try {
      return Color(int.parse(widget.generalTask.colorHex.replaceFirst('#', '0xff')));
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
  
  void _scrollToMap() {
    _scrollController.animateTo(
      200.0, // Scroll position
      duration: Duration(milliseconds: 500),
      curve: Curves.easeInOut,
    );
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
      await DatabaseHelper.instance.updateGeneralTaskScheduledTime(widget.generalTask.id!, scheduledDateTime);
      widget.generalTask.scheduledDateTime = scheduledDateTime;

      if (scheduledDateTime != null) {
        if (_linkedCalendarEvent != null) {
          final updatedEvent = _linkedCalendarEvent!.copyWith(
            title: widget.generalTask.generateCalendarEventTitle(),
            description: widget.generalTask.generateCalendarEventDescription(),
            dateTime: scheduledDateTime,
            colorHex: widget.generalTask.colorHex,
          );

          await DatabaseHelper.instance.updateCalendarEvent(updatedEvent);
          await NotificationService.scheduleEventReminders(updatedEvent);

          setState(() {
            _linkedCalendarEvent = updatedEvent;
          });

          debugPrint('✅ Updated linked calendar event');
        } else {
          final calendarEvent = CalendarEvent(
            title: widget.generalTask.generateCalendarEventTitle(),
            description: widget.generalTask.generateCalendarEventDescription(),
            dateTime: scheduledDateTime,
            reminderMinutes: [15],
            colorHex: widget.generalTask.colorHex,
            linkedTaskLocationId: null, // General tasks don't have location
          );

          final eventId = await DatabaseHelper.instance.addCalendarEvent(calendarEvent);
          await DatabaseHelper.instance.linkGeneralTaskToCalendarEvent(widget.generalTask.id!, eventId);

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
      debugPrint('⚠️ Error saving scheduling: $e');
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
              taskLocations: [], // General tasks have no location
            ),
          ),
        );

        if (result == true) {
          _loadLinkedCalendarEvent();
        }
      } catch (e) {
        debugPrint('⚠️ Error navigating to calendar event: $e');
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
    await DatabaseHelper.instance.updateGeneralTask(
      GeneralTask(
        id: widget.generalTask.id,
        title: _titleController.text.trim(),
        taskItems: widget.generalTask.taskItems,
        colorHex: '#${_selectedColor.value.toRadixString(16).substring(2)}',
        scheduledDateTime: widget.generalTask.scheduledDateTime,
        linkedCalendarEventId: widget.generalTask.linkedCalendarEventId,
      ),
    );
    Navigator.pop(context, true);
  }

  void _deleteCompletedTasks() async {
    setState(() {
      final newTaskItems = <String>[];

      for (int i = 0; i < widget.generalTask.taskItems.length; i++) {
        if (!_checkedItems[i]) {
          newTaskItems.add(widget.generalTask.taskItems[i]);
        }
      }

      widget.generalTask.taskItems
        ..clear()
        ..addAll(newTaskItems);
      _syncCheckedItems();
    });

    await DatabaseHelper.instance.updateGeneralTask(
      GeneralTask(
        id: widget.generalTask.id,
        title: _titleController.text.trim(),
        taskItems: widget.generalTask.taskItems,
        colorHex: widget.generalTask.colorHex,
        scheduledDateTime: widget.generalTask.scheduledDateTime,
        linkedCalendarEventId: widget.generalTask.linkedCalendarEventId,
      ),
    );

    _hasChanges = true;
  }

  void _addNewItem() async {
    final newItem = _newItemController.text.trim();
    if (newItem.isNotEmpty) {
      widget.generalTask.taskItems.add(newItem);
      _newItemController.clear();
      _syncCheckedItems();

      setState(() {});

      await DatabaseHelper.instance.updateGeneralTask(
        GeneralTask(
          id: widget.generalTask.id,
          title: _titleController.text.trim(),
          taskItems: widget.generalTask.taskItems,
          colorHex: widget.generalTask.colorHex,
          scheduledDateTime: widget.generalTask.scheduledDateTime,
          linkedCalendarEventId: widget.generalTask.linkedCalendarEventId,
        ),
      );

      _hasChanges = true;
      FocusScope.of(context).requestFocus(_newItemFocusNode);
    }
  }

  void _deleteEntireTask() async {
    await DatabaseHelper.instance.deleteGeneralTask(widget.generalTask.id!);
    Navigator.pop(context, true);
  }

  void _shareTask() {
    final items = widget.generalTask.taskItems;
    final taskText = StringBuffer();
    taskText.writeln("📝 General Task: ${_titleController.text.trim()}");

    if (widget.generalTask.hasScheduledTime) {
      taskText.writeln("⏰ Scheduled: ${widget.generalTask.formattedScheduledTime}");
    }

    taskText.writeln("✅ Items:");
    for (var item in items) {
      taskText.writeln("• $item");
    }

    Share.share(taskText.toString());
  }

  Future<void> _exportTaskAsFile() async {
    try {
      final task = widget.generalTask;

      final exportMap = {
        "locado_version": "1.0",
        "export_type": "general_task_share", 
        "export_timestamp": DateTime.now().toIso8601String(),
        "app_version": "1.0.0",
        "task_data": {
          "id": task.id,
          "title": task.title,
          "colorHex": task.colorHex,
          "taskItems": task.taskItems,
          "scheduledDateTime": task.scheduledDateTime?.toIso8601String(),
          "linkedCalendarEventId": task.linkedCalendarEventId,
        }
      };

      final jsonString = jsonEncode(exportMap);
      final directory = await getTemporaryDirectory();
      final safeTitle = task.title.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
      final fileName = '${safeTitle}_general_task.json';
      final filePath = '${directory.path}/$fileName';

      final file = File(filePath);
      await file.writeAsString(jsonString);

      final xfile = XFile(file.path, mimeType: 'application/json');

      await Share.shareXFiles(
        [xfile], 
        text: '''📝 Locado General Task: ${task.title}

Open this file with Locado app to import the task!''',
        subject: 'Shared Locado General Task: ${task.title}',
      );

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              Icon(Icons.share, color: Colors.white, size: 20),
              SizedBox(width: 8),
              Text('General task exported successfully!'),
            ],
          ),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 3),
        ),
      );

      print('✅ EXPORT: Created general task file: $filePath');

    } catch (e) {
      print("⚠️ EXPORT ERROR: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.error, color: Colors.white),
              const SizedBox(width: 8),
              Expanded(child: Text('Export error: $e')),
            ],
          ),
          backgroundColor: Colors.red,
        ),
      );
    }
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

                  await _updateGeneralTask();
                  _hasChanges = true;

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
              const Text('General Task Tips'),
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
                _buildTipItem(Icons.palette, 'Change colors',
                    'Use colors to categorize your tasks'),
                const SizedBox(height: 12),
                _buildTipItem(Icons.check_box, 'Mark completed',
                    'Check off items as you complete them'),
                const SizedBox(height: 12),
                _buildTipItem(Icons.delete_forever, 'Clean up',
                    'Delete completed items to keep list clean'),
                const SizedBox(height: 12),
                _buildTipItem(Icons.location_off, 'No location needed',
                    'General tasks work anywhere, anytime'),
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

  Future<void> _updateGeneralTask() async {
    final updatedTask = GeneralTask(
      id: widget.generalTask.id,
      title: _titleController.text.trim(),
      taskItems: widget.generalTask.taskItems,
      colorHex: '#${_selectedColor.value.toRadixString(16).substring(2)}',
      scheduledDateTime: widget.generalTask.scheduledDateTime,
      linkedCalendarEventId: widget.generalTask.linkedCalendarEventId,
    );

    await DatabaseHelper.instance.updateGeneralTask(updatedTask);
  }

  @override
  Widget build(BuildContext context) {
    List<Widget> activeTasks = [];
    List<Widget> completedTasks = [];

    for (int i = 0; i < widget.generalTask.taskItems.length; i++) {
      final itemWidget = Card(
        margin: const EdgeInsets.only(bottom: 8),
        color: _checkedItems[i] ? Colors.grey.shade100 : Colors.grey.shade50,
        child: CheckboxListTile(
          value: _checkedItems[i],
          title: Text(
            widget.generalTask.taskItems[i],
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
          title: const Text('General Task Details'),
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
              icon: const Icon(Icons.share),
              onPressed: _exportTaskAsFile,
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
				// Interactive location banner
				Container(
				  width: double.infinity,
				  padding: const EdgeInsets.all(16),
				  decoration: BoxDecoration(
					color: _isLocationSelectionMode ? Colors.blue.shade50 : Colors.orange.shade50,
					border: Border(
					  bottom: BorderSide(
						color: _isLocationSelectionMode ? Colors.blue.shade200 : Colors.orange.shade200, 
						width: 1
					  ),
					),
				  ),
				  child: Row(
					children: [
					  Icon(
						_isLocationSelectionMode ? Icons.location_searching : Icons.location_off,
						color: _isLocationSelectionMode ? Colors.blue.shade600 : Colors.orange.shade600,
						size: 20,
					  ),
					  const SizedBox(width: 8),
					  Expanded(
						child: Column(
						  crossAxisAlignment: CrossAxisAlignment.start,
						  children: [
							Text(
							  _isLocationSelectionMode 
								? 'Select Location on Map'
								: 'General Task (No Location)',
							  style: TextStyle(
								fontSize: 14,
								fontWeight: FontWeight.bold,
								color: _isLocationSelectionMode 
								  ? Colors.blue.shade700 
								  : Colors.orange.shade700,
							  ),
							),
							Text(
							  _isLocationSelectionMode
								? 'Long press on the map below to add a location'
								: 'This task can be completed anywhere',
							  style: TextStyle(
								fontSize: 12,
								color: _isLocationSelectionMode 
								  ? Colors.blue.shade600 
								  : Colors.orange.shade600,
							  ),
							),
						  ],
						),
					  ),
					  if (_isLocationSelectionMode)
						TextButton(
						  onPressed: _toggleLocationSelectionMode,
						  child: Text('Cancel'),
						),
					],
				  ),
				),
				
				if (_isLocationSelectionMode)
				  const SizedBox(height: 16), // Dodaj spacing

				if (_isLocationSelectionMode)
				  Container(
					height: MediaQuery.of(context).size.height * 0.7,
					child: Stack(
					  children: [
						// Map widget
						OSMMapWidget(
						  initialCameraPosition: OSMCameraPosition(
							target: ll.LatLng(48.2082, 16.3738),
							zoom: 12.0,
						  ),
						  markers: const {},
						  onMapCreated: (controller) {
							WidgetsBinding.instance.addPostFrameCallback((_) {
								  _scrollToMap();
								});
						  },
						  onLongPress: _onMapLongPress,
						  myLocationEnabled: true,
						  myLocationButtonEnabled: true,
						),
						
						// Instructions overlay
						Positioned(
						  top: 16,
						  left: 16,
						  right: 16,
						  child: Container(
							padding: const EdgeInsets.all(12),
							decoration: BoxDecoration(
							  color: Colors.blue.shade100,
							  borderRadius: BorderRadius.circular(8),
							),
							child: Text(
							  'Long press anywhere on the map to set task location',
							  style: TextStyle(color: Colors.blue.shade800),
							  textAlign: TextAlign.center,
							),
						  ),
						),
					  ],
					),
				  ),

            // Task detail form
            Expanded(
              child: SingleChildScrollView(
			    controller: _scrollController,
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
                                    if (widget.generalTask.hasScheduledTime || _linkedCalendarEvent != null) {
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
                                    widget.generalTask.hasScheduledTime
                                        ? Icons.event
                                        : Icons.schedule,
                                    color: widget.generalTask.hasScheduledTime
                                        ? Colors.green
                                        : Colors.orange,
                                  ),
                                  tooltip: widget.generalTask.hasScheduledTime
                                      ? 'View Schedule'
                                      : 'Add Schedule',
                                ),
								
								// Location button
								IconButton(
								  onPressed: _toggleLocationSelectionMode,
								  icon: Icon(
									_isLocationSelectionMode ? Icons.location_searching : Icons.add_location,
									color: _isLocationSelectionMode ? Colors.red : Colors.blue,
								  ),
								  tooltip: _isLocationSelectionMode ? 'Cancel Selection' : 'Add Location',
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
                   Column(
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
                 ],
               ),
             ),
           ),
         ],
       ),
     ),
   );
 }
 
	void _toggleLocationSelectionMode() {
	  print('Location button pressed! Current mode: $_isLocationSelectionMode');
	  setState(() {
		_isLocationSelectionMode = !_isLocationSelectionMode;
		_mapExpanded = _isLocationSelectionMode;
	  });
	  print('New mode: $_isLocationSelectionMode');
	}

	Future<void> _convertToTaskLocation(double latitude, double longitude) async {
	  final originalTaskId = widget.generalTask.id;
	  print('🔄 CONVERT: Starting conversion for GeneralTask ID: $originalTaskId');
	  
	  // Convert GeneralTask to TaskLocation
	  final taskLocation = TaskLocation(
		title: widget.generalTask.title,
		taskItems: widget.generalTask.taskItems,
		colorHex: widget.generalTask.colorHex,
		latitude: latitude,
		longitude: longitude,
		scheduledDateTime: widget.generalTask.scheduledDateTime,
	  );
	  
	  // Save new TaskLocation
	  final taskId = await DatabaseHelper.instance.addTaskLocation(taskLocation);
	  print('🔄 CONVERT: Created new TaskLocation with ID: $taskId');
	  
	  // Add geofencing
	  final helper = GeofencingIntegrationHelper.instance;
	  if (helper.isInitialized && helper.isServiceRunning) {
		final taskWithId = taskLocation.copyWith(id: taskId);
		await helper.addTaskLocationGeofence(taskWithId);
	  }
	  
	  // Delete old GeneralTask AND TaskLocation with same ID
	  await DatabaseHelper.instance.deleteGeneralTask(widget.generalTask.id!);
	  print('🔄 CONVERT: Deleted old GeneralTask with ID: ${widget.generalTask.id}');
	  
	  // DODAJ OVO - briši i TaskLocation sa istim ID-om
	  try {
		await DatabaseHelper.instance.deleteTaskLocation(widget.generalTask.id!);
		print('🔄 CONVERT: Also deleted TaskLocation with ID: ${widget.generalTask.id}');
	  } catch (e) {
		print('🔄 CONVERT: No TaskLocation found with ID: ${widget.generalTask.id} (this is OK)');
	  }
	  
	  ScaffoldMessenger.of(context).showSnackBar(
		SnackBar(content: Text('Task converted to location-based task')),
	  );
	  
	  Navigator.pop(context, {
		'action': 'converted', 
		'originalTaskId': originalTaskId
	  });
	}
	
	void _onMapLongPress(ll.LatLng tappedPoint) {
	  _convertToTaskLocation(tappedPoint.latitude, tappedPoint.longitude);
	}
}