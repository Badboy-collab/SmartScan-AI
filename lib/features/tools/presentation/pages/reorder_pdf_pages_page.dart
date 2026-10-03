import 'dart:io';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../documents/domain/entities/scanned_document.dart';
import '../../../documents/presentation/providers/document_provider.dart';

/// Drag-and-drop page reordering.
///
/// Saves the new order as a NEW document; the original is left untouched so a
/// wrong ordering never destroys the user's scan.
class ReorderPdfPagesPage extends StatefulWidget {
  const ReorderPdfPagesPage({super.key});

  @override
  State<ReorderPdfPagesPage> createState() => _ReorderPdfPagesPageState();
}

class _ReorderPdfPagesPageState extends State<ReorderPdfPagesPage> {
  ScannedDocument? _selectedDoc;
  List<String> _orderedPaths = [];
  bool _isSaving = false;

  void _onReorder(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) newIndex -= 1;
      final path = _orderedPaths.removeAt(oldIndex);
      _orderedPaths.insert(newIndex, path);
    });
  }

  Future<void> _saveAsNewDocument() async {
    final source = _selectedDoc;
    if (source == null || _orderedPaths.isEmpty || _isSaving) return;

    setState(() => _isSaving = true);
    try {
      final dir = await getApplicationDocumentsDirectory();
      final now = DateTime.now();
      final newDoc = ScannedDocument(
        id: const Uuid().v4(),
        name: '${source.name} (Reordered)',
        createdAt: now,
        updatedAt: now,
        pagePaths: List<String>.from(_orderedPaths),
        thumbnailPath: _orderedPaths.first,
        dirPath: dir.path,
      );

      await getIt<DocumentProvider>().addDocument(newDoc);
      if (!mounted) return;
      setState(() => _isSaving = false);
      context.pushReplacement('/document_viewer', extra: newDoc);
    } catch (e) {
      debugPrint('[ReorderPages] Error: $e');
      if (!mounted) return;
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final docs = getIt<DocumentProvider>().documents;

    return Scaffold(
      backgroundColor: const Color(0xFF1E1E1E),
      appBar: AppBar(
        title: const Text('Reorder PDF Pages'),
        actions: [
          if (_selectedDoc != null)
            TextButton(
              onPressed: _isSaving
                  ? null
                  : () => setState(() {
                        _orderedPaths = List<String>.from(_selectedDoc!.pagePaths);
                      }),
              child: const Text('Reset order', style: TextStyle(color: Colors.tealAccent)),
            ),
        ],
      ),
      body: docs.isEmpty
          ? const Center(child: Text('No documents available.'))
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Container(
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
                            child: Text(
                              '${d.name} (${d.pagePaths.length} pages)',
                              style: const TextStyle(color: Colors.white),
                            ),
                          );
                        }).toList(),
                        onChanged: _isSaving
                            ? null
                            : (val) => setState(() {
                                  _selectedDoc = val;
                                  _orderedPaths = val == null ? [] : List<String>.from(val.pagePaths);
                                }),
                      ),
                    ),
                  ),
                ),
                if (_selectedDoc != null) ...[
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Drag a page to move it. Page numbers update as you go.',
                        style: TextStyle(color: Colors.white54, fontSize: 12),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: ReorderableListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: _orderedPaths.length,
                      onReorder: _onReorder,
                      itemBuilder: (context, index) {
                        final path = _orderedPaths[index];
                        return Card(
                          key: ValueKey('$path#$index'),
                          color: const Color(0xFF2A2A2A),
                          margin: const EdgeInsets.symmetric(vertical: 6),
                          child: ListTile(
                            leading: SizedBox(
                              width: 44,
                              height: 56,
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: Image.file(File(path), fit: BoxFit.cover),
                              ),
                            ),
                            title: Text(
                              'Page ${index + 1}',
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                            ),
                            subtitle: Text(
                              path.split(Platform.pathSeparator).last,
                              style: const TextStyle(color: Colors.white38, fontSize: 11),
                            ),
                            trailing: const Icon(Icons.drag_handle, color: Colors.white54),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ],
            ),
      bottomNavigationBar: _selectedDoc == null
          ? null
          : SafeArea(
              child: Container(
                padding: const EdgeInsets.all(16),
                color: const Color(0xFF1E1E1E),
                child: ElevatedButton.icon(
                  onPressed: _isSaving ? null : _saveAsNewDocument,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryLight,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  icon: _isSaving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.save_alt, color: Colors.white),
                  label: Text(
                    _isSaving ? 'Saving...' : 'Save as new document',
                    style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ),
    );
  }
}
