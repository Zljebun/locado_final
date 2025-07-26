// lib/services/delete_task_service.dart

import 'package:flutter/services.dart';
import 'package:locado_final/helpers/database_helper.dart';
import 'package:flutter/material.dart';

class DeleteTaskService {
  static const MethodChannel _deleteChannel = MethodChannel('com.example.locado_final/delete_task');

  /// Check za pending delete task request iz Android-a
  static Future<void> checkAndHandlePendingDeleteTask(BuildContext context) async {
    try {
      final result = await _deleteChannel.invokeMethod('checkPendingDeleteTask');

      if (result != null && result is Map) {
        final hasDeleteRequest = result['hasDeleteRequest'] as bool? ?? false;

        if (hasDeleteRequest) {
          final taskId = result['taskId'] as String?;
          final taskTitle = result['taskTitle'] as String?;

          if (taskId != null && taskTitle != null) {
            print('🗑️ Flutter received delete task request: $taskId - $taskTitle');
            await _showDeleteConfirmationAndExecute(context, taskId, taskTitle);
          }
        }
      }
    } catch (e) {
      print('❌ Error checking pending delete task: $e');
    }
  }

  /// Prikaži confirmation dialog i izvrši brisanje
  static Future<void> _showDeleteConfirmationAndExecute(
      BuildContext context,
      String taskId,
      String taskTitle
      ) async {
    // Auto-execute delete without confirmation since user already confirmed in LockScreenTaskActivity
    await _executeTaskDeletion(context, taskId, taskTitle);
  }

  /// Izvrši stvarno brisanje taska
  static Future<void> _executeTaskDeletion(
      BuildContext context,
      String taskId,
      String taskTitle
      ) async {
    try {
      final taskIdInt = int.tryParse(taskId);
      if (taskIdInt == null) {
        throw Exception('Invalid task ID: $taskId');
      }

      print('🗑️ Executing task deletion: $taskIdInt - $taskTitle');

      // Obriši task iz baze podataka
      final deletedRows = await DatabaseHelper.instance.deleteTaskLocation(taskIdInt);

      if (deletedRows > 0) {
        print('✅ Task successfully deleted from database: $taskIdInt');

        // Potvrdi brisanje Android-u
        await _deleteChannel.invokeMethod('confirmTaskDeletion', {
          'taskId': taskId,
          'taskTitle': taskTitle,
        });

        // Prikaži success message
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.check_circle, color: Colors.white, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'Task Deleted Successfully',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                        Text(
                          '"$taskTitle" has been permanently removed',
                          style: TextStyle(fontSize: 14, color: Colors.white.withOpacity(0.9)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              backgroundColor: Colors.green.shade600,
              duration: const Duration(seconds: 4),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              margin: const EdgeInsets.all(16),
            ),
          );
        }

        print('✅ Task deletion completed successfully');
      } else {
        throw Exception('Task not found in database');
      }

    } catch (e) {
      print('❌ Error deleting task: $e');

      // Prikaži error message
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.error, color: Colors.white, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'Delete Failed',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      Text(
                        'Could not delete "$taskTitle": $e',
                        style: TextStyle(fontSize: 14, color: Colors.white.withOpacity(0.9)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            backgroundColor: Colors.red.shade600,
            duration: const Duration(seconds: 5),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            margin: const EdgeInsets.all(16),
          ),
        );
      }
    }
  }

  /// Manual delete task method (za korišćenje iz UI)
  static Future<bool> deleteTask(
      BuildContext context,
      int taskId,
      String taskTitle,
      {bool showConfirmation = true}
      ) async {
    try {
      bool shouldDelete = true;

      if (showConfirmation) {
        final confirmed = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            elevation: 8,
            backgroundColor: Colors.white,

            // 🎨 STYLED TITLE sa icon
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                      Icons.delete_forever,
                      color: Colors.red.shade600,
                      size: 28
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Delete Task',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey.shade800,
                    ),
                  ),
                ),
              ],
            ),

            // 🎨 STYLED CONTENT
            content: SizedBox(
              width: 300,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 8),

                  // Task title card
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.teal.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.teal.shade200),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.task_alt, color: Colors.teal.shade600, size: 18),
                            const SizedBox(width: 8),
                            Text(
                              'Task to delete:',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: Colors.teal.shade700,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          taskTitle,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.teal.shade800,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),

                  // Warning message
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.orange.shade200),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.warning_amber, color: Colors.orange.shade600, size: 20),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'This action cannot be undone. All task data will be permanently removed.',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.orange.shade800,
                              height: 1.3,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // 🎨 STYLED ACTION BUTTONS
            actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
            actions: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Cancel button
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(context, false),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.grey.shade100,
                        foregroundColor: Colors.grey.shade700,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(color: Colors.grey.shade300),
                        ),
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.close, size: 18),
                          SizedBox(width: 8),
                          Text('Cancel', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(width: 12),

                  // Delete button
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(context, true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red.shade600,
                        foregroundColor: Colors.white,
                        elevation: 2,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.delete_forever, size: 18),
                          SizedBox(width: 8),
                          Text('Delete', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );

        shouldDelete = confirmed == true;
      }

      if (shouldDelete) {
        final deletedRows = await DatabaseHelper.instance.deleteTaskLocation(taskId);

        if (deletedRows > 0) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.check_circle, color: Colors.white, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text(
                            'Task Deleted',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                          Text(
                            '"$taskTitle" was successfully removed',
                            style: TextStyle(fontSize: 14, color: Colors.white.withOpacity(0.9)),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                backgroundColor: Colors.green.shade600,
                duration: const Duration(seconds: 4),
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                margin: const EdgeInsets.all(16),
              ),
            );
          }
          return true;
        }
      }

      return false;

    } catch (e) {
      print('❌ Error in manual task deletion: $e');

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.error, color: Colors.white, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'Delete Failed',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      Text(
                        'Error: $e',
                        style: TextStyle(fontSize: 14, color: Colors.white.withOpacity(0.9)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            backgroundColor: Colors.red.shade600,
            duration: const Duration(seconds: 5),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            margin: const EdgeInsets.all(16),
          ),
        );
      }

      return false;
    }
  }
}