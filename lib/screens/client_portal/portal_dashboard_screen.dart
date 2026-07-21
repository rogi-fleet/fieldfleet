import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../models/generated_document.dart';
import '../../models/project.dart';
import '../../models/project_status_theme.dart';
import '../../services/service_locator.dart';
import '../../theme/theme.dart';
import '../../utils/address_formatter.dart';
import '../../utils/user_facing_error.dart';
import 'portal_preview_scope.dart';

/// Dashboard screen for authenticated portal clients.
/// Shows accessible projects and invoices.
class PortalDashboardScreen extends StatefulWidget {
  const PortalDashboardScreen({super.key});

  @override
  State<PortalDashboardScreen> createState() => _PortalDashboardScreenState();
}

class _PortalDashboardScreenState extends State<PortalDashboardScreen> {
  final dynamic _portalService = ServiceLocator.clientPortalService;

  List<Project> _projects = [];
  String? _portalEmail;
  int _invoiceCount = 0;
  int _pendingActionCount = 0;
  List<GeneratedDocument> _pendingDocuments = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final preview = PortalPreviewScope.of(context);

      // Preview always shows the customer-wide dashboard (staff already see
      // the property directly) — only check restriction on a real login.
      if (preview == null) {
        final restrictedPropertyId =
            await _portalService.getMyRestrictedPropertyId() as String?;
        if (restrictedPropertyId != null) {
          if (mounted) context.go('/portal/property/$restrictedPropertyId');
          return;
        }
      }

      final projectsFuture =
          _portalService.getPortalProjects(previewCustomerId: preview);
      final invoicesFuture =
          _portalService.getPortalInvoices(previewCustomerId: preview);
      final projects = await projectsFuture as List<Project>;
      final invoices = await invoicesFuture as List;
      final portalEmail = preview != null
          ? null
          : _portalService.getPortalEmail() as String?;

      // Collect pending-action documents across all projects (parallel)
      final List<GeneratedDocument> pendingDocs = [];
      final docFutures = projects.map((project) async {
        try {
          return await _portalService.getPortalProjectDocuments(
            project.id,
            previewCustomerId: preview,
          ) as List<GeneratedDocument>;
        } catch (_) {
          return <GeneratedDocument>[];
        }
      }).toList();
      final allProjectDocs = await Future.wait(docFutures);
      for (final docs in allProjectDocs) {
        pendingDocs.addAll(docs.where((d) => d.needsCustomerAction));
      }

      if (mounted) {
        setState(() {
          _projects = projects;
          _invoiceCount = invoices.length;
          _pendingActionCount = pendingDocs.length;
          _pendingDocuments = pendingDocs;
          _portalEmail = portalEmail;
          _isLoading = false;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = UserFacingError.uiMessage(e, action: 'load your dashboard');
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
        title: const Text('Customer Portal'),
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

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: AppColors.error),
            const SizedBox(height: 16),
            Text(_error ?? 'Unable to load your dashboard right now.'),
            const SizedBox(height: 16),
            ElevatedButton(onPressed: _loadData, child: const Text('Retry')),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView(
        padding: const EdgeInsets.all(AppSpacing.base),
        children: [
          Card(
            color: Theme.of(context).primaryColor.withValues(alpha: 0.1),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.base),
              child: Row(
                children: [
                  Icon(
                    Icons.person,
                    size: 48,
                    color: Theme.of(context).primaryColor,
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Welcome!',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          _portalEmail ?? 'Portal user',
                          style: const TextStyle(
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
          if (_pendingActionCount > 0) ...[
            const SizedBox(height: 16),
            Card(
              color: AppColors.warningLight,
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: AppColors.warning,
                  child: Text(
                    '$_pendingActionCount',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                title: Text(
                  _pendingActionCount == 1
                      ? '1 document needs your attention'
                      : '$_pendingActionCount documents need your attention',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: const Text('Review, approve, or request changes'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  if (_pendingDocuments.length == 1) {
                    context.go(
                      PortalPreviewScope.appendPreview(
                        context,
                        '/portal/documents/${_pendingDocuments.first.id}',
                      ),
                    );
                  } else if (_pendingDocuments.isNotEmpty) {
                    _showPendingDocumentsSheet();
                  }
                },
              ),
            ),
          ],
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: _buildStatCard(
                  icon: Icons.folder,
                  label: 'Projects',
                  value: _projects.length.toString(),
                  color: AppColors.success,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildStatCard(
                  icon: Icons.receipt_long,
                  label: 'Invoices',
                  value: _invoiceCount.toString(),
                  color: AppColors.info,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Card(
            child: ListTile(
              leading: const Icon(Icons.payments, color: AppColors.info),
              title: const Text('View All Invoices'),
              subtitle: const Text(
                'Open invoice list with due dates and status',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.go(
                PortalPreviewScope.appendPreview(context, '/portal/invoices'),
              ),
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'Your Projects',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          if (_projects.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(AppSpacing.lg),
                child: Column(
                  children: [
                    Icon(
                      Icons.folder_open,
                      size: 48,
                      color: AppColors.textTertiary,
                    ),
                    SizedBox(height: 12),
                    Text(
                      'No projects yet',
                      style: TextStyle(
                        fontSize: 18,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            ..._projects.map((project) {
              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: _getStatusColor(
                      project.status,
                    ).withValues(alpha: 0.2),
                    child: Icon(
                      Icons.folder,
                      color: _getStatusColor(project.status),
                    ),
                  ),
                  title: Text(project.name),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(AddressFormatter.condense(project.address)),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.sm,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: _getStatusColor(
                            project.status,
                          ).withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(AppRadius.r12),
                        ),
                        child: Text(
                          project.status.displayName,
                          style: TextStyle(
                            fontSize: 12,
                            color: _getStatusColor(project.status),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.go(
                    PortalPreviewScope.appendPreview(
                      context,
                      '/portal/projects/${project.id}',
                    ),
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _buildStatCard({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.base),
        child: Column(
          children: [
            Icon(icon, size: 32, color: color),
            const SizedBox(height: 8),
            Text(
              value,
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            Text(label, style: const TextStyle(color: AppColors.textSecondary)),
          ],
        ),
      ),
    );
  }

  void _showPendingDocumentsSheet() {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text(
                'Documents Needing Action',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
            ...(_pendingDocuments.map((doc) {
              return ListTile(
                leading: const Icon(Icons.description, color: AppColors.info),
                title: Text(doc.templateName),
                subtitle: doc.documentNumber != null
                    ? Text('#${doc.documentNumber}')
                    : null,
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.pop(context);
                  this.context.go(
                    PortalPreviewScope.appendPreview(
                      this.context,
                      '/portal/documents/${doc.id}',
                    ),
                  );
                },
              );
            })),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Color _getStatusColor(ProjectStatus status) {
    return ProjectStatusTheme.color(status);
  }
}
