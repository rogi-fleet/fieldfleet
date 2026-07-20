import 'package:flutter_test/flutter_test.dart';
import 'package:taskfleet_ops/models/floorplan/line.dart';
import 'package:taskfleet_ops/models/floorplan/vertex.dart';
import 'package:taskfleet_ops/services/floorplan/class/wall_ops.dart';
import 'package:taskfleet_ops/services/floorplan/scene_io.dart';
import 'package:taskfleet_ops/utils/floorplan/id_broker.dart';

void main() {
  group('WallOps.splitAtCrossings', () {
    test('two walls crossing at the middle each split into two', () {
      final ids = IdBroker();
      var scene = buildEmptyScene(ids: ids);
      final layer = scene.selectedLayer;

      // Horizontal wall: (0,0) → (100,0)
      // Vertical wall:   (50,-50) → (50,50)
      // Intersection at (50,0).
      scene = scene.withSelectedLayer(layer.copyWith(
        vertices: {
          'h1': Vertex(id: 'h1', x: 0, y: 0, lineIds: const {'horiz'}),
          'h2': Vertex(id: 'h2', x: 100, y: 0, lineIds: const {'horiz'}),
          'v1': Vertex(id: 'v1', x: 50, y: -50, lineIds: const {'vert'}),
          'v2': Vertex(id: 'v2', x: 50, y: 50, lineIds: const {'vert'}),
        },
        lines: {
          'horiz': FloorLine(id: 'horiz', vertexIds: ['h1', 'h2']),
          'vert': FloorLine(id: 'vert', vertexIds: ['v1', 'v2']),
        },
      ));

      final result = WallOps.splitAtCrossings(
        scene: scene,
        ids: ids,
        newLineId: 'vert',
      );

      // Both original walls should be gone, replaced by 4 new walls.
      expect(result.selectedLayer.lines, hasLength(4));
      expect(result.selectedLayer.lines.containsKey('horiz'), isFalse);
      expect(result.selectedLayer.lines.containsKey('vert'), isFalse);

      // A crossing vertex at (50, 0) should exist with degree 4.
      final crossingVertex = result.selectedLayer.vertices.values
          .where((v) => (v.x - 50).abs() < 0.001 && (v.y - 0).abs() < 0.001)
          .firstOrNull;
      expect(crossingVertex, isNotNull);
      expect(crossingVertex!.lineIds, hasLength(4));
    });

    test('parallel walls do not split', () {
      final ids = IdBroker();
      var scene = buildEmptyScene(ids: ids);
      final layer = scene.selectedLayer;
      scene = scene.withSelectedLayer(layer.copyWith(
        vertices: {
          'a1': Vertex(id: 'a1', x: 0, y: 0, lineIds: const {'a'}),
          'a2': Vertex(id: 'a2', x: 100, y: 0, lineIds: const {'a'}),
          'b1': Vertex(id: 'b1', x: 0, y: 50, lineIds: const {'b'}),
          'b2': Vertex(id: 'b2', x: 100, y: 50, lineIds: const {'b'}),
        },
        lines: {
          'a': FloorLine(id: 'a', vertexIds: ['a1', 'a2']),
          'b': FloorLine(id: 'b', vertexIds: ['b1', 'b2']),
        },
      ));

      final r = WallOps.splitAtCrossings(
        scene: scene,
        ids: ids,
        newLineId: 'b',
      );
      expect(r.selectedLayer.lines, hasLength(2));
    });

    test('endpoint touch does not split (T-junction not handled)', () {
      // (0,0)→(100,0) and (50,0)→(50,50) — second wall's start touches
      // the first wall at its midpoint. v1 intentionally skips T-junctions.
      final ids = IdBroker();
      var scene = buildEmptyScene(ids: ids);
      final layer = scene.selectedLayer;
      scene = scene.withSelectedLayer(layer.copyWith(
        vertices: {
          'h1': Vertex(id: 'h1', x: 0, y: 0, lineIds: const {'h'}),
          'h2': Vertex(id: 'h2', x: 100, y: 0, lineIds: const {'h'}),
          'v1': Vertex(id: 'v1', x: 50, y: 0, lineIds: const {'v'}),
          'v2': Vertex(id: 'v2', x: 50, y: 50, lineIds: const {'v'}),
        },
        lines: {
          'h': FloorLine(id: 'h', vertexIds: ['h1', 'h2']),
          'v': FloorLine(id: 'v', vertexIds: ['v1', 'v2']),
        },
      ));
      final r = WallOps.splitAtCrossings(
        scene: scene,
        ids: ids,
        newLineId: 'v',
      );
      // Untouched: both walls survive intact.
      expect(r.selectedLayer.lines, hasLength(2));
      expect(r.selectedLayer.lines.containsKey('h'), isTrue);
      expect(r.selectedLayer.lines.containsKey('v'), isTrue);
    });

    test('new wall crossing two existing walls splits all three correctly', () {
      // Two parallel verticals at x=30 and x=70 spanning y=-50..50.
      // Horizontal wall at y=0 from x=0 to x=100 crosses both.
      final ids = IdBroker();
      var scene = buildEmptyScene(ids: ids);
      final layer = scene.selectedLayer;
      scene = scene.withSelectedLayer(layer.copyWith(
        vertices: {
          'va1': Vertex(id: 'va1', x: 30, y: -50, lineIds: const {'va'}),
          'va2': Vertex(id: 'va2', x: 30, y: 50, lineIds: const {'va'}),
          'vb1': Vertex(id: 'vb1', x: 70, y: -50, lineIds: const {'vb'}),
          'vb2': Vertex(id: 'vb2', x: 70, y: 50, lineIds: const {'vb'}),
          'h1': Vertex(id: 'h1', x: 0, y: 0, lineIds: const {'h'}),
          'h2': Vertex(id: 'h2', x: 100, y: 0, lineIds: const {'h'}),
        },
        lines: {
          'va': FloorLine(id: 'va', vertexIds: ['va1', 'va2']),
          'vb': FloorLine(id: 'vb', vertexIds: ['vb1', 'vb2']),
          'h': FloorLine(id: 'h', vertexIds: ['h1', 'h2']),
        },
      ));

      final r = WallOps.splitAtCrossings(
        scene: scene,
        ids: ids,
        newLineId: 'h',
      );
      // 2 verticals split into 4 + 1 horizontal split into 3 = 7
      expect(r.selectedLayer.lines, hasLength(7));
    });
  });
}
