import 'package:camera/camera.dart';
import '../entities/document_corners.dart';

abstract class IDocumentDetector {
  Future<DocumentCorners?> detectEdges(CameraImage image);
  void dispose();
}
