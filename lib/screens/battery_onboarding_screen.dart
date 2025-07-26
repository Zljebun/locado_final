// lib/screens/battery_onboarding_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/onboarding_service.dart';

class BatteryOnboardingScreen extends StatefulWidget {
  const BatteryOnboardingScreen({Key? key}) : super(key: key);

  @override
  State<BatteryOnboardingScreen> createState() => _BatteryOnboardingScreenState();
}

class _BatteryOnboardingScreenState extends State<BatteryOnboardingScreen>
    with TickerProviderStateMixin {

  static const MethodChannel _geofenceChannel = MethodChannel('com.example.locado_final/geofence');

  bool _isLoading = false;
  bool _isWhitelisted = false;
  bool _canRequestWhitelist = false;

  late AnimationController _pulseController;
  late AnimationController _slideController;

  @override
  void initState() {
    super.initState();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    _slideController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );

    _checkCurrentStatus();
    _slideController.forward();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _slideController.dispose();
    super.dispose();
  }

  Future<void> _checkCurrentStatus() async {
    try {
      final result = await _geofenceChannel.invokeMethod('checkBatteryOptimization');

      setState(() {
        _isWhitelisted = result['isWhitelisted'] ?? false;
        _canRequestWhitelist = result['canRequestWhitelist'] ?? false;
      });

    } catch (e) {
      print('Error checking battery status: $e');
    }
  }

  Future<void> _requestBatteryOptimization() async {
    if (_isLoading) return;

    setState(() => _isLoading = true);

    try {
      await _geofenceChannel.invokeMethod('requestBatteryOptimizationWhitelist');

      // Wait a bit then check status again
      await Future.delayed(const Duration(seconds: 2));
      await _checkCurrentStatus();

      if (_isWhitelisted) {
        _completeOnboarding();
      }

    } catch (e) {
      _showErrorMessage('Failed to open battery settings: $e');
    }

    setState(() => _isLoading = false);
  }

  Future<void> _skipOnboarding() async {
    await _markOnboardingCompleted();
    _navigateToHome();
  }

  Future<void> _completeOnboarding() async {
    await _markOnboardingCompleted();

    // Show success message
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('✅ Battery optimization configured successfully!'),
        backgroundColor: Colors.green,
        duration: Duration(seconds: 2),
      ),
    );

    await Future.delayed(const Duration(seconds: 2));
    _navigateToHome();
  }

  Future<void> _markOnboardingCompleted() async {
    await OnboardingService.markBatteryOnboardingCompleted();
    await OnboardingService.markFirstLaunchCompleted();
  }

  void _navigateToHome() {
    Navigator.of(context).pushReplacementNamed('/home');
  }

  void _showErrorMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.3),
            end: Offset.zero,
          ).animate(CurvedAnimation(
            parent: _slideController,
            curve: Curves.easeOutCubic,
          )),
          child: FadeTransition(
            opacity: _slideController,
            child: SingleChildScrollView( // ADD THIS
              padding: const EdgeInsets.all(24.0),
              child: ConstrainedBox( // ADD THIS
                constraints: BoxConstraints(
                  minHeight: MediaQuery.of(context).size.height -
                      MediaQuery.of(context).padding.top -
                      MediaQuery.of(context).padding.bottom,
                ),
                child: IntrinsicHeight( // ADD THIS
                  child: Column(
                    children: [
                      // Header
                      const SizedBox(height: 40),

                      // Battery Icon with Pulse Animation
                      AnimatedBuilder(
                        animation: _pulseController,
                        builder: (context, child) {
                          return Transform.scale(
                            scale: 1.0 + (_pulseController.value * 0.1),
                            child: Container(
                              width: 120,
                              height: 120,
                              decoration: BoxDecoration(
                                color: _isWhitelisted ? Colors.green.shade100 : Colors.orange.shade100,
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: (_isWhitelisted ? Colors.green : Colors.orange).withOpacity(0.3),
                                    blurRadius: 20,
                                    spreadRadius: 5,
                                  ),
                                ],
                              ),
                              child: Icon(
                                _isWhitelisted ? Icons.battery_charging_full : Icons.battery_alert,
                                size: 60,
                                color: _isWhitelisted ? Colors.green : Colors.orange,
                              ),
                            ),
                          );
                        },
                      ),

                      const SizedBox(height: 32),

                      // Title
                      Text(
                        'Battery Optimization',
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey.shade800,
                        ),
                        textAlign: TextAlign.center,
                      ),

                      const SizedBox(height: 16),

                      // Subtitle
                      Text(
                        'Ensure reliable location notifications',
                        style: TextStyle(
                          fontSize: 16,
                          color: Colors.grey.shade600,
                        ),
                        textAlign: TextAlign.center,
                      ),

                      const SizedBox(height: 40),

                      // Status Card
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: _isWhitelisted ? Colors.green.shade50 : Colors.orange.shade50,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: _isWhitelisted ? Colors.green.shade200 : Colors.orange.shade200,
                            width: 1,
                          ),
                        ),
                        child: Column(
                          children: [
                            Icon(
                              _isWhitelisted ? Icons.check_circle : Icons.info_outline,
                              color: _isWhitelisted ? Colors.green : Colors.orange,
                              size: 32,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              _isWhitelisted ? 'Already Optimized!' : 'Optimization Recommended',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: _isWhitelisted ? Colors.green.shade800 : Colors.orange.shade800,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _isWhitelisted
                                  ? 'Your location notifications will work reliably in the background.'
                                  : 'Allow Locado to run in the background for reliable notifications.',
                              style: TextStyle(
                                fontSize: 14,
                                color: _isWhitelisted ? Colors.green.shade700 : Colors.orange.shade700,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 32),

                      // Benefits List
                      _buildBenefitsList(),

                      const Spacer(),

                      // Action Buttons
                      _buildActionButtons(),

                      const SizedBox(height: 16),

                      // Skip Button
                      TextButton(
                        onPressed: _isLoading ? null : _skipOnboarding,
                        child: Text(
                          'Skip for now',
                          style: TextStyle(
                            color: Colors.grey.shade600,
                            fontSize: 16,
                          ),
                        ),
                      ),

                      const SizedBox(height: 20),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBenefitsList() {
    final benefits = [
      {'icon': Icons.notifications_active, 'text': 'Never miss location-based reminders'},
      {'icon': Icons.location_on, 'text': 'Accurate geofencing even when app is closed'},
      {'icon': Icons.battery_saver, 'text': 'Minimal impact on battery life'},
    ];

    return Column(
      children: benefits.map((benefit) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 8.0),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.teal.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  benefit['icon'] as IconData,
                  color: Colors.teal,
                  size: 20,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  benefit['text'] as String,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey.shade700,
                  ),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildActionButtons() {
    if (_isWhitelisted) {
      return SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: _isLoading ? null : _completeOnboarding,
          icon: const Icon(Icons.check),
          label: const Text('Continue'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.green,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 16),
            textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      );
    }

    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: (_isLoading || !_canRequestWhitelist) ? null : _requestBatteryOptimization,
        icon: _isLoading
            ? const SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
        )
            : const Icon(Icons.settings),
        label: Text(_isLoading ? 'Opening Settings...' : 'Optimize Now'),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.orange,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 16),
          textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }
}