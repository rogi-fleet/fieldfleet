import 'package:flutter_test/flutter_test.dart';
import 'package:taskfleet_ops/utils/kpi_range_utils.dart';

void main() {
  group('resolveKpiRange', () {
    test('resolves 7D preset to inclusive 7-day window', () {
      final now = DateTime(2026, 2, 16, 15, 30);
      final resolved = resolveKpiRange(
        const KpiRange.preset(KpiRangePreset.sevenDays),
        now: now,
      );

      expect(resolved.start, DateTime(2026, 2, 10));
      expect(resolved.end, DateTime(2026, 2, 16, 23, 59, 59, 999));
      expect(resolved.granularity, KpiBucketGranularity.daily);
    });

    test('resolves YTD to monthly granularity', () {
      final now = DateTime(2026, 7, 12, 8, 0);
      final resolved = resolveKpiRange(
        const KpiRange.preset(KpiRangePreset.yearToDate),
        now: now,
      );

      expect(resolved.start, DateTime(2026, 1, 1));
      expect(resolved.end, DateTime(2026, 7, 12, 23, 59, 59, 999));
      expect(resolved.granularity, KpiBucketGranularity.monthly);
    });

    test('custom range swaps dates when start is after end', () {
      final resolved = resolveKpiRange(
        KpiRange.custom(
          start: DateTime(2026, 2, 20),
          end: DateTime(2026, 2, 10),
        ),
      );

      expect(resolved.start, DateTime(2026, 2, 10));
      expect(resolved.end, DateTime(2026, 2, 20, 23, 59, 59, 999));
      expect(resolved.granularity, KpiBucketGranularity.daily);
    });
  });

  group('generateBucketStarts', () {
    test('creates daily buckets inclusive of end day', () {
      final buckets = generateBucketStarts(
        DateTime(2026, 2, 10),
        DateTime(2026, 2, 12, 23, 59, 59),
        KpiBucketGranularity.daily,
      );

      expect(buckets, [
        DateTime(2026, 2, 10),
        DateTime(2026, 2, 11),
        DateTime(2026, 2, 12),
      ]);
    });

    test('creates monthly buckets from month start', () {
      final buckets = generateBucketStarts(
        DateTime(2026, 1, 20),
        DateTime(2026, 4, 2),
        KpiBucketGranularity.monthly,
      );

      expect(buckets, [
        DateTime(2026, 1, 1),
        DateTime(2026, 2, 1),
        DateTime(2026, 3, 1),
        DateTime(2026, 4, 1),
      ]);
    });
  });
}
