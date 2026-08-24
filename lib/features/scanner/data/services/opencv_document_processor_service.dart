import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:injectable/injectable.dart';
import 'package:opencv_dart/opencv_dart.dart' as cv;

import '../../domain/entities/document_corners.dart';
import '../../domain/entities/document_filter_type.dart';
import '../../domain/interfaces/i_document_processor.dart';

@LazySingleton(as: IDocumentProcessor)
class OpencvDocumentProcessorService implements IDocumentProcessor {
  @override
  Future<DocumentCorners?> detectCorners(Uint8List imageBytes) async {
    return await compute(_detectCornersIsolate, imageBytes);
  }

  @override
  Future<Uint8List> cropAndCorrectPerspective({
    required Uint8List imageBytes,
    required DocumentCorners corners,
    required int rotationDegrees,
  }) async {
    final params = {
      'bytes': imageBytes,
      'corners': {
        'tlX': corners.topLeft.dx, 'tlY': corners.topLeft.dy,
        'trX': corners.topRight.dx, 'trY': corners.topRight.dy,
        'blX': corners.bottomLeft.dx, 'blY': corners.bottomLeft.dy,
        'brX': corners.bottomRight.dx, 'brY': corners.bottomRight.dy,
      },
      'rotation': rotationDegrees,
    };
    return await compute(_cropIsolate, params);
  }

  @override
  Future<Uint8List> applyFilter(Uint8List imageBytes, DocumentFilterType filterType) async {
    if (filterType == DocumentFilterType.original) return imageBytes;
    
    return await compute(_filterIsolate, {
      'bytes': imageBytes,
      'type': filterType.index,
    });
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// 1. ROBUST MULTI-STRATEGY DOCUMENT CORNER DETECTION (ISOLATE)
// ═══════════════════════════════════════════════════════════════════════════
Future<DocumentCorners?> _detectCornersIsolate(Uint8List bytes) async {
  try {
    final mat = cv.imdecode(bytes, cv.IMREAD_COLOR);
    if (mat.isEmpty) return null;

    final origW = mat.cols;
    final origH = mat.rows;

    // Downscale for fast and noise-free feature extraction (700-900px on long edge)
    final maxDim = 750.0;
    final scale = min(maxDim / origW, maxDim / origH);
    final src = cv.resize(mat, (0, 0), fx: scale, fy: scale);
    final rW = src.cols;
    final rH = src.rows;
    final totalArea = (rW * rH).toDouble();

    final List<_QuadCandidate> candidates = [];

    final gray = cv.cvtColor(src, cv.COLOR_BGR2GRAY);
    final blurredGray = cv.gaussianBlur(gray, (5, 5), 0);

    // ──────────────────────────────────────────────────────────
    // METHOD 1: Color/Paper Saliency (Lab Luminance minus HSV Saturation)
    // Perfectly isolates white/light paper on wood, dark desks, and folders
    // ──────────────────────────────────────────────────────────
    try {
      final lab = cv.cvtColor(src, cv.COLOR_BGR2Lab);
      final labCh = cv.split(lab);
      final L = labCh[0];

      final hsv = cv.cvtColor(src, cv.COLOR_BGR2HSV);
      final hsvCh = cv.split(hsv);
      final S = hsvCh[1];

      // Paper confidence = L - 1.2 * S (White paper = high, colored/wood/dark = 0)
      final paperConf = cv.addWeighted(L, 1.0, S, -1.2, 0.0);
      final otsuBin = cv.threshold(paperConf, 0, 255, cv.THRESH_BINARY | cv.THRESH_OTSU).$2;

      final kClose = cv.getStructuringElement(cv.MORPH_RECT, (11, 11));
      final kOpen = cv.getStructuringElement(cv.MORPH_RECT, (5, 5));
      var paperSolid = cv.morphologyEx(otsuBin, cv.MORPH_CLOSE, kClose);
      paperSolid = cv.morphologyEx(paperSolid, cv.MORPH_OPEN, kOpen);

      _extractPaperCandidates(paperSolid, gray, rW, rH, totalArea, candidates, 2.5);
    } catch (e) {
      debugPrint('[Detect:Saliency] $e');
    }

    // ──────────────────────────────────────────────────────────
    // METHOD 2: CLAHE Enhanced Luminance + Dynamic Otsu
    // ──────────────────────────────────────────────────────────
    try {
      final lab = cv.cvtColor(src, cv.COLOR_BGR2Lab);
      final labChannels = cv.split(lab);
      final clahe = cv.createCLAHE(clipLimit: 2.5, tileGridSize: (8, 8));
      final enhancedL = clahe.apply(labChannels[0]);

      final otsuBin = cv.threshold(enhancedL, 0, 255, cv.THRESH_BINARY | cv.THRESH_OTSU).$2;
      final kClose = cv.getStructuringElement(cv.MORPH_RECT, (9, 9));
      final kOpen = cv.getStructuringElement(cv.MORPH_RECT, (5, 5));
      var morphed = cv.morphologyEx(otsuBin, cv.MORPH_CLOSE, kClose);
      morphed = cv.morphologyEx(morphed, cv.MORPH_OPEN, kOpen);

      _extractPaperCandidates(morphed, gray, rW, rH, totalArea, candidates, 1.5);
    } catch (e) {
      debugPrint('[Detect:CLAHE] $e');
    }

    // ──────────────────────────────────────────────────────────
    // METHOD 3: Multi-Threshold Canny + Morphological Closing
    // ──────────────────────────────────────────────────────────
    try {
      for (final (t1, t2) in [(30.0, 100.0), (50.0, 150.0)]) {
        final edges = cv.canny(blurredGray, t1, t2);
        final kClose = cv.getStructuringElement(cv.MORPH_RECT, (7, 7));
        final kDilate = cv.getStructuringElement(cv.MORPH_RECT, (3, 3));
        var morphedEdges = cv.morphologyEx(edges, cv.MORPH_CLOSE, kClose);
        morphedEdges = cv.dilate(morphedEdges, kDilate);

        _extractPaperCandidates(morphedEdges, gray, rW, rH, totalArea, candidates, 1.0);
      }
    } catch (e) {
      debugPrint('[Detect:Canny] $e');
    }

    // ──────────────────────────────────────────────────────────
    // METHOD 4: Adaptive Gaussian Thresholding
    // ──────────────────────────────────────────────────────────
    try {
      final adaptiveBin = cv.adaptiveThreshold(
        gray, 255, cv.ADAPTIVE_THRESH_GAUSSIAN_C, cv.THRESH_BINARY_INV, 25, 8);
      final kClose = cv.getStructuringElement(cv.MORPH_RECT, (9, 9));
      final morphed = cv.morphologyEx(adaptiveBin, cv.MORPH_CLOSE, kClose);

      _extractPaperCandidates(morphed, gray, rW, rH, totalArea, candidates, 1.1);
    } catch (e) {
      debugPrint('[Detect:Adaptive] $e');
    }

    // ──────────────────────────────────────────────────────────
    // SELECT BEST CANDIDATE (OR CLEAN NATURAL FALLBACK)
    // ──────────────────────────────────────────────────────────
    if (candidates.isEmpty) {
      debugPrint('[DocDetect] Safe fallback to natural document frame (5% margins)');
      return DocumentCorners(
        topLeft: const Offset(0.05, 0.05),
        topRight: const Offset(0.95, 0.05),
        bottomRight: const Offset(0.95, 0.95),
        bottomLeft: const Offset(0.05, 0.95),
      );
    }

    // Sort candidates by score descending
    candidates.sort((a, b) => b.score.compareTo(a.score));
    final best = candidates.first;
    debugPrint('[DocDetect] SUCCESS: Selected candidate with score=${best.score.toStringAsFixed(1)}, Area%=${(best.area / totalArea * 100).toStringAsFixed(1)}%');

    final (tl, tr, br, bl) = _sortCorners(best.points);

    return DocumentCorners(
      topLeft:     Offset((tl.x / rW).clamp(0.0, 1.0), (tl.y / rH).clamp(0.0, 1.0)),
      topRight:    Offset((tr.x / rW).clamp(0.0, 1.0), (tr.y / rH).clamp(0.0, 1.0)),
      bottomRight: Offset((br.x / rW).clamp(0.0, 1.0), (br.y / rH).clamp(0.0, 1.0)),
      bottomLeft:  Offset((bl.x / rW).clamp(0.0, 1.0), (bl.y / rH).clamp(0.0, 1.0)),
    );
  } catch (e) {
    debugPrint('[DocDetect] Critical error: $e');
    return DocumentCorners(
      topLeft: const Offset(0.05, 0.05),
      topRight: const Offset(0.95, 0.05),
      bottomRight: const Offset(0.95, 0.95),
      bottomLeft: const Offset(0.05, 0.95),
    );
  }
}

class _QuadCandidate {
  final List<cv.Point> points;
  final double area;
  final double score;

  _QuadCandidate({
    required this.points,
    required this.area,
    required this.score,
  });
}

void _extractPaperCandidates(
  cv.Mat binary,
  cv.Mat gray,
  int rW,
  int rH,
  double totalArea,
  List<_QuadCandidate> outList,
  double methodWeight,
) {
  // Use RETR_EXTERNAL to get outermost contours and ignore internal table cells
  final (contours, _) = cv.findContours(binary, cv.RETR_EXTERNAL, cv.CHAIN_APPROX_SIMPLE);
  if (contours.isEmpty) return;

  final minArea = totalArea * 0.08;
  final maxArea = totalArea * 0.92;

  final list = contours.toList();
  list.sort((a, b) => cv.contourArea(b).compareTo(cv.contourArea(a)));

  for (final contour in list.take(8)) {
    final area = cv.contourArea(contour);
    if (area < minArea || area > maxArea) continue;

    bool found = false;

    // 1. Polygon Approximation on Contour
    final perim = cv.arcLength(contour, true);
    for (final eps in [0.012, 0.018, 0.025, 0.035, 0.045, 0.06, 0.08, 0.10]) {
      final approx = cv.approxPolyDP(contour, eps * perim, true);
      if (approx.length == 4 && cv.isContourConvex(approx)) {
        final pts = approx.toList();
        final qArea = _quadArea(pts);
        if (qArea >= minArea && qArea <= maxArea) {
          final score = _scoreCandidateQuad(pts, gray, totalArea, qArea, rW, rH, methodWeight * 1.30);
          if (score > 0) {
            outList.add(_QuadCandidate(points: pts, area: qArea, score: score));
            found = true;
            break;
          }
        }
      } else if (approx.length >= 4 && approx.length <= 10) {
        final extPts = _findExtremal4Points(approx);
        if (extPts.length == 4) {
          final qArea = _quadArea(extPts);
          if (qArea >= minArea && qArea <= maxArea) {
            final score = _scoreCandidateQuad(extPts, gray, totalArea, qArea, rW, rH, methodWeight * 1.05);
            if (score > 0) {
              outList.add(_QuadCandidate(points: extPts, area: qArea, score: score));
              found = true;
              break;
            }
          }
        }
      }
    }

    // 2. 4-Segment Line Fitting on Contour
    final lineFittedPts = _fit4BoundaryLines(contour, rW, rH);
    if (lineFittedPts != null && lineFittedPts.length == 4) {
      final qArea = _quadArea(lineFittedPts);
      if (qArea >= minArea && qArea <= maxArea) {
        final score = _scoreCandidateQuad(lineFittedPts, gray, totalArea, qArea, rW, rH, methodWeight * 1.40);
        if (score > 0) {
          outList.add(_QuadCandidate(points: lineFittedPts, area: qArea, score: score));
          found = true;
        }
      }
    }

    // 3. Extremal 4 Points directly from full contour
    if (!found) {
      final fullExtPts = _findExtremal4Points(contour);
      if (fullExtPts.length == 4) {
        final qArea = _quadArea(fullExtPts);
        if (qArea >= minArea && qArea <= maxArea) {
          final score = _scoreCandidateQuad(fullExtPts, gray, totalArea, qArea, rW, rH, methodWeight * 0.90);
          if (score > 0) {
            outList.add(_QuadCandidate(points: fullExtPts, area: qArea, score: score));
          }
        }
      }
    }

    // 4. Oriented Bounding Rectangle (minAreaRect)
    try {
      final rotatedRect = cv.minAreaRect(contour);
      final boxPts = rotatedRect.points.map((p) => cv.Point(p.x.toInt(), p.y.toInt())).toList();
      if (boxPts.length == 4) {
        final qArea = _quadArea(boxPts);
        if (qArea >= minArea && qArea <= maxArea) {
          final score = _scoreCandidateQuad(boxPts, gray, totalArea, qArea, rW, rH, methodWeight * 1.10);
          if (score > 0) {
            outList.add(_QuadCandidate(points: boxPts, area: qArea, score: score));
          }
        }
      }
    } catch (_) {}
  }
}

/// Fit 4 boundary lines to the 4 sides of a contour and find their 4 intersection points
List<cv.Point>? _fit4BoundaryLines(cv.VecPoint contour, int rW, int rH) {
  if (contour.length < 8) return null;
  final rawList = contour.toList();

  // Find centroid
  double cx = 0, cy = 0;
  for (final p in rawList) {
    cx += p.x;
    cy += p.y;
  }
  cx /= rawList.length;
  cy /= rawList.length;

  // Split points into 4 quadrants / sides relative to centroid
  final topPts = <cv.Point>[];
  final bottomPts = <cv.Point>[];
  final leftPts = <cv.Point>[];
  final rightPts = <cv.Point>[];

  for (final p in rawList) {
    final dx = p.x - cx;
    final dy = p.y - cy;
    if (dy.abs() > dx.abs()) {
      if (dy < 0) {
        topPts.add(p);
      } else {
        bottomPts.add(p);
      }
    } else {
      if (dx < 0) {
        leftPts.add(p);
      } else {
        rightPts.add(p);
      }
    }
  }

  if (topPts.length < 2 || bottomPts.length < 2 || leftPts.length < 2 || rightPts.length < 2) {
    return null;
  }

  // Linear regression line: y = m*x + c or x = m*y + c
  (double, double, bool) fitLine(List<cv.Point> pts) {
    double sx = 0, sy = 0, sxx = 0, syy = 0, sxy = 0;
    final n = pts.length.toDouble();
    for (final p in pts) {
      sx += p.x;
      sy += p.y;
      sxx += p.x * p.x;
      syy += p.y * p.y;
      sxy += p.x * p.y;
    }
    final varX = sxx - (sx * sx) / n;
    final varY = syy - (sy * sy) / n;

    if (varX >= varY) {
      // y = m*x + c
      final m = (sxy - (sx * sy) / n) / (varX == 0 ? 1e-5 : varX);
      final c = (sy - m * sx) / n;
      return (m, c, false); // isVertical = false
    } else {
      // x = m*y + c
      final m = (sxy - (sx * sy) / n) / (varY == 0 ? 1e-5 : varY);
      final c = (sx - m * sy) / n;
      return (m, c, true); // isVertical = true
    }
  }

  cv.Point intersect((double, double, bool) l1, (double, double, bool) l2) {
    final (m1, c1, v1) = l1;
    final (m2, c2, v2) = l2;

    double ix, iy;
    if (!v1 && v2) {
      // l1: y = m1*x + c1, l2: x = m2*y + c2
      iy = (m1 * c2 + c1) / (1.0 - m1 * m2 == 0 ? 1e-5 : 1.0 - m1 * m2);
      ix = m2 * iy + c2;
    } else if (v1 && !v2) {
      // l1: x = m1*y + c1, l2: y = m2*x + c2
      ix = (m1 * c2 + c1) / (1.0 - m1 * m2 == 0 ? 1e-5 : 1.0 - m1 * m2);
      iy = m2 * ix + c2;
    } else if (!v1 && !v2) {
      // both: y = m*x + c
      ix = (c2 - c1) / (m1 - m2 == 0 ? 1e-5 : m1 - m2);
      iy = m1 * ix + c1;
    } else {
      // both: x = m*y + c
      iy = (c2 - c1) / (m1 - m2 == 0 ? 1e-5 : m1 - m2);
      ix = m1 * iy + c1;
    }
    return cv.Point(ix.round().clamp(0, rW), iy.round().clamp(0, rH));
  }

  final lTop = fitLine(topPts);
  final lBottom = fitLine(bottomPts);
  final lLeft = fitLine(leftPts);
  final lRight = fitLine(rightPts);

  final tl = intersect(lTop, lLeft);
  final tr = intersect(lTop, lRight);
  final br = intersect(lBottom, lRight);
  final bl = intersect(lBottom, lLeft);

  return [tl, tr, br, bl];
}

List<cv.Point> _findExtremal4Points(cv.VecPoint contour) {
  if (contour.isEmpty) return [];

  cv.Point minSum = contour[0];
  cv.Point maxSum = contour[0];
  cv.Point minDiff = contour[0];
  cv.Point maxDiff = contour[0];

  for (var i = 0; i < contour.length; i++) {
    final p = contour[i];
    final sum = p.x + p.y;
    final diff = p.x - p.y;

    if (sum < minSum.x + minSum.y) minSum = p;
    if (sum > maxSum.x + maxSum.y) maxSum = p;
    if (diff < minDiff.x - minDiff.y) minDiff = p;
    if (diff > maxDiff.x - maxDiff.y) maxDiff = p;
  }

  return [minSum, maxDiff, maxSum, minDiff];
}

double _scoreCandidateQuad(
  List<cv.Point> rawPts,
  cv.Mat gray,
  double totalArea,
  double area,
  int rW,
  int rH,
  double weightModifier,
) {
  if (rawPts.length != 4) return 0.0;
  final (tl, tr, br, bl) = _sortCorners(rawPts);
  final pts = [tl, tr, br, bl];

  // 1. Angle orthogonality check
  double anglePenalty = 0.0;
  for (int i = 0; i < 4; i++) {
    final pPrev = pts[(i + 3) % 4];
    final pCurr = pts[i];
    final pNext = pts[(i + 1) % 4];

    final v1x = pPrev.x - pCurr.x;
    final v1y = pPrev.y - pCurr.y;
    final v2x = pNext.x - pCurr.x;
    final v2y = pNext.y - pCurr.y;

    final dot = v1x * v2x + v1y * v2y;
    final mag1 = sqrt(v1x * v1x + v1y * v1y);
    final mag2 = sqrt(v2x * v2x + v2y * v2y);

    if (mag1 == 0 || mag2 == 0) return 0.0;
    final cosAngle = (dot / (mag1 * mag2)).abs();
    if (cosAngle > 0.60) return 0.0; // Angles must be reasonably rectangular
    anglePenalty += cosAngle;
  }
  final orthogonalityScore = (1.0 - (anglePenalty / 4.0)).clamp(0.2, 1.0);

  // 2. Aspect Ratio & Side Ratio Checks
  final wTop = sqrt(pow(tr.x - tl.x, 2) + pow(tr.y - tl.y, 2));
  final wBottom = sqrt(pow(br.x - bl.x, 2) + pow(br.y - bl.y, 2));
  final hLeft = sqrt(pow(bl.x - tl.x, 2) + pow(bl.y - tl.y, 2));
  final hRight = sqrt(pow(br.x - tr.x, 2) + pow(br.y - tr.y, 2));

  if (hLeft == 0 || hRight == 0 || wTop == 0 || wBottom == 0) return 0.0;

  final wRatio = min(wTop, wBottom) / max(wTop, wBottom);
  final hRatio = min(hLeft, hRight) / max(hLeft, hRight);
  if (wRatio < 0.45 || hRatio < 0.45) return 0.0;

  final avgW = (wTop + wBottom) / 2.0;
  final avgH = (hLeft + hRight) / 2.0;
  final aspect = avgW / avgH;
  if (aspect < 0.30 || aspect > 3.0) return 0.0;

  // 3. Document Area Score: prefer normal documents (15% to 85% of camera frame)
  final areaRatio = (area / totalArea).clamp(0.0, 1.0);
  double areaScore;
  if (areaRatio > 0.90) {
    areaScore = 0.20; // Heavily penalize full-frame
  } else if (areaRatio >= 0.12 && areaRatio <= 0.85) {
    areaScore = 1.0 + (0.8 * areaRatio); // Sweet spot for documents
  } else {
    areaScore = 0.4 + areaRatio;
  }

  // 4. Edge proximity penalty: heavily penalize any quad glued to frame borders
  double edgePenalty = 1.0;
  final marginX = (rW * 0.02).round();
  final marginY = (rH * 0.02).round();
  for (final p in pts) {
    if (p.x <= marginX || p.x >= (rW - marginX) || p.y <= marginY || p.y >= (rH - marginY)) {
      edgePenalty *= 0.40; // 60% penalty per corner on image boundary
    }
  }

  // 5. Interior Brightness Check: White paper must be luminous inside
  double interiorScore = 1.0;
  try {
    final cx = ((tl.x + tr.x + br.x + bl.x) / 4.0).round().clamp(0, rW - 1);
    final cy = ((tl.y + tr.y + br.y + bl.y) / 4.0).round().clamp(0, rH - 1);
    final centerVal = gray.at<int>(cy, cx);
    if (centerVal < 80) {
      interiorScore = 0.2; // Too dark inside to be white paper
    } else if (centerVal >= 130) {
      interiorScore = 1.3; // Confirmed bright paper
    }
  } catch (_) {}

  return 100.0 * orthogonalityScore * areaScore * weightModifier * wRatio * hRatio * edgePenalty * interiorScore;
}

/// Sort 4 detected points into (TL, TR, BR, BL) using sum & difference method with centroid fallback.
(cv.Point, cv.Point, cv.Point, cv.Point) _sortCorners(List<cv.Point> pts) {
  if (pts.length != 4) {
    return (cv.Point(0, 0), cv.Point(0, 0), cv.Point(0, 0), cv.Point(0, 0));
  }

  final cx = (pts[0].x + pts[1].x + pts[2].x + pts[3].x) / 4.0;
  final cy = (pts[0].y + pts[1].y + pts[2].y + pts[3].y) / 4.0;

  cv.Point tl = pts[0], tr = pts[0], br = pts[0], bl = pts[0];
  double minSum = double.infinity, maxSum = -double.infinity;
  double minDiff = double.infinity, maxDiff = -double.infinity;

  for (final p in pts) {
    final sum = (p.x + p.y).toDouble();
    final diff = (p.x - p.y).toDouble();

    if (sum < minSum) { minSum = sum; tl = p; }
    if (sum > maxSum) { maxSum = sum; br = p; }
    if (diff > maxDiff) { maxDiff = diff; tr = p; }
    if (diff < minDiff) { minDiff = diff; bl = p; }
  }

  final unique = {tl, tr, br, bl};
  if (unique.length < 4) {
    final list = List<cv.Point>.from(pts);
    list.sort((a, b) => atan2(a.y - cy, a.x - cx).compareTo(atan2(b.y - cy, b.x - cx)));
    int tlIdx = 0;
    double bestSum = double.infinity;
    for (int i = 0; i < 4; i++) {
      final s = (list[i].x + list[i].y).toDouble();
      if (s < bestSum) { bestSum = s; tlIdx = i; }
    }
    tl = list[tlIdx];
    tr = list[(tlIdx + 1) % 4];
    br = list[(tlIdx + 2) % 4];
    bl = list[(tlIdx + 3) % 4];
  }

  return (tl, tr, br, bl);
}

double _quadArea(List<cv.Point> pts) {
  if (pts.length != 4) return 0;
  double area = 0;
  for (int i = 0; i < 4; i++) {
    final j = (i + 1) % 4;
    area += pts[i].x * pts[j].y;
    area -= pts[j].x * pts[i].y;
  }
  return area.abs() / 2;
}

// ═══════════════════════════════════════════════════════════════════════════
// 2. HIGH-RESOLUTION PERSPECTIVE TRANSFORMATION & DESKEW (ISOLATE)
// ═══════════════════════════════════════════════════════════════════════════
Future<Uint8List> _cropIsolate(Map<String, dynamic> params) async {
  final Uint8List bytes = params['bytes'];
  final Map<String, double> c = params['corners'];
  int rotation = params['rotation'];

  final mat = cv.imdecode(bytes, cv.IMREAD_COLOR);
  if (mat.isEmpty) return bytes;

  final width = mat.cols;
  final height = mat.rows;

  final p0 = cv.Point2f(c['tlX']! * width, c['tlY']! * height);
  final p1 = cv.Point2f(c['trX']! * width, c['trY']! * height);
  final p3 = cv.Point2f(c['blX']! * width, c['blY']! * height);
  final p2 = cv.Point2f(c['brX']! * width, c['brY']! * height);

  // Compute precise output physical dimensions
  final wTop = sqrt(pow(p1.x - p0.x, 2) + pow(p1.y - p0.y, 2));
  final wBottom = sqrt(pow(p2.x - p3.x, 2) + pow(p2.y - p3.y, 2));
  final hLeft = sqrt(pow(p3.x - p0.x, 2) + pow(p3.y - p0.y, 2));
  final hRight = sqrt(pow(p2.x - p1.x, 2) + pow(p2.y - p1.y, 2));

  final outW = max(wTop, wBottom).round().clamp(100, 8000);
  final outH = max(hLeft, hRight).round().clamp(100, 8000);

  final srcPts = [p0, p1, p2, p3];
  final dstPts = [
    cv.Point2f(0, 0),
    cv.Point2f(outW.toDouble(), 0),
    cv.Point2f(outW.toDouble(), outH.toDouble()),
    cv.Point2f(0, outH.toDouble()),
  ];

  final transform = cv.getPerspectiveTransform2f(
    cv.VecPoint2f.fromList(srcPts), cv.VecPoint2f.fromList(dstPts));
  final warped = cv.warpPerspective(mat, transform, (outW, outH));

  var finalMat = warped;
  if (rotation == 90) {
    finalMat = cv.rotate(warped, cv.ROTATE_90_CLOCKWISE);
  } else if (rotation == 180) {
    finalMat = cv.rotate(warped, cv.ROTATE_180);
  } else if (rotation == 270) {
    finalMat = cv.rotate(warped, cv.ROTATE_90_COUNTERCLOCKWISE);
  }

  // Preserve full high-resolution image quality (Quality 96)
  final (success, encoded) = cv.imencode('.jpg', finalMat, params: cv.VecI32.fromList([cv.IMWRITE_JPEG_QUALITY, 96]));
  return encoded;
}

// ═══════════════════════════════════════════════════════════════════════════
// 3. CAMSCANNER-LEVEL ILLUMINATION-NORMALIZED ENHANCEMENT (ISOLATE)
// ═══════════════════════════════════════════════════════════════════════════
Future<Uint8List> _filterIsolate(Map<String, dynamic> params) async {
  final Uint8List bytes = params['bytes'];
  final int typeIndex = params['type'];
  final DocumentFilterType type = DocumentFilterType.values[typeIndex];

  final mat = cv.imdecode(bytes, cv.IMREAD_COLOR);
  if (mat.isEmpty) return bytes;

  final origW = mat.cols;
  final origH = mat.rows;

  // ═══════════════════════════════════════════════════════════════════════════
  // 1. MULTI-SCALE PER-CHANNEL ILLUMINATION SURFACE ESTIMATION
  // ═══════════════════════════════════════════════════════════════════════════
  final channels = cv.split(mat); // B, G, R
  final List<cv.Mat> normChannels = [];

  for (int i = 0; i < 3; i++) {
    final ch = channels[i];
    final bgSmall = cv.resize(ch, (256, (256 * origH / origW).round()), interpolation: cv.INTER_AREA);
    final bgBlurredSmall = cv.gaussianBlur(bgSmall, (31, 31), 14.0);
    final bgFull = cv.resize(bgBlurredSmall, (origW, origH), interpolation: cv.INTER_LINEAR);
    
    // Per-channel division: All paper colors (white, yellow, grey shadow) normalize to clean 255!
    final divCh = cv.divide(ch, bgFull, scale: 255.0);
    normChannels.add(divCh);
  }

  // Normalized color image (Pure clean neutral paper, zero color casts)
  final normColor = cv.merge(cv.VecMat.fromList(normChannels));

  // Compute normalized grayscale for text detection & stroke restoration
  final normGray = cv.cvtColor(normColor, cv.COLOR_BGR2GRAY);

  // ═══════════════════════════════════════════════════════════════════════════
  // 2. TEXT-AWARE INK DEEPENING & SAFE STROKE RESTORATION
  // ═══════════════════════════════════════════════════════════════════════════
  // High-Precision Ink LUT: Preserves paper [246-255], deepens text [0-245]
  final magicInkLutValues = <int>[];
  for (int i = 0; i < 256; i++) {
    if (i >= 246) {
      magicInkLutValues.add(255);
    } else {
      final double norm = i / 246.0;
      // Power 2.1 deepens handwriting, signatures, numbers, and fine table lines
      final double deep = 255.0 * pow(norm, 2.1);
      magicInkLutValues.add(deep.round().clamp(0, 255));
    }
  }
  final magicInkLut = cv.Mat.fromList(1, 256, cv.MatType.CV_8UC1, magicInkLutValues);

  final autoInkLutValues = <int>[];
  for (int i = 0; i < 256; i++) {
    if (i >= 248) {
      autoInkLutValues.add(255);
    } else {
      final double norm = i / 248.0;
      final double deep = 255.0 * pow(norm, 1.7);
      autoInkLutValues.add(deep.round().clamp(0, 255));
    }
  }
  final autoInkLut = cv.Mat.fromList(1, 256, cv.MatType.CV_8UC1, autoInkLutValues);

  cv.Mat result;

  switch (type) {
    // ── MAGIC COLOR: Pristine White Paper + Deep Vivid Ink + Reconnected Handwriting & Tables ──
    case DocumentFilterType.magic:
      final List<cv.Mat> magicChannels = [];
      for (int i = 0; i < 3; i++) {
        final deepened = cv.LUT(normChannels[i], magicInkLut);
        magicChannels.add(deepened);
      }
      final mergedMagic = cv.merge(cv.VecMat.fromList(magicChannels));

      // Safe Stroke Healing on Text & Table Lines (3x3 closing reconnects tiny micro-gaps)
      final kStroke = cv.getStructuringElement(cv.MORPH_ELLIPSE, (3, 3));
      final closedMagic = cv.morphologyEx(mergedMagic, cv.MORPH_CLOSE, kStroke);
      // Blend 85% original deepened with 15% closed to preserve natural stroke texture
      final healedMagic = cv.addWeighted(mergedMagic, 0.85, closedMagic, 0.15, 0.0);

      // Controlled Text-Aware Unsharp Sharpening (Zero Halos)
      final blur = cv.gaussianBlur(healedMagic, (0, 0), 0.9);
      result = cv.addWeighted(healedMagic, 1.30, blur, -0.30, 0.0);
      break;

    // ── AUTO: Natural Document Warmth + Balanced Text Clarity + Neutral White Balance ──
    case DocumentFilterType.auto:
      final List<cv.Mat> autoChannels = [];
      for (int i = 0; i < 3; i++) {
        final deepened = cv.LUT(normChannels[i], autoInkLut);
        autoChannels.add(deepened);
      }
      final mergedAuto = cv.merge(cv.VecMat.fromList(autoChannels));

      final blur = cv.gaussianBlur(mergedAuto, (0, 0), 0.8);
      result = cv.addWeighted(mergedAuto, 1.20, blur, -0.20, 0.0);
      break;

    // ── GRAYSCALE: High-Fidelity Monochrome (Crisp Dark Text on Pure Paper) ──
    case DocumentFilterType.grayscale:
      final deepGray = cv.LUT(normGray, magicInkLut);
      final kStroke = cv.getStructuringElement(cv.MORPH_ELLIPSE, (3, 3));
      final closedGray = cv.morphologyEx(deepGray, cv.MORPH_CLOSE, kStroke);
      final healedGray = cv.addWeighted(deepGray, 0.85, closedGray, 0.15, 0.0);

      final blur = cv.gaussianBlur(healedGray, (0, 0), 0.9);
      final sharpGray = cv.addWeighted(healedGray, 1.30, blur, -0.30, 0.0);
      result = cv.cvtColor(sharpGray, cv.COLOR_GRAY2BGR);
      break;

    // ── BLACK & WHITE: Reference Working Adaptive B&W ──
    case DocumentFilterType.blackAndWhite:
      final binary = cv.adaptiveThreshold(
        normGray, 255, cv.ADAPTIVE_THRESH_GAUSSIAN_C, cv.THRESH_BINARY, 31, 15);
      result = cv.cvtColor(binary, cv.COLOR_GRAY2BGR);
      break;

    // ── LIGHTEN: Brighten Dark Documents + Reduce Shadows + Preserve Thin Text ──
    case DocumentFilterType.lighten:
      final lightenInkLutValues = <int>[];
      for (int i = 0; i < 256; i++) {
        if (i >= 250) {
          lightenInkLutValues.add(255);
        } else {
          final double norm = i / 250.0;
          final double deep = 255.0 * pow(norm, 1.4);
          lightenInkLutValues.add(deep.round().clamp(0, 255));
        }
      }
      final lightenInkLut = cv.Mat.fromList(1, 256, cv.MatType.CV_8UC1, lightenInkLutValues);
      final List<cv.Mat> lightenChannels = [];
      for (int i = 0; i < 3; i++) {
        final deepened = cv.LUT(normChannels[i], lightenInkLut);
        lightenChannels.add(deepened);
      }
      final mergedLighten = cv.merge(cv.VecMat.fromList(lightenChannels));
      final blurL = cv.gaussianBlur(mergedLighten, (0, 0), 0.7);
      result = cv.addWeighted(mergedLighten, 1.15, blurL, -0.15, 0.0);
      break;

    case DocumentFilterType.original:
    default:
      result = mat;
      break;
  }

  // Preserve full high-resolution image quality (Quality 98)
  final (success, encoded) = cv.imencode('.jpg', result, params: cv.VecI32.fromList([cv.IMWRITE_JPEG_QUALITY, 98]));
  return encoded;
}
