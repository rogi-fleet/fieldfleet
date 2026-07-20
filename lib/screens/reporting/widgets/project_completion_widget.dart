import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:provider/provider.dart';
import '../../../providers/workspace_provider.dart';
import '../../../services/reporting_service.dart';
import '../../../theme/theme.dart';
import '../../../utils/project_terminology.dart';

class ProjectCompletionWidget extends StatelessWidget {
  final List<ProjectCompletionReport> reports;

  const ProjectCompletionWidget({
    super.key,
    required this.reports,
  });

  @override
  Widget build(BuildContext context) {
    if (reports.isEmpty) {
      return _buildEmptyState(context);
    }

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.base),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Overall Stats
          _buildOverallStats(),

          const SizedBox(height: 16),

          // Pie Chart
          SizedBox(
            height: 250,
            child: _buildPieChart(context),
          ),

          const SizedBox(height: 16),

          // Project List
          _buildProjectList(context),
        ],
      ),
    );
  }

  Widget _buildOverallStats() {
    final totalTasks = reports.fold<int>(0, (sum, r) => sum + r.totalTasks);
    final completedTasks = reports.fold<int>(0, (sum, r) => sum + r.completedTasks);
    final avgCompletion = reports.isNotEmpty
        ? reports.fold<double>(0.0, (sum, r) => sum + r.completionPercentage) / reports.length
        : 0.0;

    return Row(
      children: [
        Expanded(
          child: Card(
            color: AppColors.infoLight,
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.base),
              child: Column(
                children: [
                  Icon(Icons.check_circle, color: AppColors.infoDark, size: 32),
                  const SizedBox(height: 8),
                  Text(
                    '$completedTasks/$totalTasks',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: AppColors.infoDark),
                  ),
                  Text('Tasks Completed', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Card(
            color: AppColors.successLight,
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.base),
              child: Column(
                children: [
                  Icon(Icons.trending_up, color: AppColors.successDark, size: 32),
                  const SizedBox(height: 8),
                  Text(
                    '${avgCompletion.toStringAsFixed(1)}%',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: AppColors.successDark),
                  ),
                  Text('Avg Completion', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPieChart(BuildContext context) {
    final chrome = ChromeColors.of(context);
    final colors = [
      AppColors.success,
      AppColors.info,
      AppColors.warning,
      AppColors.messageAccent,
      AppColors.error,
      AppColors.financialAccent,
      Colors.pink,
      Colors.indigo,
    ];

    return Row(
      children: [
        Expanded(
          flex: 2,
          child: PieChart(
            PieChartData(
              sections: reports.asMap().entries.map((entry) {
                final index = entry.key;
                final report = entry.value;
                return PieChartSectionData(
                  value: report.completionPercentage,
                  title: '${report.completionPercentage.toStringAsFixed(0)}%',
                  color: colors[index % colors.length],
                  radius: 100,
                  titleStyle: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                );
              }).toList(),
              sectionsSpace: 2,
              centerSpaceRadius: 40,
            ),
          ),
        ),
        const SizedBox(width: 24),
        Expanded(
          flex: 1,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: reports.asMap().entries.map((entry) {
              final index = entry.key;
              final report = entry.value;
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: colors[index % colors.length],
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        report.projectName,
                        style: TextStyle(fontSize: 11, color: chrome.scaffoldTextSecondary),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildProjectList(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.base),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${singularProjectTerminology(context.watch<WorkspaceProvider>().projectTerminology)} Details',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: reports.length,
              separatorBuilder: (context, index) => const Divider(),
              itemBuilder: (context, index) {
                final report = reports[index];
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(report.projectName),
                  subtitle: LinearProgressIndicator(
                    value: report.completionPercentage / 100,
                    backgroundColor: AppColors.cardBorder,
                    valueColor: AlwaysStoppedAnimation(
                      report.completionPercentage >= 75
                          ? AppColors.success
                          : report.completionPercentage >= 50
                              ? AppColors.warning
                              : AppColors.error,
                    ),
                  ),
                  trailing: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '${report.completionPercentage.toStringAsFixed(0)}%',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      Text(
                        '${report.completedTasks}/${report.totalTasks} tasks',
                        style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final chrome = ChromeColors.of(context);
    return SizedBox(
      height: 300,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.check_circle_outline, size: 64, color: chrome.scaffoldTextSecondary),
            const SizedBox(height: 16),
            Text('No completion data available', style: TextStyle(fontSize: 18, color: chrome.scaffoldText)),
            const SizedBox(height: 8),
            Text('Create ${context.read<WorkspaceProvider>().projectTerminology.toLowerCase()} and tasks to see completion reports', style: TextStyle(fontSize: 14, color: chrome.scaffoldTextSecondary)),
          ],
        ),
      ),
    );
  }
}
