import 'dart:convert';

import 'package:http/http.dart' as http;

/// A newer build published on the project's GitHub releases page.
class UpdateInfo {
  const UpdateInfo({
    required this.version,
    required this.notes,
    required this.downloadUrl,
    required this.releaseUrl,
  });

  /// Release tag, e.g. `v1.0.3`.
  final String version;

  /// Release notes body (may be empty).
  final String notes;

  /// Direct `.apk` asset URL when the release ships one, otherwise the release
  /// page URL.
  final String downloadUrl;

  /// GitHub release page, always available.
  final String releaseUrl;
}

/// Outcome of one check.
///
/// [reachedServer] is `false` only when the API could not be contacted at all
/// (offline, DNS, timeout, rate limit). A reachable server that has no release
/// yet yields `reachedServer: true` with `info == null`, which is a valid
/// "nothing newer exists" answer rather than an error.
class UpdateCheck {
  const UpdateCheck({required this.reachedServer, this.info});

  final bool reachedServer;
  final UpdateInfo? info;

  static const UpdateCheck unreachable = UpdateCheck(reachedServer: false);
  static const UpdateCheck noRelease = UpdateCheck(reachedServer: true);
}

/// Checks GitHub Releases for a newer AH Scanner build.
///
/// Deliberately dependency-free (uses `http`, which the app already ships) and
/// failure-tolerant: nothing here may ever block or crash the app.
class UpdateChecker {
  UpdateChecker._();

  static const String owner = 'Badboy-collab';
  static const String repo = 'SmartScan-AI';
  static const String _latestReleaseUrl =
      'https://api.github.com/repos/$owner/$repo/releases/latest';

  static const Duration _timeout = Duration(seconds: 8);

  static Future<UpdateCheck> check() async {
    try {
      final response = await http.get(
        Uri.parse(_latestReleaseUrl),
        headers: const {'Accept': 'application/vnd.github+json'},
      ).timeout(_timeout);

      // 404 = the repo is reachable but no release has been published yet.
      if (response.statusCode == 404) return UpdateCheck.noRelease;
      if (response.statusCode != 200) return UpdateCheck.unreachable;

      final body = jsonDecode(response.body);
      if (body is! Map<String, dynamic>) return UpdateCheck.noRelease;

      final tag = (body['tag_name'] as String?)?.trim();
      if (tag == null || tag.isEmpty) return UpdateCheck.noRelease;

      final releaseUrl = (body['html_url'] as String?)?.trim() ?? '';

      String? apkUrl;
      final assets = body['assets'];
      if (assets is List) {
        for (final asset in assets) {
          if (asset is! Map) continue;
          final name = (asset['name'] as String? ?? '').toLowerCase();
          final url = asset['browser_download_url'] as String?;
          if (name.endsWith('.apk') && url != null && url.isNotEmpty) {
            apkUrl = url;
            break;
          }
        }
      }

      return UpdateCheck(
        reachedServer: true,
        info: UpdateInfo(
          version: tag,
          notes: (body['body'] as String? ?? '').trim(),
          downloadUrl: apkUrl ?? releaseUrl,
          releaseUrl: releaseUrl,
        ),
      );
    } catch (_) {
      // Offline, DNS failure, timeout, rate limit, bad JSON — stay quiet.
      return UpdateCheck.unreachable;
    }
  }

  /// `a` newer than `b` → positive, equal → 0, older → negative.
  /// Only the numeric `major.minor.patch` part is compared; a leading `v` and
  /// any `+build` suffix are ignored.
  static int compareVersions(String a, String b) {
    final left = _parts(a);
    final right = _parts(b);
    for (int i = 0; i < 3; i++) {
      final diff = left[i] - right[i];
      if (diff != 0) return diff;
    }
    return 0;
  }

  static List<int> _parts(String raw) {
    final cleaned = raw.trim().replaceFirst(RegExp(r'^[vV]'), '').split('+').first;
    final segments = cleaned.split('.');
    return List<int>.generate(3, (index) {
      if (index >= segments.length) return 0;
      final match = RegExp(r'\d+').firstMatch(segments[index]);
      return match == null ? 0 : (int.tryParse(match.group(0)!) ?? 0);
    });
  }
}
