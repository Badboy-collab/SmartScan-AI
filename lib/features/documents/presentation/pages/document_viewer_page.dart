import 'dart:io';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/utils/gallery_saver.dart';
import '../../../conversion/presentation/pages/document_conversion_page.dart';
import '../../data/services/pdf_export_service.dart';
import '../../domain/entities/scanned_document.dart';
import '../providers/document_provider.dart';

class DocumentViewerPage extends StatefulWidget {
  final ScannedDocument document;

  const DocumentViewerPage({super.key, required this.document});

  @override
  State<DocumentViewerPage> createState() => _DocumentViewerPageState();
}

class _DocumentViewerPageState extends State<DocumentViewerPage> {
  late ScannedDocument _doc;

  bool _isGeneratingPdf = false;
  bool _isReorderMode = false;
  String _pdfSize = '...';
  String _jpgSize = '...';

  @override
  void initState() {
    super.initState();
    _doc = widget.document;
    _calculateSizes();
  }

  Future<void> _calculateSizes() async {
    int jpgBytes = 0;
    for (final path in _doc.pagePaths) {
      final f = File(path);
      if (await f.exists()) jpgBytes += await f.length();
    }
    if (mounted) {
      setState(() {
        _jpgSize = '${(jpgBytes / (1024 * 1024)).toStringAsFixed(2)}MB';
        _pdfSize = '${((jpgBytes * 0.85) / (1024 * 1024)).toStringAsFixed(2)}MB';
      });
    }
  }

  Future<void> _toggleFavorite() async {
    final updated = _doc.copyWith(isFavorite: !_doc.isFavorite);
    await getIt<DocumentProvider>().updateDocument(updated);
    if (mounted) setState(() => _doc = updated);
  }

  void _handleReorder(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) newIndex -= 1;
      final pages = List<String>.from(_doc.pagePaths);
      final raws = List<String>.from(_doc.rawPagePaths);

      final movedPage = pages.removeAt(oldIndex);
      pages.insert(newIndex, movedPage);

      if (raws.length > oldIndex) {
        final movedRaw = raws.removeAt(oldIndex);
        raws.insert(newIndex, movedRaw);
      }

      _doc = _doc.copyWith(
        pagePaths: pages,
        rawPagePaths: raws,
        updatedAt: DateTime.now(),
      );
    });
    // Persist the new order immediately.
    getIt<DocumentProvider>().updateDocument(_doc);
  }

  Future<void> _sharePdf() async {
    setState(() => _isGeneratingPdf = true);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Generating PDF...'), duration: Duration(seconds: 1)),
    );

    try {
      final pdfService = getIt<PdfExportService>();
      final pdfFile = await pdfService.generatePdf(_doc);
      await _sharePdfFile(pdfFile, 'application/pdf');
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) setState(() => _isGeneratingPdf = false);
    }
  }

  Future<void> _sharePdfFile(File pdfFile, String mimeType) async {
    final xFile = XFile(pdfFile.path, mimeType: mimeType);
    await SharePlus.instance.share(ShareParams(files: [xFile], text: _doc.name));
  }

  void _showPdfSettingsSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(20, 8, 20, 12),
                  child: Text('PDF Settings', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                ),
                ListTile(
                  leading: const Icon(Icons.picture_as_pdf, color: Color(0xFF00ACC1)),
                  title: const Text('Normal PDF', style: TextStyle(color: Colors.white)),
                  subtitle: const Text('Original quality', style: TextStyle(color: Colors.white54, fontSize: 12)),
                  onTap: () {
                    Navigator.pop(ctx);
                    _sharePdf();
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.compress, color: Color(0xFF00ACC1)),
                  title: const Text('Compressed PDF', style: TextStyle(color: Colors.white)),
                  subtitle: const Text('Smaller file size (reduced quality)', style: TextStyle(color: Colors.white54, fontSize: 12)),
                  onTap: () {
                    Navigator.pop(ctx);
                    _shareCompressedPdf();
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.lock_outline, color: Color(0xFF00ACC1)),
                  title: const Text('Protect with Password', style: TextStyle(color: Colors.white)),
                  subtitle: const Text('Encrypt PDF with a password', style: TextStyle(color: Colors.white54, fontSize: 12)),
                  onTap: () {
                    Navigator.pop(ctx);
                    _protectPdf();
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _shareCompressedPdf() async {
    setState(() => _isGeneratingPdf = true);
    try {
      final pdfService = getIt<PdfExportService>();
      final pdfFile = await pdfService.generateCompressedPdf(_doc);
      await _sharePdfFile(pdfFile, 'application/pdf');
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Compress error: $e')));
    } finally {
      if (mounted) setState(() => _isGeneratingPdf = false);
    }
  }

  Future<void> _protectPdf() async {
    final passwordController = TextEditingController();
    final confirmController = TextEditingController();
    final password = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text('Protect PDF', style: TextStyle(color: Colors.white, fontSize: 16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: passwordController,
              obscureText: true,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'Password',
                labelStyle: TextStyle(color: Colors.white54),
                hintText: 'Enter password',
                enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
                focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: Color(0xFF00ACC1))),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: confirmController,
              obscureText: true,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'Confirm password',
                labelStyle: TextStyle(color: Colors.white54),
                enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
                focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: Color(0xFF00ACC1))),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel', style: TextStyle(color: Colors.white54))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00ACC1), foregroundColor: Colors.white),
            onPressed: () {
              final pw1 = passwordController.text;
              final pw2 = confirmController.text;
              if (pw1.length < 4) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Password must be at least 4 characters')));
                return;
              }
              if (pw1 != pw2) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Passwords do not match')));
                return;
              }
              Navigator.pop(ctx, pw1);
            },
            child: const Text('Protect'),
          ),
        ],
      ),
    );

    if (password != null && password.isNotEmpty) {
      setState(() => _isGeneratingPdf = true);
      try {
        final pdfService = getIt<PdfExportService>();
        final pdfFile = await pdfService.generateProtectedPdf(_doc, password);
        await _sharePdfFile(pdfFile, 'application/pdf');
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Protect error: $e')));
      } finally {
        if (mounted) setState(() => _isGeneratingPdf = false);
      }
    }
  }

  Future<void> _shareJpg() async {
    try {
      final List<XFile> xFiles = [];
      for (final path in _doc.pagePaths) {
        if (await File(path).exists()) {
          xFiles.add(XFile(path, mimeType: 'image/jpeg'));
        }
      }
      if (xFiles.isNotEmpty) {
        await SharePlus.instance.share(ShareParams(files: xFiles, text: _doc.name));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error sharing JPG: $e')));
    }
  }

  /// Writes every page as a JPEG into a location the Gallery / file manager can
  /// see (`Pictures/AH Scanner` or `Download/AH Scanner`).
  ///
  /// A single-page document keeps the plain document name (`AH Scanner
  /// 29.09.26.jpg`); a multi-page one appends the page number so the pages cannot
  /// overwrite each other. No timestamp is used, so re-saving the same document
  /// keeps requesting the same name and the platform de-duplicates it by itself
  /// (` (1)`, ` (2)`, …) instead of raising a name conflict.
  Future<void> _saveImages({required bool toDownloads}) async {
    try {
      int count = 0;
      SavedImage? lastSaved;
      final String baseName = _sanitizeFileName(_doc.name);
      final bool multiPage = _doc.pagePaths.length > 1;

      for (int i = 0; i < _doc.pagePaths.length; i++) {
        final src = File(_doc.pagePaths[i]);
        if (!await src.exists()) continue;

        lastSaved = await GallerySaver.saveJpeg(
          bytes: await src.readAsBytes(),
          fileName:
              multiPage ? '${baseName}_page_${i + 1}.jpg' : '$baseName.jpg',
          toDownloads: toDownloads,
        );
        count++;
      }

      if (!mounted) return;

      if (count == 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No page images found to save')),
        );
        return;
      }

      final String location =
          GallerySaver.locationLabel(toDownloads: toDownloads);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: toDownloads ? Colors.teal[800] : Colors.green[800],
          content: Text(
            count == 1 && lastSaved != null
                ? '✓ Saved to $location as ${lastSaved.fileName}'
                : '✓ Saved $count pages of "$baseName" to $location',
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save: $e')),
        );
      }
    }
  }

  Future<void> _saveToGallery() => _saveImages(toDownloads: false);

  Future<void> _saveToLocal() => _saveImages(toDownloads: true);

  String _sanitizeFileName(String name) {
    return name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
  }

  void _showJpgOptionsSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 20.0, vertical: 8.0),
                  child: Text('JPG OPTIONS', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                ),
                const SizedBox(height: 8),
                ListTile(
                  leading: const Icon(Icons.folder_outlined, color: Color(0xFF00ACC1), size: 26),
                  title: const Text('Save to Local', style: TextStyle(color: Colors.white, fontSize: 15)),
                  subtitle: const Text('Download/AH Scanner (visible in Files)', style: TextStyle(color: Colors.white54, fontSize: 12)),
                  onTap: () {
                    Navigator.pop(ctx);
                    _saveToLocal();
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.photo_library_outlined, color: Color(0xFF00ACC1), size: 26),
                  title: const Text('Save to Gallery', style: TextStyle(color: Colors.white, fontSize: 15)),
                  subtitle: const Text('Pictures/AH Scanner (visible in Photos)', style: TextStyle(color: Colors.white54, fontSize: 12)),
                  onTap: () {
                    Navigator.pop(ctx);
                    _saveToGallery();
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.share_outlined, color: Color(0xFF00ACC1), size: 26),
                  title: const Text('Share to Apps', style: TextStyle(color: Colors.white, fontSize: 15)),
                  subtitle: const Text('Share via WhatsApp, Telegram, Gmail...', style: TextStyle(color: Colors.white54, fontSize: 12)),
                  onTap: () {
                    Navigator.pop(ctx);
                    _shareJpg();
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _renameDocument() async {
    final controller = TextEditingController(text: _doc.name);
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Rename Document'),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(
              hintText: 'Enter new document name',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.teal, foregroundColor: Colors.white),
              onPressed: () => Navigator.pop(ctx, controller.text.trim()),
              child: const Text('Save'),
            ),
          ],
        );
      },
    );

    if (newName != null && newName.isNotEmpty && newName != _doc.name) {
      final updated = _doc.copyWith(name: newName);
      final provider = getIt<DocumentProvider>();
      await provider.updateDocument(updated);
      setState(() => _doc = updated);
    }
  }

  void _showDocumentInfo() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).cardColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        final dt = _doc.createdAt;
        final formattedDate = '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Document Information', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),
                _buildInfoRow('Name', _doc.name),
                _buildInfoRow('Pages', '${_doc.pagePaths.length} Pages'),
                _buildInfoRow('Size', _jpgSize),
                _buildInfoRow('Created', formattedDate),
                _buildInfoRow('Location', 'AH Scanner / Documents'),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('CLOSE')),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey, fontSize: 14)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
        ],
      ),
    );
  }

  Future<void> _importImages() async {
    final picker = ImagePicker();
    final List<XFile> picked = await picker.pickMultiImage();
    if (picked.isNotEmpty) {
      final provider = getIt<DocumentProvider>();
      final newPaths = [..._doc.pagePaths];
      final newRaws = [..._doc.rawPagePaths];
      for (final img in picked) {
        newPaths.add(img.path);
        newRaws.add(img.path);
      }
      final updated = _doc.copyWith(pagePaths: newPaths, rawPagePaths: newRaws);
      await provider.updateDocument(updated);
      setState(() => _doc = updated);
      _calculateSizes();
    }
  }

  void _showCamScannerMoreMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      isScrollControlled: true,
      builder: (ctx) {
        return SafeArea(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 16.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20.0),
                    child: Text(
                      _doc.name,
                      style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(height: 16),

                  // 2 Rows of 3 Quick Action Cards (Matches media_1787210645707.png)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            _buildGridTile(Icons.image, 'Import Images', const Color(0xFF00ACC1), () {
                              Navigator.pop(ctx);
                              _importImages();
                            }),
                            _buildGridTile(Icons.collections, 'Collage', const Color(0xFF00ACC1), () {
                              Navigator.pop(ctx);
                              context.push('/pdf_to_long_image');
                            }, isCrown: true),
                            _buildGridTile(Icons.description, 'Word', const Color(0xFF185ABD), () {
                              Navigator.pop(ctx);
                              context.push('/convert_document', extra: {'document': _doc, 'format': ExportFormatType.word});
                            }, isCrown: true),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            _buildGridTile(Icons.security, 'Anti-counterfeit', const Color(0xFFFF8F00), () {
                              Navigator.pop(ctx);
                              context.push('/watermark');
                            }, isCrown: true),
                            _buildGridTile(Icons.save_alt, 'Save to Gallery', const Color(0xFF00ACC1), () {
                              Navigator.pop(ctx);
                              _saveToGallery();
                            }),
                            _buildGridTile(Icons.edit_note, 'Batch Edit', const Color(0xFF00ACC1), () {
                              Navigator.pop(ctx);
                              if (_doc.pagePaths.isNotEmpty) {
                                context.push('/single_page_viewer', extra: {'document': _doc, 'initialPageIndex': 0});
                              }
                            }),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Divider(color: Colors.white12, thickness: 1),

                  _buildListTile(Icons.folder_outlined, 'Save to Local', () {
                    Navigator.pop(ctx);
                    _saveToLocal();
                  }),
                  _buildListTile(Icons.computer, 'Send to PC', () {
                    Navigator.pop(ctx);
                    _sharePdf();
                  }),
                  _buildListTile(Icons.edit_outlined, 'Rename', () {
                    Navigator.pop(ctx);
                    _renameDocument();
                  }),
                  _buildListTile(Icons.check_box_outlined, 'Select', () {
                    Navigator.pop(ctx);
                  }),
                  _buildListTile(Icons.text_fields, 'Extract Text', () {
                    Navigator.pop(ctx);
                    context.push('/ocr');
                  }, isCrown: true),
                  _buildListTile(Icons.picture_as_pdf_outlined, 'PDF Settings', () {
                    Navigator.pop(ctx);
                    _showPdfSettingsSheet();
                  }),
                  _buildListTile(Icons.email_outlined, 'Email to Myself', () {
                    Navigator.pop(ctx);
                    _sharePdf();
                  }),
                  _buildListTile(Icons.label_outline, 'Add Tags', () {
                    Navigator.pop(ctx);
                  }),
                  _buildListTile(Icons.info_outline, 'Document Information', () {
                    Navigator.pop(ctx);
                    _showDocumentInfo();
                  }),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildGridTile(IconData icon, String label, Color color, VoidCallback onTap, {bool isCrown = false}) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 4.0),
          padding: const EdgeInsets.symmetric(vertical: 12.0, horizontal: 4.0),
          decoration: BoxDecoration(
            color: const Color(0xFF282828),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Icon(icon, color: color, size: 26),
                  if (isCrown)
                    const Positioned(
                      top: -6,
                      right: -8,
                      child: Icon(Icons.workspace_premium, color: Colors.amber, size: 14),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                label,
                style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w500),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildListTile(IconData icon, String title, VoidCallback onTap, {bool isCrown = false}) {
    return ListTile(
      leading: Icon(icon, color: Colors.white70, size: 22),
      title: Row(
        children: [
          Text(title, style: const TextStyle(color: Colors.white, fontSize: 15)),
          if (isCrown) ...[
            const SizedBox(width: 6),
            const Icon(Icons.workspace_premium, color: Colors.amber, size: 16),
          ]
        ],
      ),
      onTap: onTap,
      dense: true,
      visualDensity: VisualDensity.compact,
    );
  }

  Widget _buildReorderablePageTile(int index) {
    return Stack(
      key: ValueKey('reorderable_page_$index'),
      children: [
        _buildPageCard(index),
        if (_isReorderMode)
          Positioned(
            top: 6,
            right: 6,
            child: ReorderableDragStartListener(
              index: index,
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                child: const Icon(Icons.drag_handle, color: Colors.white, size: 16),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildPageCard(int index) {
    final path = _doc.pagePaths[index];
    return GestureDetector(
      onTap: () {
        if (_isReorderMode) return;
        context.push('/single_page_viewer', extra: {
          'document': _doc,
          'initialPageIndex': index,
        }).then((_) {
          final provider = getIt<DocumentProvider>();
          final updated = provider.documents.firstWhere((d) => d.id == _doc.id, orElse: () => _doc);
          setState(() => _doc = updated);
          _calculateSizes();
        });
      },
      child: Stack(
        fit: StackFit.expand,
        children: [
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(6),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.25),
                  blurRadius: 6,
                  offset: const Offset(0, 3),
                ),
              ],
              border: Border.all(color: Colors.white12),
            ),
            clipBehavior: Clip.antiAlias,
            child: Image.file(
              File(path),
              fit: BoxFit.cover,
              key: ValueKey('${path}_${File(path).existsSync() ? File(path).lastModifiedSync().millisecondsSinceEpoch : 0}'),
            ),
          ),
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: const BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.vertical(bottom: Radius.circular(6)),
              ),
              child: Text(
                (index + 1).toString().padLeft(2, '0'),
                style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showShareSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      isScrollControlled: true,
      builder: (ctx) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.85,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          builder: (ctx, scrollController) {
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '${_doc.pagePaths.length} picture(s) selected',
                        style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white54),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                ),
                const Center(
                  child: Text('Share File', style: TextStyle(color: Color(0xFF00ACC1), fontWeight: FontWeight.bold, fontSize: 15)),
                ),
                Container(
                  height: 2,
                  margin: const EdgeInsets.only(top: 8),
                  color: const Color(0xFF00ACC1),
                ),
                Expanded(
                  child: ListView(
                    controller: scrollController,
                    padding: const EdgeInsets.all(16),
                    children: [
                      Center(
                        child: Container(
                          height: 220,
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.white24),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: _doc.pagePaths.isNotEmpty
                              ? Image.file(File(_doc.pagePaths.first), fit: BoxFit.contain)
                              : const SizedBox(),
                        ),
                      ),
                      const SizedBox(height: 20),
                      _buildShareOptionItem(Icons.picture_as_pdf, 'Share PDF', _pdfSize, onTap: () {
                        Navigator.pop(ctx);
                        _sharePdf();
                      }),
                      _buildShareOptionItem(Icons.description, 'Share Word', _pdfSize, onTap: () {
                        Navigator.pop(ctx);
                        context.push('/convert_document', extra: {'document': _doc, 'format': ExportFormatType.word});
                      }),
                      _buildShareOptionItem(Icons.image, 'Share as Long Image', '', onTap: () {
                        Navigator.pop(ctx);
                        context.push('/pdf_to_long_image');
                      }),
                      _buildShareOptionItem(Icons.image_outlined, 'Share JPG', _jpgSize, onTap: () {
                        Navigator.pop(ctx);
                        _showJpgOptionsSheet();
                      }),
                    ],
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildShareOptionItem(IconData icon, String title, String size, {required VoidCallback onTap}) {
    return ListTile(
      leading: Icon(icon, color: Colors.white, size: 26),
      title: Row(
        children: [
          Text(title, style: const TextStyle(color: Colors.white, fontSize: 15)),
          if (size.isNotEmpty) ...[
            const SizedBox(width: 8),
            Text('($size)', style: const TextStyle(color: Colors.white54, fontSize: 12)),
          ],
        ],
      ),
      onTap: onTap,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF141414), // Modern dark CamScanner background
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E1E1E),
        foregroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => context.pop(),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('AH Scanner', style: TextStyle(fontSize: 11, color: Colors.white54)),
            Text(_doc.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(_doc.isFavorite ? Icons.star : Icons.star_border, color: _doc.isFavorite ? Colors.amber : Colors.white),
            tooltip: 'Favorite',
            onPressed: _toggleFavorite,
          ),
          IconButton(
            icon: Icon(_isReorderMode ? Icons.check : Icons.swap_vert, color: Colors.white),
            tooltip: _isReorderMode ? 'Done Reordering' : 'Reorder Pages',
            onPressed: () {
              setState(() => _isReorderMode = !_isReorderMode);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  duration: const Duration(seconds: 2),
                  content: Text(_isReorderMode ? 'Drag pages to reorder' : 'Page order saved'),
                ),
              );
            },
          ),
          if (_isGeneratingPdf)
            const Center(child: Padding(padding: EdgeInsets.symmetric(horizontal: 12), child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF00ACC1)))))
          else
            IconButton(
              icon: const Icon(Icons.picture_as_pdf, color: Colors.white),
              tooltip: 'PDF',
              onPressed: _sharePdf,
            ),
          IconButton(
            icon: const Icon(Icons.share, color: Colors.white),
            tooltip: 'Share',
            onPressed: _showShareSheet,
          ),
          IconButton(
            icon: const Icon(Icons.more_vert, color: Colors.white),
            tooltip: 'More Options',
            onPressed: _showCamScannerMoreMenu,
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: _isReorderMode
            ? ReorderableListView.builder(
                buildDefaultDragHandles: false,
                itemCount: _doc.pagePaths.length,
                onReorder: _handleReorder,
                itemBuilder: (context, index) => _buildReorderablePageTile(index),
              )
            : GridView.builder(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 14,
                  mainAxisSpacing: 14,
                  childAspectRatio: 0.75,
                ),
                itemCount: _doc.pagePaths.length + 1,
                itemBuilder: (context, index) {
                  if (index < _doc.pagePaths.length) {
                    return _buildPageCard(index);
                  }
                  return InkWell(
                    borderRadius: BorderRadius.circular(6),
                    onTap: () {
                      context.push('/scanner', extra: _doc.id);
                    },
                    child: Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E1E1E),
                        border: Border.all(color: Colors.white24),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.camera_alt_outlined, color: Colors.white54, size: 36),
                            SizedBox(height: 8),
                            Text('Tap to add pages', style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w500)),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: const Color(0xFF00ACC1),
        onPressed: () {
          context.push('/scanner', extra: _doc.id);
        },
        child: const Icon(Icons.camera_alt, color: Colors.white, size: 28),
      ),
    );
  }
}
