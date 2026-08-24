import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:image/image.dart' as img;
import 'package:permission_handler/permission_handler.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/import_utils.dart';

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
    if (status.isGranted) _initCamera();
  }

  Future<void> _initCamera() async {
    try {
      _cameras = await availableCameras();
      if (_cameras.isNotEmpty) _setCamera(_selectedCameraIndex);
    } catch (e) {
      debugPrint('Error initializing camera: $e');
    }
  }

  Future<void> _setCamera(int cameraIndex) async {
    if (_cameras.isEmpty) return;
    
    final previousController = _cameraController;
    final CameraController cameraController = CameraController(
      _cameras[cameraIndex],
      ResolutionPreset.veryHigh, // 1080p-class: smooth preview + sharp text (max preset lags & blurs on many phones)
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
      await cameraController.setFlashMode(_flashMode);
      if (mounted) {
        setState(() => _isCameraInitialized = true);
      }
    } catch (e) {
      debugPrint('Error initializing camera: $e');
    }
  }

  void _switchCamera() {
    if (_cameras.length > 1) {
      _selectedCameraIndex = (_selectedCameraIndex + 1) % _cameras.length;
      _isCameraInitialized = false;
      setState(() {});
      _setCamera(_selectedCameraIndex);
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
    await _cameraController!.setFlashMode(nextMode);
    setState(() => _flashMode = nextMode);
  }

  /// Safely turns the hardware flash/torch OFF (used on dispose, lifecycle
  /// pause, camera switch, and right after capture).
  Future<void> _turnOffFlash() async {
    final controller = _cameraController;
    if (controller == null || !controller.value.isInitialized) return;
    try {
      await controller.setFlashMode(FlashMode.off);
    } catch (_) {}
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

  Future<void> _captureImage() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized) return;
    try {
      final XFile image = await _cameraController!.takePicture();

      // Turn the torch/flash OFF immediately so it never keeps burning while
      // the user reviews the crop on the next screen.
      await _turnOffFlash();
      if (mounted) setState(() => _flashMode = FlashMode.off);

      final rawBytes = await image.readAsBytes();
      
      // Apply the exact same EXIF normalization as Import so geometry & detection are 100% identical!
      final normalizedBytes = await compute(_normalizeCameraExif, rawBytes);
      
      if (mounted) {
        context.push('/scan_crop', extra: {
          'imageBytes': normalizedBytes,
          'corners': null, // Runs high-precision OpenCV detection on the captured photo
          'rotation': 0,
          'targetDocumentId': widget.targetDocumentId,
        });
      }
    } catch (e) {
      debugPrint('Error taking picture: $e');
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
                    // Flash Toggle
                    IconButton(
                      icon: Icon(_getFlashIcon(), color: Colors.white, size: 26),
                      onPressed: _toggleFlash,
                    ),
                    const SizedBox(width: 8),

                    // HD Badge Button
                    GestureDetector(
                      onTap: () {
                        setState(() => _isHdEnabled = !_isHdEnabled);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(_isHdEnabled ? 'HD Mode Enabled (High Quality)' : 'Standard Mode Enabled'),
                            duration: const Duration(seconds: 1),
                          ),
                        );
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
                  const SizedBox(height: 16),

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
              trailing: Switch(value: true, activeColor: Colors.tealAccent, onChanged: (v) {}),
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
              const Text('We need access to your camera to scan documents.', style: TextStyle(fontSize: 14, color: Colors.white70), textAlign: TextAlign.center),
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
      onTap: _captureImage,
      child: Container(
        height: 80, width: 80,
        decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 4), color: Colors.transparent),
        child: Center(child: Container(height: 64, width: 64, decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.white))),
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
