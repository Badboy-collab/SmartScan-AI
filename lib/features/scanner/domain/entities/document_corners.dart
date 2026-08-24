import 'dart:ui';

class DocumentCorners {
  final Offset topLeft;
  final Offset topRight;
  final Offset bottomLeft;
  final Offset bottomRight;

  const DocumentCorners({
    required this.topLeft,
    required this.topRight,
    required this.bottomLeft,
    required this.bottomRight,
  });

  DocumentCorners copyWith({
    Offset? topLeft,
    Offset? topRight,
    Offset? bottomLeft,
    Offset? bottomRight,
  }) {
    return DocumentCorners(
      topLeft: topLeft ?? this.topLeft,
      topRight: topRight ?? this.topRight,
      bottomLeft: bottomLeft ?? this.bottomLeft,
      bottomRight: bottomRight ?? this.bottomRight,
    );
  }

  bool get isValid {
    // Simple check to ensure corners form a valid convex quadrilateral roughly
    // In a real app, calculate cross products to ensure convexity
    return topLeft.dx < topRight.dx && bottomLeft.dx < bottomRight.dx &&
           topLeft.dy < bottomLeft.dy && topRight.dy < bottomRight.dy;
  }

  // Calculate center points to verify stability
  Offset get center {
    return Offset(
      (topLeft.dx + topRight.dx + bottomLeft.dx + bottomRight.dx) / 4,
      (topLeft.dy + topRight.dy + bottomLeft.dy + bottomRight.dy) / 4,
    );
  }

  // Check if this matches another set of corners within a threshold
  bool isStableComparedTo(DocumentCorners other, double threshold) {
    return (topLeft - other.topLeft).distance < threshold &&
           (topRight - other.topRight).distance < threshold &&
           (bottomLeft - other.bottomLeft).distance < threshold &&
           (bottomRight - other.bottomRight).distance < threshold;
  }
}
