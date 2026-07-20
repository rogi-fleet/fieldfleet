import 'package:flutter/material.dart';
import '../../../theme/theme.dart';
import '../../../models/project.dart';
import '../../../models/task.dart';
import '../../../models/budget_item.dart';
import '../../../widgets/forms/stacked_field.dart';
import '../../../widgets/projects/project_picker_tile.dart';

/// Shared picker bottom-sheets and UI helpers used by both the Clock-In screen
/// and the TimeEntryQuickForm widget.
class TimeTrackingPickers {
  TimeTrackingPickers._();

  // ── dropdown popup (desktop) ──────────────────────────────────────────

  /// Shows a dropdown popup anchored below [anchorContext]'s render box.
  static Future<T?> _showDropdownPicker<T>({
    required BuildContext context,
    required BuildContext anchorContext,
    required int itemCount,
    required Widget Function(BuildContext context, int index) itemBuilder,
  }) {
    final renderBox = anchorContext.findRenderObject() as RenderBox;
    final buttonPos = renderBox.localToGlobal(Offset.zero);
    final buttonSize = renderBox.size;
    final screenSize = MediaQuery.of(context).size;

    // Position below the button, capped to screen bounds.
    final top = buttonPos.dy + buttonSize.height + 4;
    final left = buttonPos.dx;
    final maxHeight = (screenSize.height - top - 24).clamp(200.0, 420.0);
    final width = buttonSize.width.clamp(280.0, 600.0);

    return showDialog<T>(
      context: context,
      barrierColor: Colors.black12,
      builder: (dialogContext) {
        return Stack(
          children: [
            Positioned(
              left: left,
              top: top,
              width: width,
              child: Material(
                elevation: 8,
                borderRadius: BorderRadius.circular(AppRadius.r16),
                clipBehavior: Clip.antiAlias,
                color: AppColors.surface,
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: maxHeight),
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                    shrinkWrap: true,
                    itemCount: itemCount,
                    itemBuilder: (ctx, i) => itemBuilder(dialogContext, i),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  // ── selection button ──────────────────────────────────────────────────

  /// A tile-style button that opens a bottom-sheet picker.
  static Widget selectionButton({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback? onTap,
  }) {
    final titleColor =
        onTap == null ? AppColors.textTertiary : AppColors.textPrimary;
    return InkWell(
      borderRadius: BorderRadius.circular(AppRadius.r16),
      onTap: onTap,
      child: Ink(
        padding: const EdgeInsets.all(AppSpacing.base),
        decoration: BoxDecoration(
          color: onTap == null ? AppColors.surfaceAlt : AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.r16),
          border: Border.all(color: AppColors.cardBorder),
        ),
        child: Row(
          children: [
            Icon(icon, color: AppColors.primaryDark),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: titleColor,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Icon(
              onTap == null ? Icons.block : Icons.expand_more,
              color: AppColors.textSecondary,
            ),
          ],
        ),
      ),
    );
  }

  /// A muted hint row shown when a picker has no items.
  static Widget emptyFieldHint({
    required IconData icon,
    required String text,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(AppRadius.r16),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Row(
        children: [
          Icon(icon, color: AppColors.textSecondary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── project picker ────────────────────────────────────────────────────

  /// Opens a picker listing [projects]. On wide screens the picker drops
  /// down from [anchorContext]; on narrow screens it slides up as a bottom
  /// sheet.
  static Future<Project?> showProjectPicker({
    required BuildContext context,
    required List<Project> projects,
    required String? currentProjectId,
    required String singularTermLower,
    BuildContext? anchorContext,
  }) {
    final isWide = MediaQuery.of(context).size.width >= 720;

    if (isWide && anchorContext != null) {
      return _showDropdownPicker<Project>(
        context: context,
        anchorContext: anchorContext,
        itemCount: projects.length + 1, // +1 for header
        itemBuilder: (dialogContext, index) {
          if (index == 0) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
              child: Text(
                'Select $singularTermLower',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            );
          }
          final project = projects[index - 1];
          return ProjectPickerTile(
            project: project,
            isCurrent: project.id == currentProjectId,
            onTap: () => Navigator.of(dialogContext).pop(project),
          );
        },
      );
    }

    return showModalBottomSheet<Project>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 24),
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                child: Text(
                  'Select $singularTermLower',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              ...projects.map((project) {
                return ProjectPickerTile(
                  project: project,
                  isCurrent: project.id == currentProjectId,
                  onTap: () => Navigator.of(context).pop(project),
                );
              }),
            ],
          ),
        );
      },
    );
  }

  // ── task picker ───────────────────────────────────────────────────────

  /// Opens a bottom sheet listing [tasks] (plus a "No specific task" option)
  /// and returns the selected one, or `null` for no task.
  static Future<Task?> showTaskPicker({
    required BuildContext context,
    required List<Task> tasks,
    required String? currentTaskId,
    required String singularTermLower,
  }) {
    return showModalBottomSheet<Task?>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            children: [
              const Text(
                'Select task',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  currentTaskId == null
                      ? Icons.check_circle
                      : Icons.layers_clear_outlined,
                  color: currentTaskId == null
                      ? AppColors.successDark
                      : AppColors.primaryDark,
                ),
                title: const Text('No specific task'),
                subtitle: Text(
                  'Track time at the $singularTermLower level',
                ),
                onTap: () => Navigator.of(context).pop(null),
              ),
              ...tasks.map((task) {
                final isSelected = task.id == currentTaskId;
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    isSelected ? Icons.check_circle : Icons.task_alt_outlined,
                    color: isSelected
                        ? AppColors.successDark
                        : AppColors.primaryDark,
                  ),
                  title: Text(task.title),
                  trailing: isSelected
                      ? const Icon(Icons.check, color: AppColors.successDark)
                      : null,
                  onTap: () => Navigator.of(context).pop(task),
                );
              }),
            ],
          ),
        );
      },
    );
  }

  // ── budget-item picker ────────────────────────────────────────────────

  /// Opens a bottom sheet listing [items] (plus an "Uncategorized labor"
  /// option) and returns the selected one, or `null` for uncategorized.
  static Future<BudgetItem?> showBudgetItemPicker({
    required BuildContext context,
    required List<BudgetItem> items,
    required String? currentBudgetItemId,
  }) {
    return showModalBottomSheet<BudgetItem?>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            children: [
              const Text(
                'Select budget item',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  currentBudgetItemId == null
                      ? Icons.check_circle
                      : Icons.layers_clear_outlined,
                  color: currentBudgetItemId == null
                      ? AppColors.successDark
                      : AppColors.primaryDark,
                ),
                title: const Text('Uncategorized labor'),
                subtitle: const Text('Auto-assigned default bucket'),
                onTap: () => Navigator.of(context).pop(null),
              ),
              ...items.map((item) {
                final isSelected = item.id == currentBudgetItemId;
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    isSelected
                        ? Icons.check_circle
                        : Icons.account_balance_wallet_outlined,
                    color: isSelected
                        ? AppColors.successDark
                        : item.costType?.color ?? AppColors.primaryDark,
                  ),
                  title: Text(item.name),
                  subtitle: item.costType != null
                      ? Text(item.costType!.displayLabel)
                      : null,
                  trailing: isSelected
                      ? const Icon(Icons.check, color: AppColors.successDark)
                      : null,
                  onTap: () => Navigator.of(context).pop(item),
                );
              }),
            ],
          ),
        );
      },
    );
  }

  // ── StreamBuilder field builders ──────────────────────────────────────

  /// Builds a project selector field backed by a stream.
  static Widget projectField({
    required Stream<List<Project>> stream,
    required String? selectedProjectId,
    required String singularTerm,
    required String singularTermLower,
    required String pluralTerm,
    required ValueChanged<Project> onSelected,
  }) {
    return StreamBuilder<List<Project>>(
      stream: stream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const LinearProgressIndicator();
        }
        final projects = snapshot.data ?? [];
        final activeProjects =
            projects.where((p) => !p.status.isClosed).toList();
        final selected = activeProjects
            .where((p) => p.id == selectedProjectId)
            .firstOrNull;

        String subtitle;
        if (selected != null) {
          final parts = <String>[];
          final serial = selected.serialNumber?.trim();
          if (serial != null && serial.isNotEmpty) parts.add('#$serial');
          if (selected.customerName != null &&
              selected.customerName!.isNotEmpty) {
            parts.add(selected.customerName!);
          }
          if (selected.address.isNotEmpty) parts.add(selected.address);
          subtitle = parts.isEmpty ? singularTerm : parts.join(' · ');
        } else {
          subtitle = activeProjects.isEmpty
              ? 'No active ${pluralTerm.toLowerCase()} available'
              : '${activeProjects.length} active ${pluralTerm.toLowerCase()}';
        }

        return StackedField(
          label: '$singularTerm *',
          child: Builder(
            builder: (buttonContext) {
              return selectionButton(
                icon: Icons.folder_outlined,
                title: selected?.name ?? 'Choose $singularTermLower',
                subtitle: subtitle,
                onTap: activeProjects.isEmpty
                    ? null
                    : () async {
                        final picked = await showProjectPicker(
                          context: context,
                          projects: activeProjects,
                          currentProjectId: selectedProjectId,
                          singularTermLower: singularTermLower,
                          anchorContext: buttonContext,
                        );
                        if (picked != null) onSelected(picked);
                      },
              );
            },
          ),
        );
      },
    );
  }

  /// Builds a task selector field backed by a stream.
  static Widget taskField({
    required Stream<List<Task>> stream,
    required String? selectedTaskId,
    required String singularTermLower,
    required ValueChanged<Task?> onSelected,
  }) {
    return StreamBuilder<List<Task>>(
      stream: stream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const SizedBox.shrink();
        }

        final tasks = snapshot.data ?? [];
        final incompleteTasks = tasks.where((t) => !t.isComplete).toList();

        if (incompleteTasks.isEmpty) {
          return emptyFieldHint(
            icon: Icons.task_alt,
            text:
                'No open tasks for this $singularTermLower. You can still add time at the $singularTermLower level.',
          );
        }

        final selected = incompleteTasks
            .where((t) => t.id == selectedTaskId)
            .firstOrNull;

        return StackedField(
          label: 'Task (optional)',
          child: selectionButton(
            icon: Icons.task_alt_outlined,
            title: selected?.title ?? 'Add task (optional)',
            subtitle: selected == null
                ? 'Track time to the $singularTermLower or choose a task'
                : 'Optional detail for reporting',
            onTap: () async {
              final picked = await showTaskPicker(
                context: context,
                tasks: incompleteTasks,
                currentTaskId: selectedTaskId,
                singularTermLower: singularTermLower,
              );
              onSelected(picked);
            },
          ),
        );
      },
    );
  }

  /// Builds a budget-item selector field backed by a stream.
  static Widget budgetItemField({
    required Stream<List<BudgetItem>> stream,
    required String? selectedBudgetItemId,
    required String singularTermLower,
    required ValueChanged<BudgetItem?> onSelected,
  }) {
    return StreamBuilder<List<BudgetItem>>(
      stream: stream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const SizedBox.shrink();
        }

        final allItems = snapshot.data ?? [];
        final selectableItems = allItems
            .where((item) =>
                item.itemType == BudgetItemType.item &&
                item.name != 'Uncategorized Labor')
            .toList();

        if (selectableItems.isEmpty) {
          return emptyFieldHint(
            icon: Icons.account_balance_wallet_outlined,
            text:
                'No budget items for this $singularTermLower. Time will be tracked as uncategorized labor.',
          );
        }

        final selected = selectableItems
            .where((i) => i.id == selectedBudgetItemId)
            .firstOrNull;

        return StackedField(
          label: 'Budget item (optional)',
          child: selectionButton(
            icon: Icons.account_balance_wallet_outlined,
            title: selected?.name ?? 'Uncategorized labor',
            subtitle: selected == null
                ? 'Choose a budget item or leave as uncategorized'
                : selected.costType?.displayLabel ?? 'Budget item',
            onTap: () async {
              final picked = await showBudgetItemPicker(
                context: context,
                items: selectableItems,
                currentBudgetItemId: selectedBudgetItemId,
              );
              onSelected(picked);
            },
          ),
        );
      },
    );
  }
}
