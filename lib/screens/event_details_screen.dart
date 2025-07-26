// screens/event_details_screen.dart
import 'package:flutter/material.dart';
import 'package:locado_final/models/calendar_event.dart';
import 'package:locado_final/models/task_location.dart';
import 'package:locado_final/helpers/database_helper.dart';
import 'task_detail_screen.dart';

class EventDetailsScreen extends StatefulWidget {
  final CalendarEvent event;
  final List<TaskLocation>? taskLocations;

  const EventDetailsScreen({
    Key? key,
    required this.event,
    this.taskLocations,
  }) : super(key: key);

  @override
  State<EventDetailsScreen> createState() => _EventDetailsScreenState();
}

class _EventDetailsScreenState extends State<EventDetailsScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();

  late CalendarEvent _currentEvent;
  bool _isEditMode = false;
  bool _isLoading = false;

  // Edit mode variables
  DateTime _selectedDate = DateTime.now();
  TimeOfDay _selectedTime = TimeOfDay.now();
  Color _selectedColor = Colors.teal;
  TaskLocation? _linkedTask;
  List<int> _reminderMinutes = [];

  @override
  void initState() {
    super.initState();
    _currentEvent = widget.event;
    _initializeEditValues();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  void _initializeEditValues() {
    // Initialize form fields with current event data
    _titleController.text = _currentEvent.title;
    _descriptionController.text = _currentEvent.description ?? '';

    _selectedDate = _currentEvent.dateTime;
    _selectedTime = TimeOfDay.fromDateTime(_currentEvent.dateTime);
    _selectedColor = Color(int.parse(_currentEvent.colorHex.replaceFirst('#', '0xff')));
    _reminderMinutes = List<int>.from(_currentEvent.reminderMinutes);

    // Find linked task if exists
    if (_currentEvent.linkedTaskLocationId != null && widget.taskLocations != null) {
      _linkedTask = widget.taskLocations!.firstWhere(
            (task) => task.id == _currentEvent.linkedTaskLocationId,
        orElse: () => TaskLocation(
          id: -1,
          latitude: 0,
          longitude: 0,
          title: 'Unknown Task (Deleted)',
          taskItems: [],
          colorHex: '#FF9E9E9E',
        ),
      );
    }
  }

  Future<void> _toggleEditMode() async {
    if (_isEditMode) {
      // Cancel edit - reload original values
      _initializeEditValues();
    }
    setState(() {
      _isEditMode = !_isEditMode;
    });
  }

  Future<void> _toggleCompleteStatus() async {
    setState(() => _isLoading = true);

    try {
      final updatedEvent = CalendarEvent(
        id: _currentEvent.id,
        title: _currentEvent.title,
        description: _currentEvent.description,
        dateTime: _currentEvent.dateTime,
        reminderMinutes: _currentEvent.reminderMinutes,
        colorHex: _currentEvent.colorHex,
        linkedTaskLocationId: _currentEvent.linkedTaskLocationId,
        isCompleted: !_currentEvent.isCompleted,
        completedAt: !_currentEvent.isCompleted ? DateTime.now() : null,
        createdAt: _currentEvent.createdAt,
        updatedAt: DateTime.now(),
      );

      await DatabaseHelper.instance.updateCalendarEvent(updatedEvent);

      setState(() {
        _currentEvent = updatedEvent;
      });

      final statusText = updatedEvent.isCompleted ? 'completed' : 'marked as pending';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Event ${statusText}'),
          backgroundColor: updatedEvent.isCompleted ? Colors.green : Colors.orange,
        ),
      );

    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error updating event: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _deleteEvent() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Event'),
        content: Text('Are you sure you want to delete "${_currentEvent.title}"?\n\nThis action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      setState(() => _isLoading = true);

      try {
        await DatabaseHelper.instance.deleteCalendarEvent(_currentEvent.id!);

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Event "${_currentEvent.title}" deleted'),
            backgroundColor: Colors.red,
          ),
        );

        // Return to calendar with refresh signal
        Navigator.pop(context, true);

      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error deleting event: $e'),
            backgroundColor: Colors.red,
          ),
        );
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _saveChanges() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() => _isLoading = true);

    try {
      // Combine date and time
      final eventDateTime = DateTime(
        _selectedDate.year,
        _selectedDate.month,
        _selectedDate.day,
        _selectedTime.hour,
        _selectedTime.minute,
      );

      // Create updated event
      final updatedEvent = CalendarEvent(
        id: _currentEvent.id,
        title: _titleController.text.trim(),
        description: _descriptionController.text.trim().isNotEmpty
            ? _descriptionController.text.trim()
            : null,
        dateTime: eventDateTime,
        reminderMinutes: _reminderMinutes,
        colorHex: '#${_selectedColor.value.toRadixString(16).substring(2)}',
        linkedTaskLocationId: _linkedTask?.id,
        isCompleted: _currentEvent.isCompleted,
        completedAt: _currentEvent.completedAt,
        createdAt: _currentEvent.createdAt,
        updatedAt: DateTime.now(),
      );

      await DatabaseHelper.instance.updateCalendarEvent(updatedEvent);

      setState(() {
        _currentEvent = updatedEvent;
        _isEditMode = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Event "${updatedEvent.title}" updated successfully!'),
          backgroundColor: Colors.green,
        ),
      );

    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error updating event: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // Reuse picker methods from AddEventScreen
  Future<void> _selectDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime.now().subtract(const Duration(days: 30)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
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
        _selectedDate = date;
      });
    }
  }

  Future<void> _selectTime() async {
    final time = await showTimePicker(
      context: context,
      initialTime: _selectedTime,
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
        _selectedTime = time;
      });
    }
  }

  void _showColorPicker() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Choose Event Color'),
          content: SizedBox(
            width: 280,
            child: Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                Colors.red, Colors.green, Colors.blue, Colors.orange,
                Colors.purple, Colors.teal, Colors.pink, Colors.amber,
                Colors.indigo, Colors.cyan, Colors.lime, Colors.deepOrange,
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

  void _showReminderDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Set Reminders'),
              content: SizedBox(
                width: 300,
                height: 300,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Choose when to be reminded:', style: TextStyle(fontSize: 16)),
                    const SizedBox(height: 16),
                    Expanded(
                      child: ListView(
                        children: [
                          _buildReminderOption(5, '5 minutes before', setDialogState),
                          _buildReminderOption(15, '15 minutes before', setDialogState),
                          _buildReminderOption(30, '30 minutes before', setDialogState),
                          _buildReminderOption(60, '1 hour before', setDialogState),
                          _buildReminderOption(120, '2 hours before', setDialogState),
                          _buildReminderOption(1440, '1 day before', setDialogState),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Done'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildReminderOption(int minutes, String label, StateSetter setDialogState) {
    final isSelected = _reminderMinutes.contains(minutes);

    return CheckboxListTile(
      title: Text(label),
      value: isSelected,
      activeColor: Colors.teal,
      onChanged: (bool? value) {
        setDialogState(() {
          if (value == true) {
            if (!_reminderMinutes.contains(minutes)) {
              _reminderMinutes.add(minutes);
              _reminderMinutes.sort();
            }
          } else {
            _reminderMinutes.remove(minutes);
          }
        });
        setState(() {}); // Update main state as well
      },
    );
  }

  void _showTaskLinkDialog() {
    if (widget.taskLocations == null || widget.taskLocations!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No task locations available to link'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.5,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              // Handle bar
              Container(
                margin: const EdgeInsets.only(top: 8),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),

              // Header
              Container(
                padding: const EdgeInsets.all(20),
                child: Row(
                  children: [
                    Icon(Icons.link, color: Colors.teal, size: 28),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'Link to Task Location',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    // Close button
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                      tooltip: 'Close',
                    ),
                  ],
                ),
              ),

              // Content
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Column(
                    children: [
                      // No linked task option
                      Card(
                        elevation: 2,
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          leading: Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: Colors.grey.shade400,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.clear,
                              color: Colors.white,
                              size: 20,
                            ),
                          ),
                          title: const Text(
                            'No linked task',
                            style: TextStyle(
                              fontWeight: FontWeight.w500,
                              fontSize: 16,
                            ),
                          ),
                          subtitle: const Text(
                            'Remove link to any task',
                            style: TextStyle(fontSize: 12),
                          ),
                          trailing: Container(
                            width: 24,
                            height: 24,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: _linkedTask == null ? Colors.teal : Colors.grey.shade400,
                                width: 2,
                              ),
                              color: _linkedTask == null ? Colors.teal : Colors.transparent,
                            ),
                            child: _linkedTask == null
                                ? const Icon(Icons.check, color: Colors.white, size: 16)
                                : null,
                          ),
                          onTap: () {
                            setState(() {
                              _linkedTask = null;
                            });
                            Navigator.pop(context);
                          },
                        ),
                      ),

                      // Divider with text
                      Container(
                        margin: const EdgeInsets.symmetric(vertical: 8),
                        child: Row(
                          children: [
                            Expanded(child: Divider(color: Colors.grey.shade300)),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16),
                              child: Text(
                                'Available Tasks (${widget.taskLocations!.length})',
                                style: TextStyle(
                                  color: Colors.grey.shade600,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                            Expanded(child: Divider(color: Colors.grey.shade300)),
                          ],
                        ),
                      ),

                      // Task locations list
                      Expanded(
                        child: ListView.builder(
                          controller: scrollController,
                          itemCount: widget.taskLocations!.length,
                          itemBuilder: (context, index) {
                            final task = widget.taskLocations![index];
                            final color = Color(int.parse(task.colorHex.replaceFirst('#', '0xff')));
                            final isSelected = _linkedTask?.id == task.id;

                            return Card(
                              elevation: isSelected ? 4 : 2,
                              margin: const EdgeInsets.only(bottom: 8),
                              child: ListTile(
                                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                leading: Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    color: color,
                                    shape: BoxShape.circle,
                                    boxShadow: isSelected ? [
                                      BoxShadow(
                                        color: color.withOpacity(0.3),
                                        blurRadius: 8,
                                        spreadRadius: 2,
                                      ),
                                    ] : null,
                                  ),
                                  child: const Icon(
                                    Icons.location_on,
                                    color: Colors.white,
                                    size: 20,
                                  ),
                                ),
                                title: Text(
                                  task.title,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w500,
                                    fontSize: 16,
                                    color: isSelected ? Colors.teal.shade700 : null,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                subtitle: Row(
                                  children: [
                                    Icon(
                                      Icons.task_alt,
                                      size: 14,
                                      color: Colors.grey.shade600,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      '${task.taskItems.length} items',
                                      style: TextStyle(
                                        color: Colors.grey.shade600,
                                        fontSize: 12,
                                      ),
                                    ),
                                    // Additional task info can be added here if needed
                                  ],
                                ),
                                trailing: Container(
                                  width: 24,
                                  height: 24,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: isSelected ? Colors.teal : Colors.grey.shade400,
                                      width: 2,
                                    ),
                                    color: isSelected ? Colors.teal : Colors.transparent,
                                  ),
                                  child: isSelected
                                      ? const Icon(Icons.check, color: Colors.white, size: 16)
                                      : null,
                                ),
                                onTap: () {
                                  setState(() {
                                    _linkedTask = task;
                                  });
                                  Navigator.pop(context);
                                },
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    const months = [
      '', 'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December'
    ];
    return '${months[date.month]} ${date.day}, ${date.year}';
  }

  String _formatTime(TimeOfDay time) {
    final hour = time.hour;
    final minute = time.minute.toString().padLeft(2, '0');
    final period = hour < 12 ? 'AM' : 'PM';
    final displayHour = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour);
    return '$displayHour:$minute $period';
  }

  String _formatReminders() {
    if (_reminderMinutes.isEmpty) return 'No reminders';
    if (_reminderMinutes.length == 1) {
      final minutes = _reminderMinutes.first;
      if (minutes < 60) return '${minutes}m before';
      if (minutes < 1440) return '${minutes ~/ 60}h before';
      return '${minutes ~/ 1440}d before';
    }
    return '${_reminderMinutes.length} reminders';
  }

  @override
  Widget build(BuildContext context) {
    final eventColor = Color(int.parse(_currentEvent.colorHex.replaceFirst('#', '0xff')));

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditMode ? 'Edit Event' : 'Event Details'),
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
        actions: [
          if (!_isEditMode) ...[
            // Complete/Uncomplete toggle
            IconButton(
              onPressed: _isLoading ? null : _toggleCompleteStatus,
              icon: Icon(
                _currentEvent.isCompleted ? Icons.check_circle : Icons.radio_button_unchecked,
                color: _currentEvent.isCompleted ? Colors.green.shade300 : Colors.white,
              ),
              tooltip: _currentEvent.isCompleted ? 'Mark as Pending' : 'Mark as Complete',
            ),
            // Edit button
            IconButton(
              onPressed: _toggleEditMode,
              icon: const Icon(Icons.edit),
              tooltip: 'Edit Event',
            ),
            // Delete button
            IconButton(
              onPressed: _isLoading ? null : _deleteEvent,
              icon: const Icon(Icons.delete),
              tooltip: 'Delete Event',
            ),
          ] else ...[
            // Cancel edit
            IconButton(
              onPressed: _toggleEditMode,
              icon: const Icon(Icons.close),
              tooltip: 'Cancel',
            ),
            // Save changes
            IconButton(
              onPressed: _isLoading ? null : _saveChanges,
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
              tooltip: 'Save Changes',
            ),
          ],
        ],
      ),
      body: _isEditMode ? _buildEditForm() : _buildViewMode(),
    );
  }

  Widget _buildViewMode() {
    final eventColor = Color(int.parse(_currentEvent.colorHex.replaceFirst('#', '0xff')));
    final linkedTask = _linkedTask;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Main event card
          Card(
            elevation: 4,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header with icon and status
                  Row(
                    children: [
                      Container(
                        width: 50,
                        height: 50,
                        decoration: BoxDecoration(
                          color: eventColor,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          _currentEvent.hasLinkedTask ? Icons.location_on : Icons.event,
                          color: Colors.white,
                          size: 28,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _currentEvent.title,
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                decoration: _currentEvent.isCompleted ? TextDecoration.lineThrough : null,
                              ),
                            ),
                            if (_currentEvent.isCompleted) ...[
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  Icon(Icons.check_circle, color: Colors.green, size: 16),
                                  const SizedBox(width: 4),
                                  Text(
                                    'Completed',
                                    style: TextStyle(
                                      color: Colors.green,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 20),

                  // Description
                  if (_currentEvent.description != null && _currentEvent.description!.isNotEmpty) ...[
                    const Text(
                      'Description',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _currentEvent.description!,
                      style: const TextStyle(fontSize: 16),
                    ),
                    const SizedBox(height: 20),
                  ],

                  // Date and time
                  const Text(
                    'Date & Time',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(Icons.calendar_today, color: Colors.teal, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        _formatDate(_currentEvent.dateTime),
                        style: const TextStyle(fontSize: 16),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(Icons.access_time, color: Colors.teal, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        _formatTime(TimeOfDay.fromDateTime(_currentEvent.dateTime)),
                        style: const TextStyle(fontSize: 16),
                      ),
                    ],
                  ),

                  const SizedBox(height: 20),

                  // Reminders
                  const Text(
                    'Reminders',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(Icons.notifications, color: Colors.orange, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        _formatReminders(),
                        style: const TextStyle(fontSize: 16),
                      ),
                    ],
                  ),

                  // Linked task
                  if (linkedTask != null && linkedTask.id != -1) ...[
                    const SizedBox(height: 20),
                    const Text(
                      'Linked Task',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey,
                      ),
                    ),
                    const SizedBox(height: 8),
                    InkWell(  // 🆕 DODANO: Clickable container
                      onTap: () => _navigateToTaskDetails(linkedTask),  // 🆕 NAVIGATION
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.green.shade50,
                          border: Border.all(color: Colors.green.shade200),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: Color(int.parse(linkedTask.colorHex.replaceFirst('#', '0xff'))),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.location_on,
                                color: Colors.white,
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    linkedTask.title,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w500,
                                      fontSize: 16,
                                    ),
                                  ),
                                  Text(
                                    '${linkedTask.taskItems.length} items',
                                    style: TextStyle(
                                      color: Colors.grey.shade600,
                                      fontSize: 14,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Icon(  // 🆕 DODANO: Navigation indicator
                              Icons.arrow_forward_ios,
                              size: 16,
                              color: Colors.green.shade600,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),

          const SizedBox(height: 20),

          // Action buttons
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _isLoading ? null : _toggleCompleteStatus,
                  icon: Icon(
                    _currentEvent.isCompleted ? Icons.undo : Icons.check,
                  ),
                  label: Text(
                    _currentEvent.isCompleted ? 'Mark as Pending' : 'Mark as Complete',
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _currentEvent.isCompleted ? Colors.orange : Colors.green,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _toggleEditMode,
                  icon: const Icon(Icons.edit),
                  label: const Text('Edit Event'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.teal,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // Delete button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _isLoading ? null : _deleteEvent,
              icon: const Icon(Icons.delete),
              label: const Text('Delete Event'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEditForm() {
    return Form(
      key: _formKey,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Main form card
            Card(
              elevation: 4,
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header with icon and actions
                    Row(
                      children: [
                        Icon(Icons.event, color: _selectedColor, size: 32),
                        const Spacer(),
                        // Color picker
                        IconButton(
                          onPressed: _showColorPicker,
                          icon: Icon(Icons.palette, color: _selectedColor),
                          tooltip: 'Choose Color',
                        ),
                        // Task link
                        IconButton(
                          onPressed: _showTaskLinkDialog,
                          icon: Icon(
                            _linkedTask != null ? Icons.link : Icons.link_off,
                            color: _linkedTask != null ? Colors.green : Colors.grey,
                          ),
                          tooltip: 'Link to Task',
                        ),
                      ],
                    ),

                    const SizedBox(height: 20),

                    // Event title
                    TextFormField(
                      controller: _titleController,
                      decoration: const InputDecoration(
                        labelText: 'Event Title *',
                        hintText: 'Enter event name',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.title),
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Please enter an event title';
                        }
                        return null;
                      },
                    ),

                    const SizedBox(height: 16),

                    // Event description
                    TextFormField(
                      controller: _descriptionController,
                      decoration: const InputDecoration(
                        labelText: 'Description (Optional)',
                        hintText: 'Add event details',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.description),
                      ),
                      maxLines: 3,
                    ),

                    const SizedBox(height: 20),

                    // Date and time section
                    Text(
                      'Date & Time',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.teal.shade700,
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Date picker
                    InkWell(
                      onTap: _selectDate,
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey.shade400),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.calendar_today, color: Colors.teal),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                _formatDate(_selectedDate),
                                style: const TextStyle(fontSize: 16),
                              ),
                            ),
                            Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 12),

                    // Time picker
                    InkWell(
                      onTap: _selectTime,
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey.shade400),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.access_time, color: Colors.teal),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                _formatTime(_selectedTime),
                                style: const TextStyle(fontSize: 16),
                              ),
                            ),
                            Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 20),

                    // Options section
                    Text(
                      'Options',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.teal.shade700,
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Reminders
                    InkWell(
                      onTap: _showReminderDialog,
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey.shade400),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.notifications, color: Colors.orange),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Reminders',
                                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                                  ),
                                  Text(
                                    _formatReminders(),
                                    style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
                                  ),
                                ],
                              ),
                            ),
                            Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 12),

                    // Linked task display
                    if (_linkedTask != null) ...[
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.green.shade50,
                          border: Border.all(color: Colors.green.shade200),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: Color(int.parse(_linkedTask!.colorHex.replaceFirst('#', '0xff'))),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.location_on,
                                color: Colors.white,
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Linked to Task',
                                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                                  ),
                                  Text(
                                    _linkedTask!.title,
                                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              onPressed: () => setState(() => _linkedTask = null),
                              icon: const Icon(Icons.close, size: 20),
                              tooltip: 'Unlink',
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),

            const SizedBox(height: 20),

            // Save button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isLoading ? null : _saveChanges,
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
                label: Text(_isLoading ? 'Saving...' : 'Save Changes'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.teal,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  textStyle: const TextStyle(fontSize: 18),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _navigateToTaskDetails(TaskLocation taskLocation) async {
    try {
      final result = await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => TaskDetailScreen(
            taskLocation: taskLocation,
          ),
        ),
      );

      // Refresh if task was modified
      if (result == true) {
        // Optionally reload task data or refresh calendar
        debugPrint('✅ Returned from task details, task may have been modified');
      }
    } catch (e) {
      debugPrint('❌ Error navigating to task details: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error opening task details: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}