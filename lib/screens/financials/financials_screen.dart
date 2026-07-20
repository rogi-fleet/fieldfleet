import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:go_router/go_router.dart';
import '../../services/service_locator.dart';
import 'package:provider/provider.dart';
import '../../theme/theme.dart';
import '../../providers/auth_provider.dart';
import '../../providers/workspace_provider.dart';
import '../../models/generated_document.dart';
import '../../models/document_status.dart';
import '../../models/document_type.dart';
import '../../utils/user_facing_error.dart';
import '../../widgets/common/module_header.dart';
import '../../widgets/common/zero_items_action_empty_state.dart';
import '../../widgets/adaptive_navigation.dart';

class FinancialsScreen extends StatefulWidget {
  const FinancialsScreen({super.key});

  @override
  State<FinancialsScreen> createState() => _FinancialsScreenState();
}

class _FinancialsScreenState extends State<FinancialsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _documentService = ServiceLocator.documentService;
  static final _currencyFormatter = NumberFormat.currency(symbol: '\$');
  static final _dueDateFormatter = DateFormat('MM/dd/yyyy');

  // Cache one document stream per type so rebuilds (e.g. from provider
  // notifications) reuse the existing subscription instead of recreating it.
  // Recreating the stream would reset each StreamBuilder to its loading state,
  // causing the tabs to flicker.
  final Map<DocumentType, Stream<List<GeneratedDocument>>> _documentStreams =
      {};
  String? _streamsWorkspaceId;

  Stream<List<GeneratedDocument>> _documentStream(
    String workspaceId,
    DocumentType documentType,
  ) {
    if (_streamsWorkspaceId != workspaceId) {
      _streamsWorkspaceId = workspaceId;
      _documentStreams.clear();
    }
    return _documentStreams.putIfAbsent(
      documentType,
      () => _documentService.getDocuments(
        workspaceId,
        documentType: documentType,
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 6, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // appUser is briefly null on a cold load / hard refresh; force-unwrapping
    // it here crashed the screen to the error boundary. Show a loader until it
    // hydrates (build re-runs via watch).
    final appUser = context.watch<AuthProvider>().appUser;
    if (appUser == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final workspaceId = appUser.currentWorkspaceId;
    final projectTerminology = context
        .watch<WorkspaceProvider>()
        .projectTerminology;

    return TabSwitchNotifier(
      controller: _tabController,
      child: Column(
        children: [
          ModuleHeader(
            icon: Icons.account_balance_wallet_outlined,
            title: 'Financials',
            description:
                'Project-scoped revenue and spend — bid requests, change '
                'orders, invoices, refunds, purchase orders and bills.',
            bottom: TabBar(
              controller: _tabController,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              tabs: const [
                Tab(
                  text: 'Bid Requests',
                  icon: Icon(Icons.request_quote, size: 20),
                ),
                Tab(
                  text: 'Change Orders',
                  icon: Icon(Icons.edit_document, size: 20),
                ),
                Tab(text: 'Invoices', icon: Icon(Icons.receipt, size: 20)),
                Tab(
                  text: 'Refunds',
                  icon: Icon(Icons.currency_exchange, size: 20),
                ),
                Tab(
                  text: 'Purchase Orders',
                  icon: Icon(Icons.shopping_cart, size: 20),
                ),
                Tab(text: 'Bills', icon: Icon(Icons.receipt_long, size: 20)),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              physics: const NeverScrollableScrollPhysics(),
              controller: _tabController,
              children: [
                _buildDocumentTab(
                  workspaceId: workspaceId,
                  documentType: DocumentType.requestForBid,
                  errorAction: 'load bid requests',
                  emptyIcon: Icons.request_quote_outlined,
                  emptyTitle: 'No bid requests yet',
                  emptySubtitle:
                      'Create a bid request to start collecting vendor bids',
                  ctaLabel: 'Create Bid Request',
                  header: _bidRequestHeader(),
                  buildLeading: (br) => br.bidPackageId != null
                      ? const Icon(Icons.view_column_outlined)
                      : null,
                  buildSubtitle: _bidRequestSubtitle,
                  buildTrailing: (br) =>
                      Text('${br.budgetItemIds.length} items'),
                  buildRoute: (br) => br.bidPackageId != null
                      ? '/bid-packages/${br.bidPackageId}'
                      : '/documents/${br.id}',
                ),
                _buildDocumentTab(
                  workspaceId: workspaceId,
                  documentType: DocumentType.changeOrder,
                  errorAction: 'load change orders',
                  emptyIcon: Icons.edit_document,
                  emptyTitle: 'No change orders yet',
                  emptySubtitle:
                      'Change orders track scope and cost adjustments to ${projectTerminology.toLowerCase()}',
                  ctaLabel: 'Create Change Order',
                ),
                _buildDocumentTab(
                  workspaceId: workspaceId,
                  documentType: DocumentType.invoice,
                  errorAction: 'load invoices',
                  emptyIcon: Icons.receipt_outlined,
                  emptyTitle: 'No invoices yet',
                  emptySubtitle:
                      'Create invoices to bill your customers for completed work',
                  ctaLabel: 'Create Invoice',
                  buildTitle: _numberOrTemplateName,
                  buildSubtitle: _statusAndDueDate,
                ),
                _buildDocumentTab(
                  workspaceId: workspaceId,
                  documentType: DocumentType.refund,
                  errorAction: 'load refunds',
                  emptyIcon: Icons.currency_exchange_outlined,
                  emptyTitle: 'No refunds yet',
                  emptySubtitle:
                      'Refunds will appear here when issued to customers',
                  ctaLabel: 'Create Refund',
                  buildTitle: _numberOrTemplateName,
                  buildSubtitle: _refundSubtitle,
                  totalColor: AppColors.errorDark,
                ),
                _buildDocumentTab(
                  workspaceId: workspaceId,
                  documentType: DocumentType.purchaseOrder,
                  errorAction: 'load purchase orders',
                  emptyIcon: Icons.shopping_cart_outlined,
                  emptyTitle: 'No purchase orders yet',
                  emptySubtitle:
                      'Create purchase orders to track materials and vendor purchases',
                  ctaLabel: 'Create Purchase Order',
                  buildTitle: _numberOrTemplateName,
                ),
                _buildDocumentTab(
                  workspaceId: workspaceId,
                  documentType: DocumentType.bill,
                  errorAction: 'load bills',
                  emptyIcon: Icons.receipt_long_outlined,
                  emptyTitle: 'No bills yet',
                  emptySubtitle:
                      'Bills from vendors and suppliers will appear here',
                  ctaLabel: 'Create Bill',
                  buildTitle: _numberOrTemplateName,
                  buildSubtitle: _statusAndDueDate,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDocumentTab({
    required String workspaceId,
    required DocumentType documentType,
    required String errorAction,
    required IconData emptyIcon,
    required String emptyTitle,
    required String emptySubtitle,
    required String ctaLabel,
    Widget? header,
    Widget? Function(GeneratedDocument doc)? buildLeading,
    String Function(GeneratedDocument doc)? buildTitle,
    String Function(GeneratedDocument doc)? buildSubtitle,
    Widget Function(GeneratedDocument doc)? buildTrailing,
    String Function(GeneratedDocument doc)? buildRoute,
    Color? totalColor,
  }) {
    return StreamBuilder<List<GeneratedDocument>>(
      stream: _documentStream(workspaceId, documentType),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Text(
              UserFacingError.uiMessage(snapshot.error, action: errorAction),
            ),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final docs = snapshot.data!;
        if (docs.isEmpty) {
          return ZeroItemsActionEmptyState(
            icon: emptyIcon,
            title: emptyTitle,
            subtitle: emptySubtitle,
            ctaLabel: ctaLabel,
            onTap: () => context.push('/documents/create'),
          );
        }

        final list = ListView.builder(
          padding: const EdgeInsets.all(AppSpacing.base),
          itemCount: docs.length,
          itemBuilder: (context, index) {
            final doc = docs[index];
            final title = buildTitle?.call(doc) ?? doc.templateName;
            final subtitle =
                buildSubtitle?.call(doc) ?? doc.status.displayName;
            final trailing =
                buildTrailing?.call(doc) ?? _totalLabel(doc, color: totalColor);
            final route = buildRoute?.call(doc) ?? '/documents/${doc.id}';
            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              child: ListTile(
                onTap: () => context.push(route),
                leading: buildLeading?.call(doc),
                title: Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: Text(subtitle),
                trailing: trailing,
              ),
            );
          },
        );

        if (header == null) return list;
        return Column(children: [header, Expanded(child: list)]);
      },
    );
  }

  Widget _bidRequestHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          OutlinedButton.icon(
            onPressed: () => context.push('/documents/create'),
            icon: const Icon(Icons.add, size: 16),
            label: const Text('Single-vendor RFB'),
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            onPressed: () => context.push('/bid-packages/new'),
            icon: const Icon(Icons.view_column_outlined, size: 16),
            label: const Text('Multi-vendor package'),
          ),
        ],
      ),
    );
  }

  String _numberOrTemplateName(GeneratedDocument doc) =>
      doc.documentNumber ?? doc.templateName;

  String _statusAndDueDate(GeneratedDocument doc) {
    final dueDateStr = doc.dueDate != null
        ? _dueDateFormatter.format(doc.dueDate!)
        : '';
    return '${doc.status.displayName}'
        '${dueDateStr.isNotEmpty ? " • Due: $dueDateStr" : ""}';
  }

  String _refundSubtitle(GeneratedDocument doc) {
    final reason = doc.metadata['reason'] as String? ?? '';
    return '${doc.status.displayName}'
        '${reason.isNotEmpty ? ' • $reason' : ''}';
  }

  String _bidRequestSubtitle(GeneratedDocument br) {
    final vendorBidAmount = br.metadata['vendorBidAmount'] as num?;
    final packageId = br.bidPackageId;
    return '${br.status.displayName}'
        '${vendorBidAmount != null ? " • ${_currencyFormatter.format(vendorBidAmount)}" : ""}'
        '${packageId != null ? " • multi-vendor" : ""}';
  }

  // Always show the persisted total_amount (subtotal + tax, recomputed from
  // line items in the document service) and label it "Total" so different
  // document types are directly comparable.
  Widget _totalLabel(GeneratedDocument doc, {Color? color}) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          'Total',
          style: TextStyle(
            fontSize: 11,
            color: Theme.of(context).hintColor,
          ),
        ),
        Text(
          _currencyFormatter.format(doc.totalAmount),
          style: TextStyle(fontWeight: FontWeight.bold, color: color),
        ),
      ],
    );
  }
}
