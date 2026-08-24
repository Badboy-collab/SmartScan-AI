import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import '../../../../core/di/injection.dart';
import '../../../documents/presentation/providers/document_provider.dart';
import '../../../documents/domain/entities/scanned_document.dart';
import 'package:uuid/uuid.dart';

class ToolsPage extends StatelessWidget {
  const ToolsPage({super.key});

  Future<void> _importImages(BuildContext context) async {
    try {
      final picker = ImagePicker();
      final pickedFiles = await picker.pickMultiImage();
      if (pickedFiles.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Processing images...')));
      
      final provider = getIt<DocumentProvider>();
      final docId = const Uuid().v4();
      final now = DateTime.now();
      
      List<String> validPaths = [];
      for (final pf in pickedFiles) {
        // Just save them directly as pages for now
        // In a real pipeline, they'd go through crop/filter first.
        validPaths.add(pf.path); 
      }
      
      final doc = ScannedDocument(
        id: docId,
        name: 'SmartScan ${now.month}-${now.day}-${now.year} ${now.hour}.${now.minute}',
        createdAt: now,
        updatedAt: now,
        pagePaths: validPaths,
        thumbnailPath: validPaths.isNotEmpty ? validPaths.first : '',
        dirPath: validPaths.isNotEmpty ? p.dirname(validPaths.first) : '',
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

  void _unimplemented(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Coming soon in next phase!')));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Tools')),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          _buildCategory('CONVERT', [
            _ToolItem(Icons.description, 'To Word', Colors.blue, onTap: () => context.push('/ocr')),
            _ToolItem(Icons.table_chart, 'To Excel', Colors.green, onTap: () => context.push('/ocr')),
            _ToolItem(Icons.slideshow, 'To PPT', Colors.orange, onTap: () => _unimplemented(context)),
            _ToolItem(Icons.image, 'PDF to Images', Colors.purple, onTap: () => context.push('/pdf_to_images')),
            _ToolItem(Icons.panorama, 'PDF to Long Image', Colors.redAccent, onTap: () => context.push('/pdf_to_long_image')),
          ]),
          const SizedBox(height: 24),
          _buildCategory('EDIT', [
            _ToolItem(Icons.upload_file, 'Import Files', Colors.teal, onTap: () => _importImages(context)),
            _ToolItem(Icons.draw, 'Sign', Colors.deepPurple, onTap: () => context.push('/signature')),
            _ToolItem(Icons.branding_watermark, 'Add Watermark', Colors.indigo, onTap: () => context.push('/watermark')),
            _ToolItem(Icons.merge_type, 'Merge PDFs', Colors.blueAccent, onTap: () => context.push('/pdf_merge')),
            _ToolItem(Icons.picture_as_pdf, 'Extract PDF Pages', Colors.red, onTap: () => context.push('/extract_pdf_pages')),
            _ToolItem(Icons.reorder, 'Reorder PDF Pages', Colors.blueGrey, onTap: () => _unimplemented(context)),
            _ToolItem(Icons.security, 'Protect PDF', Colors.green, onTap: () => _unimplemented(context)),
          ]),
          const SizedBox(height: 24),
          _buildCategory('SCAN', [
            _ToolItem(Icons.badge, 'ID Card', Colors.lightBlue, onTap: () => context.push('/id_card_scanner')),
            _ToolItem(Icons.text_fields, 'Scan to Text', Colors.teal, onTap: () => context.push('/ocr')),
            _ToolItem(Icons.camera_front, 'ID Photo Maker', Colors.orangeAccent, onTap: () => context.push('/id_photo_maker')),
            _ToolItem(Icons.document_scanner, 'Scan to Excel', Colors.green, onTap: () => context.push('/ocr')),
            _ToolItem(Icons.quiz, 'Question Set', Colors.purple, onTap: () => _unimplemented(context)),
            _ToolItem(Icons.book, 'Book', Colors.brown, onTap: () => _unimplemented(context)),
            _ToolItem(Icons.co_present, 'PPT', Colors.deepOrange, onTap: () => _unimplemented(context)),
            _ToolItem(Icons.image_search, 'Import Images', Colors.indigoAccent, onTap: () => _importImages(context)),
          ]),
          const SizedBox(height: 24),
          _buildCategory('OTHER', [
            _ToolItem(Icons.qr_code, 'QR Code', Colors.black54, onTap: () => context.push('/qr_scanner')),
          ]),
        ],
      ),
    );
  }

  Widget _buildCategory(String title, List<_ToolItem> items) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.grey)),
        const SizedBox(height: 16),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 4,
            crossAxisSpacing: 8,
            mainAxisSpacing: 16,
            childAspectRatio: 0.8,
          ),
          itemCount: items.length,
          itemBuilder: (context, index) {
            final item = items[index];
            return InkWell(
              onTap: item.onTap,
              borderRadius: BorderRadius.circular(8),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: item.color.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(item.icon, color: item.color, size: 28),
                  ),
                  const SizedBox(height: 8),
                  Text(item.label, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12), maxLines: 2),
                ],
              ),
            );
          },
        ),
      ],
    );
  }
}

class _ToolItem {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onTap;

  _ToolItem(this.icon, this.label, this.color, {this.onTap});
}
