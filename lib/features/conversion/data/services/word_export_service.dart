import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:path_provider/path_provider.dart';
import '../../domain/models/document_structure.dart';

class WordExportService {
  /// Converts analyzed document pages into an editable .docx Word document
  static Future<File> exportToDocx({
    required AnalyzedDocument document,
    required String baseFileName,
    void Function(String step, double progress)? onProgress,
  }) async {
    onProgress?.call('Initializing Word Engine...', 0.1);

    final archive = Archive();

    // 1. [Content_Types].xml
    const contentTypesXml = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
  <Default Extension="xml" ContentType="application/xml"/>
  <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
  <Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/>
</Types>''';
    _addFileToArchive(archive, '[Content_Types].xml', contentTypesXml);

    // 2. _rels/.rels
    const rootRelsXml = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
</Relationships>''';
    _addFileToArchive(archive, '_rels/.rels', rootRelsXml);

    // 3. word/_rels/document.xml.rels
    const docRelsXml = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rIdStyles" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>
</Relationships>''';
    _addFileToArchive(archive, 'word/_rels/document.xml.rels', docRelsXml);

    // 4. word/styles.xml
    const stylesXml = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
  <w:docDefaults>
    <w:rPrDefault>
      <w:rPr>
        <w:rFonts w:ascii="Calibri" w:hAnsi="Calibri" w:cs="Calibri"/>
        <w:sz w:val="22"/>
        <w:szCs w:val="22"/>
      </w:rPr>
    </w:rPrDefault>
  </w:docDefaults>
  <w:style w:type="paragraph" w:styleId="Heading1">
    <w:name w:val="heading 1"/>
    <w:pPr>
      <w:spacing w:before="240" w:after="120"/>
    </w:pPr>
    <w:rPr>
      <w:b/>
      <w:color w:val="008080"/>
      <w:sz w:val="32"/>
      <w:szCs w:val="32"/>
    </w:rPr>
  </w:style>
  <w:style w:type="paragraph" w:styleId="Heading2">
    <w:name w:val="heading 2"/>
    <w:pPr>
      <w:spacing w:before="160" w:after="80"/>
    </w:pPr>
    <w:rPr>
      <w:b/>
      <w:color w:val="1E293B"/>
      <w:sz w:val="26"/>
      <w:szCs w:val="26"/>
    </w:rPr>
  </w:style>
</w:styles>''';
    _addFileToArchive(archive, 'word/styles.xml', stylesXml);

    onProgress?.call('Reconstructing Document Flow...', 0.4);

    // 5. word/document.xml
    final docXml = StringBuffer();
    docXml.writeln('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>');
    docXml.writeln('<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">');
    docXml.writeln('  <w:body>');

    for (int p = 0; p < document.pages.length; p++) {
      final page = document.pages[p];

      // Page Title
      if (page.title.isNotEmpty && !page.title.startsWith('Document Page')) {
        docXml.writeln('    <w:p>');
        docXml.writeln('      <w:pPr><w:pStyle w:val="Heading1"/><w:jc w:val="center"/></w:pPr>');
        docXml.writeln('      <w:r><w:t>${_xmlEscape(page.title)}</w:t></w:r>');
        docXml.writeln('    </w:p>');
      }

      // Paragraphs and Headings
      for (final para in page.paragraphs) {
        docXml.writeln('    <w:p>');
        docXml.writeln('      <w:pPr><w:spacing w:after="120"/></w:pPr>');
        if (para.isBullet) {
          docXml.writeln('      <w:r><w:t>• </w:t></w:r>');
        }
        docXml.writeln('      <w:r><w:t>${_xmlEscape(para.text)}</w:t></w:r>');
        docXml.writeln('    </w:p>');
      }

      // Tables
      for (final table in page.tables) {
        docXml.writeln('    <w:tbl>');
        docXml.writeln('      <w:tblPr>');
        docXml.writeln('        <w:tblW w:w="5000" w:type="pct"/>');
        docXml.writeln('        <w:tblBorders>');
        docXml.writeln('          <w:top w:val="single" w:sz="4" w:space="0" w:color="CBD5E1"/>');
        docXml.writeln('          <w:left w:val="single" w:sz="4" w:space="0" w:color="CBD5E1"/>');
        docXml.writeln('          <w:bottom w:val="single" w:sz="4" w:space="0" w:color="CBD5E1"/>');
        docXml.writeln('          <w:right w:val="single" w:sz="4" w:space="0" w:color="CBD5E1"/>');
        docXml.writeln('          <w:insideH w:val="single" w:sz="4" w:space="0" w:color="E2E8F0"/>');
        docXml.writeln('          <w:insideV w:val="single" w:sz="4" w:space="0" w:color="E2E8F0"/>');
        docXml.writeln('        </w:tblBorders>');
        docXml.writeln('      </w:tblPr>');

        for (final row in table.rows) {
          docXml.writeln('      <w:tr>');
          for (final cell in row.cells) {
            docXml.writeln('        <w:tc>');
            docXml.writeln('          <w:tcPr>');
            if (row.isHeader) {
              docXml.writeln('            <w:shd w:val="clear" w:color="auto" w:fill="F1F5F9"/>');
            }
            docXml.writeln('          </w:tcPr>');
            docXml.writeln('          <w:p>');
            docXml.writeln('            <w:r>');
            if (row.isHeader) {
              docXml.writeln('              <w:rPr><w:b/></w:rPr>');
            }
            docXml.writeln('              <w:t>${_xmlEscape(cell.text)}</w:t>');
            docXml.writeln('            </w:r>');
            docXml.writeln('          </w:p>');
            docXml.writeln('        </w:tc>');
          }
          docXml.writeln('      </w:tr>');
        }

        docXml.writeln('    </w:tbl>');
        docXml.writeln('    <w:p/>'); // empty spacing paragraph
      }

      // Page break if multiple pages
      if (p < document.pages.length - 1) {
        docXml.writeln('    <w:p><w:r><w:br w:type="page"/></w:r></w:p>');
      }
    }

    docXml.writeln('    <w:sectPr>');
    docXml.writeln('      <w:pgSz w:w="11906" w:h="16838"/>'); // A4 size in twips
    docXml.writeln('      <w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440"/>');
    docXml.writeln('    </w:sectPr>');
    docXml.writeln('  </w:body>');
    docXml.writeln('</w:document>');

    _addFileToArchive(archive, 'word/document.xml', docXml.toString());

    onProgress?.call('Formatting and Packaging DOCX...', 0.8);

    final zipEncoder = ZipEncoder();
    final List<int>? encoded = zipEncoder.encode(archive);
    if (encoded == null) throw Exception('Failed to encode Word DOCX package');

    // Save in app Converted Documents folder
    final appDir = await getApplicationDocumentsDirectory();
    final convertedDir = Directory('${appDir.path}/Converted Documents');
    if (!await convertedDir.exists()) await convertedDir.create(recursive: true);

    final sanitizedName = baseFileName.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    final outPath = '${convertedDir.path}/$sanitizedName.docx';
    final outFile = File(outPath);
    await outFile.writeAsBytes(encoded);

    onProgress?.call('Conversion Complete', 1.0);
    return outFile;
  }

  static void _addFileToArchive(Archive archive, String path, String content) {
    final bytes = utf8.encode(content);
    archive.addFile(ArchiveFile(path, bytes.length, bytes));
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
