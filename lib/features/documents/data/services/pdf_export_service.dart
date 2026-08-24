import 'dart:io';
import 'package:image/image.dart' as img;
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';
import 'package:injectable/injectable.dart';
import '../../domain/entities/scanned_document.dart';
import 'pdf_security_handler.dart';

@lazySingleton
class PdfExportService {
  /// Generates a PDF from the document's pages and returns the temporary file path.
  Future<File> generatePdf(ScannedDocument document) async {
    final pdf = pw.Document();

    for (final pagePath in document.pagePaths) {
      final file = File(pagePath);
      if (await file.exists()) {
        final imageBytes = await file.readAsBytes();
        final image = pw.MemoryImage(imageBytes);

        pdf.addPage(
          pw.Page(
            margin: pw.EdgeInsets.zero,
            build: (pw.Context context) {
              return pw.Center(
                child: pw.Image(image, fit: pw.BoxFit.contain),
              );
            },
          ),
        );
      }
    }

    final tempDir = await getTemporaryDirectory();
    final pdfFile = File('${tempDir.path}/${document.name.replaceAll(' ', '_')}.pdf');
    await pdfFile.writeAsBytes(await pdf.save());
    return pdfFile;
  }

  /// Re-encodes every page as a smaller JPEG and packs them into a PDF.
  Future<File> generateCompressedPdf(
    ScannedDocument document, {
    int jpegQuality = 50,
    int maxDimension = 1400,
  }) async {
    final pdf = pw.Document();

    for (final pagePath in document.pagePaths) {
      final file = File(pagePath);
      if (!await file.exists()) continue;

      final imageBytes = await file.readAsBytes();
      img.Image? decoded = img.decodeImage(imageBytes);
      if (decoded == null) continue;

      // Downscale so the longest edge is at most maxDimension px.
      final longestEdge = decoded.width > decoded.height ? decoded.width : decoded.height;
      if (longestEdge > maxDimension) {
        final scale = maxDimension / longestEdge;
        decoded = img.copyResize(
          decoded,
          width: (decoded.width * scale).round(),
          height: (decoded.height * scale).round(),
        );
      }

      final jpgBytes = img.encodeJpg(decoded, quality: jpegQuality);
      pdf.addPage(
        pw.Page(
          margin: pw.EdgeInsets.zero,
          build: (pw.Context context) {
            return pw.Center(
              child: pw.Image(pw.MemoryImage(jpgBytes), fit: pw.BoxFit.contain),
            );
          },
        ),
      );
    }

    final tempDir = await getTemporaryDirectory();
    final pdfFile = File('${tempDir.path}/${document.name.replaceAll(' ', '_')}_compressed.pdf');
    await pdfFile.writeAsBytes(await pdf.save());
    return pdfFile;
  }

  /// Generates a PDF protected with a password (RC4-40, PDF 1.4).
  Future<File> generateProtectedPdf(ScannedDocument document, String password) async {
    final pdf = pw.Document();

    for (final pagePath in document.pagePaths) {
      final file = File(pagePath);
      if (!await file.exists()) continue;

      final imageBytes = await file.readAsBytes();
      pdf.addPage(
        pw.Page(
          margin: pw.EdgeInsets.zero,
          build: (pw.Context context) {
            return pw.Center(
              child: pw.Image(pw.MemoryImage(imageBytes), fit: pw.BoxFit.contain),
            );
          },
        ),
      );
    }

    // Attach the security handler; the pdf package writes /Encrypt in the trailer.
    pdf.document.encryption = PdfStandardSecurityHandler(
      pdf.document,
      userPassword: password,
      ownerPassword: password,
    );

    final tempDir = await getTemporaryDirectory();
    final pdfFile = File('${tempDir.path}/${document.name.replaceAll(' ', '_')}_protected.pdf');
    await pdfFile.writeAsBytes(await pdf.save());
    return pdfFile;
  }
}
