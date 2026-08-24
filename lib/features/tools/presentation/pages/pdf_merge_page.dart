import 'dart:io';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import 'package:image/image.dart' as img;

import '../../../../core/di/injection.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../documents/domain/entities/scanned_document.dart';
import '../../../documents/presentation/providers/document_provider.dart';

class PdfMergePage extends StatefulWidget {
  const PdfMergePage({super.key});

  @override
  State<PdfMergePage> createState() => _PdfMergePageState();
}

class _PdfMergePageState extends State<PdfMergePage> {
  final List<ScannedDocument> _selectedDocs = [];
  bool _isMerging = false;

  void _toggleSelect(ScannedDocument doc) {
    setState(() {
      if (_selectedDocs.contains(doc)) {
        _selectedDocs.remove(doc);
      } else {
        _selectedDocs.add(doc);
      }
    });
  }

  Future<void> _mergeSelectedDocs() async {
    if (_selectedDocs.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select at least 2 documents to merge')),
      );
      return;
    }

    setState(() => _isMerging = true);

    try {
      final pdf = pw.Document();
      final List<String> allPagePaths = [];

      for (final doc in _selectedDocs) {
        for (final path in doc.pagePaths) {
          final file = File(path);
          if (await file.exists()) {
            final bytes = await file.readAsBytes();
            final image = pw.MemoryImage(bytes);
            allPagePaths.add(path);

            pdf.addPage(
              pw.Page(
                pageFormat: PdfPageFormat.a4,
                margin: pw.EdgeInsets.zero,
                build: (pw.Context context) {
                  return pw.FullPage(
                    ignoreMargins: true,
                    child: pw.Image(image, fit: pw.BoxFit.contain),
                  );
                },
              ),
            );
          }
        }
      }

      final dir = await getApplicationDocumentsDirectory();
      final docId = const Uuid().v4();
      final mergedPdfPath = '${dir.path}/merged_$docId.pdf';
      final pdfFile = File(mergedPdfPath);
      await pdfFile.writeAsBytes(await pdf.save());

      final now = DateTime.now();
      final mergedDoc = ScannedDocument(
        id: docId,
        name: 'Merged Doc ${now.month}-${now.day} (${allPagePaths.length} pages)',
        createdAt: now,
        updatedAt: now,
        pagePaths: allPagePaths,
        thumbnailPath: allPagePaths.isNotEmpty ? allPagePaths.first : '',
        dirPath: dir.path,
        pdfPath: mergedPdfPath,
      );

      final provider = getIt<DocumentProvider>();
      await provider.addDocument(mergedDoc);

      if (mounted) {
        context.pushReplacement('/document_viewer', extra: mergedDoc);
      }
    } catch (e) {
      debugPrint('[PdfMerge] Error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Merge failed: $e')));
        setState(() => _isMerging = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final docs = getIt<DocumentProvider>().documents;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Merge PDFs'),
        actions: [
          if (_selectedDocs.length >= 2)
            TextButton(
              onPressed: _isMerging ? null : _mergeSelectedDocs,
              child: const Text('Merge', style: TextStyle(color: Colors.tealAccent, fontWeight: FontWeight.bold, fontSize: 16)),
            ),
        ],
      ),
      body: docs.isEmpty
          ? const Center(child: Text('No documents available to merge.'))
          : Stack(
              children: [
                ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    final doc = docs[index];
                    final isSelected = _selectedDocs.contains(doc);

                    return Card(
                      color: isSelected ? Colors.teal.withOpacity(0.15) : const Color(0xFF2A2A2A),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                        side: BorderSide(
                          color: isSelected ? AppColors.primaryLight : Colors.transparent,
                          width: 1.5,
                        ),
                      ),
                      margin: const EdgeInsets.only(bottom: 12),
                      child: ListTile(
                        leading: Container(
                          width: 48,
                          height: 60,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(4),
                            color: Colors.black26,
                          ),
                          child: doc.thumbnailPath.isNotEmpty && File(doc.thumbnailPath).existsSync()
                              ? Image.file(File(doc.thumbnailPath), fit: BoxFit.cover)
                              : const Icon(Icons.picture_as_pdf, color: Colors.white54),
                        ),
                        title: Text(doc.name, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                        subtitle: Text('${doc.pagePaths.length} pages', style: const TextStyle(color: Colors.white54)),
                        trailing: Checkbox(
                          value: isSelected,
                          activeColor: AppColors.primaryLight,
                          onChanged: (_) => _toggleSelect(doc),
                        ),
                        onTap: () => _toggleSelect(doc),
                      ),
                    );
                  },
                ),
                if (_isMerging)
                  Container(
                    color: Colors.black54,
                    child: Center(
                      child: CircularProgressIndicator(color: AppColors.primaryLight),
                    ),
                  ),
              ],
            ),
      bottomNavigationBar: SafeArea(
        child: Container(
          padding: const EdgeInsets.all(16),
          color: const Color(0xFF1E1E1E),
          child: ElevatedButton(
            onPressed: _selectedDocs.length < 2 || _isMerging ? null : _mergeSelectedDocs,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryLight,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: Text(
              _selectedDocs.length < 2
                  ? 'Select at least 2 documents (${_selectedDocs.length} selected)'
                  : 'Merge ${_selectedDocs.length} Documents',
              style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
        ),
      ),
    );
  }
}
