import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image/image.dart' as img;
import '../../../../core/di/injection.dart';
import '../../domain/entities/document_corners.dart';
import '../../domain/interfaces/i_document_processor.dart';
import '../widgets/interactive_crop_overlay.dart';

class ScanCropPage extends StatefulWidget {
  final Uint8List originalImageBytes;
  final DocumentCorners? initialCorners;
  final int rotation;
  final String? targetDocumentId;
  final int? targetPageIndex;
  final int filterIndex;

  const ScanCropPage({
    super.key,
    required this.originalImageBytes,
    this.initialCorners,
    required this.rotation,
    this.targetDocumentId,
    this.targetPageIndex,
    this.filterIndex = 1, // DocumentFilterType.auto
  });

  @override
  State<ScanCropPage> createState() => _ScanCropPageState();
}

class _ScanCropPageState extends State<ScanCropPage> {
  final _processor = getIt<IDocumentProcessor>();
  bool _isProcessing = false;
  bool _isDetecting = false;
  late Uint8List _currentImageBytes;
  late DocumentCorners _currentCorners;
  int _renderKey = 0;
  
  @override
  void initState() {
    super.initState();
    _currentImageBytes = widget.originalImageBytes;
    _currentCorners = widget.initialCorners ?? DocumentCorners(
      topLeft: const Offset(0.05, 0.05),
      topRight: const Offset(0.95, 0.05),
      bottomRight: const Offset(0.95, 0.95),
      bottomLeft: const Offset(0.05, 0.95),
    );
    _autoDetectCorners();
  }

  Future<void> _autoDetectCorners() async {
    setState(() => _isDetecting = true);
    final corners = await _processor.detectCorners(_currentImageBytes);
    if (mounted) {
      setState(() {
        if (corners != null) _currentCorners = corners;
        _isDetecting = false;
      });
    }
  }

  Future<void> _rotateImage(int angleDelta) async {
    setState(() => _isProcessing = true);
    try {
      final rotatedBytes = await compute(_rotateBytesIso, {
        'bytes': _currentImageBytes,
        'angle': angleDelta,
      });

      DocumentCorners newCorners;
      if (angleDelta == 90) {
        // 90 deg CW: (x, y) -> (1 - y, x)
        newCorners = DocumentCorners(
          topLeft: Offset(1 - _currentCorners.bottomLeft.dy, _currentCorners.bottomLeft.dx),
          topRight: Offset(1 - _currentCorners.topLeft.dy, _currentCorners.topLeft.dx),
          bottomRight: Offset(1 - _currentCorners.topRight.dy, _currentCorners.topRight.dx),
          bottomLeft: Offset(1 - _currentCorners.bottomRight.dy, _currentCorners.bottomRight.dx),
        );
      } else {
        // -90 deg (270 deg CW): (x, y) -> (y, 1 - x)
        newCorners = DocumentCorners(
          topLeft: Offset(_currentCorners.topRight.dy, 1 - _currentCorners.topRight.dx),
          topRight: Offset(_currentCorners.bottomRight.dy, 1 - _currentCorners.bottomRight.dx),
          bottomRight: Offset(_currentCorners.bottomLeft.dy, 1 - _currentCorners.bottomLeft.dx),
          bottomLeft: Offset(_currentCorners.topLeft.dy, 1 - _currentCorners.topLeft.dx),
        );
      }

      if (mounted) {
        setState(() {
          _currentImageBytes = rotatedBytes;
          _currentCorners = newCorners;
          _renderKey++;
        });
      }
    } catch (e) {
      debugPrint("Rotate error: $e");
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _processAndGoNext() async {
    setState(() => _isProcessing = true);
    try {
      final croppedBytes = await _processor.cropAndCorrectPerspective(
        imageBytes: _currentImageBytes,
        corners: _currentCorners,
        rotationDegrees: 0,
      );
      
      if (mounted) {
        context.push('/scan_preview', extra: {
          'imageBytes': croppedBytes,
          'rawCapturedBytes': _currentImageBytes,
          'corners': DocumentCorners(
            topLeft: const Offset(0,0), topRight: const Offset(1,0),
            bottomRight: const Offset(1,1), bottomLeft: const Offset(0,1),
          ),
          'rotation': 0,
          'filter': widget.filterIndex,
          'targetDocumentId': widget.targetDocumentId,
          'targetPageIndex': widget.targetPageIndex,
        });
      }
    } catch (e) {
      debugPrint("Crop error: $e");
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
          'Are you sure you want to discard this captured image? Your current scan will not be saved.',
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
        backgroundColor: const Color(0xFF1E1E1E),
        appBar: AppBar(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          title: const Text('Adjust Crop'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () async {
              final shouldDiscard = await _showDiscardConfirmationDialog();
              if (shouldDiscard && context.mounted) {
                context.pop();
              }
            },
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.auto_awesome),
              tooltip: 'Auto Detect',
              onPressed: _isProcessing ? null : _autoDetectCorners,
            )
          ],
        ),
        body: Stack(
          children: [
            InteractiveCropOverlay(
              key: ValueKey(_renderKey),
              imageBytes: _currentImageBytes,
              initialCorners: _currentCorners,
              onCornersChanged: (corners) {
                _currentCorners = corners;
              },
            ),
            if (_isDetecting || _isProcessing)
              Container(
                color: Colors.black54,
                child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(color: Colors.teal),
                    const SizedBox(height: 16),
                    Text(_isDetecting ? 'Detecting document...' : 'Processing...', 
                      style: const TextStyle(color: Colors.white)),
                  ],
                ),
              ),
            ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Container(
          color: Colors.black,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildBottomAction(Icons.rotate_left, 'Left', () => _rotateImage(-90)),
              _buildBottomAction(Icons.rotate_right, 'Right', () => _rotateImage(90)),
              _buildBottomAction(Icons.select_all, 'All', () {
                setState(() {
                  _currentCorners = DocumentCorners(
                    topLeft: const Offset(0, 0),
                    topRight: const Offset(1, 0),
                    bottomRight: const Offset(1, 1),
                    bottomLeft: const Offset(0, 1),
                  );
                  _renderKey++;
                });
              }),
              ElevatedButton(
                onPressed: _isDetecting || _isProcessing ? null : _processAndGoNext,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.teal,
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Next', style: TextStyle(color: Colors.white)),
                    SizedBox(width: 8),
                    Icon(Icons.arrow_forward, color: Colors.white, size: 16),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

  Widget _buildBottomAction(IconData icon, String label, VoidCallback onTap) {
    return InkWell(
      onTap: _isProcessing ? null : onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 24),
          const SizedBox(height: 4),
          Text(label, style: const TextStyle(color: Colors.white70, fontSize: 10)),
        ],
      ),
    );
  }
}

Uint8List _rotateBytesIso(Map<String, dynamic> args) {
  final Uint8List bytes = args['bytes'];
  final int angle = args['angle'];
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return bytes;
  final effectiveAngle = angle < 0 ? (360 + angle) : angle;
  final rotated = img.copyRotate(decoded, angle: effectiveAngle);
  return Uint8List.fromList(img.encodeJpg(rotated, quality: 95));
}
