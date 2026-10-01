import 'package:flutter/services.dart';

/// App identity read straight from the Android build (pubspec.yaml → Gradle →
/// PackageManager), so the About screen can never drift from the real build.
///
/// Uses the existing `ah_scanner/media_store` channel — no extra dependency.
class AppInfo {
  const AppInfo({
    required this.appName,
    required this.versionName,
    required this.versionCode,
  });

  final String appName;
  final String versionName;
  final int versionCode;

  static const MethodChannel _channel = MethodChannel('ah_scanner/media_store');

  static const AppInfo _fallback = AppInfo(
    appName: 'AH Scanner',
    versionName: '—',
    versionCode: 0,
  );

  static AppInfo? _cached;

  static Future<AppInfo> load() async {
    final cached = _cached;
    if (cached != null) return cached;
    try {
      final map = await _channel.invokeMapMethod<String, dynamic>('getAppInfo');
      _cached = AppInfo(
        appName: (map?['appName'] as String?) ?? _fallback.appName,
        versionName: (map?['versionName'] as String?) ?? _fallback.versionName,
        versionCode: (map?['versionCode'] as num?)?.toInt() ?? _fallback.versionCode,
      );
    } on PlatformException {
      _cached = _fallback;
    } on MissingPluginException {
      _cached = _fallback;
    }
    return _cached!;
  }
}
