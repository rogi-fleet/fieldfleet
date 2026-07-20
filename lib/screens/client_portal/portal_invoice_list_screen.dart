import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../models/document_status.dart';
import '../../models/generated_document.dart';
import '../../models/portal_invoice_summary.dart';
import '../../services/service_locator.dart';
import '../../theme/theme.dart';
import '../../utils/user_facing_error.dart';
import '../../widgets/common/list_skeleton.dart';
import 'portal_preview_scope.dart';

/// Global invoice list for portal clients across all accessible projects.
class PortalInvoiceListScreen extends StatefulWidget {
  const PortalInvoiceListScreen({super.key});

  @override
  State<PortalInvoiceListScreen> createState() =>
      _PortalInvoiceListScreenState();
}

class _PortalInvoiceListScreenState extends State<PortalInvoiceListScreen> {
  final dynamic _portalService = ServiceLocator.clientPortalService;

  bool _isLoading = true;
  String? _error;
  List<PortalInvoiceSummary> _invoices = [];

  static final _currencyFormat = NumberFormat.currency(symbol: '\$');
  static final _dateFormat = DateFormat('MM/dd/yyyy');

  @override
  void initState() {
    super.initState();
    _loadInvoices();
  }

  Future<void> _loadInvoices() async {
    try {
      final preview = PortalPreviewScope.of(context);
      final invoices =
          await _portalService.getPortalInvoices(previewCustomerId: preview);
      if (!mounted) return;
      setState(() {
        _invoices = List<PortalInvoiceSummary>.from(invoices);
        _isLoading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = UserFacingError.uiMessage(e, action: 'load invoices');
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go(
            PortalPreviewScope.appendPreview(context, '/portal/dashboard'),
          ),
        ),
        title: const Text('Invoices'),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const ListSkeleton();
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 64, color: AppColors.error),
              const SizedBox(height: 12),
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _loadInvoices,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    if (_invoices.isEmpty) {
      return RefreshIndicator(
        onRefresh: _loadInvoices,
        child: ListView(
          children: const [
            SizedBox(height: 120),
            Icon(Icons.receipt_long, size: 64, color: AppColors.textTertiary),
            SizedBox(height: 12),
            Center(
              child: Text(
                'No invoices available yet',
                style: TextStyle(fontSize: 18, color: AppColors.textSecondary),
              ),
            ),
          ],
        ),
      );
    }

    final outstandingCount = _invoices
        .where((row) => _isOutstanding(row.invoice))
        .length;

    return RefreshIndicator(
      onRefresh: _loadInvoices,
      child: ListView(
        padding: const EdgeInsets.all(AppSpacing.base),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.base),
              child: Row(
                children: [
                  Expanded(
                    child: _summaryTile(
                      title: 'Total',
                      value: _invoices.length.toString(),
                      color: AppColors.info,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _summaryTile(
                      title: 'Outstanding',
                      value: outstandingCount.toString(),
                      color: AppColors.warning,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          ..._invoices.map((row) {
            final invoice = row.invoice;
            final amountDue = _calculateAmountDue(invoice);
            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: _statusColor(
                    invoice,
                  ).withValues(alpha: 0.2),
                  child: Icon(
                    Icons.receipt,
                    color: _statusColor(invoice),
                  ),
                ),
                title: Text(invoice.documentNumber ?? ''),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if ((row.projectName ?? '').isNotEmpty)
                      Text(
                        row.projectName!,
                        style: const TextStyle(fontWeight: FontWeight.w500),
                      ),
                    if (invoice.dueDate != null)
                      Text('Due ${_dateFormat.format(invoice.dueDate!)}'),
                  ],
                ),
                trailing: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      _currencyFormat.format(amountDue),
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.sm,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: _statusColor(
                          invoice,
                        ).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        _statusLabel(invoice),
                        style: TextStyle(
                          fontSize: 11,
                          color: _statusColor(invoice),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                onTap: () => context.go(
                  PortalPreviewScope.appendPreview(
                    context,
                    '/portal/invoices/${invoice.id}',
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _summaryTile({
    required String title,
    required String value,
    required Color color,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(color: AppColors.textSecondary)),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }

  bool _isOutstanding(GeneratedDocument doc) {
    return doc.status == DocumentStatus.sent && doc.paidDate == null;
  }

  double _calculateAmountDue(GeneratedDocument doc) {
    final total = doc.computedGrandTotal; // canonical incl. discount [M004]
    final retainagePercent = (doc.metadata['retainagePercent'] as num?)?.toDouble() ?? 0.0;
    final retainageAmount = total * (retainagePercent / 100);
    return (total - retainageAmount - doc.amountPaid)
        .clamp(0.0, double.infinity);
  }

  String _statusLabel(GeneratedDocument doc) {
    if (doc.paidDate != null) return 'Paid';
    if (doc.amountPaid > 0) return 'Partially Paid';
    if ((doc.status == DocumentStatus.sent ||
            doc.status == DocumentStatus.viewed) &&
        doc.dueDate != null &&
        DateTime.now().isAfter(doc.dueDate!)) {
      return 'Overdue';
    }
    return doc.status.displayName;
  }

  Color _statusColor(GeneratedDocument doc) {
    if (doc.paidDate != null) return AppColors.success;
    if (doc.amountPaid > 0) return AppColors.info;
    if ((doc.status == DocumentStatus.sent ||
            doc.status == DocumentStatus.viewed) &&
        doc.dueDate != null &&
        DateTime.now().isAfter(doc.dueDate!)) {
      return AppColors.error;
    }
    switch (doc.status) {
      case DocumentStatus.draft:
        return AppColors.textTertiary;
      case DocumentStatus.sent:
        return AppColors.info;
      case DocumentStatus.viewed:
        return AppColors.info;
      case DocumentStatus.signed:
        return AppColors.success;
      case DocumentStatus.denied:
        return AppColors.error;
      case DocumentStatus.changesRequested:
        return AppColors.warning;
      case DocumentStatus.pending:
        return AppColors.warning;
      case DocumentStatus.approved:
        return AppColors.financialAccent;
      case DocumentStatus.responded:
        return AppColors.info;
      case DocumentStatus.applied:
        return AppColors.success;
      case DocumentStatus.notSelected:
      case DocumentStatus.withdrawn:
        return AppColors.textTertiary;
    }
  }
}
