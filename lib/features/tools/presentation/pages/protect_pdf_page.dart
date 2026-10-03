import 'dart:io';

import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../documents/data/services/pdf_export_service.dart';
import '../../../documents/domain/entities/scanned_document.dart';
import '../../../documents/presentation/providers/document_provider.dart';

/// Adds a password to a saved document's PDF.
///
/// The encryption itself already lived in [PdfExportService.generateProtectedPdf]
/// (PDF 1.4 standard security handler, RC4-40) but nothing in the app ever
/// called it - the "Protect PDF" tool tile only showed a "coming soon" message.
/// This page is that missing entry point.
class ProtectPdfPage extends StatefulWidget {
  const ProtectPdfPage({super.key});

  @override
  State<ProtectPdfPage> createState() => _ProtectPdfPageState();
}

class _ProtectPdfPageState extends State<ProtectPdfPage> {
  ScannedDocument? _selectedDoc;
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmController = TextEditingController();
  bool _obscure = true;
  bool _isWorking = false;
  File? _protectedFile;

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _protect() async {
    final doc = _selectedDoc;
    final password = _passwordController.text;

    if (doc == null) {
      _snack('Choose a document first');
      return;
    }
    if (password.length < 4) {
      _snack('Password must be at least 4 characters');
      return;
    }
    if (password != _confirmController.text) {
      _snack('The two passwords do not match');
      return;
    }

    setState(() {
      _isWorking = true;
      _protectedFile = null;
    });

    try {
      final file = await getIt<PdfExportService>().generateProtectedPdf(doc, password);
      if (!mounted) return;
      setState(() {
        _isWorking = false;
        _protectedFile = file;
      });
      _snack('Password-protected PDF created');
    } catch (e) {
      debugPrint('[ProtectPdf] Error: $e');
      if (!mounted) return;
      setState(() => _isWorking = false);
      _snack('Could not protect the PDF: $e');
    }
  }

  Future<void> _open() async {
    final file = _protectedFile;
    if (file == null) return;
    final result = await OpenFilex.open(file.path, type: 'application/pdf');
    if (!mounted) return;
    if (result.type != ResultType.done) {
      _snack('No PDF viewer found - use Share instead.');
    }
  }

  Future<void> _share() async {
    final file = _protectedFile;
    if (file == null) return;
    await Share.shareXFiles(
      [XFile(file.path, mimeType: 'application/pdf')],
      subject: '${_selectedDoc?.name ?? 'Document'} (protected)',
      text: 'PDF protected with AH Scanner. You will be asked for the password.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final docs = getIt<DocumentProvider>().documents;

    return Scaffold(
      backgroundColor: const Color(0xFF1E1E1E),
      appBar: AppBar(title: const Text('Protect PDF')),
      body: docs.isEmpty
          ? const Center(
              child: Text('No documents available. Scan or import one first.'),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2A2A2A),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.white24),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<ScannedDocument>(
                      value: _selectedDoc,
                      hint: const Text('Choose a document', style: TextStyle(color: Colors.white38)),
                      dropdownColor: const Color(0xFF2A2A2A),
                      isExpanded: true,
                      items: docs.map((d) {
                        return DropdownMenuItem<ScannedDocument>(
                          value: d,
                          child: Text(
                            '${d.name} (${d.pagePaths.length} pages)',
                            style: const TextStyle(color: Colors.white),
                          ),
                        );
                      }).toList(),
                      onChanged: _isWorking
                          ? null
                          : (val) => setState(() {
                                _selectedDoc = val;
                                _protectedFile = null;
                              }),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: _passwordController,
                  enabled: !_isWorking,
                  obscureText: _obscure,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: 'Password',
                    labelStyle: const TextStyle(color: Colors.white60),
                    filled: true,
                    fillColor: const Color(0xFF2A2A2A),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    suffixIcon: IconButton(
                      icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility, color: Colors.white54),
                      onPressed: () => setState(() => _obscure = !_obscure),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _confirmController,
                  enabled: !_isWorking,
                  obscureText: _obscure,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: 'Confirm password',
                    labelStyle: const TextStyle(color: Colors.white60),
                    filled: true,
                    fillColor: const Color(0xFF2A2A2A),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.amber.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.amber.withValues(alpha: 0.4)),
                  ),
                  child: const Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.info_outline, size: 18, color: Colors.amber),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Compatibility mode (PDF 1.4, RC4-40): opens in Acrobat, Chrome and phone PDF readers with the password. '
                          'It stops casual viewing but is not strong encryption - do not rely on it for confidential files.',
                          style: TextStyle(fontSize: 12, color: Colors.white70),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                ElevatedButton.icon(
                  onPressed: _isWorking ? null : _protect,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryLight,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  icon: _isWorking
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.lock_outline, color: Colors.white),
                  label: Text(
                    _isWorking ? 'Encrypting...' : 'Protect PDF',
                    style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
                if (_protectedFile != null) ...[
                  const SizedBox(height: 24),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFF2A2A2A),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.primaryLight.withValues(alpha: 0.5)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.check_circle, color: Colors.tealAccent, size: 20),
                            SizedBox(width: 8),
                            Text(
                              'Protected PDF ready',
                              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _protectedFile!.path.split(Platform.pathSeparator).last,
                          style: const TextStyle(color: Colors.white54, fontSize: 12),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: _open,
                                icon: const Icon(Icons.open_in_new, size: 18),
                                label: const Text('Open'),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: _share,
                                style: ElevatedButton.styleFrom(backgroundColor: AppColors.primaryLight),
                                icon: const Icon(Icons.share, size: 18, color: Colors.white),
                                label: const Text('Share', style: TextStyle(color: Colors.white)),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
    );
  }
}
