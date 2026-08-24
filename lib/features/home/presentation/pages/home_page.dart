import 'dart:io';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/routing/widgets/main_layout.dart';
import '../../../../core/utils/import_utils.dart';
import '../../../documents/domain/entities/scanned_document.dart';
import '../../../documents/presentation/providers/document_provider.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _buildTopBar(context),
            const SizedBox(height: 16),
            _buildActionGrid(context),
            const SizedBox(height: 16),
            _buildRecentsList(context),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Row(
        children: [
          Expanded(
            child: Container(
              height: 48,
              decoration: BoxDecoration(
                color: isDark ? Colors.grey[850] : Colors.grey[100],
                borderRadius: BorderRadius.circular(24),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: const Row(
                children: [
                  Icon(Icons.search, color: Colors.grey),
                  SizedBox(width: 8),
                  Text('Search', style: TextStyle(color: Colors.grey, fontSize: 16)),
                ],
              ),
            ),
          ),
          const SizedBox(width: 16),
          const Icon(Icons.cloud, color: Colors.blueAccent, size: 28),
          const SizedBox(width: 16),
          const Icon(Icons.workspace_premium, color: Colors.amber, size: 28),
        ],
      ),
    );
  }

  Widget _buildActionGrid(BuildContext context) {
    final items = [
      {'icon': Icons.document_scanner, 'label': 'Smart Scan', 'color': Colors.teal},
      {'icon': Icons.picture_as_pdf, 'label': 'PDF Tools', 'color': Colors.redAccent},
      {'icon': Icons.image, 'label': 'Import Images', 'color': Colors.green},
      {'icon': Icons.folder, 'label': 'Import Files', 'color': Colors.blue},
      {'icon': Icons.badge, 'label': 'ID Card', 'color': Colors.blueAccent},
      {'icon': Icons.text_fields, 'label': 'To Text', 'color': Colors.teal},
      {'icon': Icons.description, 'label': 'To Word', 'color': Colors.blue},
      {'icon': Icons.dashboard_customize, 'label': 'All', 'color': Colors.purple},
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: items.length,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 4,
          mainAxisSpacing: 16,
          crossAxisSpacing: 8,
          childAspectRatio: 0.8,
        ),
        itemBuilder: (context, index) {
          final item = items[index];
          final color = item['color'] as Color;
          final isDark = Theme.of(context).brightness == Brightness.dark;
          
          return InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () {
              switch (index) {
                case 0: // Smart Scan
                  context.push('/scanner');
                  break;
                case 1: // PDF Tools
                  context.push('/pdf_merge');
                  break;
                case 2: // Import Images
                  ImportUtils.importImages(context);
                  break;
                case 3: // Import Files
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('PDF / document import coming soon!')),
                  );
                  break;
                case 4: // ID Card
                  context.push('/id_card_scanner');
                  break;
                case 5: // To Text
                  context.push('/ocr');
                  break;
                case 6: // To Word
                  context.push('/ocr');
                  break;
                case 7: // All
                  context.go('/tools');
                  break;
              }
            },
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: isDark ? color.withValues(alpha: 0.15) : color.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(item['icon'] as IconData, color: color, size: 24),
                ),
                const SizedBox(height: 8),
                Text(
                  item['label'] as String,
                  style: const TextStyle(fontSize: 12),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildRecentsList(BuildContext context) {
    return Expanded(
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(24),
            topRight: Radius.circular(24),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 24, 20, 16),
              child: Text(
                'Recents',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
            ),
            Expanded(
              child: ListenableBuilder(
                listenable: getIt<DocumentProvider>(),
                builder: (context, _) {
                  final provider = getIt<DocumentProvider>();
                  if (provider.isLoading) {
                    return const Center(child: CircularProgressIndicator(color: Colors.teal));
                  }
                  
                  final docs = provider.documents;
                  if (docs.isEmpty) {
                    return const Center(
                      child: Text(
                        'No documents yet\nScan your first document',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey, fontSize: 16),
                      ),
                    );
                  }

                  return ListView.builder(
                    padding: const EdgeInsets.only(bottom: 80), // Fab spacing
                    itemCount: docs.length,
                    itemBuilder: (context, index) {
                      return _buildRecentItem(context, docs[index]);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecentItem(BuildContext context, ScannedDocument doc) {
    return InkWell(
      onTap: () => context.push('/document_viewer', extra: doc),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
          Container(
            width: 80,
            height: 100,
            decoration: BoxDecoration(
              color: Colors.grey.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: Colors.grey.withValues(alpha: 0.3)),
              image: DecorationImage(
                image: FileImage(File(doc.thumbnailPath)),
                fit: BoxFit.cover,
                onError: (_, __) => const Icon(Icons.receipt_long, color: Colors.grey, size: 40),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 4),
                Text(
                  doc.name,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 12),
                Text(
                  'Created: ${doc.createdAt.year}/${doc.createdAt.month}/${doc.createdAt.day}',
                  style: const TextStyle(fontSize: 13, color: Colors.grey),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(Icons.file_copy, size: 14, color: Colors.grey),
                    const SizedBox(width: 4),
                    Text('${doc.pagePaths.length}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                  ],
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 40.0),
            child: IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.grey, size: 24),
              onPressed: () => _showDeleteConfirmation(context, doc),
            ),
          ),
        ],
      ),
      ),
    );
  }

  void _showDeleteConfirmation(BuildContext context, ScannedDocument doc) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this document?'),
        content: const Text('This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () {
              getIt<DocumentProvider>().deleteDocument(doc.id);
              Navigator.pop(context);
            },
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}
