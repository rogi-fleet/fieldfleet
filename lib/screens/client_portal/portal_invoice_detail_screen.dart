import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/document_status.dart';
import '../../models/document_type.dart';
import '../../models/generated_document.dart';
import '../../services/service_locator.dart';
import '../../theme/theme.dart';
import '../../utils/user_facing_error.dart';
import 'portal_preview_scope.dart';

/// Full invoice detail view for portal clients.
class PortalInvoiceDetailScreen extends StatefulWidget {
  final String invoiceId;

  const PortalInvoiceDetailScreen({super.key, required this.invoiceId});

  @override
  State<PortalInvoiceDetailScreen> createState() =>
      _PortalInvoiceDetailScreenState();
}

class _PortalInvoiceDetailScreenState extends State<PortalInvoiceDetailScreen> {
  final dynamic _portalService = ServiceLocator.clientPortalService;

  bool _isLoading = true;
  bool _isPaying = false;
  String? _error;
  GeneratedDocument? _invoice;
  String? _projectName;

  static final _currencyFormat = NumberFormat.currency(symbol: '\$');
  static final _dateFormat = DateFormat('MM/dd/yyyy');

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final preview = PortalPreviewScope.of(context);
      final invoice = await _portalService.getPortalInvoice(
        widget.invoiceId,
        previewCustomerId: preview,
      );
      String? projectName;
      if (invoice != null && invoice.projectId != null) {
        final project = await _portalService.getPortalProject(
          invoice.projectId,
          previewCustomerId: preview,
        );
        projectName = project?.name;
      }

      if (!mounted) return;
      setState(() {
        _invoice = invoice;
        _projectName = projectName;
        _error = null;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = UserFacingError.uiMessage(e, action: 'load invoice details');
        _isLoading = false;
      });
    }
  }

  Future<void> _handlePayNow() async {
    final invoice = _invoice;
    if (invoice == null) return;

    setState(() => _isPaying = true);
    try {
      var paymentUrl = invoice.metadata['stripePaymentLinkUrl'] as String?;
      if (paymentUrl == null || paymentUrl.isEmpty) {
        paymentUrl = await _portalService.ensurePortalPaymentLink(invoice.id);
      }

      final uri = Uri.tryParse(paymentUrl ?? '');
      if (uri == null) {
        throw Exception('Invalid payment URL');
      }

      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (!launched) {
        throw Exception('Unable to open payment page');
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Payment page opened in your browser.')),
        );
      }

      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            UserFacingError.uiMessage(e, action: 'open payment page'),
          ),
          backgroundColor: AppColors.error,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isPaying = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go(
            PortalPreviewScope.appendPreview(context, '/portal/invoices'),
          ),
        ),
        title: const Text('Invoice Details'),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
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
              ElevatedButton(onPressed: _load, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }

    final invoice = _invoice;
    if (invoice == null) {
      return const Center(
        child: Text('You do not have access to this invoice.'),
      );
    }

    final subtotal = invoice.lineItemsTotal;
    final taxAmount = invoice.computedTaxAmount; // per-line taxability [M002]
    final total = invoice.computedGrandTotal; // canonical incl. discount [M004]
    final retainagePercent = (invoice.metadata['retainagePercent'] as num?)?.toDouble() ?? 0.0;
    final retainageAmount = total * (retainagePercent / 100);
    final amountPaid = invoice.amountPaid;
    final amountDue =
        (total - retainageAmount - amountPaid).clamp(0.0, double.infinity);

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(AppSpacing.base),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.base),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          invoice.documentNumber ?? '',
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      _statusChip(invoice),
                    ],
                  ),
                  if ((_projectName ?? '').isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      _projectName!,
                      style: const TextStyle(
                        fontSize: 14,
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  if (invoice.dueDate != null)
                    _detailRow('Due Date', _dateFormat.format(invoice.dueDate!)),
                  if (invoice.paidDate != null)
                    _detailRow('Paid Date', _dateFormat.format(invoice.paidDate!)),
                  _detailRow('Type', invoice.documentType.displayName),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.base),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Line Items',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  if (invoice.lineItems.isEmpty)
                    const Text(
                      'No line items',
                      style: TextStyle(color: AppColors.textTertiary),
                    )
                  else
                    ...invoice.lineItems.where((item) => item.isVisible && item.isItem).map(
                      (item) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                item.name,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Text(item.formattedTotal),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            color: AppColors.infoLight,
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.base),
              child: Column(
                children: [
                  _moneyRow('Subtotal', _currencyFormat.format(subtotal)),
                  if (invoice.discountAmount > 0)
                    _moneyRow(
                      'Discount',
                      '-${_currencyFormat.format(invoice.discountAmount)}',
                      valueColor: AppColors.success,
                    ),
                  if (invoice.collectTax && invoice.taxRate > 0)
                    _moneyRow(
                      'Tax (${invoice.taxRate.toStringAsFixed(1)}%)',
                      _currencyFormat.format(taxAmount),
                    ),
                  if (retainagePercent > 0)
                    _moneyRow(
                      'Retainage Held',
                      '-${_currencyFormat.format(retainageAmount)}',
                      valueColor: AppColors.warning,
                    ),
                  if (amountPaid > 0)
                    _moneyRow(
                      'Paid to Date',
                      '-${_currencyFormat.format(amountPaid)}',
                      valueColor: AppColors.info,
                    ),
                  const Divider(),
                  _moneyRow(
                    amountPaid > 0 ? 'Balance Due' : 'Amount Due',
                    _currencyFormat.format(amountDue),
                    isBold: true,
                    valueColor: AppColors.success,
                  ),
                ],
              ),
            ),
          ),
          if (invoice.renderedContent.trim().isNotEmpty) ...[
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.base),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Notes',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Text(invoice.renderedContent),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 20),
          if (_showPayNow(invoice))
            ElevatedButton.icon(
              onPressed: (_isPaying || PortalPreviewScope.of(context) != null)
                  ? null
                  : _handlePayNow,
              icon: _isPaying
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.open_in_new),
              label: const Text('Pay Now'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.info,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          if (!_showPayNow(invoice) && invoice.paidDate == null)
            const Text(
              'Online payment is unavailable for this invoice status.',
              style: TextStyle(color: AppColors.textSecondary),
              textAlign: TextAlign.center,
            ),
        ],
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          SizedBox(
            width: 90,
            child: Text(
              label,
              style: const TextStyle(color: AppColors.textSecondary),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }

  Widget _moneyRow(
    String label,
    String value, {
    bool isBold = false,
    Color? valueColor,
  }) {
    final labelStyle = TextStyle(
      fontSize: isBold ? 16 : 14,
      fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
    );

    final valueStyle = TextStyle(
      fontSize: isBold ? 18 : 14,
      fontWeight: isBold ? FontWeight.bold : FontWeight.w600,
      color: valueColor,
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: labelStyle),
          Text(value, style: valueStyle),
        ],
      ),
    );
  }

  Widget _statusChip(GeneratedDocument doc) {
    final color = _statusColor(doc);
    final label = _statusLabel(doc);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: AppSpacing.xs),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(color: color, fontWeight: FontWeight.w600),
      ),
    );
  }

  bool _showPayNow(GeneratedDocument doc) {
    return (doc.status == DocumentStatus.sent ||
            doc.status == DocumentStatus.viewed) &&
        doc.paidDate == null;
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
