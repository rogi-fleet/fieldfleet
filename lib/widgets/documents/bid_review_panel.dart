import 'package:flutter/material.dart';

import '../../models/budget_item.dart';
import '../../models/document_line_item.dart';
import '../../models/document_status.dart';
import '../../models/generated_document.dart';
import '../../services/service_locator.dart';
import '../../theme/theme.dart';
import '../../utils/currency_utils.dart';
import '../../utils/user_facing_error.dart';

/// GC-facing review of a vendor's submitted bid. Shown on the document
/// detail screen once an RFB transitions to `responded`. Compares the
/// internal estimate against the vendor's per-line bid and offers a
/// single action to push the bid prices into the project's budget.
class BidReviewPanel extends StatefulWidget {
  const BidReviewPanel({
    super.key,
    required this.document,
    required this.onApplied,
    required this.onRejected,
  });

  final GeneratedDocument document;
  final VoidCallback onApplied;
  final VoidCallback onRejected;

  @override
  State<BidReviewPanel> createState() => _BidReviewPanelState();
}

class _BidReviewPanelState extends State<BidReviewPanel> {
  bool _busy = false;
  String? _error;
  Map<String, BudgetItem> _budgetById = const {};

  @override
  void initState() {
    super.initState();
    _loadBudgetItems();
  }

  Future<void> _loadBudgetItems() async {
    final projectId = widget.document.projectId;
    if (projectId == null) return;
    try {
      final items = await ServiceLocator.budgetService
              .getBudgetItems(
                projectId,
                workspaceId: widget.document.workspaceId,
              )
              .first
          as List<BudgetItem>;
      if (!mounted) return;
      setState(() {
        _budgetById = {for (final it in items) it.id: it};
      });
    } catch (_) {
      // Silent — the panel still works without names on the linked items.
    }
  }

  List<DocumentLineItem> get _pricedLineItems => widget.document.lineItems
      .where((li) => li.isVisible && li.isItem)
      .toList()
    ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

  double get _internalTotal =>
      _pricedLineItems.fold(0.0, (sum, li) => sum + li.total);

  double get _bidTotal => _pricedLineItems.fold(
        0.0,
        (sum, li) => sum + (li.vendorBidTotal ?? 0),
      );

  double get _varianceRatio {
    if (_internalTotal <= 0) return 0;
    return (_bidTotal - _internalTotal) / _internalTotal;
  }

  bool get _isApplied => widget.document.status == DocumentStatus.applied;

  String _formatCurrency(double amount) {
    // Workspace currency code isn't threaded into this panel today; fall
    // back to the USD default via CurrencyUtils. Acceptable while the rest
    // of the document preview uses the same default.
    return CurrencyUtils.formatCurrency(amount, 'USD');
  }

  Future<void> _applyToBudget() async {
    final variance = _varianceRatio;
    if (variance > 0.25) {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Vendor bid is over estimate'),
          content: Text(
            'The vendor bid of ${_formatCurrency(_bidTotal)} is '
            '${(variance * 100).toStringAsFixed(1)}% above your internal '
            'estimate of ${_formatCurrency(_internalTotal)}. Apply anyway?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Apply anyway'),
            ),
          ],
        ),
      );
      if (proceed != true) return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ServiceLocator.budgetService.applyVendorBidToBudget(
        widget.document.id,
      );
      widget.onApplied();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = UserFacingError.uiMessage(
          e,
          action: 'apply the bid to the budget',
        );
      });
    }
  }

  Future<void> _rejectBid() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reject this bid?'),
        content: const Text(
          'The document will return to "sent" so the vendor can resubmit. '
          'Their submitted prices will be preserved for reference.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Reject bid'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ServiceLocator.documentService.updateDocument(
        documentId: widget.document.id,
        status: DocumentStatus.sent,
      );
      widget.onRejected();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = UserFacingError.uiMessage(e, action: 'reject the bid');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = _pricedLineItems;
    if (items.isEmpty) return const SizedBox.shrink();

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _header(),
          const Divider(height: 1),
          _tableHeader(),
          const Divider(height: 1),
          for (final item in items) _tableRow(item),
          const Divider(height: 1),
          _totalsRow(),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Text(
                _error!,
                style: TextStyle(color: AppColors.error, fontSize: 12),
              ),
            ),
          _actions(),
        ],
      ),
    );
  }

  Widget _header() {
    final status = widget.document.status;
    final label = _isApplied ? 'Bid applied' : 'Bid received';
    final color = _isApplied ? AppColors.success : AppColors.info;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.base),
      color: color.withValues(alpha: 0.08),
      child: Row(
        children: [
          Icon(
            _isApplied ? Icons.done_all : Icons.mark_email_read,
            color: color,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
                Text(
                  _isApplied
                      ? 'These prices have been pushed into the project budget.'
                      : 'Review the vendor\'s submitted prices and apply to the project budget.',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          Text(
            status.displayName,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _tableHeader() {
    const style = TextStyle(fontSize: 11, fontWeight: FontWeight.w600);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      color: AppColors.surfaceAlt,
      child: Row(
        children: const [
          Expanded(flex: 4, child: Text('Description', style: style)),
          SizedBox(
            width: 80,
            child: Text(
              'Estimate',
              textAlign: TextAlign.right,
              style: style,
            ),
          ),
          SizedBox(
            width: 80,
            child: Text(
              'Vendor bid',
              textAlign: TextAlign.right,
              style: style,
            ),
          ),
          SizedBox(
            width: 60,
            child: Text(
              'Δ',
              textAlign: TextAlign.right,
              style: style,
            ),
          ),
        ],
      ),
    );
  }

  Widget _tableRow(DocumentLineItem item) {
    final estimate = item.total;
    final bid = item.vendorBidTotal;
    final delta = bid == null ? null : bid - estimate;
    final budgetItemName = item.budgetItemId == null
        ? null
        : _budgetById[item.budgetItemId!]?.name;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                flex: 4,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.name,
                      style: const TextStyle(fontWeight: FontWeight.w500),
                    ),
                    Text(
                      'Qty ${item.formattedQuantity}'
                      '${item.unit != null ? ' ${item.unit}' : ''}',
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColors.textTertiary,
                      ),
                    ),
                    if (budgetItemName != null)
                      Text(
                        '→ $budgetItemName',
                        style: TextStyle(
                          fontSize: 11,
                          color: AppColors.textTertiary,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                  ],
                ),
              ),
              SizedBox(
                width: 80,
                child: Text(
                  _formatCurrency(estimate),
                  textAlign: TextAlign.right,
                  style: const TextStyle(fontSize: 13),
                ),
              ),
              SizedBox(
                width: 80,
                child: Text(
                  bid == null ? '—' : _formatCurrency(bid),
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: bid == null ? AppColors.textTertiary : null,
                  ),
                ),
              ),
              SizedBox(
                width: 60,
                child: Text(
                  delta == null ? '' : _formatDelta(delta),
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontSize: 12,
                    color: delta == null
                        ? AppColors.textTertiary
                        : delta > 0
                            ? AppColors.error
                            : AppColors.success,
                  ),
                ),
              ),
            ],
          ),
          if (item.vendorBidNote != null && item.vendorBidNote!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4, left: 2),
              child: Text(
                '“${item.vendorBidNote}”',
                style: TextStyle(
                  fontSize: 11,
                  fontStyle: FontStyle.italic,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _formatDelta(double delta) {
    final sign = delta > 0 ? '+' : '';
    return '$sign${_formatCurrency(delta)}';
  }

  Widget _totalsRow() {
    final variance = _varianceRatio;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.md),
      color: AppColors.primarySurface,
      child: Row(
        children: [
          const Expanded(
            flex: 4,
            child: Text(
              'Totals',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          SizedBox(
            width: 80,
            child: Text(
              _formatCurrency(_internalTotal),
              textAlign: TextAlign.right,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          SizedBox(
            width: 80,
            child: Text(
              _formatCurrency(_bidTotal),
              textAlign: TextAlign.right,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: AppColors.primary,
              ),
            ),
          ),
          SizedBox(
            width: 60,
            child: Text(
              _internalTotal <= 0
                  ? ''
                  : '${(variance * 100).toStringAsFixed(1)}%',
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: variance > 0 ? AppColors.error : AppColors.success,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _actions() {
    if (_isApplied) {
      return Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          children: [
            Icon(Icons.lock_outline, size: 16, color: AppColors.textSecondary),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                'Bid has been applied to the budget. To revise, issue a new '
                'RFB.',
                style: TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          TextButton(
            onPressed: _busy ? null : _rejectBid,
            child: const Text('Reject bid'),
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            onPressed: _busy ? null : _applyToBudget,
            icon: _busy
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.download_done, size: 16),
            label: const Text('Apply to Budget Estimate'),
          ),
        ],
      ),
    );
  }
}
