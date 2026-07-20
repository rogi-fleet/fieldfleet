import 'package:csv/csv.dart';
import 'package:intl/intl.dart';
import '../models/task.dart';
import '../models/project.dart';
import '../models/user.dart';

// Reuse the same platform-specific export helpers as budget export.
import 'budget_export_io.dart'
    if (dart.library.html) 'budget_export_web.dart' as platform_export;

class TaskExport {
  static final _dateFormat = DateFormat('yyyy-MM-dd');

  /// Export a list of tasks to CSV and trigger a platform download/share.
  ///
  /// [tasks] – the (already-filtered) tasks to export.
  /// [projectMap] – id → Project lookup for project name / serial number.
  /// [usersMap] – id → AppUser lookup for assignee names.
  /// [fileLabel] – human-readable label used in the file name and share subject.
  Future<void> exportTasksToCsv({
    required List<Task> tasks,
    required Map<String, Project> projectMap,
    required Map<String, AppUser> usersMap,
    String fileLabel = 'tasks',
  }) async {
    if (tasks.isEmpty) {
      throw Exception('No tasks to export');
    }

    final rows = <List<dynamic>>[];

    // Header
    rows.add([
      'Title',
      'Status',
      'Priority',
      'Progress',
      'Project',
      'Job #',
      'Assignees',
      'Start Date',
      'Due Date',
      'Est. Hours',
      'Description',
    ]);

    for (final task in tasks) {
      final project = projectMap[task.projectId];
      final assigneeNames = task.assignedToIds
          .map((id) => usersMap[id]?.displayName ?? id)
          .join(', ');

      rows.add([
        task.title,
        task.status,
        task.priority,
        '${task.progress}%',
        project?.name ?? '',
        project?.serialNumber ?? '',
        assigneeNames,
        task.startDate != null ? _dateFormat.format(task.startDate!) : '',
        task.dueDate != null ? _dateFormat.format(task.dueDate!) : '',
        task.estimatedDuration?.toString() ?? '',
        task.description ?? '',
      ]);
    }

    final csv = const ListToCsvConverter().convert(rows);
    final safeLabel = fileLabel.replaceAll(' ', '_').replaceAll(RegExp(r'[^\w]'), '');
    final fileName = '${safeLabel}_${DateTime.now().millisecondsSinceEpoch}.csv';

    await platform_export.exportCsv(csv, fileName, 'Task Export – $fileLabel');
  }
}
