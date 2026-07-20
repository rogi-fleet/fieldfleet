import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/project_template.dart';
import '../providers/auth_provider.dart';
import '../providers/workspace_provider.dart';
import '../screens/projects/project_onboarding_wizard.dart';
import '../services/service_locator.dart';
import '../theme/theme.dart';
import 'common/form_popup_header.dart';
import 'common/unsaved_changes_guard.dart';
import 'nav_breadcrumb_bar.dart';

String _getSingularTerminology(BuildContext context) {
  final plural = context.watch<WorkspaceProvider>().projectTerminology;
  if (plural.endsWith('s') && plural.length > 1) {
    return plural.substring(0, plural.length - 1);
  }
  return plural;
}

/// Shows the project form as a popup overlay
/// For new projects: Shows the step-by-step onboarding wizard
/// For editing projects: Reuses the same onboarding wizard in edit mode
void showProjectFormPopup(
  BuildContext context, {
  String? projectId,
  String? initialCustomerId,
  String? initialVendorId,
  DateTime? initialStartDate,
}) {
  final isMobile = MediaQuery.of(context).size.width < AppBreakpoints.mobile;
  final isNewProject = projectId == null;

  if (isMobile) {
    // Show as bottom sheet on mobile
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _ProjectFormBottomSheet(
        projectId: projectId,
        isNewProject: isNewProject,
        initialCustomerId: initialCustomerId,
        initialVendorId: initialVendorId,
        initialStartDate: initialStartDate,
      ),
    );
  } else {
    // Show as dialog on desktop
    showDialog(
      context: context,
      builder: (context) => _ProjectWizardDialog(
        initialCustomerId: initialCustomerId,
        initialVendorId: initialVendorId,
        projectId: projectId,
        initialStartDate: initialStartDate,
      ),
    );
  }
}

/// Wizard dialog for new projects (desktop)
/// Shows a choice screen first: Start Fresh or Start from Template
class _ProjectWizardDialog extends StatefulWidget {
  final String? initialCustomerId;
  final String? initialVendorId;
  final String? projectId;
  final DateTime? initialStartDate;

  const _ProjectWizardDialog({
    this.initialCustomerId,
    this.initialVendorId,
    this.projectId,
    this.initialStartDate,
  });

  @override
  State<_ProjectWizardDialog> createState() => _ProjectWizardDialogState();
}

class _ProjectWizardDialogState extends State<_ProjectWizardDialog> {
  ProjectTemplate? _selectedTemplate;
  bool _showWizard = false;
  bool get _isEditMode => widget.projectId != null;
  final _dirty = ValueNotifier<bool>(false);

  String? _navLocationOnOpen;

  @override
  void initState() {
    super.initState();
    _navLocationOnOpen = NavHistoryController.instance.current;
    // Dismiss the dialog automatically when the user navigates away — the
    // wizard uses showDialog on the root navigator (so the page underneath
    // can re-render via GoRouter), but that means hash-route changes don't
    // pop it. Without this listener you can navigate to /calendar / /ai-
    // assistant / anywhere and the wizard stays floating on top of the new
    // page, intercepting clicks and typing.
    NavHistoryController.instance.addListener(_onLocationChanged);
  }

  void _onLocationChanged() {
    if (!mounted) return;
    final current = NavHistoryController.instance.current;
    if (current != _navLocationOnOpen) {
      Navigator.of(context, rootNavigator: true).maybePop();
    }
  }

  @override
  void dispose() {
    NavHistoryController.instance.removeListener(_onLocationChanged);
    _dirty.dispose();
    super.dispose();
  }

  void _startFresh() {
    setState(() {
      _selectedTemplate = null;
      _showWizard = true;
    });
  }

  void _startFromTemplate(ProjectTemplate template) {
    setState(() {
      _selectedTemplate = template;
      _showWizard = true;
    });
  }

  void _goBackToChoice() {
    setState(() {
      _selectedTemplate = null;
      _showWizard = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final showWizard = _isEditMode ? true : _showWizard;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        await maybeCloseForm(context, isDirty: _dirty.value);
      },
      child: Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.r16)),
        child: Container(
          width: 700,
          height: MediaQuery.of(context).size.height * 0.85,
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.9,
            maxHeight: MediaQuery.of(context).size.height * 0.9,
          ),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(AppRadius.r16),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.r16),
            child: Column(
              children: [
                // Header with title and close button
                FormPopupHeader(
                  icon: showWizard ? null : Icons.rocket_launch,
                  onBack: (_showWizard && !_isEditMode) ? _goBackToChoice : null,
                  title: showWizard
                      ? (_selectedTemplate != null
                            ? 'From Template: ${_selectedTemplate!.name}'
                            : (_isEditMode
                                  ? 'Edit ${_getSingularTerminology(context)}'
                                  : 'Create New ${_getSingularTerminology(context)}'))
                      : 'Create New ${_getSingularTerminology(context)}',
                  onClose: () =>
                      maybeCloseForm(context, isDirty: _dirty.value),
                ),
                // Content: choice screen or wizard
                Expanded(
                  child: showWizard
                      ? ProjectOnboardingWizard(
                          initialCustomerId: widget.initialCustomerId,
                          initialVendorId: widget.initialVendorId,
                          initialStartDate: widget.initialStartDate,
                          template: _selectedTemplate,
                          projectId: widget.projectId,
                          dirtyNotifier: _dirty,
                        )
                      : _ProjectCreationChoice(
                          onStartFresh: _startFresh,
                          onSelectTemplate: _startFromTemplate,
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Choice screen: Start Fresh or Start from Template
class _ProjectCreationChoice extends StatelessWidget {
  final VoidCallback onStartFresh;
  final ValueChanged<ProjectTemplate> onSelectTemplate;

  const _ProjectCreationChoice({
    required this.onStartFresh,
    required this.onSelectTemplate,
  });

  @override
  Widget build(BuildContext context) {
    final workspaceId =
        context.read<AuthProvider>().appUser?.currentWorkspaceId ?? '';
    final isCompact = MediaQuery.of(context).size.width < 720;

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.xxl),
      child: Column(
        children: [
          // The dialog surface tracks colorScheme.surface; pin the heading
          // color to onSurface so it stays legible in dark chrome (where the
          // GoogleFonts inter default body color would otherwise sit dark
          // on dark).
          Text(
            'How would you like to start?',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Start from scratch or use a saved template',
            style: TextStyle(
              color: Theme.of(context)
                  .colorScheme
                  .onSurface
                  .withValues(alpha: 0.65),
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 32),

          // Option cards
          Flex(
            direction: isCompact ? Axis.vertical : Axis.horizontal,
            children: [
              Flexible(
                fit: FlexFit.tight,
                child: _ChoiceCard(
                  icon: Icons.add_circle_outline,
                  title: 'Start Fresh',
                  subtitle: 'Create from scratch with the setup wizard',
                  color: Theme.of(context).colorScheme.primary,
                  onTap: onStartFresh,
                ),
              ),
              SizedBox(width: isCompact ? 0 : 16, height: isCompact ? 16 : 0),
              Flexible(
                fit: FlexFit.tight,
                child: _ChoiceCard(
                  icon: Icons.content_copy,
                  title: 'Start from Template',
                  subtitle: 'Use a saved template with pre-configured settings',
                  color: AppColors.success,
                  onTap: () => _showTemplatePicker(context, workspaceId),
                ),
              ),
            ],
          ),

          // Saved templates list
          const SizedBox(height: 32),
          Expanded(
            child: _TemplateList(
              workspaceId: workspaceId,
              onSelect: onSelectTemplate,
            ),
          ),
        ],
      ),
    );
  }

  void _showTemplatePicker(BuildContext context, String workspaceId) {
    // The template list is already shown below — this card is a hint
    // Just scroll or focus attention there. For simplicity, we do nothing
    // extra since the list is already visible.
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Select a template from the list below')),
    );
  }
}

class _ChoiceCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const _ChoiceCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.r12),
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.xl),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.r12),
            border: Border.all(color: color.withValues(alpha: 0.3)),
            color: color.withValues(alpha: 0.05),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 40, color: color),
              const SizedBox(height: 12),
              Text(
                title,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.65),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// List of saved project templates
class _TemplateList extends StatelessWidget {
  final String workspaceId;
  final ValueChanged<ProjectTemplate> onSelect;

  const _TemplateList({required this.workspaceId, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    if (workspaceId.isEmpty) {
      return const Center(child: Text('No workspace selected'));
    }

    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              Icons.bookmarks,
              size: 18,
              color: onSurface.withValues(alpha: 0.65),
            ),
            const SizedBox(width: 8),
            Text(
              'Saved Templates',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: onSurface.withValues(alpha: 0.65),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Expanded(
          child: StreamBuilder<List<ProjectTemplate>>(
            stream: ServiceLocator.projectTemplateService.getTemplates(
              workspaceId,
            ),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              final templates = snapshot.data ?? [];

              if (templates.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.bookmark_border,
                        size: 48,
                        color: onSurface.withValues(alpha: 0.45),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'No templates yet',
                        style: TextStyle(
                          color: onSurface.withValues(alpha: 0.65),
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Save any ${_getSingularTerminology(context).toLowerCase()} as a template from its menu',
                        style: TextStyle(
                          color: onSurface.withValues(alpha: 0.45),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                );
              }

              return ListView.separated(
                itemCount: templates.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final template = templates[index];
                  return _TemplateCard(
                    template: template,
                    onTap: () => onSelect(template),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

class _TemplateCard extends StatelessWidget {
  final ProjectTemplate template;
  final VoidCallback onTap;

  const _TemplateCard({required this.template, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.sm),
            border: Border.all(color: onSurface.withValues(alpha: 0.15)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(AppSpacing.sm),
                decoration: BoxDecoration(
                  color: Theme.of(
                    context,
                  ).colorScheme.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: Icon(
                  Icons.bookmark,
                  size: 20,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      template.name,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                        color: onSurface,
                      ),
                    ),
                    if (template.description != null &&
                        template.description!.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          template.description!,
                          style: TextStyle(
                            fontSize: 12,
                            color: onSurface.withValues(alpha: 0.65),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Row(
                        children: [
                          if (template.tasks.isNotEmpty) ...[
                            Icon(
                              Icons.task_alt,
                              size: 12,
                              color: onSurface.withValues(alpha: 0.45),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '${template.tasks.length} tasks',
                              style: TextStyle(
                                fontSize: 11,
                                color: onSurface.withValues(alpha: 0.45),
                              ),
                            ),
                            const SizedBox(width: 12),
                          ],
                          if (template.budgetItems.isNotEmpty) ...[
                            Icon(
                              Icons.attach_money,
                              size: 12,
                              color: onSurface.withValues(alpha: 0.45),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '${template.budgetItems.length} budget items',
                              style: TextStyle(
                                fontSize: 11,
                                color: onSurface.withValues(alpha: 0.45),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.arrow_forward_ios,
                size: 14,
                color: onSurface.withValues(alpha: 0.45),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Bottom sheet wrapper for mobile
class _ProjectFormBottomSheet extends StatefulWidget {
  final String? projectId;
  final bool isNewProject;
  final String? initialCustomerId;
  final String? initialVendorId;
  final DateTime? initialStartDate;

  const _ProjectFormBottomSheet({
    this.projectId,
    required this.isNewProject,
    this.initialCustomerId,
    this.initialVendorId,
    this.initialStartDate,
  });

  @override
  State<_ProjectFormBottomSheet> createState() =>
      _ProjectFormBottomSheetState();
}

class _ProjectFormBottomSheetState extends State<_ProjectFormBottomSheet> {
  final _dirty = ValueNotifier<bool>(false);
  ProjectTemplate? _selectedTemplate;
  bool _showWizard = false;

  bool get _isEditMode => !widget.isNewProject;

  @override
  void dispose() {
    _dirty.dispose();
    super.dispose();
  }

  void _startFresh() {
    setState(() {
      _selectedTemplate = null;
      _showWizard = true;
    });
  }

  void _startFromTemplate(ProjectTemplate template) {
    setState(() {
      _selectedTemplate = template;
      _showWizard = true;
    });
  }

  void _goBackToChoice() {
    setState(() {
      _selectedTemplate = null;
      _showWizard = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final showWizard = _isEditMode ? true : _showWizard;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        await maybeCloseForm(context, isDirty: _dirty.value);
      },
      child: DraggableScrollableSheet(
        initialChildSize: 0.95,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (context, scrollController) {
          return Container(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(20),
              ),
            ),
            child: Column(
              children: [
                if (widget.isNewProject) ...[
                  // Header for new projects on mobile
                  FormPopupHeader(
                    dense: true,
                    borderRadius:
                        const BorderRadius.vertical(top: Radius.circular(20)),
                    icon: showWizard ? null : Icons.rocket_launch,
                    onBack: showWizard ? _goBackToChoice : null,
                    title: showWizard
                        ? (_selectedTemplate != null
                              ? 'From Template: ${_selectedTemplate!.name}'
                              : 'Create New ${_getSingularTerminology(context)}')
                        : 'Create New ${_getSingularTerminology(context)}',
                    onClose: () =>
                        maybeCloseForm(context, isDirty: _dirty.value),
                  ),
                  Expanded(
                    child: showWizard
                        ? ProjectOnboardingWizard(
                            initialCustomerId: widget.initialCustomerId,
                            initialVendorId: widget.initialVendorId,
                            initialStartDate: widget.initialStartDate,
                            template: _selectedTemplate,
                            dirtyNotifier: _dirty,
                            scrollController: scrollController,
                          )
                        : _ProjectCreationChoice(
                            onStartFresh: _startFresh,
                            onSelectTemplate: _startFromTemplate,
                          ),
                  ),
                ] else ...[
                  // Edit using the same onboarding wizard
                  FormPopupHeader(
                    dense: true,
                    borderRadius:
                        const BorderRadius.vertical(top: Radius.circular(20)),
                    icon: Icons.edit,
                    title: 'Edit ${_getSingularTerminology(context)}',
                    onClose: () =>
                        maybeCloseForm(context, isDirty: _dirty.value),
                  ),
                  Expanded(
                    child: ProjectOnboardingWizard(
                      projectId: widget.projectId,
                      dirtyNotifier: _dirty,
                      scrollController: scrollController,
                    ),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}
