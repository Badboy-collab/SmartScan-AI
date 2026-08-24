import 'dart:io';
import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'package:injectable/injectable.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path/path.dart' as p;

@lazySingleton
class ExportService {
  Future<String> getAppDocumentsDir() async {
    final dir = await getApplicationDocumentsDirectory();
    return dir.path;
  }

  Future<String> saveDocumentPage(String documentId, Uint8List imageBytes, int pageIndex) async {
    final rootDir = await getAppDocumentsDir();
    final docDir = Directory(p.join(rootDir, 'documents', documentId));
    if (!await docDir.exists()) await docDir.create(recursive: true);

    final File file = File(p.join(docDir.path, 'page_$pageIndex.jpg'));
    await file.writeAsBytes(imageBytes);
    return file.path;
  }

  Future<String> saveRawPage(String documentId, Uint8List rawBytes, int pageIndex) async {
    final rootDir = await getAppDocumentsDir();
    final docDir = Directory(p.join(rootDir, 'documents', documentId));
    if (!await docDir.exists()) await docDir.create(recursive: true);

    final File file = File(p.join(docDir.path, 'raw_page_$pageIndex.jpg'));
    await file.writeAsBytes(rawBytes);
    return file.path;
  }

  Future<String> createThumbnail(String documentId, Uint8List imageBytes) async {
    final rootDir = await getAppDocumentsDir();
    final docDir = Directory(p.join(rootDir, 'documents', documentId));
    if (!await docDir.exists()) await docDir.create(recursive: true);

    img.Image? decoded = img.decodeImage(imageBytes);
    if (decoded != null) {
      img.Image thumb = img.copyResize(decoded, width: 200);
      final File thumbFile = File(p.join(docDir.path, 'thumb.jpg'));
      await thumbFile.writeAsBytes(img.encodeJpg(thumb, quality: 70));
      return thumbFile.path;
    }
    return ''; // fallback
  }

  Future<void> deleteDocumentDirectory(String documentId) async {
    final rootDir = await getAppDocumentsDir();
    final docDir = Directory(p.join(rootDir, 'documents', documentId));
    if (await docDir.exists()) {
      await docDir.delete(recursive: true);
    }
  }

  Future<String> saveAsPdf(String documentId, List<File> pageFiles) async {
    final pdf = pw.Document();

    for (var file in pageFiles) {
      final image = pw.MemoryImage(await file.readAsBytes());
      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          build: (pw.Context context) {
            return pw.Center(child: pw.Image(image, fit: pw.BoxFit.contain));
          },
        ),
      );
    }

    final rootDir = await getAppDocumentsDir();
    final docDir = Directory(p.join(rootDir, 'documents', documentId));
    final File pdfFile = File(p.join(docDir.path, 'document_$documentId.pdf'));
    await pdfFile.writeAsBytes(await pdf.save());
    return pdfFile.path;
  }
}
