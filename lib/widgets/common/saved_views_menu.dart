import 'package:flutter/material.dart';

import '../../theme/theme.dart';
import 'view_icon_button.dart';

/// Lightweight description of a saved view for the menu.
class SavedViewEntry {
  final String id;
  final String name;

  const SavedViewEntry({required this.id, required this.name});
}

/// Toolbar entry that opens a popup listing saved views, with apply/delete
/// affordances and a "Save current view…" action. Designed to slot into a
/// [ViewToolbar.quickToggles] list. Centralizes the saved-views UX so each
/// list screen wires identical behavior.
class SavedViewsMenu extends StatelessWidget {
  final List<SavedViewEntry> savedViews;
  final String? activeSavedViewId;
  final ValueChanged<String> onApplyView;
  final ValueChanged<String> onDeleteView;
  final VoidCallback onSaveCurrentView;

  /// Disables the "Save current view…" action when no filters/sort are set —
  /// a default-state save would yield a meaningless entry.
  final bool canSaveCurrent;

  const SavedViewsMenu({
    super.key,
    required this.savedViews,
    required this.activeSavedViewId,
    required this.onApplyView,
    required this.onDeleteView,
    required this.onSaveCurrentView,
    this.canSaveCurrent = true,
  });

  @override
  Widget build(BuildContext context) {
    final hasActive = activeSavedViewId != null;
    return ViewIconButton(
      icon: hasActive ? Icons.bookmark : Icons.bookmark_border,
      tooltip: 'Saved views',
      isSelected: hasActive,
      onTap: () => _open(context),
    );
  }

  Future<void> _open(BuildContext context) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => _SavedViewsDialog(
        savedViews: savedViews,
        activeSavedViewId: activeSavedViewId,
        canSaveCurrent: canSaveCurrent,
        onApplyView: (id) {
          Navigator.of(ctx).pop();
          onApplyView(id);
        },
        onDeleteView: onDeleteView,
        onSaveCurrentView: () {
          Navigator.of(ctx).pop();
          onSaveCurrentView();
        },
      ),
    );
  }
}

class _SavedViewsDialog extends StatefulWidget {
  final List<SavedViewEntry> savedViews;
  final String? activeSavedViewId;
  final bool canSaveCurrent;
  final ValueChanged<String> onApplyView;
  final ValueChanged<String> onDeleteView;
  final VoidCallback onSaveCurrentView;

  const _SavedViewsDialog({
    required this.savedViews,
    required this.activeSavedViewId,
    required this.canSaveCurrent,
    required this.onApplyView,
    required this.onDeleteView,
    required this.onSaveCurrentView,
  });

  @override
  State<_SavedViewsDialog> createState() => _SavedViewsDialogState();
}

class _SavedViewsDialogState extends State<_SavedViewsDialog> {
  late List<SavedViewEntry> _views;

  @override
  void initState() {
    super.initState();
    _views = List.of(widget.savedViews);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.r16)),
      insetPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl, vertical: 40),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420, maxHeight: 480),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 0),
              child: Row(
                children: [
                  const Icon(
                    Icons.bookmark_outline,
                    size: 20,
                    color: AppColors.textSecondary,
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'Saved views',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: () => Navigator.of(context).pop(),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: _views.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(AppSpacing.xl),
                      child: Text(
                        'No saved views yet. Apply some filters or sorting, '
                        'then tap "Save current view" to create one.',
                        style: TextStyle(
                          fontSize: 13,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                      itemCount: _views.length,
                      itemBuilder: (context, index) {
                        final view = _views[index];
                        final isActive = view.id == widget.activeSavedViewId;
                        return ListTile(
                          leading: Icon(
                            isActive
                                ? Icons.bookmark
                                : Icons.bookmark_border,
                            color: isActive
                                ? AppColors.primary
                                : AppColors.textTertiary,
                          ),
                          title: Text(
                            view.name,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: isActive
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                              color: isActive ? AppColors.primary : null,
                            ),
                          ),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete_outline, size: 18),
                            color: AppColors.textTertiary,
                            onPressed: () {
                              widget.onDeleteView(view.id);
                              setState(() => _views.removeAt(index));
                            },
                          ),
                          onTap: () => widget.onApplyView(view.id),
                        );
                      },
                    ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.base, vertical: AppSpacing.md),
              child: Row(
                children: [
                  TextButton.icon(
                    onPressed: widget.canSaveCurrent
                        ? widget.onSaveCurrentView
                        : null,
                    icon: const Icon(Icons.bookmark_add_outlined, size: 18),
                    label: const Text('Save current view'),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Close'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Helper to prompt the user for a name for a new saved view. Returns the
/// trimmed name, or null if cancelled / empty.
Future<String?> promptSavedViewName(
  BuildContext context, {
  String hintText = 'e.g. My active jobs',
}) async {
  final controller = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Save current view'),
      content: TextField(
        controller: controller,
        autofocus: true,
        decoration: InputDecoration(hintText: hintText),
        onSubmitted: (value) {
          final trimmed = value.trim();
          if (trimmed.isNotEmpty) {
            Navigator.of(context).pop(trimmed);
          }
        },
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            final trimmed = controller.text.trim();
            if (trimmed.isEmpty) return;
            Navigator.of(context).pop(trimmed);
          },
          child: const Text('Save'),
        ),
      ],
    ),
  );
}
