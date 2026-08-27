import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/di/injection.dart';
import '../../domain/entities/document_corners.dart';
import '../../domain/entities/document_filter_type.dart';
import '../../domain/interfaces/i_document_processor.dart';
import '../../../documents/domain/entities/scanned_document.dart';
import '../../../documents/presentation/providers/document_provider.dart';

class ScanPreviewPage extends StatefulWidget {
  final Uint8List originalImageBytes; // The pre-cropped bytes
  final Uint8List? rawCapturedBytes; // The raw uncropped original photo
  final DocumentCorners initialCorners; // Unused, just for signature compatibility
  final int rotation; // Unused

  final String? targetDocumentId;
  final int? targetPageIndex;
  final int initialFilterIndex;

  const ScanPreviewPage({
    super.key,
    required this.originalImageBytes,
    this.rawCapturedBytes,
    required this.initialCorners,
    required this.rotation,
    this.targetDocumentId,
    this.targetPageIndex,
    this.initialFilterIndex = 1, // DocumentFilterType.auto
  });

  @override
  State<ScanPreviewPage> createState() => _ScanPreviewPageState();
}

class _ScanPreviewPageState extends State<ScanPreviewPage> with SingleTickerProviderStateMixin {
  final _processor = getIt<IDocumentProcessor>();
  late final TextEditingController _nameController;

  DocumentFilterType _currentFilter = DocumentFilterType.auto;
  Uint8List? _filteredBytes;
  bool _isProcessing = false;
  
  // Magic Laser Sweep Animation
  late AnimationController _sweepController;
  late Animation<double> _sweepAnimation;
  bool _isSweeping = true;

  // Cache for thumbnails
  final Map<DocumentFilterType, Uint8List> _thumbnailCache = {};

  @override
  void initState() {
    super.initState();
    final docProvider = getIt<DocumentProvider>();
    _nameController = TextEditingController(text: docProvider.generateDefaultDocumentName());
    _filteredBytes = widget.originalImageBytes;

    _sweepController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );

    _sweepAnimation = CurvedAnimation(
      parent: _sweepController,
      curve: Curves.easeInOutCubic,
    );

    _sweepAnimation.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        if (mounted) setState(() => _isSweeping = false);
      }
    });

    _initMagicEnhancement();
  }

  @override
  void dispose() {
    _sweepController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _initMagicEnhancement() async {
    // 1. First apply the filter chosen on the camera screen (default: Auto)
    final int idx = widget.initialFilterIndex.clamp(0, DocumentFilterType.values.length - 1);
    final DocumentFilterType initialFilter = DocumentFilterType.values[idx];
    final enhanced = await _processor.applyFilter(widget.originalImageBytes, initialFilter);
    if (mounted) {
      setState(() {
        _filteredBytes = enhanced;
        _currentFilter = initialFilter;
      });
      // 2. Play the signature Laser Sweep animation
      _sweepController.forward(from: 0.0);
    }
    // 3. Generate thumbnail previews
    _generateThumbnails();
  }

  Future<void> _generateThumbnails() async {
    for (final type in DocumentFilterType.values) {
      try {
        final thumb = await _processor.applyFilter(widget.originalImageBytes, type);
        if (mounted) {
          setState(() {
            _thumbnailCache[type] = thumb;
          });
        }
      } catch (_) {}
    }
  }

  Future<void> _applyFilter(DocumentFilterType filterType) async {
    if (_currentFilter == filterType) return;
    
    setState(() {
      _currentFilter = filterType;
      _isProcessing = true;
      _isSweeping = true;
    });

    final bytes = await _processor.applyFilter(widget.originalImageBytes, filterType);
    
    if (mounted) {
      setState(() {
        _filteredBytes = bytes;
        _isProcessing = false;
      });
      _sweepController.forward(from: 0.0);
    }
  }

  Future<void> _saveAndFinish() async {
    setState(() => _isProcessing = true);
    try {
      final docProvider = getIt<DocumentProvider>();
      if (widget.targetDocumentId != null && widget.targetPageIndex != null) {
        // Re-edit existing page
        final updatedDoc = await docProvider.updateExistingPage(
          widget.targetDocumentId!,
          widget.targetPageIndex!,
          _filteredBytes!,
        );
        if (mounted && updatedDoc != null) {
          context.pushReplacement('/document_viewer', extra: updatedDoc);
        }
      } else if (widget.targetDocumentId != null) {
        // Add new page to existing document
        final updatedDoc = await docProvider.addPageToDocument(
          widget.targetDocumentId!,
          _filteredBytes!,
          rawImageBytes: widget.rawCapturedBytes,
        );
        if (mounted && updatedDoc != null) {
          context.pushReplacement('/document_viewer', extra: updatedDoc);
        }
      } else {
        // Create new document
        await docProvider.saveNewDocument(
          _filteredBytes!,
          rawImageBytes: widget.rawCapturedBytes,
          customName: _nameController.text.trim().isNotEmpty ? _nameController.text.trim() : null,
        );
        final newDoc = docProvider.documents.first;
        if (mounted) {
          context.pushReplacement('/document_viewer', extra: newDoc);
        }
      }
    } catch (e) {
      debugPrint('Save error: $e');
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<bool> _showDiscardConfirmationDialog() async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF262626),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Color(0xFFFFB020), size: 24),
            SizedBox(width: 10),
            Text(
              'Discard Scan?',
              style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: const Text(
          'Are you sure you want to discard this document? Any unsaved edits and scans will be lost.',
          style: TextStyle(color: Colors.white70, fontSize: 14, height: 1.4),
        ),
        actionsPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Keep', style: TextStyle(color: Color(0xFF00FFC6), fontSize: 15, fontWeight: FontWeight.w600)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFE53935),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Discard', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final shouldDiscard = await _showDiscardConfirmationDialog();
        if (shouldDiscard && context.mounted) {
          context.pop();
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF1E1E1E), // Dark background for preview
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          foregroundColor: Colors.white,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () async {
              final shouldDiscard = await _showDiscardConfirmationDialog();
              if (shouldDiscard && context.mounted) {
                context.pop();
              }
            },
          ),
          title: TextField(
            controller: _nameController,
            style: const TextStyle(color: Colors.white, fontSize: 18),
            decoration: const InputDecoration(
              border: InputBorder.none,
              hintText: 'Document Name',
              hintStyle: TextStyle(color: Colors.white54),
            ),
          ),
        ),
        body: Column(
          children: [
            // Preview Area with Magic Laser Sweep
            Expanded(
            child: Stack(
              alignment: Alignment.center,
              children: [
                InteractiveViewer(
                  minScale: 1.0,
                  maxScale: 5.0,
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Container(
                        decoration: BoxDecoration(
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.5),
                              blurRadius: 10,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            return AnimatedBuilder(
                              animation: _sweepAnimation,
                              builder: (context, child) {
                                final isFinished = !_isSweeping || _sweepAnimation.value >= 1.0;

                                if (isFinished || _filteredBytes == null) {
                                  return Image.memory(
                                    _filteredBytes ?? widget.originalImageBytes,
                                    fit: BoxFit.contain,
                                  );
                                }

                                return Stack(
                                  children: [
                                    // 1. Bottom Layer: Original raw cropped image
                                    Image.memory(
                                      widget.originalImageBytes,
                                      fit: BoxFit.contain,
                                    ),

                                    // 2. Top Layer: Revealed Magic Enhanced image clipped from top
                                    ClipRect(
                                      clipper: _TopDownClipper(_sweepAnimation.value),
                                      child: Image.memory(
                                        _filteredBytes!,
                                        fit: BoxFit.contain,
                                      ),
                                    ),

                                    // 3. Glowing Emerald Laser Line sweeping down
                                    Positioned.fill(
                                      child: Align(
                                        alignment: Alignment(0, (_sweepAnimation.value * 2.0) - 1.0),
                                        child: Container(
                                          height: 4,
                                          decoration: BoxDecoration(
                                            gradient: const LinearGradient(
                                              colors: [
                                                Colors.transparent,
                                                Color(0xFF00FFC6),
                                                Colors.white,
                                                Color(0xFF00FFC6),
                                                Colors.transparent,
                                              ],
                                            ),
                                            boxShadow: [
                                              BoxShadow(
                                                color: const Color(0xFF00FFC6).withOpacity(0.9),
                                                blurRadius: 12,
                                                spreadRadius: 3,
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                );
                              },
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                ),
                if (_isProcessing)
                  Container(
                    color: Colors.black54,
                    child: const Center(
                      child: CircularProgressIndicator(color: Colors.teal),
                    ),
                  ),
              ],
            ),
          ),
          
          // Filters Bar
          Container(
            height: 100,
            color: Colors.black87,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
              itemCount: DocumentFilterType.values.length,
              itemBuilder: (context, index) {
                final filter = DocumentFilterType.values[index];
                return _buildFilterThumbnail(filter);
              },
            ),
          ),

          // Bottom Action Bar
          Container(
            color: Colors.black,
            padding: const EdgeInsets.only(bottom: 24, top: 12, left: 16, right: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildBottomAction(Icons.crop, 'Crop', () {
                   context.pop(); // Go back to scan_crop_page
                }),
                _buildBottomAction(Icons.text_fields, 'To Text', () {
                   context.push('/ocr');
                }),
                _buildBottomAction(Icons.draw, 'Signature', () {
                   context.push('/signature');
                }),
                
                // Save Button
                FloatingActionButton(
                  onPressed: _isProcessing ? null : _saveAndFinish,
                  backgroundColor: Colors.teal,
                  elevation: 0,
                  child: const Icon(Icons.check, color: Colors.white, size: 28),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

  Widget _buildFilterThumbnail(DocumentFilterType filter) {
    final isSelected = _currentFilter == filter;
    final thumbBytes = _thumbnailCache[filter];

    return GestureDetector(
      onTap: () => _applyFilter(filter),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 8),
        child: Column(
          children: [
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                border: Border.all(
                  color: isSelected ? Colors.teal : Colors.transparent,
                  width: 2,
                ),
                borderRadius: BorderRadius.circular(4),
              ),
              child: thumbBytes == null
                  ? const Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.teal)))
                  : Image.memory(thumbBytes, fit: BoxFit.cover),
            ),
            const SizedBox(height: 4),
            Text(
              filter.name.toUpperCase(),
              style: TextStyle(
                color: isSelected ? Colors.teal : Colors.white70,
                fontSize: 10,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomAction(IconData icon, String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white, size: 24),
            const SizedBox(height: 4),
            Text(label, style: const TextStyle(color: Colors.white70, fontSize: 10)),
          ],
        ),
      ),
    );
  }
}

class _TopDownClipper extends CustomClipper<Rect> {
  final double progress;

  _TopDownClipper(this.progress);

  @override
  Rect getClip(Size size) {
    return Rect.fromLTWH(0, 0, size.width, size.height * progress.clamp(0.0, 1.0));
  }

  @override
  bool shouldReclip(_TopDownClipper oldClipper) {
    return oldClipper.progress != progress;
  }
}
