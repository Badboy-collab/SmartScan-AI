import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../../domain/entities/document_corners.dart';

class InteractiveCropOverlay extends StatefulWidget {
  final Uint8List imageBytes;
  final DocumentCorners initialCorners;
  final ValueChanged<DocumentCorners> onCornersChanged;

  const InteractiveCropOverlay({
    super.key,
    required this.imageBytes,
    required this.initialCorners,
    required this.onCornersChanged,
  });

  @override
  State<InteractiveCropOverlay> createState() => _InteractiveCropOverlayState();
}

class _InteractiveCropOverlayState extends State<InteractiveCropOverlay> {
  ui.Image? _image;
  late DocumentCorners _currentCorners;
  int _activeCornerIndex = -1; // 0: TL, 1: TR, 2: BR, 3: BL

  @override
  void initState() {
    super.initState();
    _currentCorners = widget.initialCorners;
    _loadImage();
  }

  @override
  void didUpdateWidget(covariant InteractiveCropOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialCorners != oldWidget.initialCorners) {
      setState(() {
        _currentCorners = widget.initialCorners;
      });
    }
  }

  Future<void> _loadImage() async {
    final codec = await ui.instantiateImageCodec(widget.imageBytes);
    final frame = await codec.getNextFrame();
    if (mounted) {
      setState(() => _image = frame.image);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_image == null) {
      return const Center(child: CircularProgressIndicator(color: Colors.teal));
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final double viewW = constraints.maxWidth;
        final double viewH = constraints.maxHeight;
        
        final double imgW = _image!.width.toDouble();
        final double imgH = _image!.height.toDouble();
        
        // Calculate fit center logic
        final double scale = (viewW / imgW < viewH / imgH) ? viewW / imgW : viewH / imgH;
        final double drawW = imgW * scale;
        final double drawH = imgH * scale;
        final double offsetX = (viewW - drawW) / 2;
        final double offsetY = (viewH - drawH) / 2;

        // Convert normalized corners to screen coordinates
        Offset tl = Offset(offsetX + _currentCorners.topLeft.dx * drawW, offsetY + _currentCorners.topLeft.dy * drawH);
        Offset tr = Offset(offsetX + _currentCorners.topRight.dx * drawW, offsetY + _currentCorners.topRight.dy * drawH);
        Offset br = Offset(offsetX + _currentCorners.bottomRight.dx * drawW, offsetY + _currentCorners.bottomRight.dy * drawH);
        Offset bl = Offset(offsetX + _currentCorners.bottomLeft.dx * drawW, offsetY + _currentCorners.bottomLeft.dy * drawH);

        // Edge midpoints
        Offset topMid = Offset((tl.dx + tr.dx) / 2, (tl.dy + tr.dy) / 2);
        Offset rightMid = Offset((tr.dx + br.dx) / 2, (tr.dy + br.dy) / 2);
        Offset bottomMid = Offset((bl.dx + br.dx) / 2, (bl.dy + br.dy) / 2);
        Offset leftMid = Offset((tl.dx + bl.dx) / 2, (tl.dy + bl.dy) / 2);

        return GestureDetector(
          onPanStart: (details) {
            final tapPos = details.localPosition;
            const double hitSlop = 45.0; // Responsive touch target

            double dist(Offset a, Offset b) => (a - b).distance;

            // Prioritize corners, then edge midpoints
            if (dist(tapPos, tl) < hitSlop) {
              _activeCornerIndex = 0;
            } else if (dist(tapPos, tr) < hitSlop) {
              _activeCornerIndex = 1;
            } else if (dist(tapPos, br) < hitSlop) {
              _activeCornerIndex = 2;
            } else if (dist(tapPos, bl) < hitSlop) {
              _activeCornerIndex = 3;
            } else if (dist(tapPos, topMid) < hitSlop) {
              _activeCornerIndex = 4;
            } else if (dist(tapPos, rightMid) < hitSlop) {
              _activeCornerIndex = 5;
            } else if (dist(tapPos, bottomMid) < hitSlop) {
              _activeCornerIndex = 6;
            } else if (dist(tapPos, leftMid) < hitSlop) {
              _activeCornerIndex = 7;
            } else {
              _activeCornerIndex = -1;
            }
          },
          onPanUpdate: (details) {
            if (_activeCornerIndex == -1) return;

            final pos = details.localPosition;
            final double nx = ((pos.dx - offsetX) / drawW).clamp(0.0, 1.0);
            final double ny = ((pos.dy - offsetY) / drawH).clamp(0.0, 1.0);
            final deltaNormY = details.delta.dy / drawH;
            final deltaNormX = details.delta.dx / drawW;

            setState(() {
              switch (_activeCornerIndex) {
                case 0:
                  _currentCorners = _currentCorners.copyWith(topLeft: Offset(nx, ny));
                  break;
                case 1:
                  _currentCorners = _currentCorners.copyWith(topRight: Offset(nx, ny));
                  break;
                case 2:
                  _currentCorners = _currentCorners.copyWith(bottomRight: Offset(nx, ny));
                  break;
                case 3:
                  _currentCorners = _currentCorners.copyWith(bottomLeft: Offset(nx, ny));
                  break;
                case 4: // Top edge
                  _currentCorners = _currentCorners.copyWith(
                    topLeft: Offset(_currentCorners.topLeft.dx, (_currentCorners.topLeft.dy + deltaNormY).clamp(0.0, 1.0)),
                    topRight: Offset(_currentCorners.topRight.dx, (_currentCorners.topRight.dy + deltaNormY).clamp(0.0, 1.0)),
                  );
                  break;
                case 5: // Right edge
                  _currentCorners = _currentCorners.copyWith(
                    topRight: Offset((_currentCorners.topRight.dx + deltaNormX).clamp(0.0, 1.0), _currentCorners.topRight.dy),
                    bottomRight: Offset((_currentCorners.bottomRight.dx + deltaNormX).clamp(0.0, 1.0), _currentCorners.bottomRight.dy),
                  );
                  break;
                case 6: // Bottom edge
                  _currentCorners = _currentCorners.copyWith(
                    bottomLeft: Offset(_currentCorners.bottomLeft.dx, (_currentCorners.bottomLeft.dy + deltaNormY).clamp(0.0, 1.0)),
                    bottomRight: Offset(_currentCorners.bottomRight.dx, (_currentCorners.bottomRight.dy + deltaNormY).clamp(0.0, 1.0)),
                  );
                  break;
                case 7: // Left edge
                  _currentCorners = _currentCorners.copyWith(
                    topLeft: Offset((_currentCorners.topLeft.dx + deltaNormX).clamp(0.0, 1.0), _currentCorners.topLeft.dy),
                    bottomLeft: Offset((_currentCorners.bottomLeft.dx + deltaNormX).clamp(0.0, 1.0), _currentCorners.bottomLeft.dy),
                  );
                  break;
              }
            });
            widget.onCornersChanged(_currentCorners);
          },
          onPanEnd: (_) => _activeCornerIndex = -1,
          child: CustomPaint(
            size: Size(viewW, viewH),
            painter: _CropPainter(
              image: _image!,
              scale: scale,
              offsetX: offsetX,
              offsetY: offsetY,
              tl: tl, tr: tr, br: br, bl: bl,
              topMid: topMid, rightMid: rightMid, bottomMid: bottomMid, leftMid: leftMid,
            ),
          ),
        );
      },
    );
  }
}

class _CropPainter extends CustomPainter {
  final ui.Image image;
  final double scale, offsetX, offsetY;
  final Offset tl, tr, br, bl;
  final Offset topMid, rightMid, bottomMid, leftMid;

  _CropPainter({
    required this.image,
    required this.scale,
    required this.offsetX,
    required this.offsetY,
    required this.tl, required this.tr, required this.br, required this.bl,
    required this.topMid, required this.rightMid, required this.bottomMid, required this.leftMid,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // 1. Draw original image
    final Rect src = Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble());
    final Rect dst = Rect.fromLTWH(offsetX, offsetY, image.width * scale, image.height * scale);
    canvas.drawImageRect(image, src, dst, Paint());

    // 2. Darken outside crop zone
    final path = Path()..addPolygon([tl, tr, br, bl], true);
    final bgPath = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
      ..addPath(path, Offset.zero)
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(bgPath, Paint()..color = Colors.black54);

    // 3. Draw boundary lines with vibrant cyan/teal
    final paintLine = Paint()
      ..color = const Color(0xFF00E5FF)
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke;
    canvas.drawPath(path, paintLine);

    // 4. Draw corner circular knobs
    final paintKnob = Paint()..color = Colors.white;
    final paintKnobBorder = Paint()
      ..color = const Color(0xFF00E5FF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0;

    for (var p in [tl, tr, br, bl]) {
      canvas.drawCircle(p, 13, paintKnob);
      canvas.drawCircle(p, 13, paintKnobBorder);
    }

    // 5. Draw edge midpoint pill handles
    final paintMidKnob = Paint()..color = Colors.white;
    final paintMidBorder = Paint()
      ..color = const Color(0xFF00E5FF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    for (var p in [topMid, rightMid, bottomMid, leftMid]) {
      canvas.drawCircle(p, 8, paintMidKnob);
      canvas.drawCircle(p, 8, paintMidBorder);
    }
  }

  @override
  bool shouldRepaint(covariant _CropPainter old) => true;
}
