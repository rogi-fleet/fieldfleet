import 'package:flutter/material.dart';
import '../models/cost_item.dart';
import '../models/project.dart';
import '../theme/theme.dart';

class CostSummaryWidget extends StatelessWidget {
  final Project project;
  final List<CostItem> costItems;

  const CostSummaryWidget({
    super.key,
    required this.project,
    required this.costItems,
  });

  Map<String, double> _calculateTotals() {
    double materialCosts = 0.0;
    double laborCosts = 0.0;

    for (final item in costItems) {
      if (item.type == CostItemType.material) {
        materialCosts += item.totalCost;
      } else if (item.type == CostItemType.labor) {
        laborCosts += item.totalCost;
      }
    }

    final materialMarkup = materialCosts * (project.materialMarkupPercent / 100);
    final laborMarkup = laborCosts * (project.laborMarkupPercent / 100);
    final totalCost = materialCosts + laborCosts;
    final totalWithMarkup = materialCosts + laborCosts + materialMarkup + laborMarkup;

    double? budgetVariance;
    double? budgetVariancePercent;
    if (project.estimatedBudget != null && project.estimatedBudget! > 0) {
      budgetVariance = project.estimatedBudget! - totalWithMarkup;
      budgetVariancePercent = (budgetVariance / project.estimatedBudget!) * 100;
    }

    return {
      'materialCosts': materialCosts,
      'laborCosts': laborCosts,
      'materialMarkup': materialMarkup,
      'laborMarkup': laborMarkup,
      'totalCost': totalCost,
      'totalWithMarkup': totalWithMarkup,
      'budgetVariance': budgetVariance ?? 0,
      'budgetVariancePercent': budgetVariancePercent ?? 0,
    };
  }

  Color _getBudgetStatusColor(double variance, double? budget) {
    if (budget == null || budget == 0) return AppColors.textTertiary;

    final variancePercent = (variance / budget) * 100;
    if (variancePercent > 5) return AppColors.success;
    if (variancePercent < -5) return AppColors.error;
    return AppColors.warning;
  }

  @override
  Widget build(BuildContext context) {
    final totals = _calculateTotals();
    final materialCosts = totals['materialCosts']!;
    final laborCosts = totals['laborCosts']!;
    final materialMarkup = totals['materialMarkup']!;
    final laborMarkup = totals['laborMarkup']!;
    final totalWithMarkup = totals['totalWithMarkup']!;
    final budgetVariance = totals['budgetVariance']!;

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.base),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Cost Summary',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const Divider(height: 24),

            // Material costs
            _buildCostRow(
              'Material Costs',
              materialCosts,
              icon: Icons.construction,
              color: AppColors.info,
            ),
            _buildCostRow(
              'Material Markup (${project.materialMarkupPercent.toStringAsFixed(0)}%)',
              materialMarkup,
              indent: true,
              color: AppColors.info,
            ),
            const SizedBox(height: 8),

            // Costs
            _buildCostRow(
              'Costs',
              laborCosts,
              icon: Icons.person,
              color: AppColors.success,
            ),
            _buildCostRow(
              'Labor Markup (${project.laborMarkupPercent.toStringAsFixed(0)}%)',
              laborMarkup,
              indent: true,
              color: AppColors.success,
            ),
            const Divider(height: 24),

            // Total
            _buildCostRow(
              'Total with Markup',
              totalWithMarkup,
              icon: Icons.payments,
              color: AppColors.messageAccent,
              bold: true,
              largeFontSize: true,
            ),

            // Budget variance
            if (project.estimatedBudget != null && project.estimatedBudget! > 0) ...[
              const SizedBox(height: 16),
              _buildBudgetVariance(
                project.estimatedBudget!,
                totalWithMarkup,
                budgetVariance,
              ),
            ],

            // Cost items count
            const SizedBox(height: 16),
            Text(
              '${costItems.length} cost items',
              style: TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCostRow(
    String label,
    double amount, {
    IconData? icon,
    Color? color,
    bool indent = false,
    bool bold = false,
    bool largeFontSize = false,
  }) {
    return Padding(
      padding: EdgeInsets.only(
        left: indent ? 24.0 : 0.0,
        bottom: 4.0,
      ),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: largeFontSize ? 18 : 14,
                fontWeight: bold ? FontWeight.bold : FontWeight.normal,
                color: color,
              ),
            ),
          ),
          Text(
            '\$${amount.toStringAsFixed(2)}',
            style: TextStyle(
              fontSize: largeFontSize ? 18 : 14,
              fontWeight: bold ? FontWeight.bold : FontWeight.normal,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBudgetVariance(double budget, double actual, double variance) {
    final isOverBudget = variance < 0;
    final variancePercent = (variance / budget) * 100;
    final statusColor = _getBudgetStatusColor(variance, budget);

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: statusColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: statusColor, width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isOverBudget ? Icons.trending_up : Icons.trending_down,
                color: statusColor,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                isOverBudget ? 'Over Budget' : 'Under Budget',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: statusColor,
                  fontSize: 16,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Budget: \$${budget.toStringAsFixed(2)}',
                style: const TextStyle(fontSize: 12),
              ),
              Text(
                'Actual: \$${actual.toStringAsFixed(2)}',
                style: const TextStyle(fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${isOverBudget ? "+" : ""}\$${variance.abs().toStringAsFixed(2)} (${variancePercent.abs().toStringAsFixed(1)}%)',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: statusColor,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }
}
