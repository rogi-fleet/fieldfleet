import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'dart:math' as math;

import '../../models/floorplan/annotation.dart';
import '../../services/floorplan/floorplan_editor_controller.dart';
import '../../utils/floorplan/geometry.dart' as geom;
import '../../utils/floorplan/units.dart';
import 'empty_state_inspector.dart';
import '../../theme/theme.dart';

/// Right-rail inspector showing properties of the currently-selected element.
/// Shows nothing when nothing is selected — keeps the canvas wide.
class PropertyInspector extends StatelessWidget {
  static const double width = 260;

  const PropertyInspector({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<FloorplanEditorController>();
    final layer = controller.scene.selectedLayer;
    final sel = layer.selected;

    final Widget body;
    if (sel.lines.isNotEmpty) {
      body = _LineInspector(lineId: sel.lines.first);
    } else if (sel.holes.isNotEmpty) {
      body = _HoleInspector(holeId: sel.holes.first);
    } else if (sel.items.isNotEmpty) {
      body = _ItemInspector(itemId: sel.items.first);
    } else if (sel.annotations.isNotEmpty) {
      body = _AnnotationInspector(annotationId: sel.annotations.first);
    } else if (sel.areas.isNotEmpty) {
      body = _AreaInspector(areaId: sel.areas.first);
    } else {
      body = const EmptyStateInspector();
    }

    return Container(
      width: width,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          left: BorderSide(color: Theme.of(context).dividerColor),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.base),
        child: body,
      ),
    );
  }
}

class _EmptyInspector extends StatelessWidget {
  const _EmptyInspector();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        'Select an element to edit its properties.',
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodySmall,
      ),
    );
  }
}

class _LineInspector extends StatefulWidget {
  final String lineId;
  const _LineInspector({required this.lineId});

  @override
  State<_LineInspector> createState() => _LineInspectorState();
}

class _LineInspectorState extends State<_LineInspector> {
  final TextEditingController _lengthCtrl = TextEditingController();
  String? _lengthSeed;

  @override
  void dispose() {
    _lengthCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.read<FloorplanEditorController>();
    final layer = controller.scene.selectedLayer;
    final line = layer.lines[widget.lineId];
    if (line == null) return const _EmptyInspector();
    final unit = controller.scene.unit;
    final a = layer.vertices[line.vertexIds[0]];
    final b = layer.vertices[line.vertexIds[1]];
    final lengthCm = (a == null || b == null)
        ? 0.0
        : math.sqrt(
            math.pow(b.x - a.x, 2) + math.pow(b.y - a.y, 2),
          ).toDouble();
    // Re-seed the field whenever the underlying length changes (e.g.
    // after a drag) — but only if the user isn't currently editing it.
    final seed = '${widget.lineId}|${lengthCm.toStringAsFixed(2)}|$unit';
    if (_lengthSeed != seed) {
      _lengthSeed = seed;
      _lengthCtrl.text = formatLengthCm(lengthCm, unit)
          .replaceAll(' $unit', '');
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionHeader('Wall'),
        TextField(
          controller: _lengthCtrl,
          decoration: InputDecoration(
            labelText: 'Length',
            suffixText: unit,
            border: const OutlineInputBorder(),
            isDense: true,
          ),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          textInputAction: TextInputAction.done,
          onSubmitted: (v) => _commitLength(controller, v),
          onTapOutside: (_) =>
              _commitLength(controller, _lengthCtrl.text),
        ),
        const SizedBox(height: 8),
        _Slider(
          label: 'Thickness',
          value: line.thickness,
          min: 5,
          max: 60,
          onChanged: (v) =>
              controller.updateLineThickness(widget.lineId, v),
        ),
        const SizedBox(height: 8),
        _LineHeightField(lineId: widget.lineId),
        const SizedBox(height: 8),
        Text(
          '${line.holeIds.length} opening${line.holeIds.length == 1 ? '' : 's'} '
          'on this wall',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: controller.deleteSelectedWalls,
          icon: const Icon(Icons.delete_outline, size: 16),
          label: const Text('Delete'),
        ),
      ],
    );
  }

  void _commitLength(FloorplanEditorController controller, String input) {
    final parsed = parseLengthToCm(input, controller.scene.unit);
    if (parsed == null) return;
    controller.setWallLength(widget.lineId, parsed);
  }
}

/// Per-wall height override editor. Empty when the wall uses the scene
/// default; populated with the override value otherwise. The reset
/// button is only shown while an override is in effect.
class _LineHeightField extends StatefulWidget {
  final String lineId;
  const _LineHeightField({required this.lineId});

  @override
  State<_LineHeightField> createState() => _LineHeightFieldState();
}

class _LineHeightFieldState extends State<_LineHeightField> {
  final TextEditingController _ctrl = TextEditingController();
  String? _seed;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<FloorplanEditorController>();
    final line = controller.scene.selectedLayer.lines[widget.lineId];
    if (line == null) return const SizedBox.shrink();
    final unit = controller.scene.unit;
    final sceneDefault = controller.scene.ceilingHeightCm;
    final override = line.heightCm;
    final hasOverride = override != null;

    // Show the override in the field when set; show the scene default
    // as a placeholder hint otherwise so the user sees what they'd be
    // diverging from.
    final seedValue = hasOverride
        ? override.toStringAsFixed(1)
        : '__default_${sceneDefault.toStringAsFixed(1)}';
    final seed = '${widget.lineId}|$seedValue|$unit';
    if (_seed != seed) {
      _seed = seed;
      _ctrl.text = hasOverride
          ? formatLengthCm(override, unit).replaceAll(' $unit', '')
          : '';
    }
    final defaultLabel = formatLengthCm(sceneDefault, unit);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: TextField(
            controller: _ctrl,
            decoration: InputDecoration(
              labelText: 'Height',
              hintText: hasOverride ? null : 'Scene default · $defaultLabel',
              suffixText: unit,
              border: const OutlineInputBorder(),
              isDense: true,
            ),
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            textInputAction: TextInputAction.done,
            onSubmitted: (v) => _commit(controller, v),
            onTapOutside: (_) => _commit(controller, _ctrl.text),
          ),
        ),
        if (hasOverride) ...[
          const SizedBox(width: 6),
          IconButton(
            tooltip: 'Reset to scene default',
            onPressed: () =>
                controller.setLineHeight(widget.lineId, null),
            icon: const Icon(Icons.restore),
            visualDensity: VisualDensity.compact,
          ),
        ],
      ],
    );
  }

  void _commit(FloorplanEditorController controller, String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) {
      // Empty field means "use scene default" — clear the override.
      controller.setLineHeight(widget.lineId, null);
      return;
    }
    final parsed = parseLengthToCm(trimmed, controller.scene.unit);
    if (parsed == null) return;
    if (parsed < 10 || parsed > 1000) return;
    controller.setLineHeight(widget.lineId, parsed);
  }
}

class _HoleInspector extends StatelessWidget {
  final String holeId;
  const _HoleInspector({required this.holeId});

  @override
  Widget build(BuildContext context) {
    final controller = context.read<FloorplanEditorController>();
    final hole = controller.scene.selectedLayer.holes[holeId];
    if (hole == null) return const _EmptyInspector();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(hole.prototype == 'door' ? 'Door' : 'Window'),
        _Slider(
          label: 'Width',
          value: hole.width,
          min: 40,
          max: 220,
          onChanged: (v) =>
              controller.updateHoleSize(holeId, width: v),
        ),
        _Slider(
          label: 'Height',
          value: hole.height,
          min: 80,
          max: 260,
          onChanged: (v) =>
              controller.updateHoleSize(holeId, height: v),
        ),
        _Slider(
          label: hole.prototype == 'door' ? 'Threshold' : 'Sill height',
          value: hole.altitude,
          min: 0,
          max: 200,
          onChanged: (v) =>
              controller.updateHoleAltitude(holeId, v),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (hole.prototype == 'door')
              OutlinedButton.icon(
                onPressed: controller.flipSelectedDoor,
                icon: const Icon(Icons.swap_horiz, size: 16),
                label: const Text('Flip swing'),
              ),
            OutlinedButton.icon(
              onPressed: controller.deleteSelectedHole,
              icon: const Icon(Icons.delete_outline, size: 16),
              label: const Text('Delete'),
            ),
          ],
        ),
      ],
    );
  }
}

class _ItemInspector extends StatelessWidget {
  final String itemId;
  const _ItemInspector({required this.itemId});

  @override
  Widget build(BuildContext context) {
    final controller = context.read<FloorplanEditorController>();
    final item = controller.scene.selectedLayer.items[itemId];
    if (item == null) return const _EmptyInspector();
    final spec = controller.catalog.get(item.prototype);
    final degrees = item.rotation * 180 / 3.141592653589793;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(spec?.name ?? 'Item'),
        _Slider(
          label: 'Width',
          value: item.width,
          min: 20,
          max: 400,
          onChanged: (v) => controller.resizeItem(itemId, width: v),
        ),
        _Slider(
          label: 'Height',
          value: item.height,
          min: 20,
          max: 400,
          onChanged: (v) => controller.resizeItem(itemId, height: v),
        ),
        _Slider(
          label: 'Rotation°',
          value: degrees,
          min: 0,
          max: 360,
          onChanged: (v) => controller.setItemRotationDegrees(itemId, v),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: controller.deleteSelected,
          icon: const Icon(Icons.delete_outline, size: 16),
          label: const Text('Delete'),
        ),
      ],
    );
  }
}

class _AnnotationInspector extends StatefulWidget {
  final String annotationId;
  const _AnnotationInspector({required this.annotationId});

  @override
  State<_AnnotationInspector> createState() => _AnnotationInspectorState();
}

class _AnnotationInspectorState extends State<_AnnotationInspector> {
  final TextEditingController _textCtrl = TextEditingController();
  final FocusNode _textFocus = FocusNode();
  String? _seededId;

  @override
  void dispose() {
    _textCtrl.dispose();
    _textFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.read<FloorplanEditorController>();
    final ann = controller.scene.selectedLayer.annotations[widget.annotationId];
    if (ann == null) return const _EmptyInspector();

    // Seed the text controller when the selection first lands on this
    // annotation so the field shows the current text without overwriting
    // the user's mid-edit value on every controller notification. A
    // freshly-created annotation has empty text — auto-focus the field
    // so the user can type immediately.
    if (ann is TextAnnotation && _seededId != ann.id) {
      _textCtrl.text = ann.text;
      _seededId = ann.id;
      if (ann.text.isEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _textFocus.requestFocus();
        });
      }
    }

    final kindLabel = switch (ann) {
      TextAnnotation() => 'Text label',
      ArrowAnnotation() => 'Arrow',
      DimensionAnnotation() => 'Dimension',
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(kindLabel),
        if (ann is TextAnnotation) ...[
          TextField(
            controller: _textCtrl,
            focusNode: _textFocus,
            decoration: const InputDecoration(
              labelText: 'Text',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            onChanged: (v) =>
                controller.updateAnnotationText(widget.annotationId, v),
          ),
        ] else if (ann is DimensionAnnotation) ...[
          Text(
            'Length: ${(ann.to - ann.from).distance.toStringAsFixed(0)} ${ann.unit}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: controller.deleteSelected,
          icon: const Icon(Icons.delete_outline, size: 16),
          label: const Text('Delete'),
        ),
      ],
    );
  }
}

class _AreaInspector extends StatelessWidget {
  final String areaId;
  const _AreaInspector({required this.areaId});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<FloorplanEditorController>();
    final layer = controller.scene.selectedLayer;
    final area = layer.areas[areaId];
    if (area == null) return const _EmptyInspector();
    final unit = controller.scene.unit;
    final name = (area.properties['name'] as String?) ?? '';

    // Resolve vertex offsets in scene-space (cm). Missing vertices —
    // shouldn't happen but we don't want to crash the inspector when
    // it does — produce a degenerate polygon that yields 0 area.
    final pts = <Offset>[];
    for (final id in area.vertexIds) {
      final v = layer.vertices[id];
      if (v != null) pts.add(Offset(v.x, v.y));
    }
    final areaCm2 = geom.polygonArea(pts);
    final perimeterCm = geom.polygonPerimeter(pts);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionHeader('Room'),
        TextFormField(
          initialValue: name,
          decoration: const InputDecoration(
            labelText: 'Name',
            border: OutlineInputBorder(),
            isDense: true,
          ),
          onFieldSubmitted: (v) => controller.updateAreaName(areaId, v),
        ),
        const SizedBox(height: 12),
        _StatLine(
          icon: Icons.square_foot,
          label: 'Floor area',
          value: formatAreaCm2(areaCm2, unit),
        ),
        _StatLine(
          icon: Icons.straighten,
          label: 'Perimeter',
          value: formatLengthCm(perimeterCm, unit),
        ),
        _StatLine(
          icon: Icons.crop_square,
          label: 'Corners',
          value: '${area.vertexIds.length}',
        ),
      ],
    );
  }
}

class _StatLine extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _StatLine({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Icon(icon, size: 14, color: Theme.of(context).hintColor),
          const SizedBox(width: 8),
          Expanded(
            child: Text(label, style: Theme.of(context).textTheme.bodySmall),
          ),
          Text(
            value,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String text;
  const _SectionHeader(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        text,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
              letterSpacing: 0.4,
            ),
      ),
    );
  }
}

class _Slider extends StatelessWidget {
  final String label;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;

  const _Slider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label, style: Theme.of(context).textTheme.bodySmall),
              Text(
                value.toStringAsFixed(0),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
          Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

