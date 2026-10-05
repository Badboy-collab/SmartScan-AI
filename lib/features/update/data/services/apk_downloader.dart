import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Downloads a release APK into the app cache so the update never has to leave
/// the app for a browser round-trip.
///
/// The file is streamed to disk (a release APK is ~40 MB, so buffering it in
/// memory would be wasteful) and every chunk is reported through [onProgress].
class ApkDownloader {
  ApkDownloader._();

  /// How long to wait for the server to answer before giving up.
  static const Duration _connectTimeout = Duration(seconds: 20);

  /// Downloads [url] into `<cache>/updates/<fileName>`.
  ///
  /// [onProgress] receives the bytes received so far plus the total size when
  /// the server sends a `Content-Length` (null otherwise). A partial download
  /// is deleted before the error is rethrown, so a retry always starts clean.
  static Future<File> download({
    required String url,
    required String fileName,
    void Function(int received, int? total)? onProgress,
  }) async {
    final dir = Directory(
      p.join((await getTemporaryDirectory()).path, 'updates'),
    );
    if (!await dir.exists()) await dir.create(recursive: true);

    final target = File(p.join(dir.path, fileName));
    if (await target.exists()) await target.delete();

    final client = http.Client();
    try {
      final response = await client
          .send(http.Request('GET', Uri.parse(url)))
          .timeout(_connectTimeout);

      if (response.statusCode != 200) {
        throw HttpException('Server answered ${response.statusCode}', uri: Uri.parse(url));
      }

      final total = response.contentLength;
      final sink = target.openWrite();
      var received = 0;
      try {
        await for (final chunk in response.stream) {
          sink.add(chunk);
          received += chunk.length;
          onProgress?.call(received, total);
        }
      } finally {
        await sink.close();
      }

      if (total != null && received != total) {
        throw const HttpException('The download stopped before it finished');
      }
      return target;
    } catch (_) {
      // Never leave a truncated APK behind: the installer would fail on it and
      // the next attempt would reuse the broken file.
      if (await target.exists()) await target.delete();
      rethrow;
    } finally {
      client.close();
    }
  }
}
