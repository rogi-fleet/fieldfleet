import 'package:flutter/material.dart';
import '../../utils/user_facing_error.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../../models/document_template.dart';
import '../../models/document_type.dart';
import '../../models/template_category.dart';
import '../../services/service_locator.dart';
import '../../providers/auth_provider.dart';
import '../../theme/theme.dart';
import '../../widgets/common/list_skeleton.dart';

class TemplateListScreen extends StatefulWidget {
  const TemplateListScreen({super.key});

  @override
  State<TemplateListScreen> createState() => _TemplateListScreenState();
}

class _TemplateListScreenState extends State<TemplateListScreen> {
  final _templateService = ServiceLocator.documentTemplateService;
  DocumentType? _filterType;

  IconData _getIconForType(DocumentType type) {
    switch (type) {
      case DocumentType.invoice:
      case DocumentType.progressInvoice:
        return Icons.receipt_long;
      case DocumentType.workOrder:
      case DocumentType.workOrderEmergency:
      case DocumentType.workOrderMaintenance:
        return Icons.assignment;
      case DocumentType.quotation:
        return Icons.request_quote;
      case DocumentType.expense:
        return Icons.money_off;
      case DocumentType.bill:
        return Icons.receipt;
      case DocumentType.purchaseOrder:
        return Icons.shopping_cart;
      case DocumentType.custom:
        return Icons.description;
      default:
        return type.category.icon;
    }
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = context.watch<AuthProvider>();
    final workspaceId = authProvider.appUser?.currentWorkspaceId;

    if (workspaceId == null) {
      return const Scaffold(
        body: Center(child: Text('Error: No workspace found')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Document Templates'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/documents'),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Create Template',
            onPressed: () => context.go('/documents/templates/new'),
          ),
          PopupMenuButton<DocumentType?>(
            icon: const Icon(Icons.filter_list),
            onSelected: (type) {
              setState(() {
                _filterType = type;
              });
            },
            itemBuilder: (context) => [
              const PopupMenuItem(value: null, child: Text('All Types')),
              ...DocumentType.values.map(
                (type) => PopupMenuItem(
                  value: type,
                  child: Row(
                    children: [
                      Icon(_getIconForType(type), size: 20),
                      const SizedBox(width: 12),
                      Text(type.displayName),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
      body: StreamBuilder<List<DocumentTemplate>>(
        stream: _templateService.getTemplates(workspaceId, type: _filterType),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const ListSkeleton();
          }

          if (snapshot.hasError) {
            return Center(
              child: SelectableText(
                UserFacingError.uiMessage(snapshot.error, action: 'load data'),
              ),
            );
          }

          final templates = snapshot.data ?? [];

          if (templates.isEmpty) {
            return _buildEmptyState(context, workspaceId);
          }

          // Group templates by type
          final groupedTemplates = <DocumentType, List<DocumentTemplate>>{};
          for (final template in templates) {
            groupedTemplates.putIfAbsent(template.type, () => []).add(template);
          }

          return ListView.builder(
            padding: const EdgeInsets.all(AppSpacing.base),
            itemCount: groupedTemplates.length,
            itemBuilder: (context, index) {
              final type = groupedTemplates.keys.elementAt(index);
              final typeTemplates = groupedTemplates[type]!;

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (index > 0) const SizedBox(height: 24),
                  Row(
                    children: [
                      Icon(
                        _getIconForType(type),
                        size: 20,
                        color: AppColors.textPrimary,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        type.displayName,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ...typeTemplates.map(
                    (template) => _buildTemplateCard(context, template),
                  ),
                ],
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.go('/documents/templates/new'),
        icon: const Icon(Icons.add),
        label: const Text('New Template'),
      ),
    );
  }

  Widget _buildTemplateCard(BuildContext context, DocumentTemplate template) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: template.isDefault
              ? AppColors.success.withAlpha(51)
              : AppColors.textTertiary.withAlpha(51),
          child: Icon(
            _getIconForType(template.type),
            color: template.isDefault
                ? AppColors.success
                : AppColors.textTertiary,
          ),
        ),
        title: Row(
          children: [
            Text(template.name),
            if (template.isDefault) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.success.withAlpha(51),
                  borderRadius: BorderRadius.circular(AppRadius.r12),
                ),
                child: Text(
                  'Default',
                  style: TextStyle(
                    fontSize: 10,
                    color: AppColors.success,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ],
        ),
        subtitle: Text(template.type.displayName),
        trailing: PopupMenuButton<String>(
          onSelected: (value) async {
            switch (value) {
              case 'edit':
                context.go('/documents/templates/${template.id}/edit');
                break;
              case 'use':
                await _useTemplate(context, template);
                break;
              case 'duplicate':
                await _duplicateTemplate(context, template);
                break;
              case 'delete':
                await _deleteTemplate(context, template);
                break;
            }
          },
          itemBuilder: (context) => [
            const PopupMenuItem(
              value: 'use',
              child: Row(
                children: [
                  Icon(Icons.add_circle_outline, size: 20),
                  SizedBox(width: 12),
                  Text('Create Document'),
                ],
              ),
            ),
            const PopupMenuItem(
              value: 'edit',
              child: Row(
                children: [
                  Icon(Icons.edit, size: 20),
                  SizedBox(width: 12),
                  Text('Edit Template'),
                ],
              ),
            ),
            const PopupMenuItem(
              value: 'duplicate',
              child: Row(
                children: [
                  Icon(Icons.copy, size: 20),
                  SizedBox(width: 12),
                  Text('Duplicate'),
                ],
              ),
            ),
            const PopupMenuDivider(),
            const PopupMenuItem(
              value: 'delete',
              child: Row(
                children: [
                  Icon(Icons.delete, size: 20, color: AppColors.error),
                  SizedBox(width: 12),
                  Text('Delete', style: TextStyle(color: AppColors.error)),
                ],
              ),
            ),
          ],
        ),
        onTap: () => context.go('/documents/templates/${template.id}/edit'),
      ),
    );
  }

  Future<void> _useTemplate(
    BuildContext context,
    DocumentTemplate template,
  ) async {
    // Navigate to create document screen with pre-selected template
    context.go('/documents/create?templateId=${template.id}');
  }

  Future<void> _duplicateTemplate(
    BuildContext context,
    DocumentTemplate template,
  ) async {
    try {
      final authProvider = context.read<AuthProvider>();
      final userId = authProvider.appUser?.id ?? '';

      await _templateService.duplicateTemplate(
        templateId: template.id,
        createdBy: userId,
      );

      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Template duplicated')));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              UserFacingError.uiMessage(e, action: 'complete this action'),
            ),
          ),
        );
      }
    }
  }

  Future<void> _deleteTemplate(
    BuildContext context,
    DocumentTemplate template,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Template'),
        content: Text('Are you sure you want to delete "${template.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await _templateService.deleteTemplate(template.id);
        if (context.mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Template deleted')));
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                UserFacingError.uiMessage(e, action: 'complete this action'),
              ),
            ),
          );
        }
      }
    }
  }

  Widget _buildEmptyState(BuildContext context, String workspaceId) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.article, size: 64, color: AppColors.textTertiary),
          const SizedBox(height: 16),
          Text(
            'No templates yet',
            style: TextStyle(fontSize: 18, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 8),
          Text(
            'Create your first document template',
            style: TextStyle(fontSize: 14, color: AppColors.textTertiary),
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ElevatedButton.icon(
                onPressed: () => context.go('/documents/templates/new'),
                icon: const Icon(Icons.add),
                label: const Text('Create Template'),
              ),
              const SizedBox(width: 16),
              OutlinedButton.icon(
                onPressed: () async {
                  try {
                    final authProvider = context.read<AuthProvider>();
                    final userId = authProvider.appUser?.id ?? '';
                    await _templateService.initializeDefaultTemplates(
                      workspaceId,
                      userId,
                    );
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Default templates created'),
                        ),
                      );
                    }
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            UserFacingError.uiMessage(
                              e,
                              action: 'complete this action',
                            ),
                          ),
                        ),
                      );
                    }
                  }
                },
                icon: const Icon(Icons.auto_fix_high),
                label: const Text('Generate Defaults'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
