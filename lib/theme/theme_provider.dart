import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeProvider extends ChangeNotifier {
  static const String _themePrefsKey = 'theme_mode';

  // Default to light theme
  bool _isDarkMode = false;
  bool _isInitialized = false;

  bool get isDarkMode => _isDarkMode;
  bool get isInitialized => _isInitialized;

  ThemeMode get themeMode => _isDarkMode ? ThemeMode.dark : ThemeMode.light;

  ThemeProvider() {
    _loadThemeFromPrefs();
  }

  /// Load theme preference from SharedPreferences
  Future<void> _loadThemeFromPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _isDarkMode = prefs.getBool(_themePrefsKey) ?? false;
      _isInitialized = true;

      debugPrint('🌙 Theme loaded: ${_isDarkMode ? "Dark" : "Light"} mode');
      notifyListeners();
    } catch (e) {
      debugPrint('❌ Error loading theme preference: $e');
      _isInitialized = true;
      notifyListeners();
    }
  }

  /// Toggle between light and dark theme
  Future<void> toggleTheme() async {
    _isDarkMode = !_isDarkMode;
    await _saveThemeToPrefs();

    debugPrint('🌙 Theme toggled to: ${_isDarkMode ? "Dark" : "Light"} mode');
    notifyListeners();
  }

  /// Set specific theme mode
  Future<void> setThemeMode(bool isDark) async {
    if (_isDarkMode != isDark) {
      _isDarkMode = isDark;
      await _saveThemeToPrefs();

      debugPrint('🌙 Theme set to: ${_isDarkMode ? "Dark" : "Light"} mode');
      notifyListeners();
    }
  }

  /// Save theme preference to SharedPreferences
  Future<void> _saveThemeToPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_themePrefsKey, _isDarkMode);
      debugPrint('✅ Theme preference saved: $_isDarkMode');
    } catch (e) {
      debugPrint('❌ Error saving theme preference: $e');
    }
  }

  /// Get theme description for UI
  String get currentThemeDescription {
    return _isDarkMode ? 'Dark Mode' : 'Light Mode';
  }

  /// Get appropriate icon for current theme
  IconData get themeIcon {
    return _isDarkMode ? Icons.light_mode : Icons.dark_mode;
  }

  /// Get next theme description (for toggle button)
  String get nextThemeDescription {
    return _isDarkMode ? 'Switch to Light Mode' : 'Switch to Dark Mode';
  }
}