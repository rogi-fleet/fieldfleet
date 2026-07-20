import 'package:flutter/material.dart';

enum TimelineView {
  day,
  week,
  month,
  quarter,
  year;

  /// Parse a toolbar label ('Day', 'Week', 'Month', 'Quarter', 'Year') into a value.
  static TimelineView fromLabel(String label) {
    switch (label) {
      case 'Day':
        return TimelineView.day;
      case 'Week':
        return TimelineView.week;
      case 'Quarter':
        return TimelineView.quarter;
      case 'Year':
        return TimelineView.year;
      case 'Month':
      default:
        return TimelineView.month;
    }
  }

  /// The toolbar display label for this view.
  String get label {
    switch (this) {
      case TimelineView.day:
        return 'Day';
      case TimelineView.week:
        return 'Week';
      case TimelineView.month:
        return 'Month';
      case TimelineView.quarter:
        return 'Quarter';
      case TimelineView.year:
        return 'Year';
    }
  }
}

class TimelineCalculator {
  final TimelineView viewMode;
  final DateTime anchorDate;
  final bool showBusinessDaysOnly;

  // Pixels per day for each view mode
  static const double dayViewPixelsPerDay = 120.0;
  static const double weekViewPixelsPerDay = 40.0;
  static const double monthViewPixelsPerDay = 20.0;
  static const double quarterViewPixelsPerDay = 4.0;
  static const double yearViewPixelsPerDay = 1.5;

  TimelineCalculator({
    required this.viewMode,
    required this.anchorDate,
    this.showBusinessDaysOnly = false,
  });

  /// Get pixels per day based on current view mode
  double get pixelsPerDay {
    switch (viewMode) {
      case TimelineView.day:
        return dayViewPixelsPerDay;
      case TimelineView.week:
        return weekViewPixelsPerDay;
      case TimelineView.month:
        return monthViewPixelsPerDay;
      case TimelineView.quarter:
        return quarterViewPixelsPerDay;
      case TimelineView.year:
        return yearViewPixelsPerDay;
    }
  }

  /// Get the visible date range for the current view mode
  DateTimeRange getVisibleRange() {
    switch (viewMode) {
      case TimelineView.day:
        // Show 2 days centered on anchor
        return DateTimeRange(
          start: anchorDate.subtract(const Duration(days: 1)),
          end: anchorDate.add(const Duration(days: 2)),
        );

      case TimelineView.week:
        // Show 3 weeks centered on anchor's week
        final weekStart = _getWeekStart(anchorDate);
        return DateTimeRange(
          start: weekStart.subtract(const Duration(days: 7)),
          end: weekStart.add(const Duration(days: 21)),
        );

      case TimelineView.month:
        // Show 2 months centered on anchor's month
        final monthStart = DateTime(anchorDate.year, anchorDate.month, 1);
        return DateTimeRange(
          start: DateTime(monthStart.year, monthStart.month - 1, 1),
          end: DateTime(monthStart.year, monthStart.month + 2, 0, 23, 59, 59),
        );

      case TimelineView.quarter:
        // Show 6 months centered on anchor's quarter
        final quarterStart = _getQuarterStart(anchorDate);
        return DateTimeRange(
          start: DateTime(quarterStart.year, quarterStart.month - 3, 1),
          end: DateTime(quarterStart.year, quarterStart.month + 6, 0, 23, 59, 59),
        );

      case TimelineView.year:
        // Show 2 years centered on anchor's year
        return DateTimeRange(
          start: DateTime(anchorDate.year - 1, 1, 1),
          end: DateTime(anchorDate.year + 1, 12, 31, 23, 59, 59),
        );
    }
  }

  /// Convert a date to pixel position relative to range start
  double dateToPixel(DateTime date, DateTime rangeStart) {
    // Normalize both dates to the start of day (midnight) for consistent positioning
    final normalizedDate = DateTime(date.year, date.month, date.day);
    final normalizedRangeStart = DateTime(rangeStart.year, rangeStart.month, rangeStart.day);

    if (showBusinessDaysOnly) {
      // Count business days between range start and date
      final businessDays = countBusinessDays(normalizedRangeStart, normalizedDate);
      return businessDays * pixelsPerDay;
    } else {
      final daysDiff = normalizedDate.difference(normalizedRangeStart).inDays;
      return daysDiff * pixelsPerDay;
    }
  }

  /// Count the number of business days between two dates (excluding weekends)
  int countBusinessDays(DateTime start, DateTime end) {
    if (end.isBefore(start)) return 0;

    int count = 0;
    DateTime current = start;
    
    // Safety limit to prevent freezes from extreme date ranges (max ~13 years)
    int iterations = 0;
    const int maxIterations = 5000;

    while (current.isBefore(end) && iterations < maxIterations) {
      if (!isWeekend(current)) {
        count++;
      }
      current = current.add(const Duration(days: 1));
      iterations++;
    }

    return count;
  }

  /// Get the total number of business days in a year (approximately 260)
  int get totalBusinessDaysInYear => showBusinessDaysOnly ? 260 : 365;

  /// Get the index position for a date in the timeline (accounting for business days mode)
  int getDateIndex(DateTime date, DateTime rangeStart) {
    final normalizedDate = DateTime(date.year, date.month, date.day);
    final normalizedRangeStart = DateTime(rangeStart.year, rangeStart.month, rangeStart.day);

    if (showBusinessDaysOnly) {
      return countBusinessDays(normalizedRangeStart, normalizedDate);
    } else {
      return normalizedDate.difference(normalizedRangeStart).inDays;
    }
  }

  /// Convert duration in hours to pixel width
  double durationToPixels(double hours) {
    final days = hours / 8.0; // 8 hours = 1 work day
    return days * pixelsPerDay;
  }

  /// Convert pixel width to duration in hours
  double pixelToDuration(double pixels) {
    final days = pixels / pixelsPerDay;
    return days * 8.0; // 8 hours = 1 work day
  }

  /// Get pixel position for a task based on its start date or due date
  double getTaskPosition(DateTime? startDate, DateTime? dueDate, DateTime rangeStart) {
    final effectiveDate = startDate ?? dueDate;
    if (effectiveDate == null) return 0;
    return dateToPixel(effectiveDate, rangeStart);
  }

  /// Get pixel width for a task based on duration or date range
  double getTaskWidth(DateTime? startDate, DateTime? dueDate, double? estimatedDuration) {
    // If we have estimated duration, use it
    if (estimatedDuration != null && estimatedDuration > 0) {
      return durationToPixels(estimatedDuration);
    }

    // If we have both dates, calculate from date range
    if (startDate != null && dueDate != null) {
      // Normalize dates to start of day
      final normalizedStart = DateTime(startDate.year, startDate.month, startDate.day);
      final normalizedEnd = DateTime(dueDate.year, dueDate.month, dueDate.day);

      if (showBusinessDaysOnly) {
        // Count business days between dates (+1 to include end date)
        final businessDays = countBusinessDays(normalizedStart, normalizedEnd.add(const Duration(days: 1)));
        return businessDays > 0 ? businessDays * pixelsPerDay : pixelsPerDay;
      } else {
        // Calculate calendar days (+1 to include both start and end date)
        final daysDiff = normalizedEnd.difference(normalizedStart).inDays + 1;
        return daysDiff > 0 ? daysDiff * pixelsPerDay : pixelsPerDay;
      }
    }

    // Default to 1 day width
    return pixelsPerDay;
  }

  /// Check if a date is a weekend
  bool isWeekend(DateTime date) {
    return date.weekday == DateTime.saturday || date.weekday == DateTime.sunday;
  }

  /// Get the start of the week (Monday) for a given date
  DateTime _getWeekStart(DateTime date) {
    return date.subtract(Duration(days: date.weekday - 1));
  }

  /// Get the start of the quarter for a given date
  DateTime _getQuarterStart(DateTime date) {
    final quarterMonth = ((date.month - 1) ~/ 3) * 3 + 1;
    return DateTime(date.year, quarterMonth, 1);
  }

  /// Generate date labels for the timeline header
  List<DateLabel> generateDateLabels() {
    final range = getVisibleRange();
    final labels = <DateLabel>[];

    switch (viewMode) {
      case TimelineView.day:
        // Show hours
        var current = range.start;
        while (current.isBefore(range.end)) {
          labels.add(DateLabel(
            date: current,
            label: '${current.hour}:00',
            isWeekend: isWeekend(current),
          ));
          current = current.add(const Duration(hours: 1));
        }
        break;

      case TimelineView.week:
        // Show days
        var current = range.start;
        while (current.isBefore(range.end)) {
          labels.add(DateLabel(
            date: current,
            label: _formatDayLabel(current),
            isWeekend: isWeekend(current),
          ));
          current = current.add(const Duration(days: 1));
        }
        break;

      case TimelineView.month:
        // Show weeks
        var current = _getWeekStart(range.start);
        while (current.isBefore(range.end)) {
          labels.add(DateLabel(
            date: current,
            label: 'Week ${_getWeekNumber(current)}',
            isWeekend: false,
          ));
          current = current.add(const Duration(days: 7));
        }
        break;

      case TimelineView.quarter:
        // Show months
        var current = DateTime(range.start.year, range.start.month, 1);
        while (current.isBefore(range.end)) {
          labels.add(DateLabel(
            date: current,
            label: _formatMonthLabel(current),
            isWeekend: false,
          ));
          current = DateTime(current.year, current.month + 1, 1);
        }
        break;

      case TimelineView.year:
        // Show quarters
        var current = DateTime(range.start.year, ((range.start.month - 1) ~/ 3) * 3 + 1, 1);
        while (current.isBefore(range.end)) {
          final q = ((current.month - 1) ~/ 3) + 1;
          labels.add(DateLabel(
            date: current,
            label: 'Q$q ${current.year}',
            isWeekend: false,
          ));
          current = DateTime(current.year, current.month + 3, 1);
        }
        break;
    }

    return labels;
  }

  String _formatDayLabel(DateTime date) {
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return '${days[date.weekday - 1]} ${date.month}/${date.day}';
  }

  String _formatMonthLabel(DateTime date) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
                    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return months[date.month - 1];
  }

  int _getWeekNumber(DateTime date) {
    final dayOfYear = int.parse(date.difference(DateTime(date.year, 1, 1)).inDays.toString());
    return ((dayOfYear - date.weekday + 10) / 7).floor();
  }
}

class DateLabel {
  final DateTime date;
  final String label;
  final bool isWeekend;

  DateLabel({
    required this.date,
    required this.label,
    required this.isWeekend,
  });
}
