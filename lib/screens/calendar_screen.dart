import 'package:flutter/material.dart';
import 'package:locado_final/models/calendar_event.dart';
import 'package:locado_final/models/task_location.dart';
import 'package:locado_final/helpers/database_helper.dart';
import 'package:locado_final/screens/add_event_screen.dart';
import 'package:locado_final/services/calendar_import_service.dart';
import 'dart:async';
import 'package:locado_final/screens/event_details_screen.dart';
import 'task_detail_screen.dart';

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({Key? key}) : super(key: key);

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> with TickerProviderStateMixin {
  DateTime _selectedDate = DateTime.now();
  DateTime _focusedDate = DateTime.now();
  List<CalendarEvent> _allEvents = [];
  List<CalendarEvent> _upcomingEvents = [];
  List<TaskLocation> _taskLocations = [];
  bool _isLoading = true;

  late TabController _tabController;
  PageController _pageController = PageController();

  final CalendarImportService _calendarImportService = CalendarImportService();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    try {
      // Load calendar events and tasks
      final events = await DatabaseHelper.instance.getAllCalendarEvents();
      final tasks = await DatabaseHelper.instance.getAllTaskLocations();
      final upcoming = await DatabaseHelper.instance.getUpcomingCalendarEvents(limit: 10);

      setState(() {
        _allEvents = events;
        _taskLocations = tasks;
        _upcomingEvents = upcoming;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('❌ Error loading calendar data: $e');
      setState(() => _isLoading = false);
    }
  }

  Future<void> _showEventsForDatePopup(DateTime selectedDate) async {
    // Load events for selected date
    final eventsForDate = await DatabaseHelper.instance.getCalendarEventsForDate(selectedDate);

    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.3,
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
                    Icon(Icons.event, color: Colors.teal, size: 28),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Events',
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            _formatDate(selectedDate),
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Add event button
                    IconButton(
                      onPressed: () {
                        Navigator.pop(context); // Close popup
                        _showAddEventDialog(selectedDate: selectedDate);
                      },
                      icon: const Icon(Icons.add_circle, color: Colors.teal, size: 28),
                      tooltip: 'Add Event',
                    ),
                  ],
                ),
              ),

              // Events list
              Expanded(
                child: eventsForDate.isEmpty
                    ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.event_available,
                        size: 64,
                        color: Colors.grey.shade400,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'No events for this date',
                        style: TextStyle(
                          fontSize: 18,
                          color: Colors.grey.shade600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Tap + to add an event',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey.shade500,
                        ),
                      ),
                    ],
                  ),
                )
                    : ListView.builder(
                  controller: scrollController,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  itemCount: eventsForDate.length,
                  itemBuilder: (context, index) {
                    final event = eventsForDate[index];
                    return _buildEventCard(event, onTap: () {
                      Navigator.pop(context); // Close popup first
                      _showEventDetails(event);
                    });
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showAddEventDialog({DateTime? selectedDate}) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AddEventScreen(
          selectedDate: selectedDate ?? _selectedDate,
          taskLocations: _taskLocations,
        ),
      ),
    );

    // If event successfully added, refresh data
    if (result == true) {
      _loadData();
    }
  }

  Future<void> _importFromDeviceCalendar() async {
    try {
      // Show loading dialog
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const AlertDialog(
          content: Row(
            children: [
              CircularProgressIndicator(),
              SizedBox(width: 16),
              Expanded(child: Text('Importing events from device calendar...')),
            ],
          ),
        ),
      );

      // Attempt import
      final result = await _calendarImportService.importFromDeviceCalendar();

      // Close loading dialog
      Navigator.pop(context);

      // Show result
      _showImportResultDialog(result);

      // Refresh data if import successful
      if (result.success) {
        await _loadData();
      }

    } catch (e) {
      // Close loading dialog if open
      Navigator.pop(context);

      _showErrorDialog('Import Error', 'Failed to import calendar: $e');
    }
  }

  Future<void> _exportToDeviceCalendar() async {
    try {
      // Show loading dialog
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const AlertDialog(
          content: Row(
            children: [
              CircularProgressIndicator(),
              SizedBox(width: 16),
              Expanded(child: Text('Exporting events to device calendar...')),
            ],
          ),
        ),
      );

      // Attempt export
      final result = await _calendarImportService.exportToDeviceCalendar();

      // Close loading dialog
      Navigator.pop(context);

      // Show result
      _showExportResultDialog(result);

    } catch (e) {
      // Close loading dialog if open
      Navigator.pop(context);

      _showErrorDialog('Export Error', 'Failed to export calendar: $e');
    }
  }

  void _showImportResultDialog(CalendarImportResult result) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(
              result.success ? Icons.check_circle : Icons.error,
              color: result.success ? Colors.green : Colors.red,
              size: 24,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                result.success ? 'Import Successful' : 'Import Failed',
                style: const TextStyle(fontSize: 18),
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (result.success) ...[
                Text('📅 Events found: ${result.totalFound}'),
                const SizedBox(height: 4),
                Text('✅ Imported: ${result.imported}'),
                const SizedBox(height: 4),
                Text('🔄 Duplicates skipped: ${result.duplicates}'),
                if (result.failed > 0) ...[
                  const SizedBox(height: 4),
                  Text('❌ Failed: ${result.failed}'),
                ],
              ] else ...[
                Text(
                  result.error ?? 'Unknown error occurred',
                  style: const TextStyle(color: Colors.red),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _showExportResultDialog(CalendarExportResult result) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(
              result.success ? Icons.check_circle : Icons.error,
              color: result.success ? Colors.green : Colors.red,
              size: 24,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                result.success ? 'Export Successful' : 'Export Failed',
                style: const TextStyle(fontSize: 18),
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (result.success) ...[
                if (result.targetCalendarName != null) ...[
                  Text('📱 Target: ${result.targetCalendarName}'),
                  const SizedBox(height: 4),
                ],
                Text('📅 Events found: ${result.totalFound}'),
                const SizedBox(height: 4),
                Text('✅ Exported: ${result.exported}'),
                const SizedBox(height: 4),
                Text('🔄 Duplicates skipped: ${result.duplicates}'),
                if (result.failed > 0) ...[
                  const SizedBox(height: 4),
                  Text('❌ Failed: ${result.failed}'),
                ],
              ] else ...[
                Text(
                  result.error ?? 'Unknown error occurred',
                  style: const TextStyle(color: Colors.red),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _showErrorDialog(String title, String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.error, color: Colors.red),
            const SizedBox(width: 8),
            Text(title),
          ],
        ),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _showCalendarSyncMenu() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Row(
              children: [
                Icon(Icons.sync, color: Colors.teal, size: 28),
                const SizedBox(width: 12),
                const Text(
                  'Calendar Sync',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 20),

            // Import option
            ListTile(
              leading: const Icon(Icons.file_download, color: Colors.blue),
              title: const Text('Import from Device'),
              subtitle: const Text('Import events from your phone\'s calendar'),
              trailing: const Icon(Icons.arrow_forward_ios),
              onTap: () {
                Navigator.pop(context);
                _importFromDeviceCalendar();
              },
            ),

            const Divider(),

            // Export option
            ListTile(
              leading: const Icon(Icons.file_upload, color: Colors.green),
              title: const Text('Export to Device'),
              subtitle: const Text('Export Locado events to your phone\'s calendar'),
              trailing: const Icon(Icons.arrow_forward_ios),
              onTap: () {
                Navigator.pop(context);
                _exportToDeviceCalendar();
              },
            ),

            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }

  List<CalendarEvent> _getEventsForDay(DateTime day) {
    return _allEvents.where((event) {
      return event.dateTime.year == day.year &&
          event.dateTime.month == day.month &&
          event.dateTime.day == day.day;
    }).toList();
  }

  Widget _buildCalendarView() {
    return Column(
      children: [
        // Custom calendar header
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.teal.shade50,
            borderRadius: BorderRadius.circular(12),
          ),
          margin: const EdgeInsets.all(16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                onPressed: () {
                  setState(() {
                    _focusedDate = DateTime(_focusedDate.year, _focusedDate.month - 1);
                  });
                },
                icon: const Icon(Icons.chevron_left, color: Colors.teal),
              ),
              Text(
                '${_getMonthName(_focusedDate.month)} ${_focusedDate.year}',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.teal,
                ),
              ),
              IconButton(
                onPressed: () {
                  setState(() {
                    _focusedDate = DateTime(_focusedDate.year, _focusedDate.month + 1);
                  });
                },
                icon: const Icon(Icons.chevron_right, color: Colors.teal),
              ),
            ],
          ),
        ),

        // Custom calendar grid
        Expanded(
          child: _buildCustomCalendar(),
        ),
      ],
    );
  }

  Widget _buildCustomCalendar() {
    final daysInMonth = DateTime(_focusedDate.year, _focusedDate.month + 1, 0).day;
    final firstDayOfMonth = DateTime(_focusedDate.year, _focusedDate.month, 1);
    final startDayOfWeek = firstDayOfMonth.weekday % 7;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          // Days of week header
          Container(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat']
                  .map((day) => Expanded(
                child: Center(
                  child: Text(
                    day,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.grey.shade600,
                      fontSize: 12,
                    ),
                  ),
                ),
              ))
                  .toList(),
            ),
          ),

          // Calendar grid
          Expanded(
            child: GridView.builder(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 7,
                childAspectRatio: 1.0,
              ),
              itemCount: 42, // 6 weeks * 7 days
              itemBuilder: (context, index) {
                final dayNumber = index - startDayOfWeek + 1;

                if (dayNumber < 1 || dayNumber > daysInMonth) {
                  return const SizedBox(); // Empty cell
                }

                final currentDate = DateTime(_focusedDate.year, _focusedDate.month, dayNumber);
                final isSelected = _selectedDate.year == currentDate.year &&
                    _selectedDate.month == currentDate.month &&
                    _selectedDate.day == currentDate.day;
                final isToday = _isToday(currentDate);
                final events = _getEventsForDay(currentDate);

                return GestureDetector(
                  onTap: () => _showEventsForDatePopup(currentDate),
                  child: Container(
                    margin: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? Colors.teal
                          : isToday
                          ? Colors.teal.shade100
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                      border: events.isNotEmpty
                          ? Border.all(color: Colors.orange, width: 1)
                          : null,
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          dayNumber.toString(),
                          style: TextStyle(
                            color: isSelected
                                ? Colors.white
                                : isToday
                                ? Colors.teal.shade700
                                : Colors.black87,
                            fontWeight: isSelected || isToday
                                ? FontWeight.bold
                                : FontWeight.normal,
                            fontSize: 16,
                          ),
                        ),
                        if (events.isNotEmpty)
                          Container(
                            width: 6,
                            height: 6,
                            margin: const EdgeInsets.only(top: 2),
                            decoration: BoxDecoration(
                              color: isSelected ? Colors.white : Colors.orange,
                              shape: BoxShape.circle,
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUpcomingEvents() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.teal.shade50,
            borderRadius: BorderRadius.circular(12),
          ),
          margin: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(Icons.schedule, color: Colors.teal, size: 24),
              const SizedBox(width: 12),
              const Text(
                'Upcoming Events',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.teal,
                ),
              ),
            ],
          ),
        ),

        Expanded(
          child: _upcomingEvents.isEmpty
              ? Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.event_note,
                  size: 64,
                  color: Colors.grey.shade400,
                ),
                const SizedBox(height: 16),
                Text(
                  'No upcoming events',
                  style: TextStyle(
                    fontSize: 18,
                    color: Colors.grey.shade600,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Add your first calendar event',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey.shade500,
                  ),
                ),
              ],
            ),
          )
              : ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: _upcomingEvents.length,
            itemBuilder: (context, index) {
              final event = _upcomingEvents[index];
              return _buildEventCard(event, showDate: true);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildEventCard(CalendarEvent event, {bool showDate = false, VoidCallback? onTap}) {
    final color = Color(int.parse(event.colorHex.replaceFirst('#', '0xff')));

    // Find linked task if exists
    TaskLocation? linkedTask;
    if (event.linkedTaskLocationId != null) {
      try {
        linkedTask = _taskLocations.firstWhere(
              (task) => task.id == event.linkedTaskLocationId,
        );
      } catch (e) {
        // Task not found (might be deleted)
        linkedTask = null;
      }
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      child: ListTile(
        contentPadding: const EdgeInsets.all(16),
        leading: Container(
          width: 50,
          height: 50,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
          child: Icon(
            event.hasLinkedTask ? Icons.location_on : Icons.event,
            color: Colors.white,
            size: 24,
          ),
        ),
        title: Text(
          event.title,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 16,
            decoration: event.isCompleted ? TextDecoration.lineThrough : null,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            if (showDate) ...[
              Text(
                _formatDate(event.dateTime),
                style: TextStyle(
                  color: Colors.grey.shade600,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 2),
            ],
            Text(
              _formatTime(event.dateTime),
              style: TextStyle(
                color: Colors.grey.shade600,
                fontSize: 14,
              ),
            ),
            if (event.description != null && event.description!.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                event.description!,
                style: TextStyle(
                  color: Colors.grey.shade500,
                  fontSize: 12,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            // Fixed: Linked task display with overflow protection
            if (linkedTask != null) ...[
              const SizedBox(height: 6),
              InkWell(
                onTap: () => _navigateToTaskDetails(linkedTask!),
                borderRadius: BorderRadius.circular(4),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.teal.shade50,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: Colors.teal.shade200),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.link, size: 12, color: Colors.teal),
                      const SizedBox(width: 4),
                      Expanded( // Fixed: Added Expanded wrapper
                        child: Text(
                          'Linked: ${linkedTask.title}',
                          style: TextStyle(
                            color: Colors.teal,
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                          ),
                          overflow: TextOverflow.ellipsis, // Fixed: Added overflow handling
                          maxLines: 1, // Fixed: Limit to one line
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(Icons.arrow_forward_ios, size: 10, color: Colors.teal),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (event.isCompleted)
              Icon(Icons.check_circle, color: Colors.green, size: 20),
            const SizedBox(width: 8),
            Icon(
              Icons.arrow_forward_ios,
              color: Colors.grey,
              size: 16,
            ),
          ],
        ),
        onTap: onTap ?? () => _showEventDetails(event),
      ),
    );
  }

  Future<void> _showEventDetails(CalendarEvent event) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => EventDetailsScreen(
          event: event,
          taskLocations: _taskLocations,
        ),
      ),
    );

    // If event updated or deleted, refresh data
    if (result == true) {
      _loadData();
    }
  }

  bool _isToday(DateTime date) {
    final now = DateTime.now();
    return date.year == now.year &&
        date.month == now.month &&
        date.day == now.day;
  }

  String _getMonthName(int month) {
    const months = [
      '', 'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December'
    ];
    return months[month];
  }

  String _formatDate(DateTime date) {
    const days = ['', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const months = [
      '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];

    return '${days[date.weekday]}, ${months[date.month]} ${date.day}';
  }

  String _formatTime(DateTime dateTime) {
    final hour = dateTime.hour;
    final minute = dateTime.minute.toString().padLeft(2, '0');
    final period = hour < 12 ? 'AM' : 'PM';
    final displayHour = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour);

    return '$displayHour:$minute $period';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Calendar'),
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            onPressed: _showCalendarSyncMenu,
            icon: const Icon(Icons.sync),
            //icon: const Icon(Icons.cloud_sync ),
            tooltip: 'Calendar Sync',
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: Colors.white,
          tabs: const [
            Tab(icon: Icon(Icons.calendar_view_month), text: 'Month'),
            Tab(icon: Icon(Icons.schedule), text: 'Upcoming'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
        controller: _tabController,
        children: [
          _buildCalendarView(),
          _buildUpcomingEvents(),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddEventDialog(),
        backgroundColor: Colors.teal,
        child: const Icon(Icons.add, color: Colors.white),
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

      // Refresh calendar if task was modified
      if (result == true) {
        _loadData(); // Refresh calendar data
        debugPrint('✅ Returned from task details, refreshing calendar');
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