import 'package:flutter/material.dart';

import '../../../models/widget_grid_layout.dart';
import '../../../theme/theme.dart';
import '../dashboard_edit_controller.dart';

/// Shared edit-mode toolbar actions for the v3 grid: Undo, breakpoint preview
/// picker, save status, and Done. Embedded by both home and project-overview
/// toolbars so the editing UX is consistent.
class EditToolbarActions extends StatelessWidget {
  final DashboardEditController controller;
  final VoidCallback? onDone;
  final VoidCallback onManage;
  final VoidCallback onReset;

  const EditToolbarActions({
    super.key,
    required this.controller,
    this.onDone,
    required this.onManage,
    required this.onReset,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _BreakpointPicker(controller: controller),
        OutlinedButton.icon(
          onPressed: controller.canUndo ? controller.undo : null,
          icon: const Icon(Icons.undo, size: 16),
          label: const Text('Undo'),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: AppSpacing.xs),
            textStyle: const TextStyle(fontSize: 12),
          ),
        ),
        Tooltip(
          message: 'Show or hide widgets',
          child: OutlinedButton.icon(
            onPressed: onManage,
            icon: const Icon(Icons.widgets_outlined, size: 16),
            // Surfacing the hidden count answers "where did my card go?"
            // without opening the sheet.
            label: Text(
              controller.hiddenWidgets.isEmpty
                  ? 'Widgets'
                  : 'Widgets · ${controller.hiddenWidgets.length} hidden',
            ),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(
                  horizontal: 10, vertical: AppSpacing.xs),
              textStyle: const TextStyle(fontSize: 12),
            ),
          ),
        ),
        OutlinedButton.icon(
          onPressed: onReset,
          icon: const Icon(Icons.restore, size: 16),
          label: const Text('Reset'),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: AppSpacing.xs),
            textStyle: const TextStyle(fontSize: 12),
          ),
        ),
        if (onDone != null)
          FilledButton.icon(
            onPressed: controller.saving ? null : onDone,
            icon: controller.saving
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation(Colors.white),
                    ),
                  )
                : const Icon(Icons.check, size: 16),
            label: Text(controller.saving ? 'Saving…' : 'Done'),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: AppSpacing.xs),
              textStyle: const TextStyle(fontSize: 12),
            ),
          )
        else if (controller.saving)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 6),
            child: SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
      ],
    );
  }
}

class _BreakpointPicker extends StatelessWidget {
  final DashboardEditController controller;

  const _BreakpointPicker({required this.controller});

  @override
  Widget build(BuildContext context) {
    final isPreviewing = controller.previewBreakpoint != null;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        PopupMenuButton<GridBreakpoint?>(
          tooltip: 'Preview at size',
          onSelected: controller.setPreviewBreakpoint,
          itemBuilder: (context) => [
            const PopupMenuItem<GridBreakpoint?>(
              value: null,
              child: ListTile(
                dense: true,
                leading: Icon(Icons.devices, size: 18),
                title: Text('Auto (current size)'),
              ),
            ),
            const PopupMenuItem<GridBreakpoint?>(
              value: GridBreakpoint.mobile,
              child: ListTile(
                dense: true,
                leading: Icon(Icons.smartphone, size: 18),
                title: Text('Mobile (4 cols)'),
              ),
            ),
            const PopupMenuItem<GridBreakpoint?>(
              value: GridBreakpoint.tablet,
              child: ListTile(
                dense: true,
                leading: Icon(Icons.tablet_mac, size: 18),
                title: Text('Tablet (8 cols)'),
              ),
            ),
            const PopupMenuItem<GridBreakpoint?>(
              value: GridBreakpoint.desktop,
              child: ListTile(
                dense: true,
                leading: Icon(Icons.desktop_windows, size: 18),
                title: Text('Desktop (12 cols)'),
              ),
            ),
          ],
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              border: Border.all(
                color: isPreviewing
                    ? AppColors.primary
                    : AppColors.cardBorder,
              ),
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(8),
                bottomLeft: const Radius.circular(8),
                topRight: Radius.circular(isPreviewing ? 0 : 8),
                bottomRight: Radius.circular(isPreviewing ? 0 : 8),
              ),
              color: isPreviewing
                  ? AppColors.primary.withValues(alpha: 0.08)
                  : null,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _iconFor(controller.previewBreakpoint),
                  size: 14,
                  color: isPreviewing ? AppColors.primary : null,
                ),
                const SizedBox(width: 6),
                Text(
                  _labelFor(controller.previewBreakpoint),
                  style: TextStyle(
                    fontSize: 12,
                    color: isPreviewing ? AppColors.primary : null,
                    fontWeight:
                        isPreviewing ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
                const Icon(Icons.arrow_drop_down, size: 16),
              ],
            ),
          ),
        ),
        if (isPreviewing)
          Tooltip(
            message: 'Exit preview',
            child: InkWell(
              onTap: () => controller.setPreviewBreakpoint(null),
              borderRadius: const BorderRadius.only(
                topRight: Radius.circular(8),
                bottomRight: Radius.circular(8),
              ),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  border: Border(
                    top: BorderSide(color: AppColors.primary),
                    right: BorderSide(color: AppColors.primary),
                    bottom: BorderSide(color: AppColors.primary),
                  ),
                  borderRadius: const BorderRadius.only(
                    topRight: Radius.circular(8),
                    bottomRight: Radius.circular(8),
                  ),
                  color: AppColors.primary.withValues(alpha: 0.08),
                ),
                child: Icon(
                  Icons.close,
                  size: 14,
                  color: AppColors.primary,
                ),
              ),
            ),
          ),
      ],
    );
  }

  IconData _iconFor(GridBreakpoint? bp) {
    switch (bp) {
      case GridBreakpoint.mobile:
        return Icons.smartphone;
      case GridBreakpoint.tablet:
        return Icons.tablet_mac;
      case GridBreakpoint.desktop:
        return Icons.desktop_windows;
      case null:
        return Icons.devices;
    }
  }

  String _labelFor(GridBreakpoint? bp) {
    switch (bp) {
      case GridBreakpoint.mobile:
        return 'Mobile';
      case GridBreakpoint.tablet:
        return 'Tablet';
      case GridBreakpoint.desktop:
        return 'Desktop';
      case null:
        return 'Auto';
    }
  }
}

/// Helper that surfaces save errors as a SnackBar after the current frame.
/// Safe to call from a build method — it post-frames the SnackBar and clears
/// the controller's error so it doesn't re-fire on the next rebuild.
void showSaveErrorIfAny(BuildContext context, DashboardEditController c) {
  final err = c.saveError;
  if (err == null) return;
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!context.mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        content: Text('Failed to save dashboard: $err'),
        backgroundColor: AppColors.error,
        duration: const Duration(seconds: 4),
      ),
    );
    c.clearSaveError();
  });
}
