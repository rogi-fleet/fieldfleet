import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../../models/project.dart';
import '../../../models/project_financial_summary.dart';
import '../../../providers/workspace_provider.dart';
import '../../../services/service_locator.dart';
import '../../../theme/theme.dart';
import '../../../utils/project_terminology.dart';

enum AlertType {
  budgetOverrun,
  behindSchedule,
  overdue,
  lowBudgetRemaining,
  noBudget,
  laborOverBudget,
  laborNearBudget,
}

class ProjectAlert {
  final AlertType type;
  final String title;
  final String message;
  final AppSeverity severity;
  final IconData icon;

  ProjectAlert({
    required this.type,
    required this.title,
    required this.message,
    required this.severity,
    required this.icon,
  });
}

/// Active Alerts widget showing important project notifications
class ActiveAlertsWidget extends StatelessWidget {
  final Project project;

  const ActiveAlertsWidget({super.key, required this.project});

  @override
  Widget build(BuildContext context) {
    final projectTerminology = context.watch<WorkspaceProvider>().projectTerminology;
    final singular = singularProjectTerminology(projectTerminology);
    return FutureBuilder<List<ProjectAlert>>(
      future: ProjectAlertsEngine.generateAlerts(project, singular: singular),
      builder: (context, snapshot) {
        final alerts = snapshot.data ?? [];
        final headerColors = _headerSeverityColors(alerts);

        return Card(
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.notifications_active,
                      color: headerColors.accent,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Active Alerts',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (alerts.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.sm,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: headerColors.accent,
                          borderRadius: BorderRadius.circular(AppRadius.r12),
                        ),
                        child: Text(
                          '${alerts.length}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                if (alerts.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 6),
                    child: Text(
                      'No active alerts',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 14,
                      ),
                    ),
                  ),
                if (alerts.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  ...alerts.map((alert) => _buildAlertItem(context, alert)),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildAlertItem(BuildContext context, ProjectAlert alert) {
    final colors = AppSeverityTheme.colors(alert.severity);
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: colors.background,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: colors.border, width: 1),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(alert.icon, color: colors.accent, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  alert.title,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: colors.label,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  alert.message,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  AppSeverityColors _headerSeverityColors(List<ProjectAlert> alerts) {
    if (alerts.isEmpty) {
      return AppSeverityTheme.colors(
        AppSeverity.neutral,
        neutralBackground: AppColors.surface,
      );
    }
    final hasError = alerts.any((alert) => alert.severity == AppSeverity.error);
    final severity = hasError ? AppSeverity.error : AppSeverity.warning;
    return AppSeverityTheme.colors(severity);
  }
}

class ProjectAlertsEngine {
  static Future<List<ProjectAlert>> generateAlerts(
    Project project, {
    ProjectFinancialSummary? financialSummary,
    String singular = 'Project',
  }) async {
    final alerts = <ProjectAlert>[];

    try {
      final budget = project.estimatedBudget ?? 0.0;

      // Budget alerts
      if (budget > 0) {
        final double revenue;
        if (financialSummary != null) {
          revenue = financialSummary.collectedSoFar;
        } else {
          revenue =
              await ServiceLocator.projectService.calculateProjectRevenue(
                    project.id,
                    project.workspaceId,
                  )
                  as double;
        }
        final budgetUsage = revenue / budget;
        final budgetRemaining = budget - revenue;

        if (budgetUsage > 1.0) {
          alerts.add(
            ProjectAlert(
              type: AlertType.budgetOverrun,
              title: 'Budget Overrun',
              message:
                  'Project has exceeded budget by \$${NumberFormat('#,##0').format(revenue - budget)}',
              severity: AppSeverity.error,
              icon: Icons.error,
            ),
          );
        } else if (budgetUsage > 0.9) {
          alerts.add(
            ProjectAlert(
              type: AlertType.lowBudgetRemaining,
              title: 'Low Budget Remaining',
              message:
                  'Only \$${NumberFormat('#,##0').format(budgetRemaining)} remaining (${(1 - budgetUsage) * 100 ~/ 1}%)',
              severity: AppSeverity.warning,
              icon: Icons.warning,
            ),
          );
        }
      } else if (project.status.isOpen) {
        alerts.add(
          ProjectAlert(
            type: AlertType.noBudget,
            title: 'No Budget Set',
            message: 'This ${singular.toLowerCase()} does not have an estimated budget',
            severity: AppSeverity.warning,
            icon: Icons.info,
          ),
        );
      }

      // Timeline alerts
      if (project.isOverdue()) {
        final daysOverdue = DateTime.now()
            .difference(project.targetCompletionDate!)
            .inDays;
        alerts.add(
          ProjectAlert(
            type: AlertType.overdue,
            title: '$singular Overdue',
            message:
                'Target completion date was $daysOverdue ${daysOverdue == 1 ? 'day' : 'days'} ago',
            severity: AppSeverity.error,
            icon: Icons.schedule,
          ),
        );
      } else if (project.targetCompletionDate != null &&
          project.startDate != null) {
        // Check if behind schedule
        final now = DateTime.now();
        final totalDuration = project.targetCompletionDate!
            .difference(project.startDate!)
            .inDays;
        final elapsed = now.difference(project.startDate!).inDays;
        final timelineProgress = totalDuration > 0
            ? elapsed / totalDuration
            : 0.0;

        // We'd need task completion data here to compare properly
        // For now, just alert if getting close to deadline
        if (timelineProgress > 0.8 && !project.status.isClosed) {
          final daysRemaining = project.targetCompletionDate!
              .difference(now)
              .inDays;
          alerts.add(
            ProjectAlert(
              type: AlertType.behindSchedule,
              title: 'Approaching Deadline',
              message:
                  'Only $daysRemaining ${daysRemaining == 1 ? 'day' : 'days'} until target completion date',
              severity: AppSeverity.warning,
              icon: Icons.access_time,
            ),
          );
        }
      }
    } catch (e) {
      // Silently handle errors - don't show alerts if we can't calculate them
      debugPrint('Error generating alerts: $e');
    }

    // Labor variance alerts
    try {
      final laborSummaries = await ServiceLocator.budgetTaskLinkService
          .getLaborSummaryForProject(project.id, project.workspaceId);

      // Also need budget item names for the alert messages
      final budgetItems = await ServiceLocator.budgetService
          .getBudgetItems(project.id, workspaceId: project.workspaceId)
          .first;
      final itemNames = {for (final item in budgetItems) item.id: item.name};

      for (final entry in laborSummaries.entries) {
        final summary = entry.value;
        if (summary.estimatedHours <= 0) continue;

        final utilization = summary.hoursUtilization;
        final itemName = itemNames[entry.key] ?? 'Unknown item';

        if (utilization > 100) {
          final overageHours = summary.hoursVariance;
          final overagePct = (utilization - 100).toStringAsFixed(0);
          alerts.add(
            ProjectAlert(
              type: AlertType.laborOverBudget,
              title: 'Labor Over Budget',
              message:
                  'Labor for \'$itemName\' exceeds estimate by ${overageHours.toStringAsFixed(1)}h ($overagePct% over)',
              severity: AppSeverity.error,
              icon: Icons.timer_off,
            ),
          );
        } else if (utilization > 80) {
          alerts.add(
            ProjectAlert(
              type: AlertType.laborNearBudget,
              title: 'Labor Nearing Budget',
              message:
                  'Labor for \'$itemName\' is at ${utilization.toStringAsFixed(0)}% of estimated hours',
              severity: AppSeverity.warning,
              icon: Icons.timer,
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('Error generating labor alerts: $e');
    }

    return alerts;
  }
}
