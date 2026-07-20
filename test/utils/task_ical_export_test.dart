import 'package:flutter_test/flutter_test.dart';
import 'package:taskfleet_ops/models/task.dart';
import 'package:taskfleet_ops/utils/task_ical_export.dart';

Task _task({
  required String id,
  required String title,
  DateTime? start,
  DateTime? due,
  TaskType taskType = TaskType.standard,
  String status = 'not_started',
  String? description,
}) {
  return Task(
    id: id,
    workspaceId: 'ws1',
    projectId: 'p1',
    title: title,
    startDate: start,
    dueDate: due,
    taskType: taskType,
    status: status,
    description: description,
    createdAt: DateTime(2026, 1, 1),
    updatedAt: DateTime(2026, 1, 1),
  );
}

void main() {
  group('TaskIcalExport.buildIcs', () {
    test('emits all-day events with exclusive DTEND', () {
      final ics = TaskIcalExport.buildIcs(
        tasks: [
          _task(
            id: 't1',
            title: 'Demo day',
            start: DateTime(2026, 6, 1),
            due: DateTime(2026, 6, 3),
          ),
        ],
        calendarName: 'Kitchen Remodel',
      );

      expect(ics, contains('BEGIN:VCALENDAR'));
      expect(ics, contains('X-WR-CALNAME:Kitchen Remodel'));
      expect(ics, contains('UID:t1@taskfleet'));
      expect(ics, contains('DTSTART;VALUE=DATE:20260601'));
      // DTEND is exclusive per RFC 5545: due 6/3 → DTEND 6/4
      expect(ics, contains('DTEND;VALUE=DATE:20260604'));
      expect(ics, contains('SUMMARY:Demo day'));
      // RFC 5545 requires CRLF
      expect(ics, contains('\r\n'));
    });

    test('skips groups and undated tasks, escapes TEXT characters', () {
      final ics = TaskIcalExport.buildIcs(
        tasks: [
          _task(
            id: 'group',
            title: 'Phase 1',
            start: DateTime(2026, 6, 1),
            due: DateTime(2026, 6, 9),
            taskType: TaskType.summary,
          ),
          _task(id: 'undated', title: 'No dates'),
          _task(
            id: 't2',
            title: 'Order tile; grout, sealant',
            start: DateTime(2026, 6, 2),
            due: DateTime(2026, 6, 2),
            status: 'done',
            description: 'Line one\nLine two',
          ),
        ],
        calendarName: 'Test',
      );

      expect(ics, isNot(contains('UID:group@taskfleet')));
      expect(ics, isNot(contains('UID:undated@taskfleet')));
      expect(ics, contains('SUMMARY:Order tile\\; grout\\, sealant'));
      expect(ics, contains('DESCRIPTION:Line one\\nLine two'));
      expect(ics, contains('STATUS:COMPLETED'));
    });

    test('milestone with only a due date becomes a single-day event', () {
      final ics = TaskIcalExport.buildIcs(
        tasks: [
          _task(
            id: 'm1',
            title: 'Inspection',
            due: DateTime(2026, 7, 10),
            taskType: TaskType.milestone,
          ),
        ],
        calendarName: 'Test',
      );

      expect(ics, contains('DTSTART;VALUE=DATE:20260710'));
      expect(ics, contains('DTEND;VALUE=DATE:20260711'));
    });
  });
}
