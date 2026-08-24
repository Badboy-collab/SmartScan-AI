import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AppThemeMode {
  light,
  dark,
  navyBlue,
  system,
}

class ThemeProvider extends ChangeNotifier {
  static const String _prefKey = 'app_theme_mode';
  AppThemeMode _currentTheme = AppThemeMode.light;

  AppThemeMode get currentTheme => _currentTheme;

  ThemeProvider() {
    _loadTheme();
  }

  Future<void> _loadTheme() async {
    final prefs = await SharedPreferences.getInstance();
    final themeIndex = prefs.getInt(_prefKey) ?? 0;
    _currentTheme = AppThemeMode.values[themeIndex.clamp(0, AppThemeMode.values.length - 1)];
    notifyListeners();
  }

  Future<void> setTheme(AppThemeMode theme) async {
    _currentTheme = theme;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_prefKey, theme.index);
    notifyListeners();
  }

  ThemeData get themeData {
    switch (_currentTheme) {
      case AppThemeMode.light:
        return _lightTheme;
      case AppThemeMode.dark:
        return _darkTheme;
      case AppThemeMode.navyBlue:
        return _navyBlueTheme;
      case AppThemeMode.system:
        return _lightTheme;
    }
  }

  static final ThemeData _lightTheme = ThemeData(
    brightness: Brightness.light,
    primaryColor: Colors.teal,
    scaffoldBackgroundColor: const Color(0xFFF6F8FA),
    cardColor: Colors.white,
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.white,
      foregroundColor: Colors.black87,
      elevation: 0.5,
      iconTheme: IconThemeData(color: Colors.black87),
      titleTextStyle: TextStyle(color: Colors.black87, fontSize: 18, fontWeight: FontWeight.bold),
    ),
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: Colors.white,
      selectedItemColor: Colors.teal,
      unselectedItemColor: Colors.black54,
    ),
    textTheme: const TextTheme(
      bodyLarge: TextStyle(color: Colors.black87),
      bodyMedium: TextStyle(color: Colors.black87),
      titleMedium: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold),
    ),
    iconTheme: const IconThemeData(color: Colors.black87),
    colorScheme: const ColorScheme.light(
      primary: Colors.teal,
      surface: Colors.white,
      onSurface: Colors.black87,
    ),
  );

  static final ThemeData _darkTheme = ThemeData(
    brightness: Brightness.dark,
    primaryColor: Colors.tealAccent,
    scaffoldBackgroundColor: const Color(0xFF121212),
    cardColor: const Color(0xFF1E1E1E),
    appBarTheme: const AppBarTheme(
      backgroundColor: Color(0xFF1E1E1E),
      foregroundColor: Colors.white,
      elevation: 0.5,
      iconTheme: IconThemeData(color: Colors.white),
      titleTextStyle: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
    ),
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: Color(0xFF1E1E1E),
      selectedItemColor: Colors.tealAccent,
      unselectedItemColor: Colors.white54,
    ),
    textTheme: const TextTheme(
      bodyLarge: TextStyle(color: Colors.white),
      bodyMedium: TextStyle(color: Colors.white70),
      titleMedium: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
    ),
    iconTheme: const IconThemeData(color: Colors.white),
    colorScheme: const ColorScheme.dark(
      primary: Colors.tealAccent,
      surface: Color(0xFF1E1E1E),
      onSurface: Colors.white,
    ),
  );

  static final ThemeData _navyBlueTheme = ThemeData(
    brightness: Brightness.dark,
    primaryColor: const Color(0xFF00D4FF),
    scaffoldBackgroundColor: const Color(0xFF0A192F),
    cardColor: const Color(0xFF112240),
    appBarTheme: const AppBarTheme(
      backgroundColor: Color(0xFF112240),
      foregroundColor: Color(0xFFCCD6F6),
      elevation: 0.5,
      iconTheme: IconThemeData(color: Color(0xFF00D4FF)),
      titleTextStyle: TextStyle(color: Color(0xFFCCD6F6), fontSize: 18, fontWeight: FontWeight.bold),
    ),
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: Color(0xFF112240),
      selectedItemColor: Color(0xFF00D4FF),
      unselectedItemColor: Color(0xFF8892B0),
    ),
    textTheme: const TextTheme(
      bodyLarge: TextStyle(color: Color(0xFFCCD6F6)),
      bodyMedium: TextStyle(color: Color(0xFF8892B0)),
      titleMedium: TextStyle(color: Color(0xFFCCD6F6), fontWeight: FontWeight.bold),
    ),
    iconTheme: const IconThemeData(color: Color(0xFF00D4FF)),
    colorScheme: const ColorScheme.dark(
      primary: Color(0xFF00D4FF),
      surface: Color(0xFF112240),
      onSurface: Color(0xFFCCD6F6),
    ),
  );
}
