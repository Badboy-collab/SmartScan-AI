import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/utils/app_launcher.dart';
import '../../data/datasources/cloud_vision_ocr_service.dart';

/// Where Google issues the free key this dialog asks for.
const String visionApiConsoleUrl =
    'https://console.cloud.google.com/apis/library/vision.googleapis.com';

/// Lets the user paste, test and save the Google Cloud Vision API key.
///
/// Shared by the OCR page (বাংলা is cloud-only) and Settings, so the key is set
/// up the same way everywhere. The "Test key" button makes one real request and
/// reports Google's own reason on failure (invalid key, API not enabled,
/// billing missing), which is the part users cannot guess.
///
/// Returns `true` when a key was saved.
Future<bool> showVisionKeyDialog(
  BuildContext context, {
  String currentKey = '',
}) async {
  final controller = TextEditingController(text: currentKey);
  bool testing = false;
  String? status;
  bool statusOk = false;

  final saved = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) => AlertDialog(
        backgroundColor: Theme.of(ctx).cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Google Vision API key'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'বাংলা OCR runs on Google Cloud Vision, because the offline engine '
                'has no Bengali model. The key is free (1000 pages a month).',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                onChanged: (_) {
                  if (status != null) setLocal(() => status = null);
                },
                decoration: const InputDecoration(
                  hintText: 'Paste your API key',
                  border: OutlineInputBorder(),
                ),
              ),
              TextButton.icon(
                onPressed: () => openExternalUrl(visionApiConsoleUrl),
                icon: const Icon(Icons.open_in_new, size: 16),
                label: const Text('Open Google Cloud console'),
              ),
              if (testing) const LinearProgressIndicator(),
              if (status != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    status!,
                    style: TextStyle(
                      fontSize: 12,
                      color: statusOk ? Colors.teal : Colors.redAccent,
                    ),
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: testing
                ? null
                : () async {
                    setLocal(() {
                      testing = true;
                      status = null;
                    });
                    try {
                      await CloudVisionOcrService().testApiKey(controller.text);
                      setLocal(() {
                        testing = false;
                        statusOk = true;
                        status = 'Key works - বাংলা OCR is ready.';
                      });
                    } catch (e) {
                      setLocal(() {
                        testing = false;
                        statusOk = false;
                        status = '$e';
                      });
                    }
                  },
            child: const Text('Test key'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.teal,
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              final prefs = await SharedPreferences.getInstance();
              await prefs.setString(
                'google_vision_api_key',
                controller.text.trim(),
              );
              if (ctx.mounted) Navigator.pop(ctx, true);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    ),
  );

  controller.dispose();
  return saved ?? false;
}
