import 'package:flutter/material.dart';

class AppTheme {
  // Light Theme Colors
  static const Color lightPrimary = Color(0xFF26A69A); // Teal
  static const Color lightPrimaryVariant = Color(0xFF004D40);
  static const Color lightSecondary = Color(0xFF26A69A);
  static const Color lightBackground = Color(0xFFFFFFFF);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightError = Color(0xFFB00020);

  // Dark Theme Colors (IMPROVED - Better contrast)
  static const Color darkPrimary = Color(0xFF4DB6AC); // Lighter teal for better visibility
  static const Color darkPrimaryVariant = Color(0xFF00695C);
  static const Color darkSecondary = Color(0xFF4DB6AC);
  static const Color darkBackground = Color(0xFF121212); // Standard Material dark background
  static const Color darkSurface = Color(0xFF1E1E1E); // Better contrast for cards
  static const Color darkSurfaceVariant = Color(0xFF2C2C2C); // Lighter for inputs
  static const Color darkError = Color(0xFFCF6679);

  // Text Colors (IMPROVED)
  static const Color lightOnPrimary = Colors.white;
  static const Color lightOnSecondary = Colors.white;
  static const Color lightOnBackground = Color(0xFF000000);
  static const Color lightOnSurface = Color(0xFF000000);
  static const Color lightOnError = Colors.white;

  static const Color darkOnPrimary = Color(0xFF000000); // Black text on teal buttons
  static const Color darkOnSecondary = Color(0xFF000000);
  static const Color darkOnBackground = Color(0xFFE1E1E1); // Better contrast text
  static const Color darkOnSurface = Color(0xFFE1E1E1);
  static const Color darkOnError = Colors.white;

  // Additional Custom Colors (IMPROVED)
  static const Color lightCardBackground = Color(0xFFFAFAFA);
  static const Color darkCardBackground = Color(0xFF1E1E1E); // Better card contrast

  static const Color lightInputFill = Color(0xFFF5F5F5);
  static const Color darkInputFill = Color(0xFF2C2C2C); // Better input contrast

  static const Color lightBorder = Color(0xFFE0E0E0);
  static const Color darkBorder = Color(0xFF404040); // More visible borders

  // Light Theme
  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,

      colorScheme: const ColorScheme.light(
        primary: lightPrimary,
        primaryContainer: lightPrimaryVariant,
        secondary: lightSecondary,
        background: lightBackground,
        surface: lightSurface,
        error: lightError,
        onPrimary: lightOnPrimary,
        onSecondary: lightOnSecondary,
        onBackground: lightOnBackground,
        onSurface: lightOnSurface,
        onError: lightOnError,
      ),

      scaffoldBackgroundColor: lightBackground,

      appBarTheme: const AppBarTheme(
        backgroundColor: lightPrimary,
        foregroundColor: lightOnPrimary,
        elevation: 4,
        centerTitle: false,
      ),

      cardTheme: CardThemeData(
        color: lightCardBackground,
        elevation: 4,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: lightInputFill,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: lightBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: lightBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: lightPrimary, width: 2),
        ),
      ),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: lightPrimary,
          foregroundColor: lightOnPrimary,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      ),

      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: lightPrimary,
        foregroundColor: lightOnPrimary,
      ),

      snackBarTheme: const SnackBarThemeData(
        backgroundColor: lightSurface,
        contentTextStyle: TextStyle(color: lightOnSurface),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // Dark Theme (IMPROVED)
  static ThemeData get darkTheme {
    debugPrint('🎨 CREATING DARK THEME WITH NEW COLORS!');
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,

      colorScheme: const ColorScheme.dark(
        primary: darkPrimary,
        primaryContainer: darkPrimaryVariant,
        secondary: darkSecondary,
        background: darkBackground,
        surface: darkSurface,
        surfaceVariant: darkSurfaceVariant,
        error: darkError,
        onPrimary: darkOnPrimary,
        onSecondary: darkOnSecondary,
        onBackground: darkOnBackground,
        onSurface: darkOnSurface,
        onSurfaceVariant: darkOnSurface,
        onError: darkOnError,
      ),

      scaffoldBackgroundColor: darkBackground,

      appBarTheme: const AppBarTheme(
        backgroundColor: darkSurface,
        foregroundColor: darkOnSurface,
        elevation: 4,
        centerTitle: false,
      ),

      cardTheme: CardThemeData(
        color: darkCardBackground,
        elevation: 4,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: darkInputFill,
        labelStyle: const TextStyle(color: darkOnSurface),
        hintStyle: TextStyle(color: darkOnSurface.withOpacity(0.7)),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: darkBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: darkBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: darkPrimary, width: 2),
        ),
      ),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: darkPrimary,
          foregroundColor: darkOnPrimary,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      ),

      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: darkPrimary,
        foregroundColor: darkOnPrimary,
      ),

      snackBarTheme: SnackBarThemeData(
        backgroundColor: darkSurfaceVariant,
        contentTextStyle: const TextStyle(color: darkOnSurface),
        behavior: SnackBarBehavior.floating,
      ),

      // IMPROVED: Better text contrast in dark mode
      textTheme: const TextTheme(
        bodyLarge: TextStyle(color: darkOnSurface),
        bodyMedium: TextStyle(color: darkOnSurface),
        bodySmall: TextStyle(color: Color(0xFFB0B0B0)), // Slightly dimmer for secondary text
        headlineLarge: TextStyle(color: darkOnSurface),
        headlineMedium: TextStyle(color: darkOnSurface),
        headlineSmall: TextStyle(color: darkOnSurface),
        titleLarge: TextStyle(color: darkOnSurface),
        titleMedium: TextStyle(color: darkOnSurface),
        titleSmall: TextStyle(color: darkOnSurface),
        labelLarge: TextStyle(color: darkOnSurface),
        labelMedium: TextStyle(color: darkOnSurface),
        labelSmall: TextStyle(color: Color(0xFFB0B0B0)),
      ),

      iconTheme: const IconThemeData(color: darkOnSurface),
      primaryIconTheme: const IconThemeData(color: darkOnPrimary),

      // IMPROVED: Better button themes for dark mode
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: darkPrimary,
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: darkOnSurface,
          side: BorderSide(color: darkBorder),
        ),
      ),

      // IMPROVED: Switch and other components
      switchTheme: SwitchThemeData(
        thumbColor: MaterialStateProperty.resolveWith((states) {
          if (states.contains(MaterialState.selected)) {
            return darkPrimary;
          }
          return const Color(0xFF6C6C6C);
        }),
        trackColor: MaterialStateProperty.resolveWith((states) {
          if (states.contains(MaterialState.selected)) {
            return darkPrimary.withOpacity(0.3);
          }
          return const Color(0xFF3C3C3C);
        }),
      ),

      // IMPROVED: Dialog theme
      dialogTheme: DialogThemeData(
        backgroundColor: darkSurface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }

  // Custom color extensions for easy access
  static Color getCardColor(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? darkCardBackground
        : lightCardBackground;
  }

  static Color getInputFillColor(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? darkInputFill
        : lightInputFill;
  }

  static Color getBorderColor(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? darkBorder
        : lightBorder;
  }

  // NEW: Helper methods for secondary text colors
  static Color getSecondaryTextColor(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFFB0B0B0)
        : Colors.grey.shade600;
  }

  static Color getTertiaryTextColor(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFF808080)
        : Colors.grey.shade500;
  }
}