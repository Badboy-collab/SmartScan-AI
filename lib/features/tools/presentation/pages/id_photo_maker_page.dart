import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/theme/app_theme.dart';

class IDPhotoMakerPage extends StatefulWidget {
  const IDPhotoMakerPage({super.key});

  @override
  State<IDPhotoMakerPage> createState() => _IDPhotoMakerPageState();
}

class _IDPhotoMakerPageState extends State<IDPhotoMakerPage> {
  Uint8List? _sourceImageBytes;
  Uint8List? _resultSheetBytes;
  String? _resultFilePath;
  bool _isProcessing = false;
  String _selectedSize = '35x45mm (Passport)';
  Color _bgColor = Colors.white;

  Future<void> _pickImage(ImageSource source) async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: source);
    if (picked != null) {
      final bytes = await picked.readAsBytes();
      setState(() {
        _sourceImageBytes = bytes;
        _resultSheetBytes = null;
        _resultFilePath = null;
      });
      await _generatePrintableSheet();
    }
  }

  Future<void> _generatePrintableSheet() async {
    if (_sourceImageBytes == null) return;

    setState(() => _isProcessing = true);
    try {
      final decoded = img.decodeImage(_sourceImageBytes!);
      if (decoded == null) return;

      // Crop to portrait ratio 35:45 (7:9)
      final cropW = decoded.width;
      final cropH = (cropW * (45.0 / 35.0)).toInt();
      final actualH = cropH > decoded.height ? decoded.height : cropH;
      final actualW = (actualH * (35.0 / 45.0)).toInt();

      final startX = (decoded.width - actualW) ~/ 2;
      final startY = (decoded.height - actualH) ~/ 4; // Focus on face

      final singlePhoto = img.copyCrop(
        decoded,
        x: startX.clamp(0, decoded.width - 1),
        y: startY.clamp(0, decoded.height - 1),
        width: actualW.clamp(1, decoded.width - startX),
        height: actualH.clamp(1, decoded.height - startY),
      );

      // Resize to standard resolution for 1 photo (413 x 531 px at 300 DPI)
      final photoResized = img.copyResize(singlePhoto, width: 413, height: 531);

      // Create 4R (4x6 inch) sheet (1200 x 1800 px at 300 DPI) -> fits 6-8 photos!
      const sheetW = 1200;
      const sheetH = 1800;
      final sheet = img.Image(width: sheetW, height: sheetH);
      img.fill(sheet, color: img.ColorRgb8(255, 255, 255));

      // Lay out 2 columns x 3 rows = 6 Passport Photos with cut guidelines
      const startLeft = 130;
      const startTop = 90;
      const gapX = 110;
      const gapY = 40;

      for (int row = 0; row < 3; row++) {
        for (int col = 0; col < 2; col++) {
          final posX = startLeft + col * (413 + gapX);
          final posY = startTop + row * (531 + gapY);

          // Draw thin cut border
          img.drawRect(
            sheet,
            x1: posX - 2,
            y1: posY - 2,
            x2: posX + 413 + 2,
            y2: posY + 531 + 2,
            color: img.ColorRgb8(200, 200, 200),
          );

          img.compositeImage(sheet, photoResized, dstX: posX, dstY: posY);
        }
      }

      final dir = await getApplicationDocumentsDirectory();
      final id = const Uuid().v4();
      final outPath = '${dir.path}/passport_sheet_$id.jpg';
      final jpgBytes = Uint8List.fromList(img.encodeJpg(sheet, quality: 95));
      await File(outPath).writeAsBytes(jpgBytes);

      setState(() {
        _resultSheetBytes = jpgBytes;
        _resultFilePath = outPath;
        _isProcessing = false;
      });
    } catch (e) {
      debugPrint('[IDPhoto] Error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e')));
        setState(() => _isProcessing = false);
      }
    }
  }

  void _shareSheet() {
    if (_resultFilePath != null) {
      Share.shareXFiles([XFile(_resultFilePath!)], text: 'Passport Photos 4R Sheet ready to print');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1E1E1E),
      appBar: AppBar(
        title: const Text('ID Photo Maker'),
        actions: [
          if (_resultFilePath != null)
            IconButton(
              icon: const Icon(Icons.share),
              onPressed: _shareSheet,
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_sourceImageBytes == null) ...[
            Container(
              height: 240,
              decoration: BoxDecoration(
                color: const Color(0xFF2A2A2A),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white24),
              ),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.account_box_outlined, size: 64, color: Colors.white54),
                    const SizedBox(height: 16),
                    const Text('Take or Pick a Portrait Photo', style: TextStyle(color: Colors.white70, fontSize: 16, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        ElevatedButton.icon(
                          onPressed: () => _pickImage(ImageSource.camera),
                          icon: const Icon(Icons.camera_alt),
                          label: const Text('Camera'),
                          style: ElevatedButton.styleFrom(backgroundColor: AppColors.primaryLight),
                        ),
                        const SizedBox(width: 16),
                        OutlinedButton.icon(
                          onPressed: () => _pickImage(ImageSource.gallery),
                          icon: const Icon(Icons.photo_library),
                          label: const Text('Gallery'),
                          style: OutlinedButton.styleFrom(foregroundColor: Colors.white),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ] else ...[
            if (_isProcessing)
              const Center(child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator(color: AppColors.primaryLight)))
            else if (_resultSheetBytes != null) ...[
              const Text('4R Printable Sheet (6 Passport Photos):', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              Container(
                height: 380,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.white24),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Image.memory(_resultSheetBytes!, fit: BoxFit.contain),
              ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: _shareSheet,
                icon: const Icon(Icons.print),
                label: const Text('Print / Share 4R Sheet (6 Photos)'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryLight,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () => _pickImage(ImageSource.gallery),
                icon: const Icon(Icons.refresh),
                label: const Text('Choose Another Photo'),
                style: OutlinedButton.styleFrom(foregroundColor: Colors.white),
              ),
            ],
          ],
        ],
      ),
    );
  }
}
