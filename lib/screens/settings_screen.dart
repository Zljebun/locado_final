import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'dart:typed_data';
import '../services/locado_background_service.dart';
import 'package:flutter/services.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({Key? key}) : super(key: key);

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final TextEditingController _distanceController = TextEditingController();
  static const String _notificationDistanceKey = 'notification_distance';
  static const String _notificationSoundModeKey = 'notification_sound_mode';
  static const String _autoFocusKey = 'auto_focus_enabled';
  static const String _vibrationEnabledKey = 'vibration_enabled';
  static const String _notificationPriorityKey = 'notification_priority';
  static const String _wakeScreenEnabledKey = 'wake_screen_enabled';
  static const MethodChannel _settingsChannel = MethodChannel('com.example.locado_final/settings');
  // 🔋 BATTERY OPTIMIZATION METHOD CHANNEL
  static const MethodChannel _geofenceChannel = MethodChannel('com.example.locado_final/geofence');

  String _notificationSoundMode = 'default';
  bool _autoFocusEnabled = true;
  bool _vibrationEnabled = true;
  bool _wakeScreenEnabled = true;
  String _notificationPriority = 'high';
  bool _isLoading = false;

  // 🔋 BATTERY OPTIMIZATION VARIJABLE
  bool _isBatteryWhitelisted = false;
  bool _canRequestWhitelist = false;
  String _androidVersion = '';
  String _packageName = '';
  bool _isBatteryLoading = false;

  final FlutterLocalNotificationsPlugin _flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

  @override
  void initState() {
    super.initState();
    _initializeNotificationPlugin();
    _loadSettings();
    _checkBatteryOptimization(); // 🔋 DODANO
  }

  Future<void> _initializeNotificationPlugin() async {
    const AndroidInitializationSettings initializationSettingsAndroid =
    AndroidInitializationSettings('@mipmap/ic_launcher');
    const InitializationSettings initializationSettings =
    InitializationSettings(android: initializationSettingsAndroid);

    await _flutterLocalNotificationsPlugin.initialize(initializationSettings);
    await _createTestChannel();
  }

  Future<void> _createTestChannel() async {
    final androidPlugin = _flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

    if (androidPlugin != null) {
      const AndroidNotificationChannel testChannel = AndroidNotificationChannel(
        'test_channel',
        'Test Notifications',
        description: 'For testing notification settings',
        importance: Importance.max,
        playSound: true,
        enableVibration: true,
      );

      await androidPlugin.createNotificationChannel(testChannel);
    }
  }

  Future<void> _loadSettings() async {
    setState(() => _isLoading = true);

    final prefs = await SharedPreferences.getInstance();
    final distance = prefs.getInt(_notificationDistanceKey) ?? 100;
    final soundMode = prefs.getString(_notificationSoundModeKey) ?? 'default';
    final autoFocus = prefs.getBool(_autoFocusKey) ?? true;
    final vibration = prefs.getBool(_vibrationEnabledKey) ?? true;
    final priority = prefs.getString(_notificationPriorityKey) ?? 'high';
    final wakeScreen = prefs.getBool(_wakeScreenEnabledKey) ?? true;

    setState(() {
      _distanceController.text = distance.toString();
      _notificationSoundMode = soundMode;
      _autoFocusEnabled = autoFocus;
      _vibrationEnabled = vibration;
      _notificationPriority = priority;
      _wakeScreenEnabled = wakeScreen;
      _isLoading = false;
    });
  }

  // 🔋 BATTERY OPTIMIZATION METHODS
  Future<void> _checkBatteryOptimization() async {
    if (_isBatteryLoading) return;

    setState(() => _isBatteryLoading = true);

    try {
      final result = await _geofenceChannel.invokeMethod('checkBatteryOptimization');

      final isWhitelisted = result['isWhitelisted'] as bool? ?? false;
      final canRequest = result['canRequestWhitelist'] as bool? ?? false;
      final androidVer = result['androidVersion']?.toString() ?? '';
      final packageN = result['packageName']?.toString() ?? '';

      setState(() {
        _isBatteryWhitelisted = isWhitelisted;
        _canRequestWhitelist = canRequest;
        _androidVersion = androidVer;
        _packageName = packageN;
        _isBatteryLoading = false;
      });

    } catch (e) {
      setState(() => _isBatteryLoading = false);
      debugPrint('Error checking battery optimization: $e');
    }
  }

  Future<void> _requestBatteryOptimizationWhitelist() async {
    if (_isBatteryLoading) return;

    setState(() => _isBatteryLoading = true);

    try {
      final result = await _geofenceChannel.invokeMethod('requestBatteryOptimizationWhitelist');

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Battery optimization request: $result'),
          backgroundColor: Colors.blue,
        ),
      );

      // Čekaj malo pa proveeri status ponovo
      await Future.delayed(Duration(seconds: 2));
      await _checkBatteryOptimization();

    } catch (e) {
      setState(() => _isBatteryLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error requesting battery optimization: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _showBatteryOptimizationInfo() {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        child: Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.7,
            maxWidth: MediaQuery.of(context).size.width * 0.9,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Theme.of(context).primaryColor,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(4),
                    topRight: Radius.circular(4),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.battery_saver, color: Colors.white),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Background App Activity',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Why is this important?',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      SizedBox(height: 12),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.check_circle, color: Colors.green, size: 18),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'When Optimized (Recommended):',
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 4),
                      Text('• Location notifications work 24/7\n• Alerts appear even when app is closed\n• Geofencing works reliably'),
                      SizedBox(height: 16),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.warning, color: Colors.orange, size: 18),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'When Not Optimized:',
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 4),
                      Text('• Notifications may be delayed\n• Alerts might not appear when phone is locked\n• Location tracking may pause'),
                      SizedBox(height: 16),
                      Container(
                        width: double.infinity,
                        padding: EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.blue.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.blue.shade200),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.info_outline, color: Colors.blue.shade600, size: 20),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'This setting helps ensure you never miss important location-based reminders.',
                                style: TextStyle(color: Colors.blue.shade700, fontSize: 14),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Got it!'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, Color color, String text) {
    return Padding(
      padding: EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 18),
          SizedBox(width: 8),
          Expanded(
            child: Text(text, style: TextStyle(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  Future<void> _saveSettings() async {
    final distance = int.tryParse(_distanceController.text);

    if (distance == null || distance <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a valid distance'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_notificationDistanceKey, distance);
      await prefs.setString(_notificationSoundModeKey, _notificationSoundMode);
      await prefs.setBool(_autoFocusKey, _autoFocusEnabled);
      await prefs.setBool(_vibrationEnabledKey, _vibrationEnabled);
      await prefs.setString(_notificationPriorityKey, _notificationPriority);
      await prefs.setBool(_wakeScreenEnabledKey, _wakeScreenEnabled);

      // ✅ NOVO: POŠALJI POSTAVKE ANDROID-U
      await _sendSettingsToAndroid(distance);

      // ✅ NOVO: RESETUJ CACHE U BACKGROUND SERVICE-U
      LocadoBackgroundService.resetRadiusCache();

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Settings saved successfully'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error saving settings: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }

    setState(() => _isLoading = false);
  }

// ✅ NOVA METODA: Pošalje postavke Android-u
  Future<void> _sendSettingsToAndroid(int distance) async {
    try {
      final settingsData = {
        'geofence_radius': distance.toDouble(),
        'sound_mode': _notificationSoundMode,
        'vibration_enabled': _vibrationEnabled,
        'wake_screen_enabled': _wakeScreenEnabled,
        'notification_priority': _notificationPriority,
      };

      await _settingsChannel.invokeMethod('updateSettings', settingsData);

      debugPrint('✅ Settings sent to Android successfully');
    } catch (e) {
      debugPrint('❌ Error sending settings to Android: $e');
    }
  }

  Future<void> _testNotification() async {
    final androidDetails = AndroidNotificationDetails(
      'test_channel',
      'Test Notifications',
      channelDescription: 'Test notification with current settings',
      importance: _getImportance(),
      priority: _getPriority(),
      enableVibration: _vibrationEnabled,
      playSound: _notificationSoundMode != 'silent',
      vibrationPattern: _vibrationEnabled ? Int64List.fromList([0, 400, 300, 400]) : null,
      fullScreenIntent: _wakeScreenEnabled,
      category: AndroidNotificationCategory.alarm,
      enableLights: true,
      ledColor: const Color.fromARGB(255, 0, 255, 0),
      styleInformation: BigTextStyleInformation(
        'Testing: Sound=${_notificationSoundMode}, Vibration=${_vibrationEnabled ? "ON" : "OFF"}, WakeScreen=${_wakeScreenEnabled ? "ON" : "OFF"}',
        contentTitle: '🔔 Test Notification',
        summaryText: 'Locado Settings Test',
      ),
    );

    final platformDetails = NotificationDetails(android: androidDetails);

    await _flutterLocalNotificationsPlugin.show(
      999,
      '🔔 Test: ${_wakeScreenEnabled ? "Wake Screen" : "Normal"}',
      'Sound: $_notificationSoundMode | Vibration: ${_vibrationEnabled ? "ON" : "OFF"} | Priority: $_notificationPriority',
      platformDetails,
    );

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Test sent! Wake Screen: ${_wakeScreenEnabled ? "ON" : "OFF"}'),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Importance _getImportance() {
    switch (_notificationPriority) {
      case 'low': return Importance.low;
      case 'normal': return Importance.defaultImportance;
      case 'high': return Importance.high;
      case 'max': return Importance.max;
      default: return Importance.high;
    }
  }

  Priority _getPriority() {
    switch (_notificationPriority) {
      case 'low': return Priority.low;
      case 'normal': return Priority.defaultPriority;
      case 'high': return Priority.high;
      case 'max': return Priority.max;
      default: return Priority.high;
    }
  }

  String _getSoundModeDescription(String mode) {
    switch (mode) {
      case 'default':
        return 'App default sound';
      case 'system_notification':
        return 'System notification';
      case 'system_alert':
        return 'System alert';
      case 'system_alarm':
        return 'System alarm';
      case 'silent':
        return 'Silent mode';
      default:
        return 'Unknown';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        actions: [
          IconButton(
            onPressed: _isLoading ? null : _saveSettings,
            icon: _isLoading
                ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
                : const Icon(Icons.save),
            tooltip: 'Save Settings',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Card(
              elevation: 4,
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.settings, color: Theme.of(context).primaryColor, size: 32),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'App Configuration',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Theme.of(context).primaryColor,
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: _testNotification,
                          icon: const Icon(Icons.notifications_active, color: Colors.orange),
                          tooltip: 'Test Notification',
                        ),
                        IconButton(
                          onPressed: _showHelpDialog,
                          icon: const Icon(Icons.help_outline, color: Colors.blue),
                          tooltip: 'Help & Info',
                        ),
                      ],
                    ),

                    const SizedBox(height: 24),

                    // 🎨 NEW SECTION: APPEARANCE SETTINGS
                    _buildSectionTitle('Appearance'),
                    const SizedBox(height: 8),
                    Text(
                      'Customize the app\'s visual appearance',
                      style: TextStyle(color: Theme.of(context).textTheme.bodySmall?.color, fontSize: 14),
                    ),
                    const SizedBox(height: 12),

                    _buildStaticThemeRow(),

                    const SizedBox(height: 24),

                    // 🔋 NOVA SEKCIJA: BACKGROUND APP ACTIVITY
                    _buildSectionTitle('Background App Activity'),
                    const SizedBox(height: 8),
                    Text(
                      'Enable reliable location notifications',
                      style: TextStyle(color: Theme.of(context).textTheme.bodySmall?.color, fontSize: 14),
                    ),
                    const SizedBox(height: 12),

                    Container(
                      padding: EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: _isBatteryWhitelisted ? Colors.green.shade50 : Colors.orange.shade50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _isBatteryWhitelisted ? Colors.green.shade200 : Colors.orange.shade300,
                          width: 1,
                        ),
                      ),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: _isBatteryWhitelisted ? Colors.green : Colors.orange,
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Icon(
                                  _isBatteryWhitelisted ? Icons.check : Icons.battery_saver,
                                  color: Colors.white,
                                  size: 20,
                                ),
                              ),
                              SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _isBatteryWhitelisted ? 'Optimized ✓' : 'Needs Optimization',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: _isBatteryWhitelisted ? Colors.green.shade800 : Colors.orange.shade800,
                                      ),
                                    ),
                                    Text(
                                      _isBatteryWhitelisted
                                          ? 'Location notifications will work reliably'
                                          : 'Notifications may be delayed or missed',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: _isBatteryWhitelisted ? Colors.green.shade700 : Colors.orange.shade700,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (_isBatteryLoading)
                                SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                ),
                            ],
                          ),

                          SizedBox(height: 12),

                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: _isBatteryLoading ? null : _checkBatteryOptimization,
                                  icon: Icon(Icons.refresh, size: 18),
                                  label: Text('Check Status'),
                                  style: OutlinedButton.styleFrom(
                                    side: BorderSide(color: Theme.of(context).primaryColor),
                                    foregroundColor: Theme.of(context).primaryColor,
                                  ),
                                ),
                              ),
                              SizedBox(width: 8),
                              Expanded(
                                child: ElevatedButton.icon(
                                  onPressed: (_isBatteryLoading || _isBatteryWhitelisted || !_canRequestWhitelist)
                                      ? null
                                      : _requestBatteryOptimizationWhitelist,
                                  icon: Icon(
                                    _isBatteryWhitelisted ? Icons.check : Icons.settings,
                                    size: 18,
                                  ),
                                  label: Text(_isBatteryWhitelisted ? 'Optimized' : 'Optimize'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: _isBatteryWhitelisted ? Colors.green : Colors.orange,
                                    foregroundColor: Colors.white,
                                  ),
                                ),
                              ),
                            ],
                          ),

                          SizedBox(height: 8),

                          SizedBox(
                            width: double.infinity,
                            child: TextButton.icon(
                              onPressed: _showBatteryOptimizationInfo,
                              icon: Icon(Icons.info_outline, size: 16),
                              label: Text('Why is this important?'),
                              style: TextButton.styleFrom(
                                foregroundColor: Theme.of(context).primaryColor,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 24),

                    _buildSectionTitle('Geofence Distance'),
                    const SizedBox(height: 8),
                    Text(
                      'Set how close you need to be to receive notifications',
                      style: TextStyle(color: Theme.of(context).textTheme.bodySmall?.color, fontSize: 14),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _distanceController,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        border: const OutlineInputBorder(),
                        labelText: 'Distance in meters',
                        hintText: 'e.g. 100',
                        prefixIcon: const Icon(Icons.location_on),
                        suffixText: 'm',
                        filled: true,
                        fillColor: Colors.grey.shade50,
                      ),
                    ),

                    const SizedBox(height: 24),

                    _buildSectionTitle('Notification Settings'),
                    const SizedBox(height: 16),

                    _buildSettingRow(
                      'Sound Mode',
                      _getSoundModeDescription(_notificationSoundMode),
                      Icons.volume_up,
                      onTap: _showSoundModeDialog,
                    ),

                    const SizedBox(height: 12),

                    _buildSettingRow(
                      'Priority Level',
                      _notificationPriority.toUpperCase(),
                      Icons.priority_high,
                      onTap: _showPriorityDialog,
                    ),

                    const SizedBox(height: 16),

                    _buildToggleRow(
                      'Vibration',
                      'Enable vibration for notifications',
                      Icons.vibration,
                      _vibrationEnabled,
                          (value) => setState(() => _vibrationEnabled = value),
                    ),

                    const SizedBox(height: 8),

                    _buildToggleRow(
                      'Wake Screen',
                      'Turn on screen when notification arrives',
                      Icons.lightbulb,
                      _wakeScreenEnabled,
                          (value) => setState(() => _wakeScreenEnabled = value),
                    ),

                    const SizedBox(height: 24),

                    _buildSectionTitle('Map Behavior'),
                    const SizedBox(height: 16),

                    _buildToggleRow(
                      'Follow Movement',
                      'Camera follows your location and direction',
                      Icons.my_location,
                      _autoFocusEnabled,
                          (value) => setState(() => _autoFocusEnabled = value),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isLoading ? null : _saveSettings,
                icon: _isLoading
                    ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
                    : const Icon(Icons.save),
                label: Text(_isLoading ? 'Saving...' : 'Save Settings'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  textStyle: const TextStyle(fontSize: 18),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
  
	Widget _buildStaticThemeRow() {
	  return Container(
		padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
		decoration: BoxDecoration(
		  color: Theme.of(context).cardColor,
		  borderRadius: BorderRadius.circular(12),
		  border: Border.all(color: Colors.grey.shade300),
		),
		child: Row(
		  children: [
			Container(
			  padding: const EdgeInsets.all(8),
			  decoration: BoxDecoration(
				color: Theme.of(context).primaryColor.withOpacity(0.1),
				borderRadius: BorderRadius.circular(8),
			  ),
			  child: Icon(
				Icons.light_mode,
				color: Theme.of(context).primaryColor,
				size: 24,
			  ),
			),
			const SizedBox(width: 16),
			Expanded(
			  child: Column(
				crossAxisAlignment: CrossAxisAlignment.start,
				children: [
				  const Text(
					'Theme',
					style: TextStyle(
					  fontWeight: FontWeight.w600,
					  fontSize: 16,
					),
				  ),
				  const SizedBox(height: 2),
				  Text(
					'Light mode (fixed)',
					style: TextStyle(
					  color: Theme.of(context).textTheme.bodySmall?.color,
					  fontSize: 13,
					),
				  ),
				],
			  ),
			),
			Switch(
			  value: false, // Uvek false jer je light mode
			  onChanged: null, // Disabled
			  activeColor: Theme.of(context).primaryColor,
			),
		  ],
		),
	  );
	}


  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.bold,
        color: Theme.of(context).primaryColor,
      ),
    );
  }

  Widget _buildSettingRow(String title, String value, IconData icon, {VoidCallback? onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade300),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(icon, color: Theme.of(context).primaryColor),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.w500),
                  ),
                  Text(
                    value,
                    style: TextStyle(color: Theme.of(context).textTheme.bodySmall?.color, fontSize: 12),
                  ),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_ios, size: 16, color: Theme.of(context).textTheme.bodySmall?.color),
          ],
        ),
      ),
    );
  }

  Widget _buildToggleRow(String title, String subtitle, IconData icon, bool value, Function(bool) onChanged) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, color: Theme.of(context).primaryColor),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
                Text(
                  subtitle,
                  style: TextStyle(color: Theme.of(context).textTheme.bodySmall?.color, fontSize: 12),
                ),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeColor: Theme.of(context).primaryColor,
          ),
        ],
      ),
    );
  }

  void _showHelpDialog() {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        child: Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.6,
            maxWidth: MediaQuery.of(context).size.width * 0.9,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Theme.of(context).primaryColor,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(4),
                    topRight: Radius.circular(4),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.help, color: Colors.white),
                    const SizedBox(width: 8),
                    const Text(
                      'Settings Help',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('• Theme: Switch between Light and Dark mode'),
                      SizedBox(height: 12),
                      Text('• Background Activity: Enable reliable notifications'),
                      SizedBox(height: 12),
                      Text('• Geofence Distance: How close you need to be to get notified'),
                      SizedBox(height: 12),
                      Text('• Sound Mode: Choose notification sound type'),
                      SizedBox(height: 12),
                      Text('• Priority: Higher priority shows notifications faster'),
                      SizedBox(height: 12),
                      Text('• Wake Screen: Turn on screen for important alerts'),
                      SizedBox(height: 12),
                      Text('• Follow Movement: Camera tracks your location on map'),
                    ],
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.all(16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Got it!'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showSoundModeDialog() {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        child: Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.7,
            maxWidth: MediaQuery.of(context).size.width * 0.9,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Theme.of(context).primaryColor,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(4),
                    topRight: Radius.circular(4),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.volume_up, color: Colors.white),
                    const SizedBox(width: 8),
                    const Text(
                      'Choose Sound Mode',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildSoundOption('default', 'App Default', Icons.notifications),
                      _buildSoundOption('system_notification', 'System Notification', Icons.phone_android),
                      _buildSoundOption('system_alert', 'System Alert', Icons.warning),
                      _buildSoundOption('system_alarm', 'System Alarm', Icons.alarm),
                      _buildSoundOption('silent', 'Silent', Icons.notifications_off),
                    ],
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.all(16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancel'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showPriorityDialog() {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        child: Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.6,
            maxWidth: MediaQuery.of(context).size.width * 0.9,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Theme.of(context).primaryColor,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(4),
                    topRight: Radius.circular(4),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.priority_high, color: Colors.white),
                    const SizedBox(width: 8),
                    const Text(
                      'Choose Priority Level',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildPriorityOption('low', 'Low Priority'),
                      _buildPriorityOption('normal', 'Normal Priority'),
                      _buildPriorityOption('high', 'High Priority'),
                      _buildPriorityOption('max', 'Maximum Priority'),
                    ],
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.all(16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancel'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSoundOption(String value, String title, IconData icon) {
    return ListTile(
      leading: Icon(icon, color: Theme.of(context).primaryColor),
      title: Text(title),
      subtitle: Text(_getSoundModeDescription(value)),
      trailing: _notificationSoundMode == value
          ? Icon(Icons.check, color: Theme.of(context).primaryColor)
          : null,
      onTap: () {
        setState(() {
          _notificationSoundMode = value;
        });
        Navigator.pop(context);
      },
    );
  }

  Widget _buildPriorityOption(String value, String title) {
    return ListTile(
      leading: Icon(Icons.priority_high, color: Theme.of(context).primaryColor),
      title: Text(title),
      trailing: _notificationPriority == value
          ? Icon(Icons.check, color: Theme.of(context).primaryColor)
          : null,
      onTap: () {
        setState(() {
          _notificationPriority = value;
        });
        Navigator.pop(context);
      },
    );
  }
}