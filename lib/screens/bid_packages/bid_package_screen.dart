import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../models/bid_package.dart';
import '../../models/document_line_item.dart';
import '../../models/document_status.dart';
import '../../models/document_type.dart';
import '../../models/generated_document.dart';
import '../../models/vendor.dart';
import '../../services/service_locator.dart';
import '../../theme/theme.dart';
import '../../utils/user_facing_error.dart';

/// Multi-vendor bid package detail — lets the GC compare every vendor's
/// itemized bid side-by-side and award the package to one of them.
class BidPackageScreen extends StatefulWidget {
  const BidPackageScreen({super.key, required this.packageId});

  final String packageId;

  @override
  State<BidPackageScreen> createState() => _BidPackageScreenState();
}

class _BidPackageScreenState extends State<BidPackageScreen> {
  BidPackage? _package;
  List<GeneratedDocument> _children = const [];
  Map<String, Vendor> _vendorsById = const {};

  /// Purchase orders already derived from the awarded RFB (so the post-award
  /// CTA flips from "Create Purchase Order" to "View Purchase Order").
  List<GeneratedDocument> _awardPurchaseOrders = const [];

  bool _loading = true;
  bool _busy = false;
  String? _error;

  final _currencyFormatter = NumberFormat.currency(symbol: r'$');

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final service = ServiceLocator.bidPackageService;
      final pkg = await service.getPackage(widget.packageId);
      if (pkg == null) {
        if (!mounted) return;
        setState(() {
          _loading = false;
          _error = 'Bid package not found.';
        });
        return;
      }
      final children = await service.listChildDocuments(widget.packageId);

      final vendorsById = <String, Vendor>{};
      for (final doc in children) {
        final vid = doc.vendorId;
        if (vid == null || vendorsById.containsKey(vid)) continue;
        final v = await ServiceLocator.vendorService.getVendor(vid);
        if (v is Vendor) vendorsById[vid] = v;
      }

      var awardPOs = const <GeneratedDocument>[];
      if (pkg.status == BidPackageStatus.awarded &&
          pkg.awardedDocumentId != null) {
        final derived = await ServiceLocator.documentService
            .getDocumentsBySourceId(pkg.awardedDocumentId!);
        awardPOs = (derived as List<GeneratedDocument>)
            .where((d) => d.documentType == DocumentType.purchaseOrder)
            .toList();
      }

      if (!mounted) return;
      setState(() {
        _loading = false;
        _package = pkg;
        _children = children;
        _vendorsById = vendorsById;
        _awardPurchaseOrders = awardPOs;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = UserFacingError.uiMessage(
          e,
          action: 'load the bid package',
        );
      });
    }
  }

  /// Template rows are keyed by templateLineItemId across every child doc.
  /// Use the first child doc as the canonical source for description / qty
  /// / unit / internal estimate — all clones share those per-row fields.
  List<_TemplateRow> get _templateRows {
    if (_children.isEmpty) return const [];
    final canonical = _children.first.lineItems
        .where((li) => li.isItem && li.isVisible)
        .toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    return canonical
        .map(
          (li) => _TemplateRow(
            templateLineItemId: _templateId(li) ?? li.id,
            name: li.name,
            description: li.description,
            quantity: li.quantity,
            unit: li.unit,
            internalUnitPrice: li.unitPrice,
          ),
        )
        .toList();
  }

  /// templateLineItemId lives in the line item's raw JSON; DocumentLineItem
  /// doesn't surface it as a typed field yet. Pull it from toJson().
  String? _templateId(DocumentLineItem li) {
    final raw = li.toJson()['templateLineItemId'];
    return raw is String ? raw : null;
  }

  _VendorBid? _vendorBidForRow(
    GeneratedDocument doc,
    _TemplateRow row,
  ) {
    for (final li in doc.lineItems) {
      final tid = _templateId(li);
      if (tid == null) continue;
      if (tid == row.templateLineItemId) {
        return _VendorBid(
          lineItem: li,
          bidPrice: li.vendorBidPrice,
          bidTotal: li.vendorBidTotal,
        );
      }
    }
    return null;
  }

  double _vendorTotal(GeneratedDocument doc) {
    return doc.lineItems.fold<double>(
      0,
      (sum, li) => sum + (li.vendorBidTotal ?? 0),
    );
  }

  double _internalTotal(List<_TemplateRow> rows) {
    return rows.fold<double>(
      0,
      (sum, r) => sum + r.internalUnitPrice * r.quantity,
    );
  }

  double? _lowestBidTotal(List<GeneratedDocument> responders) {
    if (responders.isEmpty) return null;
    double? lowest;
    for (final doc in responders) {
      final total = _vendorTotal(doc);
      if (total <= 0) continue;
      if (lowest == null || total < lowest) lowest = total;
    }
    return lowest;
  }

  Future<void> _awardVendor(GeneratedDocument winner) async {
    final rows = _templateRows;
    final internal = _internalTotal(rows);
    final winnerTotal = _vendorTotal(winner);
    final variance = internal > 0 ? (winnerTotal - internal) / internal : 0;

    if (variance > 0.25) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Vendor bid is over estimate'),
          content: Text(
            '${_vendorName(winner)}\'s bid of '
            '${_currencyFormatter.format(winnerTotal)} is '
            '${(variance * 100).toStringAsFixed(1)}% above your internal '
            'estimate of ${_currencyFormatter.format(internal)}. '
            'Award anyway?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Award anyway'),
            ),
          ],
        ),
      );
      if (ok != true) return;
    } else {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('Award to ${_vendorName(winner)}?'),
          content: Text(
            'This will apply their bid of '
            '${_currencyFormatter.format(winnerTotal)} to the project '
            'budget and close out the other vendors.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Award'),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ServiceLocator.bidPackageService.awardPackage(
        packageId: widget.packageId,
        winningDocumentId: winner.id,
      );
      await _load();
      if (!mounted) return;
      setState(() => _busy = false);

      // Close the loop: offer the PO right where the award happened instead
      // of making the user hunt for the awarded RFB under Financials.
      final createPo = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('Awarded to ${_vendorName(winner)}'),
          content: const Text(
            'Their bid has been applied to the project budget. Create the '
            'purchase order now?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Later'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Create Purchase Order'),
            ),
          ],
        ),
      );
      if (createPo == true && mounted) {
        await _createPurchaseOrderFromAward();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = UserFacingError.uiMessage(
          e,
          action: 'award the bid package',
        );
      });
    }
  }

  /// Routes to the PO creation wizard pre-populated from the awarded RFB.
  /// The award already overwrote the RFB's unit prices with the winning
  /// vendor's bid, so the derived PO carries the vendor's numbers and keeps
  /// the budget links + source-document back-reference.
  Future<void> _createPurchaseOrderFromAward() async {
    final pkg = _package;
    final winnerId = pkg?.awardedDocumentId;
    if (pkg == null || winnerId == null) return;
    GeneratedDocument? winner;
    for (final doc in _children) {
      if (doc.id == winnerId) {
        winner = doc;
        break;
      }
    }
    if (winner == null) return;

    try {
      final template = await ServiceLocator.documentTemplateService
          .getDefaultTemplate(winner.workspaceId, DocumentType.purchaseOrder);
      if (template == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'No default Purchase Order template found. Create one in '
                'Templates.',
              ),
            ),
          );
        }
        return;
      }

      final prePopulatedLineItems = winner.lineItems
          .where((item) => item.isVisible && item.isItem)
          .map(
            (item) => {
              'description': item.name,
              'quantity': item.quantity,
              'unit': item.unit ?? '',
              'amount': item.total,
              if (item.budgetItemId != null) 'budgetItemId': item.budgetItemId,
            },
          )
          .toList();

      final query = <String, String>{'templateId': template.id as String};
      if (winner.projectId != null && winner.projectId!.isNotEmpty) {
        query['projectId'] = winner.projectId!;
      }

      if (!mounted) return;
      context.go(
        Uri(path: '/documents/create', queryParameters: query).toString(),
        extra: {
          'lineItems': prePopulatedLineItems,
          'selectedBudgetItemIds': winner.budgetItemIds,
          'budgetItemAmounts': winner.budgetItemAmounts ?? <String, double>{},
          'sourceDocumentId': winner.id,
          if (winner.vendorId != null) 'vendorId': winner.vendorId,
        },
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            UserFacingError.uiMessage(e, action: 'start the purchase order'),
          ),
        ),
      );
    }
  }

  Future<void> _cancelPackage() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel this bid package?'),
        content: const Text(
          'All outstanding vendor bid requests will be withdrawn. This '
          'cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Cancel package'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ServiceLocator.bidPackageService.cancelPackage(
        packageId: widget.packageId,
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = UserFacingError.uiMessage(e, action: 'cancel the package');
      });
    }
  }

  String _vendorName(GeneratedDocument doc) {
    final vid = doc.vendorId;
    if (vid == null) return 'Vendor';
    return _vendorsById[vid]?.companyName ?? 'Vendor';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_package?.name ?? 'Bid Package'),
        actions: [
          if (_package != null && !_package!.isTerminal)
            IconButton(
              icon: const Icon(Icons.cancel_outlined),
              tooltip: 'Cancel package',
              onPressed: _busy ? null : _cancelPackage,
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null && _package == null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.xl),
                    child: Text(
                      _error!,
                      style: TextStyle(color: AppColors.error),
                    ),
                  ),
                )
              : _content(),
    );
  }

  Widget _content() {
    final pkg = _package!;
    final rows = _templateRows;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.base),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _headerCard(pkg),
          const SizedBox(height: 16),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                _error!,
                style: TextStyle(color: AppColors.error),
              ),
            ),
          if (_children.isEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.xl),
                child: Text(
                  'No vendor RFBs are attached to this package.',
                  style: TextStyle(color: AppColors.textSecondary),
                ),
              ),
            )
          else
            _comparisonCard(rows),
        ],
      ),
    );
  }

  Widget _headerCard(BidPackage pkg) {
    final statusColor = _packageStatusColor(pkg.status);
    return Card(
      color: statusColor.withValues(alpha: 0.06),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.base),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    pkg.name,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: AppSpacing.xs,
                  ),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    pkg.status.displayName,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: statusColor,
                    ),
                  ),
                ),
              ],
            ),
            if (pkg.scopeDescription != null &&
                pkg.scopeDescription!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                pkg.scopeDescription!,
                style: TextStyle(color: AppColors.textSecondary),
              ),
            ],
            if (pkg.dueDate != null) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(
                    Icons.event_outlined,
                    size: 16,
                    color: AppColors.textTertiary,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Due ${DateFormat.yMMMd().format(pkg.dueDate!)}',
                    style: TextStyle(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ],
            if (pkg.status == BidPackageStatus.awarded) ...[
              const SizedBox(height: 12),
              if (_awardPurchaseOrders.isNotEmpty)
                OutlinedButton.icon(
                  onPressed: () => context.push(
                    '/documents/${_awardPurchaseOrders.first.id}',
                  ),
                  icon: const Icon(Icons.receipt_long_outlined, size: 18),
                  label: Text(
                    'View Purchase Order'
                    '${_awardPurchaseOrders.first.documentNumber != null ? ' ${_awardPurchaseOrders.first.documentNumber}' : ''}',
                  ),
                )
              else
                FilledButton.icon(
                  onPressed: _busy ? null : _createPurchaseOrderFromAward,
                  icon: const Icon(Icons.receipt_long_outlined, size: 18),
                  label: const Text('Create Purchase Order'),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _comparisonCard(List<_TemplateRow> rows) {
    final responders = _children
        .where((d) => d.status == DocumentStatus.responded ||
            d.status == DocumentStatus.applied ||
            d.status == DocumentStatus.notSelected)
        .toList();
    final lowest = _lowestBidTotal(responders);
    final internalTotal = _internalTotal(rows);
    final isAwarded = _package!.status == BidPackageStatus.awarded;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minWidth: MediaQuery.of(context).size.width - 32,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _headerRow(isAwarded: isAwarded),
              for (final row in rows) _dataRow(row),
              _totalsRow(internalTotal, lowest, isAwarded: isAwarded),
              if (!isAwarded) _awardButtons(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _headerRow({required bool isAwarded}) {
    return Container(
      color: AppColors.surfaceAlt,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 10),
      child: Row(
        children: [
          SizedBox(width: 240, child: _headerText('Description')),
          SizedBox(width: 80, child: _headerText('Qty', right: true)),
          SizedBox(
            width: 120,
            child: _headerText('Internal est.', right: true),
          ),
          for (final doc in _children) _vendorHeader(doc, isAwarded: isAwarded),
        ],
      ),
    );
  }

  Widget _headerText(String label, {bool right = false}) {
    return Text(
      label,
      textAlign: right ? TextAlign.right : TextAlign.left,
      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
    );
  }

  Widget _vendorHeader(
    GeneratedDocument doc, {
    required bool isAwarded,
  }) {
    final isWinner = isAwarded && _package!.awardedDocumentId == doc.id;
    return Container(
      width: 140,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (isWinner) ...[
                Icon(
                  Icons.emoji_events,
                  size: 14,
                  color: AppColors.warning,
                ),
                const SizedBox(width: 4),
              ],
              Flexible(
                child: Text(
                  _vendorName(doc),
                  textAlign: TextAlign.right,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          _statusPill(doc.status),
        ],
      ),
    );
  }

  Widget _statusPill(DocumentStatus status) {
    final color = _docStatusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        status.displayName,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }

  Widget _dataRow(_TemplateRow row) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 10),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: AppColors.cardBorder),
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 240,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  row.name,
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
                if (row.description != null && row.description!.isNotEmpty)
                  Text(
                    row.description!,
                    style: TextStyle(
                      fontSize: 11,
                      color: AppColors.textSecondary,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          SizedBox(
            width: 80,
            child: Text(
              row.quantity == row.quantity.roundToDouble()
                  ? '${row.quantity.toInt()}${row.unit != null ? ' ${row.unit}' : ''}'
                  : '${row.quantity.toStringAsFixed(2)}${row.unit != null ? ' ${row.unit}' : ''}',
              textAlign: TextAlign.right,
              style: const TextStyle(fontSize: 13),
            ),
          ),
          SizedBox(
            width: 120,
            child: Text(
              _currencyFormatter
                  .format(row.internalUnitPrice * row.quantity),
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          for (final doc in _children) _vendorCell(doc, row),
        ],
      ),
    );
  }

  Widget _vendorCell(GeneratedDocument doc, _TemplateRow row) {
    final bid = _vendorBidForRow(doc, row);
    return SizedBox(
      width: 140,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            bid?.bidTotal == null
                ? '—'
                : _currencyFormatter.format(bid!.bidTotal),
            textAlign: TextAlign.right,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: bid?.bidTotal == null ? AppColors.textTertiary : null,
            ),
          ),
          if (bid?.lineItem.vendorBidNote != null &&
              bid!.lineItem.vendorBidNote!.isNotEmpty)
            Text(
              '"${bid.lineItem.vendorBidNote}"',
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 10,
                fontStyle: FontStyle.italic,
                color: AppColors.textSecondary,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
        ],
      ),
    );
  }

  Widget _totalsRow(
    double internalTotal,
    double? lowestTotal, {
    required bool isAwarded,
  }) {
    return Container(
      color: AppColors.primarySurface,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.md),
      child: Row(
        children: [
          const SizedBox(width: 240, child: Text(
            'Totals',
            style: TextStyle(fontWeight: FontWeight.w700),
          )),
          const SizedBox(width: 80),
          SizedBox(
            width: 120,
            child: Text(
              _currencyFormatter.format(internalTotal),
              textAlign: TextAlign.right,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          for (final doc in _children)
            _vendorTotalCell(doc, internalTotal, lowestTotal),
        ],
      ),
    );
  }

  Widget _vendorTotalCell(
    GeneratedDocument doc,
    double internalTotal,
    double? lowestTotal,
  ) {
    final total = _vendorTotal(doc);
    final hasBid = total > 0;
    final varianceVsEstimate =
        internalTotal > 0 ? (total - internalTotal) / internalTotal : null;
    final deltaVsLow =
        lowestTotal != null && hasBid ? total - lowestTotal : null;

    return SizedBox(
      width: 140,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            hasBid ? _currencyFormatter.format(total) : '—',
            textAlign: TextAlign.right,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: hasBid ? AppColors.primary : AppColors.textTertiary,
            ),
          ),
          if (varianceVsEstimate != null && hasBid)
            Text(
              '${varianceVsEstimate >= 0 ? '+' : ''}'
              '${(varianceVsEstimate * 100).toStringAsFixed(1)}% vs est.',
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 10,
                color: varianceVsEstimate > 0
                    ? AppColors.error
                    : AppColors.success,
              ),
            ),
          if (deltaVsLow != null && deltaVsLow > 0)
            Text(
              '+${_currencyFormatter.format(deltaVsLow)} vs low',
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 10,
                color: AppColors.textSecondary,
              ),
            ),
        ],
      ),
    );
  }

  Widget _awardButtons() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.md),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.cardBorder)),
      ),
      child: Row(
        children: [
          const SizedBox(width: 240 + 80 + 120),
          for (final doc in _children)
            SizedBox(
              width: 140,
              child: _awardButtonFor(doc),
            ),
        ],
      ),
    );
  }

  Widget _awardButtonFor(GeneratedDocument doc) {
    final canAward = doc.status == DocumentStatus.responded;
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: FilledButton.tonalIcon(
        onPressed: canAward && !_busy ? () => _awardVendor(doc) : null,
        icon: _busy
            ? const SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.emoji_events_outlined, size: 14),
        label: const Text('Award', style: TextStyle(fontSize: 12)),
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
          minimumSize: const Size(0, 32),
        ),
      ),
    );
  }

  Color _packageStatusColor(BidPackageStatus status) {
    switch (status) {
      case BidPackageStatus.draft:
        return AppColors.textTertiary;
      case BidPackageStatus.sent:
        return AppColors.info;
      case BidPackageStatus.awarded:
        return AppColors.success;
      case BidPackageStatus.expired:
      case BidPackageStatus.cancelled:
        return AppColors.textTertiary;
    }
  }

  Color _docStatusColor(DocumentStatus status) {
    switch (status) {
      case DocumentStatus.draft:
        return AppColors.textTertiary;
      case DocumentStatus.sent:
      case DocumentStatus.responded:
        return AppColors.info;
      case DocumentStatus.applied:
      case DocumentStatus.signed:
      case DocumentStatus.approved:
        return AppColors.success;
      case DocumentStatus.viewed:
      case DocumentStatus.pending:
      case DocumentStatus.changesRequested:
        return AppColors.warning;
      case DocumentStatus.denied:
        return AppColors.error;
      case DocumentStatus.notSelected:
      case DocumentStatus.withdrawn:
        return AppColors.textTertiary;
    }
  }
}

/// One row in the comparison grid, shared across all vendor columns.
class _TemplateRow {
  final String templateLineItemId;
  final String name;
  final String? description;
  final double quantity;
  final String? unit;
  final double internalUnitPrice;

  _TemplateRow({
    required this.templateLineItemId,
    required this.name,
    this.description,
    required this.quantity,
    this.unit,
    required this.internalUnitPrice,
  });
}

class _VendorBid {
  final DocumentLineItem lineItem;
  final double? bidPrice;
  final double? bidTotal;

  _VendorBid({
    required this.lineItem,
    required this.bidPrice,
    required this.bidTotal,
  });
}

/// Deep link used from the ordinary document detail screen for RFBs that
/// belong to a bid package. Replaces the inline BidReviewPanel.
class BidPackageBanner extends StatelessWidget {
  const BidPackageBanner({super.key, required this.packageId});

  final String packageId;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      color: AppColors.info.withValues(alpha: 0.06),
      child: InkWell(
        onTap: () => context.push('/bid-packages/$packageId'),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.base),
          child: Row(
            children: [
              Icon(Icons.view_column_outlined, color: AppColors.info),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Part of a multi-vendor bid package',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: AppColors.info,
                      ),
                    ),
                    Text(
                      'Compare every vendor\'s bid and award a winner from '
                      'the package view.',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: AppColors.info),
            ],
          ),
        ),
      ),
    );
  }
}
