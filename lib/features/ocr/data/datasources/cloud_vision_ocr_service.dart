import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;

/// Google Cloud Vision API-based OCR.
///
/// Unlike ML Kit on-device, Cloud Vision supports Bangla (বাংলা) and many
/// other scripts. Requires a valid API key (Settings → OCR), which you can
/// create for free at https://console.cloud.google.com (enable the "Cloud
/// Vision API", then create an API key under Credentials).
class CloudVisionOcrService {
  static const String endpoint =
      'https://vision.googleapis.com/v1/images:annotate';

  /// Recognizes text in [imageBytes].
  ///
  /// [languageHints] tells Vision which languages to expect, e.g.
  /// `['bn', 'en']` for Bangla + English. [apiKey] must be the user's key.
  Future<String> recognizeText(
    Uint8List imageBytes, {
    String apiKey = '',
    List<String> languageHints = const ['bn', 'en'],
  }) async {
    if (apiKey.isEmpty) {
      throw Exception(
        'Google Vision API key is not set.\n'
        'Add it in Settings → OCR → Vision API Key.',
      );
    }

    final base64Image = base64Encode(imageBytes);
    final uri = Uri.parse('$endpoint?key=$apiKey');

    final response = await http
        .post(
          uri,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'requests': [
              {
                'image': {'content': base64Image},
                'features': [
                  {'type': 'TEXT_DETECTION', 'maxResults': 1},
                ],
                'imageContext': {'languageHints': languageHints},
              },
            ],
          }),
        )
        .timeout(const Duration(seconds: 60));

    if (response.statusCode != 200) {
      throw Exception('Vision API error (${response.statusCode}): ${response.body}');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final responses = data['responses'] as List? ?? const [];
    if (responses.isEmpty) return '';

    final annotation =
        (responses.first as Map<String, dynamic>)['fullTextAnnotation']
            as Map<String, dynamic>?;
    return (annotation?['text'] as String? ?? '').trim();
  }
}
