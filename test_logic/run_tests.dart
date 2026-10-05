// Pure-logic test runner for AH Scanner.
//
// Deliberately uses no test framework: `package:test`/`flutter_test` cannot run
// here (the app's dartcv4/OpenCV build hook needs a desktop C++ toolchain), so
// these checks run as a plain Dart program instead. Exit code 0 = all passed.
//
//   cd test_logic && dart run run_tests.dart

import '../lib/core/utils/document_naming.dart';
import '../lib/core/utils/release_parser.dart';
import '../lib/core/utils/version_compare.dart';

int _passed = 0;
final List<String> _failures = <String>[];

void _check(String label, bool ok, [String? detail]) {
  if (ok) {
    _passed++;
  } else {
    _failures.add(detail == null ? label : '$label\n       $detail');
  }
}

void _expect(String label, Object? actual, Object? expected) {
  _check(
    label,
    actual == expected,
    'expected: $expected\n       actual:   $actual',
  );
}

void main() {
  // --- Document naming contract -------------------------------------------
  // "AH Scaner DD.MM.YY H:MM" - the single "n" is intentional (product string,
  // not the app name, which is "AH Scanner").
  _expect(
    'naming: the documented example',
    defaultDocumentName(DateTime(2026, 8, 20, 1, 16)),
    'AH Scaner 20.08.26 1:16',
  );
  _expect(
    'naming: pads day/month/year/minute but not the hour',
    defaultDocumentName(DateTime(2026, 1, 5, 14, 3)),
    'AH Scaner 05.01.26 14:03',
  );
  _expect(
    'naming: midnight',
    defaultDocumentName(DateTime(2026, 12, 31, 0, 0)),
    'AH Scaner 31.12.26 0:00',
  );
  _check(
    'naming: never the app name',
    !defaultDocumentName(DateTime(2026, 9, 30, 9, 5)).contains('AH Scanner'),
  );

  // --- Version comparison --------------------------------------------------
  _check('version: newer beats older', compareVersionStrings('v1.0.3', '1.0.2') > 0);
  _expect('version: equal', compareVersionStrings('1.0.2', '1.0.2'), 0);
  _check('version: older', compareVersionStrings('1.0.1', '1.0.2') < 0);
  _check(
    'version: uppercase V and two-digit majors',
    compareVersionStrings('V2.0.0', '1.9.9') > 0,
  );
  _expect(
    'version: build metadata ignored',
    compareVersionStrings('1.0.2+3', 'v1.0.2'),
    0,
  );
  _expect(
    'version: missing parts count as zero',
    compareVersionStrings('1.2', '1.2.0'),
    0,
  );

  // --- GitHub release parsing ---------------------------------------------
  const bodyWithApk = '''
{"tag_name":"v1.0.7","html_url":"https://github.com/x/y/releases/tag/v1.0.7",
 "body":"  notes here  ",
 "assets":[
   {"name":"notes.txt","browser_download_url":"https://x/notes.txt"},
   {"name":"AH-Scanner-1.0.7.apk","browser_download_url":"https://x/app.apk"}]}''';
  final release = parseLatestRelease(bodyWithApk);
  _expect('release: tag kept as published', release?.version, 'v1.0.7');
  _expect('release: notes trimmed', release?.notes, 'notes here');
  _expect('release: first apk asset wins', release?.apkUrl, 'https://x/app.apk');
  _expect(
    'release: release page',
    release?.releaseUrl,
    'https://github.com/x/y/releases/tag/v1.0.7',
  );

  const bodyWithoutApk =
      '{"tag_name":"v1.0.7","html_url":"https://x","assets":[{"name":"notes.txt","browser_download_url":"https://x/notes.txt"}]}';
  _expect(
    'release: no apk asset leaves the url empty',
    parseLatestRelease(bodyWithoutApk)?.apkUrl,
    '',
  );
  _expect('release: not json', parseLatestRelease('<html>oops</html>'), null);
  _expect('release: json array', parseLatestRelease('[]'), null);
  _expect('release: no tag', parseLatestRelease('{"html_url":"https://x"}'), null);
  _expect('release: blank tag', parseLatestRelease('{"tag_name":"   "}'), null);

  // --- Report --------------------------------------------------------------
  if (_failures.isEmpty) {
    print('OK - $_passed assertions passed');
    return;
  }
  print('FAILED - ${_failures.length} of ${_passed + _failures.length}\n');
  for (final failure in _failures) {
    print('  x $failure');
  }
  throw StateError('${_failures.length} assertion(s) failed');
}
