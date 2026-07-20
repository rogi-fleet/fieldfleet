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

/// Tooltip copy that disambiguates role tiers. Surfaced on role tiles, role
/// dropdowns, and matrix column headers so the difference between Admin and
/// Master Admin is never a surprise.
String roleTooltipMessage(WorkspaceRoleTemplate template) {
  switch (template.role) {
    case UserRole.masterAdmin:
      return 'Master Admin — owner tier. Reserved for future billing '
          'controls. Functionally identical to Admin today.';
    case UserRole.admin:
      return 'Admin — full access across every module, including user '
          'management and workspace settings.';
    case UserRole.projectManager:
      return 'Project Manager — runs assigned jobs end to end. Writes '
          'financials, customers, and vendors; coordinates the team.';
    case UserRole.fieldTechnician:
      return 'Field Technician — mobile-first. Assigned tasks, time '
          'logging, and media upload.';
    case UserRole.client:
      return 'Customer — external portal. Read-only view of their '
          'own job and shared documents.';
    case UserRole.vendor:
      return 'Vendor — external portal. Bid requests, purchase orders, '
          'and own bills.';
    case null:
      break;
  }
  if (template.isAdmin) {
    return 'Custom role with full admin override enabled. Inherits every '
        'module at Edit level.';
  }
  return template.description?.isNotEmpty == true
      ? template.description!
      : 'Custom role. Click to configure per-module permissions.';
}

/// Read-only permission matrix: rows = modules (grouped), columns = role
/// templates, cells = CRUD badges projected from the `{none,read,write}`
/// level stored on each template.
class PermissionMatrixScreen extends StatefulWidget {
  const PermissionMatrixScreen({
    super.key,
    this.embedded = false,
    this.onOpenEditorForTemplate,
  });

  /// When true, omit the Scaffold/AppBar and render just the body so the
  /// widget can live inside another screen (e.g. a tabbed shell).
  final bool embedded;

  /// Override the "click column header" behavior. Host screens can hook
  /// into this to switch to an editor tab instead of pushing a new route.
  final void Function(WorkspaceRoleTemplate)? onOpenEditorForTemplate;

  @override
  State<PermissionMatrixScreen> createState() => PermissionMatrixScreenState();
}

class PermissionMatrixScreenState extends State<PermissionMatrixScreen> {
  /// Public reload for the host screen so it can re-fetch after an
  /// external save (e.g. Editor tab) without routing through the
  /// embedded refresh button.
  Future<void> reload() => _load();

  final RoleTemplateService _service = ServiceLocator.roleTemplateService;
  bool _isLoading = true;
  String? _error;
  List<WorkspaceRoleTemplate> _templates = const [];
  Map<String, TemplateUsage> _usage = const {};
  String? _diffBaselineId;
  String _moduleQuery = '';
  final _moduleQueryController = TextEditingController();
  String? _hoveredModule;

  @override
  void dispose() {
    _moduleQueryController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final workspaceId =
        context.read<AuthProvider>().appUser?.currentWorkspaceId;
    if (workspaceId == null || workspaceId.isEmpty) {
      setState(() {
        _templates = const [];
        _isLoading = false;
      });
      return;
    }
    setState(() => _isLoading = true);
    try {
      final results = await Future.wait([
        _service.getTemplates(workspaceId: workspaceId),
        _service.getUsageCounts(workspaceId: workspaceId),
      ]);
      if (!mounted) return;
      setState(() {
        _templates = _orderTemplates(results[0] as List<WorkspaceRoleTemplate>);
        _usage = results[1] as Map<String, TemplateUsage>;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = UserFacingError.uiMessage(e, action: 'load permission matrix');
      });
    }
  }

  /// System roles first in schematic order, then custom roles alphabetically.
  List<WorkspaceRoleTemplate> _orderTemplates(
    List<WorkspaceRoleTemplate> templates,
  ) {
    const systemOrder = [
      UserRole.masterAdmin,
      UserRole.admin,
      UserRole.projectManager,
      UserRole.fieldTechnician,
      UserRole.client,
      UserRole.vendor,
    ];
    final systemByRole = <UserRole, WorkspaceRoleTemplate>{};
    final custom = <WorkspaceRoleTemplate>[];
    for (final t in templates) {
      if (t.isSystem && t.role != null) {
        systemByRole[t.role!] = t;
      } else {
        custom.add(t);
      }
    }
    custom.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return [
      for (final role in systemOrder)
        if (systemByRole.containsKey(role)) systemByRole[role]!,
      ...custom,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final body = _isLoading
        ? const Center(child: CircularProgressIndicator())
        : _error != null
        ? Center(child: Text(_error!))
        : _templates.isEmpty
        ? const Center(child: Text('No role templates found.'))
        : _buildBody();

    if (widget.embedded) return body;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: 'Back to Workspace Settings',
          onPressed: () => context.pop(),
        ),
        title: const Text('Permission Matrix'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: _isLoading ? null : _load,
          ),
        ],
      ),
      body: body,
    );
  }

  Widget _buildBody() {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.base),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeaderCopy(),
              const SizedBox(height: 12),
              _buildToolbar(),
              const SizedBox(height: 12),
              _buildLegend(),
              const SizedBox(height: 16),
              _buildMatrix(),
            ],
          ),
        );
      },
    );
  }

  Widget _buildToolbar() {
    return Wrap(
      spacing: 12,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SizedBox(
          width: 220,
          child: TextField(
            controller: _moduleQueryController,
            decoration: InputDecoration(
              hintText: 'Filter modules',
              prefixIcon: const Icon(Icons.search, size: 18),
              suffixIcon: _moduleQuery.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.clear, size: 16),
                      onPressed: () {
                        _moduleQueryController.clear();
                        setState(() => _moduleQuery = '');
                      },
                    ),
              isDense: true,
              border: const OutlineInputBorder(),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 10,
              ),
            ),
            style: const TextStyle(fontSize: 12),
            onChanged: (value) =>
                setState(() => _moduleQuery = value.trim().toLowerCase()),
          ),
        ),
        const Text(
          'Compare to baseline:',
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        ),
        DropdownButton<String?>(
          value: _diffBaselineId,
          isDense: true,
          hint: const Text('Off', style: TextStyle(fontSize: 12)),
          items: [
            const DropdownMenuItem<String?>(
              value: null,
              child: Text('Off', style: TextStyle(fontSize: 12)),
            ),
            for (final t in _templates)
              DropdownMenuItem<String?>(
                value: t.id,
                child: Text(t.name, style: const TextStyle(fontSize: 12)),
              ),
          ],
          onChanged: (value) => setState(() => _diffBaselineId = value),
        ),
        if (_diffBaselineId != null)
          TextButton.icon(
            icon: const Icon(Icons.close, size: 14),
            label: const Text('Clear'),
            onPressed: () => setState(() => _diffBaselineId = null),
          ),
      ],
    );
  }

  bool _moduleMatches(String module) {
    if (_moduleQuery.isEmpty) return true;
    final label = (modulePermissionLabels[module] ?? module).toLowerCase();
    final desc = (modulePermissionDescriptions[module] ?? '').toLowerCase();
    return label.contains(_moduleQuery) || desc.contains(_moduleQuery);
  }

  Widget _buildHeaderCopy() {
    return const Text(
      'Click a cell to change its permission. Click a column header to open '
      'the role editor, or right-click a custom role to rename it. Use the '
      'baseline dropdown to highlight where roles diverge.',
      style: TextStyle(fontSize: 13),
    );
  }

  Widget _buildLegend() {
    return Wrap(
      spacing: 12,
      runSpacing: 8,
      children: [
        _LegendItem(
          label: 'Full CRUD',
          child: const _CrudRow(flags: {'C', 'R', 'E', 'D'}),
        ),
        _LegendItem(label: 'View only', child: const _CrudRow(flags: {'R'})),
        _LegendItem(label: 'No access', child: const _CrudRow(flags: {})),
        _LegendItem(
          label: 'Portal role',
          child: Container(
            width: 14,
            height: 14,
            decoration: BoxDecoration(
              color: AppColors.successLight,
              borderRadius: BorderRadius.circular(3),
              border: Border.all(color: AppColors.success),
            ),
          ),
        ),
        if (_diffBaselineId != null) ...[
          _LegendItem(
            label: 'Differs from baseline',
            child: Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                color: AppColors.warningLight,
                borderRadius: BorderRadius.circular(3),
                border: Border.all(color: AppColors.warning),
              ),
            ),
          ),
          _LegendItem(
            label: 'Matches baseline (dimmed)',
            child: Opacity(
              opacity: 0.35,
              child: const _CrudRow(flags: {'R'}),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildMatrix() {
    final colorScheme = Theme.of(context).colorScheme;
    final borderColor = colorScheme.outlineVariant;

    Color headerBg(WorkspaceRoleTemplate t) {
      if (t.role == UserRole.client) return AppColors.successLight;
      if (t.role == UserRole.vendor) return AppColors.messageAccentLight;
      if (t.isAdmin) return AppColors.warningLight;
      return colorScheme.surfaceContainerHighest;
    }

    Color headerFg(WorkspaceRoleTemplate t) {
      if (t.role == UserRole.client) return AppColors.successDark;
      if (t.role == UserRole.vendor) return AppColors.messageAccentDark;
      if (t.isAdmin) return AppColors.warningDark;
      return colorScheme.onSurface;
    }

    final groupedModules = <ModuleGroup, List<String>>{};
    for (final module in orderedModuleKeys) {
      if (!_moduleMatches(module)) continue;
      final group = moduleGroups[module] ?? ModuleGroup.system;
      groupedModules.putIfAbsent(group, () => []).add(module);
    }

    const moduleColWidth = 220.0;
    const roleColWidth = 140.0;
    const headerHeight = 52.0;
    const groupHeaderHeight = 28.0;
    const rowHeight = 48.0;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Sticky left pane: module labels ──
            SizedBox(
              width: moduleColWidth,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _LeftHeaderCell(height: headerHeight, borderColor: borderColor),
                  if (groupedModules.isEmpty)
                    SizedBox(
                      height: rowHeight,
                      child: Padding(
                        padding: const EdgeInsets.all(AppSpacing.md),
                        child: Text(
                          'No modules match',
                          style: TextStyle(
                            fontSize: 12,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ),
                  for (final entry in groupedModules.entries) ...[
                    _GroupHeader(
                      label: moduleGroupLabels[entry.key] ?? '',
                      width: moduleColWidth,
                      height: groupHeaderHeight,
                    ),
                    for (final module in entry.value)
                      MouseRegion(
                        onEnter: (_) => setState(() => _hoveredModule = module),
                        onExit: (_) {
                          if (_hoveredModule == module) {
                            setState(() => _hoveredModule = null);
                          }
                        },
                        child: _LeftModuleLabel(
                          module: module,
                          height: rowHeight,
                          borderColor: borderColor,
                          hovered: _hoveredModule == module,
                        ),
                      ),
                  ],
                ],
              ),
            ),
            VerticalDivider(width: 1, color: borderColor),
            // ── Scrolling right pane: role columns ──
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header
                    Container(
                      height: headerHeight,
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerHigh,
                        border: Border(
                          bottom: BorderSide(color: borderColor),
                        ),
                      ),
                      child: Row(
                        children: [
                          for (final t in _templates)
                            _RoleHeaderCell(
                              template: t,
                              width: roleColWidth,
                              headerBg: headerBg(t),
                              headerFg: headerFg(t),
                              subtitle: _subtitle(t),
                              onRename: t.isSystem
                                  ? null
                                  : () => _renameTemplate(t),
                              onOpenEditor: () {
                                if (widget.onOpenEditorForTemplate != null) {
                                  widget.onOpenEditorForTemplate!(t);
                                } else {
                                  context.push('/settings/role-templates');
                                }
                              },
                            ),
                        ],
                      ),
                    ),
                    if (groupedModules.isEmpty)
                      SizedBox(
                        height: rowHeight,
                        width: roleColWidth * _templates.length,
                      ),
                    for (final entry in groupedModules.entries) ...[
                      _GroupHeader(
                        label: '',
                        width: roleColWidth * _templates.length,
                        height: groupHeaderHeight,
                      ),
                      for (final module in entry.value)
                        MouseRegion(
                          onEnter: (_) =>
                              setState(() => _hoveredModule = module),
                          onExit: (_) {
                            if (_hoveredModule == module) {
                              setState(() => _hoveredModule = null);
                            }
                          },
                          child: Container(
                            height: rowHeight,
                            decoration: BoxDecoration(
                              color: _hoveredModule == module
                                  ? colorScheme.surfaceContainerLow
                                  : null,
                              border: Border(
                                bottom: BorderSide(
                                  color: borderColor,
                                  width: 0.5,
                                ),
                              ),
                            ),
                            child: Row(
                              children: [
                                for (final t in _templates)
                                  SizedBox(
                                    width: roleColWidth,
                                    child: _buildEditableCell(t, module),
                                  ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _subtitle(WorkspaceRoleTemplate t) {
    final usage = _usage[t.id] ?? TemplateUsage.empty;
    final countParts = <String>[];
    if (usage.memberCount > 0) {
      countParts.add('${usage.memberCount}');
    }
    if (usage.pendingInvitationCount > 0) {
      countParts.add('+${usage.pendingInvitationCount} pending');
    }
    final counts = countParts.isEmpty ? '' : ' · ${countParts.join(' ')}';
    if (t.isAdmin) return 'Full admin$counts';
    if (t.role == UserRole.client) return 'External · portal$counts';
    if (t.role == UserRole.vendor) return 'External · portal$counts';
    return '${t.isSystem ? 'System' : 'Custom'}$counts';
  }

  Widget _buildEditableCell(WorkspaceRoleTemplate t, String module) {
    final locked = t.isAdmin;
    if (locked) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        child: _cellFor(t, module),
      );
    }
    Offset tapPosition = Offset.zero;
    return GestureDetector(
      onTapDown: (details) => tapPosition = details.globalPosition,
      child: InkWell(
        onTap: () => _editCell(t, module, tapPosition),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          child: _cellFor(t, module),
        ),
      ),
    );
  }

  Future<void> _editCell(
    WorkspaceRoleTemplate template,
    String module,
    Offset tapPosition,
  ) async {
    final current = template.modulePermissions[module] ?? 'none';
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final chosen = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromPoints(tapPosition, tapPosition),
        Offset.zero & overlay.size,
      ),
      items: [
        PopupMenuItem(
          enabled: false,
          child: Text(
            '${template.name} · ${modulePermissionLabels[module] ?? module}',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        const PopupMenuDivider(),
        for (final level in modulePermissionLevels)
          PopupMenuItem<String>(
            value: level,
            child: Row(
              children: [
                Icon(
                  _levelIcon(level),
                  size: 16,
                  color: level == current
                      ? Theme.of(context).colorScheme.primary
                      : null,
                ),
                const SizedBox(width: 8),
                Text(modulePermissionLevelLabels[level] ?? level),
                const Spacer(),
                if (level == current)
                  Icon(
                    Icons.check,
                    size: 14,
                    color: Theme.of(context).colorScheme.primary,
                  ),
              ],
            ),
          ),
      ],
    );
    if (chosen == null || chosen == current) return;

    final updated = {...template.modulePermissions, module: chosen};
    try {
      await _service.updateTemplate(
        templateId: template.id,
        modulePermissions: updated,
      );
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${template.name} · ${modulePermissionLabels[module]} → '
              '${modulePermissionLevelLabels[chosen]}',
            ),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(UserFacingError.uiMessage(e, action: 'update cell')),
          backgroundColor: AppColors.error,
        ),
      );
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

  Future<void> _renameTemplate(WorkspaceRoleTemplate template) async {
    final controller = TextEditingController(text: template.name);
    String? error;
    try {
      final newName = await showDialog<String>(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              title: const Text('Rename role'),
              content: TextField(
                controller: controller,
                autofocus: true,
                decoration: InputDecoration(
                  border: const OutlineInputBorder(),
                  isDense: true,
                  errorText: error,
                ),
                onChanged: (_) {
                  if (error != null) setDialogState(() => error = null);
                },
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () {
                    final trimmed = controller.text.trim();
                    if (trimmed.isEmpty) {
                      setDialogState(() => error = 'Name is required');
                      return;
                    }
                    final clash = _templates.any(
                      (t) =>
                          t.id != template.id &&
                          t.name.toLowerCase() == trimmed.toLowerCase(),
                    );
                    if (clash) {
                      setDialogState(
                        () => error = 'Another role already has this name',
                      );
                      return;
                    }
                    Navigator.pop(ctx, trimmed);
                  },
                  child: const Text('Rename'),
                ),
              ],
            );
          },
        ),
      );
      if (newName == null || newName == template.name) return;
      await _service.updateTemplate(
        templateId: template.id,
        name: newName,
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(UserFacingError.uiMessage(e, action: 'rename role')),
          backgroundColor: AppColors.error,
        ),
      );
    } finally {
      controller.dispose();
    }
  }

  String _effectiveLevel(WorkspaceRoleTemplate t, String module) {
    if (t.isAdmin) return 'write';
    return t.modulePermissions[module] ?? 'none';
  }

  Widget _cellFor(WorkspaceRoleTemplate t, String module) {
    final level = _effectiveLevel(t, module);
    final flags = modulePermissionLevelCrud[level] ?? const <String>{};
    final portalTint = t.role == UserRole.client
        ? AppColors.success
        : t.role == UserRole.vendor
        ? AppColors.messageAccent
        : null;

    _CellDiff diff = _CellDiff.none;
    if (_diffBaselineId != null && _diffBaselineId != t.id) {
      final baseline = _templates.firstWhere(
        (x) => x.id == _diffBaselineId,
        orElse: () => t,
      );
      final baseLevel = _effectiveLevel(baseline, module);
      diff = baseLevel == level ? _CellDiff.same : _CellDiff.different;
    }

    return _CrudRow(flags: flags, portalTint: portalTint, diff: diff);
  }
}

enum _CellDiff { none, same, different }

class _LegendItem extends StatelessWidget {
  const _LegendItem({required this.label, required this.child});
  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        child,
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(fontSize: 11)),
      ],
    );
  }
}

class _CrudRow extends StatelessWidget {
  const _CrudRow({
    required this.flags,
    this.portalTint,
    this.diff = _CellDiff.none,
  });
  final Set<String> flags;
  final Color? portalTint;
  final _CellDiff diff;

  @override
  Widget build(BuildContext context) {
    Widget row = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final flag in crudOrder) ...[
          _CrudBadge(letter: flag, active: flags.contains(flag), tint: portalTint),
          if (flag != crudOrder.last) const SizedBox(width: 3),
        ],
      ],
    );
    if (diff == _CellDiff.same) {
      row = Opacity(opacity: 0.35, child: row);
    } else if (diff == _CellDiff.different) {
      row = Container(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs, vertical: 3),
        decoration: BoxDecoration(
          color: AppColors.warningLight,
          borderRadius: BorderRadius.circular(AppRadius.xs),
          border: Border.all(color: AppColors.warning),
        ),
        child: row,
      );
    }
    return row;
  }
}

class _CrudBadge extends StatelessWidget {
  const _CrudBadge({
    required this.letter,
    required this.active,
    this.tint,
  });
  final String letter;
  final bool active;
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final Color bg;
    final Color fg;
    if (!active) {
      bg = colorScheme.surfaceContainerHighest;
      fg = colorScheme.outline;
    } else if (tint != null) {
      bg = tint!.withValues(alpha: 0.15);
      fg = tint!;
    } else {
      bg = AppColors.successLight;
      fg = AppColors.successDark;
    }
    return Container(
      width: 20,
      height: 20,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppRadius.xs),
      ),
      alignment: Alignment.center,
      child: Text(
        letter,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: fg,
        ),
      ),
    );
  }
}

class _GroupHeader extends StatelessWidget {
  const _GroupHeader({
    required this.label,
    required this.width,
    this.height = 28,
  });
  final String label;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: width,
      height: height,
      color: colorScheme.surfaceContainerLow,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      alignment: Alignment.centerLeft,
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
          color: colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _LeftHeaderCell extends StatelessWidget {
  const _LeftHeaderCell({required this.height, required this.borderColor});
  final double height;
  final Color borderColor;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHigh,
        border: Border(bottom: BorderSide(color: borderColor)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      alignment: Alignment.centerLeft,
      child: const Text(
        'Module',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

class _LeftModuleLabel extends StatelessWidget {
  const _LeftModuleLabel({
    required this.module,
    required this.height,
    required this.borderColor,
    required this.hovered,
  });
  final String module;
  final double height;
  final Color borderColor;
  final bool hovered;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final label = modulePermissionLabels[module] ?? module;
    final desc = modulePermissionDescriptions[module] ?? '';
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: hovered ? colorScheme.surfaceContainerLow : null,
        border: Border(
          bottom: BorderSide(color: borderColor, width: 0.5),
        ),
      ),
      child: Tooltip(
        message: desc,
        waitDuration: const Duration(milliseconds: 400),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 6),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (desc.isNotEmpty)
                Text(
                  desc,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RoleHeaderCell extends StatelessWidget {
  const _RoleHeaderCell({
    required this.template,
    required this.width,
    required this.headerBg,
    required this.headerFg,
    required this.subtitle,
    required this.onOpenEditor,
    this.onRename,
  });
  final WorkspaceRoleTemplate template;
  final double width;
  final Color headerBg;
  final Color headerFg;
  final String subtitle;
  final VoidCallback onOpenEditor;
  final VoidCallback? onRename;

  @override
  Widget build(BuildContext context) {
    Offset tapPosition = Offset.zero;
    return SizedBox(
      width: width,
      child: Tooltip(
        message: roleTooltipMessage(template),
        waitDuration: const Duration(milliseconds: 400),
        child: GestureDetector(
          onTapDown: (d) => tapPosition = d.globalPosition,
          onSecondaryTapDown: (d) => tapPosition = d.globalPosition,
          onSecondaryTap: onRename == null
              ? null
              : () => _showContextMenu(context, tapPosition),
          child: InkWell(
            onTap: onOpenEditor,
            child: Container(
              color: headerBg,
              padding: const EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 10,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          template.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: headerFg,
                          ),
                        ),
                      ),
                      if (!template.isSystem) ...[
                        const SizedBox(width: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 5,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.messageAccent
                                .withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: Text(
                            'CUSTOM',
                            style: TextStyle(
                              fontSize: 8,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.4,
                              color: AppColors.messageAccent,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10,
                      color: headerFg.withValues(alpha: 0.75),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showContextMenu(BuildContext context, Offset pos) async {
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox;
    final chosen = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromPoints(pos, pos),
        Offset.zero & overlay.size,
      ),
      items: [
        PopupMenuItem(
          value: 'open',
          child: Row(
            children: const [
              Icon(Icons.edit_note, size: 16),
              SizedBox(width: 8),
              Text('Open in Editor tab'),
            ],
          ),
        ),
        if (onRename != null)
          PopupMenuItem(
            value: 'rename',
            child: Row(
              children: const [
                Icon(Icons.drive_file_rename_outline, size: 16),
                SizedBox(width: 8),
                Text('Rename role'),
              ],
            ),
          ),
      ],
    );
    if (chosen == 'open') onOpenEditor();
    if (chosen == 'rename') onRename!();
  }
}
