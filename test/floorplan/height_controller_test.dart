import 'package:flutter_test/flutter_test.dart';
import 'package:taskfleet_ops/models/floorplan/hole.dart';
import 'package:taskfleet_ops/services/floorplan/floorplan_editor_controller.dart';
import 'package:taskfleet_ops/services/floorplan/scene_io.dart';

/// Builds a scene with one wall and one door on that wall so the height
/// mutators have something to act on. Returns the controller and the
/// new wall + hole ids for the test to reference.
({FloorplanEditorController controller, String wallId, String holeId})
    _makeSceneWithOneDoor() {
  final c = FloorplanEditorController(scene: buildEmptyScene());
  c.beginWall(0, 0);
  c.endWall(400, 0);
  final wallId = c.scene.selectedLayer.lines.keys.first;
  c.placeHole(
    prototype: 'door',
    lineId: wallId,
    point: const Offset(200, 0),
  );
  final holeId = c.scene.selectedLayer.holes.keys.first;
  return (controller: c, wallId: wallId, holeId: holeId);
}

void main() {
  group('FloorplanEditorController heights', () {
    test('setSceneCeilingHeight commits a new value', () {
      final c = FloorplanEditorController(scene: buildEmptyScene());
      expect(c.scene.ceilingHeightCm, 240);
      c.setSceneCeilingHeight(300);
      expect(c.scene.ceilingHeightCm, 300);
      expect(c.dirty, isTrue);
    });

    test('setSceneCeilingHeight is no-op for the same value', () {
      final c = FloorplanEditorController(scene: buildEmptyScene());
      c.setSceneCeilingHeight(240);
      // No commit means no dirty flag flip and undo stack stays empty.
      expect(c.dirty, isFalse);
      expect(c.canUndo, isFalse);
    });

    test('setSceneCeilingHeight is undoable', () {
      final c = FloorplanEditorController(scene: buildEmptyScene());
      c.setSceneCeilingHeight(310);
      expect(c.scene.ceilingHeightCm, 310);
      c.undo();
      expect(c.scene.ceilingHeightCm, 240);
    });

    test('setLineHeight sets and clears per-wall override', () {
      final s = _makeSceneWithOneDoor();
      final c = s.controller;
      // Default — no override, falls back to scene 240.
      expect(c.scene.selectedLayer.lines[s.wallId]!.heightCm, isNull);
      expect(
        c.scene.selectedLayer.lines[s.wallId]!.effectiveHeightCm(
          c.scene.ceilingHeightCm,
        ),
        240,
      );
      // Set override.
      c.setLineHeight(s.wallId, 120);
      expect(c.scene.selectedLayer.lines[s.wallId]!.heightCm, 120);
      expect(
        c.scene.selectedLayer.lines[s.wallId]!.effectiveHeightCm(
          c.scene.ceilingHeightCm,
        ),
        120,
      );
      // Clear override.
      c.setLineHeight(s.wallId, null);
      expect(c.scene.selectedLayer.lines[s.wallId]!.heightCm, isNull);
    });

    test('setLineHeight is undoable as a single step', () {
      final s = _makeSceneWithOneDoor();
      final c = s.controller;
      c.setLineHeight(s.wallId, 220);
      c.undo();
      expect(c.scene.selectedLayer.lines[s.wallId]!.heightCm, isNull);
    });

    test('updateHoleAltitude lifts a window off the floor', () {
      final s = _makeSceneWithOneDoor();
      final c = s.controller;
      expect(c.scene.selectedLayer.holes[s.holeId]!.altitude, 0);
      c.updateHoleAltitude(s.holeId, 90);
      expect(c.scene.selectedLayer.holes[s.holeId]!.altitude, 90);
    });

    test('updateHoleAltitude is undoable', () {
      final s = _makeSceneWithOneDoor();
      final c = s.controller;
      c.updateHoleAltitude(s.holeId, 90);
      c.undo();
      expect(c.scene.selectedLayer.holes[s.holeId]!.altitude, 0);
    });

    test('updateHoleAltitude is a no-op for identical value', () {
      final s = _makeSceneWithOneDoor();
      final c = s.controller;
      final before = c.dirty;
      c.updateHoleAltitude(s.holeId, 0);
      expect(c.dirty, before);
    });

    test('Hole.copyWith preserves altitude when not overridden', () {
      const h = Hole(
          id: 'h', prototype: 'window', lineId: 'l', offset: 0.5, altitude: 90);
      expect(h.copyWith(width: 120).altitude, 90);
    });
  });
}
