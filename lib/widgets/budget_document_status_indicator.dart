import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/workspace_provider.dart';
import '../theme/theme.dart';
import '../services/supabase/budget_service.dart' show BudgetItemDocumentStatus;
import '../utils/currency_utils.dart';

/// Widget that displays document status indicators for a budget item.
/// Shows icons and amounts for quotes, invoices, and bid requests.
class BudgetDocumentStatusIndicator extends StatelessWidget {
  final BudgetItemDocumentStatus status;
  final bool compact;
  final VoidCallback? onTap;

  const BudgetDocumentStatusIndicator({
    super.key,
    required this.status,
    this.compact = false,
    this.onTap,
  });

  // Currency formatting helper
  String _formatCurrency(BuildContext context, double amount) {
    final currencyCode = context.read<WorkspaceProvider>().currencyCode;
    return CurrencyUtils.formatCurrency(amount, currencyCode);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    if (!status.hasDocuments) {
      return const SizedBox.shrink();
    }

    if (compact) {
      return _buildCompactIndicator(context, colorScheme);
    }

    return _buildFullIndicator(context, colorScheme);
  }

  Widget _buildCompactIndicator(BuildContext context, ColorScheme colorScheme) {
    // Show single icon based on highest priority status
    IconData icon;
    Color color;
    String tooltip;

    switch (status.statusKey) {
      case 'paid':
        icon = Icons.check_circle;
        color = AppColors.success;
        tooltip = 'Paid: ${_formatCurrency(context, status.paidAmount)}';
        break;
      case 'invoiced':
        icon = Icons.receipt_long;
        color = AppColors.warning;
        tooltip = 'Invoiced: ${_formatCurrency(context, status.invoicedAmount)}';
        break;
      case 'approved':
        icon = Icons.verified;
        color = AppColors.financialAccent;
        tooltip = 'Approved: ${_formatCurrency(context, status.approvedAmount)}';
        break;
      case 'quoted':
        icon = Icons.description;
        color = colorScheme.primary;
        tooltip = 'Quoted: ${_formatCurrency(context, status.quotedAmount)}';
        break;
      case 'pending':
        icon = Icons.hourglass_empty;
        color = AppColors.textTertiary;
        tooltip = 'Pending: ${_formatCurrency(context, status.pendingAmount)}';
        break;
      case 'pending_quote':
        icon = Icons.edit_document;
        color = AppColors.textTertiary;
        tooltip = 'Pending Quote: ${_formatCurrency(context, status.pendingQuoteAmount)}';
        break;
      case 'pending_bid':
        icon = Icons.gavel;
        color = AppColors.info;
        tooltip = 'Bid Request Pending';
        break;
      default:
        return const SizedBox.shrink();
    }

    final iconWidget = Icon(icon, size: 16, color: color);
    return Tooltip(
      message: tooltip,
      child: onTap != null
          ? MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTap: onTap,
                child: iconWidget,
              ),
            )
          : iconWidget,
    );
  }

  Widget _buildFullIndicator(BuildContext context, ColorScheme colorScheme) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (status.paidAmount > 0)
          _buildStatusChip(
            icon: Icons.check_circle,
            label: _formatCurrency(context, status.paidAmount),
            color: AppColors.success,
            tooltip: 'Paid',
          ),
        if (status.invoicedAmount > status.paidAmount)
          _buildStatusChip(
            icon: Icons.receipt_long,
            label: _formatCurrency(context, status.invoicedAmount - status.paidAmount),
            color: AppColors.warning,
            tooltip: 'Invoiced (Pending)',
          ),
        if (status.approvedAmount > 0)
          _buildStatusChip(
            icon: Icons.verified,
            label: _formatCurrency(context, status.approvedAmount),
            color: AppColors.financialAccent,
            tooltip: 'Approved',
          ),
        if (status.quotedAmount > 0)
          _buildStatusChip(
            icon: Icons.description,
            label: _formatCurrency(context, status.quotedAmount),
            color: colorScheme.primary,
            tooltip: 'Quoted',
          ),
        if (status.pendingAmount > 0)
          _buildStatusChip(
            icon: Icons.hourglass_empty,
            label: _formatCurrency(context, status.pendingAmount),
            color: AppColors.textTertiary,
            tooltip: 'Pending',
          ),
        if (status.hasPendingBid)
          _buildStatusChip(
            icon: Icons.gavel,
            label: '${status.bidRequestCount}',
            color: AppColors.info,
            tooltip: 'Bid Requests',
          ),
      ],
    );
  }
  
  Widget _buildStatusChip({
    required IconData icon,
    required String label,
    required Color color,
    required String tooltip,
  }) {
    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(AppRadius.xs),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: color,
            ),
          ),
        ],
      ),
    );
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: Tooltip(
        message: tooltip,
        child: onTap != null
            ? MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  onTap: onTap,
                  child: chip,
                ),
              )
            : chip,
      ),
    );
  }
}

/// Legend widget explaining status indicators
class BudgetStatusLegend extends StatelessWidget {
  const BudgetStatusLegend({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    
    return Wrap(
      spacing: 16,
      runSpacing: 8,
      children: [
        _buildLegendItem(Icons.check_circle, 'Paid', AppColors.success),
        _buildLegendItem(Icons.receipt_long, 'Invoiced', AppColors.warning),
        _buildLegendItem(Icons.verified, 'Approved', AppColors.financialAccent),
        _buildLegendItem(Icons.description, 'Quoted', colorScheme.primary),
        _buildLegendItem(Icons.hourglass_empty, 'Pending', AppColors.textTertiary),
        _buildLegendItem(Icons.gavel, 'Bid Request', AppColors.info),
      ],
    );
  }
  
  Widget _buildLegendItem(IconData icon, String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: color,
          ),
        ),
      ],
    );
  }
}
