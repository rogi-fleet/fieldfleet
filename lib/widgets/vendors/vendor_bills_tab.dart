import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../models/document_status.dart';
import '../../models/document_type.dart';
import '../../models/generated_document.dart';
import '../../models/project.dart';
import '../../models/vendor.dart';
import '../../providers/workspace_provider.dart';
import '../../services/service_locator.dart';
import '../../theme/theme.dart';
import '../../utils/project_terminology.dart';

class VendorBillsTab extends StatefulWidget {
  final Vendor vendor;

  const VendorBillsTab({super.key, required this.vendor});

  @override
  State<VendorBillsTab> createState() => _VendorBillsTabState();
}

class _VendorBillsTabState extends State<VendorBillsTab> {
  final dynamic _documentService = ServiceLocator.documentService;
  final dynamic _projectService = ServiceLocator.projectService;
  late final Future<Map<String, Project>> _projectsFuture;

  @override
  void initState() {
    super.initState();
    _projectsFuture = _loadProjects();
  }

  @override
  Widget build(BuildContext context) {
    final singularTerminology = singularProjectTerminology(
      context.watch<WorkspaceProvider>().projectTerminology,
    );

    // Light content surface — this tab uses light-mode content colors, so
    // without it the empty-state heading renders dark-on-dark over the
    // chrome background.
    return ColoredBox(
      color: AppColors.background,
      child: FutureBuilder<Map<String, Project>>(
      future: _projectsFuture,
      builder: (context, projectSnapshot) {
        final projectsById = projectSnapshot.data ?? const <String, Project>{};

        return StreamBuilder<List<GeneratedDocument>>(
          stream: _documentService.getDocuments(
            widget.vendor.workspaceId,
            documentType: DocumentType.bill,
          ),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            final bills = (snapshot.data ?? const <GeneratedDocument>[])
                .where((d) => d.vendorId == widget.vendor.id)
                .toList();

            if (bills.isEmpty) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.xl),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.receipt_long_outlined,
                        size: 56,
                        color: AppColors.textTertiary,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'No vendor bills yet',
                        style: TextStyle(
                          fontSize: 16,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Bills recorded for this vendor will appear here.',
                        style: TextStyle(color: AppColors.textTertiary),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              );
            }

            final currencyFormatter = NumberFormat.currency(symbol: '\$');

            return ListView.builder(
              padding: const EdgeInsets.all(AppSpacing.base),
              itemCount: bills.length,
              itemBuilder: (context, index) {
                final bill = bills[index];
                final statusColor = _statusColor(bill.status);

                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: statusColor.withAlpha(24),
                      child: Icon(Icons.receipt_outlined, color: statusColor),
                    ),
                    title: Row(
                      children: [
                        Expanded(
                          child: Text(
                            bill.documentNumber ?? bill.templateName,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                        Chip(
                          label: Text(
                            bill.status.displayName,
                            style: const TextStyle(fontSize: 11),
                          ),
                          backgroundColor: statusColor.withAlpha(30),
                          labelStyle: TextStyle(color: statusColor),
                          visualDensity: VisualDensity.compact,
                        ),
                      ],
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 4),
                        Text(
                          projectsById[bill.projectId]?.name ??
                              '$singularTerminology ${bill.projectId ?? ''}',
                        ),
                        const SizedBox(height: 2),
                        Text(
                          bill.paidDate != null
                              ? 'Paid ${DateFormat('MM/dd/yyyy').format(bill.paidDate!)}'
                              : bill.dueDate != null
                              ? 'Due ${DateFormat('MM/dd/yyyy').format(bill.dueDate!)}'
                              : '',
                          style: TextStyle(color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                    trailing: Text(
                      currencyFormatter.format(bill.lineItemsTotal),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    onTap: () {
                      if (bill.projectId != null) {
                        context.go('/projects/${bill.projectId}');
                      }
                    },
                  ),
                );
              },
            );
          },
        );
      },
      ),
    );
  }

  Future<Map<String, Project>> _loadProjects() async {
    final projects =
        await _projectService.getProjectsOnce(widget.vendor.workspaceId)
            as List<Project>;
    return {for (final project in projects) project.id: project};
  }

  Color _statusColor(DocumentStatus status) {
    switch (status) {
      case DocumentStatus.draft:
        return AppColors.textTertiary;
      case DocumentStatus.sent:
        return AppColors.info;
      case DocumentStatus.viewed:
        return AppColors.warning;
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
