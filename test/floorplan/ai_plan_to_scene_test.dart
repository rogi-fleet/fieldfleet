import 'package:flutter_test/flutter_test.dart';
import 'package:taskfleet_ops/models/ai/ai_floorplan_plan.dart';
import 'package:taskfleet_ops/services/floorplan/ai_plan_to_scene.dart';
import 'package:taskfleet_ops/utils/floorplan/id_broker.dart';

void main() {
  group('aiPlanToScene', () {
    test('single room produces 4 walls + 1 named area', () {
      final scene = aiPlanToScene(
        const AiFloorplanPlan(
          rooms: [
            AiRoom(name: 'Living Room', x: 0, y: 0, width: 400, height: 300),
          ],
        ),
        IdBroker(),
      );
      expect(scene.selectedLayer.lines, hasLength(4));
      expect(scene.selectedLayer.areas, hasLength(1));
      final area = scene.selectedLayer.areas.values.first;
      expect(area.properties['name'], 'Living Room');
    });

    test('two rooms produce 8 walls + 2 named areas', () {
      final scene = aiPlanToScene(
        const AiFloorplanPlan(
          rooms: [
            AiRoom(name: 'Living Room', x: 0, y: 0, width: 400, height: 300),
            AiRoom(name: 'Kitchen', x: 500, y: 0, width: 300, height: 300),
          ],
        ),
        IdBroker(),
      );
      expect(scene.selectedLayer.lines, hasLength(8));
      // Per-component outer-face dropping (patch 2) means disjoint
      // rooms produce exactly one area per room — no phantoms.
      expect(scene.selectedLayer.areas, hasLength(2));
      final names = scene.selectedLayer.areas.values
          .map((a) => a.properties['name'] as String?)
          .toSet();
      expect(names, containsAll(['Living Room', 'Kitchen']));
    });

    test('exterior door lands on the south wall of the from-room', () {
      final scene = aiPlanToScene(
        const AiFloorplanPlan(
          rooms: [
            AiRoom(name: 'Foyer', x: 0, y: 0, width: 300, height: 300),
          ],
          doors: [AiDoor(fromRoom: 'Foyer', offset: 0.5, width: 90)],
        ),
        IdBroker(),
      );
      expect(scene.selectedLayer.holes, hasLength(1));
      final door = scene.selectedLayer.holes.values.first;
      expect(door.prototype, 'door');
    });

    test('inter-room door picks the wall of from-room facing to-room', () {
      // Two rooms side by side: Living to the left, Kitchen to the right.
      // Door between them should land on Living's east wall (the one
      // closest to Kitchen's center).
      final scene = aiPlanToScene(
        const AiFloorplanPlan(
          rooms: [
            AiRoom(name: 'Living Room', x: 0, y: 0, width: 400, height: 300),
            AiRoom(name: 'Kitchen', x: 500, y: 0, width: 300, height: 300),
          ],
          doors: [AiDoor(fromRoom: 'Living Room', toRoom: 'Kitchen')],
        ),
        IdBroker(),
      );
      expect(scene.selectedLayer.holes, hasLength(1));
      final door = scene.selectedLayer.holes.values.first;
      // The door's host wall should connect Living's two right corners
      // (i.e. its east wall).
      final hostWall = scene.selectedLayer.lines[door.lineId]!;
      final v1 = scene.selectedLayer.vertices[hostWall.vertexIds[0]]!;
      final v2 = scene.selectedLayer.vertices[hostWall.vertexIds[1]]!;
      // Both endpoints of the host wall sit at x = 400 (Living's right edge).
      expect(v1.x, closeTo(400, 0.01));
      expect(v2.x, closeTo(400, 0.01));
    });

    test('window on a named wall lands as a window prototype', () {
      final scene = aiPlanToScene(
        const AiFloorplanPlan(
          rooms: [
            AiRoom(name: 'Bedroom', x: 0, y: 0, width: 400, height: 400),
          ],
          windows: [
            AiWindow(room: 'Bedroom', wall: 'north', width: 150),
          ],
        ),
        IdBroker(),
      );
      expect(scene.selectedLayer.holes, hasLength(1));
      expect(
        scene.selectedLayer.holes.values.first.prototype,
        'window',
      );
    });

    test('item with known prototype is placed in the named room center',
        () {
      final scene = aiPlanToScene(
        const AiFloorplanPlan(
          rooms: [
            AiRoom(name: 'Lounge', x: 0, y: 0, width: 600, height: 400),
          ],
          items: [
            AiItem(prototype: 'sofa', room: 'Lounge', position: 'center'),
          ],
        ),
        IdBroker(),
      );
      expect(scene.selectedLayer.items, hasLength(1));
      final sofa = scene.selectedLayer.items.values.first;
      expect(sofa.prototype, 'sofa');
      expect(sofa.x, closeTo(300, 1)); // room center x
      expect(sofa.y, closeTo(200, 1)); // room center y
    });

    test('unknown item prototype is silently dropped', () {
      final scene = aiPlanToScene(
        const AiFloorplanPlan(
          rooms: [
            AiRoom(name: 'Den', x: 0, y: 0, width: 400, height: 400),
          ],
          items: [
            AiItem(prototype: 'unicorn', room: 'Den'),
          ],
        ),
        IdBroker(),
      );
      expect(scene.selectedLayer.items, isEmpty);
    });

    test('door referencing a nonexistent room is silently dropped', () {
      final scene = aiPlanToScene(
        const AiFloorplanPlan(
          rooms: [
            AiRoom(name: 'A', x: 0, y: 0, width: 400, height: 400),
          ],
          doors: [
            AiDoor(fromRoom: 'B', toRoom: 'A'),
          ],
        ),
        IdBroker(),
      );
      expect(scene.selectedLayer.holes, isEmpty);
    });

    test('tiny room (width < 50 cm) is skipped entirely', () {
      final scene = aiPlanToScene(
        const AiFloorplanPlan(
          rooms: [
            AiRoom(name: 'Sliver', x: 0, y: 0, width: 10, height: 10),
            AiRoom(name: 'Real', x: 100, y: 0, width: 300, height: 300),
          ],
        ),
        IdBroker(),
      );
      expect(scene.selectedLayer.areas, hasLength(1));
      expect(
        scene.selectedLayer.areas.values.first.properties['name'],
        'Real',
      );
    });
  });

  group('AiFloorplanPlan.fromJson', () {
    test('default unit is cm', () {
      final p = AiFloorplanPlan.fromJson(const {
        'rooms': [
          {'name': 'A', 'x': 0, 'y': 0, 'width': 400, 'height': 300},
        ],
      });
      expect(p.rooms.first.width, 400);
    });

    test('m unit converts to cm', () {
      final p = AiFloorplanPlan.fromJson(const {
        'unit': 'm',
        'rooms': [
          {'name': 'A', 'x': 0, 'y': 0, 'width': 4, 'height': 3},
        ],
      });
      expect(p.rooms.first.width, 400);
      expect(p.rooms.first.height, 300);
    });

    test('door in `between` array form is parsed correctly', () {
      final p = AiFloorplanPlan.fromJson(const {
        'rooms': [],
        'doors': [
          {'between': ['Living', 'Kitchen'], 'offset': 0.4},
        ],
      });
      expect(p.doors.first.fromRoom, 'Living');
      expect(p.doors.first.toRoom, 'Kitchen');
      expect(p.doors.first.offset, 0.4);
    });
  });
}
