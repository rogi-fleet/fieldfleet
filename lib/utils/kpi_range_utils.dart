enum KpiRangePreset {
  sevenDays,
  thirtyDays,
  quarterToDate,
  yearToDate,
  twelveMonths,
  custom,
}

enum KpiBucketGranularity { daily, monthly }

class KpiRange {
  final KpiRangePreset preset;
  final DateTime? customStart;
  final DateTime? customEnd;

  const KpiRange._({required this.preset, this.customStart, this.customEnd});

  const KpiRange.preset(KpiRangePreset preset)
    : this._(preset: preset, customStart: null, customEnd: null);

  const KpiRange.custom({required DateTime start, required DateTime end})
    : this._(preset: KpiRangePreset.custom, customStart: start, customEnd: end);

  bool get isCustom => preset == KpiRangePreset.custom;

  String get label {
    switch (preset) {
      case KpiRangePreset.sevenDays:
        return '7D';
      case KpiRangePreset.thirtyDays:
        return '30D';
      case KpiRangePreset.quarterToDate:
        return 'QTD';
      case KpiRangePreset.yearToDate:
        return 'YTD';
      case KpiRangePreset.twelveMonths:
        return '12M';
      case KpiRangePreset.custom:
        return 'Custom';
    }
  }
}

class KpiResolvedRange {
  final DateTime start;
  final DateTime end;
  final KpiBucketGranularity granularity;

  const KpiResolvedRange({
    required this.start,
    required this.end,
    required this.granularity,
  });
}

DateTime kpiStartOfDay(DateTime date) =>
    DateTime(date.year, date.month, date.day);

DateTime kpiEndOfDay(DateTime date) =>
    DateTime(date.year, date.month, date.day, 23, 59, 59, 999);

KpiResolvedRange resolveKpiRange(KpiRange range, {DateTime? now}) {
  final reference = now ?? DateTime.now();
  final todayEnd = kpiEndOfDay(reference);

  DateTime start;
  DateTime end;

  switch (range.preset) {
    case KpiRangePreset.sevenDays:
      end = todayEnd;
      start = kpiStartOfDay(end.subtract(const Duration(days: 6)));
      break;
    case KpiRangePreset.thirtyDays:
      end = todayEnd;
      start = kpiStartOfDay(end.subtract(const Duration(days: 29)));
      break;
    case KpiRangePreset.quarterToDate:
      final quarterStartMonth = ((reference.month - 1) ~/ 3) * 3 + 1;
      start = DateTime(reference.year, quarterStartMonth, 1);
      end = todayEnd;
      break;
    case KpiRangePreset.yearToDate:
      start = DateTime(reference.year, 1, 1);
      end = todayEnd;
      break;
    case KpiRangePreset.twelveMonths:
      end = todayEnd;
      start = DateTime(reference.year, reference.month - 11, 1);
      break;
    case KpiRangePreset.custom:
      final customStart = range.customStart;
      final customEnd = range.customEnd;
      if (customStart == null || customEnd == null) {
        end = todayEnd;
        start = kpiStartOfDay(end.subtract(const Duration(days: 29)));
      } else {
        final startDate = kpiStartOfDay(customStart);
        final endDate = kpiEndOfDay(customEnd);
        if (startDate.isAfter(endDate)) {
          start = kpiStartOfDay(customEnd);
          end = kpiEndOfDay(customStart);
        } else {
          start = startDate;
          end = endDate;
        }
      }
      break;
  }

  final dayCount = end.difference(start).inDays + 1;
  final granularity = _resolveGranularity(range, dayCount);

  return KpiResolvedRange(start: start, end: end, granularity: granularity);
}

KpiBucketGranularity _resolveGranularity(KpiRange range, int dayCount) {
  if (range.preset == KpiRangePreset.sevenDays ||
      range.preset == KpiRangePreset.thirtyDays) {
    return KpiBucketGranularity.daily;
  }
  if (range.preset == KpiRangePreset.custom) {
    return dayCount <= 45
        ? KpiBucketGranularity.daily
        : KpiBucketGranularity.monthly;
  }
  return KpiBucketGranularity.monthly;
}

DateTime normalizeBucketDate(DateTime date, KpiBucketGranularity granularity) {
  switch (granularity) {
    case KpiBucketGranularity.daily:
      return DateTime(date.year, date.month, date.day);
    case KpiBucketGranularity.monthly:
      return DateTime(date.year, date.month, 1);
  }
}

List<DateTime> generateBucketStarts(
  DateTime start,
  DateTime end,
  KpiBucketGranularity granularity,
) {
  final normalizedStart = normalizeBucketDate(start, granularity);
  final result = <DateTime>[];

  var cursor = normalizedStart;
  while (!cursor.isAfter(end)) {
    result.add(cursor);
    cursor = granularity == KpiBucketGranularity.daily
        ? cursor.add(const Duration(days: 1))
        : DateTime(cursor.year, cursor.month + 1, 1);
  }

  return result;
}

String kpiDateOnlyString(DateTime date) {
  final y = date.year.toString().padLeft(4, '0');
  final m = date.month.toString().padLeft(2, '0');
  final d = date.day.toString().padLeft(2, '0');
  return '$y-$m-$d';
}
