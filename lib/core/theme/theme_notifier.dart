import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AppThemeMode {
  light,
  dark,
  navyBlue,
  system,
}

class ThemeNotifier extends ChangeNotifier {
  static const String _prefKey = 'app_theme_mode_v2';
  AppThemeMode _mode = AppThemeMode.light;

  AppThemeMode get mode => _mode;

  ThemeNotifier();

  Future<void> loadTheme() async {
    final prefs = await SharedPreferences.getInstance();
    final String? themeStr = prefs.getString(_prefKey);
    
    if (themeStr == 'dark') {
      _mode = AppThemeMode.dark;
    } else if (themeStr == 'navyBlue') {
      _mode = AppThemeMode.navyBlue;
    } else if (themeStr == 'system') {
      _mode = AppThemeMode.system;
    } else {
      _mode = AppThemeMode.light; // Light theme default
    }
    notifyListeners();
  }

  Future<void> setAppTheme(AppThemeMode themeMode) async {
    _mode = themeMode;
    notifyListeners();
    
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKey, themeMode.name);
  }

  ThemeData get currentThemeData {
    switch (_mode) {
      case AppThemeMode.light:
        return lightTheme;
      case AppThemeMode.dark:
        return darkTheme;
      case AppThemeMode.navyBlue:
        return navyBlueTheme;
      case AppThemeMode.system:
        final brightness = WidgetsBinding.instance.platformDispatcher.platformBrightness;
        return brightness == Brightness.dark ? darkTheme : lightTheme;
    }
  }

  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      primaryColor: const Color(0xFF00A884),
      scaffoldBackgroundColor: const Color(0xFFF4F6F8),
      cardColor: Colors.white,
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.white,
        foregroundColor: Color(0xFF1E293B),
        elevation: 0,
        iconTheme: IconThemeData(color: Color(0xFF1E293B)),
        titleTextStyle: TextStyle(color: Color(0xFF1E293B), fontSize: 18, fontWeight: FontWeight.bold),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: Colors.white,
        selectedItemColor: Color(0xFF00A884),
        unselectedItemColor: Color(0xFF64748B),
        elevation: 4,
      ),
      textTheme: const TextTheme(
        bodyLarge: TextStyle(color: Color(0xFF0F172A)),
        bodyMedium: TextStyle(color: Color(0xFF334155)),
        titleMedium: TextStyle(color: Color(0xFF0F172A), fontWeight: FontWeight.bold),
      ),
      iconTheme: const IconThemeData(color: Color(0xFF334155)),
      colorScheme: const ColorScheme.light(
        primary: Color(0xFF00A884),
        surface: Colors.white,
        onSurface: Color(0xFF0F172A),
      ),
    );
  }

  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      primaryColor: const Color(0xFF00D4AA),
      scaffoldBackgroundColor: const Color(0xFF121212),
      cardColor: const Color(0xFF1E1E1E),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFF1E1E1E),
        foregroundColor: Colors.white,
        elevation: 0,
        iconTheme: IconThemeData(color: Colors.white),
        titleTextStyle: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: Color(0xFF1E1E1E),
        selectedItemColor: Color(0xFF00D4AA),
        unselectedItemColor: Colors.white60,
      ),
      textTheme: const TextTheme(
        bodyLarge: TextStyle(color: Colors.white),
        bodyMedium: TextStyle(color: Colors.white70),
        titleMedium: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
      ),
      iconTheme: const IconThemeData(color: Colors.white),
      colorScheme: const ColorScheme.dark(
        primary: Color(0xFF00D4AA),
        surface: Color(0xFF1E1E1E),
        onSurface: Colors.white,
      ),
    );
  }

  static ThemeData get navyBlueTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      primaryColor: const Color(0xFF00D4FF),
      scaffoldBackgroundColor: const Color(0xFF0A192F),
      cardColor: const Color(0xFF112240),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFF112240),
        foregroundColor: Color(0xFFCCD6F6),
        elevation: 0,
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
}
