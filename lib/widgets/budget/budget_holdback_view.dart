import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../theme/theme.dart';
import '../../utils/budget_tab_metrics.dart';

/// Specialized holdback view shown above the table when Holdback tab is active.
///
/// Shows: 3 big stat cards, progress bar, info cards, holdback schedule table.
class BudgetHoldbackView extends StatelessWidget {
  final HoldbackBreakdown breakdown;
  final String Function(double) formatCurrency;
  final String? projectId;

  const BudgetHoldbackView({
    super.key,
    required this.breakdown,
    required this.formatCurrency,
    this.projectId,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.base, vertical: AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (projectId != null) _buildActionBar(context),
          _buildTopStats(context),
          const SizedBox(height: 12),
          _buildProgressCard(context),
          const SizedBox(height: 12),
          _buildInfoCards(context),
          if (breakdown.schedule.isNotEmpty)
            LayoutBuilder(
              builder: (context, constraints) {
                // Schedule table needs ~500px to render legibly
                if (constraints.maxWidth < 500) {
                  return const SizedBox.shrink();
                }
                return Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: _buildScheduleTable(context),
                );
              },
            ),
        ],
      ),
    );
  }

  // ── Action bar ───────────────────────────────────────────────────────

  Widget _buildActionBar(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        alignment: WrapAlignment.end,
        children: [
          OutlinedButton.icon(
            onPressed: () =>
                context.go('/projects/$projectId/holdback-releases'),
            icon: const Icon(Icons.list_alt, size: 18),
            label: const Text('View Releases'),
          ),
          FilledButton.icon(
            onPressed: () =>
                context.go('/projects/$projectId/holdback-releases/new'),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('New Release'),
          ),
        ],
      ),
    );
  }

  // ── Top stat cards ───────────────────────────────────────────────────

  Widget _buildTopStats(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 500) {
          return Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: _StatCard(
                      label: 'Invoiced with retainage',
                      value: formatCurrency(breakdown.totalInvoiced),
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _StatCard(
                      label:
                          'Holdback (${breakdown.holdbackRate.toStringAsFixed(0)}%)',
                      value: formatCurrency(breakdown.holdbackWithheld),
                      color: AppColors.warningDark,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              _StatCard(
                label: 'Net cash received',
                value: formatCurrency(breakdown.netCash),
                color: AppColors.success,
              ),
            ],
          );
        }
        return Row(
          children: [
            Expanded(
              child: _StatCard(
                label: 'Invoiced with retainage',
                value: formatCurrency(breakdown.totalInvoiced),
                color: AppColors.primary,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _StatCard(
                label:
                    'Holdback withheld (${breakdown.holdbackRate.toStringAsFixed(0)}%)',
                value: formatCurrency(breakdown.holdbackWithheld),
                color: AppColors.warningDark,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _StatCard(
                label: 'Net cash received',
                value: formatCurrency(breakdown.netCash),
                color: AppColors.success,
              ),
            ),
          ],
        );
      },
    );
  }

  // ── Progress bar card ────────────────────────────────────────────────

  Widget _buildProgressCard(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final progress = breakdown.holdbackProgress.clamp(0.0, 1.0);

    return Container(
      padding: const EdgeInsets.all(14),
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
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            spacing: 8,
            children: [
              const Text(
                'Holdback retention progress',
                style: TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
              Text(
                '${formatCurrency(breakdown.holdbackWithheld)} held of ${formatCurrency(breakdown.totalInvoiced)} invoiced',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.xl),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 10,
              backgroundColor:
                  colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
              valueColor:
                  const AlwaysStoppedAnimation<Color>(AppColors.warningDark),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                '0%',
                style: TextStyle(
                  fontSize: 11,
                  color: AppColors.textSecondary,
                ),
              ),
              Text(
                '${breakdown.holdbackRate.toStringAsFixed(0)}% rate in effect',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: AppColors.warningDark,
                ),
              ),
              const Text(
                '100%',
                style: TextStyle(
                  fontSize: 11,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Info cards row ───────────────────────────────────────────────────

  Widget _buildInfoCards(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final cards = [
          _InfoCard(
            label: 'Holdback rate',
            value: '${breakdown.holdbackRate.toStringAsFixed(0)}%',
            subtitle: 'per contract terms',
          ),
          _InfoCard(
            label: 'Released to date',
            value: formatCurrency(breakdown.releasedAmount),
            valueColor: AppColors.success,
            subtitle: breakdown.releasedCount > 0
                ? '${breakdown.releasedCount} item${breakdown.releasedCount == 1 ? '' : 's'} released'
                : 'pending completion',
          ),
          const _InfoCard(
            label: 'Release condition',
            value: 'Substantial completion',
            subtitle: 'per contract terms',
          ),
        ];

        if (constraints.maxWidth < 500) {
          return Column(
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: cards[0]),
                  const SizedBox(width: 10),
                  Expanded(child: cards[1]),
                ],
              ),
              const SizedBox(height: 10),
              cards[2],
            ],
          );
        }
        return Row(
          children: [
            for (int i = 0; i < cards.length; i++) ...[
              if (i > 0) const SizedBox(width: 10),
              Expanded(child: cards[i]),
            ],
          ],
        );
      },
    );
  }

  // ── Schedule table ───────────────────────────────────────────────────

  Widget _buildScheduleTable(BuildContext context) {
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
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: AppSpacing.sm),
            decoration: BoxDecoration(
              color:
                  colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
              border: Border(
                bottom: BorderSide(
                  color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                ),
              ),
            ),
            child: Text(
              'HOLDBACK SCHEDULE',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: AppColors.textSecondary,
                letterSpacing: 0.04 * 11,
              ),
            ),
          ),
          // Table header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: AppSpacing.sm),
            decoration: BoxDecoration(
              color:
                  colorScheme.surfaceContainerHighest.withValues(alpha: 0.15),
              border: Border(
                bottom: BorderSide(
                  color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                ),
              ),
            ),
            child: const Row(
              children: [
                Expanded(
                  flex: 3,
                  child: Text('Item', style: _headerStyle),
                ),
                Expanded(
                  flex: 2,
                  child: Text('Approved', style: _headerStyle),
                ),
                Expanded(child: Text('Holdback %', style: _headerStyle)),
                Expanded(
                  flex: 2,
                  child: Text('Holdback amt', style: _headerStyle),
                ),
                Expanded(child: Text('Status', style: _headerStyle)),
              ],
            ),
          ),
          // Rows
          for (final entry in breakdown.schedule)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: colorScheme.outlineVariant.withValues(alpha: 0.3),
                  ),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: Text(
                      entry.name,
                      style: const TextStyle(fontSize: 12),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text(
                      formatCurrency(entry.approved),
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      '${entry.holdbackPercent.toStringAsFixed(0)}%',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.warningDark,
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text(
                      formatCurrency(entry.holdbackAmount),
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.warningDark,
                      ),
                    ),
                  ),
                  Expanded(
                    child: _StatusPill(released: entry.released),
                  ),
                ],
              ),
            ),
          // Totals row
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            decoration: BoxDecoration(
              color:
                  colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
              border: Border(
                top: BorderSide(
                  color: colorScheme.outlineVariant,
                  width: 1.5,
                ),
              ),
            ),
            child: Row(
              children: [
                const Expanded(
                  flex: 3,
                  child: Text(
                    'Total held',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                Expanded(flex: 2, child: Container()),
                Expanded(child: Container()),
                Expanded(
                  flex: 2,
                  child: Text(
                    formatCurrency(breakdown.holdbackWithheld),
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: AppColors.warningDark,
                    ),
                  ),
                ),
                Expanded(child: Container()),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static const _headerStyle = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w500,
    color: AppColors.textSecondary,
  );
}

// ── Building blocks ──────────────────────────────────────────────────────

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _StatCard({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.base),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              color: AppColors.textSecondary,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w500,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;
  final String subtitle;

  const _InfoCard({
    required this.label,
    required this.value,
    this.valueColor,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: valueColor,
            ),
          ),
          Text(
            subtitle,
            style: const TextStyle(
              fontSize: 11,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  final bool released;

  const _StatusPill({required this.released});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 2),
      decoration: BoxDecoration(
        color: released
            ? AppColors.successLight
            : AppColors.textSecondary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(AppRadius.xl),
      ),
      child: Text(
        released ? 'Released' : 'Held',
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w500,
          color: released ? AppColors.successDark : AppColors.textSecondary,
        ),
      ),
    );
  }
}
