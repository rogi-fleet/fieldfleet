import 'package:flutter/material.dart';
import '../../utils/user_facing_error.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../../models/project.dart';
import '../../services/service_locator.dart';
import '../../services/supabase/budget_service.dart' show BudgetSummary;
import '../../providers/auth_provider.dart';
import '../../providers/workspace_provider.dart';
import '../../theme/theme.dart';
import '../../utils/address_formatter.dart';
import '../../utils/project_terminology.dart';

class BudgetListScreen extends StatefulWidget {
  const BudgetListScreen({super.key});

  @override
  State<BudgetListScreen> createState() => _BudgetListScreenState();
}

class _BudgetListScreenState extends State<BudgetListScreen> {
  dynamic get _projectService => ServiceLocator.projectService;
  dynamic get _budgetService => ServiceLocator.budgetService;

  // Cache the projects stream and per-project budget-summary futures so that
  // rebuilds (provider notifications, realtime emits) reuse them instead of
  // recreating them. Recreating would reset the StreamBuilder / FutureBuilders
  // to their loading state and make the cards flicker.
  Stream<List<Project>>? _projectsStream;
  final Map<String, Future<BudgetSummary>> _summaryFutures = {};
  String? _cacheWorkspaceId;

  void _ensureCacheFor(String workspaceId) {
    if (_cacheWorkspaceId != workspaceId) {
      _cacheWorkspaceId = workspaceId;
      _projectsStream = _projectService.getProjects(workspaceId);
      _summaryFutures.clear();
    }
  }

  Future<BudgetSummary> _summaryFuture(String projectId, String workspaceId) {
    return _summaryFutures.putIfAbsent(projectId, () {
      final future = _budgetService.calculateBudgetSummary(
        projectId,
        workspaceId,
      );
      // Drop a failed future from the cache so a later rebuild retries instead
      // of showing the cached error (and its loading state) forever.
      future.then<void>(
        (_) {},
        onError: (Object _) {
          _summaryFutures.remove(projectId);
        },
      );
      return future;
    });
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = context.watch<AuthProvider>();
    final workspaceId = authProvider.appUser?.currentWorkspaceId;

    if (workspaceId == null) {
      return const Scaffold(
        body: Center(child: Text('Error: No workspace found')),
      );
    }

    _ensureCacheFor(workspaceId);

    return Scaffold(
      body: StreamBuilder<List<Project>>(
        stream: _projectsStream,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: SelectableText(
                UserFacingError.uiMessage(snapshot.error, action: 'load data'),
              ),
            );
          }

          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final projects = snapshot.data ?? [];

          if (projects.isEmpty) {
            return _buildEmptyState();
          }

          return ListView.builder(
            padding: const EdgeInsets.all(AppSpacing.base),
            itemCount: projects.length,
            itemBuilder: (context, index) {
              return _buildProjectCard(projects[index], workspaceId);
            },
          );
        },
      ),
    );
  }

  Widget _buildEmptyState() {
    final projectTerminology = context.watch<WorkspaceProvider>().projectTerminology;
    final singular = singularProjectTerminology(projectTerminology);
    final canCreateProjects = context.watch<AuthProvider>().canCreateProjects;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.account_balance_wallet_outlined,
            size: 64,
            color: AppColors.textTertiary,
          ),
          const SizedBox(height: 16),
          Text(
            'No ${projectTerminology.toLowerCase()} yet',
            style: TextStyle(fontSize: 18, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 8),
          Text(
            canCreateProjects
                ? 'Create a ${singular.toLowerCase()} to start tracking budgets'
                : 'Ask an admin to create a ${singular.toLowerCase()} to start tracking budgets',
            style: TextStyle(fontSize: 14, color: AppColors.textTertiary),
          ),
          if (canCreateProjects) ...[
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () {
                context.go('/projects/new');
              },
              icon: const Icon(Icons.add),
              label: Text('Create $singular'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildProjectCard(Project project, String workspaceId) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: InkWell(
        onTap: () {
          context.go('/projects/${project.id}/budget');
        },
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.base),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          project.name,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          AddressFormatter.condense(project.address),
                          style: TextStyle(
                            fontSize: 14,
                            color: AppColors.textSecondary,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right, color: AppColors.textTertiary),
                ],
              ),
              const SizedBox(height: 16),
              FutureBuilder<BudgetSummary>(
                future: _summaryFuture(project.id, workspaceId),
                builder: (context, summarySnapshot) {
                  if (summarySnapshot.hasError) {
                    return SizedBox(
                      height: 40,
                      child: Row(
                        children: [
                          Icon(
                            Icons.error_outline,
                            size: 16,
                            color: AppColors.error,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Couldn’t load summary',
                            style: TextStyle(
                              fontSize: 14,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    );
                  }
                  if (!summarySnapshot.hasData) {
                    return const SizedBox(
                      height: 40,
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }

                  final summary = summarySnapshot.data!;

                  if (summary.totalItems == 0) {
                    return Container(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceAlt,
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.info_outline,
                            size: 16,
                            color: AppColors.textSecondary,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'No budget items',
                            style: TextStyle(
                              fontSize: 14,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    );
                  }

                  return Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: _buildSummaryItem(
                              project.status.isEstimateApproved
                                  ? 'Approved'
                                  : 'Estimated',
                              '\$${summary.totalApprovedPrice.toStringAsFixed(0)}',
                              AppColors.info,
                            ),
                          ),
                          Expanded(
                            child: _buildSummaryItem(
                              'Projected',
                              '\$${summary.totalProjectedCost.toStringAsFixed(0)}',
                              AppColors.warning,
                            ),
                          ),
                          Expanded(
                            child: _buildSummaryItem(
                              'Actual',
                              '\$${summary.totalActualCost.toStringAsFixed(0)}',
                              AppColors.textPrimary,
                            ),
                          ),
                          Expanded(
                            child: _buildSummaryItem(
                              'Profit',
                              '\$${summary.overallProfit.toStringAsFixed(0)}',
                              summary.overallProfit >= 0
                                  ? AppColors.success
                                  : AppColors.error,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: _buildSummaryItem(
                              'Margin',
                              '${summary.overallMargin.toStringAsFixed(1)}%',
                              summary.overallMargin >= 0
                                  ? AppColors.success
                                  : AppColors.error,
                            ),
                          ),
                          Expanded(
                            child: _buildSummaryItem(
                              'Progress',
                              '${summary.completionPercentage.toStringAsFixed(0)}%',
                              AppColors.financialAccent,
                            ),
                          ),
                          Expanded(
                            child: _buildSummaryItem(
                              'Items',
                              '${summary.completedItems}/${summary.totalItems}',
                              Colors.indigo,
                            ),
                          ),
                          const Expanded(child: SizedBox()), // Spacer
                        ],
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSummaryItem(String label, String value, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }
}
