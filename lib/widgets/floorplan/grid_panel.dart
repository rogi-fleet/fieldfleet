import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/floorplan/floorplan_editor_controller.dart';
import '../../utils/floorplan/units.dart';
import '../../theme/theme.dart';

/// Bottom-left floating panel for grid-related controls.
class GridPanel extends StatelessWidget {
  const GridPanel({super.key, this.bare = false});

  /// Drop the rounded surface + shadow chrome (sheet-embed path).
  final bool bare;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<FloorplanEditorController>();
    final step = controller.scene.gridSize;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 6),
      decoration: bare
          ? null
          : BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(AppRadius.sm),
              boxShadow: const [
                BoxShadow(
                    color: Color(0x14000000),
                    blurRadius: 6,
                    offset: Offset(0, 2)),
              ],
            ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.grid_4x4, size: 16),
          const SizedBox(width: 8),
          Text('Grid', style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(width: 8),
          DropdownButton<double>(
            value: _quantize(step),
            underline: const SizedBox.shrink(),
            isDense: true,
            items: const [10.0, 20.0, 50.0, 100.0]
                .map((s) => DropdownMenuItem(
                      value: s,
                      child: Text('${s.toStringAsFixed(0)} cm'),
                    ))
                .toList(),
            onChanged: (v) {
              if (v != null) controller.setGridSize(v);
            },
          ),
          const SizedBox(width: 12),
          const Icon(Icons.straighten, size: 16),
          const SizedBox(width: 8),
          Text('Units', style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(width: 6),
          DropdownButton<String>(
            value: controller.scene.unit,
            underline: const SizedBox.shrink(),
            isDense: true,
            items: kSupportedUnits
                .map((u) => DropdownMenuItem(value: u, child: Text(u)))
                .toList(),
            onChanged: (v) {
              if (v != null) controller.setUnit(v);
            },
          ),
        ],
      ),
    );
  }

  double _quantize(double step) {
    const choices = [10.0, 20.0, 50.0, 100.0];
    return choices.reduce(
      (a, b) => (a - step).abs() < (b - step).abs() ? a : b,
    );
  }
}
