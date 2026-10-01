import 'package:ah_scanner/core/utils/document_naming.dart';
import 'package:ah_scanner/core/utils/update_checker.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('defaultDocumentName', () {
    test('matches the product naming contract, including the single "n"', () {
      // The task's own example: "AH Scaner 20.08.26 1:16"
      expect(
        defaultDocumentName(DateTime(2026, 8, 20, 1, 16)),
        'AH Scaner 20.08.26 1:16',
      );
    });

    test('pads day, month, year and minutes but not the hour', () {
      expect(
        defaultDocumentName(DateTime(2026, 1, 5, 14, 3)),
        'AH Scaner 05.01.26 14:03',
      );
      expect(
        defaultDocumentName(DateTime(2026, 12, 31, 0, 0)),
        'AH Scaner 31.12.26 0:00',
      );
    });

    test('is not the app name', () {
      expect(
        defaultDocumentName(DateTime(2026, 9, 30, 9, 5)).startsWith('AH Scaner '),
        isTrue,
      );
      expect(
        defaultDocumentName(DateTime(2026, 9, 30, 9, 5)).contains('AH Scanner'),
        isFalse,
      );
    });
  });

  group('UpdateChecker.compareVersions', () {
    test('detects newer, equal and older releases', () {
      expect(UpdateChecker.compareVersions('v1.0.3', '1.0.2'), greaterThan(0));
      expect(UpdateChecker.compareVersions('1.0.2', '1.0.2'), 0);
      expect(UpdateChecker.compareVersions('1.0.1', '1.0.2'), lessThan(0));
    });

    test('ignores a leading v and build metadata', () {
      expect(UpdateChecker.compareVersions('V2.0.0', '1.9.9'), greaterThan(0));
      expect(UpdateChecker.compareVersions('1.0.2+3', 'v1.0.2'), 0);
      expect(UpdateChecker.compareVersions('1.2', '1.2.0'), 0);
    });
  });
}
