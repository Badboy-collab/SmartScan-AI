import 'dart:convert';

/// One published release, as far as the updater cares.
class LatestRelease {
  const LatestRelease({
    required this.version,
    required this.notes,
    required this.apkUrl,
    required this.releaseUrl,
  });

  /// Release tag, e.g. `v1.0.3`.
  final String version;

  /// Release notes body (may be empty).
  final String notes;

  /// Direct `.apk` asset URL, or an empty string when the release has none.
  final String apkUrl;

  /// GitHub release page, always available.
  final String releaseUrl;
}

/// Parses the body of GitHub's `releases/latest` endpoint.
///
/// Returns `null` when the payload is not a usable release (bad JSON, no tag),
/// so the caller can keep the "server reached but nothing newer" answer.
///
/// Only `dart:convert` is used, which keeps this logic testable outside
/// Flutter - see `test_logic/`.
LatestRelease? parseLatestRelease(String body) {
  try {
    final decoded = jsonDecode(body);
    if (decoded is! Map) return null;

    final tag = (decoded['tag_name'] as String?)?.trim();
    if (tag == null || tag.isEmpty) return null;

    final releaseUrl = (decoded['html_url'] as String?)?.trim() ?? '';

    // The first `.apk` asset is the one the updater installs. GitHub lists
    // assets in upload order, so an APK published for the release wins over
    // any other file type.
    var apkUrl = '';
    final assets = decoded['assets'];
    if (assets is List) {
      for (final asset in assets) {
        if (asset is! Map) continue;
        final name = (asset['name'] as String? ?? '').toLowerCase();
        final url = (asset['browser_download_url'] as String? ?? '').trim();
        if (name.endsWith('.apk') && url.isNotEmpty) {
          apkUrl = url;
          break;
        }
      }
    }

    return LatestRelease(
      version: tag,
      notes: (decoded['body'] as String? ?? '').trim(),
      apkUrl: apkUrl,
      releaseUrl: releaseUrl,
    );
  } catch (_) {
    return null;
  }
}
