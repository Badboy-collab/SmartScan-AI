import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';
import '../../features/documents/presentation/providers/document_provider.dart';
import '../../features/documents/domain/entities/scanned_document.dart';
import '../../features/scanner/domain/entities/document_corners.dart';
import '../../features/tools/data/services/pdf_import_service.dart';
import '../../core/di/injection.dart';
import 'document_naming.dart';

class ImportUtils {
  static Future<void> importImages(BuildContext context) async {
    try {
      final picker = ImagePicker();
      final pickedFiles = await picker.pickMultiImage();
      if (pickedFiles.isNotEmpty) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Processing imported images...')));
        
        if (pickedFiles.length == 1) {
          final file = File(pickedFiles.first.path);
          final rawBytes = await file.readAsBytes();
          
          // Normalize EXIF orientation so geometry, aspect ratio & coordinates match 1:1
          final normalizedBytes = await compute(_normalizeImageExif, rawBytes);
          
          if (context.mounted) {
            context.push('/scan_crop', extra: {
              'imageBytes': normalizedBytes,
              'corners': null, // Use OpenCV auto-detection on the normalized imported image
              'rotation': 0,
            });
          }
          return;
        }

        // Multiple images: copy to permanent internal storage
        final provider = getIt<DocumentProvider>();
        final docId = const Uuid().v4();
        final now = DateTime.now();

        final appDir = await getApplicationDocumentsDirectory();
        final docDir = Directory(p.join(appDir.path, 'documents', docId));
        if (!await docDir.exists()) await docDir.create(recursive: true);

        List<String> permanentPagePaths = [];
        String thumbnailPath = '';

        for (int i = 0; i < pickedFiles.length; i++) {
          final pf = pickedFiles[i];
          final rawBytes = await File(pf.path).readAsBytes();
          final normalizedBytes = await compute(_normalizeImageExif, rawBytes);
          
          final pageFile = File(p.join(docDir.path, 'page_${i + 1}.jpg'));
          await pageFile.writeAsBytes(normalizedBytes);
          permanentPagePaths.add(pageFile.path);

          if (i == 0) {
            final thumbFile = File(p.join(docDir.path, 'thumb.jpg'));
            await thumbFile.writeAsBytes(normalizedBytes);
            thumbnailPath = thumbFile.path;
          }
        }
        
        final doc = ScannedDocument(
          id: docId,
          name: defaultDocumentName(now),
          createdAt: now,
          updatedAt: now,
          pagePaths: permanentPagePaths,
          thumbnailPath: thumbnailPath.isNotEmpty ? thumbnailPath : (permanentPagePaths.isNotEmpty ? permanentPagePaths.first : ''),
          dirPath: docDir.path,
        );
        
        await provider.addDocument(doc);
        if (context.mounted) {
          context.push('/document_viewer', extra: doc);
        }
      }
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  /// Imports an outside PDF as an ordinary document: every page is rendered to
  /// an image, so the viewer, OCR, export, watermark, reorder and protect tools
  /// work on it exactly like on a scan.
  static Future<void> importPdf(BuildContext context) async {
    try {
      final picked = await PdfImportService().pickPdf();
      if (picked == null || !context.mounted) return; // Cancelled.

      final messenger = ScaffoldMessenger.of(context);
      messenger.showSnackBar(
        const SnackBar(content: Text('Importing PDF pages…')),
      );

      final appDir = await getApplicationDocumentsDirectory();
      final docId = const Uuid().v4();
      final docDir = Directory(p.join(appDir.path, 'documents', docId));

      final pages = await PdfImportService()
          .renderPdfPages(picked.path, outDir: docDir.path);
      if (pages.isEmpty) {
        throw Exception('That PDF has no pages to import.');
      }

      final now = DateTime.now();
      final doc = ScannedDocument(
        id: docId,
        name: picked.name.isEmpty ? defaultDocumentName(now) : picked.name,
        createdAt: now,
        updatedAt: now,
        pagePaths: pages,
        thumbnailPath: pages.first,
        dirPath: docDir.path,
      );

      await getIt<DocumentProvider>().addDocument(doc);
      messenger.hideCurrentSnackBar();
      if (context.mounted) context.push('/document_viewer', extra: doc);
    } on PlatformException catch (e) {
      if (context.mounted) {
        final message = e.code == 'PASSWORD'
            ? 'This PDF is password protected. Remove the password first, then import it.'
            : 'Could not import the PDF: ${e.message}'
                '${e.code == 'NO_PICKER' ? '\nInstall a file manager to pick files.' : ''}';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }
}

/// Normalizes EXIF orientation and produces clean upright JPEG bytes without orientation tags
Uint8List _normalizeImageExif(Uint8List rawBytes) {
  try {
    final decoded = img.decodeImage(rawBytes);
    if (decoded == null) return rawBytes;
    final oriented = img.bakeOrientation(decoded);
    return Uint8List.fromList(img.encodeJpg(oriented, quality: 95));
  } catch (e) {
    debugPrint('EXIF normalization error: $e');
    return rawBytes;
  }
}
