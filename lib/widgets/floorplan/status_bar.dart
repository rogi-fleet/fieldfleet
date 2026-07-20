import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/floorplan/editor_mode.dart';
import '../../services/floorplan/floorplan_editor_controller.dart';
import '../../utils/floorplan/units.dart';
import 'viewport_controller.dart';
import '../../theme/theme.dart';

/// Persistent metadata strip below the canvas. Doesn't change layout —
/// it just always shows where the cursor is, what the zoom is, what
/// tool is active, and whether there are unsaved changes.
class StatusBar extends StatelessWidget {
  const StatusBar({super.key, this.compact = false});

  /// Drop the cursor-position chip (touch finger covers it) and tighten
  /// spacing so the bar fits on a phone.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<FloorplanEditorController>();
    final viewport = context.read<FloorplanViewportController>();
    final unit = controller.scene.unit;
    final cursor = controller.cursorWorldPos;
    final zoom = controller.viewportScale;
    final selectionCount =
        controller.scene.selectedLayer.selected.totalCount;

    String cursorText() {
      if (cursor == null) return '—';
      return '${formatLengthCm(cursor.dx, unit).replaceAll(" $unit", "")}, '
          '${formatLengthCm(cursor.dy, unit).replaceAll(" $unit", "")} '
          '$unit';
    }

    final gap = compact ? 10.0 : 16.0;
    return Container(
      height: 28,
      padding: EdgeInsets.symmetric(horizontal: compact ? 8 : 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        border: Border(
          top: BorderSide(color: Theme.of(context).dividerColor),
        ),
      ),
      child: DefaultTextStyle(
        style: Theme.of(context).textTheme.bodySmall ?? const TextStyle(),
        child: Row(
          children: [
            if (!compact) ...[
              _Chip(icon: Icons.my_location, text: cursorText()),
              SizedBox(width: gap),
            ],
            _ZoomControls(
              zoom: zoom,
              compact: compact,
              onZoomOut: viewport.zoomOut,
              onZoomIn: viewport.zoomIn,
              onFit: () => viewport.fitToScene(
                controller.scene.width,
                controller.scene.height,
              ),
            ),
            SizedBox(width: gap),
            _Chip(icon: Icons.straighten, text: unit),
            SizedBox(width: gap),
            _Chip(
              icon: Icons.touch_app_outlined,
              text: _toolName(controller.mode),
            ),
            const Spacer(),
            if (selectionCount > 0)
              Padding(
                padding: EdgeInsets.only(right: gap),
                child: Text('$selectionCount sel'),
              ),
            Icon(
              controller.dirty ? Icons.circle : Icons.check_circle_outline,
              size: 12,
              color: controller.dirty
                  ? Colors.orange
                  : Theme.of(context).hintColor,
            ),
            const SizedBox(width: 4),
            Text(controller.dirty ? 'Unsaved' : 'Saved'),
          ],
        ),
      ),
    );
  }

  String _toolName(EditorMode mode) {
    if (mode is IdleMode) return 'Select';
    if (mode is PanMode) return 'Pan';
    if (mode is WaitingDrawingWallMode || mode is DrawingWallMode) {
      return 'Wall';
    }
    if (mode is WaitingDrawingHoleMode) {
      return mode.holePrototype == 'door' ? 'Door' : 'Window';
    }
    if (mode is PlacingItemMode) return 'Item: ${mode.itemPrototype}';
    if (mode is AddingAnnotationMode) {
      return 'Annotation: ${mode.annotationKind}';
    }
    if (mode is DraggingItemMode || mode is DraggingVertexMode ||
        mode is DraggingLineMode) {
      return 'Dragging';
    }
    return 'Select';
  }
}

class _Chip extends StatelessWidget {
  final IconData icon;
  final String text;
  const _Chip({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: Theme.of(context).hintColor),
        const SizedBox(width: 4),
        Text(text),
      ],
    );
  }
}

class _ZoomControls extends StatelessWidget {
  final double zoom;
  final bool compact;
  final VoidCallback onZoomOut;
  final VoidCallback onZoomIn;
  final VoidCallback onFit;

  const _ZoomControls({
    required this.zoom,
    required this.compact,
    required this.onZoomOut,
    required this.onZoomIn,
    required this.onFit,
  });

  @override
  Widget build(BuildContext context) {
    final hint = Theme.of(context).hintColor;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _ZoomBtn(
          icon: Icons.remove,
          tooltip: 'Zoom out',
          onTap: onZoomOut,
          color: hint,
        ),
        SizedBox(
          width: compact ? 36 : 44,
          child: Center(child: Text('${(zoom * 100).round()}%')),
        ),
        _ZoomBtn(
          icon: Icons.add,
          tooltip: 'Zoom in',
          onTap: onZoomIn,
          color: hint,
        ),
        const SizedBox(width: 2),
        _ZoomBtn(
          icon: Icons.fit_screen_outlined,
          tooltip: 'Fit to screen',
          onTap: onFit,
          color: hint,
        ),
      ],
    );
  }
}

class _ZoomBtn extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final Color color;

  const _ZoomBtn({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkResponse(
        onTap: onTap,
        radius: 14,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs, vertical: 2),
          child: Icon(icon, size: 16, color: color),
        ),
      ),
    );
  }
}
