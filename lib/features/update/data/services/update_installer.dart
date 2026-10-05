import 'dart:io';

import 'package:flutter/services.dart';
import 'package:open_filex/open_filex.dart';

import '../../../../core/utils/app_launcher.dart';

/// Android half of the in-app updater.
///
/// Installing an APK needs two things that live outside Dart: the
/// `REQUEST_INSTALL_PACKAGES` permission declared in the manifest, and the
/// user's "Install unknown apps" switch turned on for AH Scanner. [canInstall]
/// reports whether that switch is on, [openInstallSettings] takes the user
/// straight to it, and [install] hands the downloaded file to the installer.
class UpdateInstaller {
  UpdateInstaller._();

  /// APK MIME type, so the system shows its installer instead of a generic
  /// "open with" chooser.
  static const String apkMimeType = 'application/vnd.android.package-archive';

  /// `true` when Android will accept an install started by this app.
  static Future<bool> canInstall() async {
    try {
      return await appPlatformChannel.invokeMethod<bool>('canInstallPackages') ??
          false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Opens the "Install unknown apps" screen for AH Scanner.
  static Future<bool> openInstallSettings() async {
    try {
      return await appPlatformChannel
              .invokeMethod<bool>('openInstallSettings') ??
          false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Starts the system installer for [apk].
  ///
  /// Returns `null` when the installer took over, otherwise a readable reason.
  /// A user cancelling the install shows up as success here on purpose: the APK
  /// is valid and the app has nothing left to do.
  static Future<String?> install(File apk) async {
    if (!await apk.exists()) {
      return 'The downloaded file is no longer available. Please download again.';
    }
    try {
      final result = await OpenFilex.open(apk.path, type: apkMimeType);
      if (result.type == ResultType.done) return null;
      return result.message.isEmpty
          ? 'Android could not open the installer.'
          : result.message;
    } catch (e) {
      return 'Android could not open the installer ($e).';
    }
  }
}
