import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/floorplan/editor_mode.dart';
import '../../services/floorplan/floorplan_editor_controller.dart';
import '../../utils/floorplan/units.dart';
import '../../theme/theme.dart';

/// A small chip that floats above the canvas and tells the user what
/// the next click will do, plus action chips that surface keyboard
/// shortcuts (Esc / Shift / Alt) on touch devices where there's no
/// keyboard. Auto-hides in IdleMode where the cursor can't go wrong.
class CanvasHint extends StatelessWidget {
  const CanvasHint({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<FloorplanEditorController>();
    final hint = _hintFor(controller.mode);
    if (hint == null) return const SizedBox.shrink();

    final actions = _actionsFor(context, controller);

    final showLengthInput = controller.mode is DrawingWallMode;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 6),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.inverseSurface,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            hint,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onInverseSurface,
              fontSize: 12,
            ),
          ),
          if (showLengthInput) ...[
            const SizedBox(width: 8),
            _LengthEntry(
              unit: controller.scene.unit,
              onCommit: controller.commitInFlightWallLength,
            ),
          ],
          if (actions.isNotEmpty) ...[
            const SizedBox(width: 12),
            ...actions,
          ],
        ],
      ),
    );
  }

  String? _hintFor(EditorMode mode) {
    if (mode is WaitingDrawingWallMode) {
      return 'Click to start a wall';
    }
    if (mode is DrawingWallMode) {
      return 'Click to finish';
    }
    if (mode is WaitingDrawingHoleMode) {
      final kind = mode.holePrototype == 'door' ? 'door' : 'window';
      return 'Click a wall to place a $kind';
    }
    if (mode is PlacingItemMode) {
      return 'Click to place item';
    }
    if (mode is AddingAnnotationMode) {
      return switch (mode.annotationKind) {
        'text' => 'Click to drop a text label',
        'arrow' => 'Click and drag to draw an arrow',
        'dimension' => 'Click and drag to mark a dimension',
        _ => 'Click to annotate',
      };
    }
    if (mode is PanMode) {
      return 'Drag to pan';
    }
    if (mode is DrawingRectangleRoomMode) {
      return 'Drag to define a rectangular room';
    }
    if (mode is TracingRoomMode) {
      final n = mode.points.length;
      if (n == 0) return 'Click to start tracing the room';
      if (n < 3) return 'Click to add more corners ($n placed)';
      return 'Click first corner to close · or keep adding ($n placed)';
    }
    if (mode is CalibratingMode) {
      return mode.first == null
          ? 'Click the first reference point'
          : 'Click the second reference point';
    }
    return null;
  }

  List<Widget> _actionsFor(
    BuildContext context,
    FloorplanEditorController controller,
  ) {
    final mode = controller.mode;
    final out = <Widget>[];

    // Cancel button is meaningful in any mode that's "waiting for the
    // next click" or actively drawing — gives touch users a way out
    // without a keyboard.
    if (mode is WaitingDrawingWallMode ||
        mode is DrawingWallMode ||
        mode is WaitingDrawingHoleMode ||
        mode is PlacingItemMode ||
        mode is AddingAnnotationMode ||
        mode is DrawingRectangleRoomMode ||
        mode is TracingRoomMode ||
        mode is CalibratingMode) {
      out.add(_HintAction(
        label: 'Esc',
        icon: Icons.close,
        onTap: () {
          // Each in-flight mode has its own cancel path so undo state
          // stays consistent; fall back to a generic mode reset.
          if (mode is DrawingRectangleRoomMode) {
            controller.cancelRectangleRoom();
          } else if (mode is TracingRoomMode) {
            controller.cancelTraceRoom();
          } else if (mode is CalibratingMode) {
            controller.cancelCalibration();
          } else {
            controller.cancelDrawing();
          }
        },
      ));
    }

    // Wall-draw toggles for ortho lock + snap disable. Persistent
    // (on touch the user has no Shift / Alt to hold).
    if (mode is WaitingDrawingWallMode || mode is DrawingWallMode) {
      out.add(_HintToggle(
        label: 'Lock 45°',
        active: controller.orthoLock,
        onTap: () => controller.setOrthoLock(!controller.orthoLock),
      ));
      out.add(_HintToggle(
        label: 'No snap',
        active: controller.snapDisabled,
        onTap: () => controller.setSnapDisabled(!controller.snapDisabled),
      ));
    }

    return out;
  }
}

/// Inline length input that appears in the canvas-hint chip while a
/// wall is being drawn. Typing a number + Enter commits the wall at
/// that length in the active unit, in the cursor's current direction
/// from the start vertex.
class _LengthEntry extends StatefulWidget {
  final String unit;
  final ValueChanged<double> onCommit;

  const _LengthEntry({required this.unit, required this.onCommit});

  @override
  State<_LengthEntry> createState() => _LengthEntryState();
}

class _LengthEntryState extends State<_LengthEntry> {
  final TextEditingController _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _commit() {
    final raw = _ctrl.text.trim();
    if (raw.isEmpty) return;
    final cm = parseLengthToCm(raw, widget.unit);
    if (cm == null || cm <= 0) return;
    widget.onCommit(cm);
    _ctrl.clear();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 90,
      height: 24,
      child: TextField(
        controller: _ctrl,
        style: TextStyle(
          color: Theme.of(context).colorScheme.onInverseSurface,
          fontSize: 11,
        ),
        decoration: InputDecoration(
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 6,
            vertical: AppSpacing.xs,
          ),
          hintText: 'len',
          hintStyle: TextStyle(
            color: Theme.of(context)
                .colorScheme
                .onInverseSurface
                .withValues(alpha: 0.5),
            fontSize: 11,
          ),
          suffixText: widget.unit,
          suffixStyle: TextStyle(
            color: Theme.of(context)
                .colorScheme
                .onInverseSurface
                .withValues(alpha: 0.7),
            fontSize: 11,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadius.xs),
            borderSide: BorderSide(
              color: Theme.of(context)
                  .colorScheme
                  .onInverseSurface
                  .withValues(alpha: 0.3),
            ),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadius.xs),
            borderSide: BorderSide(
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
        ),
        keyboardType:
            const TextInputType.numberWithOptions(decimal: true),
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _commit(),
      ),
    );
  }
}

class _HintAction extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  const _HintAction({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.xs),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 12,
                color: Theme.of(context).colorScheme.onInverseSurface,
              ),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  color: Theme.of(context).colorScheme.onInverseSurface,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HintToggle extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _HintToggle({
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final on = active;
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.xs),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: on
                ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.4)
                : null,
            borderRadius: BorderRadius.circular(AppRadius.xs),
            border: Border.all(
              color: on
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context)
                      .colorScheme
                      .onInverseSurface
                      .withValues(alpha: 0.3),
              width: 1,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: on ? FontWeight.w600 : FontWeight.normal,
              color: Theme.of(context).colorScheme.onInverseSurface,
            ),
          ),
        ),
      ),
    );
  }
}
