import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:path_provider/path_provider.dart';
import '../../domain/models/document_structure.dart';

class PowerPointExportService {
  /// Converts analyzed document pages into an editable .pptx PowerPoint presentation
  static Future<File> exportToPptx({
    required AnalyzedDocument document,
    required String baseFileName,
    void Function(String step, double progress)? onProgress,
  }) async {
    onProgress?.call('Initializing PowerPoint Engine...', 0.1);

    final archive = Archive();

    // 1. [Content_Types].xml
    final contentTypesXml = StringBuffer();
    contentTypesXml.writeln('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>');
    contentTypesXml.writeln('<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">');
    contentTypesXml.writeln('  <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>');
    contentTypesXml.writeln('  <Default Extension="xml" ContentType="application/xml"/>');
    contentTypesXml.writeln('  <Override PartName="/ppt/presentation.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.presentation.main+xml"/>');

    for (int i = 0; i < document.pages.length; i++) {
      contentTypesXml.writeln('  <Override PartName="/ppt/slides/slide${i + 1}.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slide+xml"/>');
    }
    contentTypesXml.writeln('</Types>');
    _addFileToArchive(archive, '[Content_Types].xml', contentTypesXml.toString());

    // 2. _rels/.rels
    const rootRelsXml = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="ppt/presentation.xml"/>
</Relationships>''';
    _addFileToArchive(archive, '_rels/.rels', rootRelsXml);

    // 3. ppt/_rels/presentation.xml.rels
    final presRelsXml = StringBuffer();
    presRelsXml.writeln('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>');
    presRelsXml.writeln('<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">');

    for (int i = 0; i < document.pages.length; i++) {
      presRelsXml.writeln('  <Relationship Id="rIdSlide${i + 1}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slide" Target="slides/slide${i + 1}.xml"/>');
    }
    presRelsXml.writeln('</Relationships>');
    _addFileToArchive(archive, 'ppt/_rels/presentation.xml.rels', presRelsXml.toString());

    // 4. ppt/presentation.xml (16:9 Widescreen: 12192000 x 6858000 EMUs)
    final presXml = StringBuffer();
    presXml.writeln('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>');
    presXml.writeln('<p:presentation xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">');
    presXml.writeln('  <p:sldIdLst>');
    for (int i = 0; i < document.pages.length; i++) {
      presXml.writeln('    <p:sldId id="${256 + i}" r:id="rIdSlide${i + 1}"/>');
    }
    presXml.writeln('  </p:sldIdLst>');
    presXml.writeln('  <p:sldSz cx="12192000" cy="6858000"/>');
    presXml.writeln('</p:presentation>');
    _addFileToArchive(archive, 'ppt/presentation.xml', presXml.toString());

    onProgress?.call('Generating Presentation Slides...', 0.4);

    // 5. ppt/slides/slideN.xml
    for (int s = 0; s < document.pages.length; s++) {
      final page = document.pages[s];
      final slideXml = StringBuffer();

      slideXml.writeln('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>');
      slideXml.writeln('<p:sld xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main" xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main">');
      slideXml.writeln('  <p:cSld>');
      slideXml.writeln('    <p:spTree>');
      slideXml.writeln('      <p:nvGrpSpPr>');
      slideXml.writeln('        <p:cNvPr id="1" name=""/>');
      slideXml.writeln('        <p:cNvGrpSpPr/>');
      slideXml.writeln('        <p:nvPr/>');
      slideXml.writeln('      </p:nvGrpSpPr>');
      slideXml.writeln('      <p:grpSpPr/>');

      // Title Shape
      slideXml.writeln('      <p:sp>');
      slideXml.writeln('        <p:nvSpPr>');
      slideXml.writeln('          <p:cNvPr id="2" name="Title 1"/>');
      slideXml.writeln('          <p:cNvSpPr><a:spLocks noGrp="1"/></p:cNvSpPr>');
      slideXml.writeln('          <p:nvPr/>');
      slideXml.writeln('        </p:nvSpPr>');
      slideXml.writeln('        <p:spPr>');
      slideXml.writeln('          <a:xfrm><a:off x="838200" y="457200"/><a:ext cx="10515600" cy="914400"/></a:xfrm>');
      slideXml.writeln('        </p:spPr>');
      slideXml.writeln('        <p:txBody>');
      slideXml.writeln('          <a:bodyPr/>');
      slideXml.writeln('          <a:p>');
      slideXml.writeln('            <a:r>');
      slideXml.writeln('              <a:rPr sz="3200" b="1"><a:solidFill><a:srgbClr val="008080"/></a:solidFill></a:rPr>');
      slideXml.writeln('              <a:t>${_xmlEscape(page.title)}</a:t>');
      slideXml.writeln('            </a:r>');
      slideXml.writeln('          </a:p>');
      slideXml.writeln('        </p:txBody>');
      slideXml.writeln('      </p:sp>');

      // Content Box (Paragraphs & bullet points)
      if (page.paragraphs.isNotEmpty) {
        slideXml.writeln('      <p:sp>');
        slideXml.writeln('        <p:nvSpPr>');
        slideXml.writeln('          <p:cNvPr id="3" name="Content 2"/>');
        slideXml.writeln('          <p:cNvSpPr><a:spLocks noGrp="1"/></p:cNvSpPr>');
        slideXml.writeln('          <p:nvPr/>');
        slideXml.writeln('        </p:nvSpPr>');
        slideXml.writeln('        <p:spPr>');
        slideXml.writeln('          <a:xfrm><a:off x="838200" y="1600200"/><a:ext cx="10515600" cy="4572000"/></a:xfrm>');
        slideXml.writeln('        </p:spPr>');
        slideXml.writeln('        <p:txBody>');
        slideXml.writeln('          <a:bodyPr/>');
        for (final para in page.paragraphs) {
          slideXml.writeln('          <a:p>');
          slideXml.writeln('            <a:r>');
          slideXml.writeln('              <a:rPr sz="1800"/>');
          slideXml.writeln('              <a:t>${_xmlEscape(para.text)}</a:t>');
          slideXml.writeln('            </a:r>');
          slideXml.writeln('          </a:p>');
        }
        slideXml.writeln('        </p:txBody>');
        slideXml.writeln('      </p:sp>');
      }

      slideXml.writeln('    </p:spTree>');
      slideXml.writeln('  </p:cSld>');
      slideXml.writeln('</p:sld>');

      _addFileToArchive(archive, 'ppt/slides/slide${s + 1}.xml', slideXml.toString());
    }

    onProgress?.call('Validating and Packaging PPTX...', 0.8);

    final zipEncoder = ZipEncoder();
    final List<int>? encoded = zipEncoder.encode(archive);
    if (encoded == null) throw Exception('Failed to encode PowerPoint PPTX package');

    // Save in app Converted Documents folder
    final appDir = await getApplicationDocumentsDirectory();
    final convertedDir = Directory('${appDir.path}/Converted Documents');
    if (!await convertedDir.exists()) await convertedDir.create(recursive: true);

    final sanitizedName = baseFileName.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    final outPath = '${convertedDir.path}/$sanitizedName.pptx';
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
