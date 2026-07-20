import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/document_status.dart';
import '../../models/document_type.dart';
import '../../models/file_attachment.dart';
import '../../models/generated_document.dart';
import '../../models/template_category.dart';
import '../../models/portal_invoice_summary.dart';
import '../../models/project.dart';
import '../../models/selection.dart';
import '../../models/project_status_theme.dart';
import '../../services/service_locator.dart';
import '../../widgets/forms/signature_dialog.dart';
import '../../theme/theme.dart';
import '../../utils/app_logger.dart';
import '../../utils/user_facing_error.dart';
import '../../widgets/adaptive_navigation.dart';
import 'portal_messages_tab.dart';
import 'portal_preview_scope.dart';

/// Client portal view of a specific project.
/// Shows project details, documents, photos, and invoices.
class PortalProjectScreen extends StatefulWidget {
  final String projectId;

  const PortalProjectScreen({super.key, required this.projectId});

  @override
  State<PortalProjectScreen> createState() => _PortalProjectScreenState();
}

class _PortalProjectScreenState extends State<PortalProjectScreen>
    with SingleTickerProviderStateMixin {
  final dynamic _portalService = ServiceLocator.clientPortalService;
  final _storageService = ServiceLocator.storageService;

  Project? _project;
  int _pendingDocCount = 0;
  List<GeneratedDocument> _documents = [];
  List<FileAttachment> _photos = [];
  List<PortalInvoiceSummary> _invoices = [];
  List<Selection> _selections = [];
  int _pendingSelectionCount = 0;
  List<Map<String, dynamic>> _activity = [];
  bool _isLoading = true;
  String? _error;
  final Set<String> _partialErrors = {};
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 7, vsync: this);
    _tabController.addListener(_onTabSwitch);
    _loadData();
  }

  void _onTabSwitch() {
    if (!_tabController.indexIsChanging) {
      TabSwitchNotification().dispatch(context);
    }
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabSwitch);
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    try {
      final preview = PortalPreviewScope.of(context);
      final project = await _portalService.getPortalProject(
        widget.projectId,
        previewCustomerId: preview,
      );
      List<GeneratedDocument> documents = [];
      List<FileAttachment> photos = [];
      List<PortalInvoiceSummary> invoices = [];
      List<Selection> selections = [];
      List<Map<String, dynamic>> activity = [];

      if (project != null) {
        try {
          final portalInvoices = await _portalService.getPortalInvoices(
            projectId: project.id,
            previewCustomerId: preview,
          );
          invoices = List<PortalInvoiceSummary>.from(portalInvoices);
        } catch (e) {
          AppLogger.warning(
            'Portal invoices unavailable in project view',
            metadata: {'projectId': project.id, 'error': e.toString()},
          );
        }

        try {
          documents = await _portalService.getPortalProjectDocuments(
            project.id,
            previewCustomerId: preview,
          ) as List<GeneratedDocument>;
        } catch (e) {
          AppLogger.warning(
            'Portal documents unavailable in project view',
            metadata: {'projectId': project.id, 'error': e.toString()},
          );
          documents = [];
          _partialErrors.add('documents');
        }

        try {
          final allFiles = await _storageService
              .getProjectFiles(project.workspaceId, project.id)
              .first;
          photos = allFiles.where((f) => f.isImage).toList();
        } catch (e) {
          AppLogger.warning(
            'Portal photos unavailable in project view',
            metadata: {'projectId': project.id, 'error': e.toString()},
          );
          photos = [];
          _partialErrors.add('photos');
        }
      }

      if (project != null) {
        try {
          selections = await _portalService.getPortalProjectSelections(
            project.id,
            previewCustomerId: preview,
          ) as List<Selection>;
        } catch (e) {
          AppLogger.warning(
            'Portal selections unavailable in project view',
            metadata: {'projectId': project.id, 'error': e.toString()},
          );
          selections = [];
          _partialErrors.add('selections');
        }

        try {
          activity = await _portalService.getPortalProjectActivity(
            project.id,
            previewCustomerId: preview,
          ) as List<Map<String, dynamic>>;
        } catch (e) {
          AppLogger.warning(
            'Portal activity feed unavailable in project view',
            metadata: {'projectId': project.id, 'error': e.toString()},
          );
          activity = [];
          _partialErrors.add('activity');
        }
      }

      if (mounted) {
        setState(() {
          _project = project;
          _documents = documents;
          _pendingDocCount = documents.where((d) => d.needsCustomerAction).length;
          _photos = photos;
          _invoices = invoices;
          _selections = selections;
          _activity = activity;
          _pendingSelectionCount = selections
              .where((s) => s.status == SelectionStatus.awaitingClient)
              .length;
          _isLoading = false;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = UserFacingError.uiMessage(e, action: 'load this project');
          _isLoading = false;
        });
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
            PortalPreviewScope.appendPreview(context, '/portal/dashboard'),
          ),
        ),
        title: Text(_project?.name ?? 'Project'),
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            const Tab(text: 'Overview'),
            const Tab(text: 'Activity'),
            Tab(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Documents'),
                  if (_pendingDocCount > 0) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.warning,
                        borderRadius: BorderRadius.circular(AppRadius.md),
                      ),
                      child: Text(
                        '$_pendingDocCount',
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const Tab(text: 'Photos'),
            const Tab(text: 'Messages'),
            const Tab(text: 'Invoices'),
            Tab(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Selections'),
                  if (_pendingSelectionCount > 0) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        color: AppColors.warning,
                        borderRadius: BorderRadius.circular(AppRadius.md),
                      ),
                      child: Text(
                        '$_pendingSelectionCount',
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Loading project…'),
          ],
        ),
      );
    }

    if (_error != null || _project == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: AppColors.error),
            const SizedBox(height: 16),
            Text(_error ?? 'Project not found'),
            const SizedBox(height: 12),
            ElevatedButton(onPressed: _loadData, child: const Text('Retry')),
          ],
        ),
      );
    }

    return Column(
      children: [
        if (_partialErrors.isNotEmpty)
          MaterialBanner(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.base, vertical: AppSpacing.sm),
            leading: const Icon(Icons.warning_amber_rounded, color: AppColors.warning),
            content: Text(
              'Some data could not be loaded: ${_partialErrors.join(', ')}.',
            ),
            actions: [
              TextButton(
                onPressed: () {
                  setState(() => _partialErrors.clear());
                  _loadData();
                },
                child: const Text('Retry'),
              ),
              TextButton(
                onPressed: () => setState(() => _partialErrors.clear()),
                child: const Text('Dismiss'),
              ),
            ],
          ),
        Expanded(
          child: TabBarView(
            physics: const NeverScrollableScrollPhysics(),
            controller: _tabController,
            children: [
              _buildOverviewTab(),
              _buildActivityTab(),
              _buildDocumentsTab(),
              _buildPhotosTab(),
              PortalMessagesTab(projectId: widget.projectId),
              _buildInvoicesTab(),
              _buildSelectionsTab(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildOverviewTab() {
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.base),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.base),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.circle,
                      size: 12,
                      color: _getStatusColor(_project!.status),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _project!.status.displayName.toUpperCase(),
                      style: TextStyle(
                        color: _getStatusColor(_project!.status),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  _project!.name,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Card(
          child: ListTile(
            leading: const Icon(Icons.location_on),
            title: const Text('Project Address'),
            subtitle: Text(_project!.address),
          ),
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.base),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Portal Summary',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const SizedBox(height: 12),
                _buildSummaryRow('Invoices', _invoices.length.toString()),
                _buildSummaryRow('Documents', _documents.length.toString()),
                _buildSummaryRow('Photos', _photos.length.toString()),
                if (_project!.startDate != null)
                  _buildSummaryRow(
                    'Start Date',
                    _formatDate(_project!.startDate!),
                  ),
                if (_project!.targetCompletionDate != null)
                  _buildSummaryRow(
                    'Target Completion',
                    _formatDate(_project!.targetCompletionDate!),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSummaryRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: AppColors.textTertiary)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  Widget _buildActivityTab() {
    if (_activity.isEmpty) {
      return RefreshIndicator(
        onRefresh: _loadData,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: const [
            SizedBox(height: 120),
            Icon(Icons.history, size: 64, color: AppColors.textTertiary),
            SizedBox(height: 16),
            Center(
              child: Text(
                'No activity yet',
                style: TextStyle(fontSize: 18, color: AppColors.textSecondary),
              ),
            ),
            SizedBox(height: 8),
            Center(
              child: Text(
                "Updates will appear here as your project progresses.",
                style: TextStyle(color: AppColors.textTertiary),
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView.separated(
        padding: const EdgeInsets.all(AppSpacing.base),
        itemCount: _activity.length,
        separatorBuilder: (_, __) => const SizedBox(height: 4),
        itemBuilder: (context, index) {
          final event = _activity[index];
          return _ActivityTile(event: event, onTap: () => _onActivityTap(event));
        },
      ),
    );
  }

  void _onActivityTap(Map<String, dynamic> event) {
    final refType = event['ref_type'] as String?;
    final refId = event['ref_id'] as String?;
    if (refId == null) return;
    switch (refType) {
      case 'document':
        context.go(
          PortalPreviewScope.appendPreview(context, '/portal/documents/$refId'),
        );
        break;
      case 'invoice':
        context.go(
          PortalPreviewScope.appendPreview(context, '/portal/invoices/$refId'),
        );
        break;
      case 'selection':
        _tabController.animateTo(6);
        break;
      default:
        break;
    }
  }

  Widget _buildDocumentsTab() {
    if (_documents.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.description_outlined,
              size: 64,
              color: AppColors.textTertiary,
            ),
            const SizedBox(height: 16),
            const Text(
              'No documents yet',
              style: TextStyle(fontSize: 18, color: AppColors.textSecondary),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(AppSpacing.base),
      itemCount: _documents.length,
      itemBuilder: (context, index) {
        final doc = _documents[index];
        final statusColor = _getDocStatusColor(doc);
        final statusLabel = _getDocStatusLabel(doc);
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: doc.documentType.category.color.withValues(alpha: 0.2),
              child: Icon(
                doc.documentType.category.icon,
                color: doc.documentType.category.color,
              ),
            ),
            title: Text(doc.templateName),
            subtitle: doc.documentNumber != null
                ? Text('#${doc.documentNumber}')
                : null,
            trailing: Container(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(AppRadius.r12),
              ),
              child: Text(
                statusLabel,
                style: TextStyle(fontSize: 12, color: statusColor),
              ),
            ),
            onTap: () => _openDocument(doc),
          ),
        );
      },
    );
  }

  void _openDocument(GeneratedDocument doc) {
    // Route payable invoices to the invoice detail screen (which has Pay Now).
    // AIA contracts live in the invoice category but are agreements, not bills,
    // so they open in the plain document viewer (no Pay Now).
    if (doc.documentType.isPayableCustomerInvoice) {
      context.go(
        PortalPreviewScope.appendPreview(context, '/portal/invoices/${doc.id}'),
      );
    } else {
      context.go(
        PortalPreviewScope.appendPreview(context, '/portal/documents/${doc.id}'),
      );
    }
  }

  Widget _buildPhotosTab() {
    if (_photos.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.photo_library_outlined,
              size: 64,
              color: AppColors.textTertiary,
            ),
            const SizedBox(height: 16),
            const Text(
              'No photos yet',
              style: TextStyle(fontSize: 18, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 8),
            const Text(
              'Project photos will appear here',
              style: TextStyle(color: AppColors.textTertiary),
            ),
          ],
        ),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.all(AppSpacing.sm),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      itemCount: _photos.length,
      itemBuilder: (context, index) {
        final photo = _photos[index];
        return GestureDetector(
          onTap: () => _showPhotoViewer(photo),
          child: Card(
            clipBehavior: Clip.antiAlias,
            child: Stack(
              fit: StackFit.expand,
              children: [
                CachedNetworkImage(
                  imageUrl: photo.fileUrl,
                  fit: BoxFit.cover,
                  errorWidget: (context, url, error) => Container(
                    color: AppColors.surfaceAlt,
                    child: const Icon(Icons.broken_image, size: 48),
                  ),
                  progressIndicatorBuilder: (context, url, progress) =>
                      Center(child: CircularProgressIndicator(value: progress.progress)),
                ),
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                    color: Colors.black54,
                    padding: const EdgeInsets.all(AppSpacing.xs),
                    child: Text(
                      _formatDate(photo.uploadedAt),
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildInvoicesTab() {
    if (_invoices.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.receipt_long,
              size: 64,
              color: AppColors.textTertiary,
            ),
            const SizedBox(height: 16),
            const Text(
              'No invoices for this project',
              style: TextStyle(fontSize: 18, color: AppColors.textSecondary),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView.builder(
        padding: const EdgeInsets.all(AppSpacing.base),
        itemCount: _invoices.length,
        itemBuilder: (context, index) {
          final row = _invoices[index];
          final invoice = row.invoice;
          final statusColor = _getDocStatusColor(invoice);
          final statusLabel = _getDocStatusLabel(invoice);
          final amountDue = _calculateAmountDue(invoice);
          final dateFormat = DateFormat('MM/dd/yyyy');
          final currencyFormat = NumberFormat.currency(symbol: '\$');
          return Card(
            margin: const EdgeInsets.only(bottom: 12),
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: statusColor.withValues(alpha: 0.2),
                child: Icon(
                  Icons.receipt,
                  color: statusColor,
                ),
              ),
              title: Text(invoice.documentNumber ?? ''),
              subtitle: invoice.dueDate != null
                  ? Text('Due ${dateFormat.format(invoice.dueDate!)}')
                  : null,
              trailing: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    currencyFormat.format(amountDue),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.sm,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      statusLabel,
                      style: TextStyle(
                        fontSize: 11,
                        color: statusColor,
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
        },
      ),
    );
  }

  Widget _buildSelectionsTab() {
    if (_selections.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.checklist_outlined, size: 64, color: AppColors.textTertiary),
            SizedBox(height: 16),
            Text('No selections yet',
                style: TextStyle(fontSize: 18, color: AppColors.textSecondary)),
            SizedBox(height: 8),
            Text("We'll notify you when there's a choice to make.",
                style: TextStyle(color: AppColors.textTertiary)),
          ],
        ),
      );
    }
    final pending = _selections
        .where((s) => s.status == SelectionStatus.awaitingClient)
        .toList();
    final decided = _selections
        .where((s) => s.status != SelectionStatus.awaitingClient)
        .toList();
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.base),
      children: [
        if (pending.isNotEmpty) ...[
          const _SectionHeader('Awaiting your choice'),
          for (final s in pending) _PortalSelectionCard(
            selection: s,
            onApprove: (opt) => _approveSelection(s, opt),
            onDecline: (reason) => _declineSelection(s, reason),
            onAddSignature: () => _addSignature(s),
            readOnly: PortalPreviewScope.of(context) != null,
          ),
          const SizedBox(height: 16),
        ],
        if (decided.isNotEmpty) ...[
          const _SectionHeader('Decisions'),
          for (final s in decided) _PortalSelectionCard(
            selection: s,
            onApprove: (_) async {},
            onDecline: (_) async {},
            onAddSignature:
                PortalPreviewScope.of(context) != null ? null : () => _addSignature(s),
            readOnly: true,
          ),
        ],
      ],
    );
  }

  Future<void> _approveSelection(Selection s, SelectionOption opt) async {
    // JobTread parity: capture an e-signature accepting the selection + cost,
    // showing the Selections Price / Allowance Deduction / Added Price breakdown.
    final money = NumberFormat.simpleCurrency(decimalDigits: 2, name: 'USD');
    final price = opt.totalCost;
    final deduction = price <= s.allowanceAmount ? price : s.allowanceAmount;
    final added = (price - s.allowanceAmount) > 0 ? price - s.allowanceAmount : 0;
    final breakdown = 'Selections price: ${money.format(price)}\n'
        'Allowance deduction: -${money.format(deduction)}\n'
        'Added price: ${money.format(added)}';

    final signed = await SignatureDialog.show(
      context,
      title: 'Approve "${opt.name}"',
      disclaimer:
          '$breakdown\n\nThe above selection and costs are hereby accepted.',
      requireEmail: false,
      onSign: (name, email, pngBytes) async {
        // 1) Approve (rolls cost into the budget via the atomic RPC).
        await _portalService.approvePortalSelection(s.id, opt.id,
            actorName: name.trim().isEmpty ? null : name.trim());
        // 2) Best-effort: upload + attach the signature.
        try {
          final url = await _storageService.uploadSignature(
            signatureBytes: pngBytes,
            workspaceId: s.workspaceId,
            documentId: 'selection_${s.id}',
          );
          await _portalService.setSelectionSignature(s.id, url);
          // Also record in the multi-signer table.
          await _portalService.addSelectionSignatureRecord(
              s.id, name, email, url);
        } catch (_) {/* signature is best-effort; approval already saved */}
      },
    );
    if (!signed) return;
    await _loadData();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Approved "${opt.name}" for ${s.name}.')),
      );
    }
  }

  /// Collect an additional e-signature on an already-approved selection
  /// (e.g. a co-signing spouse).
  Future<void> _addSignature(Selection s) async {
    await SignatureDialog.show(
      context,
      title: 'Sign "${s.name}"',
      disclaimer: 'The above selection and costs are hereby accepted.',
      requireEmail: false,
      onSign: (name, email, pngBytes) async {
        try {
          final url = await _storageService.uploadSignature(
            signatureBytes: pngBytes,
            workspaceId: s.workspaceId,
            documentId: 'selection_${s.id}',
          );
          await _portalService.addSelectionSignatureRecord(
              s.id, name, email, url);
        } catch (_) {/* best-effort */}
      },
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Signature recorded.')));
    }
  }

  Future<void> _declineSelection(Selection s, String reason) async {
    try {
      await _portalService.declinePortalSelection(s.id, reason);
      await _loadData();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(UserFacingError.uiMessage(e,
              action: 'decline this selection'))),
        );
      }
    }
  }

  void _showPhotoViewer(FileAttachment photo) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: const EdgeInsets.all(AppSpacing.base),
        child: Stack(
          children: [
            InteractiveViewer(
              child: Center(child: CachedNetworkImage(imageUrl: photo.fileUrl)),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: () => Navigator.pop(context),
              ),
            ),
            Positioned(
              bottom: 16,
              left: 16,
              right: 16,
              child: Text(
                photo.fileName,
                style: const TextStyle(color: Colors.white),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.month}/${date.day}/${date.year}';
  }

  Color _getStatusColor(ProjectStatus status) {
    return ProjectStatusTheme.color(status);
  }

  double _calculateAmountDue(GeneratedDocument doc) {
    final subtotal = doc.lineItemsTotal;
    final taxAmount = doc.computedTaxAmount; // per-line taxability [M002]
    final total = subtotal + taxAmount;
    final retainagePercent = (doc.metadata['retainagePercent'] as num?)?.toDouble() ?? 0.0;
    final retainageAmount = total * (retainagePercent / 100);
    return total - retainageAmount;
  }

  String _getDocStatusLabel(GeneratedDocument doc) {
    if (doc.paidDate != null) return 'Paid';
    if ((doc.status == DocumentStatus.sent ||
            doc.status == DocumentStatus.viewed) &&
        doc.dueDate != null &&
        DateTime.now().isAfter(doc.dueDate!)) {
      return 'Overdue';
    }
    return doc.status.displayName;
  }

  Color _getDocStatusColor(GeneratedDocument doc) {
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

// ───────────────────── Portal selection widgets ─────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String text;
  const _SectionHeader(this.text);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        child: Text(text,
            style: const TextStyle(
                fontSize: 16, fontWeight: FontWeight.w600)),
      );
}

class _PortalSelectionCard extends StatefulWidget {
  final Selection selection;
  final Future<void> Function(SelectionOption) onApprove;
  final Future<void> Function(String reason) onDecline;
  final VoidCallback? onAddSignature;
  final bool readOnly;
  const _PortalSelectionCard({
    required this.selection,
    required this.onApprove,
    required this.onDecline,
    this.onAddSignature,
    this.readOnly = false,
  });
  @override
  State<_PortalSelectionCard> createState() => _PortalSelectionCardState();
}

class _PortalSelectionCardState extends State<_PortalSelectionCard> {
  String? _selectedOptionId;
  final _currency = NumberFormat.simpleCurrency(decimalDigits: 0, name: 'USD');

  final dynamic _portalService = ServiceLocator.clientPortalService;
  List<SelectionComment> _comments = const [];
  bool _showMessages = false;
  bool _commentsLoaded = false;
  bool _sending = false;
  final TextEditingController _msgCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _selectedOptionId = widget.selection.selectedOptionId;
  }

  @override
  void dispose() {
    _msgCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadComments() async {
    try {
      final list =
          await _portalService.getSelectionComments(widget.selection.id);
      if (mounted) setState(() {
        _comments = List<SelectionComment>.from(list);
        _commentsLoaded = true;
      });
    } catch (_) {
      if (mounted) setState(() => _commentsLoaded = true);
    }
  }

  Future<void> _toggleMessages() async {
    setState(() => _showMessages = !_showMessages);
    if (_showMessages && !_commentsLoaded) await _loadComments();
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _suggestOption() async {
    final nameCtrl = TextEditingController();
    final noteCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Suggest your own option'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              autofocus: true,
              decoration: const InputDecoration(
                  labelText: 'What would you like?',
                  hintText: 'e.g. Brushed gold faucet'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: noteCtrl,
              minLines: 1,
              maxLines: 3,
              decoration: const InputDecoration(
                  labelText: 'Notes / link (optional)'),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Send to builder')),
        ],
      ),
    );
    if (ok != true || nameCtrl.text.trim().isEmpty) return;
    try {
      await _portalService.suggestSelectionOption(
          widget.selection.id, nameCtrl.text.trim(),
          noteCtrl.text.trim().isEmpty ? null : noteCtrl.text.trim());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Sent your suggestion to the builder.')));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Could not send suggestion.')));
      }
    }
  }

  String _fileName(String url) {
    final seg = Uri.tryParse(url)?.pathSegments;
    return (seg == null || seg.isEmpty) ? 'file' : seg.last;
  }

  Future<void> _sendComment() async {
    final body = _msgCtrl.text.trim();
    if (body.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await _portalService.addSelectionComment(widget.selection.id, body);
      _msgCtrl.clear();
      await _loadComments();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not send message.')));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.selection;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(
                child: Text(s.name,
                    style: const TextStyle(
                        fontSize: 17, fontWeight: FontWeight.w600)),
              ),
              _statusPill(s.status),
            ]),
            if ((s.category ?? '').isNotEmpty || (s.location ?? '').isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  [s.category, s.location]
                      .where((v) => v != null && v.isNotEmpty)
                      .join(' · '),
                  style: const TextStyle(
                      color: AppColors.textTertiary, fontSize: 12),
                ),
              ),
            const SizedBox(height: 6),
            Wrap(spacing: 8, runSpacing: 4, children: [
              _chip('Allowance ${_currency.format(s.allowanceAmount)}'),
              if (s.dueDate != null)
                _chip('Due ${DateFormat.yMMMd().format(s.dueDate!)}'),
              if (s.status == SelectionStatus.approved)
                _chip('Selected ${_currency.format(s.selectedAmount)}',
                    color: SelectionStatus.approved.color),
            ]),
            // Live allowance vs. picked-option difference (pre- and post-approval).
            Builder(builder: (_) {
              final picked = s.status == SelectionStatus.approved
                  ? s.selectedAmount
                  : (_selectedOptionId == null
                      ? null
                      : s.options
                          .firstWhere((o) => o.id == _selectedOptionId)
                          .totalCost);
              if (!s.showAmountDifferences || picked == null) {
                return const SizedBox.shrink();
              }
              final diff = picked - s.allowanceAmount;
              if (diff == 0) return const SizedBox.shrink();
              final over = diff > 0;
              final color = over ? AppColors.error : AppColors.success;
              return Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(over ? Icons.arrow_upward : Icons.arrow_downward,
                        size: 13, color: color),
                    const SizedBox(width: 3),
                    Text(
                      over
                          ? '${_currency.format(diff)} over allowance'
                          : '${_currency.format(-diff)} under allowance',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: color,
                      ),
                    ),
                  ],
                ),
              );
            }),
            if ((s.description ?? '').isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(s.description!),
            ],
            if ((s.referenceUrl ?? '').isNotEmpty ||
                s.attachmentUrls.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8, children: [
                if ((s.referenceUrl ?? '').isNotEmpty)
                  ActionChip(
                    avatar: const Icon(Icons.link, size: 16),
                    label: const Text('Reference link',
                        style: TextStyle(fontSize: 12)),
                    onPressed: () => _openUrl(s.referenceUrl!),
                  ),
                for (final url in s.attachmentUrls)
                  ActionChip(
                    avatar: const Icon(Icons.insert_drive_file_outlined,
                        size: 16),
                    label: Text(_fileName(url),
                        style: const TextStyle(fontSize: 12)),
                    onPressed: () => _openUrl(url),
                  ),
              ]),
            ],
            const SizedBox(height: 12),
            for (final opt in s.options) _option(opt),
            if (!widget.readOnly &&
                s.status == SelectionStatus.awaitingClient) ...[
              const SizedBox(height: 12),
              Row(children: [
                FilledButton.icon(
                  onPressed: _selectedOptionId == null
                      ? null
                      : () async {
                          final opt = s.options
                              .firstWhere((o) => o.id == _selectedOptionId);
                          final overage = opt.totalCost - s.allowanceAmount;
                          // Always require explicit acknowledgement of an
                          // over-allowance pick — this is a financial-safety
                          // gate, independent of show_amount_differences (which
                          // only governs the styling/labels elsewhere).
                          if (overage > 0) {
                            final ok = await _confirmOverage(context, opt, overage);
                            if (ok != true) return;
                          }
                          widget.onApprove(opt);
                        },
                  icon: const Icon(Icons.check, size: 18),
                  label: const Text('Approve choice'),
                ),
                const SizedBox(width: 8),
                TextButton.icon(
                  onPressed: () async {
                    final reason = await _askReason(context);
                    if (reason != null) widget.onDecline(reason);
                  },
                  icon: const Icon(Icons.close,
                      size: 18, color: AppColors.error),
                  label: const Text('Decline all',
                      style: TextStyle(color: AppColors.error)),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: _suggestOption,
                  icon: const Icon(Icons.lightbulb_outline, size: 18),
                  label: const Text('Suggest your own'),
                ),
              ]),
            ],
            if (s.status == SelectionStatus.approved && s.approvedAt != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Approved ${DateFormat.yMMMd().add_jm().format(s.approvedAt!)}'
                        '${s.approvedByName != null ? " by ${s.approvedByName}" : ""}',
                        style: const TextStyle(
                            color: AppColors.textTertiary, fontSize: 12),
                      ),
                    ),
                    if (widget.onAddSignature != null)
                      TextButton.icon(
                        onPressed: widget.onAddSignature,
                        icon: const Icon(Icons.draw_outlined, size: 16),
                        label: const Text('Add signature'),
                      ),
                  ],
                ),
              ),
            if (s.status == SelectionStatus.declined &&
                (s.declineReason ?? '').isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text('Reason: ${s.declineReason}',
                    style: const TextStyle(
                        color: AppColors.textSecondary, fontSize: 12)),
              ),
            const SizedBox(height: 8),
            _buildMessages(),
          ],
        ),
      ),
    );
  }

  Widget _buildMessages() {
    final fmt = DateFormat.MMMd().add_jm();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: _toggleMessages,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
            child: Row(
              children: [
                const Icon(Icons.forum_outlined,
                    size: 16, color: AppColors.textSecondary),
                const SizedBox(width: 6),
                Text(
                  _comments.isEmpty
                      ? 'Messages'
                      : 'Messages (${_comments.length})',
                  style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      color: AppColors.textSecondary),
                ),
                const Spacer(),
                Icon(_showMessages ? Icons.expand_less : Icons.expand_more,
                    size: 18, color: AppColors.textSecondary),
              ],
            ),
          ),
        ),
        if (_showMessages) ...[
          const SizedBox(height: 4),
          if (!_commentsLoaded)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: AppSpacing.sm),
              child: SizedBox(
                  height: 16,
                  width: 16,
                  child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else if (_comments.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 6),
              child: Text('No messages yet. Ask your builder a question.',
                  style: TextStyle(
                      color: AppColors.textTertiary, fontSize: 13)),
            )
          else
            ..._comments.map((c) {
              final mine = c.isFromClient;
              return Align(
                alignment:
                    mine ? Alignment.centerRight : Alignment.centerLeft,
                child: Container(
                  margin: const EdgeInsets.only(bottom: 6),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 6),
                  constraints: const BoxConstraints(maxWidth: 320),
                  decoration: BoxDecoration(
                    color: mine
                        ? AppColors.success.withValues(alpha: 0.08)
                        : AppColors.background,
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    border: Border.all(color: AppColors.cardBorder),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${c.authorName ?? (c.isFromClient ? 'You' : 'Builder')}'
                        ' · ${fmt.format(c.createdAt)}',
                        style: const TextStyle(
                            fontSize: 11, color: AppColors.textTertiary),
                      ),
                      const SizedBox(height: 2),
                      Text(c.body),
                    ],
                  ),
                ),
              );
            }),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _msgCtrl,
                  minLines: 1,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    hintText: 'Message your builder…',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  onSubmitted: (_) => _sendComment(),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                onPressed: _sending ? null : _sendComment,
                icon: const Icon(Icons.send, size: 18),
                tooltip: 'Send',
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _option(SelectionOption opt) {
    final picked = _selectedOptionId == opt.id;
    final locked = widget.readOnly ||
        widget.selection.status != SelectionStatus.awaitingClient;
    return InkWell(
      onTap: locked
          ? null
          : () => setState(() => _selectedOptionId = opt.id),
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: picked
              ? SelectionStatus.approved.color.withOpacity(0.08)
              : AppColors.surface,
          border: Border.all(
            color: picked
                ? SelectionStatus.approved.color
                : AppColors.cardBorder,
            width: picked ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (opt.primaryImage != null) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Stack(children: [
                  CachedNetworkImage(
                  imageUrl: opt.primaryImage!,
                  width: 60,
                  height: 60,
                  fit: BoxFit.cover,
                  errorWidget: (_, __, ___) => const SizedBox(
                    width: 60,
                    height: 60,
                    child: Icon(Icons.image_not_supported,
                        color: AppColors.textTertiary),
                  ),
                ),
                  if (opt.photos.length > 1)
                    Positioned(
                      right: 2,
                      bottom: 2,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.xs, vertical: 1),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(AppRadius.sm),
                        ),
                        child: Text('${opt.photos.length}',
                            style: const TextStyle(
                                color: Colors.white, fontSize: 9)),
                      ),
                    ),
                ]),
              ),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(opt.name,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  if ((opt.vendor ?? '').isNotEmpty)
                    Text(opt.vendor!,
                        style: const TextStyle(
                            color: AppColors.textTertiary, fontSize: 12)),
                  if ((opt.description ?? '').isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(opt.description!,
                        style: const TextStyle(fontSize: 13)),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(_currency.format(opt.totalCost),
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                if (opt.quantity != 1)
                  Text(
                      '${opt.quantity} × ${_currency.format(opt.unitCost)}',
                      style: const TextStyle(
                          color: AppColors.textTertiary, fontSize: 11)),
                // Per-option budget impact, shown up-front (before picking) so
                // the customer sees cost consequences while comparing. Icon +
                // text so it isn't color-only.
                if (widget.selection.showAmountDifferences &&
                    widget.selection.allowanceAmount > 0)
                  _optionDeltaLabel(
                      opt.totalCost - widget.selection.allowanceAmount),
              ],
            ),
            if (picked)
              const Padding(
                padding: EdgeInsets.only(left: 8),
                child:
                    Icon(Icons.check_circle, color: AppColors.success),
              ),
          ],
        ),
      ),
    );
  }

  /// Small "+$X over / −$X under / on budget" label for a single option.
  /// Icon + text so the meaning survives without colour.
  Widget _optionDeltaLabel(double diff) {
    if (diff == 0) {
      return const Padding(
        padding: EdgeInsets.only(top: 2),
        child: Text('On budget',
            style: TextStyle(
                fontSize: 11,
                color: AppColors.textTertiary,
                fontWeight: FontWeight.w500)),
      );
    }
    final over = diff > 0;
    final color = over ? AppColors.error : AppColors.success;
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(over ? Icons.arrow_upward : Icons.arrow_downward,
              size: 11, color: color),
          const SizedBox(width: 2),
          Text(
            over
                ? '${_currency.format(diff)} over'
                : '${_currency.format(-diff)} under',
            style: TextStyle(
                fontSize: 11, fontWeight: FontWeight.w600, color: color),
          ),
        ],
      ),
    );
  }

  IconData _statusIcon(SelectionStatus status) {
    switch (status) {
      case SelectionStatus.approved:
        return Icons.check_circle;
      case SelectionStatus.declined:
        return Icons.cancel;
      case SelectionStatus.awaitingClient:
        return Icons.schedule;
      case SelectionStatus.cancelled:
        return Icons.block;
      case SelectionStatus.pending:
        return Icons.more_horiz;
    }
  }

  Widget _statusPill(SelectionStatus status) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 2),
      decoration: BoxDecoration(
        color: status.color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_statusIcon(status), size: 12, color: status.color),
          const SizedBox(width: 4),
          Text(status.label,
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: status.color)),
        ],
      ),
    );
  }

  Widget _chip(String label, {Color? color}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 3),
      decoration: BoxDecoration(
        color: (color ?? AppColors.textSecondary).withOpacity(0.08),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 12,
              color: color ?? AppColors.textSecondary,
              fontWeight: FontWeight.w500)),
    );
  }

  Future<bool?> _confirmOverage(
      BuildContext context, SelectionOption opt, double overage) {
    final s = widget.selection;
    return showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Row(children: const [
          Icon(Icons.warning_amber_rounded, color: AppColors.error),
          SizedBox(width: 8),
          Text('Over allowance'),
        ]),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('"${opt.name}" is ${_currency.format(overage)} over your '
                'allowance for this selection.'),
            const SizedBox(height: 12),
            _overageRow('Allowance', _currency.format(s.allowanceAmount)),
            _overageRow('Your pick', _currency.format(opt.totalCost)),
            const Divider(height: 16),
            _overageRow('Difference', '+${_currency.format(overage)}',
                emphasize: true),
            const SizedBox(height: 12),
            const Text(
              'Approving will add this amount to your project. Your contractor '
              'may issue a change order for the difference.',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Change selection')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Approve anyway')),
        ],
      ),
    );
  }

  Widget _overageRow(String label, String value, {bool emphasize = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: TextStyle(
                  fontSize: 13,
                  color: emphasize
                      ? AppColors.error
                      : AppColors.textSecondary,
                  fontWeight:
                      emphasize ? FontWeight.w700 : FontWeight.w400)),
          Text(value,
              style: TextStyle(
                  fontSize: 13,
                  color: emphasize ? AppColors.error : AppColors.textPrimary,
                  fontWeight:
                      emphasize ? FontWeight.w700 : FontWeight.w600)),
        ],
      ),
    );
  }

  Future<String?> _askReason(BuildContext context) async {
    final ctrl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Decline this selection'),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(
              labelText: 'Tell us why (optional)',
              hintText:
                  'e.g. "Out of budget" or "Want different options"'),
          autofocus: true,
          maxLines: 3,
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, ctrl.text.trim()),
              style:
                  FilledButton.styleFrom(backgroundColor: AppColors.error),
              child: const Text('Decline')),
        ],
      ),
    );
  }
}

class _ActivityTile extends StatelessWidget {
  final Map<String, dynamic> event;
  final VoidCallback onTap;

  const _ActivityTile({required this.event, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final eventType = (event['event_type'] as String?) ?? '';
    final title = (event['title'] as String?) ?? 'Activity';
    final subtitle = (event['subtitle'] as String?)?.trim();
    final actorName = (event['actor_name'] as String?)?.trim();
    final occurredAtRaw = event['occurred_at'] as String?;
    final occurredAt = occurredAtRaw != null
        ? DateTime.tryParse(occurredAtRaw)?.toLocal()
        : null;
    final amountRaw = event['amount'];
    final double? amount = amountRaw is num
        ? amountRaw.toDouble()
        : (amountRaw is String ? double.tryParse(amountRaw) : null);

    final spec = _iconForEvent(eventType);
    final showAmount = amount != null &&
        amount != 0 &&
        (eventType.startsWith('invoice_') ||
            eventType == 'document_payment_completed');
    final currencyFormat = NumberFormat.currency(symbol: '\$');

    final tappable = (event['ref_id'] != null);

    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: spec.color.withValues(alpha: 0.15),
          child: Icon(spec.icon, color: spec.color, size: 20),
        ),
        title: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (subtitle != null && subtitle.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(subtitle,
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.textSecondary)),
              ),
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                [
                  if (occurredAt != null) _formatRelative(occurredAt),
                  if (actorName != null && actorName.isNotEmpty)
                    'by $actorName',
                ].join(' · '),
                style: const TextStyle(
                    fontSize: 11, color: AppColors.textTertiary),
              ),
            ),
          ],
        ),
        trailing: showAmount
            ? Text(
                currencyFormat.format(amount),
                style: const TextStyle(fontWeight: FontWeight.bold),
              )
            : (tappable
                ? const Icon(Icons.chevron_right, color: AppColors.textTertiary)
                : null),
        onTap: tappable ? onTap : null,
      ),
    );
  }

  static String _formatRelative(DateTime when) {
    final diff = DateTime.now().difference(when);
    if (diff.inSeconds < 60) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return DateFormat('MMM d, y').format(when);
  }

  static _EventIconSpec _iconForEvent(String type) {
    switch (type) {
      case 'document_sent':
        return _EventIconSpec(Icons.send, AppColors.info);
      case 'document_viewed':
      case 'document_opened':
        return _EventIconSpec(Icons.visibility, AppColors.textSecondary);
      case 'document_downloaded':
        return _EventIconSpec(Icons.download, AppColors.textSecondary);
      case 'document_signed':
        return _EventIconSpec(Icons.draw, AppColors.success);
      case 'document_approved':
      case 'selection_approved':
      case 'change_order_approved':
        return _EventIconSpec(Icons.check_circle, AppColors.success);
      case 'document_denied':
      case 'selection_declined':
        return _EventIconSpec(Icons.cancel, AppColors.error);
      case 'document_changes_requested':
        return _EventIconSpec(Icons.edit_note, AppColors.warning);
      case 'document_payment_completed':
      case 'invoice_paid':
        return _EventIconSpec(Icons.payments, AppColors.success);
      case 'invoice_sent':
        return _EventIconSpec(Icons.receipt_long, AppColors.info);
      case 'change_order_sent':
        return _EventIconSpec(Icons.assignment, AppColors.info);
      default:
        return _EventIconSpec(Icons.timeline, AppColors.textSecondary);
    }
  }
}

class _EventIconSpec {
  final IconData icon;
  final Color color;
  const _EventIconSpec(this.icon, this.color);
}
