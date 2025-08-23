// lib/screens/debug_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'dart:async';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../services/onboarding_service.dart';
import 'package:locado_final/screens/notification_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class DebugScreen extends StatefulWidget {
  @override
  _DebugScreenState createState() => _DebugScreenState();
}

class _DebugScreenState extends State<DebugScreen> {
  static const platform = MethodChannel('com.example.locado_final/debug');
  // Battery optimization method channel
  static const platformGeofence = MethodChannel('com.example.locado_final/geofence');

  String _serviceStatus = 'Checking...';
  String _geofenceCount = 'Checking...';
  String _lastHeartbeat = 'Checking...';
  String _logFileSize = 'Checking...';
  String _logFilePath = '';
  List<String> _recentLogs = [];
  bool _isLoading = true;
  Timer? _refreshTimer;

  // Battery optimization variables
  bool _isBatteryWhitelisted = false;
  bool _canRequestWhitelist = false;
  String _androidVersion = '';
  String _packageName = '';
  bool _isBatteryLoading = false;

  // Onboarding debug variables
  Map<String, dynamic> _onboardingDebugInfo = {};
  bool _isOnboardingLoading = false;

  @override
  void initState() {
    super.initState();
    _refreshStatus();
    _checkBatteryOptimization();
    _loadOnboardingDebugInfo();
    _startAutoRefresh();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  void _startAutoRefresh() {
    _refreshTimer = Timer.periodic(Duration(seconds: 5), (timer) {
      _refreshStatus();
      _checkBatteryOptimization();
      _loadOnboardingDebugInfo();
    });
  }

  Future<void> _refreshStatus() async {
    try {
      final result = await platform.invokeMethod('getDebugStatus');

      setState(() {
        _serviceStatus = result['serviceStatus'] ?? 'Unknown';
        _geofenceCount = result['geofenceCount']?.toString() ?? '0';
        _lastHeartbeat = result['lastHeartbeat'] ?? 'Never';
        _logFileSize = result['logFileSize'] ?? '0 KB';
        _logFilePath = result['logFilePath'] ?? '';
        _recentLogs = List<String>.from(result['recentLogs'] ?? []);
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _serviceStatus = 'Error: $e';
        _isLoading = false;
      });
    }
  }

  // Battery optimization status check
  Future<void> _checkBatteryOptimization() async {
    if (_isBatteryLoading) return;

    setState(() => _isBatteryLoading = true);

    try {
      final result = await platformGeofence.invokeMethod('checkBatteryOptimization');

      setState(() {
        _isBatteryWhitelisted = result['isWhitelisted'] ?? false;
        _canRequestWhitelist = result['canRequestWhitelist'] ?? false;
        _androidVersion = result['androidVersion']?.toString() ?? '';
        _packageName = result['packageName'] ?? '';
        _isBatteryLoading = false;
      });

      print('🔋 Battery optimization status: $_isBatteryWhitelisted');
    } catch (e) {
      setState(() => _isBatteryLoading = false);
      print('❌ Error checking battery optimization: $e');
    }
  }

  // Request battery optimization whitelist
  Future<void> _requestBatteryOptimizationWhitelist() async {
    if (_isBatteryLoading) return;

    setState(() => _isBatteryLoading = true);

    try {
      final result = await platformGeofence.invokeMethod('requestBatteryOptimizationWhitelist');

      _showSnackBar('Battery optimization request: $result', Colors.blue);

      // Wait a bit then check status again
      await Future.delayed(Duration(seconds: 2));
      await _checkBatteryOptimization();

    } catch (e) {
      setState(() => _isBatteryLoading = false);
      _showSnackBar('Error requesting battery optimization: $e', Colors.red);
    }
  }

  // Load onboarding debug information
  Future<void> _loadOnboardingDebugInfo() async {
    if (_isOnboardingLoading) return;

    setState(() => _isOnboardingLoading = true);

    try {
      final debugInfo = await OnboardingService.getDebugInfo();
      setState(() {
        _onboardingDebugInfo = debugInfo;
        _isOnboardingLoading = false;
      });
    } catch (e) {
      setState(() {
        _onboardingDebugInfo = {'error': e.toString()};
        _isOnboardingLoading = false;
      });
    }
  }

  // Test battery onboarding
  Future<void> _testBatteryOnboarding() async {
    try {
      setState(() => _isOnboardingLoading = true);

      // Reset onboarding state
      await OnboardingService.resetOnboarding();

      // Refresh debug info
      await _loadOnboardingDebugInfo();

      _showSnackBar('Onboarding reset! Navigating to onboarding screen...', Colors.deepPurple);

      // Small delay for UI feedback
      await Future.delayed(Duration(milliseconds: 500));

      // Navigate to onboarding screen
      Navigator.of(context).pushNamed('/onboarding');

    } catch (e) {
      _showSnackBar('Error testing onboarding: $e', Colors.red);
      print('❌ Error testing onboarding: $e');
    } finally {
      setState(() => _isOnboardingLoading = false);
    }
  }

  // Show onboarding debug info dialog
  void _showOnboardingDebugInfo() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.info_outline, color: Colors.deepPurple),
            SizedBox(width: 8),
            Text('Onboarding Debug Info'),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: _onboardingDebugInfo.entries.map((entry) {
              return Padding(
                padding: EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 120,
                      child: Text(
                        '${entry.key}:',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        '${entry.value}',
                        style: TextStyle(fontSize: 12, fontFamily: 'monospace'),
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Close'),
          ),
        ],
      ),
    );
  }
  
	Future<void> _testImmediateNotification() async {
	  try {
		await flutterLocalNotificationsPlugin.show(
		  999,
		  'Test Notification',
		  'This is immediate test notification',
		  const NotificationDetails(
			android: AndroidNotificationDetails(
			  'calendar_reminder_channel',
			  'Calendar Reminders',
			  importance: Importance.max,
			  priority: Priority.high,
			),
		  ),
		);
		print('Test notification sent');
	  } catch (e) {
		print('Error sending test notification: $e');
	  }
	}

	Future<void> _checkPendingNotifications() async {
	  try {
		final pending = await NotificationService.getPendingNotifications();
		print('Pending notifications: ${pending.length}');
		for (final notification in pending) {
		  print('ID: ${notification.id}, Title: ${notification.title}');
		}
	  } catch (e) {
		print('Error checking pending notifications: $e');
	  }
	}

  Future<void> _shareLogFile() async {
    try {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          content: Row(
            children: [
              CircularProgressIndicator(),
              SizedBox(width: 16),
              Text('Preparing log file...'),
            ],
          ),
        ),
      );

      final result = await platform.invokeMethod('shareLogFile');

      Navigator.pop(context); // Close loading dialog

      if (result['success'] == true) {
        final String logContent = result['logContent'] ?? '';
        final String fileName = 'locado_debug_log_${DateTime.now().millisecondsSinceEpoch}.txt';

        // Create temporary file
        final tempDir = await getTemporaryDirectory();
        final tempFile = File('${tempDir.path}/$fileName');
        await tempFile.writeAsString(logContent);

        // Share the file
        await Share.shareXFiles(
          [XFile(tempFile.path)],
          text: 'Locado Debug Logs - ${DateTime.now().toString()}',
          subject: 'Locado Debug Logs',
        );

        _showSnackBar('Log file shared successfully!', Colors.green);
      } else {
        _showSnackBar('Error sharing log file: ${result['error']}', Colors.red);
      }
    } catch (e) {
      Navigator.pop(context); // Close loading dialog if still open
      _showSnackBar('Error sharing log file: $e', Colors.red);
    }
  }

  Future<void> _clearLogs() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Clear Debug Logs'),
        content: Text('Are you sure you want to clear all debug logs? This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Clear', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await platform.invokeMethod('clearLogs');
        _showSnackBar('Logs cleared successfully!', Colors.green);
        _refreshStatus();
      } catch (e) {
        _showSnackBar('Error clearing logs: $e', Colors.red);
      }
    }
  }

  Future<void> _testNotification() async {
    try {
      await platform.invokeMethod('testNotification');
      _showSnackBar('Test notification sent!', Colors.green);
    } catch (e) {
      _showSnackBar('Error sending test notification: $e', Colors.red);
    }
  }

  Future<void> _simulateGeofence() async {
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Simulate Geofence Event'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Select geofence event type:'),
            SizedBox(height: 16),
            ListTile(
              title: Text('Enter Geofence'),
              leading: Radio<String>(
                value: 'enter',
                groupValue: null,
                onChanged: (value) => Navigator.pop(context, value),
              ),
            ),
            ListTile(
              title: Text('Exit Geofence'),
              leading: Radio<String>(
                value: 'exit',
                groupValue: null,
                onChanged: (value) => Navigator.pop(context, value),
              ),
            ),
            ListTile(
              title: Text('Dwell in Geofence'),
              leading: Radio<String>(
                value: 'dwell',
                groupValue: null,
                onChanged: (value) => Navigator.pop(context, value),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, null),
            child: Text('Cancel'),
          ),
        ],
      ),
    );

    if (result != null) {
      try {
        await platform.invokeMethod('simulateGeofence', {'eventType': result});
        _showSnackBar('Geofence event simulated: $result', Colors.green);
        _refreshStatus();
      } catch (e) {
        _showSnackBar('Error simulating geofence: $e', Colors.red);
      }
    }
  }

  Future<void> _checkService() async {
    try {
      final result = await platform.invokeMethod('checkService');
      _showSnackBar('Service check completed: ${result['status']}', Colors.blue);
      _refreshStatus();
    } catch (e) {
      _showSnackBar('Error checking service: $e', Colors.red);
    }
  }

  Future<void> _viewFullLogs() async {
    try {
      final result = await platform.invokeMethod('getFullLogs');
      final String logs = result['logs'] ?? 'No logs available';

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => Scaffold(
            appBar: AppBar(
              title: Text('Debug Logs'),
              backgroundColor: Colors.teal,
              foregroundColor: Colors.white,
              actions: [
                IconButton(
                  icon: Icon(Icons.copy),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: logs));
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Logs copied to clipboard!')),
                    );
                  },
                ),
              ],
            ),
            body: Container(
              padding: EdgeInsets.all(16),
              child: SingleChildScrollView(
                child: SelectableText(
                  logs,
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    } catch (e) {
      _showSnackBar('Error loading logs: $e', Colors.red);
    }
  }

  // Battery optimization info dialog
  void _showBatteryOptimizationInfo() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.battery_saver, color: Colors.orange),
            SizedBox(width: 8),
            Text('Battery Optimization'),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Package: $_packageName', style: TextStyle(fontFamily: 'monospace', fontSize: 12)),
              SizedBox(height: 8),
              Text('Android Version: $_androidVersion'),
              SizedBox(height: 8),
              Text('Can Request Whitelist: ${_canRequestWhitelist ? "YES" : "NO"}'),
              SizedBox(height: 16),
              Text(
                'Why is this important?',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 8),
              Text(
                'When your app is NOT whitelisted:\n'
                    '• Android puts your app to sleep (Doze mode)\n'
                    '• Geofencing stops working when phone is locked\n'
                    '• Location tracking is paused\n'
                    '• Notifications may not appear\n\n'
                    'When your app IS whitelisted:\n'
                    '• App continues working even when phone sleeps\n'
                    '• Geofencing works 24/7\n'
                    '• Reliable location notifications',
                style: TextStyle(fontSize: 14),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Got it!'),
          ),
        ],
      ),
    );
  }

  void _showSnackBar(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
        duration: Duration(seconds: 3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Debug Panel'),
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: Icon(Icons.refresh),
            onPressed: () {
              _refreshStatus();
              _checkBatteryOptimization();
              _loadOnboardingDebugInfo();
            },
          ),
        ],
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Onboarding Debug Section
            _buildSectionCard(
              title: '🚀 Onboarding Debug',
              children: [
                if (_isOnboardingLoading)
                  Center(child: CircularProgressIndicator())
                else ...[
                  ..._onboardingDebugInfo.entries.take(3).map((entry) =>
                      _buildStatusRow(entry.key, '${entry.value}')
                  ).toList(),
                  SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _isOnboardingLoading ? null : _loadOnboardingDebugInfo,
                          icon: Icon(Icons.refresh),
                          label: Text('Refresh Info'),
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
                        ),
                      ),
                      SizedBox(width: 8),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _showOnboardingDebugInfo,
                          icon: Icon(Icons.info_outline),
                          label: Text('Full Info'),
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _isOnboardingLoading ? null : _testBatteryOnboarding,
                      icon: _isOnboardingLoading
                          ? SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                          : Icon(Icons.battery_charging_full),
                      label: Text(_isOnboardingLoading ? 'Resetting...' : 'Test Battery Onboarding'),
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.deepPurple),
                    ),
                  ),
                ],
              ],
            ),
            SizedBox(height: 16),

            // Battery Optimization Section
				// Manual Tests Section
				_buildSectionCard(
				  title: '🧪 Manual Tests',
				  children: [
					Row(
					  children: [
						Expanded(
						  child: ElevatedButton.icon(
							onPressed: _testNotification,
							icon: Icon(Icons.notifications),
							label: Text('Test Notification'),
							style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
						  ),
						),
						SizedBox(width: 8),
						Expanded(
						  child: ElevatedButton.icon(
							onPressed: _simulateGeofence,
							icon: Icon(Icons.location_on),
							label: Text('Simulate Geofence'),
							style: ElevatedButton.styleFrom(backgroundColor: Colors.purple),
						  ),
						),
					  ],
					),
					SizedBox(height: 8),
					// Nova dugmad za testiranje notifikacija
					Row(
					  children: [
						Expanded(
						  child: ElevatedButton.icon(
							onPressed: _testImmediateNotification,
							icon: Icon(Icons.notification_add),
							label: Text('Test Immediate'),
							style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
						  ),
						),
						SizedBox(width: 8),
						Expanded(
						  child: ElevatedButton.icon(
							onPressed: _checkPendingNotifications,
							icon: Icon(Icons.pending_actions),
							label: Text('Check Pending'),
							style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo),
						  ),
						),
					  ],
					),
					SizedBox(height: 8),
					SizedBox(
					  width: double.infinity,
					  child: ElevatedButton.icon(
						onPressed: _checkService,
						icon: Icon(Icons.health_and_safety),
						label: Text('Check Service'),
						style: ElevatedButton.styleFrom(backgroundColor: Colors.teal),
					  ),
					),
				  ],
				),
            SizedBox(height: 16),

            // Current Status Section
            _buildSectionCard(
              title: '📊 Current Status',
              children: [
                _buildStatusRow('Service', _serviceStatus),
                _buildStatusRow('Geofences', '$_geofenceCount active'),
                _buildStatusRow('Last Heartbeat', _lastHeartbeat),
              ],
            ),
            SizedBox(height: 16),

            // Log Controls Section
            _buildSectionCard(
              title: '📝 Log Controls',
              children: [
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _viewFullLogs,
                        icon: Icon(Icons.visibility),
                        label: Text('View Logs'),
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
                      ),
                    ),
                    SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _shareLogFile,
                        icon: Icon(Icons.share),
                        label: Text('Share Logs'),
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _clearLogs,
                    icon: Icon(Icons.delete),
                    label: Text('Clear Logs'),
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                  ),
                ),
              ],
            ),
            SizedBox(height: 16),

            // Manual Tests Section
            _buildSectionCard(
              title: '🧪 Manual Tests',
              children: [
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _testNotification,
                        icon: Icon(Icons.notifications),
                        label: Text('Test Notification'),
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
                      ),
                    ),
                    SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _simulateGeofence,
                        icon: Icon(Icons.location_on),
                        label: Text('Simulate Geofence'),
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.purple),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _checkService,
                    icon: Icon(Icons.health_and_safety),
                    label: Text('Check Service'),
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.teal),
                  ),
                ),
              ],
            ),
            SizedBox(height: 16),

            // Log File Info Section
            _buildSectionCard(
              title: '📁 Log File Info',
              children: [
                _buildStatusRow('File Size', _logFileSize),
                _buildStatusRow('Path', _logFilePath.isNotEmpty
                    ? _logFilePath.split('/').last
                    : 'Not available'),
                _buildStatusRow('Last Update', DateTime.now().toString().split('.').first),
              ],
            ),
            SizedBox(height: 16),

            // Recent Logs Section
            _buildSectionCard(
              title: '📋 Recent Log Entries',
              children: [
                Container(
                  height: 200,
                  child: _recentLogs.isEmpty
                      ? Center(
                    child: Text(
                      'No recent logs available',
                      style: TextStyle(color: Colors.grey),
                    ),
                  )
                      : ListView.builder(
                    itemCount: _recentLogs.length,
                    itemBuilder: (context, index) {
                      final log = _recentLogs[index];
                      return Container(
                        margin: EdgeInsets.only(bottom: 4),
                        padding: EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.grey[100],
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          log,
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 11,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionCard({required String title, required List<Widget> children}) {
    return Card(
      elevation: 4,
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.teal,
              ),
            ),
            Divider(),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _buildStatusRow(String label, String value) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              '$label:',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.grey[700],
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: Colors.grey[800],
              ),
            ),
          ),
        ],
      ),
    );
  }
}