import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'dart:ui' show Offset, Rect;

import '../../models/floorplan/annotation.dart';
import '../../models/floorplan/area.dart';
import '../../models/floorplan/editor_mode.dart';
import '../../models/floorplan/element_kind.dart';
import '../../models/floorplan/elements_set.dart';
import '../../models/floorplan/hole.dart';
import '../../models/floorplan/layer.dart';
import '../../models/floorplan/line.dart';
import '../../models/floorplan/scene.dart';
import '../../models/floorplan/vertex.dart';
import '../../utils/floorplan/id_broker.dart';
import '../../utils/floorplan/snap.dart';
import '../../utils/floorplan/snap_scene.dart';
import '../../utils/floorplan/units.dart';
import 'catalog.dart';
import '../../models/ai/ai_floorplan_edit.dart';
import 'ai_edit_to_scene.dart';
import 'class/area_ops.dart';
import 'class/hole_ops.dart';
import 'class/item_ops.dart';
import 'class/room_ops.dart';
import 'class/vertex_ops.dart';
import 'class/wall_ops.dart';

/// Owns the in-memory editor state for a single floorplan scene and exposes
/// it to the widget tree as a [ChangeNotifier].
///
/// The controller is the single mutator: widgets call `beginWall`, `dragTo`,
/// `endWall`, `undo`, etc., never edit the scene directly. Each public
/// mutating method:
/// 1. computes a new [Scene] via the per-class ops (see `class/wall_ops.dart`),
/// 2. pushes the previous scene onto the undo stack,
/// 3. clears the redo stack,
/// 4. flips the dirty flag,
/// 5. notifies listeners.
///
/// A bounded snapshot list (cap 50) is the cheapest correct undo for a model
/// this small and is what we picked over react-planner's diff-based history.
class FloorplanEditorController extends ChangeNotifier {
  FloorplanEditorController({
    required Scene scene,
    IdBroker? ids,
    int undoLimit = 50,
    Catalog? catalog,
  })  : _scene = scene,
        _ids = ids ?? IdBroker(),
        _undoLimit = undoLimit,
        _catalog = catalog ?? defaultCatalog;

  Scene _scene;
  EditorMode _mode = const IdleMode();
  final IdBroker _ids;
  final int _undoLimit;
  final Catalog _catalog;

  Catalog get catalog => _catalog;

  ({Offset point, SnapKind kind, String label})? _activeSnap;

  /// Snap target currently latched onto by an in-flight drag. Carries
  /// the snap kind + label so the painter can render kind-specific
  /// chrome ("Endpoint", "On wall", "Grid"). Null when no snap fires
  /// (or when the user is holding Alt / has the no-snap toggle on).
  ({Offset point, SnapKind kind, String label})? get activeSnap =>
      _activeSnap;

  ({ElementKind kind, String id})? _hovered;

  /// Element under the cursor during hover (mouse, web, desktop). Used by
  /// the painter to draw a halo so the user can see what the next click
  /// will hit — especially important in placement modes (door/window).
  ({ElementKind kind, String id})? get hoveredElement => _hovered;

  void setHovered(({ElementKind kind, String id})? hovered) {
    if (_hovered == hovered) return;
    _hovered = hovered;
    notifyListeners();
  }

  Offset? _cursorWorldPos;
  double _viewportScale = 1.0;

  /// Cursor position in scene coords. Updated by the canvas on every
  /// hover/move; null when the cursor is outside the canvas. Status bar
  /// reads this so users always know where they are.
  Offset? get cursorWorldPos => _cursorWorldPos;

  /// Current InteractiveViewer zoom factor (1.0 = 100%). Updated by the
  /// canvas whenever the transform changes. Status bar shows it as a %.
  double get viewportScale => _viewportScale;

  void setCursorWorldPos(Offset? pos) {
    if (_cursorWorldPos == pos) return;
    _cursorWorldPos = pos;
    notifyListeners();
  }

  void setViewportScale(double scale) {
    if ((_viewportScale - scale).abs() < 0.001) return;
    _viewportScale = scale;
    notifyListeners();
  }

  bool _orthoLock = false;
  bool _snapDisabled = false;

  /// Persistent ortho-lock toggle. On desktop, holding Shift overrides it
  /// transiently; on touch, this is the only way to lock to 45° angles.
  bool get orthoLock => _orthoLock;

  /// Persistent snap-disable toggle. On desktop, holding Alt overrides it
  /// transiently; on touch, this is the only way to bypass snapping.
  bool get snapDisabled => _snapDisabled;

  void setOrthoLock(bool value) {
    if (_orthoLock == value) return;
    _orthoLock = value;
    notifyListeners();
  }

  void setSnapDisabled(bool value) {
    if (_snapDisabled == value) return;
    _snapDisabled = value;
    notifyListeners();
  }
  final List<Scene> _undo = [];
  final List<Scene> _redo = [];
  bool _dirty = false;

  Scene get scene => _scene;
  EditorMode get mode => _mode;
  IdBroker get ids => _ids;
  bool get dirty => _dirty;
  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;

  /// Replace the scene wholesale (e.g. on initial load or remote refresh).
  /// Resets undo/redo and the dirty flag.
  void replaceScene(Scene next) {
    _scene = next;
    _mode = const IdleMode();
    _undo.clear();
    _redo.clear();
    _dirty = false;
    notifyListeners();
  }

  void markSaved() {
    _dirty = false;
    notifyListeners();
  }

  void setMode(EditorMode mode) {
    if (_mode.runtimeType == mode.runtimeType && identical(_mode, mode)) return;
    _mode = mode;
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Wall drawing
  // ---------------------------------------------------------------------------

  void beginWall(double x, double y) {
    final result = WallOps.begin(scene: _scene, ids: _ids, x: x, y: y);
    _commit(result.scene, mode: result.mode);
  }

  void dragWallTo(double x, double y, {SnapMask? mask, bool ortho = false}) {
    final m = _mode;
    if (m is! DrawingWallMode) return;
    final snapped = _maybeSnap(
      Offset(x, y),
      excludedVertexIds: {m.startVertexId, m.endVertexId},
      excludedLineIds: {m.pendingLineId},
      mask: mask,
    );
    final constrained = ortho ? _applyOrthoLock(m, snapped) : snapped;
    // Drag is high-frequency: don't push undo for every cursor delta — we
    // already pushed in beginWall, and we'll push again in endWall if the
    // wall is committed. So this is a "transient mutation" that bypasses
    // the undo stack.
    _scene = WallOps.update(
      scene: _scene,
      mode: m,
      x: constrained.dx,
      y: constrained.dy,
    );
    notifyListeners();
  }

  void endWall(double x, double y, {SnapMask? mask, bool ortho = false}) {
    final m = _mode;
    if (m is! DrawingWallMode) return;
    final snapped = _maybeSnap(
      Offset(x, y),
      excludedVertexIds: {m.startVertexId, m.endVertexId},
      excludedLineIds: {m.pendingLineId},
      mask: mask,
    );
    final constrained = ortho ? _applyOrthoLock(m, snapped) : snapped;
    final result = WallOps.end(
      scene: _scene,
      mode: m,
      x: constrained.dx,
      y: constrained.dy,
    );
    // After commit, look for any walls the new wall crossed and split
    // both at each intersection (X-crossings only). Then recompute auto-
    // areas so the just-formed rooms appear.
    var nextScene = WallOps.splitAtCrossings(
      scene: result.scene,
      ids: _ids,
      newLineId: m.pendingLineId,
    );
    nextScene = AreaOps.recompute(scene: nextScene, ids: _ids);
    _scene = nextScene;
    // Stay armed for the next wall so chained drawing doesn't require
    // re-clicking the Wall tool. Esc / V / H exits.
    _mode = const WaitingDrawingWallMode();
    _activeSnap = null;
    _ghostPreview = null;
    _dirty = true;
    notifyListeners();
  }

  /// Constrain the in-flight wall to a multiple of 45° from its start
  /// vertex. Distance from the start is preserved. Used when Shift is
  /// held during wall draw (Figma/Sketch ortho convention).
  Offset _applyOrthoLock(DrawingWallMode m, Offset cursor) {
    final start = _scene.selectedLayer.vertices[m.startVertexId];
    if (start == null) return cursor;
    final dx = cursor.dx - start.x;
    final dy = cursor.dy - start.y;
    final dist = math.sqrt(dx * dx + dy * dy);
    if (dist < 0.5) return cursor;
    final rawAngle = math.atan2(dy, dx);
    const step = math.pi / 4; // 45°
    final snappedAngle = (rawAngle / step).round() * step;
    return Offset(
      start.x + math.cos(snappedAngle) * dist,
      start.y + math.sin(snappedAngle) * dist,
    );
  }

  /// Project a cursor point through the current scene's snap index.
  /// Updates [_activeSnap] for the painter; returns the snapped point (or
  /// the raw cursor if no snap fires / mask is empty).
  Offset _maybeSnap(
    Offset cursor, {
    Set<String> excludedVertexIds = const {},
    Set<String> excludedLineIds = const {},
    SnapMask? mask,
  }) {
    final activeMask = mask ?? SnapMask.all();
    if (activeMask.enabled.isEmpty) {
      _activeSnap = null;
      return cursor;
    }
    final snaps = sceneSnaps(
      _scene,
      excludedVertexIds: excludedVertexIds,
      excludedLineIds: excludedLineIds,
    );
    final hit = nearestSnap(snaps, cursor, mask: activeMask);
    if (hit == null) {
      _activeSnap = null;
      return cursor;
    }
    _activeSnap = (
      point: hit.point,
      kind: hit.snap.kind,
      label: _labelForSnap(hit.snap.kind),
    );
    return hit.point;
  }

  static String _labelForSnap(SnapKind kind) => switch (kind) {
        SnapKind.vertex => 'Endpoint',
        SnapKind.lineSegment => 'On wall',
        SnapKind.line => 'Aligned',
        SnapKind.grid => 'Grid',
      };

  void cancelDrawing() {
    final m = _mode;
    if (m is DrawingWallMode) {
      // Roll back to the snapshot taken at beginWall, then re-arm so
      // the user can keep drawing if Esc was meant to cancel just this
      // segment, not exit the tool. (Pressing Esc again in
      // WaitingDrawingWallMode exits to Idle.)
      if (_undo.isNotEmpty) {
        _scene = _undo.removeLast();
      } else {
        _scene = WallOps.cancel(scene: _scene, mode: m);
      }
      _mode = const WaitingDrawingWallMode();
      notifyListeners();
    } else if (m is WaitingDrawingWallMode ||
        m is WaitingDrawingHoleMode ||
        m is PlacingItemMode ||
        m is AddingAnnotationMode) {
      _mode = const IdleMode();
      notifyListeners();
    }
  }

  // ---------------------------------------------------------------------------
  // Holes (doors / windows)
  // ---------------------------------------------------------------------------

  /// Drop a door/window onto [lineId] at the position closest to [point].
  void placeHole({
    required String lineId,
    required Offset point,
    required String prototype,
  }) {
    final r = HoleOps.placeOnWall(
      scene: _scene,
      ids: _ids,
      lineId: lineId,
      point: point,
      prototype: prototype,
    );
    if (r == null) return;
    _commit(r.scene);
    // Stay in the WaitingDrawingHole mode so the user can drop another.
  }

  // ---------------------------------------------------------------------------
  // Selection + property edits
  // ---------------------------------------------------------------------------

  void selectElement(ElementKind kind, String id) {
    final layer = _scene.selectedLayer;
    final next = ElementsSet.empty.withSelection(kind, id);
    _scene = _scene.withSelectedLayer(layer.copyWith(selected: next));
    notifyListeners();
  }

  /// Replace selection wholesale (used by rubber-band).
  void selectMany(ElementsSet next) {
    final layer = _scene.selectedLayer;
    _scene = _scene.withSelectedLayer(layer.copyWith(selected: next));
    notifyListeners();
  }

  /// Add a single element to the existing selection (Shift-click pattern).
  void addToSelection(ElementKind kind, String id) {
    final layer = _scene.selectedLayer;
    _scene = _scene.withSelectedLayer(
      layer.copyWith(selected: layer.selected.withSelection(kind, id)),
    );
    notifyListeners();
  }

  void clearSelection() {
    final layer = _scene.selectedLayer;
    if (layer.selected.isEmpty) return;
    _scene = _scene.withSelectedLayer(
      layer.copyWith(selected: ElementsSet.empty),
    );
    notifyListeners();
  }

  void updateLineThickness(String lineId, double thickness) {
    final layer = _scene.selectedLayer;
    final line = layer.lines[lineId];
    if (line == null) return;
    final lines = Map<String, FloorLine>.from(layer.lines);
    lines[lineId] = line.copyWith(thickness: thickness);
    _commit(_scene.withSelectedLayer(layer.copyWith(lines: lines)));
  }

  /// Set the per-wall height override in cm. Pass `null` to clear the
  /// override so the wall falls back to the scene's default ceiling
  /// height. No-ops when the requested value matches the current state
  /// (so dragging a slider that lands on the same value doesn't generate
  /// undo entries).
  void setLineHeight(String lineId, double? heightCm) {
    final layer = _scene.selectedLayer;
    final line = layer.lines[lineId];
    if (line == null) return;
    if (line.heightCm == heightCm) return;
    final lines = Map<String, FloorLine>.from(layer.lines);
    lines[lineId] = line.copyWith(
      heightCm: heightCm,
      clearHeight: heightCm == null,
    );
    _commit(_scene.withSelectedLayer(layer.copyWith(lines: lines)));
  }

  /// Set the scene-wide default ceiling height in cm. Walls that don't
  /// have a per-wall override pick up this value in the 3D preview and
  /// in volume calculations.
  void setSceneCeilingHeight(double heightCm) {
    if (_scene.ceilingHeightCm == heightCm) return;
    _commit(_scene.copyWith(ceilingHeightCm: heightCm));
  }

  void updateHoleSize(
    String holeId, {
    double? width,
    double? height,
  }) {
    final layer = _scene.selectedLayer;
    final hole = layer.holes[holeId];
    if (hole == null) return;
    final holes = Map<String, Hole>.from(layer.holes);
    holes[holeId] = hole.copyWith(width: width, height: height);
    _commit(_scene.withSelectedLayer(layer.copyWith(holes: holes)));
  }

  /// Set the sill height (floor offset) of a hole in cm. Doors are
  /// usually 0; window sills typically sit 90–110 cm above the floor.
  void updateHoleAltitude(String holeId, double altitude) {
    final layer = _scene.selectedLayer;
    final hole = layer.holes[holeId];
    if (hole == null) return;
    if (hole.altitude == altitude) return;
    final holes = Map<String, Hole>.from(layer.holes);
    holes[holeId] = hole.copyWith(altitude: altitude);
    _commit(_scene.withSelectedLayer(layer.copyWith(holes: holes)));
  }

  void updateAreaName(String areaId, String name) {
    final layer = _scene.selectedLayer;
    final area = layer.areas[areaId];
    if (area == null) return;
    final areas = Map<String, Area>.from(layer.areas);
    areas[areaId] = area.copyWith(
      properties: {...area.properties, 'name': name},
    );
    _commit(_scene.withSelectedLayer(layer.copyWith(areas: areas)));
  }

  void deleteSelectedHole() {
    final selected = _scene.selectedLayer.selected.holes;
    if (selected.isEmpty) return;
    var s = _scene;
    for (final id in selected) {
      s = HoleOps.delete(scene: s, holeId: id);
    }
    final layer = s.selectedLayer;
    _commit(s.withSelectedLayer(layer.copyWith(selected: ElementsSet.empty)));
  }

  /// Delete every selected wall (cascading hole removal + vertex
  /// back-references) and recompute auto-areas.
  void deleteSelectedWalls() {
    final selected = _scene.selectedLayer.selected.lines;
    if (selected.isEmpty) return;
    var s = _scene;
    for (final lineId in selected) {
      var layer = s.selectedLayer;
      final line = layer.lines[lineId];
      if (line == null) continue;
      // Remove holes hosted by this wall first.
      for (final holeId in [...line.holeIds]) {
        s = HoleOps.delete(scene: s, holeId: holeId);
      }
      layer = s.selectedLayer;
      // Drop the line + detach back-references on its vertices.
      final lines = Map<String, FloorLine>.from(layer.lines)..remove(lineId);
      var nextLayer = layer.copyWith(lines: lines);
      for (final vid in line.vertexIds) {
        nextLayer = VertexOps.detach(
          layer: nextLayer,
          vertexId: vid,
          lineId: lineId,
        );
      }
      s = s.withSelectedLayer(nextLayer);
    }
    s = AreaOps.recompute(scene: s, ids: _ids);
    final layer = s.selectedLayer;
    _commit(s.withSelectedLayer(layer.copyWith(selected: ElementsSet.empty)));
  }

  /// Delete whatever's selected — walls, holes, items, annotations. Used
  /// by the global Delete/Backspace keyboard shortcut so users don't have
  /// to think about which inspector is open.
  void deleteSelected() {
    final sel = _scene.selectedLayer.selected;
    if (sel.isEmpty) return;
    if (sel.lines.isNotEmpty) deleteSelectedWalls();
    if (sel.holes.isNotEmpty) deleteSelectedHole();
    if (sel.items.isNotEmpty || sel.annotations.isNotEmpty) {
      _deleteItemsAndAnnotations();
    }
  }

  void _deleteItemsAndAnnotations() {
    final sel = _scene.selectedLayer.selected;
    var s = _scene;
    for (final id in sel.items) {
      s = ItemOps.delete(scene: s, itemId: id);
    }
    if (sel.annotations.isNotEmpty) {
      final layer = s.selectedLayer;
      final next = Map<String, Annotation>.from(layer.annotations);
      for (final id in sel.annotations) {
        next.remove(id);
      }
      s = s.withSelectedLayer(layer.copyWith(annotations: next));
    }
    final layer = s.selectedLayer;
    _commit(s.withSelectedLayer(layer.copyWith(selected: ElementsSet.empty)));
  }


  // ---------------------------------------------------------------------------
  // Drag interactions — vertex / hole / item / item-rotation
  //
  // Common pattern:
  //   1. Caller calls [beginTransientEdit] on pointer-down (pushes the
  //      pre-drag scene onto the undo stack so undo restores it).
  //   2. Caller calls a `dragXxx` method on every pointer-move (transient
  //      mutation, no undo entry).
  //   3. Caller calls [endTransientEdit] on pointer-up (just flips the
  //      dirty flag + clears redo; no extra undo entry).
  // ---------------------------------------------------------------------------

  /// Push the current scene to undo BEFORE a transient drag begins, so
  /// the user can undo back to the pre-drag state.
  void beginTransientEdit() {
    _undo.add(_scene);
    if (_undo.length > _undoLimit) _undo.removeAt(0);
    _redo.clear();
  }

  /// Finish a transient drag — no extra undo entry needed (already pushed
  /// at the start). Marks dirty + notifies.
  void endTransientEdit() {
    _activeSnap = null;
    _ghostPreview = null;
    _dirty = true;
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Ghost preview — set on hover in placement modes; painter renders
  // the about-to-place element at 50% opacity so users see where the
  // next click will land. Distinct from activeSnap (which is just a
  // snap-target marker, not a per-element preview).
  // ---------------------------------------------------------------------------

  ({String prototype, ElementKind kind, Offset point, double rotation})?
      _ghostPreview;

  ({String prototype, ElementKind kind, Offset point, double rotation})?
      get ghostPreview => _ghostPreview;

  void setGhostPreview(
    ({String prototype, ElementKind kind, Offset point, double rotation})?
        preview,
  ) {
    if (_ghostPreview == preview) return;
    _ghostPreview = preview;
    notifyListeners();
  }

  /// Door swing flip — rotates a door ghost or selected door by 180°.
  void flipSelectedDoor() {
    final sel = _scene.selectedLayer.selected.holes;
    if (sel.isEmpty) return;
    final layer = _scene.selectedLayer;
    final holes = Map.of(layer.holes);
    var changed = false;
    for (final id in sel) {
      final h = layer.holes[id];
      if (h == null || h.prototype != 'door') continue;
      // Door swing flip: store as a property for now, picked up by the
      // painter. Defaults to false; toggle.
      final flipped = (h.properties['flipped'] as bool?) ?? false;
      holes[id] = h.copyWith(
        properties: {...h.properties, 'flipped': !flipped},
      );
      changed = true;
    }
    if (!changed) return;
    _commit(_scene.withSelectedLayer(layer.copyWith(holes: holes)));
  }

  // -- Items ------------------------------------------------------------------

  void placeItem({
    required String prototype,
    required Offset point,
  }) {
    final r = ItemOps.place(
      scene: _scene,
      ids: _ids,
      catalog: _catalog,
      prototype: prototype,
      x: point.dx,
      y: point.dy,
    );
    if (r == null) return;
    _commit(r.scene);
  }

  void dragItemTo(String itemId, Offset point, {SnapMask? mask}) {
    final snapped = _maybeSnap(point, mask: mask);
    _scene = ItemOps.moveTo(
      scene: _scene,
      itemId: itemId,
      x: snapped.dx,
      y: snapped.dy,
    );
    notifyListeners();
  }

  /// Back-compat for callers still using the older API name. Identical to
  /// [dragItemTo] without a snap mask.
  void moveItem(String itemId, Offset point) =>
      dragItemTo(itemId, point);

  void rotateItem(String itemId, double rotation) {
    _scene = ItemOps.rotateTo(
      scene: _scene,
      itemId: itemId,
      rotation: rotation,
    );
    notifyListeners();
  }

  /// Inspector-driven rotation set (degrees in, snap-aware). Pushes one
  /// undo entry — used by the property inspector slider.
  void setItemRotationDegrees(String itemId, double degrees) {
    final r = degrees * math.pi / 180;
    _commit(ItemOps.rotateTo(
      scene: _scene,
      itemId: itemId,
      rotation: _snapRotation(r),
    ));
  }

  void resizeItem(String itemId, {double? width, double? height}) {
    _commit(ItemOps.resize(
      scene: _scene,
      itemId: itemId,
      width: width,
      height: height,
    ));
  }

  /// Drag-resize an item from a corner handle. [point] is the cursor
  /// in scene coords; [corner] is the index returned by
  /// `pickItemResizeHandle` (0=TL, 1=TR, 2=BR, 3=BL in item-local
  /// space). Pins the OPPOSITE corner so the dragged corner tracks
  /// the cursor — standard CAD UX. Rotation-aware.
  void dragItemResizeTo(String itemId, Offset point, int corner) {
    final item = _scene.selectedLayer.items[itemId];
    if (item == null) return;
    // Convert cursor into item-local frame.
    final dx = point.dx - item.x;
    final dy = point.dy - item.y;
    final cos = math.cos(-item.rotation);
    final sin = math.sin(-item.rotation);
    final localCursorX = dx * cos - dy * sin;
    final localCursorY = dx * sin + dy * cos;

    // Anchor (opposite corner) in item-local frame: flip both signs
    // of the dragged corner. Corners: 0=(-,-) 1=(+,-) 2=(+,+) 3=(-,+).
    final dragSignX = (corner == 1 || corner == 2) ? 1.0 : -1.0;
    final dragSignY = (corner == 2 || corner == 3) ? 1.0 : -1.0;
    final hw = item.width / 2;
    final hh = item.height / 2;
    final anchorLocalX = -dragSignX * hw;
    final anchorLocalY = -dragSignY * hh;

    final newW = (localCursorX - anchorLocalX).abs().clamp(20.0, 800.0);
    final newH = (localCursorY - anchorLocalY).abs().clamp(20.0, 800.0);

    // New center in local frame is the midpoint of cursor + anchor.
    final newCenterLocalX = (localCursorX + anchorLocalX) / 2;
    final newCenterLocalY = (localCursorY + anchorLocalY) / 2;

    // Convert center back to world (rotate by +rotation).
    final cosF = math.cos(item.rotation);
    final sinF = math.sin(item.rotation);
    final newCenterX =
        item.x + newCenterLocalX * cosF - newCenterLocalY * sinF;
    final newCenterY =
        item.y + newCenterLocalX * sinF + newCenterLocalY * cosF;

    var s = ItemOps.resize(
      scene: _scene,
      itemId: itemId,
      width: newW,
      height: newH,
    );
    s = ItemOps.moveTo(
      scene: s,
      itemId: itemId,
      x: newCenterX,
      y: newCenterY,
    );
    _scene = s;
    notifyListeners();
  }

  /// Replace a transient drag-rotation. Snaps to the nearest 15° / 45° /
  /// 90° within ±7° unless [bypassSnap] is true (Shift held).
  void dragItemRotation(
    String itemId,
    double rotation, {
    bool bypassSnap = false,
  }) {
    final r = bypassSnap ? rotation : _snapRotation(rotation);
    rotateItem(itemId, r);
  }

  static double _snapRotation(double r) {
    const tolDeg = 7.0;
    const tolRad = tolDeg * math.pi / 180;
    // Common increments: 0, 15, 30, 45, 60, 75, 90, … through 360.
    for (var deg = 0; deg <= 360; deg += 15) {
      final target = deg * math.pi / 180;
      // Compare angles modulo 2π.
      final diff = ((r - target + math.pi) % (2 * math.pi)) - math.pi;
      if (diff.abs() < tolRad) return target;
    }
    return r;
  }

  // Back-compat shim — old tests/widgets called commitItemMove/commitVertexMove.
  // Forwards to the new single-name commit.
  void commitItemMove() => endTransientEdit();

  // -- Vertices ---------------------------------------------------------------

  void dragVertexTo(String vertexId, Offset point, {SnapMask? mask}) {
    final v = _scene.selectedLayer.vertices[vertexId];
    if (v == null) return;
    final snapped = _maybeSnap(
      point,
      excludedVertexIds: {vertexId},
      mask: mask,
    );
    final layer = _scene.selectedLayer;
    final vertices = Map.of(layer.vertices);
    vertices[vertexId] = v.copyWith(x: snapped.dx, y: snapped.dy);
    _scene = _scene.withSelectedLayer(layer.copyWith(vertices: vertices));
    notifyListeners();
  }

  // -- Holes ------------------------------------------------------------------

  void dragHoleTo(String holeId, Offset point) {
    _scene = HoleOps.moveAlong(scene: _scene, holeId: holeId, point: point);
    notifyListeners();
  }

  /// Translate an annotation by [delta]. Text uses (x,y); arrow and
  /// dimension translate both endpoints.
  void dragAnnotationBy(String id, Offset delta) {
    final layer = _scene.selectedLayer;
    final ann = layer.annotations[id];
    if (ann == null) return;
    Annotation next;
    if (ann is TextAnnotation) {
      next = ann.copyWith(x: ann.x + delta.dx, y: ann.y + delta.dy);
    } else if (ann is ArrowAnnotation) {
      next = ann.copyWith(
        fromX: ann.fromX + delta.dx,
        fromY: ann.fromY + delta.dy,
        toX: ann.toX + delta.dx,
        toY: ann.toY + delta.dy,
      );
    } else if (ann is DimensionAnnotation) {
      next = ann.copyWith(
        fromX: ann.fromX + delta.dx,
        fromY: ann.fromY + delta.dy,
        toX: ann.toX + delta.dx,
        toY: ann.toY + delta.dy,
      );
    } else {
      return;
    }
    final annotations = Map<String, Annotation>.from(layer.annotations);
    annotations[id] = next;
    _scene = _scene.withSelectedLayer(layer.copyWith(annotations: annotations));
    notifyListeners();
  }

  /// Translate every endpoint of [lineId] by [delta]. Connected walls
  /// follow because they share vertices.
  void dragLineBy(String lineId, Offset delta) {
    final layer = _scene.selectedLayer;
    final line = layer.lines[lineId];
    if (line == null) return;
    final vertices = Map<String, Vertex>.from(layer.vertices);
    for (final vid in line.vertexIds) {
      final v = vertices[vid];
      if (v == null) continue;
      vertices[vid] = v.copyWith(x: v.x + delta.dx, y: v.y + delta.dy);
    }
    _scene = _scene.withSelectedLayer(layer.copyWith(vertices: vertices));
    notifyListeners();
  }

  // (deleteSelected moved earlier in the file — see the `Selection +
  // property edits` section.)

  // ---------------------------------------------------------------------------
  // Annotations
  // ---------------------------------------------------------------------------

  void addTextAnnotation(Offset at, {String text = ''}) {
    final id = _ids.annotation();
    final ann = TextAnnotation(
      id: id,
      color: '#222222',
      x: at.dx,
      y: at.dy,
      text: text,
    );
    _addAnnotation(ann);
    // Auto-select so the inspector immediately shows the text field.
    selectElement(ElementKind.annotation, id);
  }

  void addArrowAnnotation(Offset from, Offset to) {
    final id = _ids.annotation();
    _addAnnotation(ArrowAnnotation(
      id: id,
      color: '#D32F2F',
      fromX: from.dx,
      fromY: from.dy,
      toX: to.dx,
      toY: to.dy,
    ));
  }

  void addDimensionAnnotation(Offset from, Offset to) {
    final id = _ids.annotation();
    _addAnnotation(DimensionAnnotation(
      id: id,
      color: '#1976D2',
      fromX: from.dx,
      fromY: from.dy,
      toX: to.dx,
      toY: to.dy,
      unit: _scene.unit,
    ));
  }

  void updateAnnotationText(String id, String text) {
    final layer = _scene.selectedLayer;
    final existing = layer.annotations[id];
    if (existing is! TextAnnotation) return;
    final updated = existing.copyWith(text: text);
    final next = Map<String, Annotation>.from(layer.annotations);
    next[id] = updated;
    _commit(_scene.withSelectedLayer(layer.copyWith(annotations: next)));
  }

  void _addAnnotation(Annotation ann) {
    final layer = _scene.selectedLayer;
    final next = Map<String, Annotation>.from(layer.annotations);
    next[ann.id] = ann;
    _commit(_scene.withSelectedLayer(layer.copyWith(annotations: next)));
  }

  void setGridSize(double step) {
    if (step == _scene.gridSize) return;
    _scene = _scene.copyWith(gridSize: step);
    notifyListeners();
  }

  /// Switch the display unit. Scene coords stay unchanged — only the
  /// formatting in painter labels and inspector fields adjusts.
  void setUnit(String unit) {
    if (!kSupportedUnits.contains(unit) || unit == _scene.unit) return;
    _commit(_scene.copyWith(unit: unit));
  }

  /// Commit the in-flight wall at exactly [lengthCm] long, in the
  /// direction from the start vertex to the current cursor (or due east
  /// if the cursor hasn't moved off the start vertex). Used by the
  /// inline length input that appears during wall draw — type "5m",
  /// hit Enter, get a 5-metre wall.
  void commitInFlightWallLength(double lengthCm) {
    final m = _mode;
    if (m is! DrawingWallMode) return;
    if (lengthCm <= 0) return;
    final layer = _scene.selectedLayer;
    final start = layer.vertices[m.startVertexId];
    if (start == null) return;
    final cursor = _cursorWorldPos ?? Offset(start.x + 1, start.y);
    final dx = cursor.dx - start.x;
    final dy = cursor.dy - start.y;
    final dist = math.sqrt(dx * dx + dy * dy);
    final ux = dist < 0.5 ? 1.0 : dx / dist;
    final uy = dist < 0.5 ? 0.0 : dy / dist;
    final endX = start.x + ux * lengthCm;
    final endY = start.y + uy * lengthCm;
    endWall(endX, endY);
  }

  /// Resize a wall to [newLengthCm] by moving its second endpoint along
  /// the wall's current direction. The first endpoint and any walls
  /// sharing it stay put. No-op if the wall is degenerate or [newLengthCm]
  /// is non-positive.
  void setWallLength(String lineId, double newLengthCm) {
    if (newLengthCm <= 0) return;
    final layer = _scene.selectedLayer;
    final line = layer.lines[lineId];
    if (line == null) return;
    final a = layer.vertices[line.vertexIds[0]];
    final b = layer.vertices[line.vertexIds[1]];
    if (a == null || b == null) return;
    final dx = b.x - a.x;
    final dy = b.y - a.y;
    final currentLen = math.sqrt(dx * dx + dy * dy);
    if (currentLen < 0.5) return;
    final ux = dx / currentLen;
    final uy = dy / currentLen;
    final vertices = Map<String, Vertex>.from(layer.vertices);
    vertices[b.id] = b.copyWith(
      x: a.x + ux * newLengthCm,
      y: a.y + uy * newLengthCm,
    );
    _commit(_scene.withSelectedLayer(layer.copyWith(vertices: vertices)));
  }

  void setBackgroundOpacity(double opacity) {
    final bg = _scene.background;
    if (bg == null) return;
    _scene = _scene.copyWith(
      background: bg.copyWith(opacity: opacity.clamp(0.0, 1.0)),
    );
    _dirty = true;
    notifyListeners();
  }

  void clearBackground() {
    if (_scene.background == null) return;
    _commit(_scene.copyWith(clearBackground: true));
  }

  /// Apply a batch of AI edit operations to the current scene as a
  /// single undo entry. Returns warnings from the validator (e.g. ops
  /// dropped due to a later remove_room) so the caller can surface
  /// them — the UI snackbar notes any conflicts.
  List<String> applyAiEditBatch(AiFloorplanEditBatch batch) {
    if (batch.operations.isEmpty) return const [];
    final result = applyAiEditsWithReport(
      _scene,
      batch.operations,
      _ids,
      catalog: _catalog,
    );
    if (!identical(result.scene, _scene)) {
      _commit(result.scene);
    }
    return result.warnings;
  }

  // ---------------------------------------------------------------------------
  // Rooms — high-level operations that build several walls + an area
  // in one user action.
  // ---------------------------------------------------------------------------

  /// Begin a rectangle-room drag. Pointer-down sets the start corner;
  /// updateRectangleRoom is called on every move; commit lands the room.
  void beginRectangleRoom(Offset at) {
    _mode = DrawingRectangleRoomMode(start: at, current: at);
    notifyListeners();
  }

  void updateRectangleRoom(Offset at) {
    final m = _mode;
    if (m is! DrawingRectangleRoomMode || m.start == null) return;
    _mode = DrawingRectangleRoomMode(start: m.start, current: at);
    notifyListeners();
  }

  void commitRectangleRoom() {
    final m = _mode;
    if (m is! DrawingRectangleRoomMode || m.start == null || m.current == null) {
      return;
    }
    final rect = Rect.fromPoints(m.start!, m.current!);
    final next = RoomOps.addRectangle(scene: _scene, ids: _ids, rect: rect);
    if (identical(next, _scene)) {
      // Degenerate (no-op) — exit to Idle.
      _mode = const IdleMode();
      notifyListeners();
      return;
    }
    _commit(next, mode: const IdleMode());
  }

  void cancelRectangleRoom() {
    if (_mode is DrawingRectangleRoomMode) {
      _mode = const IdleMode();
      notifyListeners();
    }
  }

  // -- Trace-room ------------------------------------------------------------

  void beginTraceRoom(Offset at) {
    _mode = TracingRoomMode(points: [at]);
    notifyListeners();
  }

  /// Append a point to the in-flight trace. If [at] is within
  /// [closeDistance] of the first point and the polygon has at least
  /// 3 points, the room is committed instead.
  void traceRoomTap(Offset at, {double closeDistance = 12}) {
    final m = _mode;
    if (m is! TracingRoomMode) return;
    if (m.points.isEmpty) {
      _mode = TracingRoomMode(points: [at]);
      notifyListeners();
      return;
    }
    final first = m.points.first;
    if (m.points.length >= 3 && (at - first).distance <= closeDistance) {
      // Close the loop.
      final next = RoomOps.addPolygon(
        scene: _scene,
        ids: _ids,
        points: m.points,
      );
      _commit(next, mode: const IdleMode());
      return;
    }
    _mode = TracingRoomMode(points: [...m.points, at]);
    notifyListeners();
  }

  void cancelTraceRoom() {
    if (_mode is TracingRoomMode) {
      _mode = const IdleMode();
      notifyListeners();
    }
  }

  // ---------------------------------------------------------------------------
  // Calibration — pick two points + a known length, scale the whole scene.
  // ---------------------------------------------------------------------------

  void beginCalibration() {
    _mode = const CalibratingMode();
    notifyListeners();
  }

  /// Click handler during calibration. First click sets [CalibratingMode.first]
  /// and updates the mode. Second click sets [CalibratingMode.second] —
  /// the dialog watches the controller and prompts for the real distance
  /// once both are present. Subsequent clicks are ignored until the user
  /// confirms / cancels via the dialog.
  void calibrationClick(Offset at) {
    final m = _mode;
    if (m is! CalibratingMode) return;
    if (m.first == null) {
      _mode = CalibratingMode(first: at);
      notifyListeners();
    } else if (m.second == null) {
      _mode = CalibratingMode(first: m.first, second: at);
      notifyListeners();
    }
  }

  /// Apply a scene-wide scale factor and exit calibration mode.
  /// Multiplies every vertex / item / annotation coordinate by [factor].
  /// Goes through commit so undo restores the prior scale.
  void applyCalibration(double factor) {
    if (factor <= 0 || (factor - 1).abs() < 1e-6) {
      _mode = const IdleMode();
      notifyListeners();
      return;
    }
    final scaled = _scaleScene(_scene, factor);
    _commit(scaled, mode: const IdleMode());
  }

  void cancelCalibration() {
    if (_mode is CalibratingMode) {
      _mode = const IdleMode();
      notifyListeners();
    }
  }

  Scene _scaleScene(Scene scene, double factor) {
    final layer = scene.selectedLayer;
    final vertices = layer.vertices.map(
      (id, v) => MapEntry(id, v.copyWith(x: v.x * factor, y: v.y * factor)),
    );
    final items = layer.items.map(
      (id, it) => MapEntry(
        id,
        it.copyWith(
          x: it.x * factor,
          y: it.y * factor,
          width: it.width * factor,
          height: it.height * factor,
        ),
      ),
    );
    final holes = layer.holes.map(
      (id, h) => MapEntry(id, h.copyWith(width: h.width * factor)),
    );
    final lines = layer.lines.map(
      (id, l) => MapEntry(id, l.copyWith(thickness: l.thickness * factor)),
    );
    return scene.withSelectedLayer(layer.copyWith(
      vertices: vertices,
      items: items,
      holes: holes,
      lines: lines,
    ));
  }

  // ---------------------------------------------------------------------------
  // Layers (multi-layer scaffolding from Phase 1)
  // ---------------------------------------------------------------------------

  void addLayer({String name = 'Layer'}) {
    final id = _ids.layer();
    final order = _scene.layers.values.fold<int>(
      0,
      (max, l) => l.order > max ? l.order : max,
    );
    final next = Map<String, Layer>.from(_scene.layers);
    next[id] = Layer(id: id, name: name, order: order + 1);
    _commit(_scene.copyWith(layers: next, selectedLayerId: id));
  }

  void setSelectedLayer(String id) {
    if (!_scene.layers.containsKey(id)) return;
    if (id == _scene.selectedLayerId) return;
    _scene = _scene.copyWith(selectedLayerId: id);
    notifyListeners();
  }

  void setLayerVisible(String id, bool visible) {
    final layer = _scene.layers[id];
    if (layer == null || layer.visible == visible) return;
    final next = Map<String, Layer>.from(_scene.layers);
    next[id] = layer.copyWith(visible: visible);
    _commit(_scene.copyWith(layers: next));
  }

  void renameLayer(String id, String name) {
    final layer = _scene.layers[id];
    if (layer == null) return;
    final trimmed = name.trim();
    if (trimmed.isEmpty || trimmed == layer.name) return;
    final next = Map<String, Layer>.from(_scene.layers);
    next[id] = layer.copyWith(name: trimmed);
    _commit(_scene.copyWith(layers: next));
  }

  /// Returns true on success, false if the layer is the only one or is
  /// non-empty (UI surfaces the reason).
  bool deleteLayer(String id) {
    if (_scene.layers.length <= 1) return false;
    final layer = _scene.layers[id];
    if (layer == null) return false;
    final isEmpty = layer.vertices.isEmpty &&
        layer.lines.isEmpty &&
        layer.holes.isEmpty &&
        layer.areas.isEmpty &&
        layer.items.isEmpty &&
        layer.annotations.isEmpty;
    if (!isEmpty) return false;
    final next = Map<String, Layer>.from(_scene.layers)..remove(id);
    var nextScene = _scene.copyWith(layers: next);
    if (_scene.selectedLayerId == id) {
      // Pick the lowest-order remaining layer as the new active one.
      final ordered = next.values.toList()
        ..sort((a, b) => a.order.compareTo(b.order));
      nextScene = nextScene.copyWith(selectedLayerId: ordered.first.id);
    }
    _commit(nextScene);
    return true;
  }

  /// Move [id] up (toward order=0) or down by swapping with the
  /// neighboring layer's order. No-op if already at the boundary.
  void moveLayer(String id, {required bool up}) {
    final layer = _scene.layers[id];
    if (layer == null) return;
    final ordered = _scene.layers.values.toList()
      ..sort((a, b) => a.order.compareTo(b.order));
    final idx = ordered.indexWhere((l) => l.id == id);
    if (idx < 0) return;
    final swapIdx = up ? idx - 1 : idx + 1;
    if (swapIdx < 0 || swapIdx >= ordered.length) return;
    final other = ordered[swapIdx];
    final next = Map<String, Layer>.from(_scene.layers);
    next[id] = layer.copyWith(order: other.order);
    next[other.id] = other.copyWith(order: layer.order);
    _commit(_scene.copyWith(layers: next));
  }

  // ---------------------------------------------------------------------------
  // Undo / redo
  // ---------------------------------------------------------------------------

  void undo() {
    if (_undo.isEmpty) return;
    _redo.add(_scene);
    _scene = _undo.removeLast();
    _mode = const IdleMode();
    _dirty = true;
    notifyListeners();
  }

  void redo() {
    if (_redo.isEmpty) return;
    _undo.add(_scene);
    _scene = _redo.removeLast();
    _mode = const IdleMode();
    _dirty = true;
    notifyListeners();
  }

  /// Push the current scene onto undo, swap in [next], clear redo, mark dirty.
  void _commit(Scene next, {EditorMode? mode}) {
    _undo.add(_scene);
    if (_undo.length > _undoLimit) _undo.removeAt(0);
    _redo.clear();
    _scene = next;
    if (mode != null) _mode = mode;
    _dirty = true;
    notifyListeners();
  }

  /// Test/debug seam — exposes a way to take a fresh snapshot of the
  /// current scene-list state without going through public mutators.
  @visibleForTesting
  ({int undoDepth, int redoDepth}) historyDepths() =>
      (undoDepth: _undo.length, redoDepth: _redo.length);
}
