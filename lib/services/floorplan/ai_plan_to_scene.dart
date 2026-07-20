import 'dart:ui' show Offset;

import '../../models/ai/ai_floorplan_plan.dart';
import '../../models/floorplan/scene.dart';
import '../../utils/floorplan/id_broker.dart';
import 'catalog.dart';
import 'scene_builder.dart';

/// Walks an [AiFloorplanPlan] (the high-level DSL the model emits)
/// and assembles a valid editor [Scene] using the existing builder
/// primitives. The resulting Scene is identical in shape to anything
/// the user might draw by hand — every wall has back-references,
/// every closed loop becomes an Area, every catalog item is bounded
/// to known prototypes.
///
/// Defensive: unknown rooms / prototypes / impossible doors are skipped
/// silently rather than raising, because the model will occasionally
/// hallucinate. We'd rather show the user a partial floorplan they can
/// edit than a hard error.
Scene aiPlanToScene(
  AiFloorplanPlan plan,
  IdBroker ids, {
  Catalog? catalog,
  String name = 'AI floorplan',
}) {
  final cat = catalog ?? defaultCatalog;
  final builder = SceneBuilder(ids: ids, unit: 'cm');

  // Track each room's 4 wall ids in cardinal order so doors / windows
  // can resolve "north wall of Kitchen" or "shared wall between A & B".
  // Walls are added in addWallLoop's order: NE → SE → SW → NW corners,
  // so the wall sequence is [north, east, south, west].
  final roomWalls = <String, _RoomGeometry>{};
  final knownPrototypes =
      cat.all.map((e) => e.prototype.toLowerCase()).toSet();

  for (final room in plan.rooms) {
    if (room.width < 50 || room.height < 50) continue; // skip tiny rooms
    final corners = [
      (x: room.x, y: room.y),
      (x: room.x + room.width, y: room.y),
      (x: room.x + room.width, y: room.y + room.height),
      (x: room.x, y: room.y + room.height),
    ];
    final vertexIds = builder.addWallLoop(corners);
    final lineIds = [
      builder.linesByVertices(vertexIds[0], vertexIds[1]), // north
      builder.linesByVertices(vertexIds[1], vertexIds[2]), // east
      builder.linesByVertices(vertexIds[2], vertexIds[3]), // south
      builder.linesByVertices(vertexIds[3], vertexIds[0]), // west
    ];
    if (lineIds.any((l) => l == null)) continue;
    roomWalls[room.name.toLowerCase()] = _RoomGeometry(
      room: room,
      vertexIds: vertexIds,
      northWallId: lineIds[0]!,
      eastWallId: lineIds[1]!,
      southWallId: lineIds[2]!,
      westWallId: lineIds[3]!,
    );
  }

  for (final door in plan.doors) {
    final from = roomWalls[door.fromRoom.toLowerCase()];
    if (from == null) continue;
    final wallId = door.toRoom == null
        ? from.southWallId
        : _pickFacingWall(from, roomWalls[door.toRoom!.toLowerCase()]);
    if (wallId == null) continue;
    builder.addHole(
      lineId: wallId,
      prototype: 'door',
      offset: door.offset,
      width: door.width.clamp(40.0, 240.0),
    );
  }

  for (final window in plan.windows) {
    final room = roomWalls[window.room.toLowerCase()];
    if (room == null) continue;
    final wallId = room.wallByDirection(window.wall);
    if (wallId == null) continue;
    builder.addHole(
      lineId: wallId,
      prototype: 'window',
      offset: window.offset,
      width: window.width.clamp(40.0, 300.0),
    );
  }

  for (final item in plan.items) {
    if (!knownPrototypes.contains(item.prototype)) continue;
    final room = roomWalls[item.room.toLowerCase()];
    if (room == null) continue;
    final spec = cat.get(item.prototype)!;
    final pos = _itemPositionInRoom(room.room, item.position, spec);
    builder.addItem(
      prototype: item.prototype,
      x: pos.dx,
      y: pos.dy,
      rotation: item.rotation,
      width: spec.defaultWidth,
      height: spec.defaultHeight,
    );
  }

  var scene = builder.build(name: name);
  // The auto-area detector ran inside builder.build(); now name the
  // areas to match the AI's room names by matching vertex sets.
  scene = _nameAreasFromRooms(scene, roomWalls);
  return scene;
}

class _RoomGeometry {
  final AiRoom room;
  final List<String> vertexIds;
  final String northWallId;
  final String eastWallId;
  final String southWallId;
  final String westWallId;

  _RoomGeometry({
    required this.room,
    required this.vertexIds,
    required this.northWallId,
    required this.eastWallId,
    required this.southWallId,
    required this.westWallId,
  });

  /// Center of the room in scene coords.
  Offset get center =>
      Offset(room.x + room.width / 2, room.y + room.height / 2);

  String? wallByDirection(String direction) => switch (direction) {
        'north' || 'top' => northWallId,
        'south' || 'bottom' => southWallId,
        'east' || 'right' => eastWallId,
        'west' || 'left' => westWallId,
        _ => null,
      };
}

/// For an inter-room door: pick the wall of [from] whose midpoint is
/// closest to [to]'s center. That's the wall that "faces" the other
/// room — usually but not always the one a real architect would pick.
String? _pickFacingWall(_RoomGeometry from, _RoomGeometry? to) {
  if (to == null) return from.southWallId; // graceful fallback
  final candidates = [
    (
      id: from.northWallId,
      midpoint:
          Offset(from.room.x + from.room.width / 2, from.room.y),
    ),
    (
      id: from.eastWallId,
      midpoint: Offset(
          from.room.x + from.room.width, from.room.y + from.room.height / 2),
    ),
    (
      id: from.southWallId,
      midpoint: Offset(from.room.x + from.room.width / 2,
          from.room.y + from.room.height),
    ),
    (
      id: from.westWallId,
      midpoint: Offset(from.room.x, from.room.y + from.room.height / 2),
    ),
  ];
  candidates
      .sort((a, b) => (a.midpoint - to.center).distance.compareTo(
            (b.midpoint - to.center).distance,
          ));
  return candidates.first.id;
}

Offset _itemPositionInRoom(
  AiRoom room,
  String position,
  CatalogElement spec,
) {
  final cx = room.x + room.width / 2;
  final cy = room.y + room.height / 2;
  // Inset against the wall by the item's half-extent so it doesn't
  // overlap the wall thickness.
  final ix = spec.defaultWidth / 2 + 30;
  final iy = spec.defaultHeight / 2 + 30;
  return switch (position) {
    'north' || 'top' => Offset(cx, room.y + iy),
    'south' || 'bottom' => Offset(cx, room.y + room.height - iy),
    'east' || 'right' => Offset(room.x + room.width - ix, cy),
    'west' || 'left' => Offset(room.x + ix, cy),
    _ => Offset(cx, cy),
  };
}

/// Rename each auto-detected area to match the AI room whose vertex
/// loop matches it. Areas whose vertex set doesn't match any room
/// keep their default empty name.
Scene _nameAreasFromRooms(
  Scene scene,
  Map<String, _RoomGeometry> roomWalls,
) {
  final layer = scene.selectedLayer;
  if (layer.areas.isEmpty) return scene;
  final areas = Map.of(layer.areas);
  for (final entry in [...areas.entries]) {
    final areaVertexSet = entry.value.vertexIds.toSet();
    for (final geom in roomWalls.values) {
      if (areaVertexSet.length == geom.vertexIds.length &&
          areaVertexSet.containsAll(geom.vertexIds)) {
        final a = areas[entry.key]!;
        areas[entry.key] = a.copyWith(
          properties: {...a.properties, 'name': geom.room.name},
        );
        break;
      }
    }
  }
  return scene.withSelectedLayer(layer.copyWith(areas: areas));
}
