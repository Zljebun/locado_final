import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import '../lib/services/locado_background_service.dart';
import '../lib/services/geofencing_integration_helper.dart';
import '../lib/models/task_location.dart';

/// Comprehensive Test Suite za LocadoBackgroundService
/// Testira sve funkcionalnosti Flutter Bridge Layer-a
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('LocadoBackgroundService Tests', () {
    late MethodChannel methodChannel;
    late EventChannel eventChannel;

    // Mock responses za Method Channel
    final Map<String, dynamic> mockResponses = {};

    setUp(() {
      methodChannel = const MethodChannel('com.example.locado_final/geofence');
      eventChannel = const EventChannel('com.example.locado_final/geofence_events');

      // Setup mock responses
      mockResponses.clear();
      mockResponses['testConnection'] = true;
      mockResponses['startForegroundService'] = true;
      mockResponses['stopForegroundService'] = true;
      mockResponses['isServiceRunning'] = false; // Initially not running
      mockResponses['addGeofence'] = true;
      mockResponses['removeGeofence'] = true;
      mockResponses['getActiveGeofences'] = <String>[];
      mockResponses['updateNotification'] = true;

      // Mock Method Channel handler
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(methodChannel, (MethodCall methodCall) async {

        final String method = methodCall.method;
        final dynamic arguments = methodCall.arguments;

        print('MockMethodChannel: $method called with $arguments');

        // Special handling za određene metode
        switch (method) {
          case 'addGeofence':
          // Simuliraj dodavanje geofence-a u listu
            final String id = arguments['id'];
            final List<String> activeGeofences =
            List<String>.from(mockResponses['getActiveGeofences']);
            if (!activeGeofences.contains(id)) {
              activeGeofences.add(id);
              mockResponses['getActiveGeofences'] = activeGeofences;
            }
            return mockResponses[method];

          case 'removeGeofence':
          // Simuliraj uklanjanje geofence-a iz liste
            final String id = arguments['id'];
            final List<String> activeGeofences =
            List<String>.from(mockResponses['getActiveGeofences']);
            activeGeofences.remove(id);
            mockResponses['getActiveGeofences'] = activeGeofences;
            return mockResponses[method];

          case 'startForegroundService':
            mockResponses['isServiceRunning'] = true;
            return mockResponses[method];

          case 'stopForegroundService':
            mockResponses['isServiceRunning'] = false;
            return mockResponses[method];

          default:
            return mockResponses[method];
        }
      });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(methodChannel, null);
    });

    test('testConnection() - should return true when connection is successful', () async {
      final result = await LocadoBackgroundService.testConnection();
      expect(result, isTrue);
    });

    test('startService() - should start foreground service successfully', () async {
      final result = await LocadoBackgroundService.startService();
      expect(result, isTrue);

      // Verify service is running
      final isRunning = await LocadoBackgroundService.isServiceRunning();
      expect(isRunning, isTrue);
    });

    test('stopService() - should stop foreground service successfully', () async {
      // First start the service
      await LocadoBackgroundService.startService();

      // Then stop it
      final result = await LocadoBackgroundService.stopService();
      expect(result, isTrue);

      // Verify service is stopped
      final isRunning = await LocadoBackgroundService.isServiceRunning();
      expect(isRunning, isFalse);
    });

    test('addGeofence() - should add geofence successfully', () async {
      final result = await LocadoBackgroundService.addGeofence(
        id: 'test_geofence_1',
        latitude: 44.7729,
        longitude: 17.1910,
        radius: 100.0,
        title: 'Test Location',
        description: 'Test geofence description',
      );

      expect(result, isTrue);

      // Verify geofence was added
      final activeGeofences = await LocadoBackgroundService.getActiveGeofences();
      expect(activeGeofences, contains('test_geofence_1'));
    });

    test('removeGeofence() - should remove geofence successfully', () async {
      // First add a geofence
      await LocadoBackgroundService.addGeofence(
        id: 'test_geofence_2',
        latitude: 44.7729,
        longitude: 17.1910,
      );

      // Then remove it
      final result = await LocadoBackgroundService.removeGeofence('test_geofence_2');
      expect(result, isTrue);

      // Verify geofence was removed
      final activeGeofences = await LocadoBackgroundService.getActiveGeofences();
      expect(activeGeofences, isNot(contains('test_geofence_2')));
    });

    test('getActiveGeofences() - should return list of active geofences', () async {
      // Add multiple geofences
      await LocadoBackgroundService.addGeofence(
        id: 'test_geofence_3',
        latitude: 44.7729,
        longitude: 17.1910,
      );
      await LocadoBackgroundService.addGeofence(
        id: 'test_geofence_4',
        latitude: 44.7800,
        longitude: 17.2000,
      );

      final activeGeofences = await LocadoBackgroundService.getActiveGeofences();
      expect(activeGeofences, hasLength(greaterThanOrEqualTo(2)));
      expect(activeGeofences, contains('test_geofence_3'));
      expect(activeGeofences, contains('test_geofence_4'));
    });

    test('updateNotification() - should update notification successfully', () async {
      final result = await LocadoBackgroundService.updateNotification(
        title: 'Test Notification',
        content: 'Test notification content',
      );
      expect(result, isTrue);
    });

    test('addTaskLocationGeofence() - should add geofence for TaskLocation', () async {
      final taskLocation = TaskLocation(
        id: 123,  // ili int ako želiš: 123
        title: 'Test Task',
        latitude: 44.7729,
        longitude: 17.1910,
        radius: 150.0,
        taskItems: ['Test item 1', 'Test item 2'],
        colorHex: '#FF0000',
      );

      final result = await LocadoBackgroundService.addTaskLocationGeofence(taskLocation);
      expect(result, isTrue);

      // Verify task geofence was added with correct ID
      final activeGeofences = await LocadoBackgroundService.getActiveGeofences();
      expect(activeGeofences, contains('task_123'));
    });

    test('removeTaskLocationGeofence() - should remove geofence for TaskLocation', () async {
      final taskLocation = TaskLocation(
        id: 456,  // ili int ako želiš: 123
        title: 'Test Task',
        latitude: 44.7729,
        longitude: 17.1910,
        radius: 150.0,
        taskItems: ['Test item 1', 'Test item 2'],
        colorHex: '#FF0000',
      );

      // First add the task geofence
      await LocadoBackgroundService.addTaskLocationGeofence(taskLocation);

      // Then remove it
      final result = await LocadoBackgroundService.removeTaskLocationGeofence(taskLocation);
      expect(result, isTrue);

      // Verify task geofence was removed
      final activeGeofences = await LocadoBackgroundService.getActiveGeofences();
      expect(activeGeofences, isNot(contains('task_456')));
    });

    test('syncTaskLocationGeofences() - should sync geofences with task list', () async {
      // Create test task locations
      final taskLocations = [
        TaskLocation(
          id: 1,  // ili int ako želiš: 123
          title: 'Test Task',
          latitude: 44.7729,
          longitude: 17.1910,
          radius: 150.0,
          taskItems: ['Test item 1', 'Test item 2'],
          colorHex: '#FF0000',
        ),
        TaskLocation(
          id: 2,  // ili int ako želiš: 123
          title: 'Test Task',
          latitude: 44.7729,
          longitude: 17.1910,
          radius: 150.0,
          taskItems: ['Test item 1', 'Test item 2'],
          colorHex: '#FF0000',
        ),
      ];

      // Sync geofences
      await LocadoBackgroundService.syncTaskLocationGeofences(taskLocations);

      // Verify correct geofences exist
      final activeGeofences = await LocadoBackgroundService.getActiveGeofences();
      expect(activeGeofences, contains('task_1'));
      expect(activeGeofences, contains('task_2'));
    });

    test('GeofenceEvent.fromMap() - should parse event data correctly', () {
      final eventData = {
        'geofenceId': 'task_789',
        'eventType': 'ENTER',
        'latitude': 44.7729,
        'longitude': 17.1910,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'title': 'Test Event',
        'description': 'Test event description',
      };

      final geofenceEvent = GeofenceEvent.fromMap(eventData);

      expect(geofenceEvent.geofenceId, equals('task_789'));
      expect(geofenceEvent.eventType, equals(GeofenceEventType.enter));
      expect(geofenceEvent.latitude, equals(44.7729));
      expect(geofenceEvent.longitude, equals(17.1910));
      expect(geofenceEvent.title, equals('Test Event'));
      expect(geofenceEvent.description, equals('Test event description'));
      expect(geofenceEvent.isTaskGeofence, isTrue);
      expect(geofenceEvent.taskId, equals('789'));
    });

    test('GeofenceEventType.fromString() - should parse event types correctly', () {
      expect(GeofenceEventType.fromString('ENTER'), equals(GeofenceEventType.enter));
      expect(GeofenceEventType.fromString('EXIT'), equals(GeofenceEventType.exit));
      expect(GeofenceEventType.fromString('DWELL'), equals(GeofenceEventType.dwell));
      expect(GeofenceEventType.fromString('UNKNOWN'), equals(GeofenceEventType.enter)); // default
    });

    test('Error handling - should handle method channel errors gracefully', () async {
      // Mock error response
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(methodChannel, (MethodCall methodCall) async {
        throw PlatformException(code: 'TEST_ERROR', message: 'Test error message');
      });

      // Test that errors are handled gracefully
      final testConnectionResult = await LocadoBackgroundService.testConnection();
      expect(testConnectionResult, isFalse);

      final startServiceResult = await LocadoBackgroundService.startService();
      expect(startServiceResult, isFalse);

      final addGeofenceResult = await LocadoBackgroundService.addGeofence(
        id: 'error_test',
        latitude: 44.7729,
        longitude: 17.1910,
      );
      expect(addGeofenceResult, isFalse);
    });
  });

  group('Integration Test Scenarios', () {
    test('Complete workflow - start service, add geofences, monitor, stop service', () async {
      // Step 1: Test connection
      final connectionResult = await LocadoBackgroundService.testConnection();
      expect(connectionResult, isTrue);

      // Step 2: Start service
      final startResult = await LocadoBackgroundService.startService();
      expect(startResult, isTrue);

      // Step 3: Add multiple geofences
      final addResult1 = await LocadoBackgroundService.addGeofence(
        id: 'workflow_test_1',
        latitude: 44.7729,
        longitude: 17.1910,
        title: 'Workflow Test 1',
      );
      expect(addResult1, isTrue);

      final addResult2 = await LocadoBackgroundService.addGeofence(
        id: 'workflow_test_2',
        latitude: 44.7800,
        longitude: 17.2000,
        title: 'Workflow Test 2',
      );
      expect(addResult2, isTrue);

      // Step 4: Verify active geofences
      final activeGeofences = await LocadoBackgroundService.getActiveGeofences();
      expect(activeGeofences, contains('workflow_test_1'));
      expect(activeGeofences, contains('workflow_test_2'));

      // Step 5: Update notification
      final updateResult = await LocadoBackgroundService.updateNotification(
        title: 'Locado - Workflow Test',
        content: 'Monitoring ${activeGeofences.length} locations',
      );
      expect(updateResult, isTrue);

      // Step 6: Remove one geofence
      final removeResult = await LocadoBackgroundService.removeGeofence('workflow_test_1');
      expect(removeResult, isTrue);

      // Step 7: Verify geofence was removed
      final updatedGeofences = await LocadoBackgroundService.getActiveGeofences();
      expect(updatedGeofences, isNot(contains('workflow_test_1')));
      expect(updatedGeofences, contains('workflow_test_2'));

      // Step 8: Stop service
      final stopResult = await LocadoBackgroundService.stopService();
      expect(stopResult, isTrue);

      // Step 9: Verify service is stopped
      final isRunning = await LocadoBackgroundService.isServiceRunning();
      expect(isRunning, isFalse);
    });
  });
}

/// Test helper funkcije
class TestHelpers {
  /// Kreira test TaskLocation objekat
  static TaskLocation createTestTaskLocation({
    String? id,
    String? title,
    double? latitude,
    double? longitude,
    double? radius,
  }) {
    return TaskLocation(
      id: null,
      title: title ?? 'Test Task',
      latitude: latitude ?? 44.7729,
      longitude: longitude ?? 17.1910,
      radius: radius ?? 100.0,
      taskItems: ['Test item'],
      colorHex: '#FF0000',
    );
  }

  /// Kreira listu test TaskLocation objekata
  static List<TaskLocation> createTestTaskLocationList(int count) {
    return List.generate(count, (index) => createTestTaskLocation(
      id: 'test_task_$index',
      title: 'Test Task $index',
      latitude: 44.7729 + (index * 0.001),
      longitude: 17.1910 + (index * 0.001),
    ));
  }
}

/// Manual Test Instructions (za fizičko testiranje)
///
/// 1. Deploy aplikaciju na Samsung SM A405FN
/// 2. Pokreni: flutter test test/comprehensive_background_test.dart
/// 3. Za real-world testing:
///    - Kreiraj TaskLocation u Banja Luka (44.7729, 17.1910)
///    - Pokreni background service
///    - Idi na tu lokaciju i proveri da li se trigguje geofence
///    - Proveri notification updates
///
/// Expected Results:
/// ✅ Svi unit testovi prolaze
/// ✅ Method channel komunikacija radi
/// ✅ Service lifecycle management funkcioniše
/// ✅ Geofence CRUD operacije rade
/// ✅ Error handling je implementiran
/// ✅ Integration sa TaskLocation model-om radi