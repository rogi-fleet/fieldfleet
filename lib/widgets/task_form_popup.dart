import 'package:flutter/material.dart';
import '../screens/tasks/task_form_screen.dart';
import 'common/form_popup_header.dart';
import 'common/unsaved_changes_guard.dart';
import '../theme/theme.dart';

/// Shows the task form as a popup overlay
void showTaskFormPopup(
  BuildContext context, {
  required String projectId,
  String? taskId,
  DateTime? initialStartDate,
  List<String>? initialAssignedUserIds,
  int? initialTabIndex,
}) {
  final isMobile = MediaQuery.of(context).size.width < AppBreakpoints.mobile;

  if (isMobile) {
    // Show as bottom sheet on mobile
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _TaskFormBottomSheet(
        projectId: projectId,
        taskId: taskId,
        initialStartDate: initialStartDate,
        initialAssignedUserIds: initialAssignedUserIds,
        initialTabIndex: initialTabIndex,
      ),
    );
  } else {
    // Show as dialog on desktop
    showDialog(
      context: context,
      builder: (context) => _TaskFormDialog(
        projectId: projectId,
        taskId: taskId,
        initialStartDate: initialStartDate,
        initialAssignedUserIds: initialAssignedUserIds,
        initialTabIndex: initialTabIndex,
      ),
    );
  }
}

/// Bottom sheet wrapper for mobile
class _TaskFormBottomSheet extends StatefulWidget {
  final String projectId;
  final String? taskId;
  final DateTime? initialStartDate;
  final List<String>? initialAssignedUserIds;
  final int? initialTabIndex;

  const _TaskFormBottomSheet({
    required this.projectId,
    this.taskId,
    this.initialStartDate,
    this.initialAssignedUserIds,
    this.initialTabIndex,
  });

  @override
  State<_TaskFormBottomSheet> createState() => _TaskFormBottomSheetState();
}

class _TaskFormBottomSheetState extends State<_TaskFormBottomSheet> {
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
        initialChildSize: 0.9,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (context, scrollController) {
          return Container(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Column(
              children: [
                // Header
                FormPopupHeader(
                  dense: true,
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(20)),
                  icon: widget.taskId == null ? Icons.add_task : Icons.edit,
                  title: widget.taskId == null ? 'Create New Task' : 'Edit Task',
                  onClose: () =>
                      maybeCloseForm(context, isDirty: _dirty.value),
                ),
                // Form content
                Expanded(
                  child: TaskFormContent(
                    projectId: widget.projectId,
                    taskId: widget.taskId,
                    isPopup: true,
                    initialStartDate: widget.initialStartDate,
                    initialAssignedUserIds: widget.initialAssignedUserIds,
                    initialTabIndex: widget.initialTabIndex,
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
class _TaskFormDialog extends StatefulWidget {
  final String projectId;
  final String? taskId;
  final DateTime? initialStartDate;
  final List<String>? initialAssignedUserIds;
  final int? initialTabIndex;

  const _TaskFormDialog({
    required this.projectId,
    this.taskId,
    this.initialStartDate,
    this.initialAssignedUserIds,
    this.initialTabIndex,
  });

  @override
  State<_TaskFormDialog> createState() => _TaskFormDialogState();
}

class _TaskFormDialogState extends State<_TaskFormDialog> {
  final _dirty = ValueNotifier<bool>(false);

  @override
  void dispose() {
    _dirty.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        await maybeCloseForm(context, isDirty: _dirty.value);
      },
      child: Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.r16)),
      child: Container(
        width: 600,
        height: MediaQuery.of(context).size.height * 0.95,
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.9,
          maxHeight: MediaQuery.of(context).size.height * 0.95,
        ),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(AppRadius.r16),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.r16),
          child: Column(
          children: [
            // Header
            FormPopupHeader(
              icon: widget.taskId == null ? Icons.add_task : Icons.edit,
              title: widget.taskId == null ? 'Create New Task' : 'Edit Task',
              onClose: () => maybeCloseForm(context, isDirty: _dirty.value),
            ),
            // Form content
            Expanded(
              child: TaskFormContent(
                projectId: widget.projectId,
                taskId: widget.taskId,
                isPopup: true,
                initialStartDate: widget.initialStartDate,
                initialAssignedUserIds: widget.initialAssignedUserIds,
                initialTabIndex: widget.initialTabIndex,
                dirtyNotifier: _dirty,
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
