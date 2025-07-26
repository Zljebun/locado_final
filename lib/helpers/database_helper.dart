import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:locado_final/models/location_model.dart';
import 'package:locado_final/models/task_location.dart';
import 'package:locado_final/models/calendar_event.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();

  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('locations.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);
    return openDatabase(
      path,
      version: 3, // 🆕 POVEĆANA VERZIJA SA 2 NA 3
      onCreate: _createDB,
      onUpgrade: _onUpgrade,
    );
  }

  Future _createDB(Database db, int version) async {
    // Postojeće tabele
    await db.execute('''
      CREATE TABLE locations(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        latitude REAL,
        longitude REAL,
        description TEXT,
        type TEXT
      )
    ''');

    // 🆕 AŽURIRANA task_locations tabela sa novim poljima
    await db.execute('''
      CREATE TABLE task_locations(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        latitude REAL NOT NULL,
        longitude REAL NOT NULL,
        title TEXT NOT NULL,
        taskItems TEXT NOT NULL,
        colorHex TEXT NOT NULL,
        scheduledDateTime TEXT,
        linkedCalendarEventId INTEGER,
        FOREIGN KEY (linkedCalendarEventId) REFERENCES calendar_events (id) ON DELETE SET NULL
      )
    ''');

    // Calendar eventi tabela
    await db.execute('''
      CREATE TABLE calendar_events(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT NOT NULL,
        description TEXT,
        dateTime INTEGER NOT NULL,
        reminderMinutes TEXT NOT NULL,
        colorHex TEXT NOT NULL,
        linkedTaskLocationId INTEGER,
        isCompleted INTEGER NOT NULL DEFAULT 0,
        completedAt INTEGER,
        createdAt INTEGER NOT NULL,
        updatedAt INTEGER NOT NULL,
        FOREIGN KEY (linkedTaskLocationId) REFERENCES task_locations (id) ON DELETE SET NULL
      )
    ''');
  }

  // 🆕 AŽURIRANA MIGRATION LOGIKA
  Future _onUpgrade(Database db, int oldVersion, int newVersion) async {
    print('🔄 Upgrading database from version $oldVersion to $newVersion');

    if (oldVersion < 2) {
      // Postojeća migration za calendar_events
      await db.execute('''
        CREATE TABLE calendar_events(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          title TEXT NOT NULL,
          description TEXT,
          dateTime INTEGER NOT NULL,
          reminderMinutes TEXT NOT NULL,
          colorHex TEXT NOT NULL,
          linkedTaskLocationId INTEGER,
          isCompleted INTEGER NOT NULL DEFAULT 0,
          completedAt INTEGER,
          createdAt INTEGER NOT NULL,
          updatedAt INTEGER NOT NULL,
          FOREIGN KEY (linkedTaskLocationId) REFERENCES task_locations (id) ON DELETE SET NULL
        )
      ''');
      print('✅ Added calendar_events table');
    }

    // 🆕 NOVA MIGRATION za verziju 3
    if (oldVersion < 3) {
      try {
        await db.execute('ALTER TABLE task_locations ADD COLUMN scheduledDateTime TEXT');
        print('✅ Added scheduledDateTime column to task_locations');
      } catch (e) {
        print('⚠️ scheduledDateTime column might already exist: $e');
      }

      try {
        await db.execute('ALTER TABLE task_locations ADD COLUMN linkedCalendarEventId INTEGER');
        print('✅ Added linkedCalendarEventId column to task_locations');
      } catch (e) {
        print('⚠️ linkedCalendarEventId column might already exist: $e');
      }

      print('✅ Database upgraded to version 3 - bidirectional task-calendar linking enabled');
    }
  }

  // ============ POSTOJEĆE LOCATION METODE ============
  Future<int> addLocation(Location location) async {
    final db = await instance.database;
    return db.insert('locations', location.toMap());
  }

  Future<List<Location>> getAllLocations() async {
    final db = await instance.database;
    final result = await db.query('locations');
    return result.map((map) => Location.fromMap(map)).toList();
  }

  // ============ TASK LOCATION METODE ============
  Future<int> addTaskLocation(TaskLocation taskLocation) async {
    final db = await instance.database;
    return db.insert('task_locations', taskLocation.toMap());
  }

  Future<List<TaskLocation>> getAllTaskLocations() async {
    final db = await instance.database;
    final result = await db.query('task_locations');
    return result.map((map) => TaskLocation.fromMap(map)).toList();
  }

  // 🆕 AŽURIRAN deleteTaskLocation sa bidirekcional cleanup
  Future<int> deleteTaskLocation(int id) async {
    final db = await instance.database;

    // Get the task to check if it has linked calendar event
    final task = await getTaskLocationById(id);

    if (task != null && task.linkedCalendarEventId != null) {
      // Delete the linked calendar event
      await deleteCalendarEvent(task.linkedCalendarEventId!);
      print('✅ Deleted linked calendar event ${task.linkedCalendarEventId}');
    }

    // Delete the task
    return await db.delete(
      'task_locations',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> updateTaskLocation(TaskLocation taskLocation) async {
    final db = await instance.database;
    return await db.update(
      'task_locations',
      taskLocation.toMap(),
      where: 'id = ?',
      whereArgs: [taskLocation.id],
    );
  }

  Future<void> printAllTaskLocations() async {
    final db = await database;
    final results = await db.query('task_locations');
    for (final row in results) {
      print(row);
    }
  }

  // ============ CALENDAR EVENT METODE ============

  /// Dodaje novi kalendar event
  Future<int> addCalendarEvent(CalendarEvent calendarEvent) async {
    final db = await instance.database;
    return db.insert('calendar_events', calendarEvent.toMap());
  }

  /// Vraća sve kalendar eventi
  Future<List<CalendarEvent>> getAllCalendarEvents() async {
    final db = await instance.database;
    final result = await db.query(
      'calendar_events',
      orderBy: 'dateTime ASC',
    );
    return result.map((map) => CalendarEvent.fromMap(map)).toList();
  }

  /// Vraća calendar eventi za određeni datum
  Future<List<CalendarEvent>> getCalendarEventsForDate(DateTime date) async {
    final db = await instance.database;

    // Početak i kraj dana
    final startOfDay = DateTime(date.year, date.month, date.day);
    final endOfDay = startOfDay.add(const Duration(days: 1)).subtract(const Duration(milliseconds: 1));

    final result = await db.query(
      'calendar_events',
      where: 'dateTime >= ? AND dateTime <= ?',
      whereArgs: [startOfDay.millisecondsSinceEpoch, endOfDay.millisecondsSinceEpoch],
      orderBy: 'dateTime ASC',
    );
    return result.map((map) => CalendarEvent.fromMap(map)).toList();
  }

  /// Vraća nadolazeće eventi (budući eventi)
  Future<List<CalendarEvent>> getUpcomingCalendarEvents({int limit = 10}) async {
    final db = await instance.database;
    final now = DateTime.now().millisecondsSinceEpoch;

    final result = await db.query(
      'calendar_events',
      where: 'dateTime > ? AND isCompleted = 0',
      whereArgs: [now],
      orderBy: 'dateTime ASC',
      limit: limit,
    );
    return result.map((map) => CalendarEvent.fromMap(map)).toList();
  }

  /// Vraća prošle eventi
  Future<List<CalendarEvent>> getPastCalendarEvents({int limit = 20}) async {
    final db = await instance.database;
    final now = DateTime.now().millisecondsSinceEpoch;

    final result = await db.query(
      'calendar_events',
      where: 'dateTime < ?',
      whereArgs: [now],
      orderBy: 'dateTime DESC',
      limit: limit,
    );
    return result.map((map) => CalendarEvent.fromMap(map)).toList();
  }

  /// Vraća eventi vezane za određeni TaskLocation
  Future<List<CalendarEvent>> getCalendarEventsForTask(int taskLocationId) async {
    final db = await instance.database;
    final result = await db.query(
      'calendar_events',
      where: 'linkedTaskLocationId = ?',
      whereArgs: [taskLocationId],
      orderBy: 'dateTime ASC',
    );
    return result.map((map) => CalendarEvent.fromMap(map)).toList();
  }

  /// Ažurira calendar event
  Future<int> updateCalendarEvent(CalendarEvent calendarEvent) async {
    final db = await instance.database;
    return await db.update(
      'calendar_events',
      calendarEvent.toMap(),
      where: 'id = ?',
      whereArgs: [calendarEvent.id],
    );
  }

  /// 🆕 AŽURIRAN deleteCalendarEvent sa bidirekcional cleanup
  Future<int> deleteCalendarEvent(int id) async {
    final db = await instance.database;

    // First unlink any tasks linked to this event
    await db.update(
      'task_locations',
      {'linkedCalendarEventId': null},
      where: 'linkedCalendarEventId = ?',
      whereArgs: [id],
    );

    // Then delete the calendar event
    return await db.delete(
      'calendar_events',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Označava event kao završen
  Future<int> markCalendarEventAsCompleted(int id) async {
    final db = await instance.database;
    return await db.update(
      'calendar_events',
      {
        'isCompleted': 1,
        'completedAt': DateTime.now().millisecondsSinceEpoch,
        'updatedAt': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Označava event kao nezavršen
  Future<int> markCalendarEventAsIncomplete(int id) async {
    final db = await instance.database;
    return await db.update(
      'calendar_events',
      {
        'isCompleted': 0,
        'completedAt': null,
        'updatedAt': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Briše sve završene eventi starije od određenog broja dana
  Future<int> deleteOldCompletedEvents({int daysOld = 30}) async {
    final db = await instance.database;
    final cutoffDate = DateTime.now().subtract(Duration(days: daysOld));

    return await db.delete(
      'calendar_events',
      where: 'isCompleted = 1 AND completedAt < ?',
      whereArgs: [cutoffDate.millisecondsSinceEpoch],
    );
  }

  /// Debug metoda za calendar eventi
  Future<void> printAllCalendarEvents() async {
    final db = await database;
    final results = await db.query('calendar_events', orderBy: 'dateTime ASC');
    print('=== CALENDAR EVENTS ===');
    for (final row in results) {
      final event = CalendarEvent.fromMap(row);
      print('${event.id}: ${event.title} - ${event.dateTime}');
    }
    print('=====================');
  }

  /// Vraća statistike za calendar eventi
  Future<Map<String, int>> getCalendarEventStats() async {
    final db = await instance.database;

    final totalResult = await db.rawQuery('SELECT COUNT(*) as count FROM calendar_events');
    final completedResult = await db.rawQuery('SELECT COUNT(*) as count FROM calendar_events WHERE isCompleted = 1');
    final upcomingResult = await db.rawQuery('SELECT COUNT(*) as count FROM calendar_events WHERE dateTime > ? AND isCompleted = 0', [DateTime.now().millisecondsSinceEpoch]);

    return {
      'total': totalResult.first['count'] as int,
      'completed': completedResult.first['count'] as int,
      'upcoming': upcomingResult.first['count'] as int,
    };
  }

  // ============ 🆕 TASK-CALENDAR BIDIRECTIONAL SYNC METODE ============

  /// Get task by ID
  Future<TaskLocation?> getTaskLocationById(int id) async {
    final db = await instance.database;
    final List<Map<String, dynamic>> maps = await db.query(
      'task_locations',
      where: 'id = ?',
      whereArgs: [id],
    );

    if (maps.isNotEmpty) {
      return TaskLocation.fromMap(maps.first);
    }
    return null;
  }

  /// Link task sa calendar event
  Future<void> linkTaskToCalendarEvent(int taskId, int calendarEventId) async {
    final db = await database;
    await db.update(
      'task_locations',
      {'linkedCalendarEventId': calendarEventId},
      where: 'id = ?',
      whereArgs: [taskId],
    );
    print('✅ Linked task $taskId to calendar event $calendarEventId');
  }

  /// Unlink task od calendar event
  Future<void> unlinkTaskFromCalendarEvent(int taskId) async {
    final db = await database;
    await db.update(
      'task_locations',
      {'linkedCalendarEventId': null},
      where: 'id = ?',
      whereArgs: [taskId],
    );
    print('✅ Unlinked task $taskId from calendar event');
  }

  /// Update scheduled time za task
  Future<void> updateTaskScheduledTime(int taskId, DateTime? scheduledDateTime) async {
    final db = await database;
    await db.update(
      'task_locations',
      {'scheduledDateTime': scheduledDateTime?.toIso8601String()},
      where: 'id = ?',
      whereArgs: [taskId],
    );
    print('✅ Updated scheduled time for task $taskId: ${scheduledDateTime?.toString() ?? 'removed'}');
  }

  /// Get task by linked calendar event ID
  Future<TaskLocation?> getTaskByLinkedCalendarEvent(int calendarEventId) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'task_locations',
      where: 'linkedCalendarEventId = ?',
      whereArgs: [calendarEventId],
    );

    if (maps.isNotEmpty) {
      return TaskLocation.fromMap(maps.first);
    }
    return null;
  }

  /// Get tasks scheduled for specific date
  Future<List<TaskLocation>> getTasksScheduledForDate(DateTime date) async {
    final db = await database;
    final startOfDay = DateTime(date.year, date.month, date.day);
    final endOfDay = startOfDay.add(Duration(days: 1)).subtract(Duration(milliseconds: 1));

    final List<Map<String, dynamic>> maps = await db.query(
      'task_locations',
      where: 'scheduledDateTime >= ? AND scheduledDateTime <= ?',
      whereArgs: [startOfDay.toIso8601String(), endOfDay.toIso8601String()],
      orderBy: 'scheduledDateTime ASC',
    );

    return List.generate(maps.length, (i) => TaskLocation.fromMap(maps[i]));
  }

  /// Get upcoming scheduled tasks
  Future<List<TaskLocation>> getUpcomingScheduledTasks({int limit = 5}) async {
    final db = await database;
    final now = DateTime.now();

    final List<Map<String, dynamic>> maps = await db.query(
      'task_locations',
      where: 'scheduledDateTime >= ?',
      whereArgs: [now.toIso8601String()],
      orderBy: 'scheduledDateTime ASC',
      limit: limit,
    );

    return List.generate(maps.length, (i) => TaskLocation.fromMap(maps[i]));
  }

  /// Get all scheduled tasks
  Future<List<TaskLocation>> getAllScheduledTasks() async {
    final db = await database;

    final List<Map<String, dynamic>> maps = await db.query(
      'task_locations',
      where: 'scheduledDateTime IS NOT NULL',
      orderBy: 'scheduledDateTime ASC',
    );

    return List.generate(maps.length, (i) => TaskLocation.fromMap(maps[i]));
  }

  /// Debug: Print all tasks with scheduling info
  Future<void> printAllTasksWithScheduling() async {
    final db = await database;
    final results = await db.query('task_locations', orderBy: 'scheduledDateTime ASC');
    print('=== TASKS WITH SCHEDULING ===');
    for (final row in results) {
      final task = TaskLocation.fromMap(row);
      print('${task.id}: ${task.title} - Scheduled: ${task.scheduledDateTime?.toString() ?? 'None'} - Linked Event: ${task.linkedCalendarEventId ?? 'None'}');
    }
    print('============================');
  }
}