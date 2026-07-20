import 'package:flutter_test/flutter_test.dart';
import 'package:taskfleet_ops/models/ai/ai_floorplan_edit.dart';
import 'package:taskfleet_ops/models/ai/ai_floorplan_plan.dart';
import 'package:taskfleet_ops/services/floorplan/ai_edit_to_scene.dart';
import 'package:taskfleet_ops/services/floorplan/ai_plan_to_scene.dart';
import 'package:taskfleet_ops/utils/floorplan/id_broker.dart';

void main() {
  // Helper: build a starting scene with a single 4×3m Living Room.
  // Most edit tests start from this baseline so they can poke at it.
  final ids = IdBroker();
  final baseScene = aiPlanToScene(
    const AiFloorplanPlan(
      rooms: [
        AiRoom(name: 'Living Room', x: 0, y: 0, width: 400, height: 300),
      ],
    ),
    ids,
  );

  group('applyAiEdits', () {
    test('AddRoom adds 4 walls + a named area', () {
      final s = applyAiEdits(
        baseScene,
        [
          const AddRoomEdit(
            name: 'Kitchen',
            x: 500,
            y: 0,
            width: 300,
            height: 300,
          ),
        ],
        ids,
      );
      // Living + Kitchen = 8 walls + 2 areas (no phantoms from the
      // multi-component fix in patch 2).
      expect(s.selectedLayer.lines, hasLength(8));
      expect(s.selectedLayer.areas, hasLength(2));
      final names = s.selectedLayer.areas.values
          .map((a) => a.properties['name'] as String?)
          .toSet();
      expect(names, containsAll(['Living Room', 'Kitchen']));
    });

    test('RenameRoom changes the area name in place', () {
      final s = applyAiEdits(
        baseScene,
        [const RenameRoomEdit(from: 'Living Room', to: 'Lounge')],
        ids,
      );
      final names = s.selectedLayer.areas.values
          .map((a) => a.properties['name'] as String?)
          .toSet();
      expect(names, contains('Lounge'));
      expect(names, isNot(contains('Living Room')));
    });

    test('AddDoor places a hole on the chosen room wall', () {
      final s = applyAiEdits(
        baseScene,
        [const AddDoorEdit(fromRoom: 'Living Room', offset: 0.5, width: 90)],
        ids,
      );
      expect(s.selectedLayer.holes, hasLength(1));
      final door = s.selectedLayer.holes.values.first;
      expect(door.prototype, 'door');
    });

    test('AddWindow lands on the named cardinal wall', () {
      final s = applyAiEdits(
        baseScene,
        [const AddWindowEdit(room: 'Living Room', wall: 'north', width: 150)],
        ids,
      );
      expect(s.selectedLayer.holes, hasLength(1));
      expect(s.selectedLayer.holes.values.first.prototype, 'window');
    });

    test('AddItem places a known catalog item in the room', () {
      final s = applyAiEdits(
        baseScene,
        [const AddItemEdit(prototype: 'sofa', room: 'Living Room')],
        ids,
      );
      expect(s.selectedLayer.items, hasLength(1));
      expect(s.selectedLayer.items.values.first.prototype, 'sofa');
    });

    test('RemoveItem deletes the matching item', () {
      var s = applyAiEdits(
        baseScene,
        [const AddItemEdit(prototype: 'sofa', room: 'Living Room')],
        ids,
      );
      expect(s.selectedLayer.items, hasLength(1));
      s = applyAiEdits(
        s,
        [const RemoveItemEdit(prototype: 'sofa', room: 'Living Room')],
        ids,
      );
      expect(s.selectedLayer.items, isEmpty);
    });

    test('RemoveDoor removes the first door on the chosen wall', () {
      var s = applyAiEdits(
        baseScene,
        [const AddDoorEdit(fromRoom: 'Living Room')],
        ids,
      );
      expect(s.selectedLayer.holes, hasLength(1));
      s = applyAiEdits(
        s,
        [const RemoveDoorEdit(fromRoom: 'Living Room')],
        ids,
      );
      expect(s.selectedLayer.holes, isEmpty);
    });

    test('RemoveRoom drops walls + clears area', () {
      // Use a fresh scene with 1 room + 1 sacrificial extra room.
      final fresh = applyAiEdits(
        baseScene,
        [
          const AddRoomEdit(
            name: 'Storage',
            x: 600,
            y: 0,
            width: 200,
            height: 200,
          ),
        ],
        ids,
      );
      expect(fresh.selectedLayer.lines, hasLength(8));
      final removed = applyAiEdits(
        fresh,
        [const RemoveRoomEdit(name: 'Storage')],
        ids,
      );
      // Storage's 4 walls + 4 vertices gone.
      expect(removed.selectedLayer.lines, hasLength(4));
      final names = removed.selectedLayer.areas.values
          .map((a) => a.properties['name'] as String?)
          .where((n) => n != null && n.isNotEmpty)
          .toSet();
      expect(names, isNot(contains('Storage')));
      expect(names, contains('Living Room'));
    });

    test('Op referencing a nonexistent room is skipped', () {
      final s = applyAiEdits(
        baseScene,
        [const RenameRoomEdit(from: 'Phantom', to: 'Real')],
        ids,
      );
      // Scene unchanged.
      expect(s.selectedLayer.areas, hasLength(baseScene.selectedLayer.areas.length));
    });

    test('AddItem with unknown prototype is skipped', () {
      final s = applyAiEdits(
        baseScene,
        [const AddItemEdit(prototype: 'unicorn', room: 'Living Room')],
        ids,
      );
      expect(s.selectedLayer.items, isEmpty);
    });
  });

  group('applyAiEditsWithReport — batch validation', () {
    test('rename ops run before later ops that reference the new name', () {
      // The AI emits add_item then rename — the naive ordering would
      // place the item in "Living Room" (still exists at that moment)
      // and then the rename moves it. We want the same result either
      // way, but more importantly the user can also write
      // [add_item using "Lounge", rename "Living Room" → "Lounge"]
      // and the reorder makes it work.
      final result = applyAiEditsWithReport(
        baseScene,
        const [
          AddItemEdit(prototype: 'sofa', room: 'Lounge'),
          RenameRoomEdit(from: 'Living Room', to: 'Lounge'),
        ],
        ids,
      );
      expect(result.scene.selectedLayer.items, hasLength(1));
      expect(result.warnings, isEmpty);
    });

    test('ops targeting a later-removed room are dropped with a warning',
        () {
      // Add Storage, then [remove_room Storage, add_item in Storage].
      // The add_item should be skipped with a warning since Storage
      // gets removed in the same batch.
      final fresh = applyAiEdits(
        baseScene,
        const [AddRoomEdit(name: 'Storage', x: 500, y: 0, width: 200, height: 200)],
        ids,
      );
      final result = applyAiEditsWithReport(
        fresh,
        const [
          AddItemEdit(prototype: 'sofa', room: 'Storage'),
          RemoveRoomEdit(name: 'Storage'),
        ],
        ids,
      );
      // Sofa is dropped (target room removed later), Storage is gone.
      expect(result.scene.selectedLayer.items, isEmpty);
      expect(result.warnings, hasLength(1));
      expect(result.warnings.first, contains('Storage'));
    });
  });

  group('AiFloorplanEditBatch.fromJson', () {
    test('parses the operations array dispatching on op tag', () {
      final batch = AiFloorplanEditBatch.fromJson(const {
        'operations': [
          {'op': 'add_room', 'name': 'A', 'x': 0, 'y': 0, 'width': 100, 'height': 100},
          {'op': 'rename_room', 'from': 'X', 'to': 'Y'},
          {'op': 'add_item', 'prototype': 'sofa', 'room': 'A'},
          {'op': 'unknown_op', 'foo': 'bar'},
        ],
      });
      expect(batch.operations, hasLength(3));
      expect(batch.operations[0], isA<AddRoomEdit>());
      expect(batch.operations[1], isA<RenameRoomEdit>());
      expect(batch.operations[2], isA<AddItemEdit>());
    });

    test('m unit converts dimensions to cm', () {
      final batch = AiFloorplanEditBatch.fromJson(const {
        'unit': 'm',
        'operations': [
          {'op': 'add_room', 'name': 'A', 'x': 0, 'y': 0, 'width': 4, 'height': 3},
        ],
      });
      final op = batch.operations.first as AddRoomEdit;
      expect(op.width, 400);
      expect(op.height, 300);
    });
  });
}
