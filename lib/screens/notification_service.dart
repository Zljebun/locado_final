// lib/services/notification_service.dart
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:locado_final/models/calendar_event.dart';
import 'package:timezone/timezone.dart' as tz;
import 'dart:developer' as developer;

// ✅ POSTOJEĆI GLOBAL INSTANCE - ZADRŽAN
final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
FlutterLocalNotificationsPlugin();

// 🆕 NOVA CLASS ZA CALENDAR NOTIFICATIONS
class NotificationService {
  static bool _isCalendarInitialized = false;
  static const String _calendarChannelId = 'calendar_reminder_channel';

  /// Initialize calendar notifications (dodatno za postojeće)
  static Future<void> initializeCalendarNotifications() async {
    if (_isCalendarInitialized) return;

    try {
      // Kreiraj calendar notification channel
      await _createCalendarNotificationChannel();
      _isCalendarInitialized = true;

      developer.log('✅ Calendar notifications initialized');
    } catch (e) {
      developer.log('❌ Error initializing calendar notifications: $e');
    }
  }

  /// Create calendar notification channel
  static Future<void> _createCalendarNotificationChannel() async {
    final androidPlugin = flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

    if (androidPlugin != null) {
      // NEW: Calendar reminder channel
      const calendarChannel = AndroidNotificationChannel(
        _calendarChannelId,
        'Calendar Reminders',
        description: 'Scheduled reminders for calendar events',
        importance: Importance.high,
        enableVibration: true,
        enableLights: true,
      );

      await androidPlugin.createNotificationChannel(calendarChannel);
      developer.log('✅ Calendar notification channel created');
    }
  }

  /// Schedule notifications for a calendar event
  static Future<void> scheduleEventReminders(CalendarEvent event) async {
    if (!_isCalendarInitialized) await initializeCalendarNotifications();

    if (event.reminderMinutes.isEmpty) {
      developer.log('📅 No reminders set for event: ${event.title}');
      return;
    }

    try {
      // Cancel existing notifications for this event
      await cancelEventReminders(event.id!);

      // Schedule new notifications
      for (int i = 0; i < event.reminderMinutes.length; i++) {
        final reminderMinutes = event.reminderMinutes[i];
        final notificationId = _generateNotificationId(event.id!, i);

        final scheduledDate = event.dateTime.subtract(Duration(minutes: reminderMinutes));

        // Only schedule if the reminder time is in the future
        if (scheduledDate.isAfter(DateTime.now())) {
          await _scheduleNotification(
            notificationId: notificationId,
            title: _getReminderTitle(event.title, reminderMinutes),
            body: _getReminderBody(event),
            scheduledDate: scheduledDate,
            payload: 'calendar_event_${event.id}',
          );

          developer.log('📅 Scheduled reminder for "${event.title}" - ${reminderMinutes}min before');
        } else {
          developer.log('⏰ Skipped past reminder for "${event.title}" - ${reminderMinutes}min before');
        }
      }
    } catch (e) {
      developer.log('❌ Error scheduling event reminders: $e');
    }
  }

  /// Cancel notifications for a calendar event
  static Future<void> cancelEventReminders(int eventId) async {
    try {
      // Cancel all possible reminder notifications for this event (up to 10 reminders)
      for (int i = 0; i < 10; i++) {
        final notificationId = _generateNotificationId(eventId, i);
        await flutterLocalNotificationsPlugin.cancel(notificationId);
      }

      developer.log('📅 Cancelled reminders for event ID: $eventId');
    } catch (e) {
      developer.log('❌ Error cancelling event reminders: $e');
    }
  }

  /// Schedule a single notification
  static Future<void> _scheduleNotification({
    required int notificationId,
    required String title,
    required String body,
    required DateTime scheduledDate,
    required String payload,
  }) async {
    try {
      final scheduledTZ = tz.TZDateTime.from(scheduledDate, tz.local);

      final androidDetails = AndroidNotificationDetails(
        _calendarChannelId,
        'Calendar Reminders',
        channelDescription: 'Scheduled reminders for calendar events',
        importance: Importance.high,
        priority: Priority.high,
        enableVibration: true,
        enableLights: true,
        icon: '@mipmap/ic_launcher',
        styleInformation: BigTextStyleInformation(
          body,
          contentTitle: title,
          summaryText: 'Locado Calendar',
        ),
      );

      final notificationDetails = NotificationDetails(android: androidDetails);

      await flutterLocalNotificationsPlugin.zonedSchedule(
        notificationId,
        title,
        body,
        scheduledTZ,
        notificationDetails,
        payload: payload,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
      );

      developer.log('✅ Scheduled notification ID: $notificationId for $scheduledDate');
    } catch (e) {
      developer.log('❌ Error scheduling notification: $e');
    }
  }

  /// Generate unique notification ID for event reminders
  static int _generateNotificationId(int eventId, int reminderIndex) {
    // Use event ID + reminder index to create unique IDs
    // Event ID 123 with reminder index 0 = 1230000
    // Event ID 123 with reminder index 1 = 1230001
    return eventId * 1000 + reminderIndex;
  }

  /// Generate reminder title
  static String _getReminderTitle(String eventTitle, int minutesBefore) {
    if (minutesBefore < 60) {
      return '⏰ Reminder: $eventTitle in ${minutesBefore}min';
    } else if (minutesBefore < 1440) {
      final hours = minutesBefore ~/ 60;
      return '⏰ Reminder: $eventTitle in ${hours}h';
    } else {
      final days = minutesBefore ~/ 1440;
      return '⏰ Reminder: $eventTitle in ${days}d';
    }
  }

  /// Generate reminder body
  static String _getReminderBody(CalendarEvent event) {
    final timeStr = _formatEventTime(event.dateTime);
    final dateStr = _formatEventDate(event.dateTime);

    String body = '📅 $dateStr at $timeStr';

    if (event.description != null && event.description!.isNotEmpty) {
      body += '\n\n${event.description}';
    }

    if (event.hasLinkedTask) {
      body += '\n\n📍 Linked to task location';
    }

    return body;
  }

  /// Format event time
  static String _formatEventTime(DateTime dateTime) {
    final hour = dateTime.hour;
    final minute = dateTime.minute.toString().padLeft(2, '0');
    final period = hour < 12 ? 'AM' : 'PM';
    final displayHour = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour);
    return '$displayHour:$minute $period';
  }

  /// Format event date
  static String _formatEventDate(DateTime dateTime) {
    const months = [
      '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${months[dateTime.month]} ${dateTime.day}';
  }

  /// Get all pending notifications (for debugging)
  static Future<List<PendingNotificationRequest>> getPendingNotifications() async {
    try {
      final pending = await flutterLocalNotificationsPlugin.pendingNotificationRequests();
      developer.log('📱 Pending notifications: ${pending.length}');
      return pending;
    } catch (e) {
      developer.log('❌ Error getting pending notifications: $e');
      return [];
    }
  }

  /// Cancel all calendar notifications
  static Future<void> cancelAllCalendarNotifications() async {
    try {
      final pending = await flutterLocalNotificationsPlugin.pendingNotificationRequests();

      for (final notification in pending) {
        if (notification.payload?.startsWith('calendar_event_') == true) {
          await flutterLocalNotificationsPlugin.cancel(notification.id);
        }
      }

      developer.log('📅 Cancelled all calendar notifications');
    } catch (e) {
      developer.log('❌ Error cancelling calendar notifications: $e');
    }
  }
}

// ✅ ============ POSTOJEĆE FUNKCIJE - POTPUNO ZADRŽANE ============ ✅

Future<void> initializeNotifications() async {
  const AndroidInitializationSettings initializationSettingsAndroid =
  AndroidInitializationSettings('@mipmap/ic_launcher');

  final InitializationSettings initializationSettings = InitializationSettings(
    android: initializationSettingsAndroid,
  );

  await flutterLocalNotificationsPlugin.initialize(initializationSettings);

  // Kreiraj notification channels
  await _createNotificationChannels();
}

Future<void> _createNotificationChannels() async {
  final androidPlugin = flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

  if (androidPlugin != null) {
    // Kanal za geofence notifikacije
    const geofenceChannel = AndroidNotificationChannel(
      'geofence_channel',
      'Geofence Notifications',
      description: 'Notifications when entering/exiting geofence areas',
      importance: Importance.max,
      enableVibration: true,
    );

    // Kanal za background notifikacije
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

// 🆕 NOVA FUNKCIJA: Pošalji notifikaciju za task sa settings
Future<void> showTaskNotification(String taskTitle, double distance) async {
  // Učitaj settings
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
      '📍 Nalazite se ${distance.toStringAsFixed(0)}m od lokacije zadatka.\n\nTapnite da otvorite detalje.',
      contentTitle: '🔔 Blizu ste zadatka!',
      summaryText: taskTitle,
    ),
  );

  final NotificationDetails platformDetails = NotificationDetails(
    android: androidDetails,
  );

  final notificationId = DateTime.now().millisecondsSinceEpoch ~/ 1000;

  await flutterLocalNotificationsPlugin.show(
    notificationId,
    '🔔 Blizu ste zadatka!',
    '📍 $taskTitle - ${distance.toStringAsFixed(0)}m daleko',
    platformDetails,
  );
}