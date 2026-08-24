import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:injectable/injectable.dart';
import 'package:path/path.dart' as p;
import '../../domain/entities/scanned_document.dart';
import '../../data/repositories/local_document_repository.dart';
import '../../data/services/export_service.dart';

@lazySingleton
class DocumentProvider extends ChangeNotifier {
  final LocalDocumentRepository _repository;
  final ExportService _exportService;

  List<ScannedDocument> _documents = [];
  bool _isLoading = true;

  List<ScannedDocument> get documents => _documents;
  bool get isLoading => _isLoading;

  DocumentProvider(this._repository, this._exportService) {
    loadDocuments();
  }

  Future<void> loadDocuments() async {
    _isLoading = true;
    notifyListeners();
    
    _documents = await _repository.getAllDocuments();
    
    _isLoading = false;
    notifyListeners();
  }

  String generateDefaultDocumentName() {
    final now = DateTime.now();
    final day = now.day.toString().padLeft(2, '0');
    final month = now.month.toString().padLeft(2, '0');
    final year = (now.year % 100).toString().padLeft(2, '0');
    final baseName = 'AH Scanner $day.$month.$year';

    final existingNames = _documents.map((d) => d.name).toSet();
    if (!existingNames.contains(baseName)) {
      return baseName;
    }

    int index = 1;
    while (existingNames.contains('$baseName ($index)')) {
      index++;
    }
    return '$baseName ($index)';
  }

  Future<void> saveNewDocument(Uint8List finalImageBytes, {Uint8List? rawImageBytes, String? customName}) async {
    final String docId = DateTime.now().millisecondsSinceEpoch.toString();
    final String defaultName = customName ?? generateDefaultDocumentName();
    
    final String pagePath = await _exportService.saveDocumentPage(docId, finalImageBytes, 1);
    final String rawPath = rawImageBytes != null 
        ? await _exportService.saveRawPage(docId, rawImageBytes, 1)
        : pagePath;
    final String thumbPath = await _exportService.createThumbnail(docId, finalImageBytes);

    final newDoc = ScannedDocument(
      id: docId,
      name: defaultName,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      dirPath: p.dirname(pagePath),
      pagePaths: [pagePath],
      rawPagePaths: [rawPath],
      thumbnailPath: thumbPath,
    );

    await _repository.saveDocument(newDoc);
    _documents.insert(0, newDoc);
    notifyListeners();
  }

  Future<ScannedDocument?> addPageToDocument(String docId, Uint8List finalImageBytes, {Uint8List? rawImageBytes}) async {
    final docIndex = _documents.indexWhere((d) => d.id == docId);
    if (docIndex == -1) return null;
    final doc = _documents[docIndex];
    final pageNumber = doc.pagePaths.length + 1;
    final String pagePath = await _exportService.saveDocumentPage(docId, finalImageBytes, pageNumber);
    final String rawPath = rawImageBytes != null 
        ? await _exportService.saveRawPage(docId, rawImageBytes, pageNumber)
        : pagePath;

    final updatedPages = List<String>.from(doc.pagePaths)..add(pagePath);
    final updatedRawPages = List<String>.from(doc.rawPagePaths)..add(rawPath);

    final updatedDoc = doc.copyWith(
      pagePaths: updatedPages,
      rawPagePaths: updatedRawPages,
      updatedAt: DateTime.now(),
    );
    await _repository.saveDocument(updatedDoc);
    _documents[docIndex] = updatedDoc;
    notifyListeners();
    return updatedDoc;
  }

  Future<ScannedDocument?> updateExistingPage(String docId, int pageIndex, Uint8List finalImageBytes) async {
    final docIndex = _documents.indexWhere((d) => d.id == docId);
    if (docIndex == -1) return null;
    final doc = _documents[docIndex];
    if (pageIndex < 0 || pageIndex >= doc.pagePaths.length) return null;

    final String pagePath = await _exportService.saveDocumentPage(docId, finalImageBytes, pageIndex + 1);
    
    // Update thumbnail if this is page 0
    String newThumb = doc.thumbnailPath;
    if (pageIndex == 0) {
      newThumb = await _exportService.createThumbnail(docId, finalImageBytes);
    }

    final updatedPages = List<String>.from(doc.pagePaths);
    updatedPages[pageIndex] = pagePath;

    final updatedDoc = doc.copyWith(
      pagePaths: updatedPages,
      thumbnailPath: newThumb,
      updatedAt: DateTime.now(),
    );

    await _repository.saveDocument(updatedDoc);
    _documents[docIndex] = updatedDoc;
    notifyListeners();
    return updatedDoc;
  }

  Future<void> addDocument(ScannedDocument doc) async {
    await _repository.saveDocument(doc);
    _documents.insert(0, doc);
    notifyListeners();
  }

  Future<void> renameDocument(String id, String newName) async {
    final index = _documents.indexWhere((d) => d.id == id);
    if (index >= 0) {
      _documents[index].name = newName;
      _documents[index].updatedAt = DateTime.now();
      await _repository.saveDocument(_documents[index]);
      notifyListeners();
    }
  }

  Future<void> updateDocument(ScannedDocument doc) async {
    final index = _documents.indexWhere((d) => d.id == doc.id);
    if (index >= 0) {
      _documents[index] = doc;
      await _repository.saveDocument(doc);
      notifyListeners();
    }
  }

  List<String> get folders {
    final names = _documents
        .map((d) => d.folder.trim())
        .where((f) => f.isNotEmpty)
        .toSet()
        .toList();
    names.sort();
    return names;
  }

  Future<void> moveToFolder(String id, String folderName) async {
    final index = _documents.indexWhere((d) => d.id == id);
    if (index >= 0) {
      _documents[index] = _documents[index].copyWith(folder: folderName, updatedAt: DateTime.now());
      await _repository.saveDocument(_documents[index]);
      notifyListeners();
    }
  }

  Future<void> deleteDocument(String id) async {
    await _exportService.deleteDocumentDirectory(id);
    await _repository.deleteDocument(id);
    _documents.removeWhere((d) => d.id == id);
    notifyListeners();
  }

  Future<void> clearAllLocalData() async {
    for (var doc in _documents) {
      await _exportService.deleteDocumentDirectory(doc.id);
    }
    await _repository.deleteAll();
    _documents.clear();
    notifyListeners();
  }

  String _formatDate(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} ${dt.hour.toString().padLeft(2, '0')}-${dt.minute.toString().padLeft(2, '0')}';
  }
}
