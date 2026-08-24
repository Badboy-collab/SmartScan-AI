import 'dart:ui';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import '../../domain/entities/document_corners.dart';
import '../../domain/interfaces/i_document_detector.dart';

class DartDocumentDetectorService implements IDocumentDetector {
  bool _isProcessing = false;
  DocumentCorners? _lastCorners;
  int _jumpFrames = 0;

  @override
  Future<DocumentCorners?> detectEdges(CameraImage image) async {
    if (_isProcessing) return _lastCorners;
    _isProcessing = true;

    try {
      final Plane yPlane = image.planes[0];
      final rawCorners = await compute(_processImage, _CameraFrameData(
        bytes: yPlane.bytes,
        width: image.width,
        height: image.height,
        bytesPerRow: yPlane.bytesPerRow,
      ));

      if (rawCorners != null) {
        if (!_isValidPolygon(rawCorners)) {
          return _lastCorners; // Reject mathematically invalid or concave polygons
        }

        if (_lastCorners != null) {
          // Check for sudden jumps (e.g. wrong corner snapping to internal diagonal)
          double maxJump = 0.25; // 25% of screen
          bool isJump = (rawCorners.topLeft - _lastCorners!.topLeft).distance > maxJump ||
              (rawCorners.topRight - _lastCorners!.topRight).distance > maxJump ||
              (rawCorners.bottomLeft - _lastCorners!.bottomLeft).distance > maxJump ||
              (rawCorners.bottomRight - _lastCorners!.bottomRight).distance > maxJump;

          if (isJump) {
            _jumpFrames++;
            if (_jumpFrames < 5) {
              return _lastCorners; // Temporarily reject the jump to prevent flickering
            } else {
              _jumpFrames = 0; // Accept the new stable position
            }
          } else {
            _jumpFrames = 0;
          }

          // Temporal smoothing (EMA filter)
          _lastCorners = DocumentCorners(
            topLeft: Offset.lerp(_lastCorners!.topLeft, rawCorners.topLeft, 0.25)!,
            topRight: Offset.lerp(_lastCorners!.topRight, rawCorners.topRight, 0.25)!,
            bottomLeft: Offset.lerp(_lastCorners!.bottomLeft, rawCorners.bottomLeft, 0.25)!,
            bottomRight: Offset.lerp(_lastCorners!.bottomRight, rawCorners.bottomRight, 0.25)!,
          );
        } else {
          _lastCorners = rawCorners;
        }
      }
      // If rawCorners is null, we just return _lastCorners to hold steady
      return _lastCorners;
    } catch (e) {
      debugPrint('Edge detection error: $e');
      return _lastCorners;
    } finally {
      _isProcessing = false;
    }
  }

  bool _isValidPolygon(DocumentCorners c) {
    // Check minimum edge length
    double top = (c.topRight - c.topLeft).distance;
    double bottom = (c.bottomRight - c.bottomLeft).distance;
    double left = (c.bottomLeft - c.topLeft).distance;
    double right = (c.bottomRight - c.topRight).distance;
    
    if (top < 0.15 || bottom < 0.15 || left < 0.15 || right < 0.15) return false;

    // Check convexity (Cross products of adjacent edges must have same sign)
    double cross(Offset a, Offset b, Offset p) {
      Offset ab = b - a;
      Offset bp = p - b;
      return ab.dx * bp.dy - ab.dy * bp.dx;
    }
    
    bool isConvex = cross(c.topLeft, c.topRight, c.bottomRight) > 0 &&
                    cross(c.topRight, c.bottomRight, c.bottomLeft) > 0 &&
                    cross(c.bottomRight, c.bottomLeft, c.topLeft) > 0 &&
                    cross(c.bottomLeft, c.topLeft, c.topRight) > 0;
                    
    return isConvex;
  }

  @override
  void dispose() {
    _lastCorners = null;
    _jumpFrames = 0;
  }
}

class _CameraFrameData {
  final Uint8List bytes;
  final int width;
  final int height;
  final int bytesPerRow;

  _CameraFrameData({
    required this.bytes,
    required this.width,
    required this.height,
    required this.bytesPerRow,
  });
}

DocumentCorners? _processImage(_CameraFrameData data) {
  final int width = data.width;
  final int height = data.height;
  final int bytesPerRow = data.bytesPerRow;
  final Uint8List yPlane = data.bytes;

  final int gridW = 80;
  final int gridH = 80;
  final int stepX = width ~/ gridW;
  final int stepY = height ~/ gridH;

  int minLuma = 255;
  int maxLuma = 0;
  int totalLuma = 0;
  int count = 0;

  for (int y = 0; y < gridH; y++) {
    for (int x = 0; x < gridW; x++) {
      int pixelIndex = (y * stepY) * bytesPerRow + (x * stepX);
      if (pixelIndex < yPlane.length) {
        int luma = yPlane[pixelIndex];
        if (luma < minLuma) minLuma = luma;
        if (luma > maxLuma) maxLuma = luma;
        totalLuma += luma;
        count++;
      }
    }
  }

  if (count == 0 || (maxLuma - minLuma) < 30) return null;

  int avgLuma = totalLuma ~/ count;
  int threshold = avgLuma + ((maxLuma - avgLuma) * 0.4).toInt();

  final List<bool> bright = List.filled(gridW * gridH, false);
  for (int y = 0; y < gridH; y++) {
    for (int x = 0; x < gridW; x++) {
      int pixelIndex = (y * stepY) * bytesPerRow + (x * stepX);
      if (pixelIndex < yPlane.length && yPlane[pixelIndex] >= threshold) {
        bright[y * gridW + x] = true;
      }
    }
  }

  final List<bool> visited = List.filled(gridW * gridH, false);
  int maxBlobSize = 0;
  List<int> bestBlobPixels = [];

  for (int i = 0; i < gridW * gridH; i++) {
    if (bright[i] && !visited[i]) {
      int size = 0;
      List<int> currentBlob = [];
      List<int> queue = [i];
      visited[i] = true;

      while (queue.isNotEmpty) {
        int curr = queue.removeLast();
        currentBlob.add(curr);
        size++;
        int cx = curr % gridW;
        int cy = curr ~/ gridW;

        int up = curr - gridW;
        if (cy > 0 && bright[up] && !visited[up]) { visited[up] = true; queue.add(up); }
        int down = curr + gridW;
        if (cy < gridH - 1 && bright[down] && !visited[down]) { visited[down] = true; queue.add(down); }
        int left = curr - 1;
        if (cx > 0 && bright[left] && !visited[left]) { visited[left] = true; queue.add(left); }
        int right = curr + 1;
        if (cx < gridW - 1 && bright[right] && !visited[right]) { visited[right] = true; queue.add(right); }
      }

      if (size > maxBlobSize) {
        maxBlobSize = size;
        bestBlobPixels = currentBlob;
      }
    }
  }

  double areaRatio = maxBlobSize / (gridW * gridH);
  if (areaRatio < 0.10 || areaRatio > 0.95) return null;

  // Hole Filling: Connect internal dark spots to the blob (fixes missing corners due to dark images/logos inside)
  List<bool> isBlob = List.filled(gridW * gridH, false);
  for (int idx in bestBlobPixels) isBlob[idx] = true;

  List<bool> isOutside = List.filled(gridW * gridH, false);
  List<int> outQueue = [];
  
  // Start from 4 borders
  for (int x = 0; x < gridW; x++) {
    if (!isBlob[x]) { isOutside[x] = true; outQueue.add(x); }
    if (!isBlob[(gridH - 1) * gridW + x]) { isOutside[(gridH - 1) * gridW + x] = true; outQueue.add((gridH - 1) * gridW + x); }
  }
  for (int y = 0; y < gridH; y++) {
    if (!isBlob[y * gridW]) { isOutside[y * gridW] = true; outQueue.add(y * gridW); }
    if (!isBlob[y * gridW + gridW - 1]) { isOutside[y * gridW + gridW - 1] = true; outQueue.add(y * gridW + gridW - 1); }
  }

  while (outQueue.isNotEmpty) {
    int curr = outQueue.removeLast();
    int cx = curr % gridW;
    int cy = curr ~/ gridW;

    int up = curr - gridW;
    if (cy > 0 && !isBlob[up] && !isOutside[up]) { isOutside[up] = true; outQueue.add(up); }
    int down = curr + gridW;
    if (cy < gridH - 1 && !isBlob[down] && !isOutside[down]) { isOutside[down] = true; outQueue.add(down); }
    int left = curr - 1;
    if (cx > 0 && !isBlob[left] && !isOutside[left]) { isOutside[left] = true; outQueue.add(left); }
    int right = curr + 1;
    if (cx < gridW - 1 && !isBlob[right] && !isOutside[right]) { isOutside[right] = true; outQueue.add(right); }
  }

  // Find 4 extremeties of the filled blob
  int minSum = 999999, maxSum = -999999;
  int minDiff = 999999, maxDiff = -999999;

  int tlX = 0, tlY = 0;
  int brX = 0, brY = 0;
  int blX = 0, blY = 0;
  int trX = 0, trY = 0;

  for (int i = 0; i < gridW * gridH; i++) {
    if (!isOutside[i]) {
      int x = i % gridW;
      int y = i ~/ gridW;
      
      int sum = x + y;
      int diff = x - y;

      if (sum < minSum) { minSum = sum; tlX = x; tlY = y; }
      if (sum > maxSum) { maxSum = sum; brX = x; brY = y; }
      if (diff < minDiff) { minDiff = diff; blX = x; blY = y; }
      if (diff > maxDiff) { maxDiff = diff; trX = x; trY = y; }
    }
  }

  return DocumentCorners(
    topLeft: Offset(tlX / gridW, tlY / gridH),
    topRight: Offset(trX / gridW, trY / gridH),
    bottomLeft: Offset(blX / gridW, blY / gridH),
    bottomRight: Offset(brX / gridW, brY / gridH),
  );
}
