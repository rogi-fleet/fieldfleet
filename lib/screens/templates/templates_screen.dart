import 'package:flutter/material.dart';
import '../../utils/user_facing_error.dart';
import '../../widgets/common/module_header.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../../models/document_template.dart';
import '../../models/document_type.dart';
import '../../models/template_category.dart';
import '../../models/workflow_template.dart';
import '../../models/project.dart';
import '../../services/service_locator.dart';
import '../../providers/auth_provider.dart';
import '../../theme/theme.dart';
import '../../widgets/ai/ai_project_setup_wizard.dart';
import '../../widgets/common/app_search_bar.dart';
import '../../widgets/project_selector_dialog.dart';
import '../../widgets/adaptive_navigation.dart';
import '../../models/field_form_template.dart';

/// Unified templates screen: Documents, Forms, and Workflows.
class TemplatesScreen extends StatefulWidget {
  /// Initial tab index (0 = Documents, 1 = Forms, 2 = Workflows)
  final int initialTabIndex;

  const TemplatesScreen({super.key, this.initialTabIndex = 0});

  @override
  State<TemplatesScreen> createState() => _TemplatesScreenState();
}

class _TemplatesScreenState extends State<TemplatesScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  dynamic get _documentTemplateService =>
      ServiceLocator.documentTemplateService;
  dynamic get _workflowTemplateService =>
      ServiceLocator.workflowTemplateService;
  dynamic get _fieldFormService => ServiceLocator.fieldFormService;
  String _workflowSearchQuery = '';
  bool _workflowSearchExpanded = false;
  bool _showSystemWorkflowTemplates = true;
  bool _showCustomWorkflowTemplates = true;
  bool _isGeneratingWorkflowDefaults = false;
  bool _isGeneratingFieldFormDefaults = false;
  String _fieldFormSearchQuery = '';
  FieldFormCategory? _fieldFormFilterCategory;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 3,
      vsync: this,
      initialIndex: widget.initialTabIndex.clamp(0, 2),
    );
    _tabController.addListener(_onTabChanged);
  }

  @override
  void didUpdateWidget(covariant TemplatesScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // When the user clicks Forms in the sidebar after first visiting
    // Templates (or vice-versa), GoRouter rebuilds with a new
    // initialTabIndex but the State (and its TabController) are reused, so
    // the tab pointer doesn't move. Sync the controller when the prop
    // genuinely changes.
    if (oldWidget.initialTabIndex != widget.initialTabIndex &&
        widget.initialTabIndex != _tabController.index) {
      _tabController.index = widget.initialTabIndex.clamp(0, 2);
    }
  }

  void _onTabChanged() {
    if (_tabController.indexIsChanging) {
      setState(() {});
    } else {
      TabSwitchNotification().dispatch(context);
    }
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = context.watch<AuthProvider>();
    final workspaceId = authProvider.appUser?.currentWorkspaceId;

    if (workspaceId == null) {
      return const Center(child: Text('Error: No workspace found'));
    }

    return Scaffold(
      body: Column(
        children: [
          const ModuleHeader(
            icon: Icons.dashboard_customize_outlined,
            title: 'Templates',
            description:
                'Reusable documents, forms and workflow blueprints.',
          ),
          Container(
            color: Theme.of(context).scaffoldBackgroundColor,
            child: Row(
              children: [
                Expanded(
                  child: TabBar(
                    controller: _tabController,
                    isScrollable: true,
                    tabAlignment: TabAlignment.start,
                    tabs: const [
                      Tab(icon: Icon(Icons.description), text: 'Documents'),
                      Tab(icon: Icon(Icons.assignment), text: 'Forms'),
                      Tab(icon: Icon(Icons.alt_route), text: 'Workflows'),
                    ],
                  ),
                ),
                if (_tabController.index == 0)
                  IconButton(
                    icon: const Icon(Icons.auto_fix_high),
                    tooltip: 'Generate All Default Templates',
                    onPressed: () => _generateAllDefaults(context, workspaceId),
                  ),
                if (_tabController.index == 1)
                  IconButton(
                    icon: const Icon(Icons.auto_fix_high),
                    tooltip: 'Generate Default Form Templates',
                    onPressed: _isGeneratingFieldFormDefaults
                        ? null
                        : () => _generateFieldFormDefaults(context, workspaceId),
                  ),
                if (_tabController.index == 2)
                  IconButton(
                    icon: const Icon(Icons.auto_fix_high),
                    tooltip: 'Generate Core Workflow Templates',
                    onPressed: _isGeneratingWorkflowDefaults
                        ? null
                        : () => _generateWorkflowDefaults(context, workspaceId),
                  ),
                IconButton(
                  icon: const Icon(Icons.add),
                  tooltip: switch (_tabController.index) {
                    1 => 'Create Form Template',
                    2 => 'Create Workflow Template',
                    _ => 'Create Document Template',
                  },
                  onPressed: () => _createTemplate(context),
                ),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              physics: const NeverScrollableScrollPhysics(),
              controller: _tabController,
              children: [
                _buildDocumentTemplatesTab(workspaceId),
                _buildFieldFormsTab(workspaceId),
                _buildWorkflowTemplatesTab(workspaceId),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _createTemplate(BuildContext context) {
    if (_tabController.index == 1) {
      context.push('/field-forms/new');
    } else if (_tabController.index == 2) {
      _showWorkflowTemplateDialog(context);
    } else {
      context.go('/documents/templates/new');
    }
  }

  Future<void> _generateAllDefaults(
    BuildContext context,
    String workspaceId,
  ) async {
    final authProvider = context.read<AuthProvider>();
    final userId = authProvider.appUser?.id ?? '';

    try {
      await _documentTemplateService.initializeDefaultTemplates(
        workspaceId,
        userId,
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('All default templates created successfully!'),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              UserFacingError.uiMessage(e, action: 'creating templates'),
            ),
          ),
        );
      }
    }
  }

  // ==================== Field Forms Tab ====================

  Widget _buildFieldFormsTab(String workspaceId) {
    return StreamBuilder<List<FieldFormTemplate>>(
      stream: _fieldFormService.getTemplates(workspaceId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
            child: SelectableText(
              UserFacingError.uiMessage(snapshot.error, action: 'load data'),
            ),
          );
        }

        final all = snapshot.data ?? [];
        var filtered = all.toList();
        if (_fieldFormFilterCategory != null) {
          filtered = filtered
              .where((t) => t.category == _fieldFormFilterCategory)
              .toList();
        }
        if (_fieldFormSearchQuery.isNotEmpty) {
          final q = _fieldFormSearchQuery.toLowerCase();
          filtered = filtered
              .where((t) =>
                  t.name.toLowerCase().contains(q) ||
                  (t.description?.toLowerCase().contains(q) ?? false))
              .toList();
        }

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      decoration: InputDecoration(
                        hintText: 'Search field forms…',
                        prefixIcon: const Icon(Icons.search, size: 20),
                        isDense: true,
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(AppRadius.sm)),
                        contentPadding:
                            const EdgeInsets.symmetric(vertical: 10),
                      ),
                      onChanged: (v) =>
                          setState(() => _fieldFormSearchQuery = v),
                    ),
                  ),
                  const SizedBox(width: 8),
                  PopupMenuButton<FieldFormCategory?>(
                    tooltip: 'Filter by category',
                    icon: Badge(
                      isLabelVisible: _fieldFormFilterCategory != null,
                      child: const Icon(Icons.filter_list),
                    ),
                    onSelected: (cat) =>
                        setState(() => _fieldFormFilterCategory = cat),
                    itemBuilder: (_) => [
                      const PopupMenuItem(
                          value: null, child: Text('All categories')),
                      ...FieldFormCategory.values.map(
                        (c) =>
                            PopupMenuItem(value: c, child: Text(c.displayName)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Expanded(
              child: filtered.isEmpty
                  ? _buildFieldFormEmptyState(context, all.isEmpty)
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                      itemCount: filtered.length,
                      itemBuilder: (context, index) {
                        final t = filtered[index];
                        return _FieldFormCard(
                          template: t,
                          onEdit: () =>
                              context.push('/field-forms/${t.id}/edit'),
                          onFill: () =>
                              context.push('/field-forms/${t.id}/fill'),
                          onDuplicate: () =>
                              _duplicateFieldForm(context, t),
                          onDelete: () =>
                              _deleteFieldForm(context, t),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildFieldFormEmptyState(BuildContext context, bool noTemplatesAtAll) {
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
                  ? 'Create inspection forms, completion reports, safety checklists, and more.'
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

  Future<void> _duplicateFieldForm(
      BuildContext context, FieldFormTemplate template) async {
    final auth = context.read<AuthProvider>();
    final userId = auth.appUser?.id;
    if (userId == null) return;
    try {
      await _fieldFormService.duplicateTemplate(
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

  Future<void> _deleteFieldForm(
      BuildContext context, FieldFormTemplate template) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Template'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Delete "${template.name}"?'),
            const SizedBox(height: 8),
            Text(
              'This cannot be undone. Templates with existing submissions cannot be deleted — duplicate and archive instead.',
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
            ),
          ],
        ),
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
      await _fieldFormService.deleteTemplate(template.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Deleted "${template.name}"')),
        );
      }
    } catch (e) {
      if (mounted) {
        final msg = e.toString().contains('violates foreign key')
            ? 'Cannot delete — this template has existing submissions. Duplicate it and archive the original instead.'
            : 'Error: $e';
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(msg)));
      }
    }
  }

  Future<void> _generateFieldFormDefaults(
      BuildContext context, String workspaceId) async {
    final auth = context.read<AuthProvider>();
    final userId = auth.appUser?.id ?? '';

    setState(() => _isGeneratingFieldFormDefaults = true);
    try {
      await _fieldFormService.generateDefaultTemplates(
        workspaceId: workspaceId,
        createdBy: userId,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Default field form templates created!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              UserFacingError.uiMessage(e, action: 'creating templates'),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isGeneratingFieldFormDefaults = false);
    }
  }


  // ==================== Document Templates Tab ====================

  Widget _buildDocumentTemplatesTab(String workspaceId) {
    return StreamBuilder<Map<TemplateCategory, List<DocumentTemplate>>>(
      stream: _documentTemplateService.getTemplatesByCategory(workspaceId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Center(
            child: SelectableText(
              UserFacingError.uiMessage(snapshot.error, action: 'load data'),
            ),
          );
        }

        final groupedTemplates = snapshot.data ?? {};

        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
          itemCount: TemplateCategory.values.length,
          itemBuilder: (context, index) {
            final category = TemplateCategory.values[index];
            final templates = groupedTemplates[category] ?? [];
            return _buildCategorySection(
              context,
              category,
              templates,
              workspaceId,
            );
          },
        );
      },
    );
  }

  Widget _buildCategorySection(
    BuildContext context,
    TemplateCategory category,
    List<DocumentTemplate> templates,
    String workspaceId,
  ) {
    final chrome = ChromeColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        // Category Header
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    category.displayName.toUpperCase(),
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: category.color,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    category.description,
                    style: TextStyle(
                      fontSize: 13,
                      color: chrome.scaffoldTextSecondary,
                    ),
                  ),
                ],
              ),
            ),
            TextButton.icon(
              onPressed: () => _createTemplateForCategory(context, category),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Template'),
              style: TextButton.styleFrom(foregroundColor: category.color),
            ),
          ],
        ),
        const SizedBox(height: 12),
        // Templates as chips
        if (templates.isEmpty)
          _buildCategoryEmptyState(context, category, workspaceId)
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: templates.map((template) {
              return _buildTemplateChip(context, template, category);
            }).toList(),
          ),
        const SizedBox(height: 16),
        Divider(color: chrome.scaffoldDivider),
      ],
    );
  }

  Widget _buildTemplateChip(
    BuildContext context,
    DocumentTemplate template,
    TemplateCategory category,
  ) {
    final chrome = ChromeColors.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => context.go('/documents/templates/${template.id}/edit'),
        borderRadius: BorderRadius.circular(AppRadius.sm),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
          decoration: BoxDecoration(
            border: Border.all(color: chrome.scaffoldDivider),
            borderRadius: BorderRadius.circular(AppRadius.sm),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.description_outlined,
                size: 16,
                color: chrome.scaffoldTextSecondary,
              ),
              const SizedBox(width: 8),
              Text(template.name, style: TextStyle(fontSize: 13, color: chrome.scaffoldText)),
              const SizedBox(width: 4),
              PopupMenuButton<String>(
                padding: EdgeInsets.zero,
                iconSize: 18,
                icon: Icon(
                  Icons.more_vert,
                  size: 16,
                  color: chrome.scaffoldTextSecondary,
                ),
                onSelected: (value) async {
                  switch (value) {
                    case 'edit':
                      context.go('/documents/templates/${template.id}/edit');
                      break;
                    case 'use':
                      context.go('/documents/create?templateId=${template.id}');
                      break;
                    case 'duplicate':
                      await _duplicateDocumentTemplate(context, template);
                      break;
                    case 'delete':
                      await _deleteDocumentTemplate(context, template);
                      break;
                  }
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: 'use',
                    child: Text('Create Document'),
                  ),
                  const PopupMenuItem(
                    value: 'edit',
                    child: Text('Edit Template'),
                  ),
                  const PopupMenuItem(
                    value: 'duplicate',
                    child: Text('Duplicate'),
                  ),
                  const PopupMenuDivider(),
                  const PopupMenuItem(
                    value: 'delete',
                    child: Text(
                      'Delete',
                      style: TextStyle(color: AppColors.error),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCategoryEmptyState(
    BuildContext context,
    TemplateCategory category,
    String workspaceId,
  ) {
    return OutlinedButton.icon(
      onPressed: () =>
          _generateCategoryDefaults(context, category, workspaceId),
      icon: const Icon(Icons.auto_fix_high, size: 16),
      label: const Text('Generate Default Templates'),
      style: OutlinedButton.styleFrom(
        foregroundColor: category.color,
        side: BorderSide(color: category.color.withAlpha(128)),
      ),
    );
  }

  void _createTemplateForCategory(
    BuildContext context,
    TemplateCategory category,
  ) {
    // Get first document type for this category as default
    final types = DocumentTypeExtension.forCategory(category);
    if (types.isNotEmpty) {
      // Navigate to template editor - could pass category as param
      context.go('/documents/templates/new');
    }
  }

  Future<void> _generateCategoryDefaults(
    BuildContext context,
    TemplateCategory category,
    String workspaceId,
  ) async {
    try {
      final authProvider = context.read<AuthProvider>();
      final userId = authProvider.appUser?.id ?? '';
      await _documentTemplateService.initializeCategoryTemplates(
        workspaceId,
        category,
        userId,
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${category.displayName} templates created')),
        );
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

  Future<void> _duplicateDocumentTemplate(
    BuildContext context,
    DocumentTemplate template,
  ) async {
    try {
      final authProvider = context.read<AuthProvider>();
      final userId = authProvider.appUser?.id ?? '';
      await _documentTemplateService.duplicateTemplate(
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

  Future<void> _deleteDocumentTemplate(
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
        await _documentTemplateService.deleteTemplate(template.id);
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

  // ==================== Workflow Templates Tab ====================

  Widget _buildWorkflowTemplatesTab(String workspaceId) {
    return StreamBuilder<List<WorkflowTemplate>>(
      stream: _workflowTemplateService.getTemplates(workspaceId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Center(
            child: SelectableText(
              UserFacingError.uiMessage(snapshot.error, action: 'load data'),
            ),
          );
        }

        final templates = snapshot.data ?? const <WorkflowTemplate>[];
        final filteredTemplates = templates.where((template) {
          final isSystemMatch =
              (template.isSystem && _showSystemWorkflowTemplates) ||
              (!template.isSystem && _showCustomWorkflowTemplates);
          if (!isSystemMatch) return false;

          if (_workflowSearchQuery.isEmpty) return true;
          final q = _workflowSearchQuery.toLowerCase();
          return template.name.toLowerCase().contains(q) ||
              (template.description?.toLowerCase().contains(q) ?? false) ||
              template.slug.toLowerCase().contains(q);
        }).toList();

        if (templates.isEmpty) {
          final chrome = ChromeColors.of(context);
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.alt_route,
                  size: 64,
                  color: chrome.scaffoldTextSecondary,
                ),
                const SizedBox(height: 16),
                Text(
                  'No workflow templates yet',
                  style: TextStyle(
                    fontSize: 18,
                    color: chrome.scaffoldText,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'Generate core templates, then customize per workspace.',
                  style: TextStyle(fontSize: 13, color: chrome.scaffoldTextSecondary),
                ),
                const SizedBox(height: 18),
                OutlinedButton.icon(
                  onPressed: () =>
                      _generateWorkflowDefaults(context, workspaceId),
                  icon: const Icon(Icons.auto_fix_high),
                  label: const Text('Generate Core Templates'),
                ),
              ],
            ),
          );
        }

        final chrome = ChromeColors.of(context);
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Column(
                children: [
                  _workflowSearchExpanded
                      ? Row(
                          children: [
                            Expanded(
                              child: AppSearchBar(
                                hintText: 'Search workflow templates...',
                                height: 36,
                                onChanged: (value) {
                                  setState(() => _workflowSearchQuery = value.trim());
                                },
                              ),
                            ),
                            IconButton(
                              icon: Icon(Icons.close, size: 20, color: chrome.scaffoldText),
                              onPressed: () => setState(() {
                                _workflowSearchExpanded = false;
                                _workflowSearchQuery = '';
                              }),
                              visualDensity: VisualDensity.compact,
                            ),
                          ],
                        )
                      : Align(
                          alignment: Alignment.centerLeft,
                          child: IconButton(
                            icon: Icon(Icons.search, size: 22, color: chrome.scaffoldText),
                            tooltip: 'Search workflow templates',
                            onPressed: () => setState(() => _workflowSearchExpanded = true),
                            visualDensity: VisualDensity.compact,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                          ),
                        ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      // Chip fill comes from chipTheme (always light surfaceAlt),
                      // so chrome.scaffoldText would be white-on-white in
                      // dark-chrome mode when the chip is unselected.
                      FilterChip(
                        selected: _showSystemWorkflowTemplates,
                        label: const Text('System'),
                        side: BorderSide(color: chrome.scaffoldDivider),
                        labelStyle: const TextStyle(color: AppColors.textPrimary),
                        onSelected: (value) {
                          setState(() => _showSystemWorkflowTemplates = value);
                        },
                      ),
                      const SizedBox(width: 8),
                      FilterChip(
                        selected: _showCustomWorkflowTemplates,
                        label: const Text('Custom'),
                        side: BorderSide(color: chrome.scaffoldDivider),
                        labelStyle: const TextStyle(color: AppColors.textPrimary),
                        onSelected: (value) {
                          setState(() => _showCustomWorkflowTemplates = value);
                        },
                      ),
                      const Spacer(),
                      Text(
                        '${filteredTemplates.length} shown',
                        style: TextStyle(
                          color: chrome.scaffoldTextSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Expanded(
              child: filteredTemplates.isEmpty
                  ? Center(
                      child: Text(
                        'No templates match your filters.',
                        style: TextStyle(color: chrome.scaffoldTextSecondary),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                      itemCount: filteredTemplates.length,
                      itemBuilder: (context, index) {
                        final template = filteredTemplates[index];
                        return Card(
                          margin: const EdgeInsets.only(bottom: 12),
                          child: ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 10,
                            ),
                            leading: CircleAvatar(
                              backgroundColor: template.isSystem
                                  ? AppColors.primary.withAlpha(35)
                                  : AppColors.success.withAlpha(35),
                              child: Icon(
                                template.isSystem
                                    ? Icons.shield
                                    : Icons.edit_note,
                                color: template.isSystem
                                    ? AppColors.primary
                                    : AppColors.success,
                              ),
                            ),
                            title: Text(template.name),
                            subtitle: Text(
                              template.description ?? 'No description',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: PopupMenuButton<String>(
                              onSelected: (value) async {
                                switch (value) {
                                  case 'preview':
                                    await _showWorkflowTemplatePreview(
                                      context,
                                      template,
                                    );
                                    break;
                                  case 'customize':
                                    await _customizeSystemWorkflowTemplate(
                                      context,
                                      template,
                                    );
                                    break;
                                  case 'edit':
                                    await _showWorkflowTemplateDialog(
                                      context,
                                      template: template,
                                    );
                                    break;
                                  case 'use_ai_setup':
                                    await _useWorkflowTemplateInAiSetup(
                                      context,
                                      template,
                                    );
                                    break;
                                  case 'duplicate':
                                    await _duplicateWorkflowTemplate(
                                      context,
                                      template,
                                    );
                                    break;
                                  case 'delete':
                                    await _deleteWorkflowTemplate(
                                      context,
                                      template,
                                    );
                                    break;
                                }
                              },
                              itemBuilder: (context) => [
                                const PopupMenuItem(
                                  value: 'preview',
                                  child: Text('Preview'),
                                ),
                                if (template.isSystem)
                                  const PopupMenuItem(
                                    value: 'customize',
                                    child: Text('Customize (Copy)'),
                                  ),
                                const PopupMenuItem(
                                  value: 'use_ai_setup',
                                  child: Text('Use in AI Setup'),
                                ),
                                if (!template.isSystem)
                                  const PopupMenuItem(
                                    value: 'edit',
                                    child: Text('Edit Template'),
                                  ),
                                const PopupMenuItem(
                                  value: 'duplicate',
                                  child: Text('Duplicate'),
                                ),
                                if (!template.isSystem)
                                  const PopupMenuDivider(),
                                if (!template.isSystem)
                                  const PopupMenuItem(
                                    value: 'delete',
                                    child: Text(
                                      'Delete',
                                      style: TextStyle(color: AppColors.error),
                                    ),
                                  ),
                              ],
                            ),
                            onTap: () =>
                                _showWorkflowTemplatePreview(context, template),
                          ),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _generateWorkflowDefaults(
    BuildContext context,
    String workspaceId,
  ) async {
    setState(() => _isGeneratingWorkflowDefaults = true);
    final userId = context.read<AuthProvider>().appUser?.id ?? '';
    try {
      await _workflowTemplateService.initializeCoreTemplates(
        workspaceId: workspaceId,
        createdBy: userId,
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Core workflow templates generated')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              UserFacingError.uiMessage(e, action: 'generating templates'),
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isGeneratingWorkflowDefaults = false);
      }
    }
  }

  Future<void> _showWorkflowTemplateDialog(
    BuildContext context, {
    WorkflowTemplate? template,
  }) async {
    if (template?.isSystem == true) {
      return;
    }

    final authProvider = context.read<AuthProvider>();
    final workspaceId = authProvider.appUser?.currentWorkspaceId ?? '';
    final createdBy = authProvider.appUser?.id ?? '';
    if (workspaceId.isEmpty || createdBy.isEmpty) return;

    final nameController = TextEditingController(text: template?.name ?? '');
    final descriptionController = TextEditingController(
      text: template?.description ?? '',
    );
    final markdownController = TextEditingController(
      text: template?.workflowMarkdown ?? '',
    );

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          template == null ? 'New Workflow Template' : 'Edit Workflow Template',
        ),
        content: SizedBox(
          width: 640,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: 'Template Name',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: descriptionController,
                  decoration: const InputDecoration(
                    labelText: 'Description',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 2,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: markdownController,
                  decoration: const InputDecoration(
                    labelText: 'Workflow Definition (Markdown)',
                    border: OutlineInputBorder(),
                    alignLabelWithHint: true,
                  ),
                  minLines: 10,
                  maxLines: 16,
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (saved != true || !context.mounted) return;

    final name = nameController.text.trim();
    final markdown = markdownController.text.trim();
    if (name.isEmpty || markdown.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Name and workflow definition are required'),
        ),
      );
      return;
    }

    try {
      if (template == null) {
        final baseSlug = _slugify(name);
        try {
          await _workflowTemplateService.createTemplate(
            workspaceId: workspaceId,
            name: name,
            slug: baseSlug,
            description: descriptionController.text.trim().isEmpty
                ? null
                : descriptionController.text.trim(),
            workflowMarkdown: markdown,
            createdBy: createdBy,
          );
        } catch (_) {
          await _workflowTemplateService.createTemplate(
            workspaceId: workspaceId,
            name: name,
            slug: '$baseSlug-${DateTime.now().millisecondsSinceEpoch}',
            description: descriptionController.text.trim().isEmpty
                ? null
                : descriptionController.text.trim(),
            workflowMarkdown: markdown,
            createdBy: createdBy,
          );
        }
      } else {
        await _workflowTemplateService.updateTemplate(
          templateId: template.id,
          name: name,
          description: descriptionController.text.trim().isEmpty
              ? null
              : descriptionController.text.trim(),
          workflowMarkdown: markdown,
        );
      }
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              template == null ? 'Template created' : 'Template updated',
            ),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              UserFacingError.uiMessage(e, action: 'saving template'),
            ),
          ),
        );
      }
    }
  }

  Future<void> _showWorkflowTemplatePreview(
    BuildContext context,
    WorkflowTemplate template,
  ) async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(template.name),
        content: SizedBox(
          width: 700,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  template.description ?? 'No description provided.',
                  style: const TextStyle(color: AppColors.textSecondary),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  children: [
                    Chip(label: Text(template.isSystem ? 'System' : 'Custom')),
                    Chip(label: Text('Slug: ${template.slug}')),
                  ],
                ),
                const SizedBox(height: 12),
                SelectableText(
                  template.workflowMarkdown,
                  style: const TextStyle(fontSize: 13, height: 1.45),
                ),
              ],
            ),
          ),
        ),
        actions: [
          if (template.isSystem)
            TextButton(
              onPressed: () async {
                Navigator.pop(context);
                await _customizeSystemWorkflowTemplate(context, template);
              },
              child: const Text('Customize (Copy)'),
            ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await _useWorkflowTemplateInAiSetup(context, template);
            },
            child: const Text('Use in AI Setup'),
          ),
          if (!template.isSystem)
            TextButton(
              onPressed: () async {
                Navigator.pop(context);
                await _showWorkflowTemplateDialog(context, template: template);
              },
              child: const Text('Edit'),
            ),
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _customizeSystemWorkflowTemplate(
    BuildContext context,
    WorkflowTemplate template,
  ) async {
    try {
      final createdBy = context.read<AuthProvider>().appUser?.id ?? '';
      if (createdBy.isEmpty) return;
      final duplicated = await _workflowTemplateService.duplicateTemplate(
        template: template,
        createdBy: createdBy,
      );
      if (!context.mounted) return;
      await _showWorkflowTemplateDialog(context, template: duplicated);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              UserFacingError.uiMessage(e, action: 'customizing template'),
            ),
          ),
        );
      }
    }
  }

  Future<void> _useWorkflowTemplateInAiSetup(
    BuildContext context,
    WorkflowTemplate template,
  ) async {
    final workspaceId = context
        .read<AuthProvider>()
        .appUser
        ?.currentWorkspaceId;
    if (workspaceId == null || workspaceId.isEmpty) {
      return;
    }

    final project = await showDialog<Project>(
      context: context,
      builder: (context) => ProjectSelectorDialog(workspaceId: workspaceId),
    );

    if (!context.mounted || project == null) return;

    showAiProjectSetupWizard(
      context,
      project: project,
      workspaceId: workspaceId,
      initialWorkflowTemplateId: template.id,
    );
  }

  Future<void> _duplicateWorkflowTemplate(
    BuildContext context,
    WorkflowTemplate template,
  ) async {
    final createdBy = context.read<AuthProvider>().appUser?.id ?? '';
    if (createdBy.isEmpty) return;

    try {
      await _workflowTemplateService.duplicateTemplate(
        template: template,
        createdBy: createdBy,
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Workflow template duplicated')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              UserFacingError.uiMessage(e, action: 'duplicating template'),
            ),
          ),
        );
      }
    }
  }

  Future<void> _deleteWorkflowTemplate(
    BuildContext context,
    WorkflowTemplate template,
  ) async {
    if (template.isSystem) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('System templates cannot be deleted')),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Workflow Template'),
        content: Text('Delete "${template.name}" permanently?'),
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

    if (confirmed != true || !context.mounted) return;
    try {
      await _workflowTemplateService.deleteTemplate(template.id);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Workflow template deleted')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              UserFacingError.uiMessage(e, action: 'deleting template'),
            ),
          ),
        );
      }
    }
  }

  String _slugify(String value) {
    final slug = value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-');
    return slug.replaceAll(RegExp(r'^-+|-+$'), '');
  }
}

class _FieldFormCard extends StatelessWidget {
  const _FieldFormCard({
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
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: AppSpacing.base, vertical: AppSpacing.sm),
        leading: CircleAvatar(
          backgroundColor: _categoryColor(template.category).withOpacity(0.1),
          child: Icon(_categoryIcon(template.category),
              color: _categoryColor(template.category), size: 20),
        ),
        title: Text(template.name,
            style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 2),
                  decoration: BoxDecoration(
                    color:
                        _categoryColor(template.category).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(AppRadius.r12),
                    border: Border.all(
                        color: _categoryColor(template.category)
                            .withOpacity(0.3)),
                  ),
                  child: Text(
                    template.category.displayName,
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: _categoryColor(template.category)),
                  ),
                ),
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
              child:
                  Text('Delete', style: TextStyle(color: AppColors.error)),
            ),
          ],
        ),
        onTap: onEdit,
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

  Color _categoryColor(FieldFormCategory cat) {
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
