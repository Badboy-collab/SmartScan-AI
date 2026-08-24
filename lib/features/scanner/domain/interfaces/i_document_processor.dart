import 'dart:typed_data';
import '../entities/document_filter_type.dart';
import '../entities/document_corners.dart';

abstract class IDocumentProcessor {
  Future<DocumentCorners?> detectCorners(Uint8List imageBytes);

  Future<Uint8List> cropAndCorrectPerspective({
    required Uint8List imageBytes,
    required DocumentCorners corners,
    required int rotationDegrees,
  });

  Future<Uint8List> applyFilter(Uint8List imageBytes, DocumentFilterType filterType);
}
