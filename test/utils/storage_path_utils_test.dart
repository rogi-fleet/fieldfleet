import 'package:flutter_test/flutter_test.dart';
import 'package:taskfleet_ops/utils/storage_path_utils.dart';

void main() {
  group('buildUniqueStorageFileName', () {
    test('replaces unsupported characters in storage filenames', () {
      expect(
        buildUniqueStorageFileName(
          'Screenshot 2026-01-17 at 11.31.04\u202fPM.png',
          timestampMs: 1772941286024,
        ),
        'Screenshot_2026-01-17_at_11.31.04_PM_1772941286024.png',
      );
    });

    test('keeps a valid extensionless filename usable', () {
      expect(
        buildUniqueStorageFileName('field report', timestampMs: 42),
        'field_report_42',
      );
    });

    test('falls back when the source filename sanitizes to empty', () {
      expect(
        buildUniqueStorageFileName('   ...   ', timestampMs: 42),
        'file_42',
      );
    });
  });
}
