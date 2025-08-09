import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart'; // ✅ DODANO
import '../models/task_location.dart';

/// Flutter Bridge za Native Android Geofencing Service
/// Povezuje Flutter kod sa LocadoForegroundService.kt
class LocadoBackgroundService {
  static const MethodChannel _methodChannel =
  MethodChannel('com.example.locado_final/geofence');

  static const EventChannel _eventChannel =
  EventChannel('com.example.locado_final/geofence_events');

  static StreamSubscription? _eventSubscription;
  static Function(GeofenceEvent)? _onGeofenceTriggered;

  // ✅ DODANO: Cache za radius da se ne čita stalno iz SharedPreferences
  static double? _cachedRadius;

  // ✅ DODANO: Čita radius iz SharedPreferences
  static Future<double> _getGeofenceRadius() async {
    if (_cachedRadius != null) return _cachedRadius!;

    try {
      final prefs = await SharedPreferences.getInstance();
      final radius = prefs.getInt('notification_distance') ?? 100;
      _cachedRadius = radius.toDouble();
      debugPrint('LocadoBackgroundService: Using geofence radius = ${_cachedRadius}m from settings');
      return _cachedRadius!;
    } catch (e) {
      debugPrint('LocadoBackgroundService: Error reading radius from settings, using 100m default: $e');
      _cachedRadius = 100.0;
      return _cachedRadius!;
    }
  }

  // ✅ DODANO: Resetuje cached radius kada se settings promijeni
  static void resetRadiusCache() {
    _cachedRadius = null;
    debugPrint('LocadoBackgroundService: Radius cache reset');
  }

  /// Test konekcije sa native kodom
  static Future<bool> testConnection() async {
    try {
      final result = await _methodChannel.invokeMethod('testConnection');
      debugPrint('LocadoBackgroundService: testConnection = $result');
      return result != null && result.toString().isNotEmpty;
    } catch (e) {
      debugPrint('LocadoBackgroundService: testConnection error = $e');
      return false;
    }
  }

  /// Pokreće foreground service
  static Future<bool> startService() async {
    try {
      final result = await _methodChannel.invokeMethod('startForegroundService');
      debugPrint('LocadoBackgroundService: startService = $result');
      return result == true;
    } catch (e) {
      debugPrint('LocadoBackgroundService: startService error = $e');
      return false;
    }
  }

  /// Zaustavlja foreground service
  static Future<bool> stopService() async {
    try {
      final result = await _methodChannel.invokeMethod('stopForegroundService');
      debugPrint('LocadoBackgroundService: stopService = $result');
      return result == true;
    } catch (e) {
      debugPrint('LocadoBackgroundService: stopService error = $e');
      return false;
    }
  }

  /// Proverava da li je service aktivan
  static Future<bool> isServiceRunning() async {
    try {
      final result = await _methodChannel.invokeMethod('isServiceRunning');
      return result == true;
    } catch (e) {
      debugPrint('LocadoBackgroundService: isServiceRunning error = $e');
      return false;
    }
  }

  /// Dodaje geofence za određenu lokaciju
  /// [id] - jedinstveni identifier
  /// [latitude] - geografska širina
  /// [longitude] - geografska dužina
  /// [radius] - radius u metrima (default: 100m)
  static Future<bool> addGeofence({
    required String id,
    required double latitude,
    required double longitude,
    double radius = 100.0,
    String? title,
    String? description,
  }) async {
    try {
      final Map<String, dynamic> params = {
        'id': id,
        'latitude': latitude,
        'longitude': longitude,
        'radius': radius,
        'title': title ?? 'Task Location',
        'description': description ?? 'You are near your task location',
      };

      final result = await _methodChannel.invokeMethod('addGeofence', params);
      debugPrint('LocadoBackgroundService: addGeofence($id) = $result');
      return result == true;
    } catch (e) {
      debugPrint('LocadoBackgroundService: addGeofence error = $e');
      return false;
    }
  }

  /// Uklanja geofence po ID-u
  static Future<bool> removeGeofence(String id) async {
    try {
      final result = await _methodChannel.invokeMethod('removeGeofence', {'id': id});
      debugPrint('LocadoBackgroundService: removeGeofence($id) = $result');
      return result == true;
    } catch (e) {
      debugPrint('LocadoBackgroundService: removeGeofence error = $e');
      return false;
    }
  }
  
 /// 🚀 NEW: Batch add geofences - OPTIMIZED for multiple locations
  static Future<bool> addGeofencesBatch(List<Map<String, dynamic>> geofences) async {
    try {
      debugPrint('LocadoBackgroundService: Adding ${geofences.length} geofences via BATCH processing');
      
      final result = await _methodChannel.invokeMethod('addGeofencesBatch', {
        'geofences': geofences,
      });
      
      debugPrint('LocadoBackgroundService: Batch result = $result');
      return result != null && result.toString().contains('geofences added');
    } catch (e) {
      debugPrint('LocadoBackgroundService: addGeofencesBatch error = $e');
      return false;
    }
  }

  /// 🚀 NEW: Batch remove geofences - OPTIMIZED for multiple removals
  static Future<bool> removeGeofencesBatch(List<String> geofenceIds) async {
    try {
      debugPrint('LocadoBackgroundService: Removing ${geofenceIds.length} geofences via BATCH processing');
      
      final result = await _methodChannel.invokeMethod('removeGeofencesBatch', {
        'ids': geofenceIds,
      });
      
      debugPrint('LocadoBackgroundService: Batch removal result = $result');
      return result != null && result.toString().contains('geofences removed');
    } catch (e) {
      debugPrint('LocadoBackgroundService: removeGeofencesBatch error = $e');
      return false;
    }
  }

  /// 🚀 OPTIMIZED: Fast sync with batch processing instead of individual calls
  static Future<void> syncTaskLocationGeofences(List<TaskLocation> taskLocations) async {
    print("🚀 BATCH: syncTaskLocationGeofences() started - using NEW batch implementation!");
    print("🚀 BATCH: About to call addGeofencesBatch()");
    try {
      debugPrint('LocadoBackgroundService: 🚀 Starting OPTIMIZED sync for ${taskLocations.length} locations');
      final startTime = DateTime.now();
      
      // Read radius from settings
      final radius = await _getGeofenceRadius();

      // Get current active geofences
      final activeGeofences = await getActiveGeofences();

      // Create set of task geofence IDs that should exist
      final requiredGeofenceIds = taskLocations
          .map((task) => 'task_${task.id}')
          .toSet();

      // 🗑️ BATCH REMOVAL: Find obsolete geofences
      final obsoleteGeofences = activeGeofences
          .where((activeId) => activeId.startsWith('task_') && !requiredGeofenceIds.contains(activeId))
          .toList();

      if (obsoleteGeofences.isNotEmpty) {
        debugPrint('LocadoBackgroundService: 🗑️ Batch removing ${obsoleteGeofences.length} obsolete geofences');
        await removeGeofencesBatch(obsoleteGeofences);
      }
	  
		// 🚀 BATCH ADD: Create list of new geofences
		final newGeofences = <Map<String, dynamic>>[];

		for (final taskLocation in taskLocations) {
		  final geofenceId = 'task_${taskLocation.id}';
		  if (!activeGeofences.contains(geofenceId)) {
			newGeofences.add({
			  'id': geofenceId,
			  'latitude': taskLocation.latitude,
			  'longitude': taskLocation.longitude,
			  'radius': radius,
			  'title': taskLocation.title,
			  'description': 'You are near: ${taskLocation.title}',
			});
		  }
		}

      // 🚀 BATCH ADD: Add all new geofences in one optimized call
      if (newGeofences.isNotEmpty) {
        debugPrint('LocadoBackgroundService: 🚀 Batch adding ${newGeofences.length} new geofences with ${radius}m radius');
        await addGeofencesBatch(newGeofences);
      }

      // Calculate performance improvement
      final endTime = DateTime.now();
      final duration = endTime.difference(startTime).inMilliseconds;
      
      debugPrint('LocadoBackgroundService: ✅ OPTIMIZED sync completed in ${duration}ms');
      debugPrint('LocadoBackgroundService: 📊 Performance: Processed ${taskLocations.length} locations in ${duration}ms (${(duration / taskLocations.length).toStringAsFixed(1)}ms per location)');

      // Update notification with count
      await updateNotification(
        title: 'Locado - Location Tracking (Optimized)',
        content: 'Monitoring ${taskLocations.length} task locations (${radius.toInt()}m radius) - Synced in ${duration}ms',
      );

    } catch (e) {
      debugPrint('LocadoBackgroundService: ❌ Optimized sync error = $e');
      // Fallback to old method if batch fails
      debugPrint('LocadoBackgroundService: 🔄 Falling back to individual sync method');
      await syncTaskLocationGeofencesOLD(taskLocations);
    }
  }

  /// Vraća listu aktivnih geofence ID-jeva
  static Future<List<String>> getActiveGeofences() async {
    try {
      final result = await _methodChannel.invokeMethod('getActiveGeofences');
      if (result != null && result is List) {
        return result.cast<String>();
      }
      return [];
    } catch (e) {
      debugPrint('LocadoBackgroundService: getActiveGeofences error = $e');
      return [];
    }
  }

  /// Ažurira notification tekst
  static Future<bool> updateNotification({
    required String title,
    required String content,
  }) async {
    try {
      final result = await _methodChannel.invokeMethod('updateNotification', {
        'title': title,
        'content': content,
      });
      return result == true;
    } catch (e) {
      debugPrint('LocadoBackgroundService: updateNotification error = $e');
      return false;
    }
  }

  /// Postavlja listener za geofence eventi
  static void setGeofenceEventListener(Function(GeofenceEvent) callback) {
    _onGeofenceTriggered = callback;
    _startListeningToEvents();
  }

  /// Uklanja listener za geofence eventi
  static void removeGeofenceEventListener() {
    _onGeofenceTriggered = null;
    _eventSubscription?.cancel();
    _eventSubscription = null;
  }

  /// Interno - počinje slušanje event channel-a
  static void _startListeningToEvents() {
    _eventSubscription?.cancel();

    _eventSubscription = _eventChannel.receiveBroadcastStream().listen(
          (dynamic event) {
        try {
          if (event != null && _onGeofenceTriggered != null) {
            final geofenceEvent = GeofenceEvent.fromMap(event);
            debugPrint('LocadoBackgroundService: Received event = ${geofenceEvent.toString()}');
            _onGeofenceTriggered!(geofenceEvent);
          }
        } catch (e) {
          debugPrint('LocadoBackgroundService: Event parsing error = $e');
        }
      },
      onError: (error) {
        debugPrint('LocadoBackgroundService: Event stream error = $error');
      },
    );
  }

	static Future<bool> addTaskLocationGeofence(TaskLocation taskLocation) async {
	
	  // 🚀 REDIRECT to optimized batch method for single task
	  debugPrint('LocadoBackgroundService: 🚀 Redirecting single task to batch method');
	  await syncTaskLocationGeofences([taskLocation]);
	  return true;
	}

  /// Uklanja geofence za TaskLocation objekat
  static Future<bool> removeTaskLocationGeofence(TaskLocation taskLocation) async {
    return await removeGeofence('task_${taskLocation.id ?? "null"}');
  }

  /// Ažurira sve geofence-ove na osnovu liste TaskLocation objekata
  static Future<void> syncTaskLocationGeofencesOLD(List<TaskLocation> taskLocations) async {
    print("⚠️ OLD: syncTaskLocationGeofencesOLD() called - THIS SHOULD NOT HAPPEN!");
    try {
      // ✅ ČITA RADIUS IZ SETTINGS-A
      final radius = await _getGeofenceRadius();

      // Dobij trenutne aktivne geofence-ove
      final activeGeofences = await getActiveGeofences();

      // Kreiraj set task geofence ID-jeva koji treba da postoje
      final requiredGeofenceIds = taskLocations
          .map((task) => 'task_${task.id}')
          .toSet();

      // Ukloni geofence-ove koji više nisu potrebni
      for (final activeId in activeGeofences) {
        if (activeId.startsWith('task_') && !requiredGeofenceIds.contains(activeId)) {
          await removeGeofence(activeId);
          debugPrint('LocadoBackgroundService: Removed obsolete geofence $activeId');
        }
      }

      // Dodaj nove geofence-ove SA RADIUS-OM IZ SETTINGS-A
      for (final taskLocation in taskLocations) {
        final geofenceId = 'task_${taskLocation.id}';
        if (!activeGeofences.contains(geofenceId)) {
          // ✅ KORISTIMO RADIUS IZ SETTINGS-A
          await addGeofence(
            id: geofenceId,
            latitude: taskLocation.latitude,
            longitude: taskLocation.longitude,
            radius: radius, // ✅ ISPRAVKA OVDJE
            title: taskLocation.title,
            description: 'You are near: ${taskLocation.title}',
          );
          debugPrint('LocadoBackgroundService: Added new geofence $geofenceId with radius ${radius}m');
        }
      }

      // Ažuriraj notification sa brojem aktivnih task-ova
      await updateNotification(
        title: 'Locado - Location Tracking',
        content: 'Monitoring ${taskLocations.length} task locations (${radius.toInt()}m radius)',
      );

    } catch (e) {
      debugPrint('LocadoBackgroundService: syncTaskLocationGeofences error = $e');
    }
  }

  // ✅ DODANO: Ažurira radijuse postojećih geofence-ova kada se settings promijeni
  static Future<bool> updateAllGeofenceRadiuses() async {
    try {
      // Reset cache da čita novu vrijednost
      resetRadiusCache();

      // Dobij sve aktivne task geofence-ove
      final activeGeofences = await getActiveGeofences();
      final taskGeofences = activeGeofences.where((id) => id.startsWith('task_')).toList();

      if (taskGeofences.isEmpty) {
        debugPrint('LocadoBackgroundService: No task geofences to update');
        return true;
      }

      final newRadius = await _getGeofenceRadius();
      debugPrint('LocadoBackgroundService: Updating ${taskGeofences.length} geofences to ${newRadius}m radius');

      // Za svaki task geofence, treba da ga re-kreiramo sa novim radius-om
      // (Android Geofencing API ne dozvoljava ažuriranje postojećih geofence-ova)

      // Ovdje bi trebalo učitati TaskLocation objekte iz baze i pozvati syncTaskLocationGeofences
      // Ali pošto nemamo direktan pristup bazi iz ovog service-a,
      // samo ćemo resetovati cache i označiti da su promjene potrebne

      debugPrint('LocadoBackgroundService: Geofence radius cache updated to ${newRadius}m. Next sync will use new radius.');
      return true;

    } catch (e) {
      debugPrint('LocadoBackgroundService: Error updating geofence radiuses: $e');
      return false;
    }
  }

  /// Prikazuje full screen notification za geofence alert
  static Future<bool> showFullScreenNotification({
    required String taskTitle,
    required String taskMessage,
    required String taskId,
  }) async {
    try {
      final result = await _methodChannel.invokeMethod('showFullScreenNotification', {
        'taskTitle': taskTitle,
        'taskMessage': taskMessage,
        'taskId': taskId,
      });
      debugPrint('LocadoBackgroundService: showFullScreenNotification = $result');
      return result == true;
    } catch (e) {
      debugPrint('LocadoBackgroundService: showFullScreenNotification error = $e');
      return false;
    }
  }
}

/// Model klasa za geofence event
class GeofenceEvent {
  final String geofenceId;
  final GeofenceEventType eventType;
  final double latitude;
  final double longitude;
  final DateTime timestamp;
  final String? title;
  final String? description;

  GeofenceEvent({
    required this.geofenceId,
    required this.eventType,
    required this.latitude,
    required this.longitude,
    required this.timestamp,
    this.title,
    this.description,
  });

  factory GeofenceEvent.fromMap(dynamic map) {
    return GeofenceEvent(
      geofenceId: map['geofenceId'] ?? '',
      eventType: GeofenceEventType.fromString(map['eventType'] ?? 'ENTER'),
      latitude: (map['latitude'] ?? 0.0).toDouble(),
      longitude: (map['longitude'] ?? 0.0).toDouble(),
      timestamp: DateTime.fromMillisecondsSinceEpoch(map['timestamp'] ?? 0),
      title: map['title'],
      description: map['description'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'geofenceId': geofenceId,
      'eventType': eventType.toString(),
      'latitude': latitude,
      'longitude': longitude,
      'timestamp': timestamp.millisecondsSinceEpoch,
      'title': title,
      'description': description,
    };
  }

  @override
  String toString() {
    return 'GeofenceEvent(id: $geofenceId, type: $eventType, lat: $latitude, lng: $longitude)';
  }

  /// Da li je ovo task geofence event
  bool get isTaskGeofence => geofenceId.startsWith('task_');

  /// Vraća task ID ako je task geofence
  String? get taskId {
    if (isTaskGeofence) {
      return geofenceId.replaceFirst('task_', '');
    }
    return null;
  }
}

/// Tip geofence event-a
enum GeofenceEventType {
  enter,
  exit,
  dwell;

  static GeofenceEventType fromString(String value) {
    switch (value.toUpperCase()) {
      case 'ENTER':
        return GeofenceEventType.enter;
      case 'EXIT':
        return GeofenceEventType.exit;
      case 'DWELL':
        return GeofenceEventType.dwell;
      default:
        return GeofenceEventType.enter;
    }
  }

  @override
  String toString() {
    switch (this) {
      case GeofenceEventType.enter:
        return 'ENTER';
      case GeofenceEventType.exit:
        return 'EXIT';
      case GeofenceEventType.dwell:
        return 'DWELL';
    }
  }
}