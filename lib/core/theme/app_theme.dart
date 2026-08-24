import 'package:flutter/material.dart';

class AppColors {
  // Light Theme Colors
  static const Color primaryLight = Color(0xFF1DB99B); // Teal
  static const Color backgroundLight = Colors.white;
  static const Color surfaceLight = Color(0xFFF5F5F5);
  static const Color textLight = Colors.black87;
  static const Color textSecondaryLight = Colors.black54;

  // Dark Theme Colors
  static const Color primaryDark = Color(0xFF1DB99B); // Teal
  static const Color backgroundDark = Color(0xFF121212);
  static const Color surfaceDark = Color(0xFF1E1E1E);
  static const Color textDark = Colors.white;
  static const Color textSecondaryDark = Colors.white70;

  // Shared
  static const Color error = Colors.redAccent;
  static const Color success = Colors.green;
}

class AppSpacing {
  static const double xs = 4.0;
  static const double sm = 8.0;
  static const double md = 16.0;
  static const double lg = 24.0;
  static const double xl = 32.0;
  static const double xxl = 48.0;
}

class AppTheme {
  static ThemeData get lightTheme {
    return ThemeData(
      brightness: Brightness.light,
      primaryColor: AppColors.primaryLight,
      scaffoldBackgroundColor: AppColors.backgroundLight,
      cardColor: AppColors.surfaceLight,
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.backgroundLight,
        elevation: 0,
        iconTheme: IconThemeData(color: AppColors.textLight),
        titleTextStyle: TextStyle(
          color: AppColors.textLight,
          fontSize: 20,
          fontWeight: FontWeight.bold,
        ),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: AppColors.backgroundLight,
        selectedItemColor: AppColors.primaryLight,
        unselectedItemColor: AppColors.textSecondaryLight,
        elevation: 8,
      ),
      textTheme: const TextTheme(
        bodyLarge: TextStyle(color: AppColors.textLight, fontSize: 16),
        bodyMedium: TextStyle(color: AppColors.textSecondaryLight, fontSize: 14),
      ),
      fontFamily: 'Roboto',
      useMaterial3: true,
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primaryLight,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(
            vertical: AppSpacing.md,
            horizontal: AppSpacing.lg,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      ),
    );
  }

  static ThemeData get darkTheme {
    return ThemeData(
      brightness: Brightness.dark,
      primaryColor: AppColors.primaryDark,
      scaffoldBackgroundColor: AppColors.backgroundDark,
      cardColor: AppColors.surfaceDark,
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.backgroundDark,
        elevation: 0,
        iconTheme: IconThemeData(color: AppColors.textDark),
        titleTextStyle: TextStyle(
          color: AppColors.textDark,
          fontSize: 20,
          fontWeight: FontWeight.bold,
        ),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: AppColors.surfaceDark,
        selectedItemColor: AppColors.primaryDark,
        unselectedItemColor: AppColors.textSecondaryDark,
        elevation: 8,
      ),
      textTheme: const TextTheme(
        bodyLarge: TextStyle(color: AppColors.textDark, fontSize: 16),
        bodyMedium: TextStyle(color: AppColors.textSecondaryDark, fontSize: 14),
      ),
      fontFamily: 'Roboto',
      useMaterial3: true,
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primaryDark,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(
            vertical: AppSpacing.md,
            horizontal: AppSpacing.lg,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      ),
    );
  }
}
