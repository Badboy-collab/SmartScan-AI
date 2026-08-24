import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:injectable/injectable.dart';
import '../../domain/entities/document_corners.dart';
import '../../domain/entities/document_filter_type.dart';
import '../../domain/interfaces/i_document_processor.dart';

class DartDocumentProcessorService implements IDocumentProcessor {
  @override
  Future<DocumentCorners?> detectCorners(Uint8List imageBytes) async {
    // Stub
    return null;
  }

  @override
  Future<Uint8List> cropAndCorrectPerspective({
    required Uint8List imageBytes,
    required DocumentCorners corners,
    required int rotationDegrees,
  }) async {
    final Map<String, dynamic> params = {
      'bytes': imageBytes,
      'corners': {
        'tlX': corners.topLeft.dx, 'tlY': corners.topLeft.dy,
        'trX': corners.topRight.dx, 'trY': corners.topRight.dy,
        'blX': corners.bottomLeft.dx, 'blY': corners.bottomLeft.dy,
        'brX': corners.bottomRight.dx, 'brY': corners.bottomRight.dy,
      },
      'rotation': rotationDegrees,
    };
    return await compute(_processCropIsolate, params);
  }

  @override
  Future<Uint8List> applyFilter(Uint8List imageBytes, DocumentFilterType filterType) async {
    if (filterType == DocumentFilterType.original) return imageBytes;
    
    return await compute(_applyFilterIsolate, {
      'bytes': imageBytes,
      'type': filterType.index,
    });
  }
}

Future<Uint8List> _processCropIsolate(Map<String, dynamic> params) async {
  final Uint8List bytes = params['bytes'];
  final Map<String, double> c = params['corners'];
  int rotation = params['rotation'];

  // Decode image and bake orientation
  img.Image? originalImage = img.decodeImage(bytes);
  if (originalImage == null) throw Exception("Failed to decode image");
  originalImage = img.bakeOrientation(originalImage);

  int width = originalImage.width;
  int height = originalImage.height;

  // The corners are normalized to the screen's preview (portrait). 
  // If the raw image is landscape (width > height) but the screen is portrait, 
  // we need to rotate the normalized coordinates.
  bool needsRotationFix = (width > height);
  
  double tlX = c['tlX']!; double tlY = c['tlY']!;
  double trX = c['trX']!; double trY = c['trY']!;
  double blX = c['blX']!; double blY = c['blY']!;
  double brX = c['brX']!; double brY = c['brY']!;

  if (needsRotationFix) {
    // If image is landscape but UI was portrait, the Y axis of UI corresponds to X axis of Image, etc.
    // Assuming standard Android 90 deg clockwise rotation mapping:
    // screenX = (1 - imgY) -> imgY = 1 - screenX
    // screenY = imgX -> imgX = screenY
    double mapX(double sx, double sy) => sy;
    double mapY(double sx, double sy) => 1.0 - sx;

    double ntlX = mapX(tlX, tlY), ntlY = mapY(tlX, tlY);
    double ntrX = mapX(trX, trY), ntrY = mapY(trX, trY);
    double nblX = mapX(blX, blY), nblY = mapY(blX, blY);
    double nbrX = mapX(brX, brY), nbrY = mapY(brX, brY);

    tlX = ntlX; tlY = ntlY;
    trX = ntrX; trY = ntrY;
    blX = nblX; blY = nblY;
    brX = nbrX; brY = nbrY;
  }

  // Convert to pixel coordinates
  double p0x = tlX * width, p0y = tlY * height;
  double p1x = trX * width, p1y = trY * height;
  double p2x = brX * width, p2y = brY * height;
  double p3x = blX * width, p3y = blY * height;

  // Output dimensions (max width and max height)
  double w1 = sqrt(pow(p1x - p0x, 2) + pow(p1y - p0y, 2));
  double w2 = sqrt(pow(p2x - p3x, 2) + pow(p2y - p3y, 2));
  double h1 = sqrt(pow(p3x - p0x, 2) + pow(p3y - p0y, 2));
  double h2 = sqrt(pow(p2x - p1x, 2) + pow(p2y - p1y, 2));

  int outW = max(w1, w2).toInt();
  int outH = max(h1, h2).toInt();

  // Enforce sensible orientation: A4 is typically portrait. If user scanned landscape, rotate it.
  if (outW > outH * 1.2) { // If clearly landscape
    // We'll just generate it as is, and the user can rotate it in the UI.
  }

  img.Image outImg = img.Image(width: outW, height: outH);

  // Rectangle to Quadrilateral mapping math
  double dx1 = p1x - p2x;
  double dx2 = p3x - p2x;
  double dx3 = p0x - p1x + p2x - p3x;

  double dy1 = p1y - p2y;
  double dy2 = p3y - p2y;
  double dy3 = p0y - p1y + p2y - p3y;

  double det = dx1 * dy2 - dy1 * dx2;
  if (det == 0) det = 0.00001; // Avoid div by zero

  double a13 = (dx3 * dy2 - dy3 * dx2) / det;
  double a23 = (dx1 * dy3 - dy1 * dx3) / det;

  double a11 = p1x - p0x + a13 * p1x;
  double a21 = p3x - p0x + a23 * p3x;
  double a31 = p0x;

  double a12 = p1y - p0y + a13 * p1y;
  double a22 = p3y - p0y + a23 * p3y;
  double a32 = p0y;

  for (int y = 0; y < outH; y++) {
    for (int x = 0; x < outW; x++) {
      double u = x / outW;
      double v = y / outH;

      double z = a13 * u + a23 * v + 1.0;
      double sx = (a11 * u + a21 * v + a31) / z;
      double sy = (a12 * u + a22 * v + a32) / z;

      int srcX = sx.round().clamp(0, width - 1);
      int srcY = sy.round().clamp(0, height - 1);

      outImg.setPixel(x, y, originalImage.getPixel(srcX, srcY));
    }
  }

  // Rotate final image if required by user (rotation mapping)
  if (rotation != 0) {
    if (rotation == 90) outImg = img.copyRotate(outImg, angle: 90);
    else if (rotation == 180) outImg = img.copyRotate(outImg, angle: 180);
    else if (rotation == 270) outImg = img.copyRotate(outImg, angle: 270);
  }

  return Uint8List.fromList(img.encodeJpg(outImg, quality: 90));
}

Future<Uint8List> _applyFilterIsolate(Map<String, dynamic> params) async {
  final Uint8List bytes = params['bytes'];
  final int typeIndex = params['type'];
  final DocumentFilterType type = DocumentFilterType.values[typeIndex];

  img.Image? image = img.decodeImage(bytes);
  if (image == null) return bytes;

  switch (type) {
    case DocumentFilterType.auto:
      // Contrast stretching
      image = img.adjustColor(image, contrast: 1.2, brightness: 1.05);
      break;
    case DocumentFilterType.magic:
      // Simulated Magic Color: Boost saturation, contrast, and clean white background
      image = img.adjustColor(image, contrast: 1.3, saturation: 1.5);
      for (var p in image) {
        num r = p.r; num g = p.g; num b = p.b;
        // If it's a light color, push it closer to white to clean the background
        if (r > 180 && g > 180 && b > 180) {
          p.r = (r + 40).clamp(0, 255);
          p.g = (g + 40).clamp(0, 255);
          p.b = (b + 40).clamp(0, 255);
        }
      }
      break;
    case DocumentFilterType.grayscale:
      image = img.grayscale(image);
      break;
    case DocumentFilterType.blackAndWhite:
      image = img.luminanceThreshold(image, threshold: 0.6); // Simple binary threshold
      break;
    case DocumentFilterType.original:
      break;
    case DocumentFilterType.lighten:
      image = img.adjustColor(image, brightness: 1.25);
      break;
  }

  return Uint8List.fromList(img.encodeJpg(image, quality: 90));
}
