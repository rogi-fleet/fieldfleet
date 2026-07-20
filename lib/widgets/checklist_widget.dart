import 'package:flutter/material.dart';
import 'package:taskfleet_ops/utils/user_facing_error.dart';
import '../theme/theme.dart';
import '../models/checklist_item.dart';
import '../models/task.dart';
import '../services/service_locator.dart';
import 'completion_celebration.dart';
import '../utils/text_selection_utils.dart';

/// Widget for displaying and editing a task's checklist items
class ChecklistWidget extends StatefulWidget {
  final Task task;
  final bool isEditable;
  final VoidCallback? onChanged;

  const ChecklistWidget({
    super.key,
    required this.task,
    this.isEditable = true,
    this.onChanged,
  });

  @override
  State<ChecklistWidget> createState() => _ChecklistWidgetState();
}

class _ChecklistWidgetState extends State<ChecklistWidget> {
  final _taskService = ServiceLocator.taskService;
  final _newItemController = TextEditingController();
  final _newItemFocusNode = FocusNode();
  bool _isAddingItem = false;

  @override
  void dispose() {
    _newItemController.dispose();
    _newItemFocusNode.dispose();
    super.dispose();
  }

  Future<void> _addItem() async {
    final title = _newItemController.text.trim();
    if (title.isEmpty) return;

    try {
      await _taskService.addChecklistItem(widget.task.id, title);
      _newItemController.clear();
      setState(() {
        _isAddingItem = false;
      });
      widget.onChanged?.call();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              UserFacingError.uiMessage(e, action: 'adding checklist item'),
            ),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Future<void> _toggleItem(String itemId) async {
    try {
      // Find the item being toggled
      final item = widget.task.checklistItems.firstWhere((i) => i.id == itemId);
      final wasComplete = item.isComplete;
      final totalItems = widget.task.checklistItems.length;
      final completedCount = widget.task.completedChecklistCount;

      await _taskService.toggleChecklistItemComplete(widget.task.id, itemId);
      widget.onChanged?.call();

      // Check if we just completed the last item
      if (!wasComplete && // Wasn't complete before (now it is)
          completedCount + 1 >= totalItems && // All items now complete
          mounted) {
        // Show celebration animation
        showCelebration(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              UserFacingError.uiMessage(e, action: 'toggling item'),
            ),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Future<void> _deleteItem(String itemId) async {
    try {
      await _taskService.deleteChecklistItem(widget.task.id, itemId);
      widget.onChanged?.call();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              UserFacingError.uiMessage(e, action: 'deleting item'),
            ),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Future<void> _updateItemTitle(String itemId, String newTitle) async {
    if (newTitle.trim().isEmpty) return;
    try {
      await _taskService.updateChecklistItem(
        widget.task.id,
        itemId,
        title: newTitle.trim(),
      );
      widget.onChanged?.call();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              UserFacingError.uiMessage(e, action: 'updating item'),
            ),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final items = widget.task.checklistItems;
    final completedCount = widget.task.completedChecklistCount;
    final totalCount = widget.task.totalChecklistCount;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Header with progress
        if (items.isNotEmpty) ...[
          Row(
            children: [
              Text(
                'Progress: $completedCount/$totalCount',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadius.xs),
                  child: LinearProgressIndicator(
                    value: totalCount > 0 ? completedCount / totalCount : 0,
                    backgroundColor: AppColors.cardBorder,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      completedCount == totalCount && totalCount > 0
                          ? AppColors.success
                          : theme.colorScheme.primary,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
        ],

        // Checklist items
        ReorderableListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: items.length,
          onReorder: (oldIndex, newIndex) async {
            if (!widget.isEditable) return;
            if (newIndex > oldIndex) newIndex--;

            final reordered = List<ChecklistItem>.from(items);
            final item = reordered.removeAt(oldIndex);
            reordered.insert(newIndex, item);

            try {
              await _taskService.reorderChecklistItems(
                widget.task.id,
                reordered,
              );
              widget.onChanged?.call();
            } catch (e) {
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      UserFacingError.uiMessage(e, action: 'reordering items'),
                    ),
                    backgroundColor: AppColors.error,
                  ),
                );
              }
            }
          },
          itemBuilder: (context, index) {
            final item = items[index];
            return ChecklistItemTile(
              key: ValueKey(item.id),
              item: item,
              index: index,
              isEditable: widget.isEditable,
              onToggle: () => _toggleItem(item.id),
              onDelete: () => _deleteItem(item.id),
              onTitleChanged: (newTitle) => _updateItemTitle(item.id, newTitle),
            );
          },
        ),

        // Add new item section
        if (widget.isEditable) ...[
          const SizedBox(height: 8),
          if (_isAddingItem) _buildAddItemInput() else _buildAddItemButton(),
        ],
      ],
    );
  }

  Widget _buildAddItemButton() {
    return InkWell(
      onTap: () {
        setState(() {
          _isAddingItem = true;
        });
        Future.delayed(const Duration(milliseconds: 100), () {
          _newItemFocusNode.requestFocus();
        });
      },
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 10),
        child: Row(
          children: [
            Icon(
              Icons.add,
              size: 18,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(width: 8),
            Text(
              'Add item',
              style: TextStyle(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAddItemInput() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Row(
        children: [
          Icon(
            Icons.check_box_outline_blank,
            size: 20,
            color: AppColors.textTertiary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _newItemController,
              focusNode: _newItemFocusNode,
              style: const TextStyle(fontSize: 14),
              decoration: const InputDecoration(
                hintText: 'Add a checklist item...',
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.symmetric(vertical: AppSpacing.sm),
              ),
              onSubmitted: (_) => _addItem(),
            ),
          ),
          IconButton(
            icon: Icon(
              Icons.check,
              color: Theme.of(context).colorScheme.primary,
            ),
            onPressed: _addItem,
            iconSize: 20,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: Icon(Icons.close, color: AppColors.textTertiary),
            onPressed: () {
              setState(() {
                _isAddingItem = false;
                _newItemController.clear();
              });
            },
            iconSize: 20,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }
}

/// Individual checklist item tile
class ChecklistItemTile extends StatefulWidget {
  final ChecklistItem item;
  final int index;
  final bool isEditable;
  final VoidCallback onToggle;
  final VoidCallback onDelete;
  final ValueChanged<String> onTitleChanged;

  const ChecklistItemTile({
    super.key,
    required this.item,
    required this.index,
    this.isEditable = true,
    required this.onToggle,
    required this.onDelete,
    required this.onTitleChanged,
  });

  @override
  State<ChecklistItemTile> createState() => _ChecklistItemTileState();
}

class _ChecklistItemTileState extends State<ChecklistItemTile> {
  bool _isHovered = false;
  bool _isEditing = false;
  late TextEditingController _editController;
  final _editFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _editController = TextEditingController(text: widget.item.title);
  }

  @override
  void didUpdateWidget(ChecklistItemTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item.title != widget.item.title && !_isEditing) {
      _editController.text = widget.item.title;
    }
  }

  @override
  void dispose() {
    _editController.dispose();
    _editFocusNode.dispose();
    super.dispose();
  }

  void _startEditing() {
    if (!widget.isEditable) return;
    setState(() {
      _isEditing = true;
      _editController.text = widget.item.title;
    });
    Future.delayed(const Duration(milliseconds: 100), () {
      _editFocusNode.requestFocus();
      selectAllText(_editController);
    });
  }

  void _finishEditing() {
    if (_editController.text.trim().isNotEmpty &&
        _editController.text.trim() != widget.item.title) {
      widget.onTitleChanged(_editController.text);
    }
    setState(() {
      _isEditing = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: Container(
        margin: const EdgeInsets.only(bottom: 4),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 6),
        decoration: BoxDecoration(
          color: _isHovered ? AppColors.surfaceAlt : Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        child: Row(
          children: [
            // Checkbox
            GestureDetector(
              onTap: widget.onToggle,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  color: widget.item.isComplete
                      ? AppColors.success
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(AppRadius.xs),
                  border: Border.all(
                    color: widget.item.isComplete
                        ? AppColors.success
                        : AppColors.textTertiary,
                    width: 2,
                  ),
                ),
                child: widget.item.isComplete
                    ? const Icon(Icons.check, size: 14, color: Colors.white)
                    : null,
              ),
            ),
            const SizedBox(width: 8),

            // Drag handle (visible on hover)
            if (_isHovered && widget.isEditable)
              ReorderableDragStartListener(
                index: widget.index,
                child: MouseRegion(
                  cursor: SystemMouseCursors.grab,
                  child: Icon(
                    Icons.drag_indicator,
                    size: 18,
                    color: AppColors.textTertiary,
                  ),
                ),
              ),
            const SizedBox(width: 8),

            // Title (editable or static)
            Expanded(
              child: _isEditing
                  ? TextField(
                      controller: _editController,
                      focusNode: _editFocusNode,
                      style: const TextStyle(fontSize: 14),
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                      onSubmitted: (_) => _finishEditing(),
                      onTapOutside: (_) => _finishEditing(),
                    )
                  : GestureDetector(
                      onDoubleTap: _startEditing,
                      child: Text(
                        widget.item.title,
                        style: TextStyle(
                          fontSize: 14,
                          color: widget.item.isComplete
                              ? AppColors.textTertiary
                              : AppColors.textPrimary,
                          decoration: widget.item.isComplete
                              ? TextDecoration.lineThrough
                              : null,
                        ),
                      ),
                    ),
            ),

            // Delete button (visible on hover)
            if (_isHovered && widget.isEditable)
              GestureDetector(
                onTap: widget.onDelete,
                child: Icon(
                  Icons.close,
                  size: 18,
                  color: AppColors.textTertiary,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
