import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../models/property_issue.dart';
import '../../models/property_status.dart';
import '../../services/service_locator.dart';
import '../../theme/theme.dart';
import '../../utils/user_facing_error.dart';
import '../../widgets/properties/property_status_badge.dart';
import 'portal_preview_scope.dart';

/// Scoped "building view" for a unit holder — a customer_contacts row
/// restricted to exactly one property instead of the whole customer. Shows
/// just that property and lets the unit holder report issues against it.
class PortalPropertyScreen extends StatefulWidget {
  final String propertyId;

  const PortalPropertyScreen({super.key, required this.propertyId});

  @override
  State<PortalPropertyScreen> createState() => _PortalPropertyScreenState();
}

class _PortalPropertyScreenState extends State<PortalPropertyScreen>
    with SingleTickerProviderStateMixin {
  final dynamic _portalService = ServiceLocator.clientPortalService;

  Map<String, dynamic>? _property;
  bool _isLoading = true;
  String? _error;
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    try {
      final preview = PortalPreviewScope.of(context);
      final property = await _portalService.getPortalProperty(
        widget.propertyId,
        previewCustomerId: preview,
      ) as Map<String, dynamic>?;
      if (mounted) {
        setState(() {
          _property = property;
          _isLoading = false;
          _error = property == null ? 'Property not found.' : null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = UserFacingError.uiMessage(e, action: 'load this property');
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _handleSignOut() async {
    try {
      await _portalService.signOut();
    } catch (_) {
      // Best-effort sign-out for mixed backends.
    }
    if (!mounted) return;
    context.go('/portal');
  }

  @override
  Widget build(BuildContext context) {
    final isPreview = PortalPreviewScope.of(context) != null;
    return Scaffold(
      appBar: AppBar(
        title: Text(_property?['name'] as String? ?? 'Property'),
        bottom: _property == null
            ? null
            : TabBar(
                controller: _tabController,
                tabs: const [
                  Tab(text: 'Overview'),
                  Tab(text: 'Issues'),
                ],
              ),
        actions: [
          if (!isPreview)
            IconButton(
              icon: const Icon(Icons.logout),
              tooltip: 'Sign Out',
              onPressed: _handleSignOut,
            ),
          if (isPreview)
            IconButton(
              icon: const Icon(Icons.close),
              tooltip: 'Exit preview',
              onPressed: () {
                if (Navigator.of(context).canPop()) {
                  Navigator.of(context).pop();
                } else {
                  context.go('/customers');
                }
              },
            ),
        ],
      ),
      body: Column(
        children: [
          const PortalPreviewBanner(),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null || _property == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: AppColors.error),
            const SizedBox(height: 16),
            Text(_error ?? 'Unable to load this property right now.'),
            const SizedBox(height: 16),
            ElevatedButton(onPressed: _loadData, child: const Text('Retry')),
          ],
        ),
      );
    }

    return TabBarView(
      controller: _tabController,
      children: [
        _buildOverviewTab(),
        _PortalPropertyIssuesTab(propertyId: widget.propertyId),
      ],
    );
  }

  Widget _buildOverviewTab() {
    final property = _property!;
    final status = PropertyStatus.fromString(
      (property['status'] as String?) ?? 'pending',
    );
    return RefreshIndicator(
      onRefresh: _loadData,
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
                    children: [
                      Expanded(
                        child: Text(
                          property['name'] as String? ?? 'Property',
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      PropertyStatusBadge(status: status),
                    ],
                  ),
                  if ((property['project_name'] as String?)?.isNotEmpty ==
                      true) ...[
                    const SizedBox(height: 4),
                    Text(
                      property['project_name'] as String,
                      style: const TextStyle(color: AppColors.textSecondary),
                    ),
                  ],
                  const Divider(height: 24),
                  if ((property['identifier'] as String?)?.isNotEmpty == true)
                    _buildInfoRow('Unit / Identifier',
                        property['identifier'] as String),
                  if ((property['floor'] as String?)?.isNotEmpty == true)
                    _buildInfoRow('Floor', property['floor'] as String),
                  if ((property['occupant'] as String?)?.isNotEmpty == true)
                    _buildInfoRow('Occupant', property['occupant'] as String),
                  if ((property['notes'] as String?)?.isNotEmpty == true) ...[
                    const SizedBox(height: 12),
                    const Text(
                      'Notes',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 4),
                    Text(property['notes'] as String),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(
              label,
              style: const TextStyle(color: AppColors.textSecondary),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}

class _PortalPropertyIssuesTab extends StatefulWidget {
  final String propertyId;
  const _PortalPropertyIssuesTab({required this.propertyId});

  @override
  State<_PortalPropertyIssuesTab> createState() =>
      _PortalPropertyIssuesTabState();
}

class _PortalPropertyIssuesTabState extends State<_PortalPropertyIssuesTab> {
  final dynamic _portalService = ServiceLocator.clientPortalService;
  List<PropertyIssue> _issues = const [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadIssues();
  }

  Future<void> _loadIssues() async {
    try {
      final preview = PortalPreviewScope.of(context);
      final issues = await _portalService.getPortalPropertyIssues(
        widget.propertyId,
        previewCustomerId: preview,
      ) as List<PropertyIssue>;
      if (mounted) {
        setState(() {
          _issues = issues;
          _isLoading = false;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = UserFacingError.uiMessage(e, action: 'load issues');
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _showReportIssueDialog() async {
    final titleCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    String priority = 'normal';
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('Report an issue'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: titleCtrl,
                  autofocus: true,
                  decoration: const InputDecoration(labelText: 'Title'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: descCtrl,
                  minLines: 2,
                  maxLines: 5,
                  decoration:
                      const InputDecoration(labelText: 'Description (optional)'),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: priority,
                  decoration: const InputDecoration(labelText: 'Priority'),
                  items: const [
                    DropdownMenuItem(value: 'low', child: Text('Low')),
                    DropdownMenuItem(value: 'normal', child: Text('Normal')),
                    DropdownMenuItem(value: 'high', child: Text('High')),
                    DropdownMenuItem(value: 'urgent', child: Text('Urgent')),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setDialogState(() => priority = value);
                    }
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Submit'),
            ),
          ],
        ),
      ),
    );

    if (result != true || titleCtrl.text.trim().isEmpty) return;

    try {
      await _portalService.createPortalPropertyIssue(
        propertyId: widget.propertyId,
        title: titleCtrl.text.trim(),
        description:
            descCtrl.text.trim().isEmpty ? null : descCtrl.text.trim(),
        priority: priority,
      );
      await _loadIssues();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Issue reported.')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not report this issue.')),
        );
      }
    }
  }

  Color _priorityColor(String priority) {
    switch (priority) {
      case 'urgent':
        return AppColors.error;
      case 'high':
        return AppColors.warning;
      case 'low':
        return AppColors.textTertiary;
      default:
        return AppColors.info;
    }
  }

  Widget _buildStatusChip(String status) {
    final resolved = status == 'resolved' || status == 'closed';
    final color = resolved ? AppColors.success : AppColors.warning;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(AppRadius.r12),
      ),
      child: Text(
        status.replaceAll('_', ' '),
        style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w600),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isPreview = PortalPreviewScope.of(context) != null;
    return Scaffold(
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : RefreshIndicator(
                  onRefresh: _loadIssues,
                  child: _issues.isEmpty
                      ? ListView(
                          padding: const EdgeInsets.all(AppSpacing.lg),
                          children: const [
                            SizedBox(height: 48),
                            Icon(Icons.report_problem_outlined,
                                size: 48, color: AppColors.textTertiary),
                            SizedBox(height: 12),
                            Center(
                              child: Text(
                                'No issues reported yet',
                                style: TextStyle(
                                    fontSize: 18,
                                    color: AppColors.textSecondary),
                              ),
                            ),
                          ],
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.all(AppSpacing.base),
                          itemCount: _issues.length,
                          itemBuilder: (context, index) {
                            final issue = _issues[index];
                            return Card(
                              margin: const EdgeInsets.only(bottom: 12),
                              child: Padding(
                                padding: const EdgeInsets.all(14),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            issue.title,
                                            style: const TextStyle(
                                                fontSize: 16,
                                                fontWeight: FontWeight.w600),
                                          ),
                                        ),
                                        _buildStatusChip(issue.status),
                                      ],
                                    ),
                                    if ((issue.description ?? '')
                                        .isNotEmpty) ...[
                                      const SizedBox(height: 6),
                                      Text(issue.description!),
                                    ],
                                    const SizedBox(height: 8),
                                    Row(
                                      children: [
                                        Icon(Icons.flag,
                                            size: 14,
                                            color:
                                                _priorityColor(issue.priority)),
                                        const SizedBox(width: 4),
                                        Text(
                                          issue.priority,
                                          style: TextStyle(
                                              fontSize: 12,
                                              color: _priorityColor(
                                                  issue.priority)),
                                        ),
                                        const Spacer(),
                                        Text(
                                          '${issue.createdAt.month}/${issue.createdAt.day}/${issue.createdAt.year}',
                                          style: const TextStyle(
                                              fontSize: 12,
                                              color: AppColors.textTertiary),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
      floatingActionButton: isPreview
          ? null
          : FloatingActionButton.extended(
              onPressed: _showReportIssueDialog,
              icon: const Icon(Icons.add),
              label: const Text('Report an issue'),
            ),
    );
  }
}
