import 'dart:ui' show Offset, Rect;

import 'package:flutter_test/flutter_test.dart';
import 'package:taskfleet_ops/services/floorplan/class/room_ops.dart';
import 'package:taskfleet_ops/services/floorplan/scene_io.dart';
import 'package:taskfleet_ops/utils/floorplan/id_broker.dart';

void main() {
  group('RoomOps.addRectangle', () {
    test('creates 4 walls + 1 area + names from default list', () {
      final ids = IdBroker();
      final scene = buildEmptyScene(ids: ids);
      final r = RoomOps.addRectangle(
        scene: scene,
        ids: ids,
        rect: const Rect.fromLTWH(0, 0, 400, 500),
      );
      expect(r.selectedLayer.lines, hasLength(4));
      expect(r.selectedLayer.areas, hasLength(1));
      final area = r.selectedLayer.areas.values.first;
      expect(area.properties['name'], 'Living Room');
    });

    test('subsequent rooms get the next unused default name', () {
      final ids = IdBroker();
      var scene = buildEmptyScene(ids: ids);
      scene = RoomOps.addRectangle(
        scene: scene,
        ids: ids,
        rect: const Rect.fromLTWH(0, 0, 100, 100),
      );
      scene = RoomOps.addRectangle(
        scene: scene,
        ids: ids,
        rect: const Rect.fromLTWH(200, 0, 100, 100),
      );
      final names = scene.selectedLayer.areas.values
          .map((a) => a.properties['name'] as String?)
          .toList();
      expect(names, containsAll(['Living Room', 'Kitchen']));
    });

    test('reverse-direction rect still produces a valid room', () {
      final ids = IdBroker();
      final scene = buildEmptyScene(ids: ids);
      // Drag from bottom-right back to top-left.
      final r = RoomOps.addRectangle(
        scene: scene,
        ids: ids,
        rect: Rect.fromPoints(const Offset(400, 500), const Offset(0, 0)),
      );
      expect(r.selectedLayer.lines, hasLength(4));
      expect(r.selectedLayer.areas, hasLength(1));
    });

    test('degenerate rect is a no-op', () {
      final ids = IdBroker();
      final scene = buildEmptyScene(ids: ids);
      final r = RoomOps.addRectangle(
        scene: scene,
        ids: ids,
        rect: const Rect.fromLTWH(0, 0, 0.5, 100),
      );
      expect(r.selectedLayer.lines, isEmpty);
    });
  });

  group('RoomOps.addPolygon', () {
    test('triangle yields 3 walls + 1 area', () {
      final ids = IdBroker();
      final scene = buildEmptyScene(ids: ids);
      final r = RoomOps.addPolygon(
        scene: scene,
        ids: ids,
        points: const [Offset(0, 0), Offset(100, 0), Offset(50, 80)],
      );
      expect(r.selectedLayer.lines, hasLength(3));
      expect(r.selectedLayer.areas, hasLength(1));
    });

    test('< 3 points returns scene unchanged', () {
      final ids = IdBroker();
      final scene = buildEmptyScene(ids: ids);
      final r = RoomOps.addPolygon(
        scene: scene,
        ids: ids,
        points: const [Offset(0, 0), Offset(10, 10)],
      );
      expect(r.selectedLayer.lines, isEmpty);
    });
  });
}
