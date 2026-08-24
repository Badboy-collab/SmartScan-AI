import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/theme/app_theme.dart';

class SignaturePage extends StatefulWidget {
  const SignaturePage({super.key});

  @override
  State<SignaturePage> createState() => _SignaturePageState();
}

class _SignaturePageState extends State<SignaturePage> {
  final GlobalKey _globalKey = GlobalKey();
  final List<List<Offset?>> _strokes = [];
  List<Offset?> _currentStroke = [];
  Color _selectedColor = Colors.black;
  double _strokeWidth = 3.5;

  void _undo() {
    if (_strokes.isNotEmpty) {
      setState(() {
        _strokes.removeLast();
      });
    }
  }

  void _clear() {
    setState(() {
      _strokes.clear();
      _currentStroke.clear();
    });
  }

  Future<void> _saveSignature() async {
    if (_strokes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please draw your signature first')),
      );
      return;
    }

    try {
      final boundary = _globalKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return;

      final ui.Image image = await boundary.toImage(pixelRatio: 3.0);
      final ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return;

      final Uint8List pngBytes = byteData.buffer.asUint8List();

      final dir = await getApplicationDocumentsDirectory();
      final sigId = const Uuid().v4();
      final filePath = '${dir.path}/signature_$sigId.png';
      await File(filePath).writeAsBytes(pngBytes);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Signature saved successfully!')),
        );
        Navigator.pop(context, filePath);
      }
    } catch (e) {
      debugPrint('[Signature] Save error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error saving: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1E1E1E),
      appBar: AppBar(
        title: const Text('Add Signature'),
        actions: [
          IconButton(
            icon: const Icon(Icons.undo),
            tooltip: 'Undo',
            onPressed: _strokes.isNotEmpty ? _undo : null,
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Clear',
            onPressed: _strokes.isNotEmpty ? _clear : null,
          ),
          IconButton(
            icon: const Icon(Icons.check, color: AppColors.primaryLight),
            tooltip: 'Save',
            onPressed: _saveSignature,
          ),
        ],
      ),
      body: Column(
        children: [
          // 1. Drawing Canvas Card
          Expanded(
            child: Container(
              margin: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: const [
                  BoxShadow(color: Colors.black26, blurRadius: 10, offset: Offset(0, 4)),
                ],
              ),
              clipBehavior: Clip.antiAlias,
              child: Stack(
                children: [
                  Positioned(
                    bottom: 30,
                    left: 24,
                    right: 24,
                    child: Container(
                      height: 1.5,
                      color: Colors.grey.shade300,
                    ),
                  ),
                  Positioned(
                    bottom: 10,
                    right: 24,
                    child: Text(
                      'Sign above the line',
                      style: TextStyle(color: Colors.grey.shade400, fontSize: 11, fontStyle: FontStyle.italic),
                    ),
                  ),
                  RepaintBoundary(
                    key: _globalKey,
                    child: GestureDetector(
                      onPanStart: (details) {
                        final RenderBox box = context.findRenderObject() as RenderBox;
                        final localPos = details.localPosition;
                        setState(() {
                          _currentStroke = [localPos];
                          _strokes.add(_currentStroke);
                        });
                      },
                      onPanUpdate: (details) {
                        final localPos = details.localPosition;
                        setState(() {
                          _currentStroke.add(localPos);
                        });
                      },
                      onPanEnd: (details) {
                        setState(() {
                          _currentStroke = [];
                        });
                      },
                      child: CustomPaint(
                        painter: _SignaturePainter(
                          strokes: _strokes,
                          color: _selectedColor,
                          strokeWidth: _strokeWidth,
                        ),
                        size: Size.infinite,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // 2. Ink Controls
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            color: const Color(0xFF2A2A2A),
            child: SafeArea(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Color selection
                  Row(
                    children: [
                      _buildColorPicker(Colors.black),
                      const SizedBox(width: 12),
                      _buildColorPicker(const Color(0xFF0D47A1)), // Dark Blue
                      const SizedBox(width: 12),
                      _buildColorPicker(const Color(0xFFB71C1C)), // Dark Red
                    ],
                  ),

                  // Stroke width presets
                  Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.line_weight, color: Colors.white70),
                        onPressed: () {
                          setState(() {
                            _strokeWidth = _strokeWidth == 3.5 ? 5.5 : (_strokeWidth == 5.5 ? 2.0 : 3.5);
                          });
                        },
                      ),
                      Text(
                        '${_strokeWidth.toStringAsFixed(1)} pt',
                        style: const TextStyle(color: Colors.white70, fontSize: 13),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildColorPicker(Color color) {
    final isSelected = _selectedColor == color;
    return GestureDetector(
      onTap: () => setState(() => _selectedColor = color),
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            color: isSelected ? AppColors.primaryLight : Colors.white24,
            width: isSelected ? 3.0 : 1.0,
          ),
        ),
      ),
    );
  }
}

class _SignaturePainter extends CustomPainter {
  final List<List<Offset?>> strokes;
  final Color color;
  final double strokeWidth;

  _SignaturePainter({
    required this.strokes,
    required this.color,
    required this.strokeWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke;

    for (final stroke in strokes) {
      if (stroke.length < 2) continue;
      final path = Path();
      path.moveTo(stroke.first!.dx, stroke.first!.dy);
      for (int i = 1; i < stroke.length; i++) {
        if (stroke[i] != null) {
          path.lineTo(stroke[i]!.dx, stroke[i]!.dy);
        }
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _SignaturePainter oldDelegate) => true;
}
