import 'dart:io';
import 'dart:math';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import '../../domain/models/document_structure.dart';

class DocumentLayoutAnalyzer {
  static Future<AnalyzedPage> analyzePageImage(
    File imageFile,
    int pageNumber, {
    TextRecognitionScript script = TextRecognitionScript.latin,
  }) async {
    final inputImage = InputImage.fromFile(imageFile);
    final textRecognizer = TextRecognizer(script: script);

    try {
      final RecognizedText recognizedText = await textRecognizer.processImage(inputImage);

      final List<_RawLine> allLines = [];
      for (final block in recognizedText.blocks) {
        for (final line in block.lines) {
          if (line.text.trim().isNotEmpty) {
            allLines.add(_RawLine(
              text: line.text.trim(),
              rect: line.boundingBox,
            ));
          }
        }
      }

      if (allLines.isEmpty) {
        return AnalyzedPage(
          pageNumber: pageNumber,
          pageSize: const Size(1000, 1400),
          title: 'Document Page $pageNumber',
          elements: [],
          tables: [],
          paragraphs: [],
        );
      }

      // Sort all lines vertically (top to bottom)
      allLines.sort((a, b) => a.rect.top.compareTo(b.rect.top));

      // Estimate overall page dimensions from text bounds
      final double maxRight = allLines.map((l) => l.rect.right).reduce(max);
      final double maxBottom = allLines.map((l) => l.rect.bottom).reduce(max);
      final pageSize = Size(max(800.0, maxRight + 50.0), max(1100.0, maxBottom + 50.0));

      // 1. Detect Title / Headings (Top 20% with largest height or centered)
      String pageTitle = 'Document Page $pageNumber';
      final List<DocHeading> headings = [];
      final List<_RawLine> bodyLines = [];

      final double avgHeight = allLines.map((l) => l.rect.height).reduce((a, b) => a + b) / allLines.length;

      for (int i = 0; i < allLines.length; i++) {
        final line = allLines[i];
        if (i < 3 && (line.rect.height >= avgHeight * 1.25 || line.rect.top < pageSize.height * 0.15)) {
          headings.add(DocHeading(text: line.text, level: i == 0 ? 1 : 2, boundingBox: line.rect));
          if (i == 0) pageTitle = line.text;
        } else {
          bodyLines.add(line);
        }
      }

      // 2. Detect Tables vs Paragraphs using 2D Grid Alignment
      final List<DocTable> tables = [];
      final List<DocParagraph> paragraphs = [];

      final table = _extractTableFromLines(bodyLines);
      if (table != null && table.rows.length >= 2 && table.columnCount >= 2) {
        tables.add(table);
      } else {
        // Fallback to paragraphs
        for (final line in bodyLines) {
          final isBullet = line.text.startsWith('•') || line.text.startsWith('-') || line.text.startsWith('*');
          final isNumbered = RegExp(r'^\d+[\.\)]').hasMatch(line.text);
          paragraphs.add(DocParagraph(
            text: line.text,
            isBullet: isBullet,
            isNumbered: isNumbered,
            boundingBox: line.rect,
          ));
        }
      }

      final List<DocElement> allElements = [...headings, ...tables, ...paragraphs];

      return AnalyzedPage(
        pageNumber: pageNumber,
        pageSize: pageSize,
        title: pageTitle,
        elements: allElements,
        tables: tables,
        paragraphs: paragraphs,
      );
    } catch (e) {
      debugPrint('[LayoutAnalyzer] Error: $e');
      return AnalyzedPage(
        pageNumber: pageNumber,
        pageSize: const Size(1000, 1400),
        title: 'Document Page $pageNumber',
        elements: [],
        tables: [],
        paragraphs: [],
      );
    } finally {
      textRecognizer.close();
    }
  }

  static DocTable? _extractTableFromLines(List<_RawLine> lines) {
    if (lines.isEmpty) return null;

    // Row clustering with dynamic line height tolerance
    final avgHeight = lines.map((c) => c.rect.height).reduce((a, b) => a + b) / lines.length;
    final rowTolerance = (avgHeight * 0.75).clamp(12.0, 36.0);

    final List<List<_RawLine>> rawRows = [];
    List<_RawLine> currentRow = [];
    double currentRowTop = lines.first.rect.top;

    for (final line in lines) {
      if (currentRow.isEmpty) {
        currentRow.add(line);
        currentRowTop = line.rect.top;
      } else if ((line.rect.top - currentRowTop).abs() <= rowTolerance) {
        currentRow.add(line);
      } else {
        currentRow.sort((a, b) => a.rect.left.compareTo(b.rect.left));
        rawRows.add(currentRow);
        currentRow = [line];
        currentRowTop = line.rect.top;
      }
    }
    if (currentRow.isNotEmpty) {
      currentRow.sort((a, b) => a.rect.left.compareTo(b.rect.left));
      rawRows.add(currentRow);
    }

    // Detect Global Column Boundaries
    final List<double> allXCenters = [];
    for (final row in rawRows) {
      for (final cell in row) {
        allXCenters.add(cell.rect.center.dx);
      }
    }
    allXCenters.sort();

    final List<double> columnCenters = [];
    const double colClusterGap = 55.0;

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
        if (!merged) columnCenters.add(x);
      }
    }
    columnCenters.sort();

    final int numCols = max(1, columnCenters.length);
    final List<DocTableRow> docRows = [];

    for (int r = 0; r < rawRows.length; r++) {
      final row = rawRows[r];
      final List<DocTableCell> cells = List.generate(
        numCols,
        (c) => DocTableCell(text: '', boundingBox: Rect.zero),
      );

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

        final cellText = cell.text;
        final num? parsedNum = num.tryParse(cellText.replaceAll(RegExp(r'[^0-9\.-]'), ''));

        if (cells[bestCol].text.isEmpty) {
          cells[bestCol] = DocTableCell(
            text: cellText,
            boundingBox: cell.rect,
            isNumeric: parsedNum != null,
            numericValue: parsedNum,
          );
        } else {
          cells[bestCol] = DocTableCell(
            text: '${cells[bestCol].text} $cellText',
            boundingBox: cell.rect,
            isNumeric: false,
          );
        }
      }

      if (cells.any((c) => c.text.isNotEmpty)) {
        docRows.add(DocTableRow(cells: cells, isHeader: r == 0));
      }
    }

    if (docRows.isEmpty) return null;

    final double top = lines.map((l) => l.rect.top).reduce(min);
    final double left = lines.map((l) => l.rect.left).reduce(min);
    final double right = lines.map((l) => l.rect.right).reduce(max);
    final double bottom = lines.map((l) => l.rect.bottom).reduce(max);

    return DocTable(
      rows: docRows,
      columnCount: numCols,
      boundingBox: Rect.fromLTRB(left, top, right, bottom),
    );
  }
}

class _RawLine {
  final String text;
  final Rect rect;

  _RawLine({required this.text, required this.rect});
}
