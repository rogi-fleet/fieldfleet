import 'package:flutter/material.dart';
import '../../utils/user_facing_error.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../../models/form_template.dart';
import '../../services/service_locator.dart';
import '../../providers/auth_provider.dart';
import '../../theme/theme.dart';
import '../../widgets/common/view_toolbar.dart';

class FormListScreen extends StatefulWidget {
  const FormListScreen({super.key});

  @override
  State<FormListScreen> createState() => _FormListScreenState();
}

class _FormListScreenState extends State<FormListScreen> {
  dynamic get _formService => ServiceLocator.formService;
  String _searchQuery = '';

  @override
  Widget build(BuildContext context) {
    final authProvider = context.watch<AuthProvider>();
    final workspaceId = authProvider.appUser?.currentWorkspaceId;
    final canManageForms = authProvider.canCreateProjects;

    if (workspaceId == null) {
      return const Scaffold(
        body: Center(child: Text('Error: No workspace found')),
      );
    }

    return Scaffold(
      body: Column(
        children: [
          ViewToolbar(
            searchHint: 'Search forms...',
            searchQuery: _searchQuery,
            onSearch: (query) => setState(() => _searchQuery = query.toLowerCase()),
          ),
          Expanded(
            child: StreamBuilder<List<FormTemplate>>(
              stream: _formService.getFormTemplates(workspaceId),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (snapshot.hasError) {
                  return Center(
                    child: SelectableText(
                      UserFacingError.uiMessage(
                        snapshot.error,
                        action: 'load data',
                      ),
                    ),
                  );
                }

                var forms = snapshot.data ?? [];

                // Filter by search query
                if (_searchQuery.isNotEmpty) {
                  forms = forms
                      .where(
                        (form) =>
                            form.name.toLowerCase().contains(_searchQuery) ||
                            (form.description?.toLowerCase().contains(
                                  _searchQuery,
                                ) ??
                                false),
                      )
                      .toList();
                }

                if (forms.isEmpty) {
                  return _buildEmptyState(context);
                }

                return ListView.builder(
                  itemCount: forms.length,
                  padding: EdgeInsets.fromLTRB(
                    16,
                    0,
                    16,
                    MediaQuery.paddingOf(context).bottom + 90,
                  ),
                  itemBuilder: (context, index) {
                    final form = forms[index];
                    return _buildFormCard(context, form);
                  },
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: canManageForms
          ? Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.paddingOf(context).bottom + 78,
              ),
              child: FloatingActionButton.extended(
                onPressed: () => context.go('/forms/new'),
                icon: const Icon(Icons.add),
                label: const Text('New Form'),
              ),
            )
          : null,
    );
  }

  Widget _buildFormCard(BuildContext context, FormTemplate form) {
    final canManageForms = context.watch<AuthProvider>().canCreateProjects;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: form.isPublic
              ? AppColors.success.withAlpha(51)
              : AppColors.textTertiary.withAlpha(51),
          child: Icon(
            Icons.dynamic_form,
            color: form.isPublic ? AppColors.success : AppColors.textTertiary,
          ),
        ),
        title: Text(form.name),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (form.description != null && form.description!.isNotEmpty)
              Text(
                form.description!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(
                  Icons.text_fields,
                  size: 14,
                  color: AppColors.textSecondary,
                ),
                const SizedBox(width: 4),
                Text(
                  '${form.fieldCount} fields',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(width: 16),
                if (form.isPublic) ...[
                  Icon(Icons.public, size: 14, color: AppColors.successDark),
                  const SizedBox(width: 4),
                  Text(
                    'Public',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.successDark,
                    ),
                  ),
                ] else ...[
                  Icon(Icons.lock, size: 14, color: AppColors.textSecondary),
                  const SizedBox(width: 4),
                  Text(
                    'Private',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
        trailing: PopupMenuButton<String>(
          onSelected: (value) async {
            switch (value) {
              case 'edit':
                context.go('/forms/${form.id}/edit');
                break;
              case 'view':
                context.go('/forms/${form.id}');
                break;
              case 'submissions':
                context.go('/forms/${form.id}/submissions');
                break;
              case 'duplicate':
                await _duplicateForm(context, form);
                break;
              case 'delete':
                await _deleteForm(context, form);
                break;
            }
          },
          itemBuilder: (context) => [
            const PopupMenuItem(
              value: 'view',
              child: Row(
                children: [
                  Icon(Icons.visibility, size: 20),
                  SizedBox(width: 12),
                  Text('View Details'),
                ],
              ),
            ),
            const PopupMenuItem(
              value: 'submissions',
              child: Row(
                children: [
                  Icon(Icons.list_alt, size: 20),
                  SizedBox(width: 12),
                  Text('View Submissions'),
                ],
              ),
            ),
            if (canManageForms)
              const PopupMenuItem(
                value: 'edit',
                child: Row(
                  children: [
                    Icon(Icons.edit, size: 20),
                    SizedBox(width: 12),
                    Text('Edit Form'),
                  ],
                ),
              ),
            if (canManageForms)
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
            if (canManageForms) const PopupMenuDivider(),
            if (canManageForms)
              PopupMenuItem(
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
        onTap: () => context.go('/forms/${form.id}'),
      ),
    );
  }

  Future<void> _duplicateForm(BuildContext context, FormTemplate form) async {
    try {
      final authProvider = context.read<AuthProvider>();
      final userId = authProvider.appUser?.id ?? '';

      await _formService.duplicateFormTemplate(
        formId: form.id,
        createdBy: userId,
      );

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Form duplicated successfully')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              UserFacingError.uiMessage(e, action: 'duplicating form'),
            ),
          ),
        );
      }
    }
  }

  Future<void> _deleteForm(BuildContext context, FormTemplate form) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Form'),
        content: Text(
          'Are you sure you want to delete "${form.name}"? This will also delete all submissions.',
        ),
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
        await _formService.deleteFormTemplate(form.id);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Form deleted successfully')),
          );
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                UserFacingError.uiMessage(e, action: 'deleting form'),
              ),
            ),
          );
        }
      }
    }
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.dynamic_form, size: 64, color: AppColors.textTertiary),
          const SizedBox(height: 16),
          Text(
            'No forms yet',
            style: TextStyle(fontSize: 18, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 8),
          Text(
            'Create your first form to collect information',
            style: TextStyle(fontSize: 14, color: AppColors.textTertiary),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: () => context.go('/forms/new'),
            icon: const Icon(Icons.add),
            label: const Text('Create Form'),
          ),
        ],
      ),
    );
  }
}
