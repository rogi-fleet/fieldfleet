import 'dart:ui' show Offset;

import 'package:flutter_test/flutter_test.dart';
import 'package:taskfleet_ops/models/floorplan/layer.dart';
import 'package:taskfleet_ops/models/floorplan/line.dart';
import 'package:taskfleet_ops/models/floorplan/vertex.dart';
import 'package:taskfleet_ops/services/floorplan/scene_io.dart';
import 'package:taskfleet_ops/utils/floorplan/snap.dart';
import 'package:taskfleet_ops/utils/floorplan/snap_scene.dart';

void main() {
  group('PointSnap', () {
    test('hits within radius', () {
      const s = PointSnap(point: Offset(10, 10), radius: 5);
      final h = s.hit(const Offset(11, 12));
      expect(h, isNotNull);
      expect(h!.point, const Offset(10, 10));
    });

    test('misses beyond radius', () {
      const s = PointSnap(point: Offset(0, 0), radius: 3);
      expect(s.hit(const Offset(10, 10)), isNull);
    });
  });

  group('LineSegmentSnap', () {
    test('projects onto segment', () {
      const s = LineSegmentSnap(a: Offset(0, 0), b: Offset(10, 0), radius: 5);
      final h = s.hit(const Offset(5, 3));
      expect(h, isNotNull);
      expect(h!.point.dx, closeTo(5, 0.001));
      expect(h.point.dy, closeTo(0, 0.001));
    });

    test('clamps beyond segment end', () {
      const s = LineSegmentSnap(a: Offset(0, 0), b: Offset(10, 0), radius: 5);
      // (15, 1) -> clamps to (10, 0); distance ~5.099 -> beyond radius=5
      expect(s.hit(const Offset(15, 1)), isNull);
      // (12, 1) -> clamps to (10, 0); distance ~2.236 -> hits
      final h = s.hit(const Offset(12, 1));
      expect(h, isNotNull);
      expect(h!.point.dx, closeTo(10, 0.001));
    });
  });

  group('GridSnap', () {
    test('snaps to nearest step', () {
      const s = GridSnap(step: 10, radius: 5);
      final h = s.hit(const Offset(13, 28));
      expect(h, isNotNull);
      expect(h!.point, const Offset(10, 30));
    });

    test('returns null beyond radius', () {
      const s = GridSnap(step: 10, radius: 2);
      expect(s.hit(const Offset(15, 15)), isNull);
    });
  });

  group('nearestSnap priority', () {
    test('higher priority wins over closer lower-priority snap', () {
      const point = PointSnap(point: Offset(0, 0), radius: 20);
      const grid = GridSnap(step: 1, radius: 20);
      // Both fire at (1, 1); grid would be closer (snaps to (1,1)) but
      // PointSnap (priority 30) outranks GridSnap (priority 5).
      final r = nearestSnap([point, grid], const Offset(1, 1));
      expect(r, isNotNull);
      expect(r!.snap, isA<PointSnap>());
    });

    test('mask filters out kinds', () {
      const point = PointSnap(point: Offset(0, 0), radius: 20);
      final r = nearestSnap(
        [point],
        const Offset(1, 1),
        mask: SnapMask.disabled(),
      );
      expect(r, isNull);
    });
  });

  group('sceneSnaps', () {
    test('emits one PointSnap per vertex + one LineSegmentSnap per wall', () {
      final scene = buildEmptyScene();
      final layer = scene.selectedLayer;
      final v1 = Vertex(id: 'v1', x: 0, y: 0, lineIds: const {'l1'});
      final v2 = Vertex(id: 'v2', x: 100, y: 0, lineIds: const {'l1'});
      final l = FloorLine(id: 'l1', vertexIds: ['v1', 'v2']);
      final populated = scene.withSelectedLayer(layer.copyWith(
        vertices: {'v1': v1, 'v2': v2},
        lines: {'l1': l},
      ));

      final snaps = sceneSnaps(populated, includeGrid: false);
      expect(snaps.whereType<PointSnap>(), hasLength(2));
      expect(snaps.whereType<LineSegmentSnap>(), hasLength(1));
    });

    test('excluded vertices/lines are skipped', () {
      final scene = buildEmptyScene();
      final layer = scene.selectedLayer;
      final v1 = Vertex(id: 'v1', x: 0, y: 0, lineIds: const {'l1'});
      final v2 = Vertex(id: 'v2', x: 100, y: 0, lineIds: const {'l1'});
      final l = FloorLine(id: 'l1', vertexIds: ['v1', 'v2']);
      final populated = scene.withSelectedLayer(layer.copyWith(
        vertices: {'v1': v1, 'v2': v2},
        lines: {'l1': l},
      ));

      final snaps = sceneSnaps(
        populated,
        excludedVertexIds: {'v2'},
        excludedLineIds: {'l1'},
        includeGrid: false,
      );
      expect(snaps.whereType<PointSnap>(), hasLength(1));
      expect(snaps.whereType<LineSegmentSnap>(), isEmpty);
    });
  });
}
