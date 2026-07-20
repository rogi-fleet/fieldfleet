import 'dart:ui' show Offset;

import 'package:flutter_test/flutter_test.dart';
import 'package:taskfleet_ops/models/floorplan/hole.dart';
import 'package:taskfleet_ops/models/floorplan/layer.dart';
import 'package:taskfleet_ops/models/floorplan/line.dart';
import 'package:taskfleet_ops/models/floorplan/vertex.dart';
import 'package:taskfleet_ops/services/floorplan/class/hole_ops.dart';
import 'package:taskfleet_ops/services/floorplan/class/wall_ops.dart';
import 'package:taskfleet_ops/services/floorplan/scene_io.dart';
import 'package:taskfleet_ops/utils/floorplan/id_broker.dart';

void main() {
  group('HoleOps.placeOnWall', () {
    test('drops a door at the projected offset', () {
      final ids = IdBroker();
      var scene = buildEmptyScene(ids: ids);
      var layer = scene.selectedLayer;
      final v1 = Vertex(id: 'v1', x: 0, y: 0, lineIds: const {'l1'});
      final v2 = Vertex(id: 'v2', x: 100, y: 0, lineIds: const {'l1'});
      final l = FloorLine(id: 'l1', vertexIds: ['v1', 'v2']);
      scene = scene.withSelectedLayer(layer.copyWith(
        vertices: {'v1': v1, 'v2': v2},
        lines: {'l1': l},
      ));

      final r = HoleOps.placeOnWall(
        scene: scene,
        ids: ids,
        lineId: 'l1',
        point: const Offset(40, 5),
        prototype: 'door',
        width: 80,
      )!;

      final hole = r.scene.selectedLayer.holes[r.holeId]!;
      expect(hole.prototype, 'door');
      expect(hole.lineId, 'l1');
      // Projected t = 0.4, but clamped to inset = 80/2/100 = 0.4 minimum.
      expect(hole.offset, closeTo(0.4, 0.001));
      // Wall now references the hole.
      expect(r.scene.selectedLayer.lines['l1']!.holeIds, contains(r.holeId));
    });
  });

  group('WallOps.split — hole offset rescaling', () {
    test('hole at t=0.25 stays at world position after split at t=0.5', () {
      final ids = IdBroker();
      var scene = buildEmptyScene(ids: ids);
      var layer = scene.selectedLayer;
      // 100-unit horizontal wall.
      scene = scene.withSelectedLayer(layer.copyWith(
        vertices: {
          'v1': Vertex(id: 'v1', x: 0, y: 0, lineIds: const {'l1'}),
          'v2': Vertex(id: 'v2', x: 100, y: 0, lineIds: const {'l1'}),
        },
        lines: {
          'l1': FloorLine(id: 'l1', vertexIds: ['v1', 'v2'], holeIds: ['h1']),
        },
        holes: {
          'h1': const _TestHole().build(
            id: 'h1',
            lineId: 'l1',
            offset: 0.25, // world position = (25, 0)
          ),
        },
      ));

      final r = WallOps.split(
        scene: scene,
        ids: ids,
        lineId: 'l1',
        tSplit: 0.5,
      )!;

      // Hole was at offset 0.25 on a wall split at 0.5 → goes on first
      // half (A→S, length 50), offset = 0.25 / 0.5 = 0.5.
      final hole = r.scene.selectedLayer.holes['h1']!;
      expect(hole.lineId, r.firstLineId);
      expect(hole.offset, closeTo(0.5, 0.001));

      // Walls reformed correctly.
      expect(r.scene.selectedLayer.lines, hasLength(2));
      expect(r.scene.selectedLayer.lines.containsKey('l1'), isFalse);
      final firstWall = r.scene.selectedLayer.lines[r.firstLineId]!;
      expect(firstWall.vertexIds, ['v1', r.splitVertexId]);
      expect(firstWall.holeIds, ['h1']);

      // Split vertex at world (50, 0).
      final sv = r.scene.selectedLayer.vertices[r.splitVertexId]!;
      expect(sv.x, closeTo(50, 0.001));
      expect(sv.y, closeTo(0, 0.001));
      expect(sv.lineIds, {r.firstLineId, r.secondLineId});
    });

    test('hole at t=0.75 lands on second wall with offset 0.5', () {
      final ids = IdBroker();
      var scene = buildEmptyScene(ids: ids);
      var layer = scene.selectedLayer;
      scene = scene.withSelectedLayer(layer.copyWith(
        vertices: {
          'v1': Vertex(id: 'v1', x: 0, y: 0, lineIds: const {'l1'}),
          'v2': Vertex(id: 'v2', x: 100, y: 0, lineIds: const {'l1'}),
        },
        lines: {
          'l1': FloorLine(id: 'l1', vertexIds: ['v1', 'v2'], holeIds: ['h1']),
        },
        holes: {
          'h1': const _TestHole().build(
            id: 'h1',
            lineId: 'l1',
            offset: 0.75, // world position = (75, 0)
          ),
        },
      ));

      final r = WallOps.split(
        scene: scene,
        ids: ids,
        lineId: 'l1',
        tSplit: 0.5,
      )!;
      final hole = r.scene.selectedLayer.holes['h1']!;
      expect(hole.lineId, r.secondLineId);
      // (0.75 - 0.5) / (1 - 0.5) = 0.5
      expect(hole.offset, closeTo(0.5, 0.001));
    });

    test('split at endpoint returns null', () {
      final ids = IdBroker();
      var scene = buildEmptyScene(ids: ids);
      var layer = scene.selectedLayer;
      scene = scene.withSelectedLayer(layer.copyWith(
        vertices: {
          'v1': Vertex(id: 'v1', x: 0, y: 0, lineIds: const {'l1'}),
          'v2': Vertex(id: 'v2', x: 100, y: 0, lineIds: const {'l1'}),
        },
        lines: {'l1': FloorLine(id: 'l1', vertexIds: ['v1', 'v2'])},
      ));
      expect(
        WallOps.split(scene: scene, ids: ids, lineId: 'l1', tSplit: 0),
        isNull,
      );
      expect(
        WallOps.split(scene: scene, ids: ids, lineId: 'l1', tSplit: 1),
        isNull,
      );
    });

    test('split refused when a hole window straddles the split point',
        () {
      // 100-cm wall with a door 30 cm wide centered at offset 0.5
      // (covers world x=35..65). A split at t=0.5 would cut through
      // the door — refused.
      final ids = IdBroker();
      var scene = buildEmptyScene(ids: ids);
      final layer = scene.selectedLayer;
      scene = scene.withSelectedLayer(layer.copyWith(
        vertices: {
          'v1': Vertex(id: 'v1', x: 0, y: 0, lineIds: const {'l1'}),
          'v2': Vertex(id: 'v2', x: 100, y: 0, lineIds: const {'l1'}),
        },
        lines: {
          'l1': FloorLine(id: 'l1', vertexIds: ['v1', 'v2'], holeIds: ['h1']),
        },
        holes: {
          'h1': const _TestHole().build(
            id: 'h1',
            lineId: 'l1',
            offset: 0.5,
            width: 30,
          ),
        },
      ));
      final r = WallOps.split(
        scene: scene,
        ids: ids,
        lineId: 'l1',
        tSplit: 0.5,
      );
      expect(r, isNull);
      // Original wall + hole untouched.
      expect(scene.selectedLayer.lines, hasLength(1));
      expect(scene.selectedLayer.holes, hasLength(1));
    });

    test('split allowed when hole window is fully on one side', () {
      // Same 100-cm wall + 30-cm-wide door at offset 0.2 (covers
      // x=5..35). Split at t=0.5 leaves the door fully on the first
      // half — should proceed.
      final ids = IdBroker();
      var scene = buildEmptyScene(ids: ids);
      final layer = scene.selectedLayer;
      scene = scene.withSelectedLayer(layer.copyWith(
        vertices: {
          'v1': Vertex(id: 'v1', x: 0, y: 0, lineIds: const {'l1'}),
          'v2': Vertex(id: 'v2', x: 100, y: 0, lineIds: const {'l1'}),
        },
        lines: {
          'l1': FloorLine(id: 'l1', vertexIds: ['v1', 'v2'], holeIds: ['h1']),
        },
        holes: {
          'h1': const _TestHole().build(
            id: 'h1',
            lineId: 'l1',
            offset: 0.2,
            width: 30,
          ),
        },
      ));
      final r = WallOps.split(
        scene: scene,
        ids: ids,
        lineId: 'l1',
        tSplit: 0.5,
      );
      expect(r, isNotNull);
    });

    test('multiple holes get rescaled and partitioned correctly', () {
      final ids = IdBroker();
      var scene = buildEmptyScene(ids: ids);
      var layer = scene.selectedLayer;
      scene = scene.withSelectedLayer(layer.copyWith(
        vertices: {
          'v1': Vertex(id: 'v1', x: 0, y: 0, lineIds: const {'l1'}),
          'v2': Vertex(id: 'v2', x: 100, y: 0, lineIds: const {'l1'}),
        },
        lines: {
          'l1': FloorLine(
            id: 'l1',
            vertexIds: ['v1', 'v2'],
            holeIds: ['h1', 'h2', 'h3'],
          ),
        },
        holes: {
          'h1': const _TestHole().build(id: 'h1', lineId: 'l1', offset: 0.1),
          'h2': const _TestHole().build(id: 'h2', lineId: 'l1', offset: 0.4),
          'h3': const _TestHole().build(id: 'h3', lineId: 'l1', offset: 0.9),
        },
      ));

      final r = WallOps.split(
        scene: scene,
        ids: ids,
        lineId: 'l1',
        tSplit: 0.5,
      )!;
      final h = r.scene.selectedLayer.holes;
      expect(h['h1']!.lineId, r.firstLineId);
      expect(h['h1']!.offset, closeTo(0.2, 0.001));
      expect(h['h2']!.lineId, r.firstLineId);
      expect(h['h2']!.offset, closeTo(0.8, 0.001));
      expect(h['h3']!.lineId, r.secondLineId);
      expect(h['h3']!.offset, closeTo(0.8, 0.001));
      // Wall hole assignment matches.
      expect(
        r.scene.selectedLayer.lines[r.firstLineId]!.holeIds,
        containsAll(['h1', 'h2']),
      );
      expect(
        r.scene.selectedLayer.lines[r.secondLineId]!.holeIds,
        contains('h3'),
      );
    });
  });
}

/// Small helper so tests don't have to import every Hole field default.
class _TestHole {
  const _TestHole();
  Hole build({
    required String id,
    required String lineId,
    required double offset,
    String prototype = 'door',
    double width = 5,
  }) =>
      Hole(
        id: id,
        prototype: prototype,
        lineId: lineId,
        offset: offset,
        width: width,
      );
}
