import 'dart:ui' show Offset, Rect;

import '../../models/ai/ai_floorplan_edit.dart';
import '../../models/floorplan/area.dart';
import '../../models/floorplan/line.dart';
import '../../models/floorplan/scene.dart';
import '../../models/floorplan/vertex.dart';
import '../../utils/floorplan/id_broker.dart';
import 'catalog.dart';
import 'class/area_ops.dart';
import 'class/hole_ops.dart';
import 'class/item_ops.dart';
import 'class/room_ops.dart';
import 'class/wall_ops.dart';

/// Apply a list of [AiFloorplanEdit] operations to a [Scene]. Each op
/// is defensive — references to nonexistent rooms / items are skipped
/// silently rather than failing the whole batch. Returns the new
/// scene; callers wrap in `beginTransientEdit` / `endTransientEdit`
/// so the entire batch is one undo step.
///
/// Use [applyAiEditsWithReport] to get back a list of warnings about
/// ops that were dropped due to ordering conflicts or missing
/// references.
Scene applyAiEdits(
  Scene scene,
  List<AiFloorplanEdit> ops,
  IdBroker ids, {
  Catalog? catalog,
}) {
  return applyAiEditsWithReport(scene, ops, ids, catalog: catalog).scene;
}

/// Result of applying an AI edit batch with diagnostics. [warnings]
/// is a human-readable list of problems (e.g. "Skipped add_door:
/// Kitchen was removed earlier in the batch"). UI surfaces this so
/// the user knows when the AI fought itself.
class AiEditResult {
  final Scene scene;
  final List<String> warnings;
  const AiEditResult({required this.scene, required this.warnings});
}

AiEditResult applyAiEditsWithReport(
  Scene scene,
  List<AiFloorplanEdit> ops,
  IdBroker ids, {
  Catalog? catalog,
}) {
  final cat = catalog ?? defaultCatalog;
  // Pre-pass: reorder rename ops before any op that depends on the
  // renamed room's NEW name; track which rooms get removed; warn on
  // ops that target a soon-to-be-removed room.
  final reordered = _reorderAndValidate(ops);
  var s = scene;
  for (final op in reordered.ops) {
    s = switch (op) {
      AddRoomEdit() => _addRoom(s, op, ids),
      RemoveRoomEdit() => _removeRoom(s, op, ids),
      RenameRoomEdit() => _renameRoom(s, op),
      AddDoorEdit() => _addDoor(s, op, ids),
      RemoveDoorEdit() => _removeDoor(s, op),
      AddWindowEdit() => _addWindow(s, op, ids),
      AddItemEdit() => _addItem(s, op, ids, cat),
      RemoveItemEdit() => _removeItem(s, op),
    };
  }
  return AiEditResult(scene: s, warnings: reordered.warnings);
}

/// Detect and fix ordering issues in an AI-emitted op batch:
///   - moves rename_room ops to the front so subsequent ops can
///     reference either the old or new name
///   - drops ops that target a room which a later remove_room
///     op deletes (with a warning, since the remove "wins")
({List<AiFloorplanEdit> ops, List<String> warnings}) _reorderAndValidate(
  List<AiFloorplanEdit> ops,
) {
  final warnings = <String>[];

  // Drop ops whose target room gets removed later in the batch.
  final filtered = <AiFloorplanEdit>[];
  for (var i = 0; i < ops.length; i++) {
    final op = ops[i];
    final laterRemovedNames = {
      for (var j = i + 1; j < ops.length; j++)
        if (ops[j] is RemoveRoomEdit)
          (ops[j] as RemoveRoomEdit).name.toLowerCase(),
    };
    final targetsRemovedRoom = switch (op) {
      AddDoorEdit() =>
        laterRemovedNames.contains(op.fromRoom.toLowerCase()) ||
            (op.toRoom != null &&
                laterRemovedNames.contains(op.toRoom!.toLowerCase())),
      RemoveDoorEdit() =>
        laterRemovedNames.contains(op.fromRoom.toLowerCase()),
      AddWindowEdit() => laterRemovedNames.contains(op.room.toLowerCase()),
      AddItemEdit() => laterRemovedNames.contains(op.room.toLowerCase()),
      RemoveItemEdit() =>
        op.room != null && laterRemovedNames.contains(op.room!.toLowerCase()),
      _ => false,
    };
    if (targetsRemovedRoom) {
      warnings.add(
        'Skipped ${_opLabel(op)} — its target room is removed later in '
        'the batch.',
      );
      continue;
    }
    filtered.add(op);
  }

  // Move rename_room ops to the front so anything in the same batch
  // can use the new name.
  final renames = filtered.whereType<RenameRoomEdit>().toList();
  final others = filtered.where((op) => op is! RenameRoomEdit).toList();
  return (ops: [...renames, ...others], warnings: warnings);
}

String _opLabel(AiFloorplanEdit op) => switch (op) {
      AddRoomEdit() => 'add_room("${op.name}")',
      RemoveRoomEdit() => 'remove_room("${op.name}")',
      RenameRoomEdit() => 'rename_room("${op.from}" → "${op.to}")',
      AddDoorEdit() => 'add_door(from="${op.fromRoom}")',
      RemoveDoorEdit() => 'remove_door(from="${op.fromRoom}")',
      AddWindowEdit() => 'add_window(room="${op.room}")',
      AddItemEdit() => 'add_item(${op.prototype} in "${op.room}")',
      RemoveItemEdit() => 'remove_item(${op.prototype})',
    };

// ---------------------------------------------------------------------------
// Room ops
// ---------------------------------------------------------------------------

Scene _addRoom(Scene scene, AddRoomEdit op, IdBroker ids) {
  // Snapshot wall ids that exist before we add the room — anything
  // new after this call belongs to the room. Each new wall might
  // cross existing walls; without splitAtCrossings the resulting
  // graph is broken (walls overlap with no shared vertex), and
  // _findRoomGeometry on the new room will fail because the auto-
  // area detector can't close the loop. That silently no-ops every
  // subsequent op in the AI batch.
  final beforeLineIds = scene.selectedLayer.lines.keys.toSet();
  var next = RoomOps.addRectangle(
    scene: scene,
    ids: ids,
    rect: Rect.fromLTWH(op.x, op.y, op.width, op.height),
    name: op.name,
  );
  final newLineIds = next.selectedLayer.lines.keys
      .where((id) => !beforeLineIds.contains(id))
      .toList();
  // Track whether any split actually fired. If none did (the common
  // case — non-overlapping rooms), the first recompute inside
  // addRectangle already produced the right graph + area names. A
  // second recompute can drop named areas via a known sig-collision
  // bug in AreaOps.recompute (filed as tech debt). Only re-run when
  // we actually mutated the wall graph past addRectangle.
  var splitOccurred = false;
  for (final lineId in newLineIds) {
    final after = WallOps.splitAtCrossings(
      scene: next,
      ids: ids,
      newLineId: lineId,
    );
    if (!identical(after, next)) splitOccurred = true;
    next = after;
  }
  return splitOccurred
      ? AreaOps.recompute(scene: next, ids: ids)
      : next;
}

Scene _removeRoom(Scene scene, RemoveRoomEdit op, IdBroker ids) {
  final layer = scene.selectedLayer;
  // Find the area whose name matches.
  final area = layer.areas.values
      .where((a) => (a.properties['name'] as String?) == op.name)
      .firstOrNull;
  if (area == null) return scene;
  // Delete every wall whose endpoints are both in the room's vertex
  // set, plus its hosted holes.
  final vSet = area.vertexIds.toSet();
  final wallsToRemove = <String>[];
  layer.lines.forEach((id, line) {
    if (line.vertexIds.length < 2) return;
    if (vSet.contains(line.vertexIds[0]) &&
        vSet.contains(line.vertexIds[1])) {
      wallsToRemove.add(id);
    }
  });
  if (wallsToRemove.isEmpty) return scene;
  var s = scene;
  // Cascade hole deletion first.
  for (final wallId in wallsToRemove) {
    final wall = s.selectedLayer.lines[wallId];
    if (wall == null) continue;
    for (final holeId in [...wall.holeIds]) {
      s = HoleOps.delete(scene: s, holeId: holeId);
    }
  }
  // Drop walls + orphaned vertices.
  var nextLayer = s.selectedLayer;
  final lines = Map<String, FloorLine>.from(nextLayer.lines);
  final vertices = Map<String, Vertex>.from(nextLayer.vertices);
  for (final wallId in wallsToRemove) {
    lines.remove(wallId);
  }
  // Recompute vertex back-refs and drop any vertex with no remaining
  // references.
  for (final vid in vSet) {
    final v = vertices[vid];
    if (v == null) continue;
    final stillUsed = v.lineIds.any((lid) => lines.containsKey(lid));
    if (!stillUsed) {
      vertices.remove(vid);
    } else {
      vertices[vid] = v.copyWith(
        lineIds: v.lineIds
            .where((lid) => lines.containsKey(lid))
            .toSet(),
      );
    }
  }
  nextLayer = nextLayer.copyWith(lines: lines, vertices: vertices);
  s = s.withSelectedLayer(nextLayer);
  // Recompute auto-areas — the deleted room's area entry will be gone.
  return AreaOps.recompute(scene: s, ids: ids);
}

Scene _renameRoom(Scene scene, RenameRoomEdit op) {
  final layer = scene.selectedLayer;
  final entry = layer.areas.entries
      .where((e) => (e.value.properties['name'] as String?) == op.from)
      .firstOrNull;
  if (entry == null) return scene;
  final areas = Map<String, Area>.from(layer.areas);
  areas[entry.key] = entry.value.copyWith(
    properties: {...entry.value.properties, 'name': op.to},
  );
  return scene.withSelectedLayer(layer.copyWith(areas: areas));
}

// ---------------------------------------------------------------------------
// Door / window ops
// ---------------------------------------------------------------------------

Scene _addDoor(Scene scene, AddDoorEdit op, IdBroker ids) {
  final from = _findRoomGeometry(scene, op.fromRoom);
  if (from == null) return scene;
  final wallId = op.toRoom == null
      ? from.southWallId
      : _facingWall(from, _findRoomGeometry(scene, op.toRoom!));
  if (wallId == null) return scene;
  final r = HoleOps.placeOnWall(
    scene: scene,
    ids: ids,
    lineId: wallId,
    point: _wallPointAtOffset(scene, wallId, op.offset),
    prototype: 'door',
    width: op.width.clamp(40.0, 240.0),
  );
  return r?.scene ?? scene;
}

Scene _removeDoor(Scene scene, RemoveDoorEdit op) {
  final from = _findRoomGeometry(scene, op.fromRoom);
  if (from == null) return scene;
  final wallId = op.toRoom == null
      ? from.southWallId
      : _facingWall(from, _findRoomGeometry(scene, op.toRoom!));
  if (wallId == null) return scene;
  final layer = scene.selectedLayer;
  final wall = layer.lines[wallId];
  if (wall == null || wall.holeIds.isEmpty) return scene;
  // Remove the first door on this wall (most likely the one the AI
  // is referring to). For removal of a specific door at offset, the
  // model can re-issue a more specific edit later.
  final doorId = wall.holeIds.firstWhere(
    (id) => layer.holes[id]?.prototype == 'door',
    orElse: () => '',
  );
  if (doorId.isEmpty) return scene;
  return HoleOps.delete(scene: scene, holeId: doorId);
}

Scene _addWindow(Scene scene, AddWindowEdit op, IdBroker ids) {
  final geom = _findRoomGeometry(scene, op.room);
  if (geom == null) return scene;
  final wallId = geom.wallByDirection(op.wall);
  if (wallId == null) return scene;
  final r = HoleOps.placeOnWall(
    scene: scene,
    ids: ids,
    lineId: wallId,
    point: _wallPointAtOffset(scene, wallId, op.offset),
    prototype: 'window',
    width: op.width.clamp(40.0, 300.0),
  );
  return r?.scene ?? scene;
}

// ---------------------------------------------------------------------------
// Item ops
// ---------------------------------------------------------------------------

Scene _addItem(
  Scene scene,
  AddItemEdit op,
  IdBroker ids,
  Catalog catalog,
) {
  final spec = catalog.get(op.prototype);
  if (spec == null) return scene;
  final geom = _findRoomGeometry(scene, op.room);
  if (geom == null) return scene;
  final pos = _positionInRoom(geom, op.position, spec);
  final r = ItemOps.place(
    scene: scene,
    ids: ids,
    catalog: catalog,
    prototype: op.prototype,
    x: pos.dx,
    y: pos.dy,
    rotation: op.rotation,
  );
  return r?.scene ?? scene;
}

Scene _removeItem(Scene scene, RemoveItemEdit op) {
  final layer = scene.selectedLayer;
  // Match the first item with the matching prototype, optionally
  // restricted to a named room.
  String? hitId;
  if (op.room != null) {
    final geom = _findRoomGeometry(scene, op.room!);
    if (geom == null) return scene;
    final rect = Rect.fromLTWH(
      geom.room.x,
      geom.room.y,
      geom.room.width,
      geom.room.height,
    );
    hitId = layer.items.entries
        .where((e) =>
            e.value.prototype == op.prototype &&
            rect.contains(Offset(e.value.x, e.value.y)))
        .map((e) => e.key)
        .firstOrNull;
  } else {
    hitId = layer.items.entries
        .where((e) => e.value.prototype == op.prototype)
        .map((e) => e.key)
        .firstOrNull;
  }
  if (hitId == null) return scene;
  return ItemOps.delete(scene: scene, itemId: hitId);
}

// ---------------------------------------------------------------------------
// Geometry helpers (shared with the from-scratch adapter's ideas)
// ---------------------------------------------------------------------------

class _RoomGeometry {
  final ({String name, double x, double y, double width, double height}) room;
  final String areaId;
  final String northWallId;
  final String eastWallId;
  final String southWallId;
  final String westWallId;
  _RoomGeometry({
    required this.room,
    required this.areaId,
    required this.northWallId,
    required this.eastWallId,
    required this.southWallId,
    required this.westWallId,
  });

  String? wallByDirection(String dir) => switch (dir) {
        'north' || 'top' => northWallId,
        'south' || 'bottom' => southWallId,
        'east' || 'right' => eastWallId,
        'west' || 'left' => westWallId,
        _ => null,
      };
}

/// Look up a room by name and figure out its bounding rect + four
/// cardinal walls. Works on areas the user (or a previous AI run)
/// added, not just rectangle rooms — anything axis-aligned with 4
/// vertices.
_RoomGeometry? _findRoomGeometry(Scene scene, String name) {
  final layer = scene.selectedLayer;
  final areaEntry = layer.areas.entries
      .where((e) =>
          (e.value.properties['name'] as String?)?.toLowerCase() ==
          name.toLowerCase())
      .firstOrNull;
  if (areaEntry == null) return null;
  final vertexIds = areaEntry.value.vertexIds;
  if (vertexIds.length < 4) return null;
  // Compute bounding rect from vertex positions.
  var minX = double.infinity;
  var minY = double.infinity;
  var maxX = double.negativeInfinity;
  var maxY = double.negativeInfinity;
  for (final id in vertexIds) {
    final v = layer.vertices[id];
    if (v == null) return null;
    if (v.x < minX) minX = v.x;
    if (v.y < minY) minY = v.y;
    if (v.x > maxX) maxX = v.x;
    if (v.y > maxY) maxY = v.y;
  }
  // Find walls connecting consecutive vertices and classify by
  // orientation (horizontal at minY = north, etc.).
  String? northWall;
  String? southWall;
  String? eastWall;
  String? westWall;
  for (final lineEntry in layer.lines.entries) {
    final line = lineEntry.value;
    if (line.vertexIds.length < 2) continue;
    if (!vertexIds.contains(line.vertexIds[0]) ||
        !vertexIds.contains(line.vertexIds[1])) {
      continue;
    }
    final a = layer.vertices[line.vertexIds[0]];
    final b = layer.vertices[line.vertexIds[1]];
    if (a == null || b == null) continue;
    final isHoriz = (a.y - b.y).abs() < 0.5;
    final isVert = (a.x - b.x).abs() < 0.5;
    if (isHoriz) {
      if ((a.y - minY).abs() < 0.5) {
        northWall = lineEntry.key;
      } else if ((a.y - maxY).abs() < 0.5) {
        southWall = lineEntry.key;
      }
    } else if (isVert) {
      if ((a.x - maxX).abs() < 0.5) {
        eastWall = lineEntry.key;
      } else if ((a.x - minX).abs() < 0.5) {
        westWall = lineEntry.key;
      }
    }
  }
  if (northWall == null ||
      southWall == null ||
      eastWall == null ||
      westWall == null) {
    return null;
  }
  return _RoomGeometry(
    room: (
      name: name,
      x: minX,
      y: minY,
      width: maxX - minX,
      height: maxY - minY,
    ),
    areaId: areaEntry.key,
    northWallId: northWall,
    eastWallId: eastWall,
    southWallId: southWall,
    westWallId: westWall,
  );
}

String? _facingWall(_RoomGeometry from, _RoomGeometry? to) {
  if (to == null) return from.southWallId;
  final candidates = <(String id, Offset midpoint)>[
    (
      from.northWallId,
      Offset(from.room.x + from.room.width / 2, from.room.y),
    ),
    (
      from.eastWallId,
      Offset(
          from.room.x + from.room.width, from.room.y + from.room.height / 2),
    ),
    (
      from.southWallId,
      Offset(from.room.x + from.room.width / 2,
          from.room.y + from.room.height),
    ),
    (
      from.westWallId,
      Offset(from.room.x, from.room.y + from.room.height / 2),
    ),
  ];
  final toCenter =
      Offset(to.room.x + to.room.width / 2, to.room.y + to.room.height / 2);
  candidates.sort((a, b) =>
      (a.$2 - toCenter).distance.compareTo((b.$2 - toCenter).distance));
  return candidates.first.$1;
}

Offset _wallPointAtOffset(Scene scene, String wallId, double t) {
  final layer = scene.selectedLayer;
  final wall = layer.lines[wallId];
  if (wall == null) return Offset.zero;
  final a = layer.vertices[wall.vertexIds[0]];
  final b = layer.vertices[wall.vertexIds[1]];
  if (a == null || b == null) return Offset.zero;
  return Offset(a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t);
}

Offset _positionInRoom(
  _RoomGeometry geom,
  String position,
  CatalogElement spec,
) {
  final cx = geom.room.x + geom.room.width / 2;
  final cy = geom.room.y + geom.room.height / 2;
  final ix = spec.defaultWidth / 2 + 30;
  final iy = spec.defaultHeight / 2 + 30;
  return switch (position) {
    'north' || 'top' => Offset(cx, geom.room.y + iy),
    'south' || 'bottom' => Offset(cx, geom.room.y + geom.room.height - iy),
    'east' || 'right' =>
      Offset(geom.room.x + geom.room.width - ix, cy),
    'west' || 'left' => Offset(geom.room.x + ix, cy),
    _ => Offset(cx, cy),
  };
}
