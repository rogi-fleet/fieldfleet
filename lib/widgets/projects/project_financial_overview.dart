import 'package:flutter/material.dart';
import '../../models/project_financial_summary.dart';
import '../../services/service_locator.dart';
import '../../theme/theme.dart';

/// Widget that displays comprehensive financial overview for a project
///
/// Shows 6 key metrics: Approved Price, Collected So Far, Remaining Balance,
/// Cost to Complete, Projected Profit, and Projected Margin.
class ProjectFinancialOverview extends StatelessWidget {
  final String projectId;
  final bool hasApprovedEstimate;

  const ProjectFinancialOverview({
    super.key,
    required this.projectId,
    this.hasApprovedEstimate = false,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.all(AppSpacing.base),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.base),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Financial Overview',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                Icon(
                  Icons.account_balance_wallet,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Financial data
            FutureBuilder<ProjectFinancialSummary>(
              future: ServiceLocator.projectService.getProjectFinancials(projectId),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return _buildLoadingState();
                }

                if (snapshot.hasError) {
                  return _buildErrorState(context, snapshot.error.toString());
                }

                if (!snapshot.hasData) {
                  return _buildEmptyState();
                }

                return _buildMetricsGrid(context, snapshot.data!);
              },
            ),
          ],
        ),
      ),
    );
  }

  /// Build loading skeleton
  Widget _buildLoadingState() {
    return SizedBox(
      width: double.infinity,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth > 768;
          return GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: isWide ? 3 : 2,
            mainAxisSpacing: 16,
            crossAxisSpacing: 16,
            childAspectRatio: 2.5,
            children: List.generate(
              6,
              (index) => Container(
                decoration: BoxDecoration(
                  color: AppColors.cardBorder,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  /// Build error state with retry button
  Widget _buildErrorState(BuildContext context, String error) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          children: [
            Icon(
              Icons.error_outline,
              size: 48,
              color: AppColors.error,
            ),
            const SizedBox(height: 16),
            Text(
              'Error loading financial data',
              style: TextStyle(
                fontSize: 16,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              error,
              style: TextStyle(
                fontSize: 12,
                color: AppColors.textTertiary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () {
                // Trigger rebuild
                (context as Element).markNeedsBuild();
              },
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  /// Build empty state
  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          children: [
            Icon(
              Icons.account_balance_wallet_outlined,
              size: 48,
              color: AppColors.textTertiary,
            ),
            const SizedBox(height: 16),
            Text(
              'No financial data available',
              style: TextStyle(
                fontSize: 16,
                color: AppColors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Build the metrics grid with all financial metrics
  Widget _buildMetricsGrid(BuildContext context, ProjectFinancialSummary summary) {
    return SizedBox(
      width: double.infinity,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth > 768;
          return Column(
            children: [
              GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: isWide ? 3 : 2,
                mainAxisSpacing: 16,
                crossAxisSpacing: 16,
                childAspectRatio: 2.5,
                children: [
                  _FinancialMetric(
                    label: hasApprovedEstimate ? 'Approved Price' : 'Estimated Price',
                    value: summary.formattedApprovedPrice,
                    icon: Icons.assignment_turned_in,
                    color: AppColors.info,
                  ),
                  _FinancialMetric(
                    label: 'Collected So Far',
                    value: summary.formattedCollectedSoFar,
                    icon: Icons.payments,
                    color: AppColors.success,
                  ),
                  _FinancialMetric(
                    label: 'Cost to Complete',
                    value: summary.formattedCostToComplete,
                    icon: Icons.construction,
                    color: AppColors.messageAccent,
                  ),
                  _FinancialMetric(
                    label: 'Remaining Balance',
                    value: summary.formattedRemainingBalance,
                    icon: Icons.account_balance,
                    color: summary.remainingBalance > 0 ? AppColors.warning : AppColors.textTertiary,
                  ),
                  _FinancialMetric(
                    label: 'Projected Profit',
                    value: summary.formattedProjectedProfit,
                    icon: summary.isProfitable ? Icons.check_circle : Icons.warning,
                    color: summary.isProfitable ? AppColors.success : AppColors.error,
                    showIndicator: true,
                  ),
                  _FinancialMetric(
                    label: 'Projected Margin',
                    value: summary.formattedProjectedMargin,
                    icon: Icons.trending_up,
                    color: _getMarginColor(summary),
                    showIndicator: true,
                  ),
                ],
              ),
              // Asset costs - display only if there are asset costs
              if (summary.totalAssetCosts > 0) ...[
                const SizedBox(height: 16),
                _FinancialMetric(
                  label: 'Equipment Costs',
                  value: summary.formattedTotalAssetCosts,
                  icon: Icons.inventory_2,
                  color: AppColors.financialAccent,
                  subtitle: '${summary.formattedAssetPurchaseCosts} + ${summary.formattedAssetMaintenanceCosts}',
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  /// Get color for margin based on health thresholds
  Color _getMarginColor(ProjectFinancialSummary summary) {
    if (summary.hasHealthyMargin) {
      return AppColors.success;
    } else if (summary.hasLowMargin) {
      return AppColors.warning;
    } else if (summary.hasCriticalMargin) {
      return AppColors.warning;
    } else {
      return AppColors.error;
    }
  }
}

/// Individual financial metric display
class _FinancialMetric extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final bool showIndicator;
  final String? subtitle;

  const _FinancialMetric({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    this.showIndicator = false,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(
          color: color.withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Label and icon
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w500,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ),
              Icon(
                icon,
                size: 18,
                color: color,
              ),
            ],
          ),
          const SizedBox(height: 2),

          // Value
          Text(
            value,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: color,
            ),
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
          
          // Optional subtitle
          if (subtitle != null) ...[
            const SizedBox(height: 2),
            Text(
              subtitle!,
              style: TextStyle(
                fontSize: 10,
                color: AppColors.textSecondary,
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ],
        ],
      ),
    );
  }
}
