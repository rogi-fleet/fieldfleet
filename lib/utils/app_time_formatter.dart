import 'package:intl/intl.dart';

class AppTimeFormatter {
  static String formatDateTime(
    DateTime value, {
    String pattern = 'yyyy-MM-dd HH:mm',
    String? timezone,
  }) {
    final normalizedTz = timezone?.trim();
    final resolved = normalizedTz == 'UTC' ? value.toUtc() : value.toLocal();
    final base = DateFormat(pattern).format(resolved);
    if (normalizedTz == null || normalizedTz.isEmpty) {
      return base;
    }
    return '$base $normalizedTz';
  }

  static String formatDate(
    DateTime value, {
    String pattern = 'yyyy-MM-dd',
    String? timezone,
  }) {
    return formatDateTime(value, pattern: pattern, timezone: timezone);
  }
}
