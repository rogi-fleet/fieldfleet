import 'dart:ui' show Offset;

import 'package:flutter_test/flutter_test.dart';
import 'package:taskfleet_ops/utils/floorplan/graph_cycles.dart';

void main() {
  group('findInnerCycles', () {
    test('returns empty for no edges', () {
      expect(findInnerCycles(vertices: const {}, edges: const []), isEmpty);
    });

    test('returns empty for an open polyline', () {
      final r = findInnerCycles(
        vertices: const {
          'a': Offset(0, 0),
          'b': Offset(10, 0),
          'c': Offset(10, 10),
        },
        edges: const [(a: 'a', b: 'b'), (a: 'b', b: 'c')],
      );
      expect(r, isEmpty);
    });

    test('finds one square room', () {
      final r = findInnerCycles(
        vertices: const {
          'a': Offset(0, 0),
          'b': Offset(10, 0),
          'c': Offset(10, 10),
          'd': Offset(0, 10),
        },
        edges: const [
          (a: 'a', b: 'b'),
          (a: 'b', b: 'c'),
          (a: 'c', b: 'd'),
          (a: 'd', b: 'a'),
        ],
      );
      expect(r, hasLength(1));
      // One inner cycle, four distinct vertices in the loop.
      expect(r.first.toSet(), {'a', 'b', 'c', 'd'});
    });

    test('finds two adjacent rooms (figure-8 shared wall)', () {
      // Two squares sharing the right edge of the left square == left
      // edge of the right square. 6 vertices, 7 edges; 2 inner faces.
      final r = findInnerCycles(
        vertices: const {
          'a': Offset(0, 0),
          'b': Offset(10, 0),
          'c': Offset(20, 0),
          'd': Offset(20, 10),
          'e': Offset(10, 10),
          'f': Offset(0, 10),
        },
        edges: const [
          (a: 'a', b: 'b'),
          (a: 'b', b: 'c'),
          (a: 'c', b: 'd'),
          (a: 'd', b: 'e'),
          (a: 'e', b: 'f'),
          (a: 'f', b: 'a'),
          (a: 'b', b: 'e'), // shared wall
        ],
      );
      expect(r, hasLength(2));
    });

    test('isolated triangle yields one face', () {
      final r = findInnerCycles(
        vertices: const {
          'a': Offset(0, 0),
          'b': Offset(10, 0),
          'c': Offset(5, 8),
        },
        edges: const [
          (a: 'a', b: 'b'),
          (a: 'b', b: 'c'),
          (a: 'c', b: 'a'),
        ],
      );
      expect(r, hasLength(1));
    });

    test('two disjoint squares produce exactly 2 inner cycles', () {
      // Without the per-component outer-face drop (patch 2), the
      // original implementation dropped a single global outer face
      // and left a phantom 3rd cycle. Verify both rooms come back as
      // inner cycles with no extras.
      final r = findInnerCycles(
        vertices: const {
          'a1': Offset(0, 0),
          'a2': Offset(10, 0),
          'a3': Offset(10, 10),
          'a4': Offset(0, 10),
          'b1': Offset(20, 0),
          'b2': Offset(30, 0),
          'b3': Offset(30, 10),
          'b4': Offset(20, 10),
        },
        edges: const [
          (a: 'a1', b: 'a2'),
          (a: 'a2', b: 'a3'),
          (a: 'a3', b: 'a4'),
          (a: 'a4', b: 'a1'),
          (a: 'b1', b: 'b2'),
          (a: 'b2', b: 'b3'),
          (a: 'b3', b: 'b4'),
          (a: 'b4', b: 'b1'),
        ],
      );
      expect(r, hasLength(2));
    });
  });
}
