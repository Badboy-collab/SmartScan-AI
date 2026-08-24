import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:archive/archive.dart';
import 'package:path_provider/path_provider.dart';
import '../../domain/models/document_structure.dart';

class ExcelExportService {
  /// Converts analyzed document pages into a genuine, styled .xlsx workbook
  static Future<File> exportToXlsx({
    required AnalyzedDocument document,
    required String baseFileName,
    void Function(String step, double progress)? onProgress,
  }) async {
    onProgress?.call('Initializing Excel Engine...', 0.1);

    final archive = Archive();

    // 1. [Content_Types].xml
    final contentTypesXml = StringBuffer();
    contentTypesXml.writeln('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>');
    contentTypesXml.writeln('<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">');
    contentTypesXml.writeln('  <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>');
    contentTypesXml.writeln('  <Default Extension="xml" ContentType="application/xml"/>');
    contentTypesXml.writeln('  <Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>');
    contentTypesXml.writeln('  <Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>');

    for (int i = 0; i < document.pages.length; i++) {
      contentTypesXml.writeln('  <Override PartName="/xl/worksheets/sheet${i + 1}.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>');
    }
    contentTypesXml.writeln('</Types>');
    _addFileToArchive(archive, '[Content_Types].xml', contentTypesXml.toString());

    // 2. _rels/.rels
    const rootRelsXml = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>
</Relationships>''';
    _addFileToArchive(archive, '_rels/.rels', rootRelsXml);

    // 3. xl/_rels/workbook.xml.rels
    final wbRelsXml = StringBuffer();
    wbRelsXml.writeln('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>');
    wbRelsXml.writeln('<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">');
    wbRelsXml.writeln('  <Relationship Id="rIdStyles" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>');

    for (int i = 0; i < document.pages.length; i++) {
      wbRelsXml.writeln('  <Relationship Id="rIdSheet${i + 1}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet${i + 1}.xml"/>');
    }
    wbRelsXml.writeln('</Relationships>');
    _addFileToArchive(archive, 'xl/_rels/workbook.xml.rels', wbRelsXml.toString());

    // 4. xl/workbook.xml
    final wbXml = StringBuffer();
    wbXml.writeln('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>');
    wbXml.writeln('<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">');
    wbXml.writeln('  <sheets>');
    for (int i = 0; i < document.pages.length; i++) {
      final sheetName = 'Page ${i + 1}';
      wbXml.writeln('    <sheet name="$sheetName" sheetId="${i + 1}" r:id="rIdSheet${i + 1}"/>');
    }
    wbXml.writeln('  </sheets>');
    wbXml.writeln('</workbook>');
    _addFileToArchive(archive, 'xl/workbook.xml', wbXml.toString());

    // 5. xl/styles.xml
    const stylesXml = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
  <fonts count="2">
    <font><sz val="11"/><name val="Calibri"/></font>
    <font><b/><sz val="11"/><color rgb="FFFFFFFF"/><name val="Calibri"/></font>
  </fonts>
  <fills count="3">
    <fill><patternFill patternType="none"/></fill>
    <fill><patternFill patternType="gray125"/></fill>
    <fill><patternFill patternType="solid"><fgColor rgb="FF008080"/></patternFill></fill>
  </fills>
  <borders count="2">
    <border><left/><right/><top/><bottom/><diagonal/></border>
    <border>
      <left style="thin"><color rgb="FFB0BEC5"/></left>
      <right style="thin"><color rgb="FFB0BEC5"/></right>
      <top style="thin"><color rgb="FFB0BEC5"/></top>
      <bottom style="thin"><color rgb="FFB0BEC5"/></bottom>
    </border>
  </borders>
  <cellStyleXfs count="1">
    <xf numFmtId="0" fontId="0" fillId="0" borderId="0"/>
  </cellStyleXfs>
  <cellXfs count="3">
    <xf numFmtId="0" fontId="0" fillId="0" borderId="1" xfId="0" applyBorder="1"/>
    <xf numFmtId="0" fontId="1" fillId="2" borderId="1" xfId="0" applyFont="1" applyFill="1" applyBorder="1" applyAlignment="1">
      <alignment horizontal="center" vertical="center"/>
    </xf>
    <xf numFmtId="0" fontId="0" fillId="0" borderId="1" xfId="0" applyBorder="1" applyAlignment="1">
      <alignment horizontal="right" vertical="center"/>
    </xf>
  </cellXfs>
</styleSheet>''';
    _addFileToArchive(archive, 'xl/styles.xml', stylesXml);

    onProgress?.call('Structuring Spreadsheet Grid...', 0.4);

    // 6. xl/worksheets/sheetN.xml
    for (int p = 0; p < document.pages.length; p++) {
      final page = document.pages[p];
      final sheetXml = StringBuffer();

      sheetXml.writeln('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>');
      sheetXml.writeln('<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">');

      // Auto-fit Column widths
      final Map<int, int> maxColLen = {};
      final List<List<String>> allGridRows = [];

      // Add page title if present
      if (page.title.isNotEmpty && !page.title.startsWith('Document Page')) {
        allGridRows.add([page.title]);
        allGridRows.add([]); // empty spacing row
      }

      // Add tables or paragraphs
      if (page.tables.isNotEmpty) {
        for (final table in page.tables) {
          for (final row in table.rows) {
            allGridRows.add(row.cells.map((c) => c.text).toList());
          }
          allGridRows.add([]); // spacing
        }
      } else {
        // Render paragraphs as structured text rows
        for (final para in page.paragraphs) {
          allGridRows.add([para.text]);
        }
      }

      // Compute column width estimates
      for (final row in allGridRows) {
        for (int c = 0; c < row.length; c++) {
          final len = row[c].length;
          maxColLen[c] = max(maxColLen[c] ?? 8, min(45, len + 3));
        }
      }

      sheetXml.writeln('  <cols>');
      maxColLen.forEach((colIdx, colWidth) {
        sheetXml.writeln('    <col min="${colIdx + 1}" max="${colIdx + 1}" width="$colWidth" customWidth="1"/>');
      });
      sheetXml.writeln('  </cols>');

      sheetXml.writeln('  <sheetData>');

      for (int r = 0; r < allGridRows.length; r++) {
        final row = allGridRows[r];
        if (row.isEmpty) continue;

        final isHeaderRow = r == (page.title.isNotEmpty && !page.title.startsWith('Document Page') ? 2 : 0);
        sheetXml.writeln('    <row r="${r + 1}">');

        for (int c = 0; c < row.length; c++) {
          final cellText = row[c];
          final cellRef = '${_colLetter(c)}${r + 1}';
          final num? numeric = num.tryParse(cellText.replaceAll(RegExp(r'[^0-9\.-]'), ''));

          if (isHeaderRow) {
            // Header style (style 1)
            sheetXml.writeln('      <c r="$cellRef" s="1" t="inlineStr"><is><t>${_xmlEscape(cellText)}</t></is></c>');
          } else if (numeric != null && !cellText.contains(':') && !cellText.contains('-') && cellText.trim().length <= 10) {
            // Numeric style (style 2)
            sheetXml.writeln('      <c r="$cellRef" s="2" t="n"><v>$numeric</v></c>');
          } else {
            // Standard text style (style 0)
            sheetXml.writeln('      <c r="$cellRef" s="0" t="inlineStr"><is><t>${_xmlEscape(cellText)}</t></is></c>');
          }
        }
        sheetXml.writeln('    </row>');
      }

      sheetXml.writeln('  </sheetData>');
      sheetXml.writeln('</worksheet>');

      _addFileToArchive(archive, 'xl/worksheets/sheet${p + 1}.xml', sheetXml.toString());
    }

    onProgress?.call('Validating and Packaging XLSX...', 0.8);

    final zipEncoder = ZipEncoder();
    final List<int>? encoded = zipEncoder.encode(archive);
    if (encoded == null) throw Exception('Failed to encode Excel ZIP package');

    // Save in app Converted Documents folder
    final appDir = await getApplicationDocumentsDirectory();
    final convertedDir = Directory('${appDir.path}/Converted Documents');
    if (!await convertedDir.exists()) await convertedDir.create(recursive: true);

    final sanitizedName = baseFileName.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    final outPath = '${convertedDir.path}/$sanitizedName.xlsx';
    final outFile = File(outPath);
    await outFile.writeAsBytes(encoded);

    onProgress?.call('Conversion Complete', 1.0);
    return outFile;
  }

  static void _addFileToArchive(Archive archive, String path, String content) {
    final bytes = utf8.encode(content);
    archive.addFile(ArchiveFile(path, bytes.length, bytes));
  }

  static String _colLetter(int colIndex) {
    String result = '';
    int index = colIndex;
    while (index >= 0) {
      result = String.fromCharCode((index % 26) + 65) + result;
      index = (index ~/ 26) - 1;
    }
    return result;
  }

  static String _xmlEscape(String text) {
    return text
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&apos;');
  }
}
