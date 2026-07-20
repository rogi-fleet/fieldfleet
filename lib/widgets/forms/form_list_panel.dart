import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../models/form_template.dart';
import '../../providers/auth_provider.dart';
import '../../services/service_locator.dart';
import '../../theme/theme.dart';
import '../../utils/user_facing_error.dart';
import '../common/draggable_divider.dart';
import '../common/view_icon_button.dart';
import '../common/view_toolbar.dart';
import '../common/zero_items_action_empty_state.dart';

/// Split-panel list of forms for a project tab.
///
/// On desktop (≥ 900 px) shows a resizable list/detail split pane.
/// On mobile the detail panel is omitted and [onNavigateToForm] is called
/// instead.
class FormListPanel extends StatefulWidget {
  final Stream<List<FormTemplate>> formStream;
  final String projectId;
  final VoidCallback onAddFormTap;

  /// Called on mobile when the user taps a form.
  final void Function(String formId)? onNavigateToForm;

  const FormListPanel({
    super.key,
    required this.formStream,
    required this.projectId,
    required this.onAddFormTap,
    this.onNavigateToForm,
  });

  @override
  State<FormListPanel> createState() => _FormListPanelState();
}

class _FormListPanelState extends State<FormListPanel> {
  String _searchQuery = '';
  String? _selectedFormId;
  double _splitRatio = 0.42;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        ViewToolbar(
          searchHint: 'Search forms...',
          searchQuery: _searchQuery,
          onSearch: (q) => setState(() {
            _searchQuery = q.toLowerCase();
            // Clear selection when search changes
          }),
          quickToggles: [
            ViewIconButton(
              icon: Icons.add,
              isSelected: false,
              onTap: widget.onAddFormTap,
              tooltip: 'Add Form',
            ),
          ],
        ),
        Expanded(
          child: StreamBuilder<List<FormTemplate>>(
            stream: widget.formStream,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return Center(
                  child: Text(
                    UserFacingError.uiMessage(
                      snapshot.error,
                      action: 'load forms',
                    ),
                  ),
                );
              }

              var forms = snapshot.data ?? [];

              if (_searchQuery.isNotEmpty) {
                forms = forms
                    .where(
                      (f) =>
                          f.name.toLowerCase().contains(_searchQuery) ||
                          (f.description?.toLowerCase().contains(_searchQuery) ??
                              false),
                    )
                    .toList();
              }

              if (forms.isEmpty) {
                if (_searchQuery.isNotEmpty) {
                  return const Center(
                    child: Text('No forms match your search'),
                  );
                }
                return ZeroItemsActionEmptyState(
                  icon: Icons.dynamic_form_outlined,
                  title: 'No forms yet',
                  subtitle:
                      'Add forms to collect information from customers and team members',
                  ctaLabel: 'Add Form',
                  onTap: widget.onAddFormTap,
                );
              }

              // Ensure selectedFormId is still valid
              if (_selectedFormId != null &&
                  !forms.any((f) => f.id == _selectedFormId)) {
                WidgetsBinding.instance.addPostFrameCallback(
                  (_) => setState(() => _selectedFormId = null),
                );
              }

              return LayoutBuilder(
                builder: (context, constraints) {
                  final isDesktop = constraints.maxWidth >= AppBreakpoints.tablet;

                  if (!isDesktop || _selectedFormId == null) {
                    return _buildList(forms, isDesktop);
                  }

                  // Split pane
                  final listWidth =
                      (constraints.maxWidth * _splitRatio).clamp(220.0, 520.0);
                  final detailWidth = constraints.maxWidth - listWidth - 8;

                  return Row(
                    children: [
                      SizedBox(
                        width: listWidth,
                        child: _buildList(forms, isDesktop),
                      ),
                      GestureDetector(
                        behavior: HitTestBehavior.translucent,
                        onHorizontalDragUpdate: (d) {
                          setState(() {
                            _splitRatio = ((listWidth + d.delta.dx) /
                                    constraints.maxWidth)
                                .clamp(0.25, 0.65);
                          });
                        },
                        child: const DraggableDivider(width: 8),
                      ),
                      SizedBox(
                        width: detailWidth,
                        child: _FormDetailPane(
                          formId: _selectedFormId!,
                          onClose: () =>
                              setState(() => _selectedFormId = null),
                        ),
                      ),
                    ],
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildList(List<FormTemplate> forms, bool isDesktop) {
    return ListView.builder(
      padding: const EdgeInsets.all(AppSpacing.base),
      itemCount: forms.length,
      itemBuilder: (context, i) {
        final form = forms[i];
        final isSelected = isDesktop && _selectedFormId == form.id;
        return _FormListCard(
          form: form,
          isSelected: isSelected,
          onTap: () {
            if (isDesktop) {
              setState(() => _selectedFormId = form.id);
            } else {
              widget.onNavigateToForm?.call(form.id);
            }
          },
        );
      },
    );
  }
}

// ── List card ─────────────────────────────────────────────────────────────────

class _FormListCard extends StatelessWidget {
  final FormTemplate form;
  final bool isSelected;
  final VoidCallback onTap;

  const _FormListCard({
    required this.form,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: isSelected ? AppColors.primaryLight : null,
      shape: isSelected
          ? RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.sm),
              side: BorderSide(color: AppColors.primary, width: 1.5),
            )
          : null,
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: form.isPublic
              ? AppColors.successLight
              : AppColors.surfaceAlt,
          child: Icon(
            Icons.dynamic_form,
            color: form.isPublic ? AppColors.success : AppColors.textTertiary,
            size: 20,
          ),
        ),
        title: Text(
          form.name,
          style: isSelected
              ? TextStyle(
                  fontWeight: FontWeight.w600,
                  color: AppColors.primary,
                )
              : null,
        ),
        subtitle: Row(
          children: [
            Icon(Icons.text_fields, size: 12, color: AppColors.textSecondary),
            const SizedBox(width: 4),
            Text(
              '${form.fieldCount} fields',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
            if (form.isPublic) ...[
              const SizedBox(width: 12),
              Icon(Icons.public, size: 12, color: AppColors.successDark),
              const SizedBox(width: 4),
              Text(
                'Public',
                style: TextStyle(fontSize: 12, color: AppColors.successDark),
              ),
            ],
          ],
        ),
        onTap: onTap,
      ),
    );
  }
}

// ── Detail pane ───────────────────────────────────────────────────────────────

class _FormDetailPane extends StatefulWidget {
  final String formId;
  final VoidCallback onClose;

  const _FormDetailPane({required this.formId, required this.onClose});

  @override
  State<_FormDetailPane> createState() => _FormDetailPaneState();
}

class _FormDetailPaneState extends State<_FormDetailPane> {
  FormTemplate? _form;
  int _submissionCount = 0;
  bool _loading = true;
  bool _togglingPublic = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(_FormDetailPane old) {
    super.didUpdateWidget(old);
    if (old.formId != widget.formId) {
      setState(() {
        _form = null;
        _loading = true;
      });
      _load();
    }
  }

  Future<void> _load() async {
    try {
      final form =
          await ServiceLocator.formService.getFormTemplate(widget.formId);
      final count =
          await ServiceLocator.formService.getSubmissionCount(widget.formId);
      if (mounted) {
        setState(() {
          _form = form;
          _submissionCount = count;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _togglePublic() async {
    final form = _form;
    if (form == null) return;
    setState(() => _togglingPublic = true);
    try {
      await ServiceLocator.formService.togglePublic(form.id, !form.isPublic);
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              UserFacingError.uiMessage(e, action: 'update form'),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _togglingPublic = false);
    }
  }

  Future<void> _deleteForm() async {
    final form = _form;
    if (form == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Form'),
        content: Text(
          'Are you sure you want to delete "${form.name}"? This will also delete all submissions.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    try {
      await ServiceLocator.formService.deleteFormTemplate(form.id);
      widget.onClose();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              UserFacingError.uiMessage(e, action: 'delete form'),
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_form == null) {
      return const Center(child: Text('Form not found'));
    }

    final form = _form!;
    final canManage = context.watch<AuthProvider>().canCreateProjects;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Detail toolbar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: AppColors.cardBorder),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  form.name,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (canManage) ...[
                IconButton(
                  icon: const Icon(Icons.edit_outlined, size: 20),
                  tooltip: 'Edit form',
                  onPressed: () => context.go('/forms/${form.id}/edit'),
                ),
                IconButton(
                  icon: Icon(Icons.delete_outline,
                      size: 20, color: AppColors.error),
                  tooltip: 'Delete form',
                  onPressed: _deleteForm,
                ),
              ],
              IconButton(
                icon: const Icon(Icons.close, size: 20),
                tooltip: 'Close',
                onPressed: widget.onClose,
              ),
            ],
          ),
        ),

        // Scrollable content
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.base),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Stats row
                Row(
                  children: [
                    _Stat(label: 'Fields', value: '${form.fieldCount}'),
                    const SizedBox(width: 24),
                    _Stat(
                        label: 'Required',
                        value: '${form.requiredFieldCount}'),
                    const SizedBox(width: 24),
                    _Stat(
                        label: 'Submissions',
                        value: '$_submissionCount'),
                  ],
                ),

                if (form.description != null &&
                    form.description!.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Text(
                    form.description!,
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                ],

                // Public link
                if (form.isPublic && form.publicSlug != null) ...[
                  const SizedBox(height: 20),
                  Text(
                    'Public Link',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          color: AppColors.textSecondary,
                        ),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.md, vertical: 10),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceAlt,
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.public,
                            size: 16, color: AppColors.success),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '/f/${form.publicSlug}',
                            style: const TextStyle(
                                fontFamily: 'monospace', fontSize: 13),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.copy, size: 16),
                          tooltip: 'Copy link',
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                              minWidth: 32, minHeight: 32),
                          onPressed: () {
                            Clipboard.setData(
                              ClipboardData(
                                text:
                                    '${Uri.base.origin}/f/${form.publicSlug}',
                              ),
                            );
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                  content: Text('Link copied to clipboard')),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 20),

                // Actions
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.icon(
                      onPressed: () =>
                          context.go('/forms/${form.id}/submissions'),
                      icon: const Icon(Icons.list_alt, size: 16),
                      label: Text(
                          'Submissions${_submissionCount > 0 ? ' ($_submissionCount)' : ''}'),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 10),
                      ),
                    ),
                    if (canManage)
                      OutlinedButton.icon(
                        onPressed: _togglingPublic ? null : _togglePublic,
                        icon: Icon(
                          form.isPublic ? Icons.lock_outline : Icons.public,
                          size: 16,
                        ),
                        label: Text(
                            form.isPublic ? 'Make Private' : 'Make Public'),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 10),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final String value;

  const _Stat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: Theme.of(context)
              .textTheme
              .headlineSmall
              ?.copyWith(fontWeight: FontWeight.bold),
        ),
        Text(
          label,
          style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
        ),
      ],
    );
  }
}
