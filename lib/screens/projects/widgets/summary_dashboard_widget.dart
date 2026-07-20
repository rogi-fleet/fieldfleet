import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../models/cost_plus_type.dart';
import '../../../models/price_type.dart';
import '../../../models/project.dart';
import '../../../models/project_financial_summary.dart';
import '../../../services/service_locator.dart';
import '../../../theme/theme.dart';

/// Summary Dashboard widget showing key project metrics in a compact stacked
/// layout. Includes a per-project privacy toggle that lets the user hide all
/// monetary values (and the pricing model details) on shared screens.
class SummaryDashboardWidget extends StatefulWidget {
  final Project project;
  final bool preferHalfLayout;
  final Widget? trailing;

  const SummaryDashboardWidget({
    super.key,
    required this.project,
    this.preferHalfLayout = false,
    this.trailing,
  });

  @override
  State<SummaryDashboardWidget> createState() => _SummaryDashboardWidgetState();
}

class _SummaryDashboardWidgetState extends State<SummaryDashboardWidget> {
  static const _prefsKeyPrefix = 'financial_summary_hidden_';

  bool _hidden = false;
  bool _prefsLoaded = false;

  String get _prefsKey => '$_prefsKeyPrefix${widget.project.id}';

  @override
  void initState() {
    super.initState();
    _loadHiddenPref();
  }

  @override
  void didUpdateWidget(covariant SummaryDashboardWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.project.id != widget.project.id) {
      setState(() {
        _prefsLoaded = false;
        _hidden = false;
      });
      _loadHiddenPref();
    }
  }

  Future<void> _loadHiddenPref() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _hidden = prefs.getBool(_prefsKey) ?? false;
      _prefsLoaded = true;
    });
  }

  Future<void> _toggleHidden() async {
    final next = !_hidden;
    setState(() => _hidden = next);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsKey, next);
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildHeader(context),
            if (_prefsLoaded && !_hidden) ...[
              const SizedBox(height: 4),
              _buildMetricsList(context),
              if (_hasPricingDetails(widget.project)) ...[
                const SizedBox(height: 4),
                const Divider(height: 1),
                const SizedBox(height: 4),
                _buildPricingDetails(context),
              ],
            ] else if (_prefsLoaded && _hidden) ...[
              const SizedBox(height: 4),
              _buildHiddenPlaceholder(context),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            'Financial Summary',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        if (widget.trailing != null) widget.trailing!,
        Tooltip(
          message: _hidden ? 'Show financial values' : 'Hide for privacy',
          child: Switch(
            value: !_hidden,
            onChanged: _prefsLoaded ? (_) => _toggleHidden() : null,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            thumbIcon: WidgetStateProperty.resolveWith((states) {
              return Icon(
                states.contains(WidgetState.selected)
                    ? Icons.visibility
                    : Icons.visibility_off,
                size: 14,
              );
            }),
          ),
        ),
      ],
    );
  }

  Widget _buildHiddenPlaceholder(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Row(
        children: [
          Icon(Icons.lock_outline, size: 16, color: AppColors.textSecondary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Hidden for privacy. Toggle to reveal.',
              style: TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricsList(BuildContext context) {
    return FutureBuilder<ProjectFinancialSummary>(
      future:
          ServiceLocator.projectService.getProjectFinancials(widget.project.id)
              as Future<ProjectFinancialSummary>,
      builder: (context, snapshot) {
        final financials = snapshot.data;
        final budget = financials?.approvedPrice ?? 0.0;
        final collectedRevenue = financials?.collectedSoFar ?? 0.0;
        final projectedProfit = financials?.projectedProfit ?? 0.0;
        final profitSeverity = projectedProfit < 0
            ? AppSeverity.error
            : projectedProfit == 0
                ? AppSeverity.warning
                : AppSeverity.neutral;
        final profitPalette = AppSeverityTheme.colors(profitSeverity);

        final rows = <Widget>[
          _buildMetricRow(
            context,
            icon: Icons.verified_outlined,
            label: widget.project.status.isEstimateApproved
                ? 'Approved'
                : 'Estimated Value',
            value: '\$${NumberFormat('#,##0').format(budget)}',
            color: AppColors.info,
            onTap: () =>
                context.push('/projects/${widget.project.id}/budget'),
          ),
          _buildMetricRow(
            context,
            icon: Icons.trending_up,
            label: 'Collected',
            value: '\$${NumberFormat('#,##0').format(collectedRevenue)}',
            color: AppColors.success,
            onTap: () =>
                context.push('/projects/${widget.project.id}?tab=financials'),
          ),
          _buildMetricRow(
            context,
            icon: Icons.account_balance_wallet,
            label: 'Profit',
            value: '\$${NumberFormat('#,##0').format(projectedProfit)}',
            color: profitPalette.accent,
            valueColor: profitPalette.value,
            onTap: () =>
                context.push('/projects/${widget.project.id}?tab=financials'),
          ),
          _buildMetricRow(
            context,
            icon: Icons.account_balance,
            label: 'Balance',
            value:
                '\$${NumberFormat('#,##0').format(budget - collectedRevenue)}',
            color: AppColors.messageAccent,
            onTap: () =>
                context.push('/projects/${widget.project.id}/budget'),
            isLast: true,
          ),
        ];

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: rows,
        );
      },
    );
  }

  Widget _buildMetricRow(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String value,
    required Color color,
    Color? valueColor,
    VoidCallback? onTap,
    bool isLast = false,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs, vertical: 6),
        child: Container(
          decoration: isLast
              ? null
              : BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: AppColors.cardBorder.withValues(alpha: 0.6),
                      width: 0.5,
                    ),
                  ),
                ),
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: valueColor ?? color,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  bool _hasPricingDetails(Project p) {
    return p.estimatedBudget != null ||
        p.contractAmount != null ||
        p.costPlusType != null ||
        p.costPlusValue != null ||
        p.materialMarkupPercent != 20.0 ||
        p.laborMarkupPercent != 30.0 ||
        p.priceType != PriceType.timeAndMaterial;
  }

  Widget _buildPricingDetails(BuildContext context) {
    final project = widget.project;
    final rows = <_PricingEntry>[];

    rows.add(_PricingEntry(
      icon: Icons.sell_outlined,
      label: 'Price Type',
      value: project.priceType.displayName,
    ));

    if (project.estimatedBudget != null) {
      rows.add(_PricingEntry(
        icon: Icons.savings_outlined,
        label: 'Estimated Budget',
        value: '\$${NumberFormat('#,##0').format(project.estimatedBudget)}',
      ));
    }

    if (project.priceType == PriceType.fixedPrice &&
        project.contractAmount != null) {
      rows.add(_PricingEntry(
        icon: Icons.assignment_turned_in_outlined,
        label: 'Contract Amount',
        value: '\$${NumberFormat('#,##0').format(project.contractAmount)}',
      ));
    }

    if (project.priceType == PriceType.costPlus &&
        project.costPlusType != null &&
        project.costPlusValue != null) {
      final isPercent = project.costPlusType == CostPlusType.percentage;
      rows.add(_PricingEntry(
        icon: Icons.percent,
        label: project.costPlusType!.displayName,
        value: isPercent
            ? '${project.costPlusValue}%'
            : '\$${NumberFormat('#,##0').format(project.costPlusValue)}',
      ));
    }

    rows.add(_PricingEntry(
      icon: Icons.inventory_2_outlined,
      label: 'Material Markup',
      value: '${project.materialMarkupPercent.toStringAsFixed(0)}%',
    ));
    rows.add(_PricingEntry(
      icon: Icons.engineering_outlined,
      label: 'Labor Markup',
      value: '${project.laborMarkupPercent.toStringAsFixed(0)}%',
    ));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 4),
          child: Text(
            'PRICING MODEL',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: AppColors.textSecondary,
              letterSpacing: 0.6,
            ),
          ),
        ),
        for (int i = 0; i < rows.length; i++)
          _buildPricingRow(rows[i], isLast: i == rows.length - 1),
      ],
    );
  }

  Widget _buildPricingRow(_PricingEntry entry, {required bool isLast}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs, vertical: 5),
      child: Container(
        decoration: isLast
            ? null
            : BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: AppColors.cardBorder.withValues(alpha: 0.4),
                    width: 0.5,
                  ),
                ),
              ),
        padding: const EdgeInsets.only(bottom: 5),
        child: Row(
          children: [
            Icon(entry.icon, size: 13, color: AppColors.textSecondary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                entry.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              entry.value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PricingEntry {
  final IconData icon;
  final String label;
  final String value;

  const _PricingEntry({
    required this.icon,
    required this.label,
    required this.value,
  });
}
