import '../models/project.dart';
import '../models/task.dart';
import '../models/project_health_score.dart';
import '../models/project_financial_summary.dart';

/// Pure Dart service — no DB calls. Computes a deterministic health score
/// from data that's already available on the client.
class ProjectHealthService {
  const ProjectHealthService();

  ProjectHealthScore computeScore({
    required Project project,
    required List<Task> tasks,
    ProjectFinancialSummary? financials,
  }) {
    final schedule = _scheduleScore(project, tasks);
    final budget = _budgetScore(financials);
    final velocity = _taskVelocityScore(project, tasks);
    final overdue = _overdueTasksScore(tasks);

    return _buildScore(
      schedule: schedule,
      budget: budget,
      velocity: velocity,
      overdue: overdue,
    );
  }

  ProjectHealthScore computeScoreFromMetrics({
    required Project project,
    required int totalTasks,
    required int completedTasks,
    required int overdueTasks,
    ProjectFinancialSummary? financials,
  }) {
    final schedule = _scheduleScoreFromCounts(
      project: project,
      totalTasks: totalTasks,
      completedTasks: completedTasks,
    );
    final budget = _budgetScore(financials);
    final velocity = _taskVelocityScoreFromCounts(
      project: project,
      totalTasks: totalTasks,
      completedTasks: completedTasks,
    );
    final overdue = _overdueTasksScoreFromCounts(
      totalTasks: totalTasks,
      completedTasks: completedTasks,
      overdueTasks: overdueTasks,
    );

    return _buildScore(
      schedule: schedule,
      budget: budget,
      velocity: velocity,
      overdue: overdue,
    );
  }

  ProjectHealthScore _buildScore({
    required int schedule,
    required int budget,
    required int velocity,
    required int overdue,
  }) {
    // Weighted average: schedule 30%, budget 25%, velocity 25%, overdue 20%
    final overall =
        (schedule * 0.30 + budget * 0.25 + velocity * 0.25 + overdue * 0.20)
            .round()
            .clamp(0, 100);

    return ProjectHealthScore(
      overallScore: overall,
      scheduleScore: schedule,
      budgetScore: budget,
      taskVelocityScore: velocity,
      overdueTasksScore: overdue,
    );
  }

  // ---------------------------------------------------------------------------
  // Schedule (30%): task completion % vs timeline elapsed %
  // ---------------------------------------------------------------------------
  int _scheduleScore(Project project, List<Task> tasks) {
    return _scheduleScoreFromCounts(
      project: project,
      totalTasks: tasks.length,
      completedTasks: tasks.where((t) => t.isComplete).length,
    );
  }

  int _scheduleScoreFromCounts({
    required Project project,
    required int totalTasks,
    required int completedTasks,
  }) {
    if (totalTasks == 0) return 100;
    if (project.status.isClosed) return 100;

    final completionPct = completedTasks / totalTasks;

    // If no timeline, score based on completion alone
    if (project.startDate == null || project.targetCompletionDate == null) {
      return (completionPct * 100).round().clamp(0, 100);
    }

    final now = DateTime.now();
    final totalDays = project.targetCompletionDate!
        .difference(project.startDate!)
        .inDays;
    final elapsed = now.difference(project.startDate!).inDays;
    final timelinePct = totalDays > 0
        ? (elapsed / totalDays).clamp(0.0, 1.5)
        : 0.0;

    if (timelinePct <= 0) return 100;

    // Ratio: > 1 means ahead of schedule, < 1 means behind
    final ratio = completionPct / timelinePct;
    if (ratio >= 1.0) return 100;
    if (ratio >= 0.8) return 80;
    if (ratio >= 0.6) return 60;
    if (ratio >= 0.4) return 40;
    if (ratio >= 0.2) return 20;
    return 10;
  }

  // ---------------------------------------------------------------------------
  // Budget (25%): margin health
  // ---------------------------------------------------------------------------
  int _budgetScore(ProjectFinancialSummary? f) {
    if (f == null) return 75; // No financials → neutral

    if (f.hasHealthyMargin) return 100;
    if (f.hasLowMargin) return 70;
    if (f.hasCriticalMargin) return 40;
    return 15; // danger
  }

  // ---------------------------------------------------------------------------
  // Task velocity (25%): completed tasks vs expected at current point
  // ---------------------------------------------------------------------------
  int _taskVelocityScore(Project project, List<Task> tasks) {
    return _taskVelocityScoreFromCounts(
      project: project,
      totalTasks: tasks.length,
      completedTasks: tasks.where((t) => t.isComplete).length,
    );
  }

  int _taskVelocityScoreFromCounts({
    required Project project,
    required int totalTasks,
    required int completedTasks,
  }) {
    if (totalTasks == 0) return 100;
    if (project.status.isClosed) return 100;

    if (project.startDate == null || project.targetCompletionDate == null) {
      // Without timeline, use raw completion %
      return (completedTasks / totalTasks * 100).round().clamp(0, 100);
    }

    final now = DateTime.now();
    final totalDays = project.targetCompletionDate!
        .difference(project.startDate!)
        .inDays;
    final elapsed = now.difference(project.startDate!).inDays;
    final timelinePct = totalDays > 0
        ? (elapsed / totalDays).clamp(0.0, 1.0)
        : 0.0;

    final expectedCompleted = (totalTasks * timelinePct).ceil();
    if (expectedCompleted <= 0) return 100;

    final ratio = completedTasks / expectedCompleted;
    if (ratio >= 1.0) return 100;
    if (ratio >= 0.75) return 75;
    if (ratio >= 0.5) return 50;
    if (ratio >= 0.25) return 25;
    return 10;
  }

  // ---------------------------------------------------------------------------
  // Overdue tasks (20%): percentage of tasks past due date
  // ---------------------------------------------------------------------------
  int _overdueTasksScore(List<Task> tasks) {
    final completedTasks = tasks.where((t) => t.isComplete).length;
    final overdueTasks = tasks.where((t) => t.isOverdue()).length;

    return _overdueTasksScoreFromCounts(
      totalTasks: tasks.length,
      completedTasks: completedTasks,
      overdueTasks: overdueTasks,
    );
  }

  int _overdueTasksScoreFromCounts({
    required int totalTasks,
    required int completedTasks,
    required int overdueTasks,
  }) {
    if (totalTasks == 0) return 100;

    final incompleteCount = totalTasks - completedTasks;
    if (incompleteCount <= 0) return 100;

    final overduePct = overdueTasks / incompleteCount;
    if (overduePct <= 0.0) return 100;
    if (overduePct <= 0.1) return 85;
    if (overduePct <= 0.25) return 65;
    if (overduePct <= 0.5) return 40;
    return 15;
  }
}
