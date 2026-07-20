import 'dart:ui' show Offset;

import 'package:flutter_test/flutter_test.dart';
import 'package:taskfleet_ops/models/floorplan/editor_mode.dart';
import 'package:taskfleet_ops/models/floorplan/element_kind.dart';
import 'package:taskfleet_ops/services/floorplan/floorplan_editor_controller.dart';
import 'package:taskfleet_ops/services/floorplan/scene_io.dart';

void main() {
  group('FloorplanEditorController', () {
    test('begin → drag → end commits a wall and resets to idle', () {
      final c = FloorplanEditorController(scene: buildEmptyScene());

      c.beginWall(0, 0);
      expect(c.mode, isA<DrawingWallMode>());
      expect(c.scene.selectedLayer.lines, hasLength(1));

      c.dragWallTo(100, 0);
      c.endWall(100, 0);
      // After commit the wall tool stays armed for chained drawing —
      // changed in Phase 6. Esc / V exits.
      expect(c.mode, isA<WaitingDrawingWallMode>());
      expect(c.scene.selectedLayer.lines, hasLength(1));
      expect(c.scene.selectedLayer.vertices, hasLength(2));
      expect(c.dirty, isTrue);
    });

    test('zero-length wall is discarded on end', () {
      final c = FloorplanEditorController(scene: buildEmptyScene());
      c.beginWall(50, 50);
      c.endWall(50, 50);
      expect(c.scene.selectedLayer.lines, isEmpty);
      expect(c.scene.selectedLayer.vertices, isEmpty);
    });

    test('cancelDrawing rolls back to pre-begin state', () {
      final c = FloorplanEditorController(scene: buildEmptyScene());
      c.beginWall(10, 10);
      c.dragWallTo(80, 10);
      c.cancelDrawing();
      // First Esc cancels the in-flight wall, leaving the tool armed
      // for the next stroke. Second Esc would exit to IdleMode.
      expect(c.mode, isA<WaitingDrawingWallMode>());
      expect(c.scene.selectedLayer.lines, isEmpty);
      expect(c.scene.selectedLayer.vertices, isEmpty);
      c.cancelDrawing();
      expect(c.mode, isA<IdleMode>());
    });

    test('undo/redo restores prior scene', () {
      final c = FloorplanEditorController(scene: buildEmptyScene());
      c.beginWall(0, 0);
      c.endWall(100, 0);
      expect(c.scene.selectedLayer.lines, hasLength(1));

      c.undo();
      expect(c.scene.selectedLayer.lines, isEmpty);
      expect(c.canRedo, isTrue);

      c.redo();
      expect(c.scene.selectedLayer.lines, hasLength(1));
    });

    test('end vertex merges into existing vertex within snap distance', () {
      final c = FloorplanEditorController(scene: buildEmptyScene());
      // First wall
      c.beginWall(0, 0);
      c.endWall(100, 0);
      expect(c.scene.selectedLayer.vertices, hasLength(2));

      // Second wall starting at (100, 0) — should reuse the existing vertex
      c.beginWall(100, 0);
      c.endWall(100, 100);
      expect(c.scene.selectedLayer.vertices, hasLength(3));
      expect(c.scene.selectedLayer.lines, hasLength(2));
    });

    test('replaceScene clears history and dirty flag', () {
      final c = FloorplanEditorController(scene: buildEmptyScene());
      c.beginWall(0, 0);
      c.endWall(50, 50);
      expect(c.dirty, isTrue);
      expect(c.canUndo, isTrue);

      c.replaceScene(buildEmptyScene(name: 'Fresh'));
      expect(c.dirty, isFalse);
      expect(c.canUndo, isFalse);
      expect(c.canRedo, isFalse);
      expect(c.scene.name, 'Fresh');
    });

    test('closing a wall loop creates an auto-detected area', () {
      final c = FloorplanEditorController(scene: buildEmptyScene());
      // Square: (0,0) → (100,0) → (100,100) → (0,100) → (0,0)
      c.beginWall(0, 0);
      c.endWall(100, 0);
      c.beginWall(100, 0);
      c.endWall(100, 100);
      c.beginWall(100, 100);
      c.endWall(0, 100);
      c.beginWall(0, 100);
      c.endWall(0, 0);
      expect(c.scene.selectedLayer.lines, hasLength(4));
      expect(c.scene.selectedLayer.areas, hasLength(1));
    });

    test('vertex drag uses begin/end transient — undo restores pre-drag pos',
        () {
      final c = FloorplanEditorController(scene: buildEmptyScene());
      c.beginWall(0, 0);
      c.endWall(100, 0);
      final v1Id = c.scene.selectedLayer.vertices.values.first.id;

      c.beginTransientEdit();
      c.dragVertexTo(v1Id, const Offset(20, 30));
      c.endTransientEdit();
      expect(c.scene.selectedLayer.vertices[v1Id]!.x, 20);
      expect(c.scene.selectedLayer.vertices[v1Id]!.y, 30);

      c.undo();
      expect(c.scene.selectedLayer.vertices[v1Id]!.x, isNot(20));
    });

    test('item drag undo also restores pre-drag position', () {
      final c = FloorplanEditorController(scene: buildEmptyScene());
      c.placeItem(prototype: 'sofa', point: const Offset(50, 50));
      final itemId = c.scene.selectedLayer.items.values.first.id;
      expect(c.scene.selectedLayer.items[itemId]!.x, 50);

      c.beginTransientEdit();
      c.dragItemTo(itemId, const Offset(200, 200));
      c.endTransientEdit();
      expect(c.scene.selectedLayer.items[itemId]!.x, 200);

      c.undo();
      expect(c.scene.selectedLayer.items[itemId]!.x, 50);
    });

    test('item rotation snaps to nearest 15° unless bypassed', () {
      final c = FloorplanEditorController(scene: buildEmptyScene());
      c.placeItem(prototype: 'sofa', point: const Offset(0, 0));
      final id = c.scene.selectedLayer.items.values.first.id;

      c.beginTransientEdit();
      // 0.78 rad ≈ 44.7°; should snap to 45° (≈ 0.7853 rad).
      c.dragItemRotation(id, 0.78);
      c.endTransientEdit();
      expect(
        c.scene.selectedLayer.items[id]!.rotation,
        closeTo(45 * 3.141592653589793 / 180, 0.001),
      );

      // With bypass, the raw value stays.
      c.beginTransientEdit();
      c.dragItemRotation(id, 0.78, bypassSnap: true);
      c.endTransientEdit();
      expect(c.scene.selectedLayer.items[id]!.rotation, closeTo(0.78, 0.001));
    });

    test('deleteSelectedWalls cascades hole deletion + recomputes areas', () {
      final c = FloorplanEditorController(scene: buildEmptyScene());
      // Square loop → one auto-area.
      c.beginWall(0, 0); c.endWall(100, 0);
      c.beginWall(100, 0); c.endWall(100, 100);
      c.beginWall(100, 100); c.endWall(0, 100);
      c.beginWall(0, 100); c.endWall(0, 0);
      expect(c.scene.selectedLayer.areas, hasLength(1));
      // Drop a door on the first wall.
      final firstWallId =
          c.scene.selectedLayer.lines.values.first.id;
      c.placeHole(
        lineId: firstWallId,
        point: const Offset(50, 0),
        prototype: 'door',
      );
      expect(c.scene.selectedLayer.holes, hasLength(1));
      // Select + delete that wall.
      c.selectElement(ElementKind.line, firstWallId);
      c.deleteSelectedWalls();
      // Wall, hole, and area should all be gone.
      expect(c.scene.selectedLayer.lines, hasLength(3));
      expect(c.scene.selectedLayer.holes, isEmpty);
      expect(c.scene.selectedLayer.areas, isEmpty);
    });

    test('undo of a crossing-causing wall reverts both walls + the split',
        () {
      final c = FloorplanEditorController(scene: buildEmptyScene());
      // First wall: horizontal across the middle.
      c.beginWall(0, 50);
      c.endWall(100, 50);
      expect(c.scene.selectedLayer.lines, hasLength(1));
      // Second wall: vertical, crosses the first at its midpoint.
      // splitAtCrossings will split BOTH walls into 4 + the new wall
      // into 2 = 4 walls + 1 unaffected? Actually horiz splits into
      // 2, vert splits into 2 = 4 walls total.
      c.beginWall(50, 0);
      c.endWall(50, 100);
      expect(c.scene.selectedLayer.lines, hasLength(4));
      // Undo should revert just the second wall + its split — the
      // first wall's pristine, unsplit state is restored from the
      // snapshot pushed at the second beginWall.
      c.undo();
      expect(c.scene.selectedLayer.lines, hasLength(1));
      // Redo brings back the 4-wall split state.
      c.redo();
      expect(c.scene.selectedLayer.lines, hasLength(4));
    });

    test('undo limit caps the stack', () {
      final c = FloorplanEditorController(
        scene: buildEmptyScene(),
        undoLimit: 3,
      );
      for (var i = 0; i < 6; i++) {
        c.beginWall(i.toDouble() * 10, 0);
        c.endWall(i.toDouble() * 10 + 50, 0);
      }
      expect(c.historyDepths().undoDepth, lessThanOrEqualTo(3));
    });
  });
}
