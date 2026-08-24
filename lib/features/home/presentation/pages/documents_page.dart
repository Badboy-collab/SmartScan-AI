import 'dart:io';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/di/injection.dart';
import '../../../documents/domain/entities/scanned_document.dart';
import '../../../documents/presentation/providers/document_provider.dart';

class DocumentsPage extends StatefulWidget {
  const DocumentsPage({super.key});

  @override
  State<DocumentsPage> createState() => _DocumentsPageState();
}

class _DocumentsPageState extends State<DocumentsPage> {
  bool _favoritesOnly = false;
  String? _selectedFolder;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('All Documents')),
      body: ListenableBuilder(
        listenable: getIt<DocumentProvider>(),
        builder: (context, _) {
          final provider = getIt<DocumentProvider>();
          if (provider.isLoading) {
            return const Center(child: CircularProgressIndicator(color: Colors.teal));
          }

          final allDocs = provider.documents;
          final folders = provider.folders;

          List<ScannedDocument> docs = allDocs;
          if (_favoritesOnly) docs = docs.where((d) => d.isFavorite).toList();
          if (_selectedFolder != null) docs = docs.where((d) => d.folder == _selectedFolder).toList();

          if (allDocs.isEmpty) {
            return const Center(
              child: Text(
                'No documents yet\nScan your first document',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey, fontSize: 16),
              ),
            );
          }

          return Column(
            children: [
              // Filter chips: All / Favorites / Folders
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: SizedBox(
                  height: 38,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      _buildFilterChip(
                        label: 'All (${allDocs.length})',
                        selected: !_favoritesOnly && _selectedFolder == null,
                        onSelected: () {
                          setState(() {
                            _favoritesOnly = false;
                            _selectedFolder = null;
                          });
                        },
                      ),
                      _buildFilterChip(
                        label: '⭐ Favorites (${allDocs.where((d) => d.isFavorite).length})',
                        selected: _favoritesOnly,
                        onSelected: () {
                          setState(() {
                            _favoritesOnly = true;
                            _selectedFolder = null;
                          });
                        },
                      ),
                      for (final folder in folders) ...[
                        const SizedBox(width: 6),
                        _buildFilterChip(
                          label: '📁 $folder',
                          selected: !_favoritesOnly && _selectedFolder == folder,
                          onSelected: () {
                            setState(() {
                              _favoritesOnly = false;
                              _selectedFolder = folder;
                            });
                          },
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              Expanded(
                child: docs.isEmpty
                    ? Center(
                        child: Text(
                          _favoritesOnly
                              ? 'No favorite documents yet\nTap the ⭐ in a document to favorite it'
                              : 'No documents in this folder\nLong-press a document to move it here',
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.grey, fontSize: 14),
                        ),
                      )
                    : ListView.builder(
                        itemCount: docs.length,
                        itemBuilder: (context, index) {
                          final doc = docs[index];
                          return ListTile(
                            onTap: () => context.push('/document_viewer', extra: doc),
                            onLongPress: () => _showMoveToFolderSheet(context, provider, doc),
                            leading: Container(
                              width: 50,
                              height: 60,
                              decoration: BoxDecoration(
                                color: Colors.grey.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(4),
                                image: DecorationImage(
                                  image: FileImage(File(doc.thumbnailPath)),
                                  fit: BoxFit.cover,
                                  onError: (_, __) => const Icon(Icons.receipt_long, color: Colors.grey),
                                ),
                              ),
                            ),
                            title: Row(
                              children: [
                                Flexible(child: Text(doc.name, maxLines: 1, overflow: TextOverflow.ellipsis)),
                                if (doc.isFavorite) ...[
                                  const SizedBox(width: 4),
                                  const Icon(Icons.star, color: Colors.amber, size: 14),
                                ],
                              ],
                            ),
                            subtitle: Text(
                              '${doc.createdAt.year}/${doc.createdAt.month}/${doc.createdAt.day} • ${doc.pagePaths.length} pages'
                              '${doc.folder.isNotEmpty ? ' • 📁 ${doc.folder}' : ''}',
                            ),
                            trailing: IconButton(
                              icon: const Icon(Icons.delete_outline, color: Colors.grey),
                              onPressed: () => _showDeleteConfirmation(context, doc),
                            ),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildFilterChip({required String label, required bool selected, required VoidCallback onSelected}) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: ChoiceChip(
        label: Text(label, style: const TextStyle(fontSize: 12)),
        selected: selected,
        selectedColor: Colors.teal,
        labelStyle: TextStyle(color: selected ? Colors.white : null, fontSize: 12),
        onSelected: (_) => onSelected(),
      ),
    );
  }

  void _showMoveToFolderSheet(BuildContext context, DocumentProvider provider, ScannedDocument doc) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).cardColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: Text('Move to Folder', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Text(doc.name, style: const TextStyle(color: Colors.grey, fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
              const SizedBox(height: 8),
              ListTile(
                leading: const Icon(Icons.folder_off_outlined, color: Colors.grey),
                title: const Text('No folder'),
                onTap: () async {
                  Navigator.pop(ctx);
                  await provider.moveToFolder(doc.id, '');
                },
              ),
              for (final folder in provider.folders)
                ListTile(
                  leading: const Icon(Icons.folder_outlined, color: Colors.teal),
                  title: Text(folder),
                  trailing: doc.folder == folder ? const Icon(Icons.check, color: Colors.teal, size: 18) : null,
                  onTap: () async {
                    Navigator.pop(ctx);
                    await provider.moveToFolder(doc.id, folder);
                  },
                ),
              ListTile(
                leading: const Icon(Icons.create_new_folder_outlined, color: Colors.teal),
                title: const Text('Create new folder...'),
                onTap: () async {
                  Navigator.pop(ctx);
                  final controller = TextEditingController();
                  final name = await showDialog<String>(
                    context: context,
                    builder: (dctx) => AlertDialog(
                      title: const Text('New Folder'),
                      content: TextField(
                        controller: controller,
                        autofocus: true,
                        decoration: const InputDecoration(hintText: 'Folder name', border: OutlineInputBorder()),
                      ),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(dctx), child: const Text('Cancel')),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.teal, foregroundColor: Colors.white),
                          onPressed: () => Navigator.pop(dctx, controller.text.trim()),
                          child: const Text('Create'),
                        ),
                      ],
                    ),
                  );
                  if (name != null && name.isNotEmpty) {
                    await provider.moveToFolder(doc.id, name);
                  }
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
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
