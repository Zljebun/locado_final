// lib/helpers/file_intent_handler.dart

import 'dart:io';
import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../models/task_location.dart';
import '../helpers/database_helper.dart';
import '../screens/main_navigation_screen.dart';
import '../screens/task_detail_screen.dart';
import '../main.dart';

class FileIntentHandler {
  static FileIntentHandler? _instance;
  static FileIntentHandler get instance => _instance ??= FileIntentHandler._internal();
  FileIntentHandler._internal();

  // Method channel for communicating with Android
  static const MethodChannel _channel = MethodChannel('com.example.locado_final/file_intent');

  /// Initialize file intent listening
  static void initialize() {
    print('🔗 FILE INTENT: Initializing file intent handler (Method Channel)...');

    try {
      // Set method call handler for Android to call Flutter
      _channel.setMethodCallHandler(_handleMethodCall);
      
      // Check if app was launched with a file
      _checkInitialFileIntent();
      
      print('✅ FILE INTENT: Handler initialized successfully');
    } catch (e) {
      print('❌ FILE INTENT: Failed to initialize: $e');
    }
  }

  /// Handle method calls from Android
  static Future<dynamic> _handleMethodCall(MethodCall call) async {
    print('🔗 FILE INTENT: Received method call: ${call.method}');
    
    switch (call.method) {
      case 'handleSharedFile':
        final String? filePath = call.arguments as String?;
        if (filePath != null) {
          await _handleSharedFilePath(filePath);
        }
        break;
      case 'handleFileIntent':
        final Map<dynamic, dynamic>? intentData = call.arguments as Map<dynamic, dynamic>?;
        if (intentData != null) {
          await _handleFileIntentData(intentData);
        }
        break;
      default:
        print('⚠️ FILE INTENT: Unknown method: ${call.method}');
    }
  }

  /// Check if app was launched with a file intent
  static Future<void> _checkInitialFileIntent() async {
    try {
      final result = await _channel.invokeMethod('getInitialFileIntent');
      if (result != null) {
        print('🔗 FILE INTENT: App launched with file intent: $result');
        await _handleFileIntentData(result);
      }
    } catch (e) {
      print('📁 FILE INTENT: No initial file intent: $e');
    }
  }

  /// Handle file path from sharing
  static Future<void> _handleSharedFilePath(String filePath) async {
    print('🔗 FILE INTENT: Processing shared file: $filePath');
    
    // ✅ ISPRAVKA: Provjeri sadržaj umjesto ekstenzije
    if (await _isValidLocadoFile(filePath)) {
      await _importLocadoFile(filePath);
    } else {
      print('⚠️ FILE INTENT: File failed validation: $filePath');
      NavigationService.showInfo('File type not supported. Please share a valid Locado task file.');
    }
  }

  // ✅ NOVA FUNKCIJA: Validacija sadržaja fajla
  static Future<bool> _isValidLocadoFile(String filePath) async {
    try {
      print('🔍 FILE VALIDATION: Checking file content: $filePath');
      
      final file = File(filePath);
      if (!await file.exists()) {
        print('❌ FILE VALIDATION: File does not exist');
        return false;
      }
      
      // Čitaj sadržaj fajla
      final content = await file.readAsString();
      print('📄 FILE VALIDATION: File size: ${content.length} characters');
      
      // Provjeri Locado markere
      final hasLocadoVersion = content.contains('"locado_version"');
      final hasExportType = content.contains('"task_share"');
      final hasTaskData = content.contains('"task_data"');
      final hasTaskItems = content.contains('"taskItems"');
      
      print('🔍 FLUTTER VALIDATION: Results:');
      print('  - locado_version: $hasLocadoVersion');
      print('  - task_share: $hasExportType');
      print('  - task_data: $hasTaskData');
      print('  - taskItems: $hasTaskItems');
      
      // Trebaju svi markeri za validaciju
      final isValid = hasLocadoVersion && hasExportType && hasTaskData && hasTaskItems;
      print('✅ FILE VALIDATION: Overall result: $isValid');
      
      return isValid;
    } catch (e) {
      print('❌ FILE VALIDATION: Error reading file: $e');
      return false;
    }
  }

  /// Handle file intent data from Android
  static Future<void> _handleFileIntentData(Map<dynamic, dynamic> intentData) async {
    try {
      final String? action = intentData['action'] as String?;
      final String? dataString = intentData['data'] as String?;
      final String? type = intentData['type'] as String?;
      
      print('🔗 FILE INTENT: Intent data - action: $action, type: $type, data: $dataString');
      
      if (action == 'android.intent.action.VIEW' && dataString != null) {
        // Handle file URI
        if (dataString.startsWith('content://') || dataString.startsWith('file://')) {
          // Get actual file path from URI
          try {
            final String? filePath = await _channel.invokeMethod('getFilePathFromUri', dataString);
            if (filePath != null) {
              // ✅ ISPRAVKA: Provjeri sadržaj umjesto ekstenzije
              print('📁 FILE INTENT: Got file path: $filePath');
              if (await _isValidLocadoFile(filePath)) {
                print('✅ FILE INTENT: File validated as Locado format');
                await _importLocadoFile(filePath);
              } else {
                print('❌ FILE INTENT: File failed Locado validation');
                NavigationService.showError('Invalid file format. This is not a valid Locado task file.');
              }
            } else {
              NavigationService.showError('Could not access the shared file.');
            }
          } catch (e) {
            print('❌ FILE INTENT: Error getting file path from URI: $e');
            NavigationService.showError('Failed to access shared file: $e');
          }
        }
      }
    } catch (e) {
      print('❌ FILE INTENT: Error handling intent data: $e');
      NavigationService.showError('Failed to process file intent: $e');
    }
  }

  /// Import .locado file
  static Future<void> _importLocadoFile(String filePath) async {
    try {
      print('📁 IMPORT: Starting import of .locado file: $filePath');

      final file = File(filePath);
      if (!await file.exists()) {
        throw Exception('File does not exist: $filePath');
      }

      // Read and parse file
      final jsonString = await file.readAsString();
      final Map<String, dynamic> data = jsonDecode(jsonString);

      print('📁 IMPORT: Parsed JSON data keys: ${data.keys.toList()}');

      // Validate .locado format
      if (!_validateLocadoFormat(data)) {
        throw Exception('Invalid .locado file format. This doesn\'t appear to be a valid Locado task file.');
      }

      // Extract task data
      final Map<String, dynamic> taskData = data['task_data'];
      final task = TaskLocation.fromMap(taskData);

      // Create new task (clear existing ID to create new task)
      final newTask = TaskLocation(
        id: null, // Let database assign new ID
        latitude: task.latitude,
        longitude: task.longitude,
        title: task.title,
        taskItems: List<String>.from(task.taskItems),
        colorHex: task.colorHex,
        scheduledDateTime: task.scheduledDateTime,
        linkedCalendarEventId: null, // Don't copy calendar links
      );

      // Save to database
      final taskId = await DatabaseHelper.instance.addTaskLocation(newTask);
      print('📁 IMPORT: Task saved with ID: $taskId');

      // Navigate to main screen and show imported task
      await _navigateToImportedTask(newTask.copyWith(id: taskId));

    } catch (e) {
      print('❌ IMPORT ERROR: $e');
      _showImportError(e.toString());
    }
  }

  /// Validate .locado file format
  static bool _validateLocadoFormat(Map<String, dynamic> data) {
    final hasVersion = data.containsKey('locado_version');
    final hasExportType = data.containsKey('export_type') && data['export_type'] == 'task_share';
    final hasTaskData = data.containsKey('task_data') && data['task_data'] is Map<String, dynamic>;
    
    if (!hasVersion || !hasExportType || !hasTaskData) {
      print('❌ VALIDATION: Missing required fields');
      print('  - locado_version: $hasVersion');
      print('  - export_type: $hasExportType');
      print('  - task_data: $hasTaskData');
      return false;
    }
    
    // Validate task_data structure
    final taskData = data['task_data'] as Map<String, dynamic>;
    final hasTitle = taskData.containsKey('title');
    final hasLatitude = taskData.containsKey('latitude');
    final hasLongitude = taskData.containsKey('longitude');
    final hasTaskItems = taskData.containsKey('taskItems');
    
    if (!hasTitle || !hasLatitude || !hasLongitude || !hasTaskItems) {
      print('❌ TASK DATA VALIDATION: Missing required task fields');
      print('  - title: $hasTitle');
      print('  - latitude: $hasLatitude');
      print('  - longitude: $hasLongitude');
      print('  - taskItems: $hasTaskItems');
      return false;
    }
    
    return true;
  }

  /// Navigate to main screen and focus on imported task 
	static Future<void> _navigateToImportedTask(TaskLocation task) async {
	  try {
		print('🔥 DEBUG: _navigateToImportedTask called with task: ${task.title}');
		print('🔗 IMPORT: Opening TaskDetailScreen for: ${task.title}');
		
		final navigatorKey = NavigationService.navigatorKey;
		final context = navigatorKey.currentContext;
		
		print('🔥 DEBUG: Navigator context: ${context != null ? "AVAILABLE" : "NULL"}');
		
		if (context != null) {
		  print('🔥 DEBUG: Using existing app instance');
		  
		  // ✅ DIREKTNO OTVORI TaskDetailScreen - BEZ IKAKVIH NavigationService poziva
		  final result = await Navigator.push(
			context,
			MaterialPageRoute(
			  builder: (ctx) => TaskDetailScreen(taskLocation: task),
			),
		  );
		  
		  print('🔥 DEBUG: TaskDetailScreen closed with result: $result');
		  
		  // Show success message
		  if (context.mounted) {
			ScaffoldMessenger.of(context).showSnackBar(
			  SnackBar(
				content: Row(
				  children: [
					const Icon(Icons.file_download, color: Colors.white),
					const SizedBox(width: 8),
					Expanded(child: Text('Task "${task.title}" imported successfully!')),
				  ],
				),
				backgroundColor: Colors.green,
				duration: const Duration(seconds: 3),
			  ),
			);
		  }
		  
		} else {
		  print('🔥 DEBUG: No context available - app may not be running');
		  // ✅ FALLBACK - samo pokaži error, ne pokušavaj pokretanje
		  _showImportError('Cannot open task - app not ready');
		}

	  } catch (e) {
		print('❌ IMPORT ERROR: $e');
		_showImportError('Failed to open imported task: $e');
	  }
	}



  /// Show import error message
  static void _showImportError(String error) {
    NavigationService.showError('Import failed: $error');
  }

  /// Clean up resources
  static void dispose() {
    print('🔗 FILE INTENT: Disposing resources...');
    // Method channel doesn't need explicit cleanup
  }
}