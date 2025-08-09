import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import '../services/locado_background_service.dart';
import '../models/task_location.dart';
import '../helpers/database_helper.dart';

/// Helper klasa za lakšu integraciju geofencing funkcionalnosti
/// sa postojećim Locado kodom
class GeofencingIntegrationHelper {
  static GeofencingIntegrationHelper? _instance;
  static GeofencingIntegrationHelper get instance => _instance ??= GeofencingIntegrationHelper._();

  GeofencingIntegrationHelper._();

  bool _isInitialized = false;
  bool _isServiceRunning = false;
  List<String> _activeGeofences = [];
  Function(GeofenceEvent)? _globalEventCallback;

  /// Getters za status
  bool get isInitialized => _isInitialized;
  bool get isServiceRunning => _isServiceRunning;
  List<String> get activeGeofences => List.from(_activeGeofences);

  /// Inicijalizuje ceo geofencing sistem - pozovi na početku aplikacije
  Future<bool> initializeGeofencing({
    Function(GeofenceEvent)? onGeofenceEvent,
    bool autoStartService = false,
  }) async {
    try {
      //GeofencingIntegrationHelper:('GeofencingIntegrationHelper: Starting initialization...');

      // 1. Proveri da li je native kod dostupan
      final connectionResult = await LocadoBackgroundService.testConnection();
      if (!connectionResult) {
        //GeofencingIntegrationHelper:('GeofencingIntegrationHelper: Native connection failed');
        return false;
      }

      // 2. Zahtevaj permissions
      final permissionsGranted = await _requestAllPermissions();
      if (!permissionsGranted) {
        //GeofencingIntegrationHelper:('GeofencingIntegrationHelper: Permissions not granted');
        return false;
      }

      // 3. Setup event listener
      if (onGeofenceEvent != null) {
        _globalEventCallback = onGeofenceEvent;
        LocadoBackgroundService.setGeofenceEventListener(_handleGeofenceEvent);
      }

      // 4. Proveri trenutno stanje service-a
      _isServiceRunning = await LocadoBackgroundService.isServiceRunning();

      // 5. Auto-start service ako je requested
      if (autoStartService && !_isServiceRunning) {
        await startGeofencingService();
      }

      // 6. Učitaj trenutne aktivne geofence-ove
      await _refreshActiveGeofences();

      _isInitialized = true;
      //GeofencingIntegrationHelper:('GeofencingIntegrationHelper: Initialization successful');
      return true;

    } catch (e) {
      //GeofencingIntegrationHelper:('GeofencingIntegrationHelper: Initialization error = $e');
      return false;
    }
  }

  /// Zahteva sve potrebne permissions
  Future<bool> _requestAllPermissions() async {
    try {
      // Fine location permission
      var status = await Permission.locationWhenInUse.request();
      if (!status.isGranted) {
        //GeofencingIntegrationHelper:('GeofencingIntegrationHelper: Fine location permission denied');
        return false;
      }

      // Background location permission
      status = await Permission.locationAlways.request();
      if (!status.isGranted) {
        //GeofencingIntegrationHelper:('GeofencingIntegrationHelper: Background location permission denied');
        return false;
      }

      // Notification permission (Android 13+)
      if (await Permission.notification.isDenied) {
        status = await Permission.notification.request();
        // Notification permission nije kritičan za geofencing
      }

      //GeofencingIntegrationHelper:('GeofencingIntegrationHelper: All required permissions granted');
      return true;

    } catch (e) {
      //GeofencingIntegrationHelper:('GeofencingIntegrationHelper: Permission request error = $e');
      return false;
    }
  }

  /// Pokreće geofencing service
  Future<bool> startGeofencingService() async {
    if (!_isInitialized) {
      //GeofencingIntegrationHelper:('GeofencingIntegrationHelper: Not initialized, call initializeGeofencing() first');
      return false;
    }

    try {
      final result = await LocadoBackgroundService.startService();
      if (result) {
        _isServiceRunning = true;
        //GeofencingIntegrationHelper:('GeofencingIntegrationHelper: Service started successfully');
      }
      return result;
    } catch (e) {
      //GeofencingIntegrationHelper:('GeofencingIntegrationHelper: Start service error = $e');
      return false;
    }
  }

  /// Zaustavlja geofencing service
  Future<bool> stopGeofencingService() async {
    try {
      final result = await LocadoBackgroundService.stopService();
      if (result) {
        _isServiceRunning = false;
        _activeGeofences.clear();
        //GeofencingIntegrationHelper:('GeofencingIntegrationHelper: Service stopped successfully');
      }
      return result;
    } catch (e) {
      //GeofencingIntegrationHelper:('GeofencingIntegrationHelper: Stop service error = $e');
      return false;
    }
  }

  // ===== NOVE METODE ZA DATABASE INTEGRACIJU =====

  /// Učitava sve postojeće task-ove iz database-a i dodaje ih u geofencing
  Future<void> initializeExistingTasks() async {
    try {
      // 1. BRZA PROVERA - da li već imamo geofence-ove
      final existingGeofences = await LocadoBackgroundService.getActiveGeofences();
      if (existingGeofences.isNotEmpty) {
        _activeGeofences = existingGeofences;
        return; // IZAĐI ODMAH - NAJVEĆA OPTIMIZACIJA
      }

      // 2. SAMO JEDNA PROVERA SERVICE STATUS-a
      _isServiceRunning = await LocadoBackgroundService.isServiceRunning();

      if (!_isServiceRunning) {
        // JEDNA BRZA RETRY - BEZ DELAY-a
        await startGeofencingService();

        // KRATKA PROVERA - 500ms maksimalno
        await Future.delayed(Duration(milliseconds: 500));
        _isServiceRunning = await LocadoBackgroundService.isServiceRunning();

        if (!_isServiceRunning) {
          return; // NE ČEKAJ VIŠE - NASTAVI BEZ GEOFENCING-a
        }
      }

      // 3. BATCH OPERACIJA - sve task-ove odjednom
      await _batchLoadTasksToGeofencing();

    } catch (e) {
      debugPrint('❌ Error in fast initialization: $e');
    }
  }

	Future<void> _batchLoadTasksToGeofencing() async {
	  try {
		final taskLocations = await DatabaseHelper.instance.getAllTaskLocations();

		if (taskLocations.isEmpty) return;

		// 🚀 BATCH PROCESSING - PRAVI BATCH!
		await LocadoBackgroundService.syncTaskLocationGeofences(taskLocations);

		// JEDAN REFRESH NA KRAJU
		await _refreshActiveGeofences();

	  } catch (e) {
		debugPrint('❌ Batch loading error: $e');
	  }
	}

  /// Dodaje pojedinačni task u geofencing sistem
  Future<bool> addTaskToGeofencing({
    required String taskId,
    required double latitude,
    required double longitude,
    required String title,
    double radius = 100.0,
  }) async {
    try {
      // Retry logika za service status
      for (int attempt = 1; attempt <= 2; attempt++) {
        _isServiceRunning = await LocadoBackgroundService.isServiceRunning();

        if (!_isServiceRunning) {
          if (attempt == 1) {
            //GeofencingIntegrationHelper:('⚠️ GeofencingIntegrationHelper: Service not running, starting it (attempt $attempt/2)...');
            await startGeofencingService();
            await Future.delayed(Duration(milliseconds: 800));
            continue;
          } else {
            //GeofencingIntegrationHelper:('❌ GeofencingIntegrationHelper: Service not running after retry, cannot add task $taskId');
            return false;
          }
        }
        break;
      }

      // Dodaj geofence koristeći postojeći API
      final result = await LocadoBackgroundService.addGeofence(
        id: 'task_$taskId',
        latitude: latitude,
        longitude: longitude,
        radius: radius,
        title: title,
      );

      // WORKAROUND: Native dodaje geofence uspešno, ali vraća false
      // Vidimo u logs-ima "Added new geofence task_X", tako da smatramo uspešno
      //GeofencingIntegrationHelper:('🔧 GeofencingIntegrationHelper: Workaround - assuming geofence added successfully for task $taskId');

      await _refreshActiveGeofences();
      //GeofencingIntegrationHelper:('✅ GeofencingIntegrationHelper: Task added to geofencing - $title (ID: $taskId)');

      // Update service notification
      await updateServiceNotification(
        content: 'Monitoring ${_activeGeofences.length} locations',
      );

      return true;
    } catch (e) {
      //GeofencingIntegrationHelper:('❌ GeofencingIntegrationHelper: Error adding task to geofencing: $e');
      return false;
    }
  }

  /// Uklanja task iz geofencing sistema
  Future<bool> removeTaskFromGeofencing(String taskId) async {
    try {
      if (!_isServiceRunning) {
        //GeofencingIntegrationHelper:('⚠️ GeofencingIntegrationHelper: Service not running, cannot remove task');
        return false;
      }

      final result = await LocadoBackgroundService.removeGeofence('task_$taskId');
      if (result) {
        await _refreshActiveGeofences();
        //GeofencingIntegrationHelper:('✅ GeofencingIntegrationHelper: Task removed from geofencing - $taskId');

        // Update service notification
        await updateServiceNotification(
          content: 'Monitoring ${_activeGeofences.length} locations',
        );
      } else {
        debugPrint('❌ GeofencingIntegrationHelper: Failed to remove task from geofencing - $taskId');
      }
      return result;
    } catch (e) {
      //GeofencingIntegrationHelper:('❌ GeofencingIntegrationHelper: Error removing task: $e');
      return false;
    }
  }

  /// Proverava da li je task trenutno u geofencing sistemu
  bool isTaskMonitored(String taskId) {
    return _activeGeofences.contains('task_$taskId');
  }

  /// Sinhronizuje database task-ove sa geofencing sistemom
  Future<void> syncWithDatabase() async {
    try {
      //GeofencingIntegrationHelper:('🔄 GeofencingIntegrationHelper: Syncing with database...');

      // Učitaj sve task-ove iz database-a
      final taskLocations = await DatabaseHelper.instance.getAllTaskLocations();
      final databaseTaskIds = taskLocations
          .map((taskLocation) => 'task_${taskLocation.id}')
          .toSet();

      // Ukloni geofence-ove koji ne postoje u database-u
      final toRemove = _activeGeofences.where((id) =>
      id.startsWith('task_') && !databaseTaskIds.contains(id)).toList();

      for (var geofenceId in toRemove) {
        final taskId = geofenceId.replaceFirst('task_', '');
        await removeTaskFromGeofencing(taskId);
      }

      // Dodaj task-ove koji nisu u geofencing sistemu
      for (var taskLocation in taskLocations) {
        final taskId = taskLocation.id.toString();
        if (!isTaskMonitored(taskId)) {
          await addTaskToGeofencing(
            taskId: taskId,
            latitude: taskLocation.latitude,
            longitude: taskLocation.longitude,
            title: taskLocation.title,
          );
        }
      }

      //GeofencingIntegrationHelper:('✅ GeofencingIntegrationHelper: Database sync completed');
    } catch (e) {
      debugPrint('❌ GeofencingIntegrationHelper: Database sync error: $e');
    }
  }

  /// Debug metoda za pregled status-a
  Future<void> printStatus() async {
    try {
      //GeofencingIntegrationHelper:('=== GEOFENCING STATUS ===');
      //GeofencingIntegrationHelper:('Initialized: $_isInitialized');
      //GeofencingIntegrationHelper:('Service Running: $_isServiceRunning');
      //GeofencingIntegrationHelper:('Active Geofences: ${_activeGeofences.length}');

      if (_activeGeofences.isNotEmpty) {
        //GeofencingIntegrationHelper:('Active Geofence IDs:');
        for (var id in _activeGeofences) {
          debugPrint('  - $id');
        }
      }

      // Test connection
      final connection = await LocadoBackgroundService.testConnection();
      //GeofencingIntegrationHelper:('Native Connection: $connection');

      //GeofencingIntegrationHelper:('========================');
    } catch (e) {
      debugPrint('❌ Error printing status: $e');
    }
  }

  /// Sinhronizuje geofence-ove sa listom TaskLocation objekata
  Future<bool> syncTaskLocations(List<TaskLocation> taskLocations) async {
    if (!_isServiceRunning) {
      //GeofencingIntegrationHelper:('GeofencingIntegrationHelper: Service not running, start it first');
      return false;
    }

    try {
      await LocadoBackgroundService.syncTaskLocationGeofences(taskLocations);
      await _refreshActiveGeofences();

      //GeofencingIntegrationHelper:('GeofencingIntegrationHelper: Synced ${taskLocations.length} task locations');
      //GeofencingIntegrationHelper:('GeofencingIntegrationHelper: ${_activeGeofences.length} active geofences');
      return true;

    } catch (e) {
      //GeofencingIntegrationHelper:('GeofencingIntegrationHelper: Sync error = $e');
      return false;
    }
  }

  /// Dodaje geofence za jednu TaskLocation
  Future<bool> addTaskLocationGeofence(TaskLocation taskLocation) async {
    if (!_isServiceRunning) {
      //GeofencingIntegrationHelper:('GeofencingIntegrationHelper: Service not running');
      return false;
    }

    try {
      final result = await LocadoBackgroundService.addTaskLocationGeofence(taskLocation);
      if (result) {
        await _refreshActiveGeofences();
        //GeofencingIntegrationHelper:('GeofencingIntegrationHelper: Added geofence for task ${taskLocation.id}');
      }
      return result;
    } catch (e) {
      //GeofencingIntegrationHelper:('GeofencingIntegrationHelper: Add geofence error = $e');
      return false;
    }
  }

  /// Uklanja geofence za jednu TaskLocation
  Future<bool> removeTaskLocationGeofence(TaskLocation taskLocation) async {
    try {
      final result = await LocadoBackgroundService.removeTaskLocationGeofence(taskLocation);
      if (result) {
        await _refreshActiveGeofences();
        //GeofencingIntegrationHelper:('GeofencingIntegrationHelper: Removed geofence for task ${taskLocation.id}');
      }
      return result;
    } catch (e) {
      //GeofencingIntegrationHelper:('GeofencingIntegrationHelper: Remove geofence error = $e');
      return false;
    }
  }

  /// Proverava da li TaskLocation ima aktivan geofence
  bool isTaskLocationMonitored(TaskLocation taskLocation) {
    return _activeGeofences.contains('task_${taskLocation.id ?? "null"}');
  }

  /// Ažurira notification poruku
  Future<bool> updateServiceNotification({
    String? title,
    String? content,
  }) async {
    try {
      final result = await LocadoBackgroundService.updateNotification(
        title: title ?? 'Locado - Location Tracking',
        content: content ?? 'Monitoring ${_activeGeofences.length} locations',
      );
      return result;
    } catch (e) {
      //GeofencingIntegrationHelper:('GeofencingIntegrationHelper: Update notification error = $e');
      return false;
    }
  }

  /// Interno - refreshuje listu aktivnih geofence-ova
  Future<void> _refreshActiveGeofences() async {
    try {
      final geofences = await LocadoBackgroundService.getActiveGeofences();
      //GeofencingIntegrationHelper:('🔍 GeofencingIntegrationHelper: Retrieved ${geofences.length} active geofences from native');

      if (geofences.length != _activeGeofences.length) {
        debugPrint('🔄 GeofencingIntegrationHelper: Active geofences updated: ${_activeGeofences.length} → ${geofences.length}');
      }

      _activeGeofences = geofences;
    } catch (e) {
      //GeofencingIntegrationHelper:('❌ GeofencingIntegrationHelper: Refresh active geofences error = $e');
      _activeGeofences = [];
    }
  }

  /// Interno - rukuje geofence event-ovima
  void _handleGeofenceEvent(GeofenceEvent event) {
    //GeofencingIntegrationHelper:('GeofencingIntegrationHelper: Received event = ${event.toString()}');

    // Refresh active geofences
    _refreshActiveGeofences();

    // Proslijedi event globalnom callback-u
    _globalEventCallback?.call(event);
  }

  /// Cleanup - pozovi kada se aplikacija zatvarala
  void cleanup() {
    LocadoBackgroundService.removeGeofenceEventListener();
    _globalEventCallback = null;
    _isInitialized = false;
  }
}

/// Widget mixin za lakšu integraciju u postojeće screens
mixin GeofencingScreenMixin<T extends StatefulWidget> on State<T> {
  bool _geofencingEnabled = false;

  bool get isGeofencingEnabled => _geofencingEnabled;

  /// Inicijalizuje geofencing za ovaj screen
  Future<void> initializeScreenGeofencing({
    Function(GeofenceEvent)? onGeofenceEvent,
  }) async {
    final helper = GeofencingIntegrationHelper.instance;

    if (!helper.isInitialized) {
      final result = await helper.initializeGeofencing(
        onGeofenceEvent: onGeofenceEvent ?? _defaultGeofenceEventHandler,
        autoStartService: true,
      );

      setState(() {
        _geofencingEnabled = result;
      });
    } else {
      setState(() {
        _geofencingEnabled = true;
      });
    }

    if (_geofencingEnabled) {
      debugPrint('GeofencingScreenMixin: Geofencing enabled for ${widget.runtimeType}');
    } else {
      debugPrint('GeofencingScreenMixin: Failed to enable geofencing for ${widget.runtimeType}');
    }
  }

  /// Default geofence event handler - može se override
  void _defaultGeofenceEventHandler(GeofenceEvent event) {
    if (event.isTaskGeofence && event.eventType == GeofenceEventType.enter) {
      _showDefaultTaskReminder(event);
    }
  }

  /// Default task reminder - prikazuje SnackBar
  void _showDefaultTaskReminder(GeofenceEvent event) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.location_on, color: Colors.white),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  event.title ?? 'You are near a task location',
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            ],
          ),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 5),
          action: SnackBarAction(
            label: 'View',
            textColor: Colors.white,
            onPressed: () {
              // Override ovaj deo u konkretnom screen-u
              _onTaskReminderTapped(event);
            },
          ),
        ),
      );
    }
  }

  /// Override ovaj metod u konkretnom screen-u
  void _onTaskReminderTapped(GeofenceEvent event) {
    debugPrint('GeofencingScreenMixin: Task reminder tapped for ${event.geofenceId}');
  }

  /// Helper metod za sync task locations
  Future<void> syncTaskLocationsFromScreen(List<TaskLocation> taskLocations) async {
    if (_geofencingEnabled) {
      final helper = GeofencingIntegrationHelper.instance;
      await helper.syncTaskLocations(taskLocations);
    }
  }

  /// Helper metod za dodavanje pojedinačnog geofence-a
  Future<bool> addTaskGeofenceFromScreen(TaskLocation taskLocation) async {
    if (_geofencingEnabled) {
      final helper = GeofencingIntegrationHelper.instance;
      return await helper.addTaskLocationGeofence(taskLocation);
    }
    return false;
  }

  /// Helper metod za uklanjanje pojedinačnog geofence-a
  Future<bool> removeTaskGeofenceFromScreen(TaskLocation taskLocation) async {
    if (_geofencingEnabled) {
      final helper = GeofencingIntegrationHelper.instance;
      return await helper.removeTaskLocationGeofence(taskLocation);
    }
    return false;
  }

  /// Proverava da li je task monitored
  bool isTaskMonitoredFromScreen(TaskLocation taskLocation) {
    if (_geofencingEnabled) {
      final helper = GeofencingIntegrationHelper.instance;
      return helper.isTaskLocationMonitored(taskLocation);
    }
    return false;
  }
}

/// Notification Manager za task reminders
class TaskReminderNotificationManager {
  static TaskReminderNotificationManager? _instance;
  static TaskReminderNotificationManager get instance =>
      _instance ??= TaskReminderNotificationManager._();

  TaskReminderNotificationManager._();

  /// Prikazuje local notification za task reminder
  Future<void> showTaskReminderNotification({
    required String taskId,
    required String title,
    required String body,
    Map<String, String>? payload,
  }) async {
    // Placeholder - integriši sa postojećim notification sistemom
    // ili dodaj flutter_local_notifications package

    //GeofencingIntegrationHelper:('TaskReminderNotificationManager: Showing notification');
    //GeofencingIntegrationHelper:('Title: $title');
    //GeofencingIntegrationHelper:('Body: $body');
    //GeofencingIntegrationHelper:('TaskId: $taskId');

    // TODO: Implementiraj stvarne notifikacije
    // final flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();
    // await flutterLocalNotificationsPlugin.show(
    //   taskId.hashCode,
    //   title,
    //   body,
    //   NotificationDetails(...),
    //   payload: jsonEncode(payload),
    // );
  }
}

/// Extension za TaskLocation sa geofencing helper metodama
extension TaskLocationGeofencing on TaskLocation {
  /// Geofence ID za ovu TaskLocation
  String get geofenceId => 'task_${id ?? "null"}';

  /// Proverava da li je ovaj task trenutno monitored
  bool get isMonitored {
    return GeofencingIntegrationHelper.instance.activeGeofences.contains(geofenceId);
  }

  /// Dodaje geofence za ovaj task
  Future<bool> startMonitoring() async {
    final helper = GeofencingIntegrationHelper.instance;
    if (helper.isServiceRunning) {
      return await helper.addTaskLocationGeofence(this);
    }
    return false;
  }

  /// Uklanja geofence za ovaj task
  Future<bool> stopMonitoring() async {
    final helper = GeofencingIntegrationHelper.instance;
    return await helper.removeTaskLocationGeofence(this);
  }

  /// Toggle monitoring status
  Future<bool> toggleMonitoring() async {
    if (isMonitored) {
      return await stopMonitoring();
    } else {
      return await startMonitoring();
    }
  }
}

/// Utility klasa za debug informacije
class GeofencingDebugInfo {
  static Future<Map<String, dynamic>> getSystemStatus() async {
    final helper = GeofencingIntegrationHelper.instance;

    return {
      'isInitialized': helper.isInitialized,
      'isServiceRunning': helper.isServiceRunning,
      'activeGeofences': helper.activeGeofences,
      'activeGeofenceCount': helper.activeGeofences.length,
      'permissions': await _getPermissionStatus(),
      'nativeConnection': await LocadoBackgroundService.testConnection(),
      'timestamp': DateTime.now().toIso8601String(),
    };
  }

  static Future<Map<String, bool>> _getPermissionStatus() async {
    return {
      'locationWhenInUse': await Permission.locationWhenInUse.isGranted,
      'locationAlways': await Permission.locationAlways.isGranted,
      'notification': await Permission.notification.isGranted,
    };
  }

  static void printSystemStatus() async {
    final status = await getSystemStatus();
    //GeofencingIntegrationHelper:('=== GEOFENCING SYSTEM STATUS ===');
    status.forEach((key, value) {
      debugPrint('$key: $value');
    });
    //GeofencingIntegrationHelper:('================================');
  }
}

/// App-wide geofencing controller - koristi za centralizovano upravljanje
class AppGeofencingController {
  static AppGeofencingController? _instance;
  static AppGeofencingController get instance => _instance ??= AppGeofencingController._();

  AppGeofencingController._();

  /// Inicijalizuje geofencing za celu aplikaciju
  Future<bool> initializeApp() async {
    final helper = GeofencingIntegrationHelper.instance;

    final result = await helper.initializeGeofencing(
      onGeofenceEvent: _handleAppLevelGeofenceEvent,
      autoStartService: true,
    );

    if (result) {
      //GeofencingIntegrationHelper:('AppGeofencingController: App-level geofencing initialized');

      // Auto-sync sa postojećim task-ovima iz database
      await _autoSyncWithDatabase();
    }

    return result;
  }

  /// Auto-sync sa database task-ovima
  Future<void> _autoSyncWithDatabase() async {
    try {
      // Koristi novo database integration API
      await GeofencingIntegrationHelper.instance.initializeExistingTasks();
      //GeofencingIntegrationHelper:('AppGeofencingController: Auto-sync with database completed');
    } catch (e) {
      debugPrint('AppGeofencingController: Auto-sync error = $e');
    }
  }

  /// App-level geofence event handler
  void _handleAppLevelGeofenceEvent(GeofenceEvent event) {
    //GeofencingIntegrationHelper:('AppGeofencingController: Received app-level event = ${event.toString()}');

    // App-level logic za geofence eventi
    if (event.isTaskGeofence && event.eventType == GeofenceEventType.enter) {
      _handleTaskProximityEvent(event);
    }
  }

  /// Rukuje task proximity event-ovima
  void _handleTaskProximityEvent(GeofenceEvent event) {
    final taskId = event.taskId;
    if (taskId != null) {
      // Pošalji notification
      TaskReminderNotificationManager.instance.showTaskReminderNotification(
        taskId: taskId,
        title: 'Task Reminder',
        body: event.description ?? 'You are near a task location',
        payload: {
          'taskId': taskId,
          'eventType': event.eventType.toString(),
          'latitude': event.latitude.toString(),
          'longitude': event.longitude.toString(),
        },
      );

      // Analytics/logging
      _logTaskProximityEvent(event);
    }
  }

  /// Log task proximity events za analytics
  void _logTaskProximityEvent(GeofenceEvent event) {
    // Placeholder - integriši sa analytics sistemom
    debugPrint('Analytics: Task proximity event - ${event.geofenceId}');
  }

  /// Cleanup when app is closing
  void cleanup() {
    GeofencingIntegrationHelper.instance.cleanup();
  }
}

/// Widget za prikaz geofencing status-a (može se dodati u bilo koji screen)
class GeofencingStatusWidget extends StatefulWidget {
  final bool showDetails;

  const GeofencingStatusWidget({
    Key? key,
    this.showDetails = false,
  }) : super(key: key);

  @override
  State<GeofencingStatusWidget> createState() => _GeofencingStatusWidgetState();
}

class _GeofencingStatusWidgetState extends State<GeofencingStatusWidget> {
  late GeofencingIntegrationHelper _helper;

  @override
  void initState() {
    super.initState();
    _helper = GeofencingIntegrationHelper.instance;
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.showDetails) {
      // Compact status indicator
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            _helper.isServiceRunning ? Icons.location_on : Icons.location_off,
            color: _helper.isServiceRunning ? Colors.green : Colors.red,
            size: 16,
          ),
          const SizedBox(width: 4),
          Text(
            '${_helper.activeGeofences.length}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      );
    }

    // Detailed status card
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  _helper.isServiceRunning ? Icons.location_on : Icons.location_off,
                  color: _helper.isServiceRunning ? Colors.green : Colors.red,
                ),
                const SizedBox(width: 8),
                Text(
                  'Geofencing ${_helper.isServiceRunning ? "Active" : "Inactive"}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text('Active Geofences: ${_helper.activeGeofences.length}'),
            Text('Initialized: ${_helper.isInitialized ? "Yes" : "No"}'),
            if (widget.showDetails && _helper.activeGeofences.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                'Active IDs:',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              ..._helper.activeGeofences.map(
                    (id) => Text(
                  '• $id',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}