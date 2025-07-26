// lib/task_detail_app.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:locado_final/helpers/database_helper.dart';
import 'package:locado_final/models/task_location.dart';
import 'package:locado_final/screens/task_detail_screen.dart';

class TaskDetailApp extends StatefulWidget {
  const TaskDetailApp({Key? key}) : super(key: key);

  @override
  State<TaskDetailApp> createState() => _TaskDetailAppState();
}

class _TaskDetailAppState extends State<TaskDetailApp> {
  static const platform = MethodChannel('com.example.locado_final/task_detail_direct');

  TaskLocation? taskLocation;
  bool isLoading = true;
  String? errorMessage;

  @override
  void initState() {
    super.initState();
    _loadTaskDetailData();
  }

  Future<void> _loadTaskDetailData() async {
    try {
      print('🔍 TaskDetailApp: Getting task data from Android...');

      // Get task data from Android
      final result = await platform.invokeMethod('getTaskDetailData');

      final taskId = result['taskId'] as String;
      final taskTitle = result['taskTitle'] as String;
      final fromNotification = result['fromNotification'] as bool;

      print('📝 TaskDetailApp: TaskID: $taskId, Title: $taskTitle, FromNotification: $fromNotification');

      if (taskId.isNotEmpty) {
        // Parse task ID to get the actual database ID
        final actualTaskId = taskId.startsWith('task_')
            ? int.tryParse(taskId.substring(5))
            : int.tryParse(taskId);

        if (actualTaskId != null) {
          // Load task from database
          print('📊 TaskDetailApp: Loading task $actualTaskId from database...');

          final loadedTask = await DatabaseHelper.instance.getTaskLocationById(actualTaskId);

          if (loadedTask != null) {
            print('✅ TaskDetailApp: Task loaded successfully');
            setState(() {
              taskLocation = loadedTask;
              isLoading = false;
            });
          } else {
            print('❌ TaskDetailApp: Task not found in database');
            setState(() {
              errorMessage = 'Task not found';
              isLoading = false;
            });
          }
        } else {
          print('❌ TaskDetailApp: Invalid task ID format');
          setState(() {
            errorMessage = 'Invalid task ID';
            isLoading = false;
          });
        }
      } else {
        print('❌ TaskDetailApp: Empty task ID');
        setState(() {
          errorMessage = 'No task ID provided';
          isLoading = false;
        });
      }
    } catch (e) {
      print('❌ TaskDetailApp: Error loading task data: $e');
      setState(() {
        errorMessage = 'Error loading task: $e';
        isLoading = false;
      });
    }
  }

  Future<void> _closeTaskDetail() async {
    try {
      await platform.invokeMethod('closeTaskDetail');
    } catch (e) {
      print('❌ Error closing task detail: $e');
      // Fallback: use system navigator
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Task Detail',
      theme: ThemeData(
        primarySwatch: Colors.teal,
        fontFamily: 'Roboto',
      ),
      home: Scaffold(
        body: isLoading
            ? const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(color: Colors.teal),
              SizedBox(height: 16),
              Text('Loading task details...'),
            ],
          ),
        )
            : errorMessage != null
            ? Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.error_outline,
                size: 64,
                color: Colors.red.shade400,
              ),
              const SizedBox(height: 16),
              Text(
                'Error',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.red.shade700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                errorMessage!,
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.grey.shade600,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: _closeTaskDetail,
                icon: const Icon(Icons.close),
                label: const Text('Close'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
        )
            : taskLocation != null
            ? WillPopScope(
          onWillPop: () async {
            await _closeTaskDetail();
            return false;
          },
          child: TaskDetailScreen(
            taskLocation: taskLocation!,
          ),
        )
            : Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.task_alt,
                size: 64,
                color: Colors.grey.shade400,
              ),
              const SizedBox(height: 16),
              Text(
                'Task not found',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey.shade600,
                ),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: _closeTaskDetail,
                icon: const Icon(Icons.close),
                label: const Text('Close'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.grey,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}