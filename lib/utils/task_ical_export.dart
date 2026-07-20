import 'package:intl/intl.dart';
import '../models/gantt_task_extensions.dart';
import '../models/task.dart';

// Reuse the same platform-specific export helpers as budget/task CSV export.
import 'budget_export_io.dart'
    if (dart.library.html) 'budget_export_web.dart' as platform_export;

/// Exports a project schedule as an iCalendar (.ics) file so crews can pull
/// tasks into Google Calendar / Outlook / Apple Calendar.
///
/// Tasks become all-day VEVENTs spanning effective start → due date
/// (DTEND is exclusive per RFC 5545, hence the +1 day). Milestones become
/// single-day events. Undated tasks are skipped.
class TaskIcalExport {
  static final _icsDate = DateFormat('yyyyMMdd');
  static final _icsDateTime = DateFormat("yyyyMMdd'T'HHmmss'Z'");

  /// Generate the .ics content. Exposed for tests.
  static String buildIcs({
    required List<Task> tasks,
    required String calendarName,
  }) {
    final now = DateTime.now().toUtc();
    final dtStamp = _icsDateTime.format(now);

    final buffer = StringBuffer()
      ..writeln('BEGIN:VCALENDAR')
      ..writeln('VERSION:2.0')
      ..writeln('PRODID:-//TaskFleet//Schedule Export//EN')
      ..writeln('CALSCALE:GREGORIAN')
      ..writeln('METHOD:PUBLISH')
      ..writeln('X-WR-CALNAME:${_escape(calendarName)}');

    for (final task in tasks) {
      // Groups are containers — exporting them would double-cover their
      // children's date spans.
      if (task.taskType == TaskType.summary) continue;

      final start = task.getEffectiveStartDate(tasks);
      final end = task.getEffectiveEndDate(tasks);
      final eventStart = start ?? end;
      if (eventStart == null) continue;
      final eventEnd = (end != null && end.isAfter(eventStart))
          ? end
          : eventStart;

      buffer
        ..writeln('BEGIN:VEVENT')
        ..writeln('UID:${task.id}@taskfleet')
        ..writeln('DTSTAMP:$dtStamp')
        ..writeln('DTSTART;VALUE=DATE:${_icsDate.format(eventStart)}')
        ..writeln(
          'DTEND;VALUE=DATE:'
          '${_icsDate.format(eventEnd.add(const Duration(days: 1)))}',
        )
        ..writeln('SUMMARY:${_escape(task.title)}');
      final description = task.description;
      if (description != null && description.trim().isNotEmpty) {
        buffer.writeln('DESCRIPTION:${_escape(description.trim())}');
      }
      buffer
        ..writeln('STATUS:${task.status == 'done' ? 'COMPLETED' : 'CONFIRMED'}')
        ..writeln('END:VEVENT');
    }

    buffer.writeln('END:VCALENDAR');
    // RFC 5545 requires CRLF line endings.
    return buffer.toString().replaceAll('\n', '\r\n');
  }

  /// Build and download/share the .ics file.
  static Future<void> exportSchedule({
    required List<Task> tasks,
    required String calendarName,
  }) async {
    final ics = buildIcs(tasks: tasks, calendarName: calendarName);
    final safeLabel = calendarName
        .replaceAll(' ', '_')
        .replaceAll(RegExp(r'[^\w]'), '');
    final fileName =
        '${safeLabel.isEmpty ? 'schedule' : safeLabel}_schedule.ics';
    await platform_export.exportCsv(
      ics,
      fileName,
      'Schedule – $calendarName',
    );
  }

  /// Escape per RFC 5545 TEXT rules: backslash, semicolon, comma, newline.
  static String _escape(String value) {
    return value
        .replaceAll('\\', '\\\\')
        .replaceAll(';', '\\;')
        .replaceAll(',', '\\,')
        .replaceAll('\r\n', '\\n')
        .replaceAll('\n', '\\n');
  }
}
