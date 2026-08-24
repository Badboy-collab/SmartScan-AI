import 'dart:io';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:share_plus/share_plus.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../documents/domain/entities/scanned_document.dart';
import '../../data/services/document_layout_analyzer.dart';
import '../../data/services/excel_export_service.dart';
import '../../data/services/powerpoint_export_service.dart';
import '../../data/services/word_export_service.dart';
import '../../domain/models/document_structure.dart';

enum ExportFormatType {
  excel,
  word,
  powerpoint,
  pdf,
}

class DocumentConversionPage extends StatefulWidget {
  final ScannedDocument document;
  final ExportFormatType format;

  const DocumentConversionPage({
    super.key,
    required this.document,
    required this.format,
  });

  @override
  State<DocumentConversionPage> createState() => _DocumentConversionPageState();
}

class _DocumentConversionPageState extends State<DocumentConversionPage> {
  bool _isConverting = true;
  bool _isCancelled = false;
  String _currentStepText = 'Starting Conversion...';
  double _currentProgress = 0.0;
  int _activeStepIndex = 0;
  File? _convertedFile;
  String? _errorMessage;

  List<String> get _pipelineSteps {
    switch (widget.format) {
      case ExportFormatType.excel:
        return [
          'Analyze Document',
          'Detecting Tables',
          'Recognizing Cells',
          'Checking OCR',
          'Building Spreadsheet',
          'Formatting Workbook',
          'Validating Workbook',
          'Complete',
        ];
      case ExportFormatType.word:
        return [
          'Analyze Document',
          'Recognizing Text',
          'Detecting Paragraphs',
          'Detecting Tables',
          'Reconstructing Document',
          'Formatting DOCX',
          'Validating',
          'Complete',
        ];
      case ExportFormatType.powerpoint:
        return [
          'Analyze Pages',
          'Detecting Slide Layout',
          'Recognizing Text',
          'Detecting Tables/Images',
          'Creating Editable Objects',
          'Building Presentation',
          'Validating',
          'Complete',
        ];
      case ExportFormatType.pdf:
        return [
          'Analyze Document',
          'Optimizing Pages',
          'Generating PDF',
          'Validating',
          'Complete',
        ];
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startConversion();
    });
  }

  Future<void> _startConversion() async {
    try {
      final doc = widget.document;
      final pages = <AnalyzedPage>[];

      for (int i = 0; i < doc.pagePaths.length; i++) {
        if (_isCancelled) return;
        final stepIdx = ((i / doc.pagePaths.length) * 3).floor();
        _updateProgress(_pipelineSteps[stepIdx], (i + 1) / (doc.pagePaths.length * 2), stepIdx);

        final pageFile = File(doc.pagePaths[i]);
        if (await pageFile.exists()) {
          final analyzed = await DocumentLayoutAnalyzer.analyzePageImage(pageFile, i + 1);
          pages.add(analyzed);
        }
      }

      if (_isCancelled) return;
      final analyzedDoc = AnalyzedDocument(pages: pages);

      File? resultFile;

      switch (widget.format) {
        case ExportFormatType.excel:
          _updateProgress('Building Spreadsheet & Formatting Cells...', 0.7, 4);
          await Future.delayed(const Duration(milliseconds: 300));
          _updateProgress('Formatting Workbook Styles & Widths...', 0.85, 5);
          resultFile = await ExcelExportService.exportToXlsx(
            document: analyzedDoc,
            baseFileName: doc.name,
            onProgress: (step, prog) {
              if (!_isCancelled) _updateProgress(step, 0.7 + (prog * 0.25), 6);
            },
          );
          break;

        case ExportFormatType.word:
          _updateProgress('Reconstructing Paragraphs & Tables...', 0.7, 4);
          await Future.delayed(const Duration(milliseconds: 300));
          _updateProgress('Formatting DOCX Structure...', 0.85, 5);
          resultFile = await WordExportService.exportToDocx(
            document: analyzedDoc,
            baseFileName: doc.name,
            onProgress: (step, prog) {
              if (!_isCancelled) _updateProgress(step, 0.7 + (prog * 0.25), 6);
            },
          );
          break;

        case ExportFormatType.powerpoint:
          _updateProgress('Creating Editable Presentation Shapes...', 0.7, 4);
          await Future.delayed(const Duration(milliseconds: 300));
          _updateProgress('Building 16:9 Presentation Slides...', 0.85, 5);
          resultFile = await PowerPointExportService.exportToPptx(
            document: analyzedDoc,
            baseFileName: doc.name,
            onProgress: (step, prog) {
              if (!_isCancelled) _updateProgress(step, 0.7 + (prog * 0.25), 6);
            },
          );
          break;

        case ExportFormatType.pdf:
          if (doc.pdfPath != null) {
            resultFile = File(doc.pdfPath!);
          }
          break;
      }

      if (_isCancelled) return;

      if (mounted && resultFile != null && await resultFile.exists()) {
        setState(() {
          _isConverting = false;
          _convertedFile = resultFile;
          _activeStepIndex = _pipelineSteps.length - 1;
          _currentProgress = 1.0;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isConverting = false;
          _errorMessage = 'Conversion failed: $e';
        });
      }
    }
  }

  void _updateProgress(String text, double progress, int stepIndex) {
    if (mounted) {
      setState(() {
        _currentStepText = text;
        _currentProgress = progress.clamp(0.0, 1.0);
        _activeStepIndex = stepIndex.clamp(0, _pipelineSteps.length - 1);
      });
    }
  }

  String get _mimeType {
    switch (widget.format) {
      case ExportFormatType.excel:
        return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
      case ExportFormatType.word:
        return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
      case ExportFormatType.powerpoint:
        return 'application/vnd.openxmlformats-officedocument.presentationml.presentation';
      case ExportFormatType.pdf:
        return 'application/pdf';
    }
  }

  Future<void> _openFile({String? explicitMime}) async {
    if (_convertedFile == null) return;
    try {
      final targetMime = explicitMime ?? _mimeType;
      final result = await OpenFilex.open(_convertedFile!.path, type: targetMime);
      if (result.type == ResultType.noAppToOpen || result.type == ResultType.error) {
        if (mounted) {
          _showNoAppFoundDialog();
        }
      }
    } catch (e) {
      if (mounted) {
        _showNoAppFoundDialog();
      }
    }
  }

  void _showNoAppFoundDialog() {
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Compatible app not found.'),
          content: const Text(
            'No dedicated application was found to open this document directly on your device. You can share it or choose another app.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                _openFile(explicitMime: '*/*');
              },
              child: const Text('Open With'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(ctx);
                _shareFile();
              },
              child: const Text('Share File'),
            ),
          ],
        );
      },
    );
  }

  void _shareFile() {
    if (_convertedFile == null) return;
    SharePlus.instance.share(
      ShareParams(
        files: [XFile(_convertedFile!.path)],
        text: 'Exported from AH Scanner',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    Color formatColor = Colors.teal;
    IconData formatIcon = Icons.insert_drive_file;
    String formatName = 'Document';
    String formatExt = '.file';

    switch (widget.format) {
      case ExportFormatType.excel:
        formatColor = const Color(0xFF107C41);
        formatIcon = Icons.table_chart;
        formatName = 'Microsoft Excel';
        formatExt = '.xlsx';
        break;
      case ExportFormatType.word:
        formatColor = const Color(0xFF185ABD);
        formatIcon = Icons.description;
        formatName = 'Microsoft Word';
        formatExt = '.docx';
        break;
      case ExportFormatType.powerpoint:
        formatColor = const Color(0xFFC43E1C);
        formatIcon = Icons.slideshow;
        formatName = 'PowerPoint Presentation';
        formatExt = '.pptx';
        break;
      case ExportFormatType.pdf:
        formatColor = const Color(0xFFE53935);
        formatIcon = Icons.picture_as_pdf;
        formatName = 'PDF Document';
        formatExt = '.pdf';
        break;
    }

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text('Export to $formatName'),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () {
            _isCancelled = true;
            Navigator.pop(context);
          },
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
          child: _isConverting
              ? _buildConvertingView(formatColor, formatIcon, formatName, isDark)
              : _errorMessage != null
                  ? _buildErrorView(isDark)
                  : _buildCompletionView(formatColor, formatIcon, formatName, formatExt, isDark),
        ),
      ),
    );
  }

  Widget _buildConvertingView(Color formatColor, IconData formatIcon, String formatName, bool isDark) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            color: formatColor.withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          child: Icon(formatIcon, size: 42, color: formatColor),
        ),
        const SizedBox(height: 24),
        Text(
          'Converting to $formatName',
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Text(
          _currentStepText,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 14, color: Colors.grey[600]),
        ),
        const SizedBox(height: 32),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            value: _currentProgress,
            minHeight: 8,
            backgroundColor: isDark ? Colors.white12 : Colors.black12,
            valueColor: AlwaysStoppedAnimation<Color>(formatColor),
          ),
        ),
        const SizedBox(height: 36),
        // Pipeline Stage Checklist
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: isDark ? Colors.white12 : const Color(0xFFE2E8F0)),
          ),
          child: Column(
            children: _pipelineSteps.asMap().entries.map((entry) {
              final idx = entry.key;
              final stepName = entry.value;
              final isDone = idx < _activeStepIndex;
              final isCurrent = idx == _activeStepIndex;

              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4.0),
                child: Row(
                  children: [
                    Icon(
                      isDone
                          ? Icons.check_circle
                          : isCurrent
                              ? Icons.radio_button_checked
                              : Icons.radio_button_unchecked,
                      size: 18,
                      color: isDone
                          ? Colors.green
                          : isCurrent
                              ? formatColor
                              : Colors.grey,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      stepName,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                        color: isDone || isCurrent
                            ? Theme.of(context).textTheme.bodyLarge?.color
                            : Colors.grey,
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ),
        const Spacer(),
        OutlinedButton(
          onPressed: () {
            _isCancelled = true;
            Navigator.pop(context);
          },
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(double.infinity, 48),
            side: const BorderSide(color: Colors.grey),
          ),
          child: const Text('Cancel Conversion'),
        ),
      ],
    );
  }

  Widget _buildCompletionView(Color formatColor, IconData formatIcon, String formatName, String formatExt, bool isDark) {
    final fileName = '${widget.document.name}$formatExt';
    final fileSizeKb = _convertedFile != null ? (_convertedFile!.lengthSync() / 1024).toStringAsFixed(1) : '0';

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Spacer(),
        Container(
          width: 90,
          height: 90,
          decoration: BoxDecoration(
            color: formatColor.withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          child: Icon(formatIcon, size: 48, color: formatColor),
        ),
        const SizedBox(height: 20),
        const Text(
          'Conversion Complete!',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Text(
          'Your document has been successfully converted into an editable $formatName file.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 14, color: Colors.grey[600], height: 1.4),
        ),
        const SizedBox(height: 28),
        // File Card
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: isDark ? Colors.white12 : const Color(0xFFE2E8F0)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: formatColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(formatIcon, color: formatColor, size: 28),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      fileName,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$fileSizeKb KB • Saved to Converted Documents',
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const Spacer(),
        // Action Buttons
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _openFile,
                style: ElevatedButton.styleFrom(
                  backgroundColor: formatColor,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 50),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                icon: const Icon(Icons.open_in_new, size: 20),
                label: Text(
                  widget.format == ExportFormatType.excel
                      ? 'OPEN IN EXCEL'
                      : widget.format == ExportFormatType.word
                          ? 'OPEN IN WORD'
                          : widget.format == ExportFormatType.powerpoint
                              ? 'OPEN IN POWERPOINT'
                              : 'OPEN PDF',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _shareFile,
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 50),
                  side: BorderSide(color: formatColor, width: 1.5),
                  foregroundColor: formatColor,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                icon: const Icon(Icons.share, size: 20),
                label: const Text('SHARE', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('DONE', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }

  Widget _buildErrorView(bool isDark) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.error_outline, size: 64, color: Colors.red),
        const SizedBox(height: 16),
        const Text('Conversion Failed', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Text(_errorMessage ?? 'Unknown error occurred', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey[600])),
        const SizedBox(height: 24),
        ElevatedButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Go Back'),
        ),
      ],
    );
  }
}
