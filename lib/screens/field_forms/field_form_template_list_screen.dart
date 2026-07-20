import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../models/field_form_template.dart';
import '../../providers/auth_provider.dart';
import '../../services/service_locator.dart';
import '../../widgets/common/list_skeleton.dart';
import '../../widgets/common/module_header.dart';
import '../../theme/theme.dart';

class FieldFormTemplateListScreen extends StatefulWidget {
  const FieldFormTemplateListScreen({super.key});

  @override
  State<FieldFormTemplateListScreen> createState() =>
      _FieldFormTemplateListScreenState();
}

class _FieldFormTemplateListScreenState
    extends State<FieldFormTemplateListScreen> {
  final _searchController = TextEditingController();
  String _searchQuery = '';
  FieldFormCategory? _filterCategory;

  dynamic get _service => ServiceLocator.fieldFormService;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = context.watch<AuthProvider>();
    final workspaceId = authProvider.appUser?.currentWorkspaceId;

    return Scaffold(
      body: Column(
        children: [
          ModuleHeader(
            icon: Icons.assignment_outlined,
            title: 'Field Forms',
            description:
                'Field-collected inspections, checklists and submissions.',
            trailing: [
              IconButton(
                icon: const Icon(Icons.add),
                tooltip: 'New Template',
                onPressed: () => context.push('/field-forms/new'),
              ),
            ],
          ),
          _buildSearchAndFilter(context),
          Expanded(
            child: workspaceId == null
                ? const Center(child: Text('No workspace selected'))
                : StreamBuilder<List<FieldFormTemplate>>(
                    stream: _service.getTemplates(workspaceId),
                    builder: (context, snapshot) {
                      if (snapshot.hasError) {
                        return Center(child: Text('Error: ${snapshot.error}'));
                      }
                      if (!snapshot.hasData) {
                        return const ListSkeleton();
                      }
                      final all = snapshot.data!;
                      final filtered = _applyFilters(all);
                      if (filtered.isEmpty) {
                        return _buildEmptyState(context, all.isEmpty);
                      }
                      return ListView.builder(
                        padding: const EdgeInsets.all(AppSpacing.base),
                        itemCount: filtered.length,
                        itemBuilder: (context, index) =>
                            _TemplateCard(
                              template: filtered[index],
                              onEdit: () => context.push(
                                  '/field-forms/${filtered[index].id}/edit'),
                              onFill: () => context.push(
                                  '/field-forms/${filtered[index].id}/fill'),
                              onDuplicate: () =>
                                  _duplicate(context, filtered[index]),
                              onDelete: () =>
                                  _confirmDelete(context, filtered[index]),
                            ),
                      );
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/field-forms/new'),
        icon: const Icon(Icons.add),
        label: const Text('New Template'),
      ),
    );
  }

  Widget _buildSearchAndFilter(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search templates…',
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: () => setState(() {
                          _searchController.clear();
                          _searchQuery = '';
                        }),
                      )
                    : null,
                isDense: true,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadius.sm)),
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
              ),
              onChanged: (v) => setState(() => _searchQuery = v),
            ),
          ),
          const SizedBox(width: 8),
          PopupMenuButton<FieldFormCategory?>(
            tooltip: 'Filter by category',
            icon: Badge(
              isLabelVisible: _filterCategory != null,
              child: const Icon(Icons.filter_list),
            ),
            onSelected: (cat) => setState(() => _filterCategory = cat),
            itemBuilder: (_) => [
              const PopupMenuItem(value: null, child: Text('All categories')),
              ...FieldFormCategory.values.map(
                (c) => PopupMenuItem(value: c, child: Text(c.displayName)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  List<FieldFormTemplate> _applyFilters(List<FieldFormTemplate> templates) {
    var result = templates;
    if (_filterCategory != null) {
      result = result.where((t) => t.category == _filterCategory).toList();
    }
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      result = result
          .where((t) =>
              t.name.toLowerCase().contains(q) ||
              (t.description?.toLowerCase().contains(q) ?? false))
          .toList();
    }
    return result;
  }

  Widget _buildEmptyState(BuildContext context, bool noTemplatesAtAll) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.assignment_outlined,
                size: 64, color: AppColors.textTertiary),
            const SizedBox(height: 16),
            Text(
              noTemplatesAtAll
                  ? 'No field form templates yet'
                  : 'No templates match your filters',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              noTemplatesAtAll
                  ? 'Create a template for inspections, completions, safety checklists, and more.'
                  : 'Try clearing filters or searching something else.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary),
            ),
            if (noTemplatesAtAll) ...[
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: () => context.push('/field-forms/new'),
                icon: const Icon(Icons.add),
                label: const Text('Create Template'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _duplicate(BuildContext context, FieldFormTemplate template) async {
    final auth = context.read<AuthProvider>();
    final userId = auth.appUser?.id;
    if (userId == null) return;
    try {
      await _service.duplicateTemplate(
          templateId: template.id, createdBy: userId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Duplicated "${template.name}"')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  Future<void> _confirmDelete(
      BuildContext context, FieldFormTemplate template) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Template'),
        content: Text(
            'Delete "${template.name}"? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await _service.deleteTemplate(template.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Deleted "${template.name}"')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }
}

class _TemplateCard extends StatelessWidget {
  const _TemplateCard({
    required this.template,
    required this.onEdit,
    required this.onFill,
    required this.onDuplicate,
    required this.onDelete,
  });

  final FieldFormTemplate template;
  final VoidCallback onEdit;
  final VoidCallback onFill;
  final VoidCallback onDuplicate;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: AppSpacing.base, vertical: AppSpacing.sm),
        leading: CircleAvatar(
          backgroundColor: AppColors.primary.withOpacity(0.1),
          child: Icon(_categoryIcon(template.category),
              color: AppColors.primary, size: 20),
        ),
        title: Text(template.name,
            style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Row(
              children: [
                _CategoryChip(template.category),
                const SizedBox(width: 8),
                Text(
                  '${template.fieldCount} field${template.fieldCount == 1 ? '' : 's'}',
                  style: TextStyle(
                      fontSize: 12, color: AppColors.textSecondary),
                ),
                if (template.requiresAnySignature) ...[
                  const SizedBox(width: 8),
                  const Icon(Icons.draw_outlined,
                      size: 14, color: AppColors.textSecondary),
                  const SizedBox(width: 2),
                  Text('Signatures',
                      style: TextStyle(
                          fontSize: 12, color: AppColors.textSecondary)),
                ],
              ],
            ),
            if (template.description != null &&
                template.description!.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                template.description!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 12, color: AppColors.textSecondary),
              ),
            ],
          ],
        ),
        trailing: PopupMenuButton<String>(
          onSelected: (action) {
            switch (action) {
              case 'fill':
                onFill();
              case 'edit':
                onEdit();
              case 'duplicate':
                onDuplicate();
              case 'delete':
                onDelete();
            }
          },
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'fill', child: Text('Fill Form')),
            PopupMenuItem(value: 'edit', child: Text('Edit Template')),
            PopupMenuItem(value: 'duplicate', child: Text('Duplicate')),
            PopupMenuDivider(),
            PopupMenuItem(
              value: 'delete',
              child: Text('Delete', style: TextStyle(color: AppColors.error)),
            ),
          ],
        ),
        onTap: onFill,
      ),
    );
  }

  IconData _categoryIcon(FieldFormCategory cat) {
    switch (cat) {
      case FieldFormCategory.inspection:
        return Icons.search;
      case FieldFormCategory.completion:
        return Icons.check_circle_outline;
      case FieldFormCategory.safety:
        return Icons.shield_outlined;
      case FieldFormCategory.assessment:
        return Icons.assignment_outlined;
      case FieldFormCategory.custom:
        return Icons.description_outlined;
    }
  }
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip(this.category);
  final FieldFormCategory category;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 2),
      decoration: BoxDecoration(
        color: _color(category).withOpacity(0.1),
        borderRadius: BorderRadius.circular(AppRadius.r12),
        border: Border.all(color: _color(category).withOpacity(0.3)),
      ),
      child: Text(
        category.displayName,
        style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: _color(category)),
      ),
    );
  }

  Color _color(FieldFormCategory cat) {
    switch (cat) {
      case FieldFormCategory.inspection:
        return Colors.blue;
      case FieldFormCategory.completion:
        return Colors.green;
      case FieldFormCategory.safety:
        return Colors.orange;
      case FieldFormCategory.assessment:
        return Colors.purple;
      case FieldFormCategory.custom:
        return Colors.grey;
    }
  }
}
