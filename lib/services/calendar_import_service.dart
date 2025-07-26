// lib/services/calendar_import_service.dart
import 'package:device_calendar/device_calendar.dart';
import 'package:flutter/material.dart';
import 'package:locado_final/models/calendar_event.dart';
import 'package:locado_final/helpers/database_helper.dart';
import 'package:locado_final/screens/notification_service.dart';
import 'package:timezone/timezone.dart' as tz;
import 'dart:developer' as developer;

/// Service for import/export calendars between device calendars and Locado calendars
class CalendarImportService {
  static final CalendarImportService _instance = CalendarImportService._internal();
  factory CalendarImportService() => _instance;
  CalendarImportService._internal();

  final DeviceCalendarPlugin _deviceCalendarPlugin = DeviceCalendarPlugin();

  /// Checks if calendar permissions are granted
  Future<bool> hasCalendarPermissions() async {
    try {
      var permissionsGranted = await _deviceCalendarPlugin.hasPermissions();
      return permissionsGranted.isSuccess && (permissionsGranted.data ?? false);
    } catch (e) {
      developer.log('❌ Error checking calendar permissions: $e');
      return false;
    }
  }

  /// Requests calendar permissions
  Future<bool> requestCalendarPermissions() async {
    try {
      var permissionsGranted = await _deviceCalendarPlugin.requestPermissions();
      return permissionsGranted.isSuccess && (permissionsGranted.data ?? false);
    } catch (e) {
      developer.log('❌ Error requesting calendar permissions: $e');
      return false;
    }
  }

  /// Gets all available calendars on device
  Future<List<Calendar>> getDeviceCalendars() async {
    try {
      final calendarsResult = await _deviceCalendarPlugin.retrieveCalendars();
      if (calendarsResult.isSuccess && calendarsResult.data != null) {
        return calendarsResult.data!;
      }
      return [];
    } catch (e) {
      developer.log('❌ Error getting device calendars: $e');
      return [];
    }
  }

  /// Imports all events from device calendar into Locado
  Future<CalendarImportResult> importFromDeviceCalendar({
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final result = CalendarImportResult();

    try {
      // Check permissions
      bool hasPermissions = await hasCalendarPermissions();
      if (!hasPermissions) {
        hasPermissions = await requestCalendarPermissions();
        if (!hasPermissions) {
          result.error = 'Calendar permissions not granted';
          return result;
        }
      }

      // Set default dates if not provided
      startDate ??= DateTime.now().subtract(const Duration(days: 365)); // Past year
      endDate ??= DateTime.now().add(const Duration(days: 365)); // Next year

      // Get all calendars
      final calendars = await getDeviceCalendars();
      developer.log('📅 Found ${calendars.length} calendars on device');

      // Get existing Locado events to check for duplicates
      final existingEvents = await DatabaseHelper.instance.getAllCalendarEvents();
      final existingTitlesAndDates = existingEvents.map((e) =>
      '${e.title}_${e.dateTime.millisecondsSinceEpoch}'
      ).toSet();

      // Import events from all calendars
      for (final calendar in calendars) {
        if (calendar.id == null) continue;

        try {
          final eventsResult = await _deviceCalendarPlugin.retrieveEvents(
            calendar.id!,
            RetrieveEventsParams(
              startDate: startDate,
              endDate: endDate,
            ),
          );

          if (eventsResult.isSuccess && eventsResult.data != null) {
            developer.log('📋 Calendar "${calendar.name}": ${eventsResult.data!.length} events');

            for (final deviceEvent in eventsResult.data!) {
              result.totalFound++;

              // Convert device event to Locado CalendarEvent
              final locadoEvent = _convertDeviceEventToLocado(deviceEvent);
              if (locadoEvent == null) {
                result.skipped++;
                continue;
              }

              // Check for duplicates (title + date)
              final eventKey = '${locadoEvent.title}_${locadoEvent.dateTime.millisecondsSinceEpoch}';
              if (existingTitlesAndDates.contains(eventKey)) {
                result.duplicates++;
                developer.log('⚠️ Duplicate event skipped: ${locadoEvent.title}');
                continue;
              }

              // Add to Locado database
              try {
                final eventId = await DatabaseHelper.instance.addCalendarEvent(locadoEvent);

                // Schedule notifications if has reminders
                if (locadoEvent.reminderMinutes.isNotEmpty) {
                  final eventWithId = locadoEvent.copyWith(id: eventId);
                  await NotificationService.scheduleEventReminders(eventWithId);
                }

                result.imported++;
                developer.log('✅ Imported: ${locadoEvent.title}');
              } catch (e) {
                result.failed++;
                developer.log('❌ Failed to import event: ${locadoEvent.title} - $e');
              }
            }
          }
        } catch (e) {
          developer.log('❌ Error processing calendar ${calendar.name}: $e');
        }
      }

      result.success = true;
      developer.log('🎉 Import completed: ${result.imported} imported, ${result.duplicates} duplicates, ${result.failed} failed');

    } catch (e) {
      result.error = 'Import error: $e';
      developer.log('❌ Calendar import error: $e');
    }

    return result;
  }

  /// Exports Locado events to device calendar
  Future<CalendarExportResult> exportToDeviceCalendar({
    String? targetCalendarId,
  }) async {
    final result = CalendarExportResult();

    try {
      // Check permissions
      bool hasPermissions = await hasCalendarPermissions();
      if (!hasPermissions) {
        hasPermissions = await requestCalendarPermissions();
        if (!hasPermissions) {
          result.error = 'Calendar permissions not granted';
          return result;
        }
      }

      // Find target calendar
      Calendar? targetCalendar;
      if (targetCalendarId != null) {
        final calendars = await getDeviceCalendars();
        try {
          targetCalendar = calendars.firstWhere((cal) => cal.id == targetCalendarId);
        } catch (e) {
          // Calendar not found
        }
      }

      // If target calendar not specified or not found, use first writable
      if (targetCalendar == null) {
        final calendars = await getDeviceCalendars();
        for (final calendar in calendars) {
          if (calendar.isReadOnly == false) {
            targetCalendar = calendar;
            break;
          }
        }
      }

      if (targetCalendar == null) {
        result.error = 'No writable calendar found on device';
        return result;
      }

      developer.log('📤 Exporting to calendar: ${targetCalendar.name} (ID: ${targetCalendar.id})');

      // Get all Locado events
      final locadoEvents = await DatabaseHelper.instance.getAllCalendarEvents();
      developer.log('📋 Found ${locadoEvents.length} Locado events to export');

      // Get existing events from target calendar to check duplicates
      final existingEventsResult = await _deviceCalendarPlugin.retrieveEvents(
        targetCalendar.id!,
        RetrieveEventsParams(
          startDate: DateTime.now().subtract(const Duration(days: 365)),
          endDate: DateTime.now().add(const Duration(days: 365)),
        ),
      );

      final existingEventKeys = <String>{};
      if (existingEventsResult.isSuccess && existingEventsResult.data != null) {
        for (final event in existingEventsResult.data!) {
          if (event.title != null && event.start != null) {
            existingEventKeys.add('${event.title}_${event.start!.millisecondsSinceEpoch}');
          }
        }
      }

      // Export each Locado event
      for (final locadoEvent in locadoEvents) {
        result.totalFound++;

        // Check for duplicates
        final eventKey = '${locadoEvent.title}_${locadoEvent.dateTime.millisecondsSinceEpoch}';
        if (existingEventKeys.contains(eventKey)) {
          result.duplicates++;
          developer.log('⚠️ Duplicate event skipped: ${locadoEvent.title}');
          continue;
        }

        // Convert Locado event to device event
        final deviceEvent = _convertLocadoEventToDevice(locadoEvent, targetCalendar.id!);

        try {
          final createResult = await _deviceCalendarPlugin.createOrUpdateEvent(deviceEvent);
          if (createResult?.isSuccess == true) {
            result.exported++;
            developer.log('✅ Exported: ${locadoEvent.title}');
          } else {
            result.failed++;
            developer.log('❌ Failed to export: ${locadoEvent.title} - Error: ${createResult?.errors?.join(", ") ?? "Unknown error"}');
          }
        } catch (e) {
          result.failed++;
          developer.log('❌ Export error for ${locadoEvent.title}: $e');
        }
      }

      result.success = true;
      result.targetCalendarName = targetCalendar.name;
      developer.log('🎉 Export completed: ${result.exported} exported, ${result.duplicates} duplicates, ${result.failed} failed');

    } catch (e) {
      result.error = 'Export error: $e';
      developer.log('❌ Calendar export error: $e');
    }

    return result;
  }

  /// Converts device calendar event to Locado CalendarEvent
  CalendarEvent? _convertDeviceEventToLocado(Event deviceEvent) {
    try {
      // Check required fields
      if (deviceEvent.title == null || deviceEvent.title!.isEmpty) return null;
      if (deviceEvent.start == null) return null;

      // Convert reminders
      List<int> reminderMinutes = [];
      if (deviceEvent.reminders != null) {
        for (final reminder in deviceEvent.reminders!) {
          if (reminder.minutes != null) {
            reminderMinutes.add(reminder.minutes!);
          }
        }
      }
      // Default reminder if none
      if (reminderMinutes.isEmpty) {
        reminderMinutes = [15];
      }

      // Default color
      String colorHex = '#2196F3'; // Default blue

      return CalendarEvent(
        title: deviceEvent.title!,
        description: deviceEvent.description,
        dateTime: deviceEvent.start!,
        reminderMinutes: reminderMinutes,
        colorHex: colorHex,
        isCompleted: false,
      );
    } catch (e) {
      developer.log('❌ Error converting device event: $e');
      return null;
    }
  }

  /// Converts Locado CalendarEvent to device Event
  Event _convertLocadoEventToDevice(CalendarEvent locadoEvent, String calendarId) {
    // Convert reminders
    List<Reminder> reminders = [];
    for (final minutes in locadoEvent.reminderMinutes) {
      reminders.add(Reminder(minutes: minutes));
    }

    // Convert to TZDateTime (required by device_calendar plugin)
    final startTZ = tz.TZDateTime.from(locadoEvent.dateTime, tz.local);
    final endTZ = tz.TZDateTime.from(
      locadoEvent.dateTime.add(const Duration(hours: 1)), // Default 1h duration
      tz.local,
    );

    return Event(
      calendarId, // Fixed: Properly set calendar ID
      title: locadoEvent.title,
      description: locadoEvent.description,
      start: startTZ,
      end: endTZ,
      reminders: reminders,
    );
  }
}

/// Result class for import operations
class CalendarImportResult {
  bool success = false;
  String? error;
  int totalFound = 0;
  int imported = 0;
  int duplicates = 0;
  int skipped = 0;
  int failed = 0;

  String get summary {
    if (!success) return error ?? 'Import failed';
    return 'Found: $totalFound, Imported: $imported, Duplicates: $duplicates, Failed: $failed';
  }
}

/// Result class for export operations
class CalendarExportResult {
  bool success = false;
  String? error;
  int totalFound = 0;
  int exported = 0;
  int duplicates = 0;
  int failed = 0;
  String? targetCalendarName;

  String get summary {
    if (!success) return error ?? 'Export failed';
    return 'Found: $totalFound, Exported: $exported, Duplicates: $duplicates, Failed: $failed';
  }
}