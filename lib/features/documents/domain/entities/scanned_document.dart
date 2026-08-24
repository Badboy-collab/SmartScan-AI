class ScannedDocument {
  final String id;
  String name;
  final DateTime createdAt;
  DateTime updatedAt;
  final String dirPath;
  List<String> pagePaths;
  List<String> rawPagePaths;
  String thumbnailPath;
  String? pdfPath;
  bool isFavorite;
  String folder;

  ScannedDocument({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.updatedAt,
    required this.dirPath,
    required this.pagePaths,
    List<String>? rawPagePaths,
    required this.thumbnailPath,
    this.pdfPath,
    this.isFavorite = false,
    this.folder = '',
  }) : rawPagePaths = rawPagePaths ?? List.from(pagePaths);

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'dirPath': dirPath,
      'pagePaths': pagePaths,
      'rawPagePaths': rawPagePaths,
      'thumbnailPath': thumbnailPath,
      'pdfPath': pdfPath,
      'isFavorite': isFavorite,
      'folder': folder,
    };
  }

  factory ScannedDocument.fromJson(Map<String, dynamic> json) {
    final pages = (json['pagePaths'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [];
    final rawPages = (json['rawPagePaths'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? List<String>.from(pages);
    final now = DateTime.now();

    DateTime parseDate(dynamic val) {
      if (val is String) {
        return DateTime.tryParse(val) ?? now;
      }
      return now;
    }

    return ScannedDocument(
      id: json['id']?.toString() ?? now.millisecondsSinceEpoch.toString(),
      name: json['name']?.toString() ?? 'Untitled Document',
      createdAt: parseDate(json['createdAt']),
      updatedAt: parseDate(json['updatedAt']),
      dirPath: json['dirPath']?.toString() ?? '',
      pagePaths: pages,
      rawPagePaths: rawPages,
      thumbnailPath: json['thumbnailPath']?.toString() ?? (pages.isNotEmpty ? pages.first : ''),
      pdfPath: json['pdfPath']?.toString(),
      isFavorite: json['isFavorite'] == true,
      folder: json['folder']?.toString() ?? '',
    );
  }

  ScannedDocument copyWith({
    String? id,
    String? name,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? dirPath,
    List<String>? pagePaths,
    List<String>? rawPagePaths,
    String? thumbnailPath,
    String? pdfPath,
    bool? isFavorite,
    String? folder,
  }) {
    return ScannedDocument(
      id: id ?? this.id,
      name: name ?? this.name,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      dirPath: dirPath ?? this.dirPath,
      pagePaths: pagePaths ?? this.pagePaths,
      rawPagePaths: rawPagePaths ?? this.rawPagePaths,
      thumbnailPath: thumbnailPath ?? this.thumbnailPath,
      pdfPath: pdfPath ?? this.pdfPath,
      isFavorite: isFavorite ?? this.isFavorite,
      folder: folder ?? this.folder,
    );
  }
}
