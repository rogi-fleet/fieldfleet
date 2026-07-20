import '../../../models/task.dart';

/// Filters and sorts tasks assigned to [userId] that are due or starting
/// today. Returns a list sorted by start time.
List<Task> filterTodaysTasks(List<Task> tasks, String userId) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final tomorrow = today.add(const Duration(days: 1));

  final filtered = tasks.where((task) {
    if (!task.assignedToIds.contains(userId)) return false;
    if (task.isComplete) return false;

    final due = task.dueDate;
    final start = task.startDate;

    // Due today.
    if (due != null && !due.isBefore(today) && due.isBefore(tomorrow)) {
      return true;
    }
    // Starting today.
    if (start != null && !start.isBefore(today) && start.isBefore(tomorrow)) {
      return true;
    }
    return false;
  }).toList();

  filtered.sort((a, b) {
    final aTime = a.startDate ?? a.dueDate;
    final bTime = b.startDate ?? b.dueDate;
    if (aTime == null && bTime == null) return 0;
    if (aTime == null) return 1;
    if (bTime == null) return -1;
    return aTime.compareTo(bTime);
  });

  return filtered;
}
