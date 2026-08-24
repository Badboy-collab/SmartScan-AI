import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'package:uuid/uuid.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../documents/domain/entities/scanned_document.dart';
import '../../../documents/presentation/providers/document_provider.dart';
import '../../../scanner/domain/entities/document_corners.dart';
import '../../../scanner/domain/entities/document_filter_type.dart';
import '../../../scanner/domain/interfaces/i_document_processor.dart';

class IDCardScannerPage extends StatefulWidget {
  const IDCardScannerPage({super.key});

  @override
  State<IDCardScannerPage> createState() => _IDCardScannerPageState();
}

class _IDCardScannerPageState extends State<IDCardScannerPage> {
  CameraController? _cameraController;
  List<CameraDescription> _cameras = [];
  bool _isCameraInitialized = false;

  int _step = 1; // 1: Front, 2: Back, 3: Assembling
  Uint8List? _frontImageBytes;
  Uint8List? _backImageBytes;
  bool _isProcessing = false;

  final _processor = getIt<IDocumentProcessor>();

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  Future<void> _initCamera() async {
    _cameras = await availableCameras();
    if (_cameras.isEmpty) return;

    _cameraController = CameraController(
      _cameras.first,
      ResolutionPreset.veryHigh,
      enableAudio: false,
    );

    await _cameraController!.initialize();
    if (mounted) {
      setState(() => _isCameraInitialized = true);
    }
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    super.dispose();
  }

  Future<void> _captureCard() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized || _isProcessing) return;

    setState(() => _isProcessing = true);
    try {
      final XFile rawFile = await _cameraController!.takePicture();
      final bytes = await rawFile.readAsBytes();

      // Process card: Auto crop and enhance
      final corners = await _processor.detectCorners(bytes) ?? DocumentCorners(
        topLeft: const Offset(0.1, 0.2),
        topRight: const Offset(0.9, 0.2),
        bottomRight: const Offset(0.9, 0.8),
        bottomLeft: const Offset(0.1, 0.8),
      );

      final cropped = await _processor.cropAndCorrectPerspective(
        imageBytes: bytes,
        corners: corners,
        rotationDegrees: 0,
      );

      final enhanced = await _processor.applyFilter(cropped, DocumentFilterType.magic);

      if (_step == 1) {
        setState(() {
          _frontImageBytes = enhanced;
          _step = 2;
          _isProcessing = false;
        });
      } else if (_step == 2) {
        setState(() {
          _backImageBytes = enhanced;
          _step = 3;
        });
        await _assembleA4Sheet();
      }
    } catch (e) {
      debugPrint('[IDCard] Error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Processing error: $e')));
        setState(() => _isProcessing = false);
      }
    }
  }

  Future<void> _assembleA4Sheet() async {
    if (_frontImageBytes == null || _backImageBytes == null) return;

    try {
      // Create A4 canvas (2480 x 3508 at 300 DPI or 1240 x 1754 at 150 DPI)
      const a4Width = 1240;
      const a4Height = 1754;
      final canvas = img.Image(width: a4Width, height: a4Height);
      img.fill(canvas, color: img.ColorRgb8(255, 255, 255)); // Clean white A4 paper

      final frontDecoded = img.decodeImage(_frontImageBytes!);
      final backDecoded = img.decodeImage(_backImageBytes!);

      if (frontDecoded != null && backDecoded != null) {
        // Standard ID card size proportion: ~86mm x 54mm -> Width: 860px, Height: 540px
        const cardTargetW = 860;
        const cardTargetH = 540;

        final frontResized = img.copyResize(frontDecoded, width: cardTargetW, height: cardTargetH);
        final backResized = img.copyResize(backDecoded, width: cardTargetW, height: cardTargetH);

        // Draw subtle border around cards
        img.drawRect(canvas, 
          x1: (a4Width - cardTargetW) ~/ 2 - 2, 
          y1: 200 - 2, 
          x2: (a4Width + cardTargetW) ~/ 2 + 2, 
          y2: 200 + cardTargetH + 2, 
          color: img.ColorRgb8(220, 220, 220));

        img.drawRect(canvas, 
          x1: (a4Width - cardTargetW) ~/ 2 - 2, 
          y1: 900 - 2, 
          x2: (a4Width + cardTargetW) ~/ 2 + 2, 
          y2: 900 + cardTargetH + 2, 
          color: img.ColorRgb8(220, 220, 220));

        // Composite Front card (Top half)
        img.compositeImage(canvas, frontResized, dstX: (a4Width - cardTargetW) ~/ 2, dstY: 200);

        // Composite Back card (Bottom half)
        img.compositeImage(canvas, backResized, dstX: (a4Width - cardTargetW) ~/ 2, dstY: 900);

        // Save generated A4 sheet
        final dir = await getApplicationDocumentsDirectory();
        final docId = const Uuid().v4();
        final filePath = '${dir.path}/id_card_$docId.jpg';
        await File(filePath).writeAsBytes(img.encodeJpg(canvas, quality: 95));

        final now = DateTime.now();
        final doc = ScannedDocument(
          id: docId,
          name: 'ID Card ${now.month}-${now.day}-${now.year}',
          createdAt: now,
          updatedAt: now,
          pagePaths: [filePath],
          thumbnailPath: filePath,
          dirPath: dir.path,
        );

        final provider = getIt<DocumentProvider>();
        await provider.addDocument(doc);

        if (mounted) {
          context.pushReplacement('/document_viewer', extra: doc);
        }
      }
    } catch (e) {
      debugPrint('[IDCard] Assembly Error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Save error: $e')));
        setState(() => _isProcessing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_isCameraInitialized || _cameraController == null) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator(color: AppColors.primaryLight)),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Colors.white,
        title: Text(_step == 1 ? 'Scan ID Card (Front)' : 'Scan ID Card (Back)'),
      ),
      body: Stack(
        children: [
          // 1. Camera Viewfinder
          Center(
            child: CameraPreview(_cameraController!),
          ),

          // 2. ID Card Guide Outline
          Center(
            child: Container(
              width: MediaQuery.of(context).size.width * 0.88,
              height: (MediaQuery.of(context).size.width * 0.88) * (54.0 / 85.6),
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.primaryLight, width: 2.5),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Stack(
                children: [
                  Positioned(
                    top: 12,
                    left: 12,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        _step == 1 ? '1. Fit FRONT side inside frame' : '2. Fit BACK side inside frame',
                        style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // 3. Processing Overlay
          if (_isProcessing || _step == 3)
            Container(
              color: Colors.black87,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: AppColors.primaryLight),
                    const SizedBox(height: 16),
                    Text(
                      _step == 3 ? 'Combining Front & Back onto A4 Sheet...' : 'Optimizing ID card...',
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                    ),
                  ],
                ),
              ),
            ),

          // 4. Capture Controls
          Positioned(
            bottom: 30,
            left: 0,
            right: 0,
            child: Center(
              child: GestureDetector(
                onTap: _isProcessing ? null : _captureCard,
                child: Container(
                  width: 76,
                  height: 76,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 4),
                    color: AppColors.primaryLight,
                  ),
                  child: const Icon(Icons.camera_alt, color: Colors.white, size: 36),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
