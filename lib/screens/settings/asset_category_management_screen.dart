import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/asset_category_config.dart';
import '../../providers/auth_provider.dart';
import '../../services/supabase/asset_category_service.dart';
import '../../theme/theme.dart';
import '../../utils/user_facing_error.dart';
import '../../widgets/common/form_popup_footer.dart';
import '../../widgets/common/form_popup_scaffold.dart';

/// Workspace settings page for managing asset categories. Mirrors the
/// customer-type management screen's UX so admins find it familiar:
/// list with reorder, add via dialog, edit + recolor in place, delete
/// with reassign confirmation.
class AssetCategoryManagementScreen extends StatefulWidget {
  const AssetCategoryManagementScreen({super.key});

  @override
  State<AssetCategoryManagementScreen> createState() =>
      _AssetCategoryManagementScreenState();
}

class _AssetCategoryManagementScreenState
    extends State<AssetCategoryManagementScreen> {
  final _service = SupabaseAssetCategoryService();

  String? get _workspaceId {
    final user = context.read<AuthProvider>().appUser;
    return user?.activeWorkspaceId ?? user?.workspaceId;
  }

  Future<void> _showEditor({AssetCategoryConfig? existing}) async {
    final result = await showFormPopup<_CategoryEditorResult>(
      context,
      icon: existing == null ? Icons.category : Icons.edit,
      title: existing == null ? 'New category' : 'Edit category',
      width: 480,
      builder: (popupContext, scrollController) => _CategoryEditorDialog(
        existing: existing,
        scrollController: scrollController,
      ),
    );
    if (result == null) return;

    final workspaceId = _workspaceId;
    if (workspaceId == null) return;

    try {
      if (existing == null) {
        await _service.create(
          workspaceId: workspaceId,
          name: result.name,
          color: result.color,
          iconName: result.iconName,
        );
      } else {
        await _service.update(
          workspaceId: workspaceId,
          id: existing.id,
          oldName: existing.name,
          newName: result.name,
          color: result.color,
          iconName: result.iconName,
        );
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              Text(existing == null ? 'Category created' : 'Category updated'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      final msg = e.toString().contains('duplicate key') ||
              e.toString().contains('unique constraint')
          ? 'A category with that name already exists'
          : UserFacingError.uiMessage(e, action: 'save category');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  Future<void> _confirmDelete(AssetCategoryConfig category) async {
    final workspaceId = _workspaceId;
    if (workspaceId == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete "${category.name}"?'),
        content: const Text(
          'Any equipment in this category will be reassigned to "Other". '
          'This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await _service.delete(
        workspaceId: workspaceId,
        id: category.id,
        name: category.name,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Category deleted')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              Text(UserFacingError.uiMessage(e, action: 'delete category')),
        ),
      );
    }
  }

  Future<void> _reorder(List<AssetCategoryConfig> items) async {
    try {
      await _service.reorder(items.map((c) => c.id).toList());
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(UserFacingError.uiMessage(e, action: 'reorder')),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // Establish a dependency on AuthProvider so this rebuilds once appUser
    // hydrates. On a cold load/refresh appUser is briefly null and the
    // read-based _workspaceId getter would otherwise render a permanent
    // "No active workspace" with no rebuild.
    context.watch<AuthProvider>();
    final workspaceId = _workspaceId;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Equipment Categories'),
        actions: [
          IconButton(
            tooltip: 'Add category',
            icon: const Icon(Icons.add),
            onPressed: workspaceId == null ? null : () => _showEditor(),
          ),
        ],
      ),
      body: workspaceId == null
          ? const Center(child: Text('No active workspace'))
          : StreamBuilder<List<AssetCategoryConfig>>(
              stream: _service.streamCategories(workspaceId),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(
                    child: SelectableText(
                      UserFacingError.uiMessage(
                        snapshot.error,
                        action: 'load categories',
                      ),
                    ),
                  );
                }
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                final categories = snapshot.data ?? const [];
                if (categories.isEmpty) {
                  return const Center(
                    child: Text('No categories yet. Tap + to add one.'),
                  );
                }
                return ReorderableListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                  itemCount: categories.length,
                  onReorder: (oldIndex, newIndex) {
                    final reordered = [...categories];
                    if (newIndex > oldIndex) newIndex -= 1;
                    final moved = reordered.removeAt(oldIndex);
                    reordered.insert(newIndex, moved);
                    _reorder(reordered);
                  },
                  itemBuilder: (context, index) {
                    final c = categories[index];
                    return ListTile(
                      key: ValueKey(c.id),
                      leading: CircleAvatar(
                        backgroundColor: c.colorValue.withValues(alpha: 0.2),
                        child: Icon(c.icon, color: c.colorValue, size: 20),
                      ),
                      title: Text(c.name),
                      subtitle: c.isDefault
                          ? const Text(
                              'Default',
                              style: TextStyle(
                                fontSize: 11,
                                color: AppColors.textTertiary,
                              ),
                            )
                          : null,
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.edit_outlined),
                            tooltip: 'Edit',
                            onPressed: () => _showEditor(existing: c),
                          ),
                          IconButton(
                            icon: const Icon(
                              Icons.delete_outline,
                              color: AppColors.error,
                            ),
                            tooltip: 'Delete',
                            onPressed: () => _confirmDelete(c),
                          ),
                          const Icon(Icons.drag_handle),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
    );
  }
}

class _CategoryEditorResult {
  final String name;
  final String color;
  final String iconName;

  _CategoryEditorResult({
    required this.name,
    required this.color,
    required this.iconName,
  });
}

class _CategoryEditorDialog extends StatefulWidget {
  final AssetCategoryConfig? existing;
  final ScrollController? scrollController;

  const _CategoryEditorDialog({this.existing, this.scrollController});

  @override
  State<_CategoryEditorDialog> createState() => _CategoryEditorDialogState();
}

class _CategoryEditorDialogState extends State<_CategoryEditorDialog> {
  late TextEditingController _nameController;
  late String _color;
  late String _iconName;

  static const _palette = <String>[
    '#2196F3',
    '#4CAF50',
    '#FF9800',
    '#F44336',
    '#9C27B0',
    '#3F51B5',
    '#00ACC1',
    '#795548',
    '#9E9E9E',
    '#E65100',
  ];

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _nameController = TextEditingController(text: existing?.name ?? '');
    _color = existing?.color ?? _palette.first;
    _iconName = existing?.iconName ?? 'category_outlined';
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: SingleChildScrollView(
            controller: widget.scrollController,
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _nameController,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'Name',
                    border: OutlineInputBorder(),
                    hintText: 'e.g. Power tools',
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Color',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final hex in _palette)
                      GestureDetector(
                        onTap: () => setState(() => _color = hex),
                        child: Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: _hexToColor(hex),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: hex == _color
                                  ? AppColors.primary
                                  : AppColors.cardBorder,
                              width: hex == _color ? 3 : 1,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                const Text(
                  'Icon',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final entry in assetCategoryIconPicker())
                      GestureDetector(
                        onTap: () => setState(() => _iconName = entry.key),
                        child: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: entry.key == _iconName
                                ? AppColors.primary.withValues(alpha: 0.12)
                                : AppColors.surfaceAlt,
                            borderRadius: BorderRadius.circular(AppRadius.sm),
                            border: Border.all(
                              color: entry.key == _iconName
                                  ? AppColors.primary
                                  : AppColors.cardBorder,
                              width: entry.key == _iconName ? 2 : 1,
                            ),
                          ),
                          child: Icon(
                            entry.value,
                            size: 20,
                            color: entry.key == _iconName
                                ? AppColors.primary
                                : AppColors.textSecondary,
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
        FormPopupFooter(
          onSubmit: () {
            final name = _nameController.text.trim();
            if (name.isEmpty) return;
            Navigator.pop(
              context,
              _CategoryEditorResult(
                name: name,
                color: _color,
                iconName: _iconName,
              ),
            );
          },
          submitLabel: isEdit ? 'Save' : 'Create',
        ),
      ],
    );
  }

  Color _hexToColor(String hex) {
    final cleaned = hex.replaceFirst('#', '').padLeft(6, '0');
    return Color(0xFF000000 | (int.tryParse(cleaned, radix: 16) ?? 0x9E9E9E));
  }
}
