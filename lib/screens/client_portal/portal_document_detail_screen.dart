import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/document_activity.dart';
import '../../models/document_status.dart';
import '../../models/document_type.dart';
import '../../models/generated_document.dart';
import '../../services/service_locator.dart';
import '../../theme/theme.dart';
import '../../utils/user_facing_error.dart';
import 'portal_preview_scope.dart';

/// Full document detail view for portal clients with approval actions.
class PortalDocumentDetailScreen extends StatefulWidget {
  final String documentId;

  const PortalDocumentDetailScreen({super.key, required this.documentId});

  @override
  State<PortalDocumentDetailScreen> createState() =>
      _PortalDocumentDetailScreenState();
}

class _PortalDocumentDetailScreenState
    extends State<PortalDocumentDetailScreen> {
  final dynamic _portalService = ServiceLocator.clientPortalService;

  bool _isLoading = true;
  bool _isActioning = false;
  String? _activeAction; // 'sign', 'deny', 'changes'
  String? _error;
  GeneratedDocument? _document;
  List<DocumentActivity> _activity = [];

  static final _currencyFormat = NumberFormat.currency(symbol: '\$');
  static final _dateFormat = DateFormat('MM/dd/yyyy');
  static final _dateTimeFormat = DateFormat('MM/dd/yyyy h:mm a');

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final preview = PortalPreviewScope.of(context);
      final docFuture = _portalService.getPortalDocument(
        widget.documentId,
        previewCustomerId: preview,
      );
      final activityFuture = _portalService.getPortalDocumentActivity(
        widget.documentId,
        previewCustomerId: preview,
      );
      final doc = await docFuture as GeneratedDocument?;
      final activity = await activityFuture as List<DocumentActivity>;

      if (!mounted) return;
      setState(() {
        _document = doc;
        _activity = activity;
        _error = null;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = UserFacingError.uiMessage(e, action: 'load document');
        _isLoading = false;
      });
    }
  }

  Future<void> _handleApproveAndSign() async {
    final doc = _document;
    if (doc == null) return;

    setState(() { _isActioning = true; _activeAction = 'sign'; });
    try {
      final result = await _portalService.getOrCreateSignLink(doc.id);
      final token = result['token'] as String?;
      if (token == null || token.isEmpty) {
        throw Exception('Failed to create signing link');
      }

      if (!mounted) return;
      await context.push('/sign/$token');
      // Refresh after returning from the signing screen
      if (mounted) _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            UserFacingError.uiMessage(e, action: 'create signing link'),
          ),
          backgroundColor: AppColors.error,
        ),
      );
    } finally {
      if (mounted) setState(() { _isActioning = false; _activeAction = null; });
    }
  }

  Future<void> _handleDeny() async {
    final reason = await _showDenyDialog();
    if (reason == null) return;

    setState(() { _isActioning = true; _activeAction = 'deny'; });
    try {
      await _portalService.denyDocument(
        widget.documentId,
        reason,
        actorName: _document?.preparedFor?.name,
      );
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Document denied.')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            UserFacingError.uiMessage(e, action: 'deny document'),
          ),
          backgroundColor: AppColors.error,
        ),
      );
    } finally {
      if (mounted) setState(() { _isActioning = false; _activeAction = null; });
    }
  }

  Future<void> _handleRequestChanges() async {
    final reason = await _showReasonDialog(
      'Request Changes',
      'What changes are needed?',
    );
    if (reason == null) return;

    setState(() { _isActioning = true; _activeAction = 'changes'; });
    try {
      await _portalService.requestDocumentChanges(
        widget.documentId,
        reason,
        actorName: _document?.preparedFor?.name,
      );
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Change request submitted.')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            UserFacingError.uiMessage(e, action: 'request changes'),
          ),
          backgroundColor: AppColors.error,
        ),
      );
    } finally {
      if (mounted) setState(() { _isActioning = false; _activeAction = null; });
    }
  }

  Future<String?> _showReasonDialog(String title, String hint) async {
    final controller = TextEditingController();
    final errorNotifier = ValueNotifier<String?>(null);
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: controller,
              decoration: InputDecoration(
                hintText: hint,
                border: const OutlineInputBorder(),
              ),
              maxLines: 3,
              autofocus: true,
              onChanged: (_) => errorNotifier.value = null,
            ),
            ValueListenableBuilder<String?>(
              valueListenable: errorNotifier,
              builder: (context, error, _) {
                if (error == null) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    error,
                    style: const TextStyle(
                      color: AppColors.error,
                      fontSize: 12,
                    ),
                  ),
                );
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final text = controller.text.trim();
              if (text.isEmpty) {
                errorNotifier.value = 'Please enter a reason.';
                return;
              }
              Navigator.pop(context, text);
            },
            child: const Text('Submit'),
          ),
        ],
      ),
    );
  }

  Future<String?> _showDenyDialog() async {
    final controller = TextEditingController();
    final errorNotifier = ValueNotifier<String?>(null);
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Deny Document'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'This will deny the document and notify the sender. '
              'This action cannot be undone.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                hintText: 'Reason for denial',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
              autofocus: true,
              onChanged: (_) => errorNotifier.value = null,
            ),
            ValueListenableBuilder<String?>(
              valueListenable: errorNotifier,
              builder: (context, error, _) {
                if (error == null) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    error,
                    style: const TextStyle(
                      color: AppColors.error,
                      fontSize: 12,
                    ),
                  ),
                );
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final text = controller.text.trim();
              if (text.isEmpty) {
                errorNotifier.value = 'Please enter a reason.';
                return;
              }
              Navigator.pop(context, text);
            },
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.error,
            ),
            child: const Text('Deny Document'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go(
                PortalPreviewScope.appendPreview(context, '/portal/dashboard'),
              );
            }
          },
        ),
        title: Text(_document?.templateName ?? 'Document'),
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

    final doc = _document;
    if (doc == null) {
      return const Center(
        child: Text('You do not have access to this document.'),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(AppSpacing.base),
        children: [
          _buildHeader(doc),
          if (doc.pdfUrl != null && doc.pdfUrl!.isNotEmpty) ...[
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () async {
                final uri = Uri.tryParse(doc.pdfUrl!);
                if (uri != null) {
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                }
              },
              icon: const Icon(Icons.picture_as_pdf),
              label: const Text('View PDF'),
            ),
          ],
          const SizedBox(height: 12),
          if (doc.isDenied || doc.hasChangesRequested) ...[
            _buildStatusBanner(doc),
            const SizedBox(height: 12),
          ],
          if (doc.isSigned) ...[
            _buildSignedBanner(doc),
            const SizedBox(height: 12),
          ],
          if (doc.renderedContent.trim().isNotEmpty) ...[
            _buildContentCard(doc),
            const SizedBox(height: 12),
          ],
          if (doc.lineItems.isNotEmpty) ...[
            _buildLineItemsCard(doc),
            const SizedBox(height: 12),
            _buildTotalsCard(doc),
            const SizedBox(height: 12),
          ],
          if (doc.needsCustomerAction) ...[
            _buildActionBar(doc),
            const SizedBox(height: 12),
          ],
          if (doc.hasChangesRequested) ...[
            Card(
              color: AppColors.warningLight,
              child: const Padding(
                padding: EdgeInsets.all(AppSpacing.base),
                child: Row(
                  children: [
                    Icon(Icons.hourglass_top, color: AppColors.warning),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Your change request has been submitted. '
                        'The contractor will revise this document.',
                        style: TextStyle(color: AppColors.warningDark),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
          if (_activity.isNotEmpty) ...[
            _buildActivityTimeline(),
          ],
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildHeader(GeneratedDocument doc) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.base),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        doc.templateName,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (doc.documentNumber != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          '#${doc.documentNumber}',
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                _statusChip(doc),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(
                  Icons.category_outlined,
                  size: 16,
                  color: AppColors.textTertiary,
                ),
                const SizedBox(width: 6),
                Text(
                  doc.documentType.displayName,
                  style: const TextStyle(color: AppColors.textSecondary),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(
                  Icons.calendar_today,
                  size: 16,
                  color: AppColors.textTertiary,
                ),
                const SizedBox(width: 6),
                Text(
                  'Created ${_dateFormat.format(doc.createdAt)}',
                  style: const TextStyle(color: AppColors.textSecondary),
                ),
              ],
            ),
            if (doc.dueDate != null) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(
                    Icons.event,
                    size: 16,
                    color: AppColors.textTertiary,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Due ${_dateFormat.format(doc.dueDate!)}',
                    style: const TextStyle(color: AppColors.textSecondary),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStatusBanner(GeneratedDocument doc) {
    final isDenied = doc.isDenied;
    final color = isDenied ? AppColors.error : AppColors.warning;
    final bgColor = isDenied ? AppColors.errorLight : AppColors.warningLight;
    final icon = isDenied ? Icons.cancel : Icons.edit_note;
    final title = isDenied ? 'Document Denied' : 'Changes Requested';
    final byName = doc.deniedByName ?? doc.deniedByEmail ?? '';

    return Card(
      color: bgColor,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.base),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: color,
                    ),
                  ),
                  if (byName.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      'By $byName',
                      style: TextStyle(color: color, fontSize: 13),
                    ),
                  ],
                  if (doc.denialReason != null &&
                      doc.denialReason!.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      doc.denialReason!,
                      style: const TextStyle(fontSize: 14),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSignedBanner(GeneratedDocument doc) {
    return Card(
      color: AppColors.successLight,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.base),
        child: Row(
          children: [
            const Icon(Icons.check_circle, color: AppColors.success, size: 24),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Document Signed',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: AppColors.success,
                    ),
                  ),
                  if (doc.signedByName != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Signed by ${doc.signedByName}${doc.signedAt != null ? ' on ${_dateFormat.format(doc.signedAt!)}' : ''}',
                      style: const TextStyle(
                        color: AppColors.successDark,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContentCard(GeneratedDocument doc) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.base),
        child: MarkdownBody(data: doc.renderedContent),
      ),
    );
  }

  Widget _buildLineItemsCard(GeneratedDocument doc) {
    final visibleItems =
        doc.lineItems.where((item) => item.isVisible && item.isItem).toList();
    if (visibleItems.isEmpty) return const SizedBox.shrink();

    return Card(
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
            ...visibleItems.map(
              (item) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        item.name,
                        style: const TextStyle(fontWeight: FontWeight.w500),
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
    );
  }

  Widget _buildTotalsCard(GeneratedDocument doc) {
    final subtotal = doc.lineItemsTotal;
    final taxAmount = doc.computedTaxAmount; // per-line taxability [M002]
    final total = subtotal + taxAmount;
    final retainagePercent =
        (doc.metadata['retainagePercent'] as num?)?.toDouble() ?? 0.0;
    final retainageAmount = total * (retainagePercent / 100);
    final amountDue = total - retainageAmount;

    return Card(
      color: AppColors.infoLight,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.base),
        child: Column(
          children: [
            _moneyRow('Subtotal', _currencyFormat.format(subtotal)),
            if (doc.collectTax && doc.taxRate > 0)
              _moneyRow(
                'Tax (${doc.taxRate.toStringAsFixed(1)}%)',
                _currencyFormat.format(taxAmount),
              ),
            if (retainagePercent > 0)
              _moneyRow(
                'Retainage Held',
                '-${_currencyFormat.format(retainageAmount)}',
                valueColor: AppColors.warning,
              ),
            const Divider(),
            _moneyRow(
              'Amount Due',
              _currencyFormat.format(amountDue),
              isBold: true,
              valueColor: AppColors.success,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionBar(GeneratedDocument doc) {
    const spinnerSize = SizedBox(
      width: 16,
      height: 16,
      child: CircularProgressIndicator(strokeWidth: 2),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilledButton.icon(
          onPressed:
              (_isActioning || PortalPreviewScope.of(context) != null)
                  ? null
                  : _handleApproveAndSign,
          icon: _activeAction == 'sign'
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.draw),
          label: const Text('Approve & Sign'),
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.success,
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed:
                    (_isActioning || PortalPreviewScope.of(context) != null)
                        ? null
                        : _handleRequestChanges,
                icon: _activeAction == 'changes'
                    ? spinnerSize
                    : const Icon(Icons.edit_note),
                label: const Text('Request Changes'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed:
                    (_isActioning || PortalPreviewScope.of(context) != null)
                        ? null
                        : _handleDeny,
                icon: _activeAction == 'deny'
                    ? spinnerSize
                    : const Icon(Icons.cancel, color: AppColors.error),
                label: Text(
                  'Deny',
                  style: TextStyle(
                    color: _activeAction == 'deny' ? null : AppColors.error,
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(
                    color: _activeAction == 'deny'
                        ? Theme.of(context).disabledColor
                        : AppColors.error,
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildActivityTimeline() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.base),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Activity',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            ..._activity.map((entry) {
              final reason = entry.details['reason'] as String?;
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      entry.displayIcon,
                      size: 20,
                      color: entry.displayColor,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            entry.displayTitle,
                            style: const TextStyle(fontWeight: FontWeight.w500),
                          ),
                          if (reason != null && reason.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              reason,
                              style: const TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 13,
                              ),
                            ),
                          ],
                          const SizedBox(height: 2),
                          Text(
                            _dateTimeFormat.format(entry.createdAt),
                            style: const TextStyle(
                              color: AppColors.textTertiary,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
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

  Widget _moneyRow(
    String label,
    String value, {
    bool isBold = false,
    Color? valueColor,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: isBold ? 16 : 14,
              fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: isBold ? 18 : 14,
              fontWeight: isBold ? FontWeight.bold : FontWeight.w600,
              color: valueColor,
            ),
          ),
        ],
      ),
    );
  }

  String _statusLabel(GeneratedDocument doc) {
    if (doc.paidDate != null) return 'Paid';
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
