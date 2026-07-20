import 'package:flutter/material.dart';
import 'package:taskfleet_ops/utils/user_facing_error.dart';
import '../services/service_locator.dart';

import 'package:taskfleet_ops/widgets/forms/stacked_field.dart';
import 'common/form_popup_header.dart';
import 'package:taskfleet_ops/widgets/common/form_popup_footer.dart';
import 'common/unsaved_changes_guard.dart';
import '../theme/theme.dart';

/// Shows the group form as a popup overlay
void showGroupFormPopup(
  BuildContext context, {
  required String projectId,
  required String groupId,
}) {
  final isMobile = MediaQuery.of(context).size.width < AppBreakpoints.mobile;

  if (isMobile) {
    // Show as bottom sheet on mobile
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) =>
          _GroupFormBottomSheet(projectId: projectId, groupId: groupId),
    );
  } else {
    // Show as dialog on desktop
    showDialog(
      context: context,
      builder: (context) =>
          _GroupFormDialog(projectId: projectId, groupId: groupId),
    );
  }
}

/// Bottom sheet wrapper for mobile
class _GroupFormBottomSheet extends StatefulWidget {
  final String projectId;
  final String groupId;

  const _GroupFormBottomSheet({required this.projectId, required this.groupId});

  @override
  State<_GroupFormBottomSheet> createState() => _GroupFormBottomSheetState();
}

class _GroupFormBottomSheetState extends State<_GroupFormBottomSheet> {
  final _dirty = ValueNotifier<bool>(false);

  @override
  void dispose() {
    _dirty.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        await maybeCloseForm(context, isDirty: _dirty.value);
      },
      child: DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.4,
        maxChildSize: 0.9,
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
                // Header
                FormPopupHeader(
                  dense: true,
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(20)),
                  icon: Icons.folder_outlined,
                  title: 'Edit Phase',
                  onClose: () =>
                      maybeCloseForm(context, isDirty: _dirty.value),
                ),
                // Form content
                Expanded(
                  child: _GroupFormContent(
                    projectId: widget.projectId,
                    groupId: widget.groupId,
                    dirtyNotifier: _dirty,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Dialog wrapper for desktop
class _GroupFormDialog extends StatefulWidget {
  final String projectId;
  final String groupId;

  const _GroupFormDialog({required this.projectId, required this.groupId});

  @override
  State<_GroupFormDialog> createState() => _GroupFormDialogState();
}

class _GroupFormDialogState extends State<_GroupFormDialog> {
  final _dirty = ValueNotifier<bool>(false);

  @override
  void dispose() {
    _dirty.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        await maybeCloseForm(context, isDirty: _dirty.value);
      },
      child: Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.r16)),
        clipBehavior: Clip.antiAlias,
        child: Container(
          width: 500,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
          ),
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.9,
            maxHeight: MediaQuery.of(context).size.height * 0.7,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              FormPopupHeader(
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(16)),
                icon: Icons.folder_outlined,
                title: 'Edit Phase',
                onClose: () =>
                    maybeCloseForm(context, isDirty: _dirty.value),
              ),
              // Form content
              Expanded(
                child: _GroupFormContent(
                  projectId: widget.projectId,
                  groupId: widget.groupId,
                  dirtyNotifier: _dirty,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Simplified group form content - only editable group properties
class _GroupFormContent extends StatefulWidget {
  final String projectId;
  final String groupId;
  final ValueNotifier<bool>? dirtyNotifier;

  const _GroupFormContent({
    required this.projectId,
    required this.groupId,
    this.dirtyNotifier,
  });

  @override
  State<_GroupFormContent> createState() => _GroupFormContentState();
}

class _GroupFormContentState extends State<_GroupFormContent> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();

  bool _isLoading = true;
  bool _isSaving = false;
  Color _selectedColor = AppColors.categoryPalette.first;
  String _selectedStatus = 'not_started';
  String _selectedPriority = 'medium';
  bool _initialLoadComplete = false;

  static const List<Color> _colorOptions = AppColors.categoryPalette;

  final List<String> _statusOptions = [
    'not_started',
    'working_on_it',
    'stuck',
    'done',
  ];

  final List<String> _priorityOptions = ['low', 'medium', 'high'];

  @override
  void initState() {
    super.initState();
    _titleController.addListener(_markDirty);
    _descriptionController.addListener(_markDirty);
    _loadGroup();
  }

  void _markDirty() {
    if (_initialLoadComplete) {
      widget.dirtyNotifier?.value = true;
    }
  }

  Future<void> _loadGroup() async {
    try {
      final group = await ServiceLocator.taskService.getTask(widget.groupId);
      if (group != null && mounted) {
        setState(() {
          _titleController.text = group.title;
          _descriptionController.text = group.description ?? '';
          _selectedColor = group.groupColor;
          _selectedStatus = _normalizeStatus(group.status);
          _selectedPriority = _normalizePriority(group.priority);
          _isLoading = false;
          _initialLoadComplete = true;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              UserFacingError.uiMessage(e, action: 'loading phase'),
            ),
          ),
        );
      }
    }
  }

  Future<void> _saveGroup() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    try {
      await ServiceLocator.taskService.updateTask(
        taskId: widget.groupId,
        title: _titleController.text.trim(),
        description: _descriptionController.text.trim().isEmpty
            ? null
            : _descriptionController.text.trim(),
        groupColor: _selectedColor,
        status: _selectedStatus,
        priority: _selectedPriority,
      );

      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(UserFacingError.uiMessage(e, action: 'saving phase')),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  /// Normalize status value to match dropdown options
  String _normalizeStatus(String status) {
    switch (status.toLowerCase().replaceAll(' ', '_')) {
      case 'not_started':
      case 'notstarted':
        return 'not_started';
      case 'working_on_it':
      case 'workingonit':
      case 'in_progress':
        return 'working_on_it';
      case 'stuck':
      case 'blocked':
        return 'stuck';
      case 'done':
      case 'complete':
      case 'completed':
        return 'done';
      default:
        return 'not_started';
    }
  }

  /// Normalize priority value to match dropdown options
  String _normalizePriority(String priority) {
    switch (priority.toLowerCase()) {
      case 'low':
        return 'low';
      case 'medium':
      case 'normal':
        return 'medium';
      case 'high':
      case 'critical':
        return 'high';
      default:
        return 'medium';
    }
  }

  @override
  void dispose() {
    _titleController.removeListener(_markDirty);
    _descriptionController.removeListener(_markDirty);
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Form(
      key: _formKey,
      child: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AppSpacing.base),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
            // Title
            StackedField(
              label: 'Phase Name',
              child: TextFormField(
                controller: _titleController,
                decoration: const InputDecoration(border: OutlineInputBorder()),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter a phase name';
                  }
                  return null;
                },
              ),
            ),
            const SizedBox(height: 16),

            // Description
            StackedField(
              label: 'Description (optional)',
              child: TextFormField(
                controller: _descriptionController,
                decoration: const InputDecoration(border: OutlineInputBorder()),
                maxLines: 3,
              ),
            ),
            const SizedBox(height: 24),

            // Group Color
            Text('Phase Color', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _colorOptions.map((color) {
                final isSelected =
                    _selectedColor.toARGB32() == color.toARGB32();
                return InkWell(
                  onTap: () {
                    _markDirty();
                    setState(() => _selectedColor = color);
                  },
                  borderRadius: BorderRadius.circular(AppRadius.xl),
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                      border: isSelected
                          ? Border.all(color: Colors.black, width: 3)
                          : null,
                    ),
                    child: isSelected
                        ? const Icon(Icons.check, color: Colors.white, size: 20)
                        : null,
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 24),

            // Status
            StackedField(
              label: 'Status',
              child: DropdownButtonFormField<String>(
                borderRadius: AppRadius.cardRadius,
                initialValue: _selectedStatus,
                decoration: const InputDecoration(border: OutlineInputBorder()),
                items: _statusOptions.map((status) {
                  return DropdownMenuItem(value: status, child: Text(status));
                }).toList(),
                onChanged: (value) {
                  if (value != null) {
                    _markDirty();
                    setState(() => _selectedStatus = value);
                  }
                },
              ),
            ),
            const SizedBox(height: 16),

            // Priority
            StackedField(
              label: 'Priority',
              child: DropdownButtonFormField<String>(
                borderRadius: AppRadius.cardRadius,
                initialValue: _selectedPriority,
                decoration: const InputDecoration(border: OutlineInputBorder()),
                items: _priorityOptions.map((priority) {
                  return DropdownMenuItem(
                    value: priority,
                    child: Text(priority),
                  );
                }).toList(),
                onChanged: (value) {
                  if (value != null) {
                    _markDirty();
                    setState(() => _selectedPriority = value);
                  }
                },
              ),
            ),
            const SizedBox(height: 24),

            // Info note about calculated values
            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: Colors.blue.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(AppRadius.sm),
                border: Border.all(color: Colors.blue.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.blue[700], size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Dates and progress are automatically calculated from child tasks.',
                      style: TextStyle(color: Colors.blue[700], fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
                ],
              ),
            ),
          ),
          FormPopupFooter(
            onSubmit: _isSaving ? null : _saveGroup,
            submitLabel: 'Save Phase',
            busy: _isSaving,
          ),
        ],
      ),
    );
  }
}
