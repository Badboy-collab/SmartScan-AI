import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:flutter/services.dart';
import 'package:open_filex/open_filex.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../conversion/data/services/excel_export_service.dart';
import '../../../conversion/data/services/powerpoint_export_service.dart';
import '../../../conversion/data/services/word_export_service.dart';
import '../../../conversion/domain/models/document_structure.dart';
import '../../data/datasources/cloud_vision_ocr_service.dart';

class OcrPage extends StatefulWidget {
  final bool startInExcelMode;

  /// Which converter the caller came for: 'text' (default), 'word', 'excel' or
  /// 'ppt'. Set through /ocr?mode=... by the scanner mode strip and the Tools
  /// grid, so tapping "To Word" opens this page ready to export a .docx.
  final String initialFormat;

  const OcrPage({
    super.key,
    this.startInExcelMode = false,
    this.initialFormat = 'text',
  });

  @override
  State<OcrPage> createState() => _OcrPageState();
}

class _OcrPageState extends State<OcrPage> with SingleTickerProviderStateMixin {
  String _extractedText = '';
  List<List<String>> _tableRows = [];
  bool _isProcessing = false;
  File? _imageFile;
  late TabController _tabController;
  late TextEditingController _textController;
  TextRecognitionScript _script = TextRecognitionScript.latin;
  bool _useCloud = false;

  @override
  void initState() {
    super.initState();
    final startOnTableTab = widget.startInExcelMode || widget.initialFormat == 'excel';
    _tabController = TabController(length: 2, vsync: this, initialIndex: startOnTableTab ? 1 : 0);
    _textController = TextEditingController();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _pickImage();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _textController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    try {
      final picker = ImagePicker();
      final pickedFile = await picker.pickImage(source: ImageSource.gallery);
      if (pickedFile != null) {
        setState(() {
          _imageFile = File(pickedFile.path);
          _isProcessing = true;
        });
        _processImage();
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  Future<void> _processImage() async {
    if (_imageFile == null) return;

    try {
      if (_useCloud) {
        // Cloud Vision path — supports Bangla and many other scripts.
        final prefs = await SharedPreferences.getInstance();
        final apiKey = prefs.getString('google_vision_api_key') ?? '';
        final bytes = await _imageFile!.readAsBytes();
        final text = await CloudVisionOcrService().recognizeText(
          bytes,
          apiKey: apiKey,
          languageHints: const ['bn', 'en'],
        );
        setState(() {
          _extractedText = text;
          _textController.text = text;
          _tableRows = [];
        });
        return;
      }

      final inputImage = InputImage.fromFile(_imageFile!);
      final textRecognizer = TextRecognizer(script: _script);
      try {
        final RecognizedText recognizedText = await textRecognizer.processImage(inputImage);

        // 1. Plain Text
        final fullText = recognizedText.text;

        // 2. Intelligent 2D Geometric Multi-Column & Table Detection
        final table = _extractGeometricTable(recognizedText);

        setState(() {
          _extractedText = fullText;
          _textController.text = fullText;
          _tableRows = table;
        });
      } finally {
        textRecognizer.close();
      }
    } catch (e) {
      setState(() {
        _extractedText = 'Error recognizing text: $e';
        _textController.text = _extractedText;
      });
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  List<List<String>> _extractGeometricTable(RecognizedText recognizedText) {
    final List<_CellBox> allCells = [];

    // Collect all text lines with precise 2D bounding boxes
    for (final block in recognizedText.blocks) {
      for (final line in block.lines) {
        if (line.text.trim().isNotEmpty) {
          allCells.add(_CellBox(
            text: line.text.trim(),
            rect: line.boundingBox,
          ));
        }
      }
    }

    if (allCells.isEmpty) return [];

    // 1. Sort all elements vertically (top to bottom)
    allCells.sort((a, b) => a.rect.top.compareTo(b.rect.top));

    // Dynamic row clustering tolerance based on median line height
    final avgHeight = allCells.map((c) => c.rect.height).reduce((a, b) => a + b) / allCells.length;
    final rowTolerance = (avgHeight * 0.75).clamp(12.0, 36.0);

    // 2. Cluster into Rows
    final List<List<_CellBox>> rawRows = [];
    List<_CellBox> currentRow = [];
    double currentRowTop = allCells.first.rect.top;

    for (final cell in allCells) {
      if (currentRow.isEmpty) {
        currentRow.add(cell);
        currentRowTop = cell.rect.top;
      } else if ((cell.rect.top - currentRowTop).abs() <= rowTolerance) {
        currentRow.add(cell);
      } else {
        currentRow.sort((a, b) => a.rect.left.compareTo(b.rect.left));
        rawRows.add(currentRow);
        currentRow = [cell];
        currentRowTop = cell.rect.top;
      }
    }
    if (currentRow.isNotEmpty) {
      currentRow.sort((a, b) => a.rect.left.compareTo(b.rect.left));
      rawRows.add(currentRow);
    }

    // 3. Detect Global Column Boundaries (X-clustering)
    final List<double> allXCenters = [];
    for (final row in rawRows) {
      for (final cell in row) {
        allXCenters.add(cell.rect.center.dx);
      }
    }
    allXCenters.sort();

    final List<double> columnCenters = [];
    const double colClusterGap = 55.0; // Distance between column centers

    for (final x in allXCenters) {
      if (columnCenters.isEmpty) {
        columnCenters.add(x);
      } else {
        bool merged = false;
        for (int i = 0; i < columnCenters.length; i++) {
          if ((columnCenters[i] - x).abs() < colClusterGap) {
            columnCenters[i] = (columnCenters[i] + x) / 2.0;
            merged = true;
            break;
          }
        }
        if (!merged) {
          columnCenters.add(x);
        }
      }
    }
    columnCenters.sort();

    // 4. Align Rows into Multi-Column Grid
    final int numCols = max(1, columnCenters.length);
    final List<List<String>> structuredGrid = [];

    for (final row in rawRows) {
      final List<String> gridRow = List.filled(numCols, '');
      for (final cell in row) {
        final cellCenterX = cell.rect.center.dx;
        int bestCol = 0;
        double minDistance = double.infinity;

        for (int c = 0; c < numCols; c++) {
          final dist = (columnCenters[c] - cellCenterX).abs();
          if (dist < minDistance) {
            minDistance = dist;
            bestCol = c;
          }
        }

        if (gridRow[bestCol].isEmpty) {
          gridRow[bestCol] = cell.text;
        } else {
          gridRow[bestCol] = '${gridRow[bestCol]} ${cell.text}';
        }
      }

      // Filter out any columns that are empty across all rows
      if (gridRow.any((val) => val.trim().isNotEmpty)) {
        structuredGrid.add(gridRow);
      }
    }

    // Cleanup: Remove entirely empty columns
    if (structuredGrid.isNotEmpty) {
      final List<int> activeColumns = [];
      for (int c = 0; c < numCols; c++) {
        if (structuredGrid.any((row) => row[c].trim().isNotEmpty)) {
          activeColumns.add(c);
        }
      }

      if (activeColumns.isNotEmpty && activeColumns.length < numCols) {
        return structuredGrid.map((row) => activeColumns.map((colIdx) => row[colIdx]).toList()).toList();
      }
    }

    return structuredGrid.isNotEmpty ? structuredGrid : rawRows.map((r) => r.map((c) => c.text).toList()).toList();
  }

  /// Shapes the OCR result the way the Office converters expect it.
  AnalyzedDocument _buildAnalyzedDocument() {
    final List<DocTableRow> docRows = [];
    final int numCols = _tableRows.isNotEmpty ? _tableRows.first.length : 1;

    for (int r = 0; r < _tableRows.length; r++) {
      final row = _tableRows[r];
      final List<DocTableCell> cells = [];
      for (int c = 0; c < row.length; c++) {
        final cellText = row[c];
        final num? numVal = num.tryParse(cellText.replaceAll(RegExp(r'[^0-9\.-]'), ''));
        cells.add(DocTableCell(
          text: cellText,
          boundingBox: Rect.zero,
          isNumeric: numVal != null,
          numericValue: numVal,
        ));
      }
      docRows.add(DocTableRow(cells: cells, isHeader: r == 0));
    }

    final page = AnalyzedPage(
      pageNumber: 1,
      pageSize: const Size(1000, 1400),
      title: 'Scanned Table',
      elements: [],
      tables: [
        DocTable(
          rows: docRows,
          columnCount: numCols,
          boundingBox: Rect.zero,
        ),
      ],
      paragraphs: _extractedText.split('\n').where((l) => l.trim().isNotEmpty).map((l) => DocParagraph(text: l, boundingBox: Rect.zero)).toList(),
    );

    return AnalyzedDocument(pages: [page]);
  }

  static const String _xlsxMime = 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
  static const String _docxMime = 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
  static const String _pptxMime = 'application/vnd.openxmlformats-officedocument.presentationml.presentation';

  /// Runs one converter and then offers to open the finished file.
  Future<void> _runExport({
    required String label,
    required String mime,
    required Future<File> Function(AnalyzedDocument document, String baseName) convert,
  }) async {
    if (_tableRows.isEmpty && _extractedText.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No data to export')));
      return;
    }

    try {
      final baseName = 'Scanned_Table_${DateTime.now().millisecondsSinceEpoch}';
      final file = await convert(_buildAnalyzedDocument(), baseName);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Exported to $label successfully!'),
          action: SnackBarAction(
            label: 'OPEN',
            onPressed: () => OpenFilex.open(file.path, type: mime),
          ),
        ),
      );
      // Direct open in the matching Office viewer.
      await OpenFilex.open(file.path, type: mime);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Export error: $e')));
    }
  }

  Future<void> _exportExcel() => _runExport(
        label: 'Excel (.xlsx)',
        mime: _xlsxMime,
        convert: (doc, baseName) => ExcelExportService.exportToXlsx(document: doc, baseFileName: baseName),
      );

  Future<void> _exportWord() => _runExport(
        label: 'Word (.docx)',
        mime: _docxMime,
        convert: (doc, baseName) => WordExportService.exportToDocx(document: doc, baseFileName: baseName),
      );

  Future<void> _exportPpt() => _runExport(
        label: 'PowerPoint (.pptx)',
        mime: _pptxMime,
        convert: (doc, baseName) => PowerPointExportService.exportToPptx(document: doc, baseFileName: baseName),
      );

  /// The single export entry point (app bar and table header both use it).
  Widget _buildExportMenu() {
    return PopupMenuButton<String>(
      tooltip: 'Export as Excel, Word or PowerPoint',
      onSelected: (value) async {
        if (value == 'excel') {
          await _exportExcel();
        } else if (value == 'word') {
          await _exportWord();
        } else if (value == 'ppt') {
          await _exportPpt();
        }
      },
      itemBuilder: (_) => const [
        PopupMenuItem(
          value: 'excel',
          child: ListTile(dense: true, leading: Icon(Icons.table_chart_outlined), title: Text('Excel (.xlsx)')),
        ),
        PopupMenuItem(
          value: 'word',
          child: ListTile(dense: true, leading: Icon(Icons.description_outlined), title: Text('Word (.docx)')),
        ),
        PopupMenuItem(
          value: 'ppt',
          child: ListTile(dense: true, leading: Icon(Icons.slideshow_outlined), title: Text('PowerPoint (.pptx)')),
        ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFF107C41),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.file_download, size: 16, color: Colors.white),
            SizedBox(width: 6),
            Text('Export', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
            Icon(Icons.arrow_drop_down, color: Colors.white),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Scan to Text & Office'),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.add_photo_alternate_outlined),
            tooltip: 'Pick New Image',
            onPressed: _pickImage,
          ),
          IconButton(
            icon: const Icon(Icons.copy),
            tooltip: 'Copy Text',
            onPressed: () {
              if (_extractedText.isNotEmpty) {
                Clipboard.setData(ClipboardData(text: _textController.text));
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Text copied to clipboard')));
              }
            },
          ),
          _buildExportMenu(),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.teal,
          unselectedLabelColor: isDark ? Colors.white60 : Colors.black54,
          indicatorColor: Colors.teal,
          indicatorWeight: 3,
          tabs: const [
            Tab(icon: Icon(Icons.text_fields), text: 'Text Mode'),
            Tab(icon: Icon(Icons.table_view), text: 'To Excel / Table'),
          ],
        ),
      ),
      body: Column(
        children: [
          _buildScriptSelector(isDark),
          if (_imageFile != null)
            Container(
              height: 140,
              width: double.infinity,
              color: isDark ? Colors.black38 : const Color(0xFFE2E8F0),
              child: Image.file(_imageFile!, fit: BoxFit.contain),
            ),
          Expanded(
            child: _isProcessing
                ? const Center(child: CircularProgressIndicator(color: Colors.teal))
                : _extractedText.isEmpty
                    ? Center(
                        child: ElevatedButton.icon(
                          onPressed: _pickImage,
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.teal, foregroundColor: Colors.white),
                          icon: const Icon(Icons.image),
                          label: const Text('Select Image to Scan'),
                        ),
                      )
                    : TabBarView(
                        controller: _tabController,
                        children: [
                          // 1. Text Mode
                          Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: TextField(
                              controller: _textController,
                              maxLines: null,
                              expands: true,
                              style: TextStyle(
                                color: theme.textTheme.bodyLarge?.color,
                                fontSize: 15,
                                height: 1.5,
                              ),
                              decoration: InputDecoration(
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: BorderSide(color: isDark ? Colors.white24 : Colors.black12),
                                ),
                                filled: true,
                                fillColor: theme.cardColor,
                              ),
                            ),
                          ),

                          // 2. Table / Excel Mode (Professional 2D Spreadsheet View)
                          _tableRows.isEmpty
                              ? const Center(child: Text('No tabular data detected'))
                              : Column(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 10.0),
                                      decoration: BoxDecoration(
                                        color: theme.cardColor,
                                        border: Border(bottom: BorderSide(color: isDark ? Colors.white12 : const Color(0xFFE2E8F0))),
                                      ),
                                      child: Row(
                                        children: [
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  '${_tableRows.length} Rows × ${_tableRows.first.length} Columns',
                                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.teal),
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                                const SizedBox(height: 2),
                                                Text(
                                                  'Spreadsheet Grid View',
                                                  style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                                                ),
                                              ],
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          _buildExportMenu(),
                                        ],
                                      ),
                                    ),
                                    Expanded(
                                      child: SingleChildScrollView(
                                        padding: const EdgeInsets.all(8.0),
                                        child: SingleChildScrollView(
                                          scrollDirection: Axis.horizontal,
                                          child: _buildSpreadsheetGrid(theme, isDark),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                        ],
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildScriptSelector(bool isDark) {
    const scripts = <(TextRecognitionScript, String)>[
      (TextRecognitionScript.latin, 'English'),
      (TextRecognitionScript.devanagiri, 'Hindi'),
      (TextRecognitionScript.chinese, '中文'),
      (TextRecognitionScript.japanese, '日本語'),
      (TextRecognitionScript.korean, '한국어'),
    ];

    return Container(
      height: 46,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      color: isDark ? Colors.black26 : const Color(0xFFF8FAFC),
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          for (final (script, label) in scripts)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(label, style: const TextStyle(fontSize: 12)),
                selected: !_useCloud && _script == script,
                selectedColor: Colors.teal,
                labelStyle: TextStyle(
                  fontSize: 12,
                  color: !_useCloud && _script == script ? Colors.white : null,
                ),
                onSelected: (_) {
                  if (!_useCloud && _script == script) return;
                  setState(() {
                    _useCloud = false;
                    _script = script;
                    _isProcessing = true;
                  });
                  if (_imageFile != null) _processImage();
                },
              ),
            ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: const Text('বাংলা (Cloud)', style: TextStyle(fontSize: 12)),
              selected: _useCloud,
              selectedColor: Colors.indigo,
              labelStyle: TextStyle(
                fontSize: 12,
                color: _useCloud ? Colors.white : null,
              ),
              onSelected: (_) {
                if (_useCloud) return;
                setState(() {
                  _useCloud = true;
                  _isProcessing = true;
                });
                if (_imageFile != null) _processImage();
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSpreadsheetGrid(ThemeData theme, bool isDark) {
    if (_tableRows.isEmpty) return const SizedBox.shrink();
    final int numCols = _tableRows.first.length;

    return Container(
      decoration: BoxDecoration(
        color: theme.cardColor,
        border: Border.all(color: isDark ? Colors.white24 : const Color(0xFFCBD5E1)),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Table(
        defaultVerticalAlignment: TableCellVerticalAlignment.middle,
        border: TableBorder.all(
          color: isDark ? Colors.white12 : const Color(0xFFE2E8F0),
          width: 1,
        ),
        defaultColumnWidth: const IntrinsicColumnWidth(),
        children: [
          // 1. Column Letter Header Row (A, B, C, D, ...)
          TableRow(
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0),
            ),
            children: [
              // Corner Cell
              Container(
                width: 36,
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                alignment: Alignment.center,
                child: Text('#', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: isDark ? Colors.white60 : Colors.black54)),
              ),
              ...List.generate(numCols, (c) {
                return Container(
                  padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                  alignment: Alignment.center,
                  child: Text(
                    _colName(c),
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: isDark ? Colors.white70 : Colors.black87),
                  ),
                );
              }),
            ],
          ),

          // 2. Data Rows with Row Number on the left
          ..._tableRows.asMap().entries.map((entry) {
            final rowIndex = entry.key;
            final row = entry.value;
            final isHeader = rowIndex == 0;

            return TableRow(
              decoration: BoxDecoration(
                color: isHeader
                    ? (isDark ? const Color(0xFF0F3E2E) : const Color(0xFFE6F4EA))
                    : (rowIndex % 2 == 0 ? theme.cardColor : (isDark ? const Color(0xFF161B22) : const Color(0xFFF8FAFC))),
              ),
              children: [
                // Row Number Indicator
                Container(
                  width: 36,
                  padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                  ),
                  child: Text(
                    '${rowIndex + 1}',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: isDark ? Colors.white54 : Colors.black45),
                  ),
                ),
                // Cell Contents
                ...row.map((cellText) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 8.0),
                    child: Text(
                      cellText.isEmpty ? '—' : cellText,
                      style: TextStyle(
                        fontWeight: isHeader ? FontWeight.bold : FontWeight.normal,
                        color: cellText.isEmpty ? Colors.grey[400] : theme.textTheme.bodyLarge?.color,
                        fontSize: 12.5,
                      ),
                    ),
                  );
                }),
              ],
            );
          }),
        ],
      ),
    );
  }

  String _colName(int index) {
    String result = '';
    int i = index;
    while (i >= 0) {
      result = String.fromCharCode((i % 26) + 65) + result;
      i = (i ~/ 26) - 1;
    }
    return result;
  }
}

class _CellBox {
  final String text;
  final Rect rect;

  _CellBox({required this.text, required this.rect});
}
