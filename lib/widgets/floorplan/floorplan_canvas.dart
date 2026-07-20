import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../models/floorplan/annotation.dart';
import '../../models/floorplan/editor_mode.dart';
import '../../models/floorplan/element_kind.dart';
import '../../models/floorplan/elements_set.dart';
import '../../models/floorplan/layer.dart';
import '../../services/floorplan/floorplan_editor_controller.dart';
import '../../utils/floorplan/snap.dart';
import 'background_layer.dart';
import 'floorplan_scene_painter.dart';
import 'viewport_controller.dart';

/// Pan/zoom + paint surface for a floorplan scene.
///
/// Layout from bottom to top:
/// 1. [InteractiveViewer] handles pan + pinch-zoom in screen space.
/// 2. A scene-sized child stack:
///    - [BackgroundLayer] (faded PDF underlay, Phase 3)
///    - [CustomPaint] using [FloorplanScenePainter]
///    - [Listener] forwarding pointer events to the [_GestureRouter]
///
/// The InteractiveViewer's pan is **disabled while drawing** so the gesture
/// router gets the single-finger drag that draws walls. Pinch-zoom stays
/// enabled in all modes.
class FloorplanCanvas extends StatefulWidget {
  final double snapDistance;

  const FloorplanCanvas({super.key, this.snapDistance = 8.0});

  @override
  State<FloorplanCanvas> createState() => _FloorplanCanvasState();
}

class _FloorplanCanvasState extends State<FloorplanCanvas> {
  PointerDeviceKind _lastPointerKind = PointerDeviceKind.mouse;
  FloorplanViewportController? _viewport;

  bool get _isTouch => _lastPointerKind == PointerDeviceKind.touch;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final viewport = context.read<FloorplanViewportController>();
    if (!identical(viewport, _viewport)) {
      _viewport?.transform.removeListener(_pushScale);
      _viewport = viewport;
      viewport.transform.addListener(_pushScale);
    }
  }

  @override
  void dispose() {
    _viewport?.transform.removeListener(_pushScale);
    super.dispose();
  }

  void _pushScale() {
    final viewport = _viewport;
    if (viewport == null) return;
    // Pull the controller off the inherited tree without triggering a
    // dependency for this State — we don't want every transform tick to
    // mark our build dirty, just to push the new scale into the model.
    final ctl = Provider.of<FloorplanEditorController>(context, listen: false);
    ctl.setViewportScale(viewport.scale);
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<FloorplanEditorController>();
    final viewport = context.read<FloorplanViewportController>();
    final isPan = controller.mode is PanMode;
    final isSelect = controller.mode is IdleMode;
    // Single-finger / left-click drag pans the InteractiveViewer when:
    //   - the user has the Pan tool selected, OR
    //   - the user is on a touch device AND in Select mode (because
    //     rubber-band needs a precise cursor; on touch we let pan win).
    // Pinch-zoom always works.
    final panEnabled = isPan || (isSelect && _isTouch);

    return LayoutBuilder(builder: (context, constraints) {
      // Report the canvas viewport size up so zoom buttons can anchor at
      // the visible center. Safe to call during build — the viewport
      // controller doesn't notify on size changes.
      viewport.setViewportSize(
        Size(constraints.maxWidth, constraints.maxHeight),
      );
      return Listener(
      // Top-level sniff for pointer kind so we can flip layout/gesture
      // behavior for touch devices without re-plumbing it through every
      // child. Updates only when the kind changes.
      onPointerDown: (e) {
        if (e.kind != _lastPointerKind) {
          setState(() => _lastPointerKind = e.kind);
        }
      },
      child: InteractiveViewer(
        transformationController: viewport.transform,
        minScale: FloorplanViewportController.minScale,
        maxScale: FloorplanViewportController.maxScale,
        boundaryMargin: const EdgeInsets.all(400),
        panEnabled: panEnabled,
        scaleEnabled: true,
        child: SizedBox(
          width: controller.scene.width,
          height: controller.scene.height,
          child: RepaintBoundary(
            child: Stack(
              children: [
                BackgroundLayer(
                  background: controller.scene.background,
                  sceneWidth: controller.scene.width,
                  sceneHeight: controller.scene.height,
                ),
                _PaintLayer(controller: controller),
                _GestureRouter(
                  controller: controller,
                  // Fingers are imprecise — bump every hit-test radius
                  // (snap, element pick, handle pick) on touch.
                  snapDistance: _isTouch ? 22.0 : widget.snapDistance,
                  isTouch: _isTouch,
                ),
              ],
            ),
          ),
        ),
      ),
    );
    });
  }
}

class _PaintLayer extends StatelessWidget {
  final FloorplanEditorController controller;

  const _PaintLayer({required this.controller});

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: CustomPaint(
        painter: FloorplanScenePainter(
          scene: controller.scene,
          mode: controller.mode,
          snapHint: controller.activeSnap,
          hovered: controller.hoveredElement,
          ghostPreview: controller.ghostPreview,
          inverseViewportScale: controller.viewportScale > 0
              ? 1.0 / controller.viewportScale
              : 1.0,
          catalog: controller.catalog,
        ),
      ),
    );
  }
}

class _GestureRouter extends StatefulWidget {
  final FloorplanEditorController controller;
  final double snapDistance;
  final bool isTouch;

  const _GestureRouter({
    required this.controller,
    required this.snapDistance,
    required this.isTouch,
  });

  @override
  State<_GestureRouter> createState() => _GestureRouterState();
}

class _GestureRouterState extends State<_GestureRouter> {
  String? _draggingItemId;
  String? _draggingVertexId;
  String? _draggingHoleId;
  String? _draggingLineId;
  String? _draggingAnnotationId;
  String? _resizingItemId;
  int _resizingCorner = 0;
  Offset? _lastDragPos;
  String? _rotatingItemId;
  Offset? _annotationStart;

  /// Active rubber-band selection rect (scene coords). Null when not
  /// drawing one. The router paints its own overlay above the scene so the
  /// scene painter doesn't need to know about selection state.
  Offset? _rubberStart;
  Rect? _rubberRect;

  /// Long-press → marquee on touch. Pointer-down on empty space arms a
  /// timer; if the finger holds still for 350ms, we promote the gesture
  /// to a rubber-band selection. Movement before the timer fires
  /// cancels (treat as pan). Released early = tap.
  Timer? _longPressTimer;
  Offset? _longPressDownPos;
  static const _kLongPressDuration = Duration(milliseconds: 350);
  static const _kLongPressMoveTolerance = 12.0;

  /// Tap-once-to-preview, tap-twice-to-commit on touch for placement
  /// modes (door / window / item). Stores the world-pos of the first
  /// preview tap so a follow-up tap nearby commits, while a tap far
  /// away just moves the preview.
  Offset? _pendingPlacementTap;

  FloorplanEditorController get controller => widget.controller;
  double get snapDistance => widget.snapDistance;
  bool get _isTouch => widget.isTouch;

  bool get _isDragging =>
      _draggingItemId != null ||
      _draggingVertexId != null ||
      _draggingHoleId != null ||
      _draggingLineId != null ||
      _draggingAnnotationId != null ||
      _resizingItemId != null ||
      _rotatingItemId != null;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: Stack(
        children: [
          if (_rubberRect != null)
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _RubberBandPainter(rect: _rubberRect!),
                ),
              ),
            ),
          MouseRegion(
            cursor: _cursorForMode(controller.mode),
            onHover: (e) => _onPointerHover(e.localPosition),
            onExit: (_) {
              controller.setHovered(null);
              controller.setCursorWorldPos(null);
            },
            child: Listener(
              behavior: HitTestBehavior.translucent,
              onPointerDown: (e) => _onPointerDown(e.localPosition),
              onPointerMove: (e) {
                _onPointerMove(e.localPosition);
                // Touch devices don't fire onHover but their onPointerMove
                // gives us the same data — mirror it into the ghost
                // preview so touch users get the affordance too.
                if (_isTouch) _onPointerHover(e.localPosition);
              },
              onPointerUp: (e) => _onPointerUp(e.localPosition),
            ),
          ),
        ],
      ),
    );
  }

  void _onPointerDown(Offset p) {
    final mode = controller.mode;
    // Any non-placement mode invalidates a pending placement preview.
    if (mode is! WaitingDrawingHoleMode && mode is! PlacingItemMode) {
      _pendingPlacementTap = null;
    }
    // PanMode hands all pointer events to the InteractiveViewer for pan.
    if (mode is PanMode) return;
    // Rectangle room: pointer-down starts the rect; pointer-up commits.
    if (mode is DrawingRectangleRoomMode) {
      controller.beginRectangleRoom(p);
      return;
    }
    // Trace room: each click appends a point or closes the loop.
    if (mode is TracingRoomMode) {
      controller.traceRoomTap(p);
      return;
    }
    if (mode is CalibratingMode) {
      // Calibration's first click sets point A. The second click is
      // captured separately by the calibration dialog through a
      // higher-level handler we don't wire here yet.
      controller.calibrationClick(p);
      return;
    }
    if (mode is WaitingDrawingHoleMode) {
      // Touch: first tap previews, nearby second tap commits, far tap
      // moves the preview. Mouse commits immediately.
      if (_isTouch && !_isPlacementCommitTap(p)) {
        _pendingPlacementTap = p;
        _onPointerHover(p);
        return;
      }
      _pendingPlacementTap = null;
      final hit = _painter().pickElement(p, snapDistance);
      if (hit != null && hit.kind == ElementKind.line) {
        controller.placeHole(
          lineId: hit.id,
          point: p,
          prototype: mode.holePrototype,
        );
      }
      return;
    }
    if (mode is PlacingItemMode) {
      if (_isTouch && !_isPlacementCommitTap(p)) {
        _pendingPlacementTap = p;
        _onPointerHover(p);
        return;
      }
      _pendingPlacementTap = null;
      controller.placeItem(prototype: mode.itemPrototype, point: p);
      return;
    }
    if (mode is AddingAnnotationMode) {
      if (mode.annotationKind == 'text') {
        // Create with empty text + return to Select mode so the
        // inspector's auto-focused text field gets the keyboard input.
        controller.addTextAnnotation(p);
        controller.setMode(const IdleMode());
      } else {
        // Click-drag flow: stash the start point so PointerUp can complete.
        _annotationStart = p;
      }
      return;
    }
    if (mode is IdleMode) {
      // First, see if the cursor is on a handle of a currently-selected
      // item: corner resize, then rotation. Each starts its own drag.
      final selectedItemId = controller.scene.selectedLayer.selected.items
          .cast<String?>()
          .firstWhere((_) => true, orElse: () => null);
      if (selectedItemId != null) {
        final corner = _painter().pickItemResizeHandle(
          p,
          selectedItemId,
          snapDistance + 4,
        );
        if (corner != null) {
          _resizingItemId = selectedItemId;
          _resizingCorner = corner;
          controller.beginTransientEdit();
          return;
        }
        final handleHit = _painter().pickRotationHandle(
          p,
          selectedItemId,
          snapDistance + 4,
        );
        if (handleHit) {
          _rotatingItemId = selectedItemId;
          controller.beginTransientEdit();
          return;
        }
      }
      // Otherwise tap-to-select + start matching drag for vertex/hole/item.
      final hit = _painter().pickElement(p, snapDistance);
      final shift = HardwareKeyboard.instance.isShiftPressed;
      if (hit != null) {
        if (shift) {
          controller.addToSelection(hit.kind, hit.id);
        } else {
          controller.selectElement(hit.kind, hit.id);
          if (hit.kind == ElementKind.vertex) {
            _draggingVertexId = hit.id;
            controller.beginTransientEdit();
          } else if (hit.kind == ElementKind.hole) {
            _draggingHoleId = hit.id;
            controller.beginTransientEdit();
          } else if (hit.kind == ElementKind.item) {
            _draggingItemId = hit.id;
            controller.beginTransientEdit();
          } else if (hit.kind == ElementKind.line) {
            _draggingLineId = hit.id;
            _lastDragPos = p;
            controller.beginTransientEdit();
          } else if (hit.kind == ElementKind.annotation) {
            _draggingAnnotationId = hit.id;
            _lastDragPos = p;
            controller.beginTransientEdit();
          }
        }
      } else {
        // Empty space — desktop starts a rubber-band selection;
        // touch arms a long-press timer that promotes to rubber-band
        // if the finger stays put (otherwise InteractiveViewer pans).
        if (!shift) controller.clearSelection();
        if (!_isTouch) {
          _rubberStart = p;
          setState(() => _rubberRect = Rect.fromPoints(p, p));
        } else {
          _armLongPress(p);
        }
      }
      return;
    }
    if (mode is WaitingDrawingWallMode) {
      controller.beginWall(p.dx, p.dy);
    } else if (mode is DrawingWallMode) {
      // Allow tap-tap drawing in addition to drag-to-draw.
      controller.endWall(p.dx, p.dy);
    }
  }

  FloorplanScenePainter _painter() => FloorplanScenePainter(
        scene: controller.scene,
        mode: controller.mode,
        catalog: controller.catalog,
      );

  void _onPointerMove(Offset p) {
    controller.setCursorWorldPos(p);
    // Long-press → marquee: cancel the timer the moment the finger
    // moves more than a few pixels (it's a pan, not a hold).
    if (_longPressTimer != null && _longPressDownPos != null) {
      if ((p - _longPressDownPos!).distance > _kLongPressMoveTolerance) {
        _cancelLongPress();
      }
    }
    final mode = controller.mode;
    if (mode is DrawingRectangleRoomMode) {
      controller.updateRectangleRoom(p);
      return;
    }
    if (mode is DrawingWallMode) {
      controller.dragWallTo(
        p.dx,
        p.dy,
        mask: _snapMask(),
        ortho: _orthoActive(),
      );
    } else if (_resizingItemId != null) {
      controller.dragItemResizeTo(_resizingItemId!, p, _resizingCorner);
    } else if (_rotatingItemId != null) {
      final item = controller.scene.selectedLayer.items[_rotatingItemId!];
      if (item == null) return;
      // Atan2 from item center to cursor, offset by π/2 so the handle
      // (which renders straight up from center) reads as "rotation = 0".
      final angle = (p - Offset(item.x, item.y)).direction + math.pi / 2;
      controller.dragItemRotation(
        _rotatingItemId!,
        angle,
        bypassSnap: HardwareKeyboard.instance.isShiftPressed,
      );
    } else if (_draggingVertexId != null) {
      controller.dragVertexTo(_draggingVertexId!, p, mask: _snapMask());
    } else if (_draggingHoleId != null) {
      controller.dragHoleTo(_draggingHoleId!, p);
    } else if (_draggingItemId != null) {
      controller.dragItemTo(_draggingItemId!, p, mask: _snapMask());
    } else if (_draggingLineId != null && _lastDragPos != null) {
      final delta = p - _lastDragPos!;
      controller.dragLineBy(_draggingLineId!, delta);
      _lastDragPos = p;
    } else if (_draggingAnnotationId != null && _lastDragPos != null) {
      final delta = p - _lastDragPos!;
      controller.dragAnnotationBy(_draggingAnnotationId!, delta);
      _lastDragPos = p;
    } else if (_rubberStart != null) {
      setState(() => _rubberRect = Rect.fromPoints(_rubberStart!, p));
    }
  }

  /// Arm the long-press timer for touch marquee. If still armed when
  /// the timer fires, promote the gesture to a rubber-band selection
  /// anchored at the original down position.
  void _armLongPress(Offset p) {
    _cancelLongPress();
    _longPressDownPos = p;
    _longPressTimer = Timer(_kLongPressDuration, () {
      _longPressTimer = null;
      // Only promote if we're still in IdleMode and not already
      // dragging something else (defensive — _isDragging should be
      // false since the down hit empty space).
      if (controller.mode is! IdleMode || _isDragging) return;
      final start = _longPressDownPos;
      if (start == null) return;
      _rubberStart = start;
      setState(() => _rubberRect = Rect.fromPoints(start, start));
    });
  }

  void _cancelLongPress() {
    _longPressTimer?.cancel();
    _longPressTimer = null;
    _longPressDownPos = null;
  }

  /// True when [p] is close enough to the previously-armed placement
  /// preview to count as a "commit" tap. A first tap (no prior preview)
  /// or a tap far from the prior preview returns false — caller should
  /// treat that as a re-preview.
  bool _isPlacementCommitTap(Offset p) {
    final prior = _pendingPlacementTap;
    if (prior == null) return false;
    return (p - prior).distance <= snapDistance + 8;
  }

  @override
  void dispose() {
    _cancelLongPress();
    super.dispose();
  }

  /// Honor Alt-to-disable-snapping (matches react-planner / Figma
  /// convention) plus the on-screen "no snap" toggle for touch devices.
  SnapMask _snapMask() {
    final off = HardwareKeyboard.instance.isAltPressed ||
        controller.snapDisabled;
    return off ? SnapMask.disabled() : SnapMask.all();
  }

  bool _orthoActive() =>
      HardwareKeyboard.instance.isShiftPressed || controller.orthoLock;

  /// System cursor that signals the active tool's intent. Drawing tools
  /// get a precise crosshair; placement modes get a pointer; pan gets a
  /// hand; select stays as the default arrow.
  MouseCursor _cursorForMode(EditorMode mode) {
    if (mode is PanMode) return SystemMouseCursors.grab;
    if (mode is WaitingDrawingWallMode ||
        mode is DrawingWallMode ||
        mode is DrawingRectangleRoomMode ||
        mode is TracingRoomMode ||
        mode is CalibratingMode) {
      return SystemMouseCursors.precise;
    }
    if (mode is WaitingDrawingHoleMode ||
        mode is PlacingItemMode ||
        mode is AddingAnnotationMode) {
      return SystemMouseCursors.click;
    }
    return SystemMouseCursors.basic;
  }

  /// Update the controller's hover state on every mouse move so the
  /// painter can highlight what the next click will hit. In placement
  /// modes (door/window) we restrict hover to walls so the visual
  /// affordance matches the action that actually fires.
  void _onPointerHover(Offset p) {
    controller.setCursorWorldPos(p);
    final mode = controller.mode;
    // Ghost preview for placement modes — paint the to-be-placed
    // element at 50% opacity so users see exactly where the next click
    // will commit it.
    if (mode is WaitingDrawingHoleMode) {
      final hit = _painter().pickElement(p, snapDistance);
      if (hit != null && hit.kind == ElementKind.line) {
        // Snap the ghost to the wall.
        final layer = controller.scene.selectedLayer;
        final line = layer.lines[hit.id];
        final a = line == null ? null : layer.vertices[line.vertexIds[0]];
        final b = line == null ? null : layer.vertices[line.vertexIds[1]];
        if (a != null && b != null) {
          final aP = Offset(a.x, a.y);
          final bP = Offset(b.x, b.y);
          final dir = bP - aP;
          final len = dir.distance;
          if (len > 0.5) {
            // Project p onto the wall.
            final t = (((p - aP).dx * dir.dx + (p - aP).dy * dir.dy) /
                    (len * len))
                .clamp(0.0, 1.0);
            final projected = aP + dir * t;
            final angle = math.atan2(dir.dy, dir.dx);
            controller.setGhostPreview((
              prototype: mode.holePrototype,
              kind: ElementKind.hole,
              point: projected,
              rotation: angle,
            ));
            controller.setHovered(hit);
            return;
          }
        }
      }
      controller.setGhostPreview(null);
      controller.setHovered(null);
      return;
    }
    if (mode is PlacingItemMode) {
      controller.setGhostPreview((
        prototype: mode.itemPrototype,
        kind: ElementKind.item,
        point: p,
        rotation: 0,
      ));
      return;
    }
    // Generic hover for selection feedback.
    controller.setGhostPreview(null);
    final hit = _painter().pickElement(p, snapDistance);
    if (hit == null) {
      controller.setHovered(null);
      return;
    }
    controller.setHovered(hit);
  }

  void _onPointerUp(Offset p) {
    _cancelLongPress();
    final mode = controller.mode;
    if (mode is DrawingRectangleRoomMode) {
      controller.commitRectangleRoom();
      return;
    }
    if (mode is DrawingWallMode) {
      controller.endWall(
        p.dx,
        p.dy,
        mask: _snapMask(),
        ortho: _orthoActive(),
      );
      return;
    }
    if (_isDragging) {
      controller.endTransientEdit();
      _draggingItemId = null;
      _draggingVertexId = null;
      _draggingHoleId = null;
      _draggingLineId = null;
      _draggingAnnotationId = null;
      _resizingItemId = null;
      _lastDragPos = null;
      _rotatingItemId = null;
      return;
    }
    if (_rubberRect != null) {
      final rect = _rubberRect!;
      final inside = _elementsInRect(controller.scene.selectedLayer, rect);
      final shift = HardwareKeyboard.instance.isShiftPressed;
      if (shift) {
        // Additive: union with existing.
        final prior = controller.scene.selectedLayer.selected;
        controller.selectMany(ElementsSet(
          vertices: {...prior.vertices, ...inside.vertices},
          lines: {...prior.lines, ...inside.lines},
          holes: {...prior.holes, ...inside.holes},
          areas: {...prior.areas, ...inside.areas},
          items: {...prior.items, ...inside.items},
          annotations: {...prior.annotations, ...inside.annotations},
        ));
      } else {
        controller.selectMany(inside);
      }
      setState(() {
        _rubberRect = null;
        _rubberStart = null;
      });
      return;
    }
    if (mode is AddingAnnotationMode && _annotationStart != null) {
      final start = _annotationStart!;
      _annotationStart = null;
      if ((p - start).distance < 4) {
        controller.setMode(const IdleMode());
        return;
      }
      if (mode.annotationKind == 'arrow') {
        controller.addArrowAnnotation(start, p);
      } else if (mode.annotationKind == 'dimension') {
        controller.addDimensionAnnotation(start, p);
      }
      controller.setMode(const IdleMode());
    }
  }
}

/// Determine which elements lie fully inside [rect], using a centroid /
/// endpoint test per kind. Walls require both endpoints inside; holes and
/// items use their visual center; annotations use a representative point
/// (text origin, midpoint of arrow/dimension).
ElementsSet _elementsInRect(Layer layer, Rect rect) {
  final vertices = <String>{};
  final lines = <String>{};
  final holes = <String>{};
  final items = <String>{};
  final annotations = <String>{};

  layer.vertices.forEach((id, v) {
    if (rect.contains(Offset(v.x, v.y))) vertices.add(id);
  });
  layer.lines.forEach((id, line) {
    final a = layer.vertices[line.vertexIds[0]];
    final b = layer.vertices[line.vertexIds[1]];
    if (a == null || b == null) return;
    if (rect.contains(Offset(a.x, a.y)) && rect.contains(Offset(b.x, b.y))) {
      lines.add(id);
    }
  });
  layer.holes.forEach((id, hole) {
    final line = layer.lines[hole.lineId];
    if (line == null) return;
    final a = layer.vertices[line.vertexIds[0]];
    final b = layer.vertices[line.vertexIds[1]];
    if (a == null || b == null) return;
    final aP = Offset(a.x, a.y);
    final bP = Offset(b.x, b.y);
    final wallLen = (bP - aP).distance;
    if (wallLen < 0.01) return;
    final dir = (bP - aP) / wallLen;
    final center = aP + dir * (hole.offset * wallLen);
    if (rect.contains(center)) holes.add(id);
  });
  layer.items.forEach((id, item) {
    if (rect.contains(Offset(item.x, item.y))) items.add(id);
  });
  layer.annotations.forEach((id, ann) {
    Offset? pos;
    if (ann is TextAnnotation) {
      pos = ann.offset;
    } else if (ann is ArrowAnnotation) {
      pos = (ann.from + ann.to) / 2;
    } else if (ann is DimensionAnnotation) {
      pos = (ann.from + ann.to) / 2;
    }
    if (pos != null && rect.contains(pos)) annotations.add(id);
  });

  return ElementsSet(
    vertices: vertices,
    lines: lines,
    holes: holes,
    items: items,
    annotations: annotations,
  );
}

class _RubberBandPainter extends CustomPainter {
  final Rect rect;
  const _RubberBandPainter({required this.rect});

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      rect,
      Paint()..color = const Color(0x111976D2),
    );
    canvas.drawRect(
      rect,
      Paint()
        ..color = AppColors.info
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(_RubberBandPainter old) => old.rect != rect;
}
