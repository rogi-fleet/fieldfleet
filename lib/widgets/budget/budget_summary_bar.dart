import 'package:flutter/material.dart';
import '../../theme/theme.dart';
import '../../utils/budget_tab_metrics.dart';

/// Consolidated budget summary panel combining the high-level project metrics
/// and the per-view KPI metrics into one cohesive container.
///
/// Top section: 5 project-level metrics (Approved, Estimated cost, etc.)
/// Bottom section: view-specific KPIs (e.g. Invoicing → contract / invoiced / remaining)
class BudgetSummaryPanel extends StatelessWidget {
  final BudgetSummaryMetrics metrics;
  final String Function(double) formatCurrency;
  final bool hasApprovedEstimate;

  /// View-mode-specific KPIs. When empty the bottom section is hidden.
  final List<TabKpi> viewKpis;

  const BudgetSummaryPanel({
    super.key,
    required this.metrics,
    required this.formatCurrency,
    this.hasApprovedEstimate = false,
    this.viewKpis = const [],
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final borderColor = colorScheme.outlineVariant.withValues(alpha: 0.5);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: AppSpacing.base, vertical: AppSpacing.sm),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(AppRadius.r12),
        border: Border.all(color: borderColor),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final w = constraints.maxWidth;
          final summaryItems = _buildSummaryItems();

          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── Top: project-level summary ──
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.md),
                child: _buildMetricRow(summaryItems, w),
              ),

              // ── Bottom: view-specific KPIs ──
              if (viewKpis.isNotEmpty) ...[
                Divider(
                  height: 1,
                  thickness: 0.5,
                  color: borderColor,
                ),
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.md),
                  child: _buildMetricRow(
                    viewKpis.map(_kpiToMetric).toList(),
                    w,
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  // ── Data ──────────────────────────────────────────────────────────────

  List<_MetricData> _buildSummaryItems() {
    final hasRevisions = metrics.revisedContract != metrics.approved;

    return [
      _MetricData(
        label: hasRevisions
            ? (hasApprovedEstimate ? 'Original approved' : 'Original estimate')
            : (hasApprovedEstimate ? 'Approved' : 'Estimated'),
        value: formatCurrency(metrics.approved),
        color: AppColors.primary,
      ),
      _MetricData(
        label: 'Estimated cost',
        value: formatCurrency(metrics.estimatedCost),
        color: AppColors.textSecondary,
      ),
      _MetricData(
        label: 'Actual cost',
        value: formatCurrency(metrics.actualCost),
        color: AppColors.warningDark,
      ),
      if (hasRevisions)
        _MetricData(
          label: 'Revised contract',
          value: formatCurrency(metrics.revisedContract),
          color: AppColors.primary,
        ),
      _MetricData(
        label: 'Profit (projected)',
        value:
            '${formatCurrency(metrics.projectedProfit)} (${metrics.projectedMargin.toStringAsFixed(1)}%)',
        color:
            metrics.projectedProfit >= 0 ? AppColors.success : AppColors.error,
      ),
    ];
  }

  static _MetricData _kpiToMetric(TabKpi kpi) {
    return _MetricData(
      label: kpi.label,
      value: kpi.value,
      color: _resolveKpiColor(kpi.color),
      subtitle: kpi.subtitle,
      isSecondary: true,
    );
  }

  // ── Layout ────────────────────────────────────────────────────────────

  Widget _buildMetricRow(List<_MetricData> items, double width) {
    if (width < 400) return _buildNarrowLayout(items);
    if (width < 720) return _buildCompactLayout(items);
    return _buildWideLayout(items);
  }

  Widget _buildWideLayout(List<_MetricData> items) {
    return Row(
      children: [
        for (int i = 0; i < items.length; i++) ...[
          if (i > 0) _buildDivider(),
          Expanded(child: _buildMetric(items[i])),
        ],
      ],
    );
  }

  Widget _buildCompactLayout(List<_MetricData> items) {
    if (items.length <= 3) return _buildWideLayout(items);

    final splitAt = (items.length / 2).ceil();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            for (int i = 0; i < splitAt; i++) ...[
              if (i > 0) _buildDivider(),
              Expanded(child: _buildMetric(items[i])),
            ],
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            for (int i = splitAt; i < items.length; i++) ...[
              if (i > splitAt) _buildDivider(),
              Expanded(child: _buildMetric(items[i])),
            ],
            // Pad remaining space so items don't stretch too wide
            if (items.length - splitAt < splitAt) const Spacer(),
          ],
        ),
      ],
    );
  }

  Widget _buildNarrowLayout(List<_MetricData> items) {
    final rows = <Widget>[];
    for (int i = 0; i < items.length; i += 2) {
      if (i + 1 < items.length) {
        rows.add(Row(
          children: [
            Expanded(child: _buildMetric(items[i])),
            _buildDivider(),
            Expanded(child: _buildMetric(items[i + 1])),
          ],
        ));
      } else {
        rows.add(_buildMetric(items[i]));
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (int i = 0; i < rows.length; i++) ...[
          if (i > 0) const SizedBox(height: 10),
          rows[i],
        ],
      ],
    );
  }

  // ── Shared widgets ────────────────────────────────────────────────────

  Widget _buildDivider() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      child: SizedBox(
        height: 36,
        child: VerticalDivider(
          width: 1,
          thickness: 0.5,
          color: AppColors.cardBorder,
        ),
      ),
    );
  }

  Widget _buildMetric(_MetricData data) {
    final valueFontSize = data.isSecondary ? 14.0 : 15.0;
    final valueWeight = data.isSecondary ? FontWeight.w500 : FontWeight.w600;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          data.label,
          style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 2),
        Text(
          data.value,
          style: TextStyle(
            fontSize: valueFontSize,
            fontWeight: valueWeight,
            color: data.color,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        if (data.subtitle != null) ...[
          const SizedBox(height: 1),
          Text(
            data.subtitle!,
            style:
                const TextStyle(fontSize: 10, color: AppColors.textSecondary),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ],
    );
  }

  static Color _resolveKpiColor(String color) {
    switch (color) {
      case 'primary':
        return AppColors.primary;
      case 'success':
        return AppColors.success;
      case 'warning':
        return AppColors.warningDark;
      case 'error':
        return AppColors.error;
      case 'muted':
        return AppColors.textSecondary;
      default:
        return AppColors.textPrimary;
    }
  }
}

class _MetricData {
  final String label;
  final String value;
  final Color color;
  final String? subtitle;
  final bool isSecondary;

  const _MetricData({
    required this.label,
    required this.value,
    required this.color,
    this.subtitle,
    this.isSecondary = false,
  });
}
