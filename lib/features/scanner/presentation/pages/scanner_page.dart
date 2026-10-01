import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
import 'package:image/image.dart' as img;
import 'package:permission_handler/permission_handler.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/app_settings.dart';
import '../../../../core/utils/import_utils.dart';
import '../../domain/entities/document_filter_type.dart';

class ScannerPage extends StatefulWidget {
  final String? targetDocumentId;

  const ScannerPage({super.key, this.targetDocumentId});

  @override
  State<ScannerPage> createState() => _ScannerPageState();
}

class _ScannerPageState extends State<ScannerPage> with WidgetsBindingObserver {
  CameraController? _cameraController;
  List<CameraDescription> _cameras = [];
  bool _isCameraInitialized = false;
  PermissionStatus _permissionStatus = PermissionStatus.denied;
  FlashMode _flashMode = FlashMode.off;
  int _selectedCameraIndex = 0;

  // Scan color filter chosen before capture (applied on the preview page)
  DocumentFilterType _scanFilter = DocumentFilterType.auto;
  bool _showGrid = false;

  // Tap-to-focus feedback ring
  final GlobalKey _previewKey = GlobalKey();
  Offset? _focusRingOffset;
  Timer? _focusRingTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkPermissionAndInitCamera();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _focusRingTimer?.cancel();
    _turnOffFlash();
    _cameraController?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final CameraController? cameraController = _cameraController;
    if (cameraController == null || !cameraController.value.isInitialized) return;

    if (state == AppLifecycleState.inactive || state == AppLifecycleState.paused) {
      _turnOffFlash();
      cameraController.dispose();
      _cameraController = null;
      if (mounted) {
        setState(() {
          _isCameraInitialized = false;
        });
      }
    } else if (state == AppLifecycleState.resumed) {
      _checkPermissionAndInitCamera();
    }
  }

  Future<void> _checkPermissionAndInitCamera() async {
    final status = await Permission.camera.request();
    if (mounted) setState(() => _permissionStatus = status);
    if (!status.isGranted) return;
    // Restore the remembered camera choices *before* the camera is created, so
    // the viewfinder comes back exactly how the user left it.
    await _loadPreferences();
    await _initCamera();
  }

  /// Restores the saved flash mode and capture quality.
  Future<void> _loadPreferences() async {
    _flashMode = await AppSettings.flashMode();
    _isHdEnabled = await AppSettings.hdCapture();
    if (mounted) setState(() {});
  }

  Future<void> _initCamera() async {
    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty) return;
      // `availableCameras()` order is platform/sensor dependent, so index 0 can
      // be the front camera or an auxiliary lens (which has a tiny sensor and no
      // flash). Always start on a rear camera.
      if (_cameras[_selectedCameraIndex].lensDirection !=
          CameraLensDirection.back) {
        final backIndex = _cameras.indexWhere(
          (c) => c.lensDirection == CameraLensDirection.back,
        );
        if (backIndex >= 0) _selectedCameraIndex = backIndex;
      }
      await _setCamera(_selectedCameraIndex);
    } catch (e) {
      debugPrint('Error initializing camera: $e');
    }
  }

  Future<void> _setCamera(int cameraIndex) async {
    if (_cameras.isEmpty) return;
    
    final previousController = _cameraController;
    final CameraController cameraController = CameraController(
      _cameras[cameraIndex],
      // `max` lets CameraX pick the sensor's highest available size for BOTH the
      // live preview and the captured file. Do NOT go back to `veryHigh`: that
      // preset is only 1080p (~2MP), which is what made the preview look blocky
      // and the scanned text soft on a high-megapixel phone.
      _isHdEnabled ? ResolutionPreset.max : ResolutionPreset.high,
      enableAudio: false,
    );

    if (previousController != null) {
      try {
        await previousController.setFlashMode(FlashMode.off);
      } catch (_) {}
    }
    await previousController?.dispose();

    if (mounted) setState(() => _cameraController = cameraController);

    try {
      await cameraController.initialize();
      // NOTE: keep the platform default focus mode (continuous AF on Android
      // camera2/CameraX) — calling setFocusMode here would switch it to a
      // one-shot auto focus and make captures blurrier. Use tap-to-focus instead.
      await _applyFlashMode(cameraController, _flashMode);
      if (mounted) {
        setState(() => _isCameraInitialized = true);
      }
    } catch (e) {
      debugPrint('Error initializing camera: $e');
    }
  }

  /// Re-creates the camera when the HD toggle changes the resolution preset.
  Future<void> _reinitCameraForResolution() async {
    if (_cameras.isEmpty) return;
    if (mounted) setState(() => _isCameraInitialized = false);
    await _setCamera(_selectedCameraIndex);
  }

  void _switchCamera() {
    if (_cameras.length > 1) {
      _selectedCameraIndex = (_selectedCameraIndex + 1) % _cameras.length;
      _isCameraInitialized = false;
      setState(() {});
      _setCamera(_selectedCameraIndex);
    }
  }

  /// Applies [mode] to [controller] without ever throwing.
  ///
  /// Some lenses (front, macro, depth) report no flash hardware and
  /// `setFlashMode` throws. Letting that escape aborted camera initialisation
  /// entirely, leaving the screen stuck on the loading spinner.
  Future<void> _applyFlashMode(CameraController controller, FlashMode mode) async {
    try {
      await controller.setFlashMode(mode);
    } catch (e) {
      debugPrint('Flash mode $mode is not supported by this camera: $e');
    }
  }

  Future<void> _selectFlashMode(FlashMode mode) async {
    final controller = _cameraController;
    if (controller == null || !controller.value.isInitialized) return;
    try {
      await controller.setFlashMode(mode);
      if (mounted) setState(() => _flashMode = mode);
      // Remembered so re-opening the camera starts on the same mode (torch
      // included) and nothing silently changes behind the user's back.
      await AppSettings.setFlashMode(mode);
    } catch (e) {
      debugPrint('Set flash mode error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Flash mode not supported on this camera'),
            duration: Duration(seconds: 1),
          ),
        );
      }
    }
  }

  void _toggleFlash() async {
    if (_cameraController == null) return;
    FlashMode nextMode;
    switch (_flashMode) {
      case FlashMode.off: nextMode = FlashMode.auto; break;
      case FlashMode.auto: nextMode = FlashMode.always; break;
      case FlashMode.always: nextMode = FlashMode.torch; break;
      case FlashMode.torch: nextMode = FlashMode.off; break;
    }
    _selectFlashMode(nextMode);
  }

  /// Safely turns the hardware flash/torch OFF (used on dispose, lifecycle
  /// pause, and camera switch, where the controller is being torn down anyway).
  /// Deliberately NOT called after a capture — see `_captureImage`.
  Future<void> _turnOffFlash() async {
    final controller = _cameraController;
    if (controller == null || !controller.value.isInitialized) return;
    try {
      await controller.setFlashMode(FlashMode.off);
    } catch (_) {}
  }

  /// Puts the physical LED out whenever the viewfinder leaves the screen.
  ///
  /// `FlashMode.torch` keeps the lamp lit continuously, so without this the torch
  /// burned for as long as the user stayed on the crop page. Only the hardware is
  /// switched off — `_flashMode` keeps the user's selection, which is re-applied
  /// as soon as the viewfinder is visible again.
  Future<void> _extinguishTorch() async {
    if (_flashMode != FlashMode.torch) return;
    await _turnOffFlash();
  }

  /// Maps a tap on the preview to a camera focus/exposure point and shows a ring.
  Future<void> _handleTapToFocus(TapDownDetails details) async {
    final controller = _cameraController;
    if (controller == null || !controller.value.isInitialized) return;

    final RenderBox? previewBox =
        _previewKey.currentContext?.findRenderObject() as RenderBox?;
    final RenderBox? pageBox = context.findRenderObject() as RenderBox?;
    if (previewBox == null || pageBox == null) return;

    final Size size = previewBox.size;
    if (size.width <= 0 || size.height <= 0) return;

    final Offset norm = Offset(
      (details.localPosition.dx / size.width).clamp(0.0, 1.0),
      (details.localPosition.dy / size.height).clamp(0.0, 1.0),
    );

    try {
      await controller.setFocusPoint(norm);
      await controller.setExposurePoint(norm);
    } catch (e) {
      debugPrint('Tap-to-focus error: $e');
    }

    final Offset ringPos =
        previewBox.localToGlobal(details.localPosition) -
            pageBox.localToGlobal(Offset.zero);
    _focusRingTimer?.cancel();
    if (mounted) setState(() => _focusRingOffset = ringPos);
    _focusRingTimer = Timer(const Duration(milliseconds: 700), () {
      if (mounted) setState(() => _focusRingOffset = null);
    });
  }

  bool _isCapturing = false;

  Future<void> _captureImage() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized || _isCapturing) return;
    
    setState(() => _isCapturing = true);
    HapticFeedback.lightImpact();

    try {
      final XFile image = await _cameraController!.takePicture();

      // NOTE: the user's flash selection is deliberately NOT reset here.
      // Forcing it back to `off` after every shot was exactly why the flash
      // choice appeared to change by itself while scanning.

      final rawBytes = await image.readAsBytes();

      // Put the LED out while the crop page covers the viewfinder; the
      // selection itself is kept and re-applied once we come back.
      await _extinguishTorch();

      if (mounted) {
        await context.push('/scan_crop', extra: {
          'imageBytes': rawBytes,
          'corners': null, // OpenCV runs in C++ in background isolate
          'rotation': 0,
          'filter': _scanFilter.index,
          'targetDocumentId': widget.targetDocumentId,
        });

        // Seamlessly restore the camera viewfinder when user pops back
        if (mounted) {
          setState(() => _isCapturing = false);
          if (_cameraController == null || !_cameraController!.value.isInitialized) {
            await _initCamera();
          } else {
            // Bring the remembered flash mode (torch included) back now that the
            // viewfinder is visible again.
            await _applyFlashMode(_cameraController!, _flashMode);
            setState(() => _isCameraInitialized = true);
          }
        }
      }
    } catch (e) {
      debugPrint('Error taking picture: $e');
    } finally {
      if (mounted) setState(() => _isCapturing = false);
    }
  }

  String _filterLabel(DocumentFilterType type) {
    switch (type) {
      case DocumentFilterType.original:
        return 'Original';
      case DocumentFilterType.auto:
        return 'Auto';
      case DocumentFilterType.lighten:
        return 'Lighten';
      case DocumentFilterType.magic:
        return 'Magic Color';
      case DocumentFilterType.grayscale:
        return 'Grayscale';
      case DocumentFilterType.blackAndWhite:
        return 'B&W';
    }
  }

  IconData _getFlashIcon() {
    switch (_flashMode) {
      case FlashMode.off: return Icons.flash_off;
      case FlashMode.auto: return Icons.flash_auto;
      case FlashMode.always: return Icons.flash_on;
      case FlashMode.torch: return Icons.highlight;
    }
  }

  // Scan Modes matching sc.jpg
  final List<String> _scanModes = [
    'To Text',
    'To Word',
    'To Excel',
    'Single',
    'Batch',
    'ID Card',
    'Book',
    'PPT',
  ];
  int _selectedModeIndex = 3; // Default 'Single'
  bool _isHdEnabled = true;

  @override
  Widget build(BuildContext context) {
    if (_permissionStatus.isDenied || _permissionStatus.isPermanentlyDenied) {
      return _buildPermissionScreen(
        'Camera Permission Required',
        'Grant Permission',
        _checkPermissionAndInitCamera,
      );
    }

    if (!_isCameraInitialized || _cameraController == null) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator(color: Colors.teal)),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // 1. Clean Camera Viewfinder Preview (Zero lag, pure 60fps)
          Center(
            child: GestureDetector(
              key: _previewKey,
              behavior: HitTestBehavior.opaque,
              onTapDown: _handleTapToFocus,
              child: CameraPreview(_cameraController!),
            ),
          ),

          // Tap-to-focus indicator ring
          if (_focusRingOffset != null)
            Positioned(
              left: _focusRingOffset!.dx - 30,
              top: _focusRingOffset!.dy - 30,
              child: IgnorePointer(
                child: Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: const Color(0xFF00FFC6), width: 2.5),
                  ),
                ),
              ),
            ),

          // 1b. Optional 3x3 grid lines (toggled from camera settings)
          if (_showGrid)
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(painter: _GridPainter()),
              ),
            ),

          // 2. Top Bar matching sc.jpg (Close, Flash, HD, More)
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            left: 12,
            right: 12,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white, size: 28),
                  onPressed: () => context.pop(),
                ),
                Row(
                  children: [
                    // Flash Mode 1-Click Popup Menu
                    PopupMenuButton<FlashMode>(
                      initialValue: _flashMode,
                      tooltip: 'Flash Mode',
                      color: const Color(0xFF1E293B),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      icon: Icon(
                        _getFlashIcon(),
                        color: _flashMode != FlashMode.off ? const Color(0xFF00D4AA) : Colors.white,
                        size: 26,
                      ),
                      onSelected: _selectFlashMode,
                      itemBuilder: (context) => [
                        PopupMenuItem(
                          value: FlashMode.auto,
                          child: Row(
                            children: [
                              Icon(Icons.flash_auto, color: _flashMode == FlashMode.auto ? const Color(0xFF00D4AA) : Colors.white70, size: 20),
                              const SizedBox(width: 12),
                              Text('Auto Flash', style: TextStyle(color: _flashMode == FlashMode.auto ? const Color(0xFF00D4AA) : Colors.white, fontSize: 14, fontWeight: _flashMode == FlashMode.auto ? FontWeight.bold : FontWeight.normal)),
                            ],
                          ),
                        ),
                        PopupMenuItem(
                          value: FlashMode.always,
                          child: Row(
                            children: [
                              Icon(Icons.flash_on, color: _flashMode == FlashMode.always ? const Color(0xFF00D4AA) : Colors.white70, size: 20),
                              const SizedBox(width: 12),
                              Text('Flash On', style: TextStyle(color: _flashMode == FlashMode.always ? const Color(0xFF00D4AA) : Colors.white, fontSize: 14, fontWeight: _flashMode == FlashMode.always ? FontWeight.bold : FontWeight.normal)),
                            ],
                          ),
                        ),
                        PopupMenuItem(
                          value: FlashMode.torch,
                          child: Row(
                            children: [
                              Icon(Icons.highlight, color: _flashMode == FlashMode.torch ? const Color(0xFF00D4AA) : Colors.white70, size: 20),
                              const SizedBox(width: 12),
                              Text('Torch Light', style: TextStyle(color: _flashMode == FlashMode.torch ? const Color(0xFF00D4AA) : Colors.white, fontSize: 14, fontWeight: _flashMode == FlashMode.torch ? FontWeight.bold : FontWeight.normal)),
                            ],
                          ),
                        ),
                        PopupMenuItem(
                          value: FlashMode.off,
                          child: Row(
                            children: [
                              Icon(Icons.flash_off, color: _flashMode == FlashMode.off ? const Color(0xFF00D4AA) : Colors.white60, size: 20),
                              const SizedBox(width: 12),
                              Text('Flash Off', style: TextStyle(color: _flashMode == FlashMode.off ? const Color(0xFF00D4AA) : Colors.white, fontSize: 14, fontWeight: _flashMode == FlashMode.off ? FontWeight.bold : FontWeight.normal)),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(width: 8),

                    // HD Badge Button
                    GestureDetector(
                      onTap: () async {
                        final messenger = ScaffoldMessenger.of(context);
                        setState(() => _isHdEnabled = !_isHdEnabled);
                        await AppSettings.setHdCapture(_isHdEnabled);
                        messenger.showSnackBar(
                          SnackBar(
                            content: Text(_isHdEnabled ? 'HD Mode: full sensor resolution' : 'Standard Mode: 720p'),
                            duration: const Duration(seconds: 1),
                          ),
                        );
                        // Actually switch the camera resolution now
                        await _reinitCameraForResolution();
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: _isHdEnabled ? Colors.white : Colors.transparent,
                          border: Border.all(color: Colors.white, width: 1.5),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          'HD',
                          style: TextStyle(
                            color: _isHdEnabled ? Colors.black : Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),

                    // More Menu
                    IconButton(
                      icon: const Icon(Icons.more_vert, color: Colors.white, size: 26),
                      onPressed: () => _showCameraOptionsSheet(context),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // 3. Mode Selector & Bottom Controls Area
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.only(bottom: 32, top: 12),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.transparent, Colors.black.withOpacity(0.85), Colors.black],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Horizontal Mode Selector Carousel
                  SizedBox(
                    height: 38,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: _scanModes.length,
                      itemBuilder: (context, index) {
                        final mode = _scanModes[index];
                        final isSelected = _selectedModeIndex == index;

                        return GestureDetector(
                          onTap: () {
                            setState(() => _selectedModeIndex = index);
                            _handleModeChange(mode);
                          },
                          child: Container(
                            margin: const EdgeInsets.symmetric(horizontal: 14),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  mode,
                                  style: TextStyle(
                                    color: isSelected ? const Color(0xFF00FFC6) : Colors.white70,
                                    fontSize: 14,
                                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                if (isSelected)
                                  Container(
                                    width: 20,
                                    height: 2.5,
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF00FFC6),
                                      borderRadius: BorderRadius.circular(2),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Bottom Action Bar: Grid Icon, Shutter Button, Gallery Icon
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 28.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // Left: Grid icon
                        IconButton(
                          icon: const Icon(Icons.grid_view_rounded, color: Colors.white, size: 28),
                          onPressed: () => _showCameraOptionsSheet(context),
                        ),

                        // Center: CamScanner signature Shutter Button
                        GestureDetector(
                          onTap: _captureImage,
                          child: Container(
                            width: 74,
                            height: 74,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: const Color(0xFF00D4AA), width: 3.5),
                            ),
                            child: Center(
                              child: Container(
                                width: 60,
                                height: 60,
                                decoration: const BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                        ),

                        // Right: Gallery Import
                        IconButton(
                          icon: const Icon(Icons.photo_library_outlined, color: Colors.white, size: 28),
                          onPressed: () => ImportUtils.importImages(context),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _handleModeChange(String mode) {
    if (mode == 'ID Card') {
      context.push('/id_card_scanner');
    } else if (mode == 'To Text') {
      context.push('/ocr');
    } else if (mode == 'To Excel') {
      context.push('/ocr');
    }
  }

  void _showCameraOptionsSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Camera Settings', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(Icons.flip_camera_ios, color: Colors.tealAccent),
              title: const Text('Switch Camera', style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(ctx);
                _switchCamera();
              },
            ),
            ListTile(
              leading: const Icon(Icons.grid_on, color: Colors.tealAccent),
              title: const Text('Grid Lines', style: TextStyle(color: Colors.white)),
              trailing: Switch(
                value: _showGrid,
                activeColor: Colors.tealAccent,
                onChanged: (v) {
                  Navigator.pop(ctx);
                  setState(() => _showGrid = v);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(v ? 'Grid lines enabled' : 'Grid lines disabled'),
                      duration: const Duration(seconds: 1),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPermissionScreen(String title, String buttonText, VoidCallback onPressed) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(backgroundColor: Colors.black, iconTheme: const IconThemeData(color: Colors.white), elevation: 0),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.camera_alt, size: 80, color: Colors.grey),
              const SizedBox(height: 24),
              Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white), textAlign: TextAlign.center),
              const SizedBox(height: 16),
              const Text('AH Scanner needs camera access to scan documents.', style: TextStyle(fontSize: 14, color: Colors.white70), textAlign: TextAlign.center),
              const SizedBox(height: 32),
              ElevatedButton(
                onPressed: onPressed,
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.primaryLight, padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16)),
                child: Text(buttonText, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildControlButton(IconData icon, VoidCallback onTap) {
    return InkWell(onTap: onTap, child: Container(padding: const EdgeInsets.all(12), decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle), child: Icon(icon, color: Colors.white, size: 24)));
  }

  Widget _buildSideButton(IconData icon, VoidCallback onTap) {
    return InkWell(onTap: onTap, child: Container(padding: const EdgeInsets.all(16), decoration: const BoxDecoration(color: Colors.black45, shape: BoxShape.circle), child: Icon(icon, color: Colors.white, size: 28)));
  }

  Widget _buildCaptureButton() {
    return GestureDetector(
      onTap: _isCapturing ? null : _captureImage,
      child: Container(
        height: 80, width: 80,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 4),
          color: Colors.transparent,
        ),
        child: Center(
          child: _isCapturing
              ? const SizedBox(
                  width: 32,
                  height: 32,
                  child: CircularProgressIndicator(
                    strokeWidth: 3,
                    color: Color(0xFF00FFC6),
                  ),
                )
              : Container(
                  height: 64,
                  width: 64,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white,
                  ),
                ),
        ),
      ),
    );
  }
}

/// Normalizes camera capture EXIF orientation and produces clean upright JPEG bytes
Uint8List _normalizeCameraExif(Uint8List rawBytes) {
  try {
    final decoded = img.decodeImage(rawBytes);
    if (decoded == null) return rawBytes;
    final oriented = img.bakeOrientation(decoded);
    return Uint8List.fromList(img.encodeJpg(oriented, quality: 100));
  } catch (e) {
    debugPrint('Camera EXIF normalization error: $e');
    return rawBytes;
  }
}

/// Draws a subtle 3x3 rule-of-thirds grid over the camera preview.
class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withOpacity(0.55)
      ..strokeWidth = 1.0;
    for (int i = 1; i <= 2; i++) {
      final dx = size.width * i / 3;
      canvas.drawLine(Offset(dx, 0), Offset(dx, size.height), paint);
      final dy = size.height * i / 3;
      canvas.drawLine(Offset(0, dy), Offset(size.width, dy), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
