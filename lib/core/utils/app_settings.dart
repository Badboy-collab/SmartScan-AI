import 'package:camera/camera.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Where exported JPEGs are written by default.
enum SaveLocation { gallery, download }

/// Typed wrapper over [SharedPreferences] for the scanner and document-save
/// preferences the app actually honours.
///
/// Every getter falls back to a sane default, so a fresh install behaves exactly
/// as it did before these settings existed.
class AppSettings {
  AppSettings._();

  static const String _kFlashMode = 'scanner.flash_mode';
  static const String _kHdCapture = 'scanner.hd_capture';
  static const String _kSaveLocation = 'save.default_location';
  static const String _kAutoExport = 'save.auto_export_after_scan';
  static const String _kUpdateDismissed = 'update.dismissed_version';

  static Future<SharedPreferences> get _prefs =>
      SharedPreferences.getInstance();

  /// Flash mode the viewfinder starts with. The in-camera selector keeps it
  /// up to date, so re-opening the camera restores the user's choice — including
  /// a torch that was left on.
  static Future<FlashMode> flashMode() async {
    final prefs = await _prefs;
    final String? stored = prefs.getString(_kFlashMode);
    return FlashMode.values.firstWhere(
      (mode) => mode.name == stored,
      orElse: () => FlashMode.off,
    );
  }

  static Future<void> setFlashMode(FlashMode mode) async {
    final prefs = await _prefs;
    await prefs.setString(_kFlashMode, mode.name);
  }

  /// `true` captures at the sensor's highest available size, `false` uses a
  /// faster 720p capture that produces smaller files.
  static Future<bool> hdCapture() async {
    final prefs = await _prefs;
    return prefs.getBool(_kHdCapture) ?? true;
  }

  static Future<void> setHdCapture(bool value) async {
    final prefs = await _prefs;
    await prefs.setBool(_kHdCapture, value);
  }

  /// Default target used when a finished scan is exported automatically.
  static Future<SaveLocation> saveLocation() async {
    final prefs = await _prefs;
    final String? stored = prefs.getString(_kSaveLocation);
    return SaveLocation.values.firstWhere(
      (value) => value.name == stored,
      orElse: () => SaveLocation.gallery,
    );
  }

  static Future<void> setSaveLocation(SaveLocation location) async {
    final prefs = await _prefs;
    await prefs.setString(_kSaveLocation, location.name);
  }

  /// Copies each finished scan straight into Pictures (or Download) as soon as
  /// it has been stored inside the app.
  static Future<bool> autoExportAfterScan() async {
    final prefs = await _prefs;
    return prefs.getBool(_kAutoExport) ?? false;
  }

  static Future<void> setAutoExportAfterScan(bool value) async {
    final prefs = await _prefs;
    await prefs.setBool(_kAutoExport, value);
  }

  /// Release tag the user already said "Later" to, so the startup prompt asks at
  /// most once per published version.
  static Future<String?> dismissedUpdateVersion() async {
    final prefs = await _prefs;
    return prefs.getString(_kUpdateDismissed);
  }

  static Future<void> setDismissedUpdateVersion(String version) async {
    final prefs = await _prefs;
    await prefs.setString(_kUpdateDismissed, version);
  }
}
