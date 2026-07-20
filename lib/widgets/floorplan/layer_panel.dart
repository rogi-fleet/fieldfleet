import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/floorplan/layer.dart';
import '../../services/floorplan/floorplan_editor_controller.dart';
import '../../theme/theme.dart';

/// Bottom-right floating panel listing the scene's layers. Lets users pick
/// the active layer (the one new draws/places target) and toggle layer
/// visibility. v1 ships add-layer; rename/reorder/delete are future work.
class LayerPanel extends StatelessWidget {
  const LayerPanel({super.key, this.width = 220, this.bare = false});

  /// Fixed width for the floating-panel form. Pass null to let the
  /// panel size to its parent (used when embedded in a bottom sheet).
  final double? width;

  /// Drop the rounded surface + shadow chrome. Useful when the panel
  /// is hosted inside another surface (e.g. a bottom sheet) that
  /// already provides its own background.
  final bool bare;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<FloorplanEditorController>();
    final layers = controller.scene.layers.values.toList()
      ..sort((a, b) => a.order.compareTo(b.order));

    return Container(
      width: width,
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      decoration: bare
          ? null
          : BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(AppRadius.sm),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x14000000),
                  blurRadius: 6,
                  offset: Offset(0, 2),
                ),
              ],
            ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            child: Row(
              children: [
                Text(
                  'Layers',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.add, size: 18),
                  tooltip: 'Add layer',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => controller.addLayer(
                    name: 'Layer ${controller.scene.layers.length + 1}',
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          ...layers.asMap().entries.map((entry) {
            final i = entry.key;
            final layer = entry.value;
            final isActive = layer.id == controller.scene.selectedLayerId;
            final isFirst = i == 0;
            final isLast = i == layers.length - 1;
            return InkWell(
              onTap: () => controller.setSelectedLayer(layer.id),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.xs,
                ),
                color: isActive
                    ? Theme.of(context)
                        .colorScheme
                        .primary
                        .withValues(alpha: 0.08)
                    : null,
                child: Row(
                  children: [
                    IconButton(
                      icon: Icon(
                        layer.visible
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                        size: 16,
                      ),
                      visualDensity: VisualDensity.compact,
                      onPressed: () => controller.setLayerVisible(
                        layer.id,
                        !layer.visible,
                      ),
                    ),
                    Expanded(
                      child: Text(
                        layer.name,
                        style: TextStyle(
                          fontWeight: isActive
                              ? FontWeight.w600
                              : FontWeight.normal,
                        ),
                      ),
                    ),
                    if (isActive)
                      const Padding(
                        padding: EdgeInsets.only(right: 4),
                        child: Icon(
                          Icons.radio_button_checked,
                          size: 14,
                          color: AppColors.info,
                        ),
                      ),
                    PopupMenuButton<String>(
                      icon: const Icon(Icons.more_vert, size: 16),
                      tooltip: 'Layer options',
                      padding: EdgeInsets.zero,
                      onSelected: (action) =>
                          _onLayerAction(context, controller, layer, action),
                      itemBuilder: (_) => [
                        const PopupMenuItem(
                          value: 'rename',
                          child: Row(
                            children: [
                              Icon(Icons.edit, size: 16),
                              SizedBox(width: 8),
                              Text('Rename'),
                            ],
                          ),
                        ),
                        if (!isFirst)
                          const PopupMenuItem(
                            value: 'up',
                            child: Row(
                              children: [
                                Icon(Icons.arrow_upward, size: 16),
                                SizedBox(width: 8),
                                Text('Move up'),
                              ],
                            ),
                          ),
                        if (!isLast)
                          const PopupMenuItem(
                            value: 'down',
                            child: Row(
                              children: [
                                Icon(Icons.arrow_downward, size: 16),
                                SizedBox(width: 8),
                                Text('Move down'),
                              ],
                            ),
                          ),
                        if (layers.length > 1)
                          const PopupMenuItem(
                            value: 'delete',
                            child: Row(
                              children: [
                                Icon(
                                  Icons.delete_outline,
                                  size: 16,
                                  color: Colors.red,
                                ),
                                SizedBox(width: 8),
                                Text(
                                  'Delete',
                                  style: TextStyle(color: Colors.red),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  Future<void> _onLayerAction(
    BuildContext context,
    FloorplanEditorController controller,
    Layer layer,
    String action,
  ) async {
    switch (action) {
      case 'rename':
        final renamed = await _promptRename(context, layer.name);
        if (renamed != null) controller.renameLayer(layer.id, renamed);
      case 'up':
        controller.moveLayer(layer.id, up: true);
      case 'down':
        controller.moveLayer(layer.id, up: false);
      case 'delete':
        final ok = controller.deleteLayer(layer.id);
        if (!ok && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Layer must be empty before it can be deleted.',
              ),
            ),
          );
        }
    }
  }

  Future<String?> _promptRename(BuildContext context, String current) async {
    final ctrl = TextEditingController(text: current);
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Rename layer'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            isDense: true,
          ),
          onSubmitted: (v) => Navigator.pop(dialogContext, v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, ctrl.text),
            child: const Text('Rename'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    return result;
  }
}
