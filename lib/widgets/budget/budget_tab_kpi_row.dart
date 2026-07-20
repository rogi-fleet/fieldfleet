import 'package:flutter/material.dart';
import '../../theme/theme.dart';
import '../../utils/budget_tab_metrics.dart';

/// Renders a row of KPI cards for the active budget view mode.
///
/// Sits between the toolbar and the table/card view, providing contextual
/// summary metrics for whichever tab is selected.
class BudgetTabKpiRow extends StatelessWidget {
  final List<TabKpi> kpis;

  /// Optional action button shown at the trailing end of the KPI row.
  final String? actionLabel;
  final IconData? actionIcon;
  final VoidCallback? onAction;

  const BudgetTabKpiRow({
    super.key,
    required this.kpis,
    this.actionLabel,
    this.actionIcon,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    if (kpis.isEmpty) return const SizedBox.shrink();

    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.base, vertical: AppSpacing.sm),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < AppBreakpoints.mobile) {
            return _buildWrapLayout(constraints.maxWidth);
          }
          return _buildRowLayout();
        },
      ),
    );
  }

  Widget _buildRowLayout() {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (int i = 0; i < kpis.length; i++) ...[
            if (i > 0) const SizedBox(width: 10),
            Expanded(child: _KpiCard(kpi: kpis[i])),
          ],
          if (onAction != null) ...[
            const SizedBox(width: 10),
            Center(
              child: _ActionButton(
                label: actionLabel ?? 'Create',
                icon: actionIcon ?? Icons.add,
                onPressed: onAction!,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildWrapLayout(double availableWidth) {
    final cardWidth = (availableWidth - 10) / 2; // 2 columns, 10px gap
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final kpi in kpis)
              SizedBox(
                width: cardWidth,
                child: _KpiCard(kpi: kpi),
              ),
          ],
        ),
        if (onAction != null) ...[
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: _ActionButton(
              label: actionLabel ?? 'Create',
              icon: actionIcon ?? Icons.add,
              onPressed: onAction!,
            ),
          ),
        ],
      ],
    );
  }
}

class _ActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onPressed;

  const _ActionButton({
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 16),
      label: Text(label, style: const TextStyle(fontSize: 12)),
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }
}

class _KpiCard extends StatelessWidget {
  final TabKpi kpi;

  const _KpiCard({required this.kpi});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final valueColor = _resolveColor(kpi.color);

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            kpi.label,
            style: const TextStyle(
              fontSize: 11,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            kpi.value,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w500,
              color: valueColor,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (kpi.subtitle != null) ...[
            const SizedBox(height: 3),
            Text(
              kpi.subtitle!,
              style: const TextStyle(
                fontSize: 11,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ],
      ),
    );
  }

  static Color _resolveColor(String color) {
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
