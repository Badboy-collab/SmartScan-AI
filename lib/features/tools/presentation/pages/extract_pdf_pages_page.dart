import 'dart:io';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../documents/domain/entities/scanned_document.dart';
import '../../../documents/presentation/providers/document_provider.dart';

class ExtractPdfPagesPage extends StatefulWidget {
  final bool exportAsImagesOnly;

  const ExtractPdfPagesPage({super.key, this.exportAsImagesOnly = false});

  @override
  State<ExtractPdfPagesPage> createState() => _ExtractPdfPagesPageState();
}

class _ExtractPdfPagesPageState extends State<ExtractPdfPagesPage> {
  ScannedDocument? _selectedDoc;
  final Set<int> _selectedPageIndices = {};
  bool _isProcessing = false;

  void _togglePage(int index) {
    setState(() {
      if (_selectedPageIndices.contains(index)) {
        _selectedPageIndices.remove(index);
      } else {
        _selectedPageIndices.add(index);
      }
    });
  }

  void _selectAll() {
    if (_selectedDoc == null) return;
    setState(() {
      if (_selectedPageIndices.length == _selectedDoc!.pagePaths.length) {
        _selectedPageIndices.clear();
      } else {
        _selectedPageIndices.addAll(List.generate(_selectedDoc!.pagePaths.length, (i) => i));
      }
    });
  }

  Future<void> _extractPages() async {
    if (_selectedDoc == null || _selectedPageIndices.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select at least one page')),
      );
      return;
    }

    setState(() => _isProcessing = true);
    try {
      final List<String> extractedPaths = _selectedPageIndices
          .map((i) => _selectedDoc!.pagePaths[i])
          .toList();

      if (widget.exportAsImagesOnly) {
        // Share individual images
        final xfiles = extractedPaths.map((p) => XFile(p)).toList();
        await Share.shareXFiles(xfiles, text: 'Exported pages from AH Scanner');
        setState(() => _isProcessing = false);
        return;
      }

      // Create new extracted document
      final dir = await getApplicationDocumentsDirectory();
      final docId = const Uuid().v4();
      final now = DateTime.now();

      final newDoc = ScannedDocument(
        id: docId,
        name: '${_selectedDoc!.name} (Extracted ${extractedPaths.length}p)',
        createdAt: now,
        updatedAt: now,
        pagePaths: extractedPaths,
        thumbnailPath: extractedPaths.first,
        dirPath: dir.path,
      );

      final provider = getIt<DocumentProvider>();
      await provider.addDocument(newDoc);

      if (mounted) {
        context.pushReplacement('/document_viewer', extra: newDoc);
      }
    } catch (e) {
      debugPrint('[ExtractPages] Error: $e');
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
        title: Text(widget.exportAsImagesOnly ? 'PDF to Images' : 'Extract PDF Pages'),
        actions: [
          if (_selectedDoc != null)
            TextButton(
              onPressed: _selectAll,
              child: Text(
                _selectedPageIndices.length == _selectedDoc!.pagePaths.length ? 'Deselect All' : 'Select All',
                style: const TextStyle(color: Colors.tealAccent, fontWeight: FontWeight.bold),
              ),
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
                            child: Text('${d.name} (${d.pagePaths.length} pages)', style: const TextStyle(color: Colors.white)),
                          );
                        }).toList(),
                        onChanged: (val) {
                          setState(() {
                            _selectedDoc = val;
                            _selectedPageIndices.clear();
                            if (val != null) {
                              _selectedPageIndices.addAll(List.generate(val.pagePaths.length, (i) => i));
                            }
                          });
                        },
                      ),
                    ),
                  ),
                ),
                if (_selectedDoc != null)
                  Expanded(
                    child: GridView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3,
                        crossAxisSpacing: 10,
                        mainAxisSpacing: 10,
                        childAspectRatio: 0.7,
                      ),
                      itemCount: _selectedDoc!.pagePaths.length,
                      itemBuilder: (context, index) {
                        final isSelected = _selectedPageIndices.contains(index);
                        final path = _selectedDoc!.pagePaths[index];

                        return GestureDetector(
                          onTap: () => _togglePage(index),
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              Container(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                    color: isSelected ? AppColors.primaryLight : Colors.white24,
                                    width: isSelected ? 3 : 1,
                                  ),
                                ),
                                clipBehavior: Clip.antiAlias,
                                child: Image.file(File(path), fit: BoxFit.cover),
                              ),
                              Positioned(
                                top: 6,
                                right: 6,
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: isSelected ? AppColors.primaryLight : Colors.black54,
                                    shape: BoxShape.circle,
                                  ),
                                  padding: const EdgeInsets.all(4),
                                  child: Icon(
                                    isSelected ? Icons.check : Icons.circle_outlined,
                                    color: Colors.white,
                                    size: 16,
                                  ),
                                ),
                              ),
                              Positioned(
                                bottom: 4,
                                left: 6,
                                child: Text(
                                  'Page ${index + 1}',
                                  style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold, shadows: [Shadow(color: Colors.black, blurRadius: 4)]),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
              ],
            ),
      bottomNavigationBar: _selectedDoc != null
          ? SafeArea(
              child: Container(
                padding: const EdgeInsets.all(16),
                color: const Color(0xFF1E1E1E),
                child: ElevatedButton(
                  onPressed: _selectedPageIndices.isEmpty || _isProcessing ? null : _extractPages,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryLight,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: Text(
                    widget.exportAsImagesOnly
                        ? 'Share ${_selectedPageIndices.length} Image(s)'
                        : 'Extract ${_selectedPageIndices.length} Page(s) to New Doc',
                    style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            )
          : null,
    );
  }
}
