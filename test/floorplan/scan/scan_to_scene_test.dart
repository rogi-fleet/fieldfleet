import 'package:flutter_test/flutter_test.dart';
import 'package:taskfleet_ops/models/floorplan/layer.dart';
import 'package:taskfleet_ops/models/floorplan/scan/floor_plan_scan_result.dart';
import 'package:taskfleet_ops/models/floorplan/scene.dart';
import 'package:taskfleet_ops/services/floorplan/scan/scan_to_scene.dart';

FloorPlanScanResult _rect5x4(
    {List<ScannedOpening> openings = const [],
    Pose roomToWorld = const Pose(x: 0, y: 0, yaw: 0)}) {
  // Axis-aligned room, 5 m wide × 4 m deep, CCW from origin.
  // Vertex order:   (0,0) -> (5,0) -> (5,4) -> (0,4)
  final room = ScannedRoom(
    id: 'r1',
    label: 'Living Room',
    floorPolygonMeters: const [
      Vec2(0, 0),
      Vec2(5, 0),
      Vec2(5, 4),
      Vec2(0, 4),
    ],
    roomToWorld: roomToWorld,
  );
  return FloorPlanScanResult(
    captureId: 'cap-1',
    engine: ScanSourceEngine.roomPlan,
    confidence: 0.9,
    rooms: [room],
    openings: openings,
    capturedAt: DateTime.utc(2026, 5, 12, 10, 30),
  );
}

void main() {
  group('ScanToScene', () {
    test('empty result yields a single empty layer with default canvas', () {
      final result = FloorPlanScanResult(
        captureId: 'c',
        engine: ScanSourceEngine.arKitPlaneTap,
        confidence: 0.5,
        rooms: const [],
        capturedAt: DateTime.utc(2026, 1, 1),
      );
      final scene = ScanToScene.convert(result);
      expect(scene.layers, hasLength(1));
      final layer = scene.selectedLayer;
      expect(layer.vertices, isEmpty);
      expect(layer.lines, isEmpty);
      expect(layer.holes, isEmpty);
      expect(layer.areas, isEmpty);
      // Default 2000×2000 canvas when there is no geometry.
      expect(scene.width, 2000);
      expect(scene.height, 2000);
    });

    test('5×4 m room becomes 4 vertices, 4 walls, 1 area in cm', () {
      final scene = ScanToScene.convert(_rect5x4());
      final layer = scene.selectedLayer;
      expect(layer.vertices, hasLength(4));
      expect(layer.lines, hasLength(4));
      expect(layer.areas, hasLength(1));

      // Bounding box of the vertices, in scene units (cm), is 500×400.
      final xs = layer.vertices.values.map((v) => v.x);
      final ys = layer.vertices.values.map((v) => v.y);
      final width = xs.reduce((a, b) => a > b ? a : b) -
          xs.reduce((a, b) => a < b ? a : b);
      final height = ys.reduce((a, b) => a > b ? a : b) -
          ys.reduce((a, b) => a < b ? a : b);
      expect(width, closeTo(500, 0.001));
      expect(height, closeTo(400, 0.001));

      // Each wall has thickness 20cm and exactly two vertex ids.
      for (final w in layer.lines.values) {
        expect(w.prototype, 'wall');
        expect(w.vertexIds, hasLength(2));
        expect(w.thickness, 20.0);
      }

      // Canvas would be 500+400 cm of geometry plus 200cm padding on each
      // side (900×800), but the converter clamps to a 1000cm minimum so
      // the editor always has working space around small scans.
      expect(scene.width, 1000);
      expect(scene.height, 1000);
    });

    test('vertices carry back-references to incident walls and areas', () {
      final scene = ScanToScene.convert(_rect5x4());
      final layer = scene.selectedLayer;
      // In a rectangle every vertex touches exactly two walls and one area.
      for (final v in layer.vertices.values) {
        expect(v.lineIds, hasLength(2));
        expect(v.areaIds, hasLength(1));
      }
    });

    test('opening on edge 0 of the 5m wall becomes a hole with offset≈0.4',
        () {
      // Door, 2.0m from the start of the 5m bottom edge, 0.9m wide.
      final opening = ScannedOpening(
        kind: OpeningKind.door,
        roomId: 'r1',
        wallEdgeIndex: 0,
        offsetAlongWall: 2.0,
        widthMeters: 0.9,
        heightMeters: 2.0,
      );
      final scene = ScanToScene.convert(_rect5x4(openings: [opening]));
      final layer = scene.selectedLayer;
      expect(layer.holes, hasLength(1));
      final hole = layer.holes.values.first;
      expect(hole.prototype, 'door');
      expect(hole.width, closeTo(90, 0.001));
      expect(hole.height, closeTo(200, 0.001));
      expect(hole.offset, closeTo(0.4, 0.001));
      // The host wall now lists the hole.
      final hostWall = layer.lines[hole.lineId]!;
      expect(hostWall.holeIds, contains(hole.id));
    });

    test('out-of-range opening edge index is dropped, not thrown', () {
      final scene = ScanToScene.convert(_rect5x4(openings: [
        const ScannedOpening(
          kind: OpeningKind.window,
          roomId: 'r1',
          wallEdgeIndex: 99,
          offsetAlongWall: 1.0,
          widthMeters: 1.0,
          heightMeters: 1.0,
          sillHeightMeters: 1.0,
        ),
      ]));
      expect(scene.selectedLayer.holes, isEmpty);
    });

    test('opening on a missing room id is dropped', () {
      final scene = ScanToScene.convert(_rect5x4(openings: [
        const ScannedOpening(
          kind: OpeningKind.door,
          roomId: 'no-such-room',
          wallEdgeIndex: 0,
          offsetAlongWall: 1.0,
          widthMeters: 1.0,
          heightMeters: 2.0,
        ),
      ]));
      expect(scene.selectedLayer.holes, isEmpty);
    });

    test('degenerate (<3 vertex) rooms are skipped, scene still valid', () {
      final result = FloorPlanScanResult(
        captureId: 'c',
        engine: ScanSourceEngine.arCorePlaneTap,
        confidence: 0.5,
        rooms: const [
          ScannedRoom(
            id: 'tiny',
            floorPolygonMeters: [Vec2(0, 0), Vec2(1, 0)],
            roomToWorld: Pose(x: 0, y: 0, yaw: 0),
          ),
        ],
        capturedAt: DateTime.utc(2026, 1, 1),
      );
      final scene = ScanToScene.convert(result);
      expect(scene.selectedLayer.lines, isEmpty);
      expect(scene.selectedLayer.areas, isEmpty);
    });

    test('JSON round-trip is stable', () {
      final original = _rect5x4(openings: [
        const ScannedOpening(
          kind: OpeningKind.window,
          roomId: 'r1',
          wallEdgeIndex: 1,
          offsetAlongWall: 1.5,
          widthMeters: 1.2,
          heightMeters: 1.0,
          sillHeightMeters: 0.9,
        ),
      ]);
      final json = original.toJson();
      final back = FloorPlanScanResult.fromJson(json);
      expect(back.rooms.first.floorPolygonMeters.first.x, 0);
      expect(back.openings.first.kind, OpeningKind.window);
      expect(back.openings.first.sillHeightMeters, 0.9);
    });

    test('room pose translates and rotates the geometry into world space', () {
      // Same 5×4 m room rotated 90° CCW and shifted by (10, 20) metres.
      final rotated = _rect5x4(
        roomToWorld: Pose(x: 10, y: 20, yaw: 1.5707963267948966),
      );
      final scene = ScanToScene.convert(rotated);
      final layer = scene.selectedLayer;
      // After yaw=90°, the 5m extent goes along +y and 4m along -x.
      // In cm that's 500cm along +y and 400cm along -x. The bounding box's
      // width and height should swap.
      final xs = layer.vertices.values.map((v) => v.x);
      final ys = layer.vertices.values.map((v) => v.y);
      final width = xs.reduce((a, b) => a > b ? a : b) -
          xs.reduce((a, b) => a < b ? a : b);
      final height = ys.reduce((a, b) => a > b ? a : b) -
          ys.reduce((a, b) => a < b ? a : b);
      expect(width, closeTo(400, 0.001));
      expect(height, closeTo(500, 0.001));
    });

    test('ceiling height from scan flows into Scene.ceilingHeightCm', () {
      final result = FloorPlanScanResult(
        captureId: 'c',
        engine: ScanSourceEngine.roomPlan,
        confidence: 0.9,
        rooms: const [
          ScannedRoom(
            id: 'r',
            floorPolygonMeters: [
              Vec2(0, 0),
              Vec2(3, 0),
              Vec2(3, 3),
              Vec2(0, 3),
            ],
            roomToWorld: Pose(x: 0, y: 0, yaw: 0),
          ),
        ],
        ceilingHeightMeters: 2.7,
        capturedAt: DateTime.utc(2026, 5, 12),
      );
      final scene = ScanToScene.convert(result);
      expect(scene.ceilingHeightCm, closeTo(270, 0.001));
    });

    test('missing scan ceiling falls back to scene default (240)', () {
      final result = FloorPlanScanResult(
        captureId: 'c',
        engine: ScanSourceEngine.arCorePlaneTap,
        confidence: 0.5,
        rooms: const [
          ScannedRoom(
            id: 'r',
            floorPolygonMeters: [
              Vec2(0, 0),
              Vec2(3, 0),
              Vec2(3, 3),
              Vec2(0, 3),
            ],
            roomToWorld: Pose(x: 0, y: 0, yaw: 0),
          ),
        ],
        capturedAt: DateTime.utc(2026, 5, 12),
      );
      final scene = ScanToScene.convert(result);
      expect(scene.ceilingHeightCm, 240);
    });

    test('per-wall heights only override when they meaningfully differ', () {
      // 5×4 m room with ceiling 240 cm; one wall is a half-wall at 110 cm,
      // the other three are within tolerance of the reference.
      final result = FloorPlanScanResult(
        captureId: 'c',
        engine: ScanSourceEngine.roomPlan,
        confidence: 0.9,
        rooms: const [
          ScannedRoom(
            id: 'r1',
            floorPolygonMeters: [
              Vec2(0, 0),
              Vec2(5, 0),
              Vec2(5, 4),
              Vec2(0, 4),
            ],
            roomToWorld: Pose(x: 0, y: 0, yaw: 0),
            perWallHeightsMeters: [
              1.10, // half wall — overrides
              2.40, // matches reference — inherits scene
              2.45, // within tolerance — inherits scene
              2.35, // within tolerance — inherits scene
            ],
          ),
        ],
        ceilingHeightMeters: 2.4,
        capturedAt: DateTime.utc(2026, 5, 12),
      );
      final scene = ScanToScene.convert(result);
      final overrideCount = scene.selectedLayer.lines.values
          .where((l) => l.heightCm != null)
          .length;
      expect(overrideCount, 1);
      final overridden = scene.selectedLayer.lines.values
          .firstWhere((l) => l.heightCm != null);
      expect(overridden.heightCm, closeTo(110, 0.001));
    });

    test('per-wall height length mismatch is rejected silently', () {
      final result = FloorPlanScanResult(
        captureId: 'c',
        engine: ScanSourceEngine.roomPlan,
        confidence: 0.9,
        rooms: const [
          ScannedRoom(
            id: 'r1',
            floorPolygonMeters: [
              Vec2(0, 0),
              Vec2(5, 0),
              Vec2(5, 4),
              Vec2(0, 4),
            ],
            roomToWorld: Pose(x: 0, y: 0, yaw: 0),
            perWallHeightsMeters: [1.10, 2.40], // 4 walls, only 2 heights
          ),
        ],
        ceilingHeightMeters: 2.4,
        capturedAt: DateTime.utc(2026, 5, 12),
      );
      final scene = ScanToScene.convert(result);
      final overrides = scene.selectedLayer.lines.values
          .where((l) => l.heightCm != null);
      expect(overrides, isEmpty);
    });

    test('absurd scan ceiling (30 cm) is rejected for the default', () {
      final result = FloorPlanScanResult(
        captureId: 'c',
        engine: ScanSourceEngine.roomPlan,
        confidence: 0.4,
        rooms: const [
          ScannedRoom(
            id: 'r',
            floorPolygonMeters: [
              Vec2(0, 0),
              Vec2(3, 0),
              Vec2(3, 3),
              Vec2(0, 3),
            ],
            roomToWorld: Pose(x: 0, y: 0, yaw: 0),
          ),
        ],
        ceilingHeightMeters: 0.3,
        capturedAt: DateTime.utc(2026, 5, 12),
      );
      final scene = ScanToScene.convert(result);
      expect(scene.ceilingHeightCm, 240);
    });

    group('appendInto', () {
      Scene emptyScene() {
        const layerId = 'lyr-empty';
        return const Scene(
          id: 'sc-empty',
          selectedLayerId: layerId,
          layers: {layerId: Layer(id: layerId)},
        );
      }

      test('appending into an empty scene matches convert() shape', () {
        final appended = ScanToScene.appendInto(emptyScene(), _rect5x4());
        expect(appended.selectedLayer.vertices, hasLength(4));
        expect(appended.selectedLayer.lines, hasLength(4));
        expect(appended.selectedLayer.areas, hasLength(1));
      });

      test('preserves existing geometry and places new room to the right', () {
        // Start with one rectangular room.
        final base = ScanToScene.convert(_rect5x4());
        final baseLayer = base.selectedLayer;
        final baseRightEdge = baseLayer.vertices.values
            .map((v) => v.x)
            .reduce((a, b) => a > b ? a : b);

        // Append a second room.
        final after = ScanToScene.appendInto(base, _rect5x4());
        final newLayer = after.selectedLayer;

        // Existing geometry is intact.
        expect(newLayer.vertices.length, baseLayer.vertices.length + 4);
        expect(newLayer.lines.length, baseLayer.lines.length + 4);
        expect(newLayer.areas.length, baseLayer.areas.length + 1);
        for (final id in baseLayer.vertices.keys) {
          expect(newLayer.vertices[id]?.x, baseLayer.vertices[id]?.x);
          expect(newLayer.vertices[id]?.y, baseLayer.vertices[id]?.y);
        }

        // New geometry sits to the right of the existing.
        final newOnlyIds =
            newLayer.vertices.keys.toSet().difference(baseLayer.vertices.keys.toSet());
        final newMinX = newOnlyIds
            .map((id) => newLayer.vertices[id]!.x)
            .reduce((a, b) => a < b ? a : b);
        expect(newMinX, greaterThan(baseRightEdge));
      });

      test('appended geometry shares no vertex/line ids with existing', () {
        final base = ScanToScene.convert(_rect5x4());
        final after = ScanToScene.appendInto(base, _rect5x4());
        final baseLayer = base.selectedLayer;
        final newLayer = after.selectedLayer;
        // Every original id is unchanged and still present.
        for (final id in baseLayer.lines.keys) {
          expect(newLayer.lines, contains(id));
        }
        // No new id collides with an existing one.
        final intersection = newLayer.lines.keys
            .toSet()
            .difference(baseLayer.lines.keys.toSet());
        for (final id in intersection) {
          expect(baseLayer.lines.containsKey(id), isFalse);
        }
      });

      test('grows the canvas when the appended room would overflow it', () {
        final base = ScanToScene.convert(_rect5x4());
        final widthBefore = base.width;
        final after = ScanToScene.appendInto(base, _rect5x4());
        expect(after.width, greaterThan(widthBefore));
      });

      test('never shrinks the canvas, even when there is slack', () {
        final base = ScanToScene.convert(_rect5x4()).copyWith(
          width: 20000,
          height: 20000,
        );
        final after = ScanToScene.appendInto(base, _rect5x4());
        expect(after.width, 20000);
        expect(after.height, 20000);
      });

      test('scan with no rooms returns the scene unchanged', () {
        final base = ScanToScene.convert(_rect5x4());
        final empty = FloorPlanScanResult(
          captureId: 'c',
          engine: ScanSourceEngine.arCorePlaneTap,
          confidence: 0.5,
          rooms: const [],
          capturedAt: DateTime.utc(2026, 5, 12),
        );
        final after = ScanToScene.appendInto(base, empty);
        expect(after.selectedLayer.lines.length, base.selectedLayer.lines.length);
        expect(after.selectedLayer.vertices.length,
            base.selectedLayer.vertices.length);
        expect(after.width, base.width);
      });
    });

    test('opening width is preserved across pose transforms', () {
      // The polygon is rotated but a door's width is measured *along* the
      // wall, so the resulting Hole.width must still be 90cm regardless
      // of the room pose.
      const opening = ScannedOpening(
        kind: OpeningKind.door,
        roomId: 'r1',
        wallEdgeIndex: 0,
        offsetAlongWall: 2.0,
        widthMeters: 0.9,
        heightMeters: 2.0,
      );
      final rotated = _rect5x4(
        openings: const [opening],
        roomToWorld: Pose(x: 7, y: -3, yaw: 0.7853981633974483),
      );
      final scene = ScanToScene.convert(rotated);
      final hole = scene.selectedLayer.holes.values.first;
      expect(hole.width, closeTo(90, 0.001));
      // Offset normalisation should still resolve to 2/5 = 0.4.
      expect(hole.offset, closeTo(0.4, 0.001));
    });
  });
}
