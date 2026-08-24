import 'dart:io';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../documents/domain/entities/scanned_document.dart';
import '../../../documents/presentation/providers/document_provider.dart';

class LongImagePage extends StatefulWidget {
  const LongImagePage({super.key});

  @override
  State<LongImagePage> createState() => _LongImagePageState();
}

class _LongImagePageState extends State<LongImagePage> {
  ScannedDocument? _selectedDoc;
  bool _isProcessing = false;
  String? _generatedImagePath;

  Future<void> _generateLongImage() async {
    if (_selectedDoc == null || _selectedDoc!.pagePaths.isEmpty) return;

    setState(() => _isProcessing = true);
    try {
      final List<img.Image> loadedImages = [];
      int targetWidth = 1080;
      int totalHeight = 0;

      for (final path in _selectedDoc!.pagePaths) {
        final file = File(path);
        if (await file.exists()) {
          final bytes = await file.readAsBytes();
          final decoded = img.decodeImage(bytes);
          if (decoded != null) {
            // Resize proportionally to targetWidth
            final resized = img.copyResize(decoded, width: targetWidth);
            loadedImages.add(resized);
            totalHeight += resized.height;
          }
        }
      }

      if (loadedImages.isEmpty) {
        throw Exception('No images could be loaded');
      }

      // Create composite vertical long canvas
      final longCanvas = img.Image(width: targetWidth, height: totalHeight);
      int currentY = 0;
      for (final image in loadedImages) {
        img.compositeImage(longCanvas, image, dstY: currentY);
        currentY += image.height;
      }

      final dir = await getApplicationDocumentsDirectory();
      final id = const Uuid().v4();
      final outPath = '${dir.path}/long_image_$id.jpg';
      await File(outPath).writeAsBytes(img.encodeJpg(longCanvas, quality: 90));

      setState(() {
        _generatedImagePath = outPath;
        _isProcessing = false;
      });
    } catch (e) {
      debugPrint('[LongImage] Error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e')));
        setState(() => _isProcessing = false);
      }
    }
  }

  void _shareGenerated() {
    if (_generatedImagePath != null) {
      Share.shareXFiles([XFile(_generatedImagePath!)], text: 'Long image exported from AH Scanner');
    }
  }

  @override
  Widget build(BuildContext context) {
    final docs = getIt<DocumentProvider>().documents;

    return Scaffold(
      backgroundColor: const Color(0xFF1E1E1E),
      appBar: AppBar(
        title: const Text('PDF to Long Image'),
        actions: [
          if (_generatedImagePath != null)
            IconButton(
              icon: const Icon(Icons.share),
              onPressed: _shareGenerated,
            ),
        ],
      ),
      body: docs.isEmpty
          ? const Center(child: Text('No documents available.'))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const Text('Select Document', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2A2A2A),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.white24),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<ScannedDocument>(
                      value: _selectedDoc,
                      hint: const Text('Choose a document', style: TextStyle(color: Colors.white38)),
                      dropdownColor: const Color(0xFF2A2A2A),
                      isExpanded: true,
                      items: docs.map((d) {
                        return DropdownMenuItem<ScannedDocument>(
                          value: d,
                          child: Text('${d.name} (${d.pagePaths.length} pages)', style: const TextStyle(color: Colors.white)),
                        );
                      }).toList(),
                      onChanged: (val) {
                        setState(() {
                          _selectedDoc = val;
                          _generatedImagePath = null;
                        });
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                if (_selectedDoc != null && _generatedImagePath == null)
                  ElevatedButton(
                    onPressed: _isProcessing ? null : _generateLongImage,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primaryLight,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    child: _isProcessing
                        ? Center(child: CircularProgressIndicator(color: Colors.white))
                        : const Text('Stitch to Single Long Image', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                  ),
                if (_generatedImagePath != null) ...[
                  const Text('Preview Long Image:', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  Container(
                    height: 400,
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.white24),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: SingleChildScrollView(
                      child: Image.file(File(_generatedImagePath!)),
                    ),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: _shareGenerated,
                    icon: const Icon(Icons.share, color: Colors.white),
                    label: const Text('Share Long Image', style: TextStyle(color: Colors.white)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primaryLight,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ],
              ],
            ),
    );
  }
}
