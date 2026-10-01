import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

/// A file that has just been written to a public, Gallery-visible location.
class SavedImage {
  /// Absolute path (Android 9-) or `Pictures/AH Scanner/<name>` on Android 10+.
  final String path;

  /// The name the platform actually stored, which can differ from the requested
  /// one when the platform de-duplicated it.
  final String fileName;

  const SavedImage({required this.path, required this.fileName});
}

/// Writes images somewhere the phone's Gallery and file manager can actually see.
///
/// On Android 10+ this goes through MediaStore into `Pictures/AH Scanner`
/// (or `Download/AH Scanner`). That route needs no storage permission and
/// de-duplicates names by itself, so the app never has to rename a file to dodge
/// a "file already exists" error — the requested name is always passed through
/// unchanged.
///
/// The previous implementation copied into `Android/data/<package>/files`, which
/// Android 11+ hides from both the Gallery and every file manager, so the saved
/// pictures were never findable.
class GallerySaver {
  GallerySaver._();

  static const MethodChannel _channel = MethodChannel('ah_scanner/media_store');
  static const String defaultFolder = 'AH Scanner';

  static int? _sdkInt;

  /// The Android API level, or null on other platforms / when unavailable.
  static Future<int?> androidSdkInt() async {
    if (!Platform.isAndroid) return null;
    if (_sdkInt != null) return _sdkInt;
    try {
      _sdkInt = await _channel.invokeMethod<int>('getSdkInt');
    } catch (e) {
      debugPrint('GallerySaver: could not read the Android API level: $e');
    }
    return _sdkInt;
  }

  /// Human-readable folder shown in the success message.
  static String locationLabel({bool toDownloads = false}) {
    if (Platform.isAndroid) {
      return toDownloads ? 'Download/$defaultFolder' : 'Pictures/$defaultFolder';
    }
    return defaultFolder;
  }

  /// Saves [bytes] as [fileName] inside [folder] and returns where it landed.
  ///
  /// [fileName] is passed to the platform verbatim. If a file with that name
  /// already exists the platform appends a numbered suffix instead of failing.
  static Future<SavedImage> saveJpeg({
    required Uint8List bytes,
    required String fileName,
    String folder = defaultFolder,
    bool toDownloads = false,
  }) async {
    if (Platform.isAndroid) {
      return _saveOnAndroid(
        bytes: bytes,
        fileName: fileName,
        folder: folder,
        toDownloads: toDownloads,
      );
    }
    return _saveOnDesktop(
      bytes: bytes,
      fileName: fileName,
      folder: folder,
      toDownloads: toDownloads,
    );
  }

  static Future<SavedImage> _saveOnAndroid({
    required Uint8List bytes,
    required String fileName,
    required String folder,
    required bool toDownloads,
  }) async {
    Future<SavedImage> attempt() async {
      final path = await _channel.invokeMethod<String>('saveImage', {
        'bytes': bytes,
        'fileName': fileName,
        'folder': folder,
        'toDownloads': toDownloads,
      });
      if (path == null || path.isEmpty) {
        throw StateError('The platform did not report where the file was saved');
      }
      return SavedImage(path: path, fileName: p.basename(path));
    }

    try {
      return await attempt();
    } on PlatformException catch (e) {
      // Android 9 and older need WRITE_EXTERNAL_STORAGE; retry once it is granted.
      if (e.code != 'NEEDS_PERMISSION') rethrow;
      final status = await Permission.storage.request();
      if (!status.isGranted) {
        throw const FileSystemException(
          'Storage permission is required to save on Android 9 and older',
        );
      }
      return attempt();
    }
  }

  static Future<SavedImage> _saveOnDesktop({
    required Uint8List bytes,
    required String fileName,
    required String folder,
    required bool toDownloads,
  }) async {
    final Directory baseDir =
        await getDownloadsDirectory() ?? await getApplicationDocumentsDirectory();
    final Directory dir = Directory(p.join(baseDir.path, folder));
    if (!await dir.exists()) await dir.create(recursive: true);

    final String stem = p.basenameWithoutExtension(fileName);
    final String extension = p.extension(fileName);
    File target = File(p.join(dir.path, fileName));
    int index = 1;
    while (await target.exists()) {
      target = File(p.join(dir.path, '$stem ($index)$extension'));
      index++;
    }

    await target.writeAsBytes(bytes, flush: true);
    return SavedImage(path: target.path, fileName: p.basename(target.path));
  }
}
