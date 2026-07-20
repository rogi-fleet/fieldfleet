import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/file_tag.dart';
import '../../models/user_role.dart';
import '../../providers/auth_provider.dart';
import '../../services/service_locator.dart';
import '../../theme/theme.dart';
import '../../widgets/common/form_popup_footer.dart';
import '../../widgets/common/form_popup_scaffold.dart';

/// Workspace settings screen for managing file tags.
///
/// Lists every tag (active + archived), surfaces visibility + file count,
/// and opens an edit dialog for rename / recolor / role-restrict / archive.
/// Gated on `documents:write` by the parent nav — this screen assumes the
/// caller already checked that permission.
class FileTagManagerScreen extends StatefulWidget {
  const FileTagManagerScreen({super.key});

  @override
  State<FileTagManagerScreen> createState() => _FileTagManagerScreenState();
}

class _FileTagManagerScreenState extends State<FileTagManagerScreen> {
  late final _service = ServiceLocator.fileTagService;
  bool _showArchived = false;

  String get _workspaceId =>
      context.read<AuthProvider>().appUser?.currentWorkspaceId ?? '';

  Color _hexToColor(String hex) {
    var v = hex.replaceAll('#', '');
    if (v.length == 6) v = 'FF$v';
    if (v.length == 3) {
      v = v.split('').map((c) => '$c$c').join();
      v = 'FF$v';
    }
    return Color(int.parse(v, radix: 16));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('File Tags'),
        actions: [
          Row(
            children: [
              const Text('Show archived', style: TextStyle(fontSize: 12)),
              Switch(
                value: _showArchived,
                onChanged: (v) => setState(() => _showArchived = v),
              ),
              const SizedBox(width: 8),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'New tag',
            onPressed: _openCreateDialog,
          ),
        ],
      ),
      body: StreamBuilder<List<FileTag>>(
        stream: _service.streamWorkspaceTags(
          _workspaceId,
          includeArchived: true,
        ),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Text('Failed to load tags: ${snapshot.error}'),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final tags = snapshot.data!
              .where((t) => _showArchived || !t.isArchived)
              .toList();
          if (tags.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.xxxl),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.label_outline,
                      size: 48,
                      color: AppColors.textTertiary,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _showArchived
                          ? 'No tags yet'
                          : 'No active tags. Toggle "Show archived" to see older ones.',
                      style: TextStyle(color: AppColors.textSecondary),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            );
          }
          return ListView.separated(
            itemCount: tags.length,
            separatorBuilder: (_, __) =>
                Divider(height: 1, color: Theme.of(context).dividerColor),
            itemBuilder: (_, i) => _buildTagRow(tags[i]),
          );
        },
      ),
    );
  }

  Widget _buildTagRow(FileTag tag) {
    final color = _hexToColor(tag.color);
    final muted = tag.isArchived;
    return ListTile(
      onTap: () => _openEditDialog(tag),
      leading: CircleAvatar(
        radius: 10,
        backgroundColor: muted ? color.withValues(alpha: 0.4) : color,
      ),
      title: Row(
        children: [
          Expanded(
            child: Text(
              tag.name,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color:
                    muted ? AppColors.textSecondary : AppColors.textPrimary,
              ),
            ),
          ),
          if (muted)
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.surfaceAlt,
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              child: Text(
                'Archived',
                style: TextStyle(
                  fontSize: 11,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
        ],
      ),
      subtitle: Text(
        tag.isRestricted
            ? 'Visible to: ${tag.visibleToRoles.map(_roleLabel).join(", ")}'
            : 'Visible to everyone',
        style: TextStyle(
          fontSize: 12,
          color: tag.isRestricted
              ? AppColors.primary
              : AppColors.textSecondary,
        ),
      ),
      trailing: IconButton(
        icon: Icon(tag.isArchived ? Icons.unarchive : Icons.archive_outlined),
        tooltip: tag.isArchived ? 'Restore' : 'Archive',
        onPressed: () async {
          if (tag.isArchived) {
            await _service.restoreTag(tag.id);
          } else {
            await _service.archiveTag(tag.id);
          }
        },
      ),
    );
  }

  Future<void> _openCreateDialog() async {
    final result = await showFormPopup<_TagDraft>(
      context,
      icon: Icons.new_label,
      title: 'New tag',
      width: 400,
      builder: (popupContext, scrollController) => _TagEditorDialog(
        initial: const _TagDraft(),
        scrollController: scrollController,
      ),
    );
    if (result == null || !mounted) return;
    final userId = context.read<AuthProvider>().appUser?.id;
    await _service.createTag(
      workspaceId: _workspaceId,
      name: result.name,
      color: result.color,
      description: result.description,
      createdBy: userId,
      visibleToRoles: result.visibleToRoles,
    );
  }

  Future<void> _openEditDialog(FileTag tag) async {
    final result = await showFormPopup<_TagDraft>(
      context,
      icon: Icons.edit,
      title: 'Edit tag',
      width: 400,
      builder: (popupContext, scrollController) => _TagEditorDialog(
        initial: _TagDraft(
          name: tag.name,
          color: tag.color,
          description: tag.description ?? '',
          visibleToRoles: tag.visibleToRoles,
        ),
        scrollController: scrollController,
      ),
    );
    if (result == null) return;
    await _service.updateTag(
      tag.id,
      name: result.name,
      color: result.color,
      description: result.description,
      visibleToRoles: result.visibleToRoles,
    );
  }

  static String _roleLabel(String token) {
    if (token == '*') return 'Admins';
    // Match user_role_tokens format (snake_case role enum string).
    for (final r in UserRole.values) {
      if (_tokenFor(r) == token) return r.displayName;
    }
    // Probably a role_template_id — show truncated.
    return token.length > 8 ? '${token.substring(0, 8)}…' : token;
  }

  static String _tokenFor(UserRole role) {
    switch (role) {
      case UserRole.masterAdmin:
        return 'master_admin';
      case UserRole.admin:
        return 'admin';
      case UserRole.projectManager:
        return 'project_manager';
      case UserRole.fieldTechnician:
        return 'field_technician';
      case UserRole.client:
        return 'client';
      case UserRole.vendor:
        return 'vendor';
    }
  }
}

// ---------------------------------------------------------------------------
// Editor dialog — used for both create and edit
// ---------------------------------------------------------------------------

class _TagDraft {
  final String name;
  final String color;
  final String description;
  final List<String> visibleToRoles;

  const _TagDraft({
    this.name = '',
    this.color = '#64748B',
    this.description = '',
    this.visibleToRoles = const [],
  });
}

class _TagEditorDialog extends StatefulWidget {
  final _TagDraft initial;
  final ScrollController? scrollController;

  const _TagEditorDialog({
    required this.initial,
    this.scrollController,
  });

  @override
  State<_TagEditorDialog> createState() => _TagEditorDialogState();
}

class _TagEditorDialogState extends State<_TagEditorDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _descController;
  late String _color;
  late Set<String> _roleTokens;

  static const List<String> _palette = [
    '#64748B', // slate (default)
    '#2563EB', // blue
    '#16A34A', // green
    '#F59E0B', // amber
    '#DC2626', // red
    '#9333EA', // purple
    '#0891B2', // cyan
    '#EC4899', // pink
  ];

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initial.name);
    _descController = TextEditingController(text: widget.initial.description);
    _color = widget.initial.color;
    _roleTokens = {...widget.initial.visibleToRoles};
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descController.dispose();
    super.dispose();
  }

  Color _hex(String v) {
    var s = v.replaceAll('#', '');
    if (s.length == 6) s = 'FF$s';
    return Color(int.parse(s, radix: 16));
  }

  String _tokenFor(UserRole r) => _FileTagManagerScreenState._tokenFor(r);

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: SingleChildScrollView(
            controller: widget.scrollController,
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
              controller: _nameController,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Name',
                hintText: 'e.g. Photo, Contract, Work in progress',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _descController,
              minLines: 1,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Description (optional)',
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Color',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _palette.map((hex) {
                final selected = hex.toLowerCase() == _color.toLowerCase();
                return GestureDetector(
                  onTap: () => setState(() => _color = hex),
                  child: Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: _hex(hex),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: selected
                            ? AppColors.primary
                            : Colors.transparent,
                        width: 3,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 20),
            Text(
              'Visibility',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              _roleTokens.isEmpty
                  ? 'Everyone in the workspace can see files with this tag.'
                  : 'Only selected roles can see files carrying only this tag.',
              style: TextStyle(fontSize: 11, color: AppColors.textTertiary),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: UserRole.values.map((role) {
                final token = _tokenFor(role);
                final selected = _roleTokens.contains(token);
                return FilterChip(
                  label: Text(role.displayName),
                  selected: selected,
                  onSelected: (v) {
                    setState(() {
                      if (v) {
                        _roleTokens.add(token);
                      } else {
                        _roleTokens.remove(token);
                      }
                    });
                  },
                );
              }).toList(),
            ),
              ],
            ),
          ),
        ),
        FormPopupFooter(
          onSubmit: () {
            final name = _nameController.text.trim();
            if (name.isEmpty) return;
            Navigator.of(context).pop(_TagDraft(
              name: name,
              color: _color,
              description: _descController.text.trim(),
              visibleToRoles: _roleTokens.toList()..sort(),
            ));
          },
          submitLabel: 'Save',
        ),
      ],
    );
  }
}
