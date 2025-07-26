// lib/screens/task_detail_bridge.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:locado_final/models/task_location.dart';
import 'package:locado_final/helpers/database_helper.dart';
import 'package:locado_final/screens/task_detail_screen.dart';

class TaskDetailBridge extends StatefulWidget {
  @override
  _TaskDetailBridgeState createState() => _TaskDetailBridgeState();
}

class _TaskDetailBridgeState extends State<TaskDetailBridge> {
  static const MethodChannel _channel = MethodChannel('com.example.locado_final/task_detail_channel');

  TaskLocation? taskLocation;
  bool isLoading = true;
  String? error;
  String? taskId;
  String? taskTitle;

  @override
  void initState() {
    super.initState();
    _initializeFromAndroid();
  }

  /// Inicijalizuje podatke iz Android TaskDetailFlutterActivity
  Future<void> _initializeFromAndroid() async {
    try {
      // Pozovi Android da dobije task podatke
      final result = await _channel.invokeMethod('getTaskData');

      if (result != null && result is Map) {
        final taskIdFromAndroid = result['taskId'] as String?;
        final taskTitleFromAndroid = result['taskTitle'] as String?;

        if (taskIdFromAndroid != null && taskIdFromAndroid.isNotEmpty) {
          setState(() {
            taskId = taskIdFromAndroid;
            taskTitle = taskTitleFromAndroid;
          });

          await _loadTaskData(taskIdFromAndroid);
        } else {
          setState(() {
            error = 'No task ID received from Android';
            isLoading = false;
          });
        }
      } else {
        setState(() {
          error = 'Failed to receive data from Android';
          isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        error = 'Error communicating with Android: $e';
        isLoading = false;
      });
    }
  }

  /// Učitava task podatke iz baze
  Future<void> _loadTaskData(String taskId) async {
    try {
      final taskIdInt = int.tryParse(taskId);
      if (taskIdInt == null) {
        setState(() {
          error = 'Invalid task ID: $taskId';
          isLoading = false;
        });
        return;
      }

      final task = await DatabaseHelper.instance.getTaskLocationById(taskIdInt);

      if (task != null) {
        setState(() {
          taskLocation = task;
          isLoading = false;
        });
      } else {
        setState(() {
          error = 'Task not found with ID: $taskId';
          isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        error = 'Failed to load task: $e';
        isLoading = false;
      });
    }
  }

  /// Zatvaranje kroz Android
  Future<void> _closeTaskDetail() async {
    try {
      await _channel.invokeMethod('closeTaskDetail');
    } catch (e) {
      // Fallback: sistemski izlaz
      SystemNavigator.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Task Detail',
      theme: ThemeData(
        primarySwatch: Colors.teal,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: Scaffold(
        body: _buildBody(),
      ),
      debugShowCheckedModeBanner: false,
    );
  }

  Widget _buildBody() {
    if (isLoading) {
      return _buildLoadingScreen();
    }

    if (error != null) {
      return _buildErrorScreen();
    }

    if (taskLocation == null) {
      return _buildNotFoundScreen();
    }

    // 🎯 GLAVNI DEO: Prikaz postojećeg TaskDetailScreen sa lock screen mode
    return WillPopScope(
      onWillPop: () async {
        await _closeTaskDetail();
        return false;
      },
      child: TaskDetailScreen(
        taskLocation: taskLocation!,
        isLockScreenMode: true, // 🔥 NOVO: Lock screen mode
      ),
    );
  }

  Widget _buildLoadingScreen() {
    return Container(
      color: Colors.white,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(
              color: Colors.teal,
              strokeWidth: 3,
            ),
            SizedBox(height: 24),
            Text(
              'Loading task details...',
              style: TextStyle(
                fontSize: 18,
                color: Colors.grey.shade600,
              ),
            ),
            if (taskTitle != null) ...[
              SizedBox(height: 8),
              Text(
                taskTitle!,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.teal,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildErrorScreen() {
    return Container(
      color: Colors.white,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.error_outline,
                color: Colors.red,
                size: 64,
              ),
              SizedBox(height: 24),
              Text(
                'Error Loading Task',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.red,
                ),
              ),
              SizedBox(height: 16),
              Text(
                error!,
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.grey.shade600,
                ),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: 32),
              ElevatedButton(
                onPressed: _closeTaskDetail,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                  padding: EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                ),
                child: Text(
                  'Close',
                  style: TextStyle(fontSize: 16),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNotFoundScreen() {
    return Container(
      color: Colors.white,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.search_off,
                size: 64,
                color: Colors.grey.shade400,
              ),
              SizedBox(height: 24),
              Text(
                'Task Not Found',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey.shade600,
                ),
              ),
              SizedBox(height: 16),
              Text(
                'The requested task could not be found.',
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.grey.shade600,
                ),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: 32),
              ElevatedButton(
                onPressed: _closeTaskDetail,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.grey.shade600,
                  foregroundColor: Colors.white,
                  padding: EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                ),
                child: Text(
                  'Close',
                  style: TextStyle(fontSize: 16),
                ),

              ),
            ],
          ),
        ),
      ),
    );
  }
}