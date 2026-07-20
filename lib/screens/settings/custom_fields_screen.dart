import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../models/custom_field_definition.dart';
import '../../models/custom_field_type.dart';
import '../../providers/auth_provider.dart';
import '../../providers/custom_field_definitions_provider.dart';
import '../../providers/workspace_provider.dart';
import '../../theme/theme.dart';
import '../../utils/project_terminology.dart';
import '../../widgets/common/list_skeleton.dart';
import '../../widgets/forms/form_field_preview.dart';

/// Workspace settings screen for managing custom fields.
///
/// v1: Projects entity only. The Customers / Cost Items / Vendors tabs are
/// rendered disabled with a "Coming soon" hint so the eventual scope reads
/// honestly. See docs/plans/custom-fields.md.
class CustomFieldsScreen extends StatefulWidget {
  const CustomFieldsScreen({super.key});

  @override
  State<CustomFieldsScreen> createState() => _CustomFieldsScreenState();
}

class _CustomFieldsScreenState extends State<CustomFieldsScreen> {
  late final CustomFieldDefinitionsProvider _provider;
  bool _showArchived = false;
  CustomFieldType? _typeFilter;

  String get _workspaceId =>
      context.read<AuthProvider>().appUser?.currentWorkspaceId ?? '';

  @override
  void initState() {
    super.initState();
    _provider = CustomFieldDefinitionsProvider();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_workspaceId.isNotEmpty) _provider.load(_workspaceId);
    });
  }

  @override
  void dispose() {
    _provider.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final plural = context.watch<WorkspaceProvider>().projectTerminology;
    return ChangeNotifierProvider.value(
      value: _provider,
      child: DefaultTabController(
        length: 4,
        child: Scaffold(
          backgroundColor: AppColors.background,
          appBar: AppBar(
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              tooltip: 'Back to workspace settings',
              onPressed: () => context.pop(),
            ),
            title: const Text('Custom Fields'),
            bottom: TabBar(
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              tabs: [
                Tab(text: plural),
                const Tab(
                  text: 'Customers',
                  icon: Icon(Icons.lock_outline, size: 14),
                ),
                const Tab(
                  text: 'Cost Items',
                  icon: Icon(Icons.lock_outline, size: 14),
                ),
                const Tab(
                  text: 'Vendors',
                  icon: Icon(Icons.lock_outline, size: 14),
                ),
              ],
            ),
          ),
          body: TabBarView(
            children: [
              _buildProjectsTab(),
              _buildComingSoon('Customers'),
              _buildComingSoon('Cost Items'),
              _buildComingSoon('Vendors'),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildComingSoon(String entity) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.schedule, size: 48, color: AppColors.textTertiary),
            const SizedBox(height: 12),
            Text(
              'Custom fields on $entity — coming soon',
              style: const TextStyle(color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProjectsTab() {
    final plural = context.watch<WorkspaceProvider>().projectTerminology;
    final singular = singularProjectTerminology(plural);
    return Consumer<CustomFieldDefinitionsProvider>(
      builder: (context, provider, _) {
        if (provider.isLoading && provider.all.isEmpty) {
          return const ListSkeleton();
        }
        if (provider.error != null && provider.all.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: Text('Failed to load: ${provider.error}'),
            ),
          );
        }

        final active = provider.active;
        final archived = provider.archived;
        final isEmpty = active.isEmpty && archived.isEmpty;

        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 960),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              children: [
                _HeroHeader(
                  activeCount: active.length,
                  archivedCount: archived.length,
                  onAdd: _openAddDialog,
                  singularTerminology: singular,
                  pluralTerminology: plural,
                ),
                const SizedBox(height: 16),
                if (active.length >= 45) ...[
                  _NearLimitBanner(activeCount: active.length),
                  const SizedBox(height: 12),
                ],
                if (!isEmpty) ...[
                  _Toolbar(
                    typeFilter: _typeFilter,
                    onTypeFilterChanged: (t) =>
                        setState(() => _typeFilter = t),
                    showArchived: _showArchived,
                    onShowArchivedChanged: (v) =>
                        setState(() => _showArchived = v),
                    archivedCount: archived.length,
                  ),
                  const SizedBox(height: 12),
                ],
                if (isEmpty)
                  _buildEmptyState(plural)
                else ...[
                  _buildActiveSection(provider, active),
                  if (_showArchived && archived.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    _buildArchivedSection(provider, archived),
                  ],
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildActiveSection(
    CustomFieldDefinitionsProvider provider,
    List<CustomFieldDefinition> active,
  ) {
    final filtered = _typeFilter == null
        ? active
        : active.where((d) => d.type == _typeFilter).toList();

    if (filtered.isEmpty) {
      return _SectionFrame(
        title: 'Active fields',
        count: 0,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xxl),
          child: Center(
            child: Text(
              'No fields match the selected type.',
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ),
        ),
      );
    }

    // Reorder only makes sense on the unfiltered list, because indices
    // align with the provider's canonical order. When a filter is active,
    // we show the cards but hide the drag handle.
    final canReorder = _typeFilter == null;

    return _SectionFrame(
      title: 'Active fields',
      count: active.length,
      child: ReorderableListView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        buildDefaultDragHandles: false,
        itemCount: filtered.length,
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
        onReorder: (oldIndex, newIndex) async {
          if (!canReorder) return;
          if (newIndex > oldIndex) newIndex -= 1;
          final ids = active.map((d) => d.id).toList();
          final moved = ids.removeAt(oldIndex);
          ids.insert(newIndex, moved);
          await provider.reorder(ids);
        },
        itemBuilder: (context, index) {
          final def = filtered[index];
          return _DefinitionRow(
            key: ValueKey(def.id),
            definition: def,
            index: canReorder ? index : -1,
            onEdit: () => _openEditDialog(def),
            onArchive: () => provider.archive(def.id),
          );
        },
      ),
    );
  }

  Widget _buildArchivedSection(
    CustomFieldDefinitionsProvider provider,
    List<CustomFieldDefinition> archived,
  ) {
    return _SectionFrame(
      title: 'Archived',
      count: archived.length,
      dimmed: true,
      child: Column(
        children: archived
            .map(
              (def) => _DefinitionRow(
                key: ValueKey(def.id),
                definition: def,
                index: -1,
                onEdit: () => _openEditDialog(def),
                onRestore: () => provider.restore(def.id),
              ),
            )
            .toList(),
      ),
    );
  }

  Widget _buildEmptyState(String pluralTerminology) {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(AppSpacing.xxxl),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.r12),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: AppColors.primarySurface,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.dynamic_form,
              size: 36,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'No custom fields yet',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: 420,
            child: Text(
              'Capture data your ${pluralTerminology.toLowerCase()} need beyond the built-ins — '
              'Permit Number, HOA Contact, Lot Size, and anything else.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textSecondary,
                height: 1.4,
              ),
            ),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _openAddDialog,
            icon: const Icon(Icons.add),
            label: const Text('Add your first field'),
          ),
        ],
      ),
    );
  }

  Future<void> _openAddDialog() async {
    await showDialog<void>(
      context: context,
      builder: (_) => _CustomFieldDialog(
        provider: _provider,
        createdBy: context.read<AuthProvider>().appUser?.id,
      ),
    );
  }

  Future<void> _openEditDialog(CustomFieldDefinition def) async {
    await showDialog<void>(
      context: context,
      builder: (_) => _CustomFieldDialog(
        provider: _provider,
        existing: def,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Hero header — title, description, stats, primary CTA
// ---------------------------------------------------------------------------

class _HeroHeader extends StatelessWidget {
  final int activeCount;
  final int archivedCount;
  final VoidCallback onAdd;
  final String singularTerminology;
  final String pluralTerminology;

  const _HeroHeader({
    required this.activeCount,
    required this.archivedCount,
    required this.onAdd,
    required this.singularTerminology,
    required this.pluralTerminology,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.primarySurface,
            AppColors.primarySurface.withValues(alpha: 0.4),
          ],
        ),
        borderRadius: BorderRadius.circular(AppRadius.r12),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.15)),
      ),
      child: LayoutBuilder(
        builder: (context, c) {
          final compact = c.maxWidth < 560;
          final left = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                    ),
                    child: const Icon(
                      Icons.dynamic_form,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    '$singularTerminology Custom Fields',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                'Extend the ${singularTerminology.toLowerCase()} schema with ad-hoc fields — permits, '
                'HOA info, lot size, anything your workflow needs.',
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _StatPill(
                    icon: Icons.check_circle_outline,
                    label: '$activeCount active',
                    color: AppColors.success,
                  ),
                  if (archivedCount > 0)
                    _StatPill(
                      icon: Icons.inventory_2_outlined,
                      label: '$archivedCount archived',
                      color: AppColors.textTertiary,
                    ),
                  _StatPill(
                    icon: Icons.speed_outlined,
                    label: 'Limit: 50',
                    color: AppColors.info,
                  ),
                ],
              ),
            ],
          );
          final cta = FilledButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.add),
            label: const Text('Add field'),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(
                horizontal: 18,
                vertical: 14,
              ),
            ),
          );
          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [left, const SizedBox(height: 16), cta],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(child: left),
              const SizedBox(width: 16),
              cta,
            ],
          );
        },
      ),
    );
  }
}

class _StatPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _StatPill({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.xl),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Toolbar — type filter + show archived
// ---------------------------------------------------------------------------

class _Toolbar extends StatelessWidget {
  final CustomFieldType? typeFilter;
  final ValueChanged<CustomFieldType?> onTypeFilterChanged;
  final bool showArchived;
  final ValueChanged<bool> onShowArchivedChanged;
  final int archivedCount;

  const _Toolbar({
    required this.typeFilter,
    required this.onTypeFilterChanged,
    required this.showArchived,
    required this.onShowArchivedChanged,
    required this.archivedCount,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.filter_list,
            size: 18,
            color: AppColors.textSecondary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _filterChip(
                    'All types',
                    typeFilter == null,
                    () => onTypeFilterChanged(null),
                  ),
                  for (final t in CustomFieldType.values) ...[
                    const SizedBox(width: 6),
                    _filterChip(
                      t.displayName,
                      typeFilter == t,
                      () => onTypeFilterChanged(t),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(width: 12),
          const VerticalDivider(width: 1, indent: 6, endIndent: 6),
          const SizedBox(width: 8),
          FilterChip(
            label: Text(
              archivedCount > 0
                  ? 'Archived ($archivedCount)'
                  : 'Archived',
            ),
            avatar: Icon(
              showArchived ? Icons.visibility : Icons.visibility_off_outlined,
              size: 16,
              color: showArchived
                  ? AppColors.primary
                  : AppColors.textSecondary,
            ),
            selected: showArchived,
            onSelected: onShowArchivedChanged,
            visualDensity: VisualDensity.compact,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            labelStyle: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color:
                  showArchived ? AppColors.primary : AppColors.textSecondary,
            ),
            selectedColor: AppColors.primarySurface,
            backgroundColor: AppColors.surface,
            side: BorderSide(
              color: showArchived ? AppColors.primary : AppColors.cardBorder,
            ),
          ),
        ],
      ),
    );
  }

  Widget _filterChip(String label, bool selected, VoidCallback onTap) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      labelStyle: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        color: selected ? AppColors.primary : AppColors.textSecondary,
      ),
      selectedColor: AppColors.primarySurface,
      backgroundColor: AppColors.surface,
      side: BorderSide(
        color: selected ? AppColors.primary : AppColors.cardBorder,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Near-limit banner
// ---------------------------------------------------------------------------

class _NearLimitBanner extends StatelessWidget {
  final int activeCount;
  const _NearLimitBanner({required this.activeCount});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.warningLight,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber, size: 18, color: AppColors.warning),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '$activeCount of 50 fields used. The workspace cap is enforced '
              'server-side — archive fields you no longer need.',
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Section frame — titled card container
// ---------------------------------------------------------------------------

class _SectionFrame extends StatelessWidget {
  final String title;
  final int count;
  final bool dimmed;
  final Widget child;

  const _SectionFrame({
    required this.title,
    required this.count,
    required this.child,
    this.dimmed = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.r12),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: dimmed
                        ? AppColors.textTertiary
                        : AppColors.textPrimary,
                    letterSpacing: 0.3,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceAlt,
                    borderRadius: BorderRadius.circular(AppRadius.md),
                  ),
                  child: Text(
                    '$count',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: AppColors.cardBorder),
          child,
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Definition row
// ---------------------------------------------------------------------------

class _DefinitionRow extends StatelessWidget {
  final CustomFieldDefinition definition;
  final int index; // -1 = no drag handle (archived or filter active)
  final VoidCallback onEdit;
  final VoidCallback? onArchive;
  final VoidCallback? onRestore;

  const _DefinitionRow({
    super.key,
    required this.definition,
    required this.index,
    required this.onEdit,
    this.onArchive,
    this.onRestore,
  });

  @override
  Widget build(BuildContext context) {
    final isArchived = definition.isArchived;
    final draggable = index >= 0;
    final accent = _typeAccent(definition.type);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onEdit,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 6),
          child: Row(
            children: [
              SizedBox(
                width: 28,
                child: draggable
                    ? ReorderableDragStartListener(
                        index: index,
                        child: const Icon(
                          Icons.drag_indicator,
                          size: 18,
                          color: AppColors.textTertiary,
                        ),
                      )
                    : null,
              ),
              _TypeIcon(type: definition.type, color: accent),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            definition.label,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: isArchived
                                  ? AppColors.textTertiary
                                  : AppColors.textPrimary,
                            ),
                          ),
                        ),
                        if (definition.isRequired) ...[
                          const SizedBox(width: 4),
                          Text(
                            '*',
                            style: TextStyle(
                              color: AppColors.error,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Text(
                          definition.type.displayName,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                        ),
                        if (definition.fieldGroup != null) ...[
                          _dot(),
                          Flexible(
                            child: Text(
                              definition.fieldGroup!,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (!isArchived) ...[
                if (definition.isRequired)
                  _badge('Required', AppColors.error),
                if (definition.groupable) ...[
                  const SizedBox(width: 6),
                  _badge('Groupable', AppColors.info),
                ],
              ] else
                _badge('Archived', AppColors.textTertiary),
              const SizedBox(width: 8),
              if (isArchived && onRestore != null)
                IconButton(
                  icon: const Icon(Icons.restore_from_trash, size: 18),
                  tooltip: 'Restore',
                  onPressed: onRestore,
                )
              else if (onArchive != null)
                IconButton(
                  icon: const Icon(Icons.archive_outlined, size: 18),
                  tooltip: 'Archive',
                  onPressed: onArchive,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _dot() => const Padding(
        padding: EdgeInsets.symmetric(horizontal: 6),
        child: Text(
          '·',
          style: TextStyle(color: AppColors.textTertiary),
        ),
      );

  Widget _badge(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: color,
          letterSpacing: 0.3,
        ),
      ),
    );
  }

  static Color _typeAccent(CustomFieldType type) {
    switch (type) {
      case CustomFieldType.text:
      case CustomFieldType.longText:
        return AppColors.primary;
      case CustomFieldType.number:
        return AppColors.financialAccent;
      case CustomFieldType.date:
        return AppColors.secondary;
      case CustomFieldType.picklist:
      case CustomFieldType.multiSelect:
        return AppColors.messageAccent;
      case CustomFieldType.checkbox:
        return AppColors.success;
      case CustomFieldType.file:
      case CustomFieldType.photo:
        return AppColors.info;
    }
  }
}

class _TypeIcon extends StatelessWidget {
  final CustomFieldType type;
  final Color color;

  const _TypeIcon({required this.type, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Icon(_iconFor(type), size: 18, color: color),
    );
  }

  IconData _iconFor(CustomFieldType type) {
    switch (type) {
      case CustomFieldType.text:
        return Icons.short_text;
      case CustomFieldType.longText:
        return Icons.notes;
      case CustomFieldType.number:
        return Icons.tag;
      case CustomFieldType.date:
        return Icons.calendar_today;
      case CustomFieldType.picklist:
        return Icons.arrow_drop_down_circle_outlined;
      case CustomFieldType.multiSelect:
        return Icons.checklist;
      case CustomFieldType.checkbox:
        return Icons.check_box_outlined;
      case CustomFieldType.file:
        return Icons.attach_file;
      case CustomFieldType.photo:
        return Icons.photo_camera_outlined;
    }
  }
}

// ---------------------------------------------------------------------------
// Add / Edit dialog
// ---------------------------------------------------------------------------

class _CustomFieldDialog extends StatefulWidget {
  final CustomFieldDefinitionsProvider provider;
  final CustomFieldDefinition? existing;
  final String? createdBy;

  const _CustomFieldDialog({
    required this.provider,
    this.existing,
    this.createdBy,
  });

  @override
  State<_CustomFieldDialog> createState() => _CustomFieldDialogState();
}

class _CustomFieldDialogState extends State<_CustomFieldDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _labelCtrl;
  late final TextEditingController _groupCtrl;
  late final TextEditingController _optionsCtrl;
  late CustomFieldType _type;
  late bool _isRequired;
  late bool _showInForm;
  late bool _groupable;

  bool get _isEdit => widget.existing != null;

  List<String> _groupSuggestions = const [];

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _labelCtrl = TextEditingController(text: e?.label ?? '');
    _groupCtrl = TextEditingController(text: e?.fieldGroup ?? '');
    _optionsCtrl = TextEditingController(
      text: (e?.optionItems ?? const []).join('\n'),
    );
    _type = e?.type ?? CustomFieldType.text;
    _isRequired = e?.isRequired ?? false;
    _showInForm = e?.showInForm ?? true;
    _groupable = e?.groupable ?? false;

    widget.provider.listGroups().then((groups) {
      if (mounted) setState(() => _groupSuggestions = groups);
    });
  }

  @override
  void dispose() {
    _labelCtrl.dispose();
    _groupCtrl.dispose();
    _optionsCtrl.dispose();
    super.dispose();
  }

  List<String> _parseOptions() => _optionsCtrl.text
      .split('\n')
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();

  @override
  Widget build(BuildContext context) {
    final plural = context.watch<WorkspaceProvider>().projectTerminology;
    final singular = singularProjectTerminology(plural).toLowerCase();
    return Dialog(
      insetPadding: const EdgeInsets.all(AppSpacing.xl),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _isEdit ? 'Edit Custom Field' : 'Add Custom Field',
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                if (_isEdit)
                  Text(
                    'Type cannot be changed. To change a field\'s type, '
                    'archive it and create a new one.',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                const SizedBox(height: 16),
                LayoutBuilder(builder: (context, c) {
                  final wide = c.maxWidth >= 540;
                  final form = _buildFormColumn(singular);
                  final preview = _buildPreviewColumn();
                  if (wide) {
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(flex: 3, child: form),
                        const SizedBox(width: 20),
                        Expanded(flex: 2, child: preview),
                      ],
                    );
                  }
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [form, const SizedBox(height: 16), preview],
                  );
                }),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Cancel'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: _save,
                      child: Text(_isEdit ? 'Save' : 'Add Field'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFormColumn(String singular) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextFormField(
          controller: _labelCtrl,
          decoration: const InputDecoration(
            labelText: 'Label',
            border: OutlineInputBorder(),
            isDense: true,
          ),
          validator: (v) =>
              (v == null || v.trim().isEmpty) ? 'Required' : null,
          autofocus: !_isEdit,
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 12),
        Autocomplete<String>(
          initialValue: TextEditingValue(text: _groupCtrl.text),
          optionsBuilder: (val) {
            final q = val.text.toLowerCase();
            if (q.isEmpty) return _groupSuggestions;
            return _groupSuggestions
                .where((g) => g.toLowerCase().contains(q));
          },
          fieldViewBuilder:
              (context, controller, focusNode, onFieldSubmitted) {
            // Keep our internal controller in sync — Autocomplete makes its
            // own controller, so we mirror it back into _groupCtrl on each
            // build.
            controller.text = _groupCtrl.text;
            controller.selection = TextSelection.collapsed(
              offset: controller.text.length,
            );
            return TextField(
              controller: controller,
              focusNode: focusNode,
              decoration: const InputDecoration(
                labelText: 'Group (optional)',
                hintText: 'e.g. Permits, HOA',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (v) => _groupCtrl.text = v,
              onSubmitted: (_) => onFieldSubmitted(),
            );
          },
          onSelected: (v) => setState(() => _groupCtrl.text = v),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<CustomFieldType>(
          initialValue: _type,
          decoration: const InputDecoration(
            labelText: 'Type',
            border: OutlineInputBorder(),
            isDense: true,
          ),
          // Type is immutable on edit — disable the picker.
          onChanged: _isEdit ? null : (v) => setState(() => _type = v!),
          items: CustomFieldType.values
              .map((t) => DropdownMenuItem(
                    value: t,
                    child: Text(t.displayName),
                  ))
              .toList(),
        ),
        if (_type.hasOptions) ...[
          const SizedBox(height: 12),
          TextFormField(
            controller: _optionsCtrl,
            decoration: const InputDecoration(
              labelText: 'Options (one per line)',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            maxLines: 5,
            minLines: 3,
            validator: (_) {
              final opts = _parseOptions();
              if (opts.isEmpty) return 'Add at least one option';
              return null;
            },
            onChanged: (_) => setState(() {}),
          ),
        ],
        const SizedBox(height: 8),
        SwitchListTile(
          value: _isRequired,
          onChanged: (v) {
            if (v && !_isRequired) _showRequiredWarning();
            setState(() => _isRequired = v);
          },
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: const Text('Required'),
          subtitle: Text(
            'Field users must enter a value to save the $singular',
            style: const TextStyle(fontSize: 11),
          ),
        ),
        SwitchListTile(
          value: _showInForm,
          onChanged: (v) => setState(() => _showInForm = v),
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: const Text('Show in form'),
          subtitle: Text(
            'Render in $singular create/edit form. Off = data-only field '
            'populated by automation or import.',
            style: const TextStyle(fontSize: 11),
          ),
        ),
        SwitchListTile(
          value: _groupable,
          onChanged: (v) => setState(() => _groupable = v),
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: const Text('Groupable'),
          subtitle: const Text(
            'Mirror values to an indexed table for reporting / group-by',
            style: TextStyle(fontSize: 11),
          ),
        ),
      ],
    );
  }

  Widget _buildPreviewColumn() {
    final fakeDef = CustomFieldDefinition(
      id: 'preview',
      workspaceId: '',
      entityType: 'project',
      key: 'preview',
      label: _labelCtrl.text.trim().isEmpty ? 'Field label' : _labelCtrl.text,
      type: _type,
      options: _type.hasOptions
          ? <String, dynamic>{'items': _parseOptions()}
          : null,
      isRequired: _isRequired,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    return Container(
      padding: const EdgeInsets.all(AppSpacing.base),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'PREVIEW',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: AppColors.textTertiary,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            fakeDef.label + (fakeDef.isRequired ? ' *' : ''),
            style: const TextStyle(fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 6),
          FormFieldPreview(
            field: fakeDef.toFormFieldDefinition(),
            dense: false,
          ),
        ],
      ),
    );
  }

  void _showRequiredWarning() {
    final plural = context
        .read<WorkspaceProvider>()
        .projectTerminology
        .toLowerCase();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 4),
        content: Text(
          'Heads-up: existing $plural without a value for this field will '
          'fail to save until a value is provided.',
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final label = _labelCtrl.text.trim();
    final group = _groupCtrl.text.trim();
    final options = _type.hasOptions ? _parseOptions() : null;

    try {
      if (_isEdit) {
        await widget.provider.update(
          id: widget.existing!.id,
          label: label,
          fieldGroup: group,
          clearFieldGroup: group.isEmpty,
          options: options,
          clearOptions: options == null && _type.hasOptions,
          isRequired: _isRequired,
          showInForm: _showInForm,
          groupable: _groupable,
        );
      } else {
        await widget.provider.create(
          label: label,
          type: _type,
          fieldGroup: group.isEmpty ? null : group,
          options: options,
          isRequired: _isRequired,
          showInForm: _showInForm,
          groupable: _groupable,
          createdBy: widget.createdBy,
        );
      }
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Save failed: $e')),
        );
      }
    }
  }
}
