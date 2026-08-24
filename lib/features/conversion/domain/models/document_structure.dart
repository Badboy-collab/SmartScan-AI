import 'dart:ui';

/// Structural hierarchy of an analyzed document
class AnalyzedDocument {
  final List<AnalyzedPage> pages;

  AnalyzedDocument({required this.pages});
}

class AnalyzedPage {
  final int pageNumber;
  final Size pageSize;
  final String title;
  final List<DocElement> elements;
  final List<DocTable> tables;
  final List<DocParagraph> paragraphs;

  AnalyzedPage({
    required this.pageNumber,
    required this.pageSize,
    required this.title,
    required this.elements,
    required this.tables,
    required this.paragraphs,
  });
}

abstract class DocElement {
  final Rect boundingBox;
  DocElement({required this.boundingBox});
}

class DocHeading extends DocElement {
  final String text;
  final int level; // 1 = Title, 2 = Heading, 3 = Subheading

  DocHeading({
    required this.text,
    this.level = 1,
    required super.boundingBox,
  });
}

class DocParagraph extends DocElement {
  final String text;
  final bool isBullet;
  final bool isNumbered;

  DocParagraph({
    required this.text,
    this.isBullet = false,
    this.isNumbered = false,
    required super.boundingBox,
  });
}

class DocTable extends DocElement {
  final List<DocTableRow> rows;
  final int columnCount;

  DocTable({
    required this.rows,
    required this.columnCount,
    required super.boundingBox,
  });
}

class DocTableRow {
  final List<DocTableCell> cells;
  final bool isHeader;

  DocTableRow({
    required this.cells,
    this.isHeader = false,
  });
}

class DocTableCell {
  final String text;
  final Rect boundingBox;
  final int colSpan;
  final int rowSpan;
  final bool isNumeric;
  final num? numericValue;

  DocTableCell({
    required this.text,
    required this.boundingBox,
    this.colSpan = 1,
    this.rowSpan = 1,
    this.isNumeric = false,
    this.numericValue,
  });
}
