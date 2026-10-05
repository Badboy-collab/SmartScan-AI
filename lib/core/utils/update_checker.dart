import 'package:http/http.dart' as http;

import 'release_parser.dart';
import 'version_compare.dart';

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

  /// `true` when [downloadUrl] points at an installable APK rather than a page.
  /// The in-app updater only downloads the former; otherwise it hands the link
  /// to the browser.
  bool get hasApkAsset => downloadUrl.toLowerCase().endsWith('.apk');
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
/// failure-tolerant: nothing here may ever block or crash the app. The response
/// parsing and version comparison live in their own pure files so they can be
/// unit tested without the native toolchain - see `test_logic/`.
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

      final release = parseLatestRelease(response.body);
      if (release == null) return UpdateCheck.noRelease;

      return UpdateCheck(
        reachedServer: true,
        info: UpdateInfo(
          version: release.version,
          notes: release.notes,
          // Releases without an APK asset still offer their page, which keeps
          // the update button useful instead of dead.
          downloadUrl: release.apkUrl.isNotEmpty
              ? release.apkUrl
              : release.releaseUrl,
          releaseUrl: release.releaseUrl,
        ),
      );
    } catch (_) {
      // Offline, DNS failure, timeout, rate limit, bad JSON — stay quiet.
      return UpdateCheck.unreachable;
    }
  }

  /// `a` newer than `b` → positive, equal → 0, older → negative.
  static int compareVersions(String a, String b) => compareVersionStrings(a, b);
}
