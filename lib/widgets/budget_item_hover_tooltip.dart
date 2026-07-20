import 'package:flutter/material.dart';
import '../models/budget_item.dart';
import '../theme/theme.dart';
import '../services/supabase/budget_service.dart' show BudgetItemDocumentStatus;

/// A rich hover tooltip for budget items that displays comprehensive information
/// including name, hierarchy level, financial summary, and document status.
class BudgetItemHoverTooltip extends StatelessWidget {
  final BudgetItem item;
  final Widget child;
  final BudgetItemDocumentStatus? documentStatus;
  final Duration waitDuration;
  final bool preferBelow;

  const BudgetItemHoverTooltip({
    super.key,
    required this.item,
    required this.child,
    this.documentStatus,
    this.waitDuration = const Duration(milliseconds: 500),
    this.preferBelow = true,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      richMessage: WidgetSpan(
        child: _buildTooltipContent(context),
      ),
      waitDuration: waitDuration,
      preferBelow: preferBelow,
      padding: EdgeInsets.zero,
      decoration: const BoxDecoration(
        color: Colors.transparent,
      ),
      child: child,
    );
  }

  Widget _buildTooltipContent(BuildContext context) {
    final theme = Theme.of(context);
    final levelColor = _getHierarchyLevelColor();

    return Container(
      constraints: const BoxConstraints(maxWidth: 320),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(AppRadius.r12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(
          color: theme.dividerColor.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with name and hierarchy badge
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: levelColor.withValues(alpha:0.1),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(12),
              ),
              border: Border(
                bottom: BorderSide(
                  color: levelColor.withValues(alpha:0.2),
                ),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: levelColor,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    item.name,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                _buildHierarchyBadge(levelColor),
              ],
            ),
          ),

          // Body content
          Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Financial summary
                _buildFinancialSummary(context),

                // Description
                if (item.description != null && item.description!.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    item.description!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha:0.7),
                    ),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],

                // Notes preview
                if (item.notes != null && item.notes!.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _buildNotesPreview(context),
                ],

                // Document status
                if (documentStatus != null && documentStatus!.hasDocuments) ...[
                  const SizedBox(height: 12),
                  _buildDocumentStatus(context),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHierarchyBadge(Color color) {
    return Container(
      margin: const EdgeInsets.only(left: 8),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
      decoration: BoxDecoration(
        color: color.withValues(alpha:0.2),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        item.hierarchyLevelName,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }

  Widget _buildFinancialSummary(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withValues(alpha:0.05),
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(
          color: theme.colorScheme.primary.withValues(alpha:0.1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.attach_money,
                size: 14,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 6),
              Text(
                'Financial Summary',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _buildFinancialRow('Approved Price', item.formattedApprovedPrice, AppColors.info),
          const SizedBox(height: 4),
          _buildFinancialRow('Projected Cost', item.formattedProjectedCost, AppColors.warning),
          const SizedBox(height: 4),
          _buildFinancialRow(
            'Profit',
            item.formattedProjectedProfit,
            item.projectedProfit >= 0 ? AppColors.success : AppColors.error,
          ),
          const SizedBox(height: 4),
          _buildFinancialRow(
            'Margin',
            item.formattedProjectedMargin,
            item.projectedMargin >= 0 ? AppColors.success : AppColors.error,
          ),
          const Divider(height: 16, thickness: 0.5),
          _buildFinancialRow(
            'Quantity',
            '${item.quantity} ${item.unit ?? ''}',
            theme.colorScheme.onSurface,
          ),
          const SizedBox(height: 4),
          _buildFinancialRow('Unit Cost', item.formattedUnitCost, AppColors.textPrimary),
          const SizedBox(height: 4),
          _buildFinancialRow('Unit Price', item.formattedUnitPrice, AppColors.textPrimary),
        ],
      ),
    );
  }

  Widget _buildFinancialRow(String label, String value, Color valueColor) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: AppColors.textSecondary,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: valueColor,
          ),
        ),
      ],
    );
  }

  Widget _buildNotesPreview(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha:0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: AppColors.warning.withValues(alpha:0.3),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.sticky_note_2_outlined,
            size: 14,
            color: AppColors.warningDark,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              item.notes!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppColors.warningDark,
                fontSize: 10,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDocumentStatus(BuildContext context) {
    final status = documentStatus!;
    final indicators = <Widget>[];

    if (status.paidAmount > 0) {
      indicators.add(_buildStatusChip('Paid', AppColors.success, Icons.check_circle));
    } else if (status.invoicedAmount > 0) {
      indicators.add(_buildStatusChip('Invoiced', AppColors.info, Icons.receipt));
    }

    if (status.quotedAmount > 0) {
      indicators.add(_buildStatusChip('Quoted', AppColors.messageAccent, Icons.description));
    } else if (status.pendingQuoteAmount > 0) {
      indicators.add(_buildStatusChip('Quote Pending', AppColors.warning, Icons.pending));
    }

    if (status.bidRequestCount > 0) {
      indicators.add(_buildStatusChip(
        '${status.bidRequestCount} Bid${status.bidRequestCount > 1 ? 's' : ''}',
        AppColors.financialAccent,
        Icons.gavel,
      ));
    }

    return Wrap(
      spacing: 6,
      runSpacing: 4,
      children: indicators,
    );
  }

  Widget _buildStatusChip(String label, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha:0.1),
        borderRadius: BorderRadius.circular(AppRadius.xs),
        border: Border.all(
          color: color.withValues(alpha:0.3),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 10, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Color _getHierarchyLevelColor() {
    switch (item.hierarchyLevel) {
      case 0:
        return Colors.indigo; // Package
      case 1:
        return AppColors.financialAccent; // Section
      case 2:
        return AppColors.info; // Item
      default:
        return AppColors.textTertiary;
    }
  }
}
