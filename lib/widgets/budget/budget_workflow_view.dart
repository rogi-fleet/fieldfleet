import 'package:flutter/material.dart';
import '../../models/financial_workflow_state.dart';
import '../../screens/projects/budget_view_screen.dart';
import '../../theme/theme.dart';

/// Workflow canvas shown when the user selects the "Workflow" view mode in the
/// budget dropdown. Follows the same pattern as [BudgetHoldbackView] and
/// [BudgetProfitView] — a stateless widget receiving pre-computed data.
class BudgetWorkflowView extends StatelessWidget {
  final FinancialWorkflowState state;
  final String projectName;
  final String Function(double) formatCurrency;
  final void Function(WorkflowNode node)? onNodeTap;
  final void Function(BudgetViewMode mode)? onBandTap;
  final bool compact;

  const BudgetWorkflowView({
    super.key,
    required this.state,
    required this.projectName,
    required this.formatCurrency,
    this.onNodeTap,
    this.onBandTap,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.base, vertical: AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!compact) ...[
            _WorkflowHeader(projectName: projectName),
            const SizedBox(height: 12),
          ],
          _WorkflowKpiStrip(
            state: state,
            formatCurrency: formatCurrency,
            compact: compact,
          ),
          const SizedBox(height: 16),
          for (int i = 0; i < state.bands.length; i++) ...[
            if (i > 0) const SizedBox(height: 8),
            _WorkflowBandRow(
              band: state.bands[i],
              onNodeTap: onNodeTap,
              onBandTap: onBandTap,
              compact: compact,
            ),
          ],
        ],
      ),
    );
  }
}

// ── Header ─────────────────────────────────────────────────────────────────

class _WorkflowHeader extends StatelessWidget {
  final String projectName;

  const _WorkflowHeader({required this.projectName});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Text(
          'Financials Workflow — $projectName',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: colorScheme.onSurface,
          ),
        ),
        const SizedBox(width: 12),
        Text(
          'Click any step to open, create, or review that document',
          style: TextStyle(
            fontSize: 12,
            color: colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

// ── KPI Strip ──────────────────────────────────────────────────────────────

class _WorkflowKpiStrip extends StatelessWidget {
  final FinancialWorkflowState state;
  final String Function(double) formatCurrency;
  final bool compact;

  const _WorkflowKpiStrip({
    required this.state,
    required this.formatCurrency,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final kpis = [
      (
        icon: Icons.description_outlined,
        label: 'Approved Estimate',
        value: formatCurrency(state.approvedEstimate),
        color: AppColors.primary,
      ),
      (
        icon: Icons.receipt_long_outlined,
        label: 'Invoiced to Date',
        value: formatCurrency(state.invoicedToDate),
        color: AppColors.warning,
      ),
      (
        icon: Icons.payments_outlined,
        label: 'Collected',
        value: formatCurrency(state.collected),
        color: AppColors.invoiceAccent,
      ),
      (
        icon: Icons.account_balance_wallet_outlined,
        label: 'Outstanding',
        value: formatCurrency(state.outstanding),
        color: state.outstanding > 0 ? AppColors.error : AppColors.success,
      ),
    ];

    if (compact) {
      return Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _KpiCard(
                  icon: kpis[0].icon,
                  label: kpis[0].label,
                  value: kpis[0].value,
                  color: kpis[0].color,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _KpiCard(
                  icon: kpis[1].icon,
                  label: kpis[1].label,
                  value: kpis[1].value,
                  color: kpis[1].color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _KpiCard(
                  icon: kpis[2].icon,
                  label: kpis[2].label,
                  value: kpis[2].value,
                  color: kpis[2].color,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _KpiCard(
                  icon: kpis[3].icon,
                  label: kpis[3].label,
                  value: kpis[3].value,
                  color: kpis[3].color,
                ),
              ),
            ],
          ),
        ],
      );
    }

    return Row(
      children: [
        for (int i = 0; i < kpis.length; i++) ...[
          if (i > 0) const SizedBox(width: 10),
          Expanded(
            child: _KpiCard(
              icon: kpis[i].icon,
              label: kpis[i].label,
              value: kpis[i].value,
              color: kpis[i].color,
            ),
          ),
        ],
      ],
    );
  }
}

class _KpiCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _KpiCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: AppSpacing.md),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    color: colorScheme.onSurfaceVariant,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Band Row ───────────────────────────────────────────────────────────────

class _WorkflowBandRow extends StatelessWidget {
  final WorkflowBand band;
  final void Function(WorkflowNode node)? onNodeTap;
  final void Function(BudgetViewMode mode)? onBandTap;
  final bool compact;

  const _WorkflowBandRow({
    required this.band,
    this.onNodeTap,
    this.onBandTap,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(AppRadius.r12),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.4),
        ),
      ),
      child: compact
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _BandLabel(
                  label: band.label,
                  subtitle: band.subtitle,
                  icon: band.icon,
                  compact: true,
                  onTap: band.viewMode != null && onBandTap != null
                      ? () => onBandTap!(band.viewMode!)
                      : null,
                ),
                Divider(
                  height: 1,
                  thickness: 1,
                  color: colorScheme.outlineVariant.withValues(alpha: 0.4),
                ),
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (int i = 0; i < band.chains.length; i++) ...[
                        if (i > 0) const SizedBox(height: 8),
                        _buildChain(band.chains[i], colorScheme),
                      ],
                    ],
                  ),
                ),
              ],
            )
          : IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Band label column
                  SizedBox(
                    width: 120,
                    child: _BandLabel(
                      label: band.label,
                      subtitle: band.subtitle,
                      icon: band.icon,
                      onTap: band.viewMode != null && onBandTap != null
                          ? () => onBandTap!(band.viewMode!)
                          : null,
                    ),
                  ),
                  VerticalDivider(
                    width: 1,
                    thickness: 1,
                    color: colorScheme.outlineVariant.withValues(alpha: 0.4),
                  ),
                  // Chain area
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.lg, vertical: AppSpacing.base),
                      child: band.chains.length == 1
                          ? _buildChain(band.chains[0], colorScheme)
                          : Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                    child: _buildChain(
                                        band.chains[0], colorScheme)),
                                if (band.chains.length > 1) ...[
                                  const SizedBox(width: 40),
                                  Expanded(
                                      child: _buildChain(
                                          band.chains[1], colorScheme)),
                                ],
                              ],
                            ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildChain(List<WorkflowNode> nodes, ColorScheme colorScheme) {
    if (nodes.isEmpty) return const SizedBox.shrink();
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (int i = 0; i < nodes.length; i++) ...[
            if (i > 0)
              _WorkflowArrow(
                label: nodes[i - 1].transitionLabel,
                color: _statusColor(nodes[i - 1].status, colorScheme),
              ),
            _WorkflowNodeChip(
              node: nodes[i],
              onTap: onNodeTap != null ? () => onNodeTap!(nodes[i]) : null,
            ),
          ],
        ],
      ),
    );
  }
}

class _BandLabel extends StatelessWidget {
  final String label;
  final String subtitle;
  final IconData icon;
  final bool compact;
  final VoidCallback? onTap;

  const _BandLabel({
    required this.label,
    required this.subtitle,
    required this.icon,
    this.compact = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    if (compact) {
      return InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: [
              Icon(icon, size: 20, color: colorScheme.onSurfaceVariant),
              const SizedBox(width: 10),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                  color: colorScheme.onSurface,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 11,
                    color: colorScheme.outline,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (onTap != null)
                Icon(
                  Icons.chevron_right,
                  size: 16,
                  color: colorScheme.outline,
                ),
            ],
          ),
        ),
      );
    }
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 24, color: colorScheme.onSurfaceVariant),
            const SizedBox(height: 6),
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
                color: colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 10,
                color: colorScheme.outline,
              ),
            ),
            if (onTap != null) ...[
              const SizedBox(height: 4),
              Icon(
                Icons.chevron_right,
                size: 14,
                color: colorScheme.outline,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Node Chip ──────────────────────────────────────────────────────────────

class _WorkflowNodeChip extends StatelessWidget {
  final WorkflowNode node;
  final VoidCallback? onTap;

  const _WorkflowNodeChip({required this.node, this.onTap});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final statusColor = _statusColor(node.status, colorScheme);
    final bgColor = node.status == WorkflowNodeStatus.notStarted
        ? colorScheme.surfaceContainerHighest.withValues(alpha: 0.5)
        : statusColor.withValues(alpha: 0.08);
    final borderColor = node.status == WorkflowNodeStatus.notStarted
        ? colorScheme.outlineVariant
        : statusColor.withValues(alpha: 0.4);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: Container(
          width: 130,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 10),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: borderColor),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Icon with optional badge
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: node.status == WorkflowNodeStatus.notStarted
                          ? colorScheme.surfaceContainerHighest
                          : statusColor.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      node.icon,
                      size: 18,
                      color: node.status == WorkflowNodeStatus.notStarted
                          ? colorScheme.outline
                          : statusColor,
                    ),
                  ),
                  if (node.status == WorkflowNodeStatus.complete)
                    Positioned(
                      right: -2,
                      top: -2,
                      child: Container(
                        width: 14,
                        height: 14,
                        decoration: const BoxDecoration(
                          color: AppColors.success,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.check,
                          size: 10,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  if (node.status == WorkflowNodeStatus.overdue)
                    Positioned(
                      right: -2,
                      top: -2,
                      child: Container(
                        width: 14,
                        height: 14,
                        decoration: const BoxDecoration(
                          color: AppColors.error,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.priority_high,
                          size: 10,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  if (node.count != null && node.count! > 1)
                    Positioned(
                      left: -4,
                      top: -4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.xs, vertical: 1),
                        decoration: BoxDecoration(
                          color: statusColor,
                          borderRadius: BorderRadius.circular(AppRadius.sm),
                        ),
                        child: Text(
                          '${node.count}',
                          style: const TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              // Label
              Text(
                node.label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  height: 1.2,
                  color: colorScheme.onSurface,
                ),
              ),
              // Status text
              if (node.statusText != null) ...[
                const SizedBox(height: 3),
                Text(
                  node.statusText!,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                    color: _statusTextColor(node.status, colorScheme),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Color _statusTextColor(WorkflowNodeStatus status, ColorScheme colorScheme) {
    switch (status) {
      case WorkflowNodeStatus.complete:
        return AppColors.success;
      case WorkflowNodeStatus.overdue:
        return AppColors.error;
      case WorkflowNodeStatus.active:
        return AppColors.warning;
      case WorkflowNodeStatus.draft:
        return AppColors.info;
      case WorkflowNodeStatus.notStarted:
        return colorScheme.outline;
    }
  }
}

// ── Arrow ──────────────────────────────────────────────────────────────────

class _WorkflowArrow extends StatelessWidget {
  final String? label;
  final Color color;

  const _WorkflowArrow({this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 80,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (label != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                label!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 8,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.3,
                  color: color.withValues(alpha: 0.7),
                ),
              ),
            ),
          Row(
            children: [
              Expanded(
                child: Container(
                  height: 2,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        color.withValues(alpha: 0.3),
                        color.withValues(alpha: 0.6),
                      ],
                    ),
                  ),
                ),
              ),
              Icon(
                Icons.arrow_right,
                size: 16,
                color: color.withValues(alpha: 0.6),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Shared helper ──────────────────────────────────────────────────────────

Color _statusColor(WorkflowNodeStatus status, ColorScheme colorScheme) {
  switch (status) {
    case WorkflowNodeStatus.complete:
      return AppColors.success;
    case WorkflowNodeStatus.overdue:
      return AppColors.error;
    case WorkflowNodeStatus.active:
      return AppColors.warning;
    case WorkflowNodeStatus.draft:
      return AppColors.info;
    case WorkflowNodeStatus.notStarted:
      return colorScheme.outline;
  }
}
