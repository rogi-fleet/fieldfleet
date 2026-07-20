import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/document_line_item.dart';
import '../../models/generated_document.dart';
import '../../models/project.dart';
import '../../models/user_role.dart';
import '../../providers/auth_provider.dart';
import '../../services/service_locator.dart';
import '../../theme/theme.dart';
import '../../utils/app_time_formatter.dart';
import '../../utils/user_facing_error.dart';

/// Landing surface for authenticated portal users (role=client or vendor
/// on workspace_members). Reuses the main app chrome but replaces the
/// operational dashboard with a portal-framed welcome + list of the rows
/// they're actually allowed to see (RLS already narrows them).
///
/// Distinct from the magic-link portal under /portal/* — that one serves
/// unauthenticated link recipients. This is for accepted invitations.
class AuthenticatedPortalHome extends StatefulWidget {
  const AuthenticatedPortalHome({super.key, required this.userId});

  final String userId;

  @override
  State<AuthenticatedPortalHome> createState() =>
      _AuthenticatedPortalHomeState();
}

class _AuthenticatedPortalHomeState extends State<AuthenticatedPortalHome> {
  bool _isLoading = true;
  String? _error;
  List<Project> _projects = const [];
  List<_BidRequestSummary> _bidRequests = const [];
  List<_FinancialSummary> _purchaseOrders = const [];
  List<_FinancialSummary> _bills = const [];
  List<GeneratedDocument> _pendingActionDocs = const [];
  int _documentCount = 0;
  bool _welcomeDismissed = true;

  String get _welcomeDismissKey =>
      'portal.welcome_card.dismissed.${widget.userId}';

  @override
  void initState() {
    super.initState();
    _load();
    _loadWelcomeDismissed();
  }

  Future<void> _load() async {
    final workspaceId =
        context.read<AuthProvider>().appUser?.currentWorkspaceId;
    if (workspaceId == null || workspaceId.isEmpty) {
      setState(() => _isLoading = false);
      return;
    }
    try {
      // All queries are RLS-scoped to the portal user's linked entity.
      final results = await Future.wait([
        ServiceLocator.projectService.getProjectsOnce(workspaceId)
            as Future<dynamic>,
        _fetchBidRequests(workspaceId),
        _fetchDocumentCount(workspaceId),
        _fetchPendingActionDocs(workspaceId),
        _fetchFinancials(
          workspaceId,
          table: 'purchase_orders',
          numberColumn: 'purchase_order_number',
        ),
        _fetchFinancials(
          workspaceId,
          table: 'bills',
          numberColumn: 'bill_number',
        ),
      ]);
      if (!mounted) return;
      setState(() {
        _projects = List<Project>.from(results[0] as List);
        _bidRequests = results[1] as List<_BidRequestSummary>;
        _documentCount = results[2] as int;
        _pendingActionDocs = results[3] as List<GeneratedDocument>;
        _purchaseOrders = results[4] as List<_FinancialSummary>;
        _bills = results[5] as List<_FinancialSummary>;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = UserFacingError.uiMessage(e, action: 'load your portal');
      });
    }
  }

  Future<List<_BidRequestSummary>> _fetchBidRequests(
    String workspaceId,
  ) async {
    try {
      final rows = await Supabase.instance.client
          .from('bid_requests')
          .select(
            'id, request_number, status, sent_date, due_date, '
            'vendor_bid_amount, workspace_id, project_id, vendor_id, '
            'projects!inner(name)',
          )
          .eq('workspace_id', workspaceId)
          .order('sent_date', ascending: false)
          .limit(10);
      return (rows as List)
          .map((r) => _BidRequestSummary.fromJson(r as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<List<GeneratedDocument>> _fetchPendingActionDocs(
    String workspaceId,
  ) async {
    try {
      final rows = await Supabase.instance.client
          .from('generated_documents')
          .select()
          .eq('workspace_id', workspaceId)
          .inFilter('status', ['sent', 'viewed'])
          .order('created_at', ascending: false)
          .limit(10);
      return (rows as List)
          .map((r) {
            final map = r as Map<String, dynamic>;
            return GeneratedDocument.fromJson(map, map['id'] as String);
          })
          .where((d) => d.needsCustomerAction)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<List<_FinancialSummary>> _fetchFinancials(
    String workspaceId, {
    required String table,
    required String numberColumn,
  }) async {
    try {
      final rows = await Supabase.instance.client
          .from(table)
          .select(
            'id, $numberColumn, status, total, due_date, created_at, projects!inner(name)',
          )
          .eq('workspace_id', workspaceId)
          .order('created_at', ascending: false)
          .limit(6);
      return (rows as List).map((r) {
        final map = r as Map<String, dynamic>;
        return _FinancialSummary.fromJson(map, numberColumn: numberColumn);
      }).toList();
    } catch (_) {
      return const [];
    }
  }

  Future<int> _fetchDocumentCount(String workspaceId) async {
    try {
      final rows = await Supabase.instance.client
          .from('generated_documents')
          .select('id')
          .eq('workspace_id', workspaceId);
      return (rows as List).length;
    } catch (_) {
      return 0;
    }
  }

  Future<void> _loadWelcomeDismissed() async {
    final prefs = await SharedPreferences.getInstance();
    final dismissed = prefs.getBool(_welcomeDismissKey) ?? false;
    if (!mounted) return;
    setState(() => _welcomeDismissed = dismissed);
  }

  Future<void> _dismissWelcome() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_welcomeDismissKey, true);
    if (!mounted) return;
    setState(() => _welcomeDismissed = true);
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = context.watch<AuthProvider>();
    final role = authProvider.appUser?.role;
    final isVendor = role == UserRole.vendor;

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Text(_error!),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(AppSpacing.base),
        children: [
          _buildHeader(authProvider, isVendor),
          const SizedBox(height: 16),
          if (!_welcomeDismissed)
            _PortalWelcomeCard(
              isVendor: isVendor,
              onDismiss: _dismissWelcome,
            ),
          if (!_welcomeDismissed) const SizedBox(height: 16),
          _buildStatsRow(isVendor),
          const SizedBox(height: 20),
          if (!isVendor && _pendingActionDocs.isNotEmpty) ...[
            _buildPendingActionsSection(),
            const SizedBox(height: 20),
          ],
          if (isVendor) _buildBidRequestsSection(),
          if (isVendor) const SizedBox(height: 20),
          if (isVendor && (_purchaseOrders.isNotEmpty || _bills.isNotEmpty)) ...[
            _buildVendorFinancialsSection(),
            const SizedBox(height: 20),
          ],
          _buildProjectsSection(isVendor),
        ],
      ),
    );
  }

  Widget _buildVendorFinancialsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_purchaseOrders.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              'RECENT PURCHASE ORDERS',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
                color: AppColors.textTertiary,
              ),
            ),
          ),
          for (final po in _purchaseOrders)
            _FinancialTile(summary: po, icon: Icons.receipt_outlined),
          const SizedBox(height: 16),
        ],
        if (_bills.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              'RECENT BILLS',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
                color: AppColors.textTertiary,
              ),
            ),
          ),
          for (final bill in _bills)
            _FinancialTile(summary: bill, icon: Icons.payments_outlined),
        ],
      ],
    );
  }

  Future<void> _openBidResponseSheet(_BidRequestSummary bid) async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _BidResponseSheet(bid: bid),
    );
    if (result == true) {
      await _load();
    }
  }

  String _docTitle(GeneratedDocument doc) {
    final num = doc.documentNumber?.trim() ?? '';
    final name = doc.templateName.trim();
    if (num.isNotEmpty && name.isNotEmpty) return '$num · $name';
    if (num.isNotEmpty) return num;
    if (name.isNotEmpty) return name;
    return 'Document';
  }

  Widget _buildPendingActionsSection() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 10, 14),
      decoration: BoxDecoration(
        color: AppColors.warningLight,
        border: Border(left: BorderSide(color: AppColors.warning, width: 3)),
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.pending_actions_outlined,
                color: AppColors.warningDark,
                size: 18,
              ),
              const SizedBox(width: 8),
              Text(
                '${_pendingActionDocs.length} document'
                '${_pendingActionDocs.length == 1 ? '' : 's'} waiting for you',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.warningDark,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (final doc in _pendingActionDocs)
            InkWell(
              onTap: () => context.push('/documents/${doc.id}'),
              borderRadius: BorderRadius.circular(AppRadius.xs),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
                child: Row(
                  children: [
                    const Text('•  ', style: TextStyle(fontSize: 13)),
                    Expanded(
                      child: Text(
                        _docTitle(doc),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Icon(
                      Icons.chevron_right,
                      size: 16,
                      color: AppColors.warningDark,
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildHeader(AuthProvider authProvider, bool isVendor) {
    final roleColor = isVendor ? AppColors.messageAccent : AppColors.success;
    final roleLabel = isVendor ? 'Vendor Portal' : 'Customer Portal';
    final displayName = authProvider.appUser?.displayName ??
        authProvider.appUser?.email ??
        'there';
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            roleColor.withValues(alpha: 0.12),
            roleColor.withValues(alpha: 0.04),
          ],
        ),
        border: Border(left: BorderSide(color: roleColor, width: 3)),
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            roleLabel.toUpperCase(),
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
              color: roleColor,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Welcome back, $displayName',
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            isVendor
                ? 'Your bid requests, purchase orders, and bills in one place.'
                : 'Your jobs, invoices, and shared documents in one place.',
            style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsRow(bool isVendor) {
    final pendingBidCount = _bidRequests
        .where((b) => b.needsResponse)
        .length;
    return Row(
      children: [
        Expanded(
          child: _StatTile(
            label: isVendor ? 'Pending Bids' : 'My Jobs',
            value: isVendor
                ? pendingBidCount.toString()
                : _projects.length.toString(),
            icon: isVendor ? Icons.how_to_vote_outlined : Icons.work_outline,
            color: isVendor ? AppColors.warning : AppColors.info,
            onTap: () =>
                context.push(isVendor ? '/documents' : '/projects'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _StatTile(
            label: 'Shared Documents',
            value: _documentCount.toString(),
            icon: Icons.description_outlined,
            color: isVendor ? AppColors.messageAccent : AppColors.success,
            onTap: () => context.push('/documents'),
          ),
        ),
      ],
    );
  }

  Widget _buildBidRequestsSection() {
    if (_bidRequests.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        child: Row(
          children: [
            Icon(
              Icons.how_to_vote_outlined,
              color: AppColors.textTertiary,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'No bid requests yet. When the workspace invites you to bid, '
                'they\'ll appear here.',
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            'BID REQUESTS',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
              color: AppColors.textTertiary,
            ),
          ),
        ),
        for (final bid in _bidRequests)
          _BidRequestTile(
            bid: bid,
            onRespond: bid.needsResponse ? () => _openBidResponseSheet(bid) : null,
          ),
      ],
    );
  }

  Widget _buildProjectsSection(bool isVendor) {
    if (_projects.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(AppSpacing.xl),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        child: Column(
          children: [
            Icon(
              Icons.folder_open_outlined,
              size: 40,
              color: AppColors.textTertiary,
            ),
            const SizedBox(height: 8),
            Text(
              isVendor
                  ? 'No bid requests or projects yet'
                  : 'No jobs linked to your account yet',
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Text(
              isVendor
                  ? 'Your workspace admin will notify you when a bid is ready.'
                  : 'Your workspace admin will share job details here as work begins.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            isVendor ? 'PROJECTS' : 'YOUR JOBS',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
              color: AppColors.textTertiary,
            ),
          ),
        ),
        for (final project in _projects) _PortalProjectTile(project: project),
      ],
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    required this.onTap,
  });
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.base),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: Icon(icon, color: color, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      value,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PortalProjectTile extends StatelessWidget {
  const _PortalProjectTile({required this.project});
  final Project project;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        leading: const Icon(Icons.work_outline),
        title: Text(project.name),
        subtitle: project.address.isNotEmpty
            ? Text(project.address, maxLines: 1, overflow: TextOverflow.ellipsis)
            : null,
        trailing: const Icon(Icons.chevron_right),
        onTap: () => context.push('/projects/${project.id}'),
      ),
    );
  }
}

class _PortalWelcomeCard extends StatelessWidget {
  const _PortalWelcomeCard({required this.isVendor, required this.onDismiss});
  final bool isVendor;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final bullets = isVendor
        ? const [
            'Bid requests from this workspace — and only the ones assigned to you',
            'Purchase orders and bills where you are the vendor',
            'Documents shared with you on those projects',
          ]
        : const [
            'Jobs linked to your customer account — nobody else\'s',
            'Invoices and change orders for your jobs',
            'Documents shared with you by the workspace',
          ];
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 10, 14),
      decoration: BoxDecoration(
        color: AppColors.infoLight,
        border: Border(left: BorderSide(color: AppColors.info, width: 3)),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.emoji_people_outlined, color: AppColors.infoDark),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'What you can see here',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.infoDark,
                  ),
                ),
                const SizedBox(height: 6),
                for (final bullet in bullets)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 3),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('•  ', style: TextStyle(fontSize: 12)),
                        Expanded(
                          child: Text(
                            bullet,
                            style: const TextStyle(fontSize: 12, height: 1.4),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Dismiss',
            iconSize: 18,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            icon: const Icon(Icons.close),
            onPressed: onDismiss,
          ),
        ],
      ),
    );
  }
}

class _BidRequestSummary {
  _BidRequestSummary({
    required this.id,
    required this.workspaceId,
    required this.projectId,
    required this.vendorId,
    required this.requestNumber,
    required this.status,
    required this.projectName,
    this.sentDate,
    this.dueDate,
    this.vendorBidAmount,
  });

  final String id;
  final String workspaceId;
  final String? projectId;
  final String? vendorId;
  final String? requestNumber;
  final String status;
  final String projectName;
  final DateTime? sentDate;
  final DateTime? dueDate;
  final num? vendorBidAmount;

  /// Vendor is expected to respond only while the request is sitting in
  /// 'sent'. Once they submit, the RPC flips status to 'responded'.
  bool get needsResponse => status.toLowerCase() == 'sent';

  /// Terminal for the vendor: awarded to someone else ('declined') or the
  /// package was cancelled / expired ('expired'). Also covers 'accepted'
  /// in case anything flips to that pre-existing enum value.
  bool get isTerminal {
    final s = status.toLowerCase();
    return s == 'declined' || s == 'expired' || s == 'accepted';
  }

  String get vendorFacingLabel {
    switch (status.toLowerCase()) {
      case 'sent':
        return 'Needs response';
      case 'responded':
        return 'Bid submitted';
      case 'accepted':
        return 'Awarded to you';
      case 'declined':
        return 'Not selected';
      case 'expired':
        return 'Closed';
      default:
        return status;
    }
  }

  factory _BidRequestSummary.fromJson(Map<String, dynamic> json) {
    DateTime? parseDate(dynamic raw) {
      if (raw == null) return null;
      if (raw is String) return DateTime.tryParse(raw);
      return null;
    }

    final project = json['projects'] as Map<String, dynamic>?;
    return _BidRequestSummary(
      id: json['id'] as String,
      workspaceId: json['workspace_id'] as String,
      projectId: json['project_id'] as String?,
      vendorId: json['vendor_id'] as String?,
      requestNumber: json['request_number'] as String?,
      status: (json['status'] as String?) ?? 'unknown',
      projectName: (project?['name'] as String?) ?? 'Project',
      sentDate: parseDate(json['sent_date']),
      dueDate: parseDate(json['due_date']),
      vendorBidAmount: json['vendor_bid_amount'] as num?,
    );
  }
}

class _BidRequestTile extends StatelessWidget {
  const _BidRequestTile({required this.bid, this.onRespond});
  final _BidRequestSummary bid;
  final VoidCallback? onRespond;

  Color _statusColor() {
    switch (bid.status.toLowerCase()) {
      case 'sent':
        return AppColors.warning;
      case 'responded':
      case 'accepted':
        return AppColors.success;
      case 'declined':
      case 'expired':
        return AppColors.textTertiary;
      default:
        return AppColors.info;
    }
  }

  @override
  Widget build(BuildContext context) {
    final statusColor = _statusColor();
    final statusLabel = bid.vendorFacingLabel;
    final isTerminal = bid.isTerminal;
    // Only open the response sheet while the vendor can still act on it.
    final effectiveOnTap = (isTerminal || !bid.needsResponse) ? null : onRespond;
    final subtitleParts = <String>[];
    if (bid.requestNumber != null) subtitleParts.add('#${bid.requestNumber}');
    if (bid.dueDate != null) {
      subtitleParts.add(
        'Due ${AppTimeFormatter.formatDate(bid.dueDate!)}',
      );
    }
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      clipBehavior: Clip.antiAlias,
      color: isTerminal
          ? Theme.of(context).colorScheme.surfaceContainerHighest
              .withValues(alpha: 0.4)
          : null,
      child: InkWell(
        onTap: effectiveOnTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.base, vertical: AppSpacing.md),
          child: Row(
            children: [
              Icon(
                isTerminal
                    ? Icons.do_not_disturb_on_outlined
                    : Icons.how_to_vote_outlined,
                color: statusColor,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      bid.projectName,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: isTerminal ? AppColors.textSecondary : null,
                      ),
                    ),
                    if (subtitleParts.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          subtitleParts.join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                    if (bid.status.toLowerCase() == 'declined')
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          'This bid was not selected. Thanks for bidding.',
                          style: TextStyle(
                            fontSize: 11,
                            fontStyle: FontStyle.italic,
                            color: AppColors.textTertiary,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: AppSpacing.xs,
                ),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  statusLabel,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: statusColor,
                  ),
                ),
              ),
              if (effectiveOnTap != null) ...[
                const SizedBox(width: 6),
                Icon(
                  Icons.chevron_right,
                  size: 18,
                  color: statusColor,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Itemized bid response sheet. Loads the request-for-bid document's line
/// items, lets the vendor enter a bid price per line (plus an optional
/// per-line note), and submits everything in one RPC call.
class _BidResponseSheet extends StatefulWidget {
  const _BidResponseSheet({required this.bid});
  final _BidRequestSummary bid;

  @override
  State<_BidResponseSheet> createState() => _BidResponseSheetState();
}

class _BidResponseSheetState extends State<_BidResponseSheet> {
  final _overallNotesController = TextEditingController();
  final Map<String, TextEditingController> _priceControllers = {};
  final Map<String, TextEditingController> _noteControllers = {};

  bool _loading = true;
  bool _submitting = false;
  String? _error;
  String? _documentId;
  List<DocumentLineItem> _lineItems = const [];

  @override
  void initState() {
    super.initState();
    _loadDocument();
  }

  @override
  void dispose() {
    _overallNotesController.dispose();
    for (final c in _priceControllers.values) {
      c.dispose();
    }
    for (final c in _noteControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _loadDocument() async {
    try {
      var filter = Supabase.instance.client
          .from('generated_documents')
          .select('id, line_items, metadata')
          .eq('workspace_id', widget.bid.workspaceId)
          .eq('document_type', 'request_for_bid');

      final projectId = widget.bid.projectId;
      final vendorId = widget.bid.vendorId;
      if (projectId != null) {
        filter = filter.eq('project_id', projectId);
      }
      if (vendorId != null) {
        filter = filter.eq('vendor_id', vendorId);
      }

      final row = await filter
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();

      if (!mounted) return;

      if (row == null) {
        setState(() {
          _loading = false;
          _error = 'Could not find the bid request document.';
        });
        return;
      }

      final rawItems = (row['line_items'] as List?) ?? const [];
      final items = rawItems
          .map((e) => DocumentLineItem.fromJson(e as Map<String, dynamic>))
          .where((i) => i.isVisible && i.isItem)
          .toList()
        ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

      for (final item in items) {
        final bidPrice = item.vendorBidPrice;
        _priceControllers[item.id] = TextEditingController(
          text: bidPrice == null ? '' : bidPrice.toStringAsFixed(2),
        );
        _noteControllers[item.id] = TextEditingController(
          text: item.vendorBidNote ?? '',
        );
      }

      final metadata = row['metadata'];
      if (metadata is Map && metadata['vendorBidNote'] is String) {
        _overallNotesController.text = metadata['vendorBidNote'] as String;
      }

      setState(() {
        _loading = false;
        _documentId = row['id'] as String;
        _lineItems = items;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = UserFacingError.uiMessage(
          e,
          action: 'load the bid request',
        );
      });
    }
  }

  double get _runningTotal {
    double total = 0;
    for (final item in _lineItems) {
      final priceText = _priceControllers[item.id]?.text.trim() ?? '';
      if (priceText.isEmpty) continue;
      final price = double.tryParse(priceText.replaceAll(',', ''));
      if (price == null) continue;
      total += price * item.quantity;
    }
    return total;
  }

  Future<void> _submit() async {
    final documentId = _documentId;
    if (documentId == null) return;

    final bids = <Map<String, dynamic>>[];
    for (final item in _lineItems) {
      final priceText = _priceControllers[item.id]?.text.trim() ?? '';
      final noteText = _noteControllers[item.id]?.text.trim() ?? '';
      double? price;
      if (priceText.isNotEmpty) {
        price = double.tryParse(priceText.replaceAll(',', ''));
        if (price == null || price < 0) {
          setState(
            () => _error = 'Enter a valid price for "${item.name}"',
          );
          return;
        }
      }
      bids.add({
        'id': item.id,
        'vendorBidPrice': price,
        'vendorBidNote': noteText.isEmpty ? null : noteText,
      });
    }

    if (bids.every((b) => b['vendorBidPrice'] == null)) {
      setState(() => _error = 'Enter at least one bid price before submitting');
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final overallNote = _overallNotesController.text.trim();
      await ServiceLocator.documentService.submitVendorBid(
        documentId: documentId,
        lineItemBids: bids,
        overallNote: overallNote.isEmpty ? null : overallNote,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = UserFacingError.uiMessage(e, action: 'submit your bid');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final viewInsets = MediaQuery.of(context).viewInsets;
    final mediaHeight = MediaQuery.of(context).size.height;
    return Padding(
      padding: EdgeInsets.only(bottom: viewInsets.bottom),
      child: SafeArea(
        top: false,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: mediaHeight * 0.88),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _header(),
                const SizedBox(height: 12),
                if (_loading)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: AppSpacing.xxl),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else
                  Flexible(child: _body()),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      _error!,
                      style: TextStyle(fontSize: 12, color: AppColors.error),
                    ),
                  ),
                const SizedBox(height: 12),
                _actions(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _header() {
    return Row(
      children: [
        Icon(Icons.how_to_vote_outlined, color: AppColors.warning),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Respond to bid',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
              Text(
                widget.bid.projectName,
                style: TextStyle(
                  fontSize: 13,
                  color: AppColors.textSecondary,
                ),
              ),
              if (widget.bid.dueDate != null)
                Text(
                  'Due ${AppTimeFormatter.formatDate(widget.bid.dueDate!)}',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textTertiary,
                  ),
                ),
            ],
          ),
        ),
        IconButton(
          icon: const Icon(Icons.close),
          onPressed: _submitting ? null : () => Navigator.pop(context),
        ),
      ],
    );
  }

  Widget _body() {
    if (_lineItems.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
        child: Text(
          'This bid request has no line items to price.',
          style: TextStyle(color: AppColors.textSecondary),
        ),
      );
    }
    final total = _runningTotal;
    return ListView(
      shrinkWrap: true,
      children: [
        for (final item in _lineItems) _lineItemRow(item),
        const Divider(height: 24),
        TextField(
          controller: _overallNotesController,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: 'Overall notes (optional)',
            hintText: 'Timeline, exclusions, references…',
            border: OutlineInputBorder(),
            isDense: true,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Bid total',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            Text(
              '\$${total.toStringAsFixed(2)}',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppColors.primary,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _lineItemRow(DocumentLineItem item) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.name,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    if (item.description != null &&
                        item.description!.isNotEmpty)
                      Text(
                        item.description!,
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    Text(
                      'Qty ${item.formattedQuantity}'
                      '${item.unit != null ? ' ${item.unit}' : ''}',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 110,
                child: TextField(
                  controller: _priceControllers[item.id],
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Bid price',
                    prefixText: r'$ ',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _noteControllers[item.id],
            decoration: const InputDecoration(
              hintText: 'Note for this line (optional)',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
        ],
      ),
    );
  }

  Widget _actions() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        const SizedBox(width: 8),
        FilledButton.icon(
          onPressed: _submitting || _loading || _documentId == null
              ? null
              : _submit,
          icon: _submitting
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.send, size: 16),
          label: const Text('Submit bid'),
        ),
      ],
    );
  }
}

class _FinancialSummary {
  _FinancialSummary({
    required this.id,
    required this.number,
    required this.status,
    required this.projectName,
    this.total,
    this.dueDate,
  });

  final String id;
  final String? number;
  final String status;
  final String projectName;
  final num? total;
  final DateTime? dueDate;

  factory _FinancialSummary.fromJson(
    Map<String, dynamic> json, {
    required String numberColumn,
  }) {
    DateTime? parseDate(dynamic raw) {
      if (raw == null) return null;
      if (raw is String) return DateTime.tryParse(raw);
      return null;
    }

    final project = json['projects'] as Map<String, dynamic>?;
    return _FinancialSummary(
      id: json['id'] as String,
      number: json[numberColumn] as String?,
      status: (json['status'] as String?) ?? 'unknown',
      projectName: (project?['name'] as String?) ?? 'Project',
      total: json['total'] as num?,
      dueDate: parseDate(json['due_date']),
    );
  }
}

class _FinancialTile extends StatelessWidget {
  const _FinancialTile({required this.summary, required this.icon});
  final _FinancialSummary summary;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final subtitleParts = <String>[];
    if (summary.number != null && summary.number!.isNotEmpty) {
      subtitleParts.add('#${summary.number}');
    }
    if (summary.dueDate != null) {
      subtitleParts.add('Due ${AppTimeFormatter.formatDate(summary.dueDate!)}');
    }
    final totalLabel = summary.total == null
        ? null
        : '\$${summary.total!.toStringAsFixed(2)}';
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        leading: Icon(icon, color: AppColors.messageAccent),
        title: Text(summary.projectName),
        subtitle: subtitleParts.isEmpty
            ? null
            : Text(
                subtitleParts.join(' · '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
        trailing: totalLabel != null
            ? Text(
                totalLabel,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              )
            : null,
      ),
    );
  }
}
