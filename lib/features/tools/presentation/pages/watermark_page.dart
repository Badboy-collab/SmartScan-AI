import 'dart:io';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../documents/domain/entities/scanned_document.dart';
import '../../../documents/presentation/providers/document_provider.dart';

class WatermarkPage extends StatefulWidget {
  const WatermarkPage({super.key});

  @override
  State<WatermarkPage> createState() => _WatermarkPageState();
}

class _WatermarkPageState extends State<WatermarkPage> {
  ScannedDocument? _selectedDoc;
  final TextEditingController _watermarkController = TextEditingController(text: 'CONFIDENTIAL');
  Color _watermarkColor = Colors.red;
  double _opacity = 0.25;
  bool _isProcessing = false;

  final List<String> _presets = ['CONFIDENTIAL', 'ORIGINAL', 'DO NOT COPY', 'PAID', 'DRAFT'];

  Future<void> _applyWatermark() async {
    if (_selectedDoc == null || _watermarkController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a document and enter watermark text')),
      );
      return;
    }

    setState(() => _isProcessing = true);

    try {
      final pdf = pw.Document();
      final text = _watermarkController.text.trim();
      final colorHex = _watermarkColor.value.toRadixString(16).padLeft(8, '0');
      final r = int.parse(colorHex.substring(2, 4), radix: 16) / 255.0;
      final g = int.parse(colorHex.substring(4, 6), radix: 16) / 255.0;
      final b = int.parse(colorHex.substring(6, 8), radix: 16) / 255.0;

      for (final path in _selectedDoc!.pagePaths) {
        final file = File(path);
        if (await file.exists()) {
          final bytes = await file.readAsBytes();
          final image = pw.MemoryImage(bytes);

          pdf.addPage(
            pw.Page(
              pageFormat: PdfPageFormat.a4,
              margin: pw.EdgeInsets.zero,
              build: (pw.Context context) {
                return pw.Stack(
                  alignment: pw.Alignment.center,
                  children: [
                    pw.FullPage(
                      ignoreMargins: true,
                      child: pw.Image(image, fit: pw.BoxFit.contain),
                    ),
                    pw.Transform.rotate(
                      angle: -0.785398, // -45 degrees
                      child: pw.Opacity(
                        opacity: _opacity,
                        child: pw.Text(
                          text,
                          style: pw.TextStyle(
                            color: PdfColor(r, g, b),
                            fontSize: 48,
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          );
        }
      }

      final dir = await getApplicationDocumentsDirectory();
      final docId = const Uuid().v4();
      final outPath = '${dir.path}/watermarked_$docId.pdf';
      await File(outPath).writeAsBytes(await pdf.save());

      final now = DateTime.now();
      final newDoc = ScannedDocument(
        id: docId,
        name: '${_selectedDoc!.name} (Watermarked)',
        createdAt: now,
        updatedAt: now,
        pagePaths: _selectedDoc!.pagePaths,
        thumbnailPath: _selectedDoc!.thumbnailPath,
        dirPath: dir.path,
        pdfPath: outPath,
      );

      final provider = getIt<DocumentProvider>();
      await provider.addDocument(newDoc);

      if (mounted) {
        context.pushReplacement('/document_viewer', extra: newDoc);
      }
    } catch (e) {
      debugPrint('[Watermark] Error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
        setState(() => _isProcessing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final docs = getIt<DocumentProvider>().documents;

    return Scaffold(
      backgroundColor: const Color(0xFF1E1E1E),
      appBar: AppBar(
        title: const Text('Add Watermark'),
      ),
      body: docs.isEmpty
          ? const Center(child: Text('No documents available to watermark.'))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // 1. Document Selection Dropdown
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
                      hint: const Text('Choose a document to watermark', style: TextStyle(color: Colors.white38)),
                      dropdownColor: const Color(0xFF2A2A2A),
                      isExpanded: true,
                      items: docs.map((d) {
                        return DropdownMenuItem<ScannedDocument>(
                          value: d,
                          child: Text(d.name, style: const TextStyle(color: Colors.white)),
                        );
                      }).toList(),
                      onChanged: (val) => setState(() => _selectedDoc = val),
                    ),
                  ),
                ),

                const SizedBox(height: 24),

                // 2. Watermark Text Input
                const Text('Watermark Text', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                TextField(
                  controller: _watermarkController,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: const Color(0xFF2A2A2A),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),

                const SizedBox(height: 12),

                // Quick Presets
                Wrap(
                  spacing: 8,
                  children: _presets.map((preset) {
                    return ActionChip(
                      label: Text(preset, style: const TextStyle(fontSize: 12)),
                      backgroundColor: const Color(0xFF2A2A2A),
                      onPressed: () => setState(() => _watermarkController.text = preset),
                    );
                  }).toList(),
                ),

                const SizedBox(height: 24),

                // 3. Color & Opacity
                const Text('Watermark Color & Opacity', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                Row(
                  children: [
                    _buildColorChoice(Colors.red),
                    const SizedBox(width: 12),
                    _buildColorChoice(Colors.blue),
                    const SizedBox(width: 12),
                    _buildColorChoice(Colors.grey),
                    const SizedBox(width: 12),
                    _buildColorChoice(Colors.black),
                  ],
                ),

                const SizedBox(height: 16),
                Slider(
                  value: _opacity,
                  min: 0.1,
                  max: 0.8,
                  activeColor: AppColors.primaryLight,
                  onChanged: (v) => setState(() => _opacity = v),
                ),
                Center(
                  child: Text('Opacity: ${(_opacity * 100).toInt()}%', style: const TextStyle(color: Colors.white54, fontSize: 12)),
                ),

                const SizedBox(height: 32),

                // 4. Apply Button
                ElevatedButton(
                  onPressed: _selectedDoc == null || _isProcessing ? null : _applyWatermark,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryLight,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: _isProcessing
                      ? CircularProgressIndicator(color: Colors.white)
                      : const Text('Apply Watermark & Save PDF', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
    );
  }

  Widget _buildColorChoice(Color color) {
    final isSelected = _watermarkColor == color;
    return GestureDetector(
      onTap: () => setState(() => _watermarkColor = color),
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            color: isSelected ? AppColors.primaryLight : Colors.white24,
            width: isSelected ? 3.0 : 1.0,
          ),
        ),
      ),
    );
  }
}
