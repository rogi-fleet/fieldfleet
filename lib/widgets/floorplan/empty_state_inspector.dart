import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/floorplan/editor_mode.dart';
import '../../services/floorplan/floorplan_editor_controller.dart';
import '../../utils/floorplan/units.dart';
import '../../theme/theme.dart';

/// Shown in the inspector slot when nothing is selected. Replaces the
/// previous "Select an element to edit" placeholder with a quick-stats
/// summary + four action buttons so users always have an obvious next
/// step.
class EmptyStateInspector extends StatelessWidget {
  const EmptyStateInspector({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<FloorplanEditorController>();
    final layer = controller.scene.selectedLayer;

    final stats = <(IconData, String, int)>[
      (Icons.architecture, 'Walls', layer.lines.length),
      (Icons.crop_square_outlined, 'Rooms', layer.areas.length),
      (Icons.sensor_door_outlined, 'Doors',
          layer.holes.values.where((h) => h.prototype == 'door').length),
      (Icons.window_outlined, 'Windows',
          layer.holes.values.where((h) => h.prototype == 'window').length),
      (Icons.chair_outlined, 'Items', layer.items.length),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Floorplan',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 12),
        ...stats.map((s) => _StatRow(icon: s.$1, label: s.$2, count: s.$3)),
        const SizedBox(height: 16),
        Text(
          'Quick actions',
          style: Theme.of(context).textTheme.labelSmall,
        ),
        const SizedBox(height: 6),
        _Action(
          icon: Icons.architecture,
          label: 'Draw a wall',
          onTap: () =>
              controller.setMode(const WaitingDrawingWallMode()),
        ),
        _Action(
          icon: Icons.sensor_door_outlined,
          label: 'Place a door',
          onTap: () => controller.setMode(
            const WaitingDrawingHoleMode(holePrototype: 'door'),
          ),
        ),
        _Action(
          icon: Icons.chair_outlined,
          label: 'Add furniture',
          onTap: () => controller.setMode(
            const PlacingItemMode(itemPrototype: 'sofa'),
          ),
        ),
        _Action(
          icon: Icons.text_fields,
          label: 'Add a label',
          onTap: () => controller.setMode(
            const AddingAnnotationMode(annotationKind: 'text'),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Building',
          style: Theme.of(context).textTheme.labelSmall,
        ),
        const SizedBox(height: 6),
        _CeilingHeightField(controller: controller),
        const SizedBox(height: 16),
        Text(
          'Tip: select something on the canvas to edit its properties.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}

/// Scene-wide ceiling height editor. Lives in the empty-state inspector
/// rather than the status bar so it sits next to the rest of the
/// building-level metadata.
class _CeilingHeightField extends StatefulWidget {
  final FloorplanEditorController controller;
  const _CeilingHeightField({required this.controller});

  @override
  State<_CeilingHeightField> createState() => _CeilingHeightFieldState();
}

class _CeilingHeightFieldState extends State<_CeilingHeightField> {
  final TextEditingController _ctrl = TextEditingController();
  String? _seed;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final unit = widget.controller.scene.unit;
    final ceilingCm = widget.controller.scene.ceilingHeightCm;
    final seed = '${ceilingCm.toStringAsFixed(1)}|$unit';
    if (_seed != seed) {
      _seed = seed;
      _ctrl.text = formatLengthCm(ceilingCm, unit).replaceAll(' $unit', '');
    }
    return TextField(
      controller: _ctrl,
      decoration: InputDecoration(
        labelText: 'Ceiling height',
        suffixText: unit,
        helperText: 'Applies to every wall that has no override',
        border: const OutlineInputBorder(),
        isDense: true,
      ),
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      textInputAction: TextInputAction.done,
      onSubmitted: (v) => _commit(v),
      onTapOutside: (_) => _commit(_ctrl.text),
    );
  }

  void _commit(String input) {
    final parsed = parseLengthToCm(input, widget.controller.scene.unit);
    if (parsed == null) return;
    if (parsed < 100 || parsed > 1000) return;
    widget.controller.setSceneCeilingHeight(parsed);
  }
}

class _StatRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final int count;

  const _StatRow({
    required this.icon,
    required this.label,
    required this.count,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Icon(icon, size: 14, color: Theme.of(context).hintColor),
          const SizedBox(width: 8),
          Expanded(
            child: Text(label, style: Theme.of(context).textTheme.bodySmall),
          ),
          Text(
            '$count',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
          ),
        ],
      ),
    );
  }
}

class _Action extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _Action({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: TextButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 16),
        label: Text(label),
        style: TextButton.styleFrom(
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      ),
    );
  }
}
