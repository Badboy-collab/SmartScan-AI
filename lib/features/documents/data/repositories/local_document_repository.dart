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
      if (await file.exists()) {
        final String content = await file.readAsString();
        if (content.trim().isNotEmpty) {
          final List<dynamic> jsonList = jsonDecode(content);
          return jsonList.map((e) => ScannedDocument.fromJson(e as Map<String, dynamic>)).toList();
        }
      }
      // Try backup file if main file is empty
      final dir = await getApplicationDocumentsDirectory();
      final backupFile = File(p.join(dir.path, '$_indexFileName.bak'));
      if (await backupFile.exists()) {
        final String content = await backupFile.readAsString();
        final List<dynamic> jsonList = jsonDecode(content);
        return jsonList.map((e) => ScannedDocument.fromJson(e as Map<String, dynamic>)).toList();
      }
      return [];
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
    final dir = await getApplicationDocumentsDirectory();
    final file = File(p.join(dir.path, _indexFileName));
    final tmpFile = File(p.join(dir.path, '$_indexFileName.tmp'));
    final bakFile = File(p.join(dir.path, '$_indexFileName.bak'));

    final String content = jsonEncode(docs.map((e) => e.toJson()).toList());
    
    // 1. Write to temp file
    await tmpFile.writeAsString(content, flush: true);
    
    // 2. Backup existing file if present
    if (await file.exists()) {
      try {
        await file.copy(bakFile.path);
      } catch (_) {}
    }
    
    // 3. Atomically rename temp file to target
    await tmpFile.rename(file.path);
  }
}
