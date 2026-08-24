import 'dart:convert';
import 'dart:io';
import 'package:injectable/injectable.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import '../../domain/entities/scanned_document.dart';

@lazySingleton
class LocalDocumentRepository {
  static const String _indexFileName = 'documents_index.json';

  Future<File> _getIndexFile() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File(p.join(dir.path, _indexFileName));
    if (!await file.exists()) {
      await file.writeAsString(jsonEncode([]));
    }
    return file;
  }

  Future<List<ScannedDocument>> getAllDocuments() async {
    try {
      final file = await _getIndexFile();
      final String content = await file.readAsString();
      final List<dynamic> jsonList = jsonDecode(content);
      return jsonList.map((e) => ScannedDocument.fromJson(e)).toList();
    } catch (e) {
      return [];
    }
  }

  Future<void> saveDocument(ScannedDocument document) async {
    final docs = await getAllDocuments();
    final index = docs.indexWhere((d) => d.id == document.id);
    if (index >= 0) {
      docs[index] = document;
    } else {
      docs.insert(0, document); // Add new documents to the top
    }
    await _saveAll(docs);
  }

  Future<void> deleteDocument(String id) async {
    final docs = await getAllDocuments();
    docs.removeWhere((d) => d.id == id);
    await _saveAll(docs);
  }

  Future<void> deleteAll() async {
    await _saveAll([]);
  }

  Future<void> _saveAll(List<ScannedDocument> docs) async {
    final file = await _getIndexFile();
    final String content = jsonEncode(docs.map((e) => e.toJson()).toList());
    await file.writeAsString(content);
  }
}
