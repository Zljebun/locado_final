// lib/services/notification_service.dart
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:locado_final/models/calendar_event.dart';
import 'package:timezone/timezone.dart' as tz;
import 'dart:developer' as developer;
import 'package:flutter/services.dart';
import 'dart:io';

// Existing global instance - preserved
final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
FlutterLocalNotificationsPlugin();

// New class for calendar notifications with native AlarmManager
class NotificationService {
  static bool _isCalendarInitialized = false;
  static const String _calendarChannelId = 'calendar_reminder_channel';
  
  // Native AlarmManager integration
  static const MethodChannel _alarmChannel = MethodChannel('com.example.locado_final/alarm_manager');

  /// Initialize calendar notifications (modified for native AlarmManager)
  static Future<void> initializeCalendarNotifications() async {
    if (_isCalendarInitialized) return;

    try {
      // Request notification permissions - same as before
      final hasPermission = await requestNotificationPermissions();
      if (!hasPermission) {
        developer.log('Warning: Notification permission denied');
      }

      // Using native Android AlarmManager which is always available
      // instead of flutter_local_notifications exact alarm permission
      
      await _createCalendarNotificationChannel();
      _isCalendarInitialized = true;
      developer.log('Calendar notifications initialized with native AlarmManager');
    } catch (e) {
      developer.log('Error initializing calendar notifications: $e');
    }
  }
  
  /// Request notification permissions (Android 13+) - preserved as is
  static Future<bool> requestNotificationPermissions() async {
    try {
      final androidPlugin = flutterLocalNotificationsPlugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

      if (androidPlugin != null) {
        final granted = await androidPlugin.requestNotificationsPermission();
        developer.log('Notification permission granted: $granted');
        return granted ?? false;
      }
      
      return true; // For older Android versions
    } catch (e) {
      developer.log('Error requesting notification permissions: $e');
      return false;
    }
  }

  /// Create calendar notification channel - preserved as is
  static Future<void> _createCalendarNotificationChannel() async {
    final androidPlugin = flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

    if (androidPlugin != null) {
      const calendarChannel = AndroidNotificationChannel(
        _calendarChannelId,
        'Calendar Reminders',
        description: 'Scheduled reminders for calendar events',
        importance: Importance.high,
        enableVibration: true,
        enableLights: true,
      );

      await androidPlugin.createNotificationChannel(calendarChannel);
      developer.log('Calendar notification channel created');
    }
  }
  
  /// New implementation: Schedule notifications using native AlarmManager
  static Future<void> scheduleEventReminders(CalendarEvent event) async {
    print('NATIVE SCHEDULE: scheduleEventReminders called');
    print('Event title: ${event.title}');
    print('Event ID: ${event.id}');
    print('Event dateTime: ${event.dateTime}');
    print('Reminder minutes: ${event.reminderMinutes}');
    print('Linked task ID: ${event.linkedTaskLocationId}');
    
    if (!_isCalendarInitialized) {
      print('Calendar not initialized, calling init...');
      await initializeCalendarNotifications();
    }

    if (event.reminderMinutes.isEmpty) {
      print('No reminders set for event: ${event.title}');
      return;
    }

    try {
      print('Starting NATIVE notification scheduling...');
      
      // Cancel existing notifications for this event
      await cancelEventReminders(event.id!);
      print('Cancelled existing reminders');

      // Schedule new notifications using native AlarmManager
      for (int i = 0; i < event.reminderMinutes.length; i++) {
        final reminderMinutes = event.reminderMinutes[i];
        final notificationId = _generateNotificationId(event.id!, i);

        final scheduledDate = event.dateTime.subtract(Duration(minutes: reminderMinutes));
        
        print('Processing reminder $i: ${reminderMinutes}min before');
        print('Scheduled date: $scheduledDate');
        print('Current time: ${DateTime.now()}');

        // Only schedule if the reminder time is in the future
        if (scheduledDate.isAfter(DateTime.now())) {
          print('Scheduling NATIVE notification ID: $notificationId');
          
          // Call native AlarmManager instead of flutter_local_notifications
          await _scheduleNativeNotification(
            notificationId: notificationId,
            title: _getReminderTitle(event.title, reminderMinutes),
            body: _getReminderBody(event),
            scheduledDate: scheduledDate,
            taskId: event.linkedTaskLocationId, // Pass the actual task ID
            eventId: event.id!,
          );

          print('NATIVE: Successfully scheduled reminder for "${event.title}" - ${reminderMinutes}min before');
        } else {
          print('Skipped past reminder for "${event.title}" - ${reminderMinutes}min before');
        }
      }
      
      print('All NATIVE reminders processed successfully');
    } catch (e) {
      print('Error scheduling NATIVE event reminders: $e');
    }
  }

  /// New method: Schedule notification using native AlarmManager with task ID
  static Future<void> _scheduleNativeNotification({
    required int notificationId,
    required String title,
    required String body,
    required DateTime scheduledDate,
    required int? taskId,
    required int eventId,
  }) async {
    try {
      print('NATIVE: Calling AlarmManager for notification ID $notificationId');
      print('NATIVE: Scheduled for $scheduledDate');
      print('NATIVE: Task ID: $taskId, Event ID: $eventId');
      
      // Call native AlarmManager via MethodChannel with task ID
      final result = await _alarmChannel.invokeMethod('scheduleNotification', {
        'id': notificationId,
        'title': title,
        'body': body,
        'timestamp': scheduledDate.millisecondsSinceEpoch,
        'taskId': taskId, // Include task ID for navigation
        'eventId': eventId, // Include event ID for reference
      });
      
      print('NATIVE: AlarmManager response: $result');
      
    } catch (e) {
      print('NATIVE: Error scheduling with AlarmManager: $e');
      
      // Fallback: If native fails, use flutter_local_notifications
      print('NATIVE: Falling back to flutter_local_notifications...');
      await _scheduleNotificationFallback(
        notificationId: notificationId,
        title: title,
        body: body,
        scheduledDate: scheduledDate,
        payload: 'calendar_event_${eventId}_task_${taskId ?? 'none'}',
      );
    }
  }

  /// Fallback: Old implementation as backup
  static Future<void> _scheduleNotificationFallback({
    required int notificationId,
    required String title,
    required String body,
    required DateTime scheduledDate,
    required String payload,
  }) async {
    try {
      final scheduledTZ = tz.TZDateTime.from(scheduledDate, tz.local);
      
      print('FALLBACK: Scheduling for $scheduledTZ using flutter_local_notifications');

      const androidDetails = AndroidNotificationDetails(
        'calendar_reminder_channel',
        'Calendar Reminders',
        channelDescription: 'Scheduled reminders for calendar events',
        importance: Importance.max,
        priority: Priority.high,
        enableVibration: true,
        enableLights: true,
        playSound: true,
      );

      const notificationDetails = NotificationDetails(android: androidDetails);

      await flutterLocalNotificationsPlugin.zonedSchedule(
        notificationId,
        title,
        body,
        scheduledTZ,
        notificationDetails,
        payload: payload,
        androidScheduleMode: AndroidScheduleMode.alarmClock,
        uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
      );

      print('FALLBACK: Scheduled ID $notificationId for $scheduledTZ');
    } catch (e) {
      print('FALLBACK: Error scheduling: $e');
    }
  }

  /// New implementation: Cancel notifications using native AlarmManager
  static Future<void> cancelEventReminders(int eventId) async {
    try {
      print('NATIVE: Cancelling reminders for event ID: $eventId');
      
      // Cancel all possible reminder notifications for this event (up to 10 reminders)
      for (int i = 0; i < 10; i++) {
        final notificationId = _generateNotificationId(eventId, i);
        
        try {
          // Call native AlarmManager for cancellation
          await _alarmChannel.invokeMethod('cancelNotification', {
            'id': notificationId,
          });
          
          print('NATIVE: Cancelled alarm ID $notificationId');
        } catch (e) {
          print('NATIVE: Error cancelling alarm ID $notificationId: $e');
          
          // Fallback: Cancel via flutter_local_notifications too
          await flutterLocalNotificationsPlugin.cancel(notificationId);
          print('FALLBACK: Cancelled flutter notification ID $notificationId');
        }
      }

      developer.log('Cancelled reminders for event ID: $eventId');
    } catch (e) {
      developer.log('Error cancelling event reminders: $e');
    }
  }

  /// Generate unique notification ID for event reminders - preserved as is
  static int _generateNotificationId(int eventId, int reminderIndex) {
    return eventId * 1000 + reminderIndex;
  }

  /// Generate reminder title - preserved as is
  static String _getReminderTitle(String eventTitle, int minutesBefore) {
    if (minutesBefore < 60) {
      return 'Reminder: $eventTitle in ${minutesBefore}min';
    } else if (minutesBefore < 1440) {
      final hours = minutesBefore ~/ 60;
      return 'Reminder: $eventTitle in ${hours}h';
    } else {
      final days = minutesBefore ~/ 1440;
      return 'Reminder: $eventTitle in ${days}d';
    }
  }

  /// Generate reminder body - preserved as is
  static String _getReminderBody(CalendarEvent event) {
    final timeStr = _formatEventTime(event.dateTime);
    final dateStr = _formatEventDate(event.dateTime);

    String body = '$dateStr at $timeStr';

    if (event.description != null && event.description!.isNotEmpty) {
      body += '\n\n${event.description}';
    }

    if (event.hasLinkedTask) {
      body += '\n\nLinked to task location';
    }

    return body;
  }

  /// Format event time - preserved as is
  static String _formatEventTime(DateTime dateTime) {
    final hour = dateTime.hour;
    final minute = dateTime.minute.toString().padLeft(2, '0');
    final period = hour < 12 ? 'AM' : 'PM';
    final displayHour = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour);
    return '$displayHour:$minute $period';
  }

  /// Format event date - preserved as is
  static String _formatEventDate(DateTime dateTime) {
    const months = [
      '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${months[dateTime.month]} ${dateTime.day}';
  }

  /// New method: Get pending notifications from native AlarmManager
  static Future<List<Map<String, dynamic>>> getNativePendingNotifications() async {
    try {
      final result = await _alarmChannel.invokeMethod('getScheduledNotifications');
      print('Native pending notifications: $result');
      
      if (result != null && result['notifications'] != null) {
        return List<Map<String, dynamic>>.from(result['notifications']);
      }
      
      return [];
    } catch (e) {
      print('Error getting native pending notifications: $e');
      return [];
    }
  }

  /// Get all pending notifications (hybrid - native + flutter fallback)
  static Future<List<PendingNotificationRequest>> getPendingNotifications() async {
    try {
      // Try to get native notifications first
      final nativeNotifications = await getNativePendingNotifications();
      print('Native notifications count: ${nativeNotifications.length}');
      
      // Also get flutter_local_notifications for fallback
      final flutterPending = await flutterLocalNotificationsPlugin.pendingNotificationRequests();
      print('Flutter notifications count: ${flutterPending.length}');
      
      developer.log('Total pending notifications: Native=${nativeNotifications.length}, Flutter=${flutterPending.length}');
      return flutterPending; // Return flutter pending for compatibility
    } catch (e) {
      developer.log('Error getting pending notifications: $e');
      return [];
    }
  }

  /// Cancel all calendar notifications (hybrid native + flutter)
  static Future<void> cancelAllCalendarNotifications() async {
    try {
      print('Cancelling all calendar notifications...');
      
      // Try to cancel native alarms (if available)
      try {
        await _alarmChannel.invokeMethod('cancelAllNotifications');
        print('Native alarms cancelled');
      } catch (e) {
        print('Could not cancel native alarms: $e');
      }
      
      // Cancel flutter_local_notifications
      final pending = await flutterLocalNotificationsPlugin.pendingNotificationRequests();

      for (final notification in pending) {
        if (notification.payload?.startsWith('calendar_event_') == true) {
          await flutterLocalNotificationsPlugin.cancel(notification.id);
        }
      }

      developer.log('Cancelled all calendar notifications (native + flutter)');
    } catch (e) {
      developer.log('Error cancelling calendar notifications: $e');
    }
  }
}

// ============ Existing functions - completely preserved ============

Future<void> initializeNotifications() async {
  const AndroidInitializationSettings initializationSettingsAndroid =
  AndroidInitializationSettings('@mipmap/ic_launcher');

  final InitializationSettings initializationSettings = InitializationSettings(
    android: initializationSettingsAndroid,
  );

  await flutterLocalNotificationsPlugin.initialize(initializationSettings);

  // Create notification channels
  await _createNotificationChannels();
}

Future<void> _createNotificationChannels() async {
  final androidPlugin = flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

  if (androidPlugin != null) {
    // Channel for geofence notifications
    const geofenceChannel = AndroidNotificationChannel(
      'geofence_channel',
      'Geofence Notifications',
      description: 'Notifications when entering/exiting geofence areas',
      importance: Importance.max,
      enableVibration: true,
    );

    // Channel for background notifications
    const backgroundChannel = AndroidNotificationChannel(
      'locado_background_channel',
      'Locado Background Notifications',
      description: 'Notifications from background location tracking',
      importance: Importance.max,
      enableVibration: true,
    );

    await androidPlugin.createNotificationChannel(geofenceChannel);
    await androidPlugin.createNotificationChannel(backgroundChannel);
  }
}

Future<void> showTestNotification() async {
  const AndroidNotificationDetails androidPlatformChannelSpecifics =
  AndroidNotificationDetails(
    'geofence_channel',
    'Geofence Notifications',
    channelDescription: 'Notifications for geofence events',
    importance: Importance.max,
    priority: Priority.high,
    ticker: 'ticker',
  );

  const NotificationDetails platformChannelSpecifics = NotificationDetails(
    android: androidPlatformChannelSpecifics,
  );

  await flutterLocalNotificationsPlugin.show(
    0,
    'Test Notification',
    'This is a test notification from Locado!',
    platformChannelSpecifics,
  );
}

// New function: Send notification for task with settings - preserved as is
Future<void> showTaskNotification(String taskTitle, double distance) async {
  final prefs = await SharedPreferences.getInstance();
  final notificationWithSound = prefs.getBool('notification_with_sound') ?? true;

  final AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
    'geofence_channel',
    'Geofence Notifications',
    channelDescription: 'Notifications when near a task location',
    importance: Importance.max,
    priority: Priority.high,
    visibility: NotificationVisibility.public,
    enableVibration: true,
    playSound: notificationWithSound,
    sound: notificationWithSound
        ? const RawResourceAndroidNotificationSound('notification')
        : null,
    styleInformation: BigTextStyleInformation(
      'You are ${distance.toStringAsFixed(0)}m from the task location.\n\nTap to open details.',
      contentTitle: 'You are near a task!',
      summaryText: taskTitle,
    ),
  );

  final NotificationDetails platformDetails = NotificationDetails(
    android: androidDetails,
  );

  final notificationId = DateTime.now().millisecondsSinceEpoch ~/ 1000;

  await flutterLocalNotificationsPlugin.show(
    notificationId,
    'You are near a task!',
    '$taskTitle - ${distance.toStringAsFixed(0)}m away',
    platformDetails,
  );
}