import 'package:flutter/material.dart';

/// Shared "add child" button used by hierarchical table rows.
///
/// Presents a small popup menu with "Add item" and "Add group" actions and
/// optionally expands the parent row before invoking the selected callback.
class TreeRowAddButton extends StatelessWidget {
  const TreeRowAddButton({
    super.key,
    required this.isExpanded,
    required this.onAddItem,
    required this.onAddGroup,
    this.onEnsureExpanded,
    this.tooltip = 'Add to group',
  });

  final bool isExpanded;
  final VoidCallback onAddItem;
  final VoidCallback onAddGroup;
  final VoidCallback? onEnsureExpanded;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 20,
      height: 36,
      child: IconButton(
        icon: const Icon(Icons.add_circle_outline, size: 16),
        color: Theme.of(context).colorScheme.onSurfaceVariant,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(),
        tooltip: tooltip,
        onPressed: () => _showAddMenu(context),
      ),
    );
  }

  void _showAddMenu(BuildContext context) {
    final renderBox = context.findRenderObject() as RenderBox;
    final overlay =
        Navigator.of(context).overlay!.context.findRenderObject() as RenderBox;
    final buttonPosition = renderBox.localToGlobal(
      Offset.zero,
      ancestor: overlay,
    );

    final position = RelativeRect.fromLTRB(
      buttonPosition.dx,
      buttonPosition.dy + renderBox.size.height,
      overlay.size.width - buttonPosition.dx - renderBox.size.width,
      overlay.size.height - buttonPosition.dy - renderBox.size.height,
    );

    showMenu<String>(
      context: context,
      position: position,
      items: const [
        PopupMenuItem<String>(
          value: 'add_item',
          child: Row(
            children: [
              Icon(Icons.add, size: 18),
              SizedBox(width: 8),
              Text('Add item'),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'add_group',
          child: Row(
            children: [
              Icon(Icons.create_new_folder_outlined, size: 18),
              SizedBox(width: 8),
              Text('Add group'),
            ],
          ),
        ),
      ],
    ).then((value) {
      if (value == null) return;

      if (!isExpanded) {
        onEnsureExpanded?.call();
      }

      if (value == 'add_item') {
        onAddItem();
      } else if (value == 'add_group') {
        onAddGroup();
      }
    });
  }
}
