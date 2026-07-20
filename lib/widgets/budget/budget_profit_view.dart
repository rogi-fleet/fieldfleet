import 'package:flutter/material.dart';
import '../../theme/theme.dart';
import '../../utils/budget_tab_metrics.dart';
import 'budget_margin_gauge.dart';

/// Specialized P&L view shown above the table when the Profit tab is active.
///
/// Two-column layout on desktop (revenue/cost left, gauge/targets right).
/// Stacks vertically on narrow screens.
class BudgetProfitView extends StatelessWidget {
  final ProfitBreakdown breakdown;
  final String Function(double) formatCurrency;

  const BudgetProfitView({
    super.key,
    required this.breakdown,
    required this.formatCurrency,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.base, vertical: AppSpacing.sm),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 720) {
            return Column(
              children: [
                _buildRevenueCard(context),
                const SizedBox(height: 12),
                _buildCostCard(context),
                const SizedBox(height: 12),
                _buildMarginGaugeCard(context),
                const SizedBox(height: 12),
                _buildMarginTargetsCard(context),
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 3,
                child: Column(
                  children: [
                    _buildRevenueCard(context),
                    const SizedBox(height: 12),
                    _buildCostCard(context),
                    const SizedBox(height: 12),
                    _buildMarginTargetsCard(context),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: _buildMarginGaugeCard(context),
              ),
            ],
          );
        },
      ),
    );
  }

  // ── Cards ────────────────────────────────────────────────────────────

  Widget _buildRevenueCard(BuildContext context) {
    return _Card(
      title: 'Revenue breakdown',
      child: _BreakdownList(
        lines: breakdown.revenueLines,
        formatCurrency: formatCurrency,
      ),
    );
  }

  Widget _buildCostCard(BuildContext context) {
    return _Card(
      title: 'Cost breakdown',
      child: _BreakdownList(
        lines: breakdown.costLines,
        formatCurrency: formatCurrency,
      ),
    );
  }

  Widget _buildMarginGaugeCard(BuildContext context) {
    return _Card(
      title: 'Margin gauge',
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
        child: Center(
          child: BudgetMarginGauge(
            percentage: breakdown.projectedMargin,
            targetPercentage: breakdown.estimatedMargin,
          ),
        ),
      ),
    );
  }

  Widget _buildMarginTargetsCard(BuildContext context) {
    return _Card(
      title: 'Margin vs. targets',
      child: Column(
        children: [
          _TargetRow(
            label: 'Estimated margin',
            value: '${breakdown.estimatedMargin.toStringAsFixed(1)}%',
          ),
          _TargetRow(
            label: 'Current actual',
            value: '${breakdown.actualMargin.toStringAsFixed(1)}%',
            color: AppColors.success,
            isBold: true,
          ),
          _TargetRow(
            label: 'Upgrade contribution',
            value:
                '${breakdown.upgradeMarginContribution >= 0 ? '+' : ''}${breakdown.upgradeMarginContribution.toStringAsFixed(1)}%',
            color: breakdown.upgradeMarginContribution >= 0
                ? AppColors.success
                : AppColors.error,
          ),
          _TargetRow(
            label: 'Cost overrun impact',
            value:
                '${breakdown.overrunMarginImpact >= 0 ? '+' : ''}${breakdown.overrunMarginImpact.toStringAsFixed(1)}%',
            color: breakdown.overrunMarginImpact >= 0
                ? AppColors.success
                : AppColors.error,
            showBorder: false,
          ),
        ],
      ),
    );
  }
}

// ── Shared building blocks ───────────────────────────────────────────────

class _Card extends StatelessWidget {
  final String title;
  final Widget child;

  const _Card({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: AppSpacing.sm),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
              border: Border(
                bottom: BorderSide(
                  color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                ),
              ),
            ),
            child: Text(
              title.toUpperCase(),
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: AppColors.textSecondary,
                letterSpacing: 0.04 * 11,
              ),
            ),
          ),
          // Body
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: AppSpacing.xs),
            child: child,
          ),
        ],
      ),
    );
  }
}

class _BreakdownList extends StatelessWidget {
  final List<BreakdownLine> lines;
  final String Function(double) formatCurrency;

  const _BreakdownList({
    required this.lines,
    required this.formatCurrency,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    // Hide zero-amount lines that aren't totals or footnotes
    final visibleLines = lines
        .where((l) => l.isTotal || l.isFootnote || l.amount != 0)
        .toList();

    return Column(
      children: [
        for (final line in visibleLines)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 7),
            decoration: line.isTotal
                ? BoxDecoration(
                    border: Border(
                      top: BorderSide(
                        color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                      ),
                    ),
                  )
                : null,
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    line.label,
                    style: TextStyle(
                      fontSize: line.isFootnote ? 11 : 12,
                      fontWeight: line.isTotal ? FontWeight.w500 : null,
                      color: line.isFootnote
                          ? _resolveColor(line.color) ?? AppColors.textSecondary
                          : line.isTotal
                              ? null
                              : AppColors.textSecondary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  line.amount >= 0
                      ? formatCurrency(line.amount)
                      : '-${formatCurrency(line.amount.abs())}',
                  style: TextStyle(
                    fontSize: line.isFootnote ? 11 : (line.isTotal ? 13 : 12),
                    fontWeight: line.isTotal ? FontWeight.w500 : null,
                    color: _resolveColor(line.color) ??
                        (line.isTotal ? AppColors.primary : null),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  static Color? _resolveColor(String? color) {
    switch (color) {
      case 'success':
        return AppColors.success;
      case 'warning':
        return AppColors.warningDark;
      case 'error':
        return AppColors.error;
      case 'muted':
        return AppColors.textSecondary;
      default:
        return null;
    }
  }
}

class _TargetRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? color;
  final bool isBold;
  final bool showBorder;

  const _TargetRow({
    required this.label,
    required this.value,
    this.color,
    this.isBold = false,
    this.showBorder = true,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 7),
      decoration: showBorder
          ? BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                ),
              ),
            )
          : null,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 12,
              fontWeight: isBold ? FontWeight.w500 : null,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
