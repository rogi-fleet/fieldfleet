import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../models/user_role.dart';
import '../../models/workspace_role_template.dart';
import '../../providers/auth_provider.dart';
import '../../services/role_template_service.dart';
import '../../services/service_locator.dart';
import '../../theme/theme.dart';
import '../../utils/module_permissions.dart';
import '../../utils/user_facing_error.dart';
import 'permission_matrix_screen.dart' show roleTooltipMessage;

class RoleTemplatesScreen extends StatefulWidget {
  const RoleTemplatesScreen({
    super.key,
    this.embedded = false,
    this.focusTemplateId,
  });

  /// When true, omit the Scaffold/AppBar and render just the body so the
  /// widget can live inside another screen (e.g. a tabbed shell).
  final bool embedded;

  /// If provided, auto-selects the matching template when the screen loads
  /// (or when the id changes while embedded).
  final String? focusTemplateId;

  @override
  State<RoleTemplatesScreen> createState() => RoleTemplatesScreenState();
}

class RoleTemplatesScreenState extends State<RoleTemplatesScreen> {
  /// Dirty-state signal for host screens to show a tab-level indicator.
  final ValueNotifier<bool> dirtyNotifier = ValueNotifier<bool>(false);

  /// Public reload for host screens that need to refresh after an
  /// external change (e.g. the matrix reloading after a save).
  Future<void> reload() => _loadTemplates();

  /// Public hook for a host screen's "Create role" button.
  Future<void> triggerCreate() => _createRole();

  /// Lets the host screen ask the editor for its discard-guard dialog
  /// before popping the shared screen.
  Future<bool> confirmDiscardChanges() => _confirmDiscardChanges();

  bool get hasUnsavedChanges => _hasUnsavedChanges;

  /// True when the mobile layout is showing a role detail view.
  /// The host screen uses this to route mobile back presses to
  /// [clearSelection] before popping the screen itself.
  bool get hasMobileSelection => _selectedTemplate != null;

  /// Discard-guarded selection clear. Used by the host screen's back
  /// button on mobile so there's a single source of truth for the
  /// "go back to role list" action.
  Future<void> clearSelection() async {
    if (!await _confirmDiscardChanges()) return;
    if (!mounted) return;
    setState(() => _selectedTemplate = null);
  }

  final RoleTemplateService _roleTemplateService =
      ServiceLocator.roleTemplateService;

  bool _isLoading = true;
  bool _isSaving = false;
  String? _workspaceId;
  List<WorkspaceRoleTemplate> _templates = const [];
  Map<String, TemplateUsage> _usage = const {};
  WorkspaceRoleTemplate? _selectedTemplate;

  // Edit state
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  bool _editIsAdmin = false;
  String _editInterfaceMode = 'manager';
  Map<String, String> _editPermissions = {};
  bool _hasUnsavedChanges = false;

  void _setDirty(bool dirty) {
    if (_hasUnsavedChanges == dirty) return;
    _hasUnsavedChanges = dirty;
    dirtyNotifier.value = dirty;
  }

  @override
  void initState() {
    super.initState();
    _loadTemplates();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    dirtyNotifier.dispose();
    super.dispose();
  }

  Future<void> _loadTemplates() async {
    final workspaceId =
        context.read<AuthProvider>().appUser?.currentWorkspaceId ?? '';

    if (workspaceId.isEmpty) {
      if (!mounted) return;
      setState(() {
        _workspaceId = null;
        _templates = const [];
        _isLoading = false;
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _workspaceId = workspaceId;
    });

    try {
      final results = await Future.wait([
        _roleTemplateService.getTemplates(workspaceId: workspaceId),
        _roleTemplateService.getUsageCounts(workspaceId: workspaceId),
      ]);
      final templates = results[0] as List<WorkspaceRoleTemplate>;
      final usage = results[1] as Map<String, TemplateUsage>;
      if (!mounted) return;
      setState(() {
        _templates = List<WorkspaceRoleTemplate>.from(templates);
        _usage = usage;
        _isLoading = false;
        // Preference order: explicit focus id → preserve selection → first.
        final focusId = widget.focusTemplateId;
        if (focusId != null) {
          final focus = _templates.where((t) => t.id == focusId);
          if (focus.isNotEmpty) {
            _selectTemplate(focus.first);
            return;
          }
        }
        if (_selectedTemplate == null && _templates.isNotEmpty) {
          _selectTemplate(_templates.first);
        } else if (_selectedTemplate != null) {
          final updated = _templates.where(
            (t) => t.id == _selectedTemplate!.id,
          );
          if (updated.isNotEmpty) {
            _selectTemplate(updated.first);
          }
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            UserFacingError.uiMessage(e, action: 'load role templates'),
          ),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  void _selectTemplate(WorkspaceRoleTemplate template) {
    setState(() {
      _selectedTemplate = template;
      _nameController.text = template.name;
      _descriptionController.text = template.description ?? '';
      _editIsAdmin = template.isAdmin;
      _editInterfaceMode = template.defaultInterfaceMode;
      _editPermissions = normalizeModulePermissions(
        Map<String, String>.from(template.modulePermissions),
      );
      _setDirty(false);
    });
  }

  Future<bool> _confirmDiscardChanges() async {
    if (!_hasUnsavedChanges) return true;
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Leave without saving?'),
        content: const Text(
          'Your changes to this role have not been saved. '
          'Leaving will discard them.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep editing'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.warning),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Leave without saving'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  void _markChanged() {
    if (!_hasUnsavedChanges) {
      setState(() => _setDirty(true));
    }
  }

  Future<void> _saveTemplate() async {
    if (_selectedTemplate == null || _workspaceId == null) return;

    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Role name is required')));
      return;
    }

    // Warn if turning admin off on a template that has assigned members.
    if (_selectedTemplate!.isAdmin && !_editIsAdmin) {
      final confirmed = await _confirmRemoveAdmin(_selectedTemplate!);
      if (!confirmed) return;
    }

    setState(() => _isSaving = true);
    try {
      await _roleTemplateService.updateTemplate(
        templateId: _selectedTemplate!.id,
        name: name,
        modulePermissions: _editPermissions,
        isAdmin: _editIsAdmin,
        defaultInterfaceMode: _editInterfaceMode,
        description: _descriptionController.text.trim().isEmpty
            ? null
            : _descriptionController.text.trim(),
        clearDescription: _descriptionController.text.trim().isEmpty,
      );
      setState(() => _setDirty(false));
      await _loadTemplates();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Role saved')));
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(UserFacingError.uiMessage(e, action: 'save the role')),
          backgroundColor: AppColors.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<bool> _confirmRemoveAdmin(WorkspaceRoleTemplate template) async {
    int memberCount = 0;
    try {
      memberCount = await _roleTemplateService.getMemberCountForTemplate(
        templateId: template.id,
      );
    } catch (_) {}

    if (!mounted) return false;
    final members = memberCount == 1 ? 'member' : 'members';
    final body = memberCount > 0
        ? 'Turning off admin on "${template.name}" will remove admin '
              'access from $memberCount $members assigned to this role. '
              'Continue?'
        : 'Turning off admin on "${template.name}" will remove admin '
              'access from anyone assigned to this role in the future. '
              'Continue?';

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove admin access?'),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove admin'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  String _uniqueName(String base) {
    final existingNames = _templates.map((t) => t.name).toSet();
    if (!existingNames.contains(base)) return base;
    for (var i = 2; ; i++) {
      final candidate = '$base $i';
      if (!existingNames.contains(candidate)) return candidate;
    }
  }

  Future<void> _createRole() async {
    if (_workspaceId == null) return;

    final result = await _showNewRoleDialog();
    if (result == null) return;

    setState(() => _isSaving = true);
    try {
      final template = await _roleTemplateService.createTemplate(
        workspaceId: _workspaceId!,
        name: result.name,
        modulePermissions: result.preset.permissions,
        isAdmin: result.preset.isAdmin,
        defaultInterfaceMode: result.preset.interfaceMode,
      );
      await _loadTemplates();
      if (mounted) {
        final created = _templates.where((t) => t.id == template.id);
        if (created.isNotEmpty) {
          _selectTemplate(created.first);
        }
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            UserFacingError.uiMessage(e, action: 'create the role'),
          ),
          backgroundColor: AppColors.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<_NewRoleResult?> _showNewRoleDialog() async {
    final nameController = TextEditingController(text: _uniqueName('New Role'));
    _RolePreset selectedPreset = _RolePreset.fieldTech;
    String? nameError;

    try {
      return await showDialog<_NewRoleResult>(
        context: context,
        builder: (dialogContext) {
          return StatefulBuilder(
            builder: (ctx, setDialogState) {
              bool validate() {
                final trimmed = nameController.text.trim();
                if (trimmed.isEmpty) {
                  setDialogState(() => nameError = 'Name is required');
                  return false;
                }
                final existing = _templates
                    .map((t) => t.name.toLowerCase())
                    .toSet();
                if (existing.contains(trimmed.toLowerCase())) {
                  setDialogState(
                    () => nameError = 'A role with this name already exists',
                  );
                  return false;
                }
                return true;
              }

              return AlertDialog(
                title: const Text('Create New Role'),
                content: SizedBox(
                  width: 420,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextField(
                        controller: nameController,
                        autofocus: true,
                        decoration: InputDecoration(
                          labelText: 'Role name',
                          border: const OutlineInputBorder(),
                          isDense: true,
                          errorText: nameError,
                        ),
                        onChanged: (_) {
                          if (nameError != null) {
                            setDialogState(() => nameError = null);
                          }
                        },
                      ),
                      const SizedBox(height: 20),
                      Text(
                        'Start from preset',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textSecondary,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 8),
                      ..._RolePreset.values.map((preset) {
                        return RadioListTile<_RolePreset>(
                          value: preset,
                          groupValue: selectedPreset,
                          onChanged: (v) {
                            if (v != null) {
                              setDialogState(() => selectedPreset = v);
                            }
                          },
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                          title: Text(preset.title),
                          subtitle: Text(
                            preset.subtitle,
                            style: const TextStyle(fontSize: 12),
                          ),
                        );
                      }),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(dialogContext, null),
                    child: const Text('Cancel'),
                  ),
                  FilledButton(
                    onPressed: () {
                      if (!validate()) return;
                      Navigator.pop(
                        dialogContext,
                        _NewRoleResult(
                          name: nameController.text.trim(),
                          preset: selectedPreset,
                        ),
                      );
                    },
                    child: const Text('Create'),
                  ),
                ],
              );
            },
          );
        },
      );
    } finally {
      nameController.dispose();
    }
  }

  Future<void> _cloneTemplate() async {
    if (_selectedTemplate == null) return;

    setState(() => _isSaving = true);
    try {
      final cloned = await _roleTemplateService.cloneTemplate(
        templateId: _selectedTemplate!.id,
        newName: _uniqueName('${_selectedTemplate!.name} (Copy)'),
      );
      await _loadTemplates();
      if (mounted) {
        final created = _templates.where((t) => t.id == cloned.id);
        if (created.isNotEmpty) {
          _selectTemplate(created.first);
        }
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(UserFacingError.uiMessage(e, action: 'clone the role')),
          backgroundColor: AppColors.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _deleteTemplate() async {
    if (_selectedTemplate == null || _selectedTemplate!.isSystem) return;
    final target = _selectedTemplate!;

    List<TemplateMemberSummary> members = const [];
    try {
      members = await _roleTemplateService.getMembersForTemplate(
        templateId: target.id,
      );
    } catch (_) {}

    if (!mounted) return;

    String? reassignToTemplateId;
    if (members.isNotEmpty) {
      reassignToTemplateId = await _showReassignAndDeleteDialog(
        target: target,
        members: members,
      );
      if (reassignToTemplateId == null) return;
    } else {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Delete Role?'),
          content: Text('Delete "${target.name}" permanently?'),
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
      if (confirmed != true) return;
    }

    setState(() => _isSaving = true);
    try {
      if (reassignToTemplateId != null) {
        final workspaceId = _workspaceId!;
        for (final member in members) {
          await ServiceLocator.workspaceMemberService.updateMemberRoleTemplate(
            workspaceId: workspaceId,
            userId: member.userId,
            roleTemplateId: reassignToTemplateId,
          );
        }
      }
      await _roleTemplateService.deleteTemplate(templateId: target.id);
      setState(() => _selectedTemplate = null);
      await _loadTemplates();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            UserFacingError.uiMessage(e, action: 'delete the role'),
          ),
          backgroundColor: AppColors.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<String?> _showReassignAndDeleteDialog({
    required WorkspaceRoleTemplate target,
    required List<TemplateMemberSummary> members,
  }) async {
    final options = _templates.where((t) => t.id != target.id).toList();
    if (options.isEmpty) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Cannot delete role'),
          content: const Text(
            'There are no other roles to reassign these members to. '
            'Create another role first, then try deleting.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return null;
    }

    String selectedId = options.first.id;

    return showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              title: Text('Delete "${target.name}"?'),
              content: SizedBox(
                width: 460,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${members.length} member${members.length == 1 ? '' : 's'} '
                      'currently assigned to this role. Pick a new role for '
                      'them before deleting.',
                      style: const TextStyle(fontSize: 13),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      constraints: const BoxConstraints(maxHeight: 160),
                      decoration: BoxDecoration(
                        border: Border.all(color: AppColors.cardBorder),
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                      ),
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: members.length,
                        separatorBuilder: (_, __) =>
                            Divider(height: 1, color: AppColors.cardBorder),
                        itemBuilder: (_, i) {
                          final m = members[i];
                          final label = (m.displayName?.isNotEmpty == true)
                              ? m.displayName!
                              : m.email;
                          return ListTile(
                            dense: true,
                            leading: Icon(
                              Icons.person_outline,
                              size: 18,
                              color: AppColors.textSecondary,
                            ),
                            title: Text(
                              label,
                              style: const TextStyle(fontSize: 13),
                            ),
                            subtitle:
                                (m.displayName?.isNotEmpty == true &&
                                    m.email.isNotEmpty)
                                ? Text(
                                    m.email,
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: AppColors.textTertiary,
                                    ),
                                  )
                                : null,
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Reassign to',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textSecondary,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<String>(
                      initialValue: selectedId,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      items: options.map((t) {
                        return DropdownMenuItem<String>(
                          value: t.id,
                          child: Row(
                            children: [
                              Icon(
                                t.isAdmin
                                    ? Icons.admin_panel_settings
                                    : Icons.person_outline,
                                size: 18,
                                color: t.isAdmin
                                    ? AppColors.messageAccent
                                    : AppColors.primary,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  t.name,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                      onChanged: (value) {
                        if (value != null) {
                          setDialogState(() => selectedId = value);
                        }
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, null),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.error,
                  ),
                  onPressed: () => Navigator.pop(dialogContext, selectedId),
                  child: const Text('Reassign and delete'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  void didUpdateWidget(covariant RoleTemplatesScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.focusTemplateId != null &&
        widget.focusTemplateId != oldWidget.focusTemplateId) {
      _focusTemplateById(widget.focusTemplateId!);
    }
  }

  void _focusTemplateById(String templateId) {
    final matches = _templates.where((t) => t.id == templateId);
    if (matches.isEmpty) return;
    final target = matches.first;
    if (_selectedTemplate?.id == target.id) return;
    _selectTemplate(target);
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = context.watch<AuthProvider>();
    final canManage = authProvider.canManageUsers;
    final isWide = MediaQuery.sizeOf(context).width > 720;

    final body = _isLoading
        ? const Center(child: CircularProgressIndicator())
        : !canManage
        ? const Center(
            child: Padding(
              padding: EdgeInsets.all(AppSpacing.xl),
              child: Text('Only workspace admins can manage roles.'),
            ),
          )
        : isWide
        ? _buildDesktopLayout()
        : _buildMobileLayout();

    if (widget.embedded) return body;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Roles & Permissions'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () async {
            if (await _confirmDiscardChanges()) context.pop();
          },
        ),
      ),
      body: body,
    );
  }

  // ---------------------------------------------------------------------------
  // Desktop: side-by-side master-detail
  // ---------------------------------------------------------------------------

  Widget _buildDesktopLayout() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: 280, child: _buildRoleList()),
        const VerticalDivider(width: 1),
        Expanded(
          child: _selectedTemplate != null
              ? _buildRoleEditor()
              : const Center(
                  child: Text(
                    'Select a role to edit',
                    style: TextStyle(color: AppColors.textTertiary),
                  ),
                ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Mobile: list with tap-to-edit
  // ---------------------------------------------------------------------------

  Widget _buildMobileLayout() {
    if (_selectedTemplate != null) {
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) async {
          if (!didPop && await _confirmDiscardChanges()) {
            setState(() => _selectedTemplate = null);
          }
        },
        child: _buildRoleEditor(),
      );
    }
    return _buildRoleList();
  }

  // ---------------------------------------------------------------------------
  // Role list (left panel)
  // ---------------------------------------------------------------------------

  Widget _buildRoleList() {
    final systemRoles = _templates.where((t) => t.isSystem).toList();
    final customRoles = _templates.where((t) => !t.isSystem).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header with + button
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
          child: Row(
            children: [
              Text(
                'ROLES',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textTertiary,
                  letterSpacing: 0.5,
                ),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.add, size: 20),
                tooltip: 'Create Role',
                onPressed: _isSaving ? null : _createRole,
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
            children: [
              if (systemRoles.isNotEmpty) ...[
                _buildSectionLabel('System Roles'),
                ...systemRoles.map(_buildRoleTile),
              ],
              if (customRoles.isNotEmpty) ...[
                const SizedBox(height: 12),
                _buildSectionLabel('Custom Roles'),
                ...customRoles.map(_buildRoleTile),
              ],
              if (customRoles.isEmpty) ...[
                const SizedBox(height: 12),
                _buildSectionLabel('Custom Roles'),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.base,
                    vertical: AppSpacing.sm,
                  ),
                  child: Text(
                    'No custom roles yet',
                    style: TextStyle(
                      color: AppColors.textTertiary,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSectionLabel(String label) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.base, vertical: AppSpacing.xs),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: AppColors.primary,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _buildRoleTile(WorkspaceRoleTemplate template) {
    final isSelected = _selectedTemplate?.id == template.id;
    final showsLiveEdits = isSelected && _hasUnsavedChanges;
    final displayName = showsLiveEdits && _nameController.text.trim().isNotEmpty
        ? _nameController.text
        : template.name;
    final displayIsAdmin = showsLiveEdits ? _editIsAdmin : template.isAdmin;
    return Tooltip(
      message: roleTooltipMessage(template),
      waitDuration: const Duration(milliseconds: 600),
      child: ListTile(
      dense: true,
      selected: isSelected,
      selectedTileColor: AppColors.primarySurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
      leading: Icon(
        displayIsAdmin ? Icons.admin_panel_settings : Icons.person_outline,
        size: 20,
        color: displayIsAdmin
            ? AppColors.secondary
            : isSelected
            ? AppColors.primary
            : AppColors.textSecondary,
      ),
      title: Row(
        children: [
          Flexible(
            child: Text(
              displayName,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 14,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                color: displayIsAdmin ? AppColors.secondary : null,
                fontStyle: showsLiveEdits ? FontStyle.italic : FontStyle.normal,
              ),
            ),
          ),
          if (displayIsAdmin) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: AppColors.secondary.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(AppRadius.xs),
              ),
              child: Text(
                'ADMIN',
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  color: AppColors.secondary,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ],
          if (showsLiveEdits) ...[
            const SizedBox(width: 6),
            Tooltip(
              message: 'Unsaved changes',
              child: Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: AppColors.warning,
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ],
        ],
      ),
      subtitle: _buildRoleTileSubtitle(template),
      onTap: () async {
        if (await _confirmDiscardChanges()) _selectTemplate(template);
      },
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Role editor (right panel)
  // ---------------------------------------------------------------------------

  Widget _buildRoleEditor() {
    final template = _selectedTemplate!;
    final isWide = MediaQuery.sizeOf(context).width > 720;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Mobile header. Suppressed when embedded because the
                // shell's app bar owns the back action for the whole
                // screen.
                if (!isWide && !widget.embedded)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.arrow_back),
                          onPressed: () async {
                            if (await _confirmDiscardChanges()) {
                              setState(() => _selectedTemplate = null);
                            }
                          },
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Edit Role',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ],
                    ),
                  ),

                Text(
                  'EDIT ${template.name.toUpperCase()} ROLE',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.secondary,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 20),

                // Name
                _buildFieldLabel('Name'),
                const SizedBox(height: 6),
                TextField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  onChanged: (_) => setState(() => _setDirty(true)),
                ),
                const SizedBox(height: 20),

                // Full admin access
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                    'Full admin access',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: template.isSystem && template.isAdmin
                      ? const Text(
                          'Cannot be disabled on the system Admin role',
                          style: TextStyle(fontSize: 12),
                        )
                      : null,
                  value: _editIsAdmin,
                  onChanged: template.isSystem && template.isAdmin
                      ? null
                      : (value) {
                          setState(() => _editIsAdmin = value);
                          _markChanged();
                        },
                ),
                const Divider(),
                const SizedBox(height: 12),

                // Description
                _buildFieldLabel('Description'),
                const SizedBox(height: 6),
                TextField(
                  controller: _descriptionController,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    isDense: true,
                    hintText: 'Optional description for this role',
                  ),
                  maxLines: 2,
                  onChanged: (_) => _markChanged(),
                ),
                const SizedBox(height: 24),

                // Module Permissions
                _buildFieldLabel('Module Permissions'),
                const SizedBox(height: 4),
                if (_editIsAdmin)
                  Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(AppSpacing.md),
                    decoration: BoxDecoration(
                      color: AppColors.secondary.withValues(alpha: 0.08),
                      border: Border.all(
                        color: AppColors.secondary.withValues(alpha: 0.3),
                      ),
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.admin_panel_settings,
                          size: 20,
                          color: AppColors.secondary,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Full admin access is enabled',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.secondary,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'All modules are granted Edit access regardless of '
                                'the per-module settings below. Disable "Full admin '
                                'access" above to use these settings.',
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
                ..._buildGroupedModuleRows(),

                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: AppColors.surface,
            border: Border(top: BorderSide(color: AppColors.cardBorder)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl, vertical: AppSpacing.md),
          child: Row(
            children: [
              if (!template.isSystem)
                OutlinedButton.icon(
                  onPressed: _isSaving ? null : _deleteTemplate,
                  icon: Icon(Icons.delete_outline, color: AppColors.error),
                  label: Text(
                    'Delete',
                    style: TextStyle(color: AppColors.error),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(
                      color: AppColors.error.withValues(alpha: 0.4),
                    ),
                  ),
                ),
              const Spacer(),
              TextButton.icon(
                onPressed: _isSaving ? null : _cloneTemplate,
                icon: const Icon(Icons.copy_outlined),
                label: const Text('Clone'),
              ),
              const SizedBox(width: 8),
              if (_hasUnsavedChanges)
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: Text(
                    'Unsaved changes',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.warning,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
              OutlinedButton(
                onPressed: _hasUnsavedChanges && !_isSaving
                    ? () => _selectTemplate(template)
                    : null,
                child: const Text('Cancel'),
              ),
              const SizedBox(width: 12),
              FilledButton(
                onPressed: _hasUnsavedChanges && !_isSaving
                    ? _saveTemplate
                    : null,
                child: _isSaving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('Save'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildFieldLabel(String label) {
    return Text(
      label,
      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
    );
  }

  Widget? _buildRoleTileSubtitle(WorkspaceRoleTemplate template) {
    final description = template.description?.trim();
    final usage = _usage[template.id] ?? TemplateUsage.empty;
    final parts = <String>[];
    if (usage.memberCount > 0) {
      parts.add(
        '${usage.memberCount} ${usage.memberCount == 1 ? 'member' : 'members'}',
      );
    }
    if (usage.pendingInvitationCount > 0) {
      parts.add('${usage.pendingInvitationCount} pending');
    }
    final usageText = parts.isEmpty ? null : parts.join(' · ');
    if (usageText == null && (description == null || description.isEmpty)) {
      return null;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (description != null && description.isNotEmpty)
          Text(
            description,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12, color: AppColors.textTertiary),
          ),
        if (usageText != null)
          Text(
            usageText,
            style: TextStyle(
              fontSize: 11,
              color: usage.memberCount > 0
                  ? AppColors.primary
                  : AppColors.textTertiary,
              fontWeight: FontWeight.w600,
            ),
          ),
      ],
    );
  }

  List<Widget> _buildGroupedModuleRows() {
    final byGroup = <ModuleGroup, List<String>>{};
    for (final key in orderedModuleKeys) {
      final group = moduleGroups[key] ?? ModuleGroup.system;
      byGroup.putIfAbsent(group, () => []).add(key);
    }
    final widgets = <Widget>[];
    for (final entry in byGroup.entries) {
      widgets.add(
        Padding(
          padding: const EdgeInsets.fromLTRB(0, 16, 0, 4),
          child: Text(
            (moduleGroupLabels[entry.key] ?? '').toUpperCase(),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
              color: AppColors.textTertiary,
            ),
          ),
        ),
      );
      for (final moduleKey in entry.value) {
        widgets.add(_buildModuleRow(moduleKey));
      }
    }
    return widgets;
  }

  Widget _buildModuleRow(String moduleKey) {
    final label = modulePermissionLabels[moduleKey] ?? moduleKey;
    final currentLevel = _editPermissions[moduleKey] ?? 'none';
    final isNarrow = MediaQuery.sizeOf(context).width < AppBreakpoints.mobile;
    final description = modulePermissionDescriptions[moduleKey];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(
            width: isNarrow ? 110 : 150,
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    label,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w500),
                  ),
                ),
                if (description != null) ...[
                  const SizedBox(width: 4),
                  Tooltip(
                    message: description,
                    triggerMode: TooltipTriggerMode.tap,
                    showDuration: const Duration(seconds: 6),
                    child: Icon(
                      Icons.help_outline,
                      size: 14,
                      color: AppColors.textTertiary,
                    ),
                  ),
                ],
              ],
            ),
          ),
          Expanded(
            child: SegmentedButton<String>(
              showSelectedIcon: false,
              segments: modulePermissionLevels.map((level) {
                final label = modulePermissionLevelLabels[level] ?? level;
                final shortLabel = _shortLevelLabel(level);
                return ButtonSegment(
                  value: level,
                  icon: Icon(_levelIcon(level), size: 16),
                  label: Text(isNarrow ? shortLabel : label),
                  tooltip: label,
                );
              }).toList(),
              selected: {currentLevel},
              onSelectionChanged: _editIsAdmin
                  ? null
                  : (values) {
                      setState(() {
                        _editPermissions[moduleKey] = values.first;
                      });
                      _markChanged();
                    },
            ),
          ),
          if (_editIsAdmin) ...[
            const SizedBox(width: 8),
            Tooltip(
              message: 'Overridden by Full admin access',
              child: Icon(
                Icons.lock_outline,
                size: 18,
                color: AppColors.textTertiary,
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _shortLevelLabel(String level) {
    switch (level) {
      case 'write':
        return 'Edit';
      case 'read':
        return 'View';
      default:
        return 'None';
    }
  }

  IconData _levelIcon(String level) {
    switch (level) {
      case 'write':
        return Icons.edit_outlined;
      case 'read':
        return Icons.visibility_outlined;
      default:
        return Icons.block_outlined;
    }
  }
}

enum _RolePreset {
  masterAdmin,
  admin,
  projectManager,
  fieldTech,
  client,
  vendor,
  blank;

  String get title {
    switch (this) {
      case _RolePreset.masterAdmin:
        return 'Master Admin — owner tier';
      case _RolePreset.admin:
        return 'Admin — full access';
      case _RolePreset.projectManager:
        return 'Project Manager';
      case _RolePreset.fieldTech:
        return 'Field Technician';
      case _RolePreset.client:
        return 'Customer';
      case _RolePreset.vendor:
        return 'Vendor / Subcontractor';
      case _RolePreset.blank:
        return 'Blank — no access';
    }
  }

  String get subtitle {
    switch (this) {
      case _RolePreset.masterAdmin:
        return 'Manages users, billing, and every module';
      case _RolePreset.admin:
        return 'Full operational access. Cannot manage users or billing';
      case _RolePreset.projectManager:
        return 'Manages assigned jobs, schedules, and team coordination';
      case _RolePreset.fieldTech:
        return 'On-site work, time logging, limited office access';
      case _RolePreset.client:
        return 'External portal — read-only view of their job';
      case _RolePreset.vendor:
        return 'External portal — bid requests and own bills';
      case _RolePreset.blank:
        return 'Start from scratch — no permissions set';
    }
  }

  bool get isAdmin =>
      this == _RolePreset.admin || this == _RolePreset.masterAdmin;

  String get interfaceMode {
    switch (this) {
      case _RolePreset.fieldTech:
        return 'field';
      default:
        return 'manager';
    }
  }

  Map<String, String> get permissions {
    switch (this) {
      case _RolePreset.masterAdmin:
        return defaultPermissionsForRole(UserRole.masterAdmin);
      case _RolePreset.admin:
        return defaultPermissionsForRole(UserRole.admin);
      case _RolePreset.projectManager:
        return defaultPermissionsForRole(UserRole.projectManager);
      case _RolePreset.fieldTech:
        return defaultPermissionsForRole(UserRole.fieldTechnician);
      case _RolePreset.client:
        return defaultPermissionsForRole(UserRole.client);
      case _RolePreset.vendor:
        return defaultPermissionsForRole(UserRole.vendor);
      case _RolePreset.blank:
        return {for (final key in orderedModuleKeys) key: 'none'};
    }
  }
}

class _NewRoleResult {
  final String name;
  final _RolePreset preset;

  const _NewRoleResult({required this.name, required this.preset});
}
