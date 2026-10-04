import 'package:flutter/services.dart';

/// A PDF chosen by the user, copied into the app cache.
class PickedPdf {
  /// Path of the cached copy (readable by `dart:io`).
  final String path;

  /// The file's own name with the `.pdf` suffix removed — this becomes the
  /// document name, so an imported file keeps the name the user gave it.
  final String name;

  const PickedPdf({required this.path, required this.name});
}

/// Brings an outside PDF into the app as ordinary page images.
///
/// Rendering is done by the platform's own PDF engine
/// (`android.graphics.pdf.PdfRenderer`) through the existing `media_store`
/// method channel: no extra package, no bundled native library, and the same
/// renderer Android itself uses for previews.
class PdfImportService {
  static const MethodChannel _channel = MethodChannel('ah_scanner/media_store');

  /// Opens the system document picker filtered to PDFs.
  ///
  /// Returns `null` when the user backs out (not an error). Throws a
  /// [PlatformException] when the picker cannot start or the file cannot be read.
  Future<PickedPdf?> pickPdf() async {
    final data = await _channel.invokeMapMethod<String, dynamic>('pickPdf');
    if (data == null) return null;

    final path = data['path'] as String?;
    if (path == null) return null;

    final raw = (data['name'] as String?) ?? '';
    final name = raw.toLowerCase().endsWith('.pdf')
        ? raw.substring(0, raw.length - 4)
        : raw;

    return PickedPdf(path: path, name: name.trim());
  }

  /// Rasterises [pdfPath] into one JPEG per page inside [outDir] and returns
  /// their paths in page order.
  ///
  /// [maxWidth] caps the long edge so a 300dpi page cannot exhaust memory.
  /// Throws a [PlatformException] with code `PASSWORD` for encrypted PDFs.
  Future<List<String>> renderPdfPages(
    String pdfPath, {
    required String outDir,
    int maxWidth = 1600,
  }) async {
    final pages = await _channel.invokeListMethod<String>('renderPdfPages', {
      'path': pdfPath,
      'outDir': outDir,
      'maxWidth': maxWidth,
    });
    return pages ?? const [];
  }
}
