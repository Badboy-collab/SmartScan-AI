import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image/image.dart' as img;
import 'package:share_plus/share_plus.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/theme/app_theme.dart';
import '../../domain/entities/scanned_document.dart';
import '../providers/document_provider.dart';
import '../../../scanner/domain/entities/document_filter_type.dart';
import '../../../scanner/domain/interfaces/i_document_processor.dart';
import '../../../conversion/presentation/pages/document_conversion_page.dart';

class SinglePageViewerPage extends StatefulWidget {
  final ScannedDocument document;
  final int initialPageIndex;

  const SinglePageViewerPage({
    super.key,
    required this.document,
    this.initialPageIndex = 0,
  });

  @override
  State<SinglePageViewerPage> createState() => _SinglePageViewerPageState();
}

class _SinglePageViewerPageState extends State<SinglePageViewerPage> {
  late ScannedDocument _doc;
  late int _currentPageIndex;
  late PageController _pageController;
  bool _dontAskAgainCrop = false;
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    _doc = widget.document;
    _currentPageIndex = widget.initialPageIndex.clamp(0, _doc.pagePaths.length - 1);
    _pageController = PageController(initialPage: _currentPageIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _onCropPressed() {
    if (_dontAskAgainCrop) {
      _navigateToCrop();
    } else {
      _showCropWarningDialog();
    }
  }

  void _showCropWarningDialog() {
    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF2A2A2A),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              title: const Text('Note', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'This action may clear all the recognition results, annotations, watermarks and signatures. Do you want to continue?',
                    style: TextStyle(color: Colors.white70, fontSize: 14, height: 1.4),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Checkbox(
                        value: _dontAskAgainCrop,
                        activeColor: AppColors.primaryLight,
                        onChanged: (val) {
                          setDialogState(() => _dontAskAgainCrop = val ?? false);
                          setState(() => _dontAskAgainCrop = val ?? false);
                        },
                      ),
                      const Text("Don't ask me again", style: TextStyle(color: Colors.white60, fontSize: 13)),
                    ],
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
                ),
                TextButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    _navigateToCrop();
                  },
                  child: const Text('OK', style: TextStyle(color: AppColors.primaryLight, fontWeight: FontWeight.bold)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _navigateToCrop() async {
    try {
      // Load raw uncropped image if available, else current page
      final rawPath = _doc.rawPagePaths.length > _currentPageIndex
          ? _doc.rawPagePaths[_currentPageIndex]
          : _doc.pagePaths[_currentPageIndex];

      final file = File(rawPath);
      if (!await file.exists()) return;
      final bytes = await file.readAsBytes();

      if (mounted) {
        context.push('/scan_crop', extra: {
          'imageBytes': bytes,
          'targetDocumentId': _doc.id,
          'targetPageIndex': _currentPageIndex,
          'rotation': 0,
        }).then((_) {
          // Refresh doc on return
          final provider = getIt<DocumentProvider>();
          final updated = provider.documents.firstWhere((d) => d.id == _doc.id, orElse: () => _doc);
          setState(() {
            _doc = updated;
          });
        });
      }
    } catch (e) {
      debugPrint('[SinglePageViewer] Error opening crop: $e');
    }
  }

  Future<void> _rotateCurrentPage() async {
    if (_isProcessing) return;
    setState(() => _isProcessing = true);

    try {
      final currentPath = _doc.pagePaths[_currentPageIndex];
      final bytes = await File(currentPath).readAsBytes();
      final decoded = img.decodeImage(bytes);

      if (decoded != null) {
        final rotated = img.copyRotate(decoded, angle: 90);
        final rotatedBytes = Uint8List.fromList(img.encodeJpg(rotated, quality: 95));

        final provider = getIt<DocumentProvider>();
        final updatedDoc = await provider.updateExistingPage(_doc.id, _currentPageIndex, rotatedBytes);

        if (updatedDoc != null && mounted) {
          setState(() {
            _doc = updatedDoc;
            _isProcessing = false;
          });
        }
      }
    } catch (e) {
      debugPrint('[Rotate] Error: $e');
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  void _shareCurrentPage() {
    final path = _doc.pagePaths[_currentPageIndex];
    Share.shareXFiles([XFile(path)], text: '${_doc.name} - Page ${_currentPageIndex + 1}');
  }

  Future<void> _showEnhanceSheet() async {
    final rawPath = _doc.rawPagePaths.length > _currentPageIndex
        ? _doc.rawPagePaths[_currentPageIndex]
        : _doc.pagePaths[_currentPageIndex];

    final file = File(rawPath);
    if (!await file.exists()) return;
    final masterBytes = await file.readAsBytes();

    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).cardColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16.0, horizontal: 8.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Enhance Document',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildFilterOption(ctx, 'Original', Icons.image_outlined, masterBytes, DocumentFilterType.original),
                      _buildFilterOption(ctx, 'Auto', Icons.auto_fix_high, masterBytes, DocumentFilterType.auto),
                      _buildFilterOption(ctx, 'Lighten', Icons.brightness_6, masterBytes, DocumentFilterType.lighten),
                      _buildFilterOption(ctx, 'Magic', Icons.auto_awesome, masterBytes, DocumentFilterType.magic),
                      _buildFilterOption(ctx, 'Grayscale', Icons.filter_b_and_w, masterBytes, DocumentFilterType.grayscale),
                      _buildFilterOption(ctx, 'B&W', Icons.contrast, masterBytes, DocumentFilterType.blackAndWhite),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildFilterOption(BuildContext ctx, String name, IconData icon, Uint8List masterBytes, DocumentFilterType filter) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () async {
        Navigator.pop(ctx);
        setState(() => _isProcessing = true);
        try {
          final processor = getIt<IDocumentProcessor>();
          final enhanced = await processor.applyFilter(masterBytes, filter);
          final provider = getIt<DocumentProvider>();
          final updatedDoc = await provider.updateExistingPage(_doc.id, _currentPageIndex, enhanced);
          if (updatedDoc != null && mounted) {
            setState(() {
              _doc = updatedDoc;
              _isProcessing = false;
            });
          }
        } catch (e) {
          debugPrint('Enhance error: $e');
          if (mounted) setState(() => _isProcessing = false);
        }
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 6.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.teal.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: Colors.teal, size: 24),
            ),
            const SizedBox(height: 6),
            Text(name, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
          ],
        ),
      ),
    );
  }

  void _showExportOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).cardColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Convert & Export Document', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),
                ListTile(
                  leading: const Icon(Icons.table_chart, color: Color(0xFF107C41), size: 28),
                  title: const Text('Convert to Excel (.xlsx)', style: TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: const Text('Extracts table grids into real spreadsheet cells'),
                  onTap: () {
                    Navigator.pop(ctx);
                    context.push('/convert_document', extra: {
                      'document': _doc,
                      'format': ExportFormatType.excel,
                    });
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.description, color: Color(0xFF185ABD), size: 28),
                  title: const Text('Convert to Word (.docx)', style: TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: const Text('Reconstructs paragraphs, titles & tables'),
                  onTap: () {
                    Navigator.pop(ctx);
                    context.push('/convert_document', extra: {
                      'document': _doc,
                      'format': ExportFormatType.word,
                    });
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.slideshow, color: Color(0xFFC43E1C), size: 28),
                  title: const Text('Convert to PowerPoint (.pptx)', style: TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: const Text('Creates editable 16:9 presentation slides'),
                  onTap: () {
                    Navigator.pop(ctx);
                    context.push('/convert_document', extra: {
                      'document': _doc,
                      'format': ExportFormatType.powerpoint,
                    });
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final String pageTitle = '${(_currentPageIndex + 1).toString().padLeft(2, '0')}';

    return Scaffold(
      backgroundColor: const Color(0xFFE9ECEF), // Clean light paper background
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 1,
        foregroundColor: Colors.black87,
        iconTheme: const IconThemeData(color: Colors.black87),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black87),
          onPressed: () => context.pop(),
        ),
        title: Column(
          children: [
            Text(pageTitle, style: const TextStyle(color: Colors.black87, fontSize: 18, fontWeight: FontWeight.bold)),
            Text('${_currentPageIndex + 1}/${_doc.pagePaths.length}', style: const TextStyle(fontSize: 12, color: Colors.black54)),
          ],
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.crop, color: Colors.teal, size: 24),
            tooltip: 'Re-crop Page',
            onPressed: _onCropPressed,
          ),
          IconButton(
            icon: const Icon(Icons.file_download_outlined, color: Colors.teal, size: 24),
            tooltip: 'Convert / Export',
            onPressed: _showExportOptions,
          ),
          IconButton(
            icon: const Icon(Icons.share, color: Colors.black87),
            tooltip: 'Share',
            onPressed: _shareCurrentPage,
          ),
        ],
      ),
      body: Stack(
        children: [
          PageView.builder(
            controller: _pageController,
            itemCount: _doc.pagePaths.length,
            onPageChanged: (index) => setState(() => _currentPageIndex = index),
            itemBuilder: (context, index) {
              final path = _doc.pagePaths[index];
              return InteractiveViewer(
                minScale: 0.8,
                maxScale: 5.0,
                child: Center(
                  child: Container(
                    margin: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(4),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.15),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Image.file(
                      File(path),
                      fit: BoxFit.contain,
                      key: ValueKey('${path}_${File(path).existsSync() ? File(path).lastModifiedSync().millisecondsSinceEpoch : 0}'),
                    ),
                  ),
                ),
              );
            },
          ),
          if (_isProcessing)
            Container(
              color: Colors.black26,
              child: const Center(
                child: CircularProgressIndicator(color: AppColors.primaryLight),
              ),
            ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 6,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildBottomButton(Icons.crop, 'Crop', _onCropPressed),
              _buildBottomButton(Icons.rotate_right, 'Rotate', _rotateCurrentPage),
              _buildBottomButton(Icons.auto_awesome, 'Enhance', _showEnhanceSheet),
              _buildBottomButton(Icons.text_fields, 'OCR / Text', () => context.push('/ocr')),
              _buildBottomButton(Icons.draw, 'Signature', () => context.push('/signature')),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBottomButton(IconData icon, String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.black87, size: 22),
            const SizedBox(height: 4),
            Text(label, style: const TextStyle(color: Colors.black87, fontSize: 11, fontWeight: FontWeight.w500)),
          ],
        ),
      ),
    );
  }
}
