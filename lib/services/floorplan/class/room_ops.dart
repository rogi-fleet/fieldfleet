import 'dart:ui' show Offset, Rect;

import '../../../models/floorplan/area.dart';
import '../../../models/floorplan/line.dart';
import '../../../models/floorplan/scene.dart';
import '../../../models/floorplan/vertex.dart';
import '../../../utils/floorplan/id_broker.dart';
import 'area_ops.dart';

/// Static operations on whole rooms — built from the same wall + vertex
/// primitives as everything else, but as a single user-facing action
/// instead of one wall at a time.
class RoomOps {
  const RoomOps._();

  /// Cycle of names a freshly-created room picks from when no name is
  /// provided. Subsequent rooms in the same scene pick the first unused
  /// name — so you get Living Room, Kitchen, Bedroom… without thinking.
  static const List<String> kDefaultRoomNames = [
    'Living Room',
    'Kitchen',
    'Bedroom',
    'Bathroom',
    'Hall',
    'Office',
    'Dining Room',
    'Closet',
    'Laundry',
    'Entryway',
    'Garage',
    'Patio',
    'Storage',
  ];

  static String pickNextRoomName(Scene scene) {
    final used = scene.layers.values
        .expand((l) => l.areas.values)
        .map((a) => (a.properties['name'] as String?)?.trim() ?? '')
        .where((n) => n.isNotEmpty)
        .toSet();
    for (final candidate in kDefaultRoomNames) {
      if (!used.contains(candidate)) return candidate;
    }
    return 'Room ${used.length + 1}';
  }

  /// Drop a 4-wall rectangular room with the given [rect] (scene coords).
  /// Auto-areas recompute so the new room appears immediately. The new
  /// area is named with [pickNextRoomName].
  static Scene addRectangle({
    required Scene scene,
    required IdBroker ids,
    required Rect rect,
    String? name,
  }) {
    if (rect.width.abs() < 1 || rect.height.abs() < 1) return scene;
    // Rect can be in any direction; build a normalized version with
    // (left, top) being the min corner so the resulting polygon is
    // always counter-clockwise as viewed in screen coords.
    final left = rect.left < rect.right ? rect.left : rect.right;
    final right = rect.left < rect.right ? rect.right : rect.left;
    final top = rect.top < rect.bottom ? rect.top : rect.bottom;
    final bottom = rect.top < rect.bottom ? rect.bottom : rect.top;
    return _addPolygon(
      scene: scene,
      ids: ids,
      points: [
        Offset(left, top),
        Offset(right, top),
        Offset(right, bottom),
        Offset(left, bottom),
      ],
      name: name,
    );
  }

  /// Drop a closed polygonal room with the given [points] in order.
  /// First and last points should NOT be the same — the closing wall is
  /// added implicitly. Returns the scene with the new walls + area, or
  /// the original scene if there are fewer than 3 points.
  static Scene addPolygon({
    required Scene scene,
    required IdBroker ids,
    required List<Offset> points,
    String? name,
  }) {
    if (points.length < 3) return scene;
    return _addPolygon(scene: scene, ids: ids, points: points, name: name);
  }

  static Scene _addPolygon({
    required Scene scene,
    required IdBroker ids,
    required List<Offset> points,
    String? name,
  }) {
    var s = scene;
    var layer = s.selectedLayer;

    // Allocate vertices for every point.
    final vertexIds = <String>[];
    final vertices = Map<String, Vertex>.from(layer.vertices);
    for (final p in points) {
      final id = ids.vertex();
      vertices[id] = Vertex(id: id, x: p.dx, y: p.dy);
      vertexIds.add(id);
    }
    layer = layer.copyWith(vertices: vertices);

    // Add walls connecting consecutive vertices, closing back to the
    // first.
    final lines = Map<String, FloorLine>.from(layer.lines);
    for (var i = 0; i < vertexIds.length; i++) {
      final a = vertexIds[i];
      final b = vertexIds[(i + 1) % vertexIds.length];
      final lineId = ids.line();
      lines[lineId] = FloorLine(id: lineId, vertexIds: [a, b]);
      // Update vertex back-refs.
      final va = vertices[a]!;
      vertices[a] = va.copyWith(lineIds: {...va.lineIds, lineId});
      final vb = vertices[b]!;
      vertices[b] = vb.copyWith(lineIds: {...vb.lineIds, lineId});
    }
    layer = layer.copyWith(vertices: vertices, lines: lines);
    s = s.withSelectedLayer(layer);

    // Recompute auto-areas, then name the room we just created.
    s = AreaOps.recompute(scene: s, ids: ids);
    final layerAfter = s.selectedLayer;
    final newName = name ?? pickNextRoomName(s);
    final freshArea = layerAfter.areas.values
        .where((a) => a.vertexIds.toSet().containsAll(vertexIds.toSet()))
        .firstOrNull;
    if (freshArea != null) {
      final areas = Map<String, Area>.from(layerAfter.areas);
      areas[freshArea.id] = freshArea.copyWith(
        properties: {...freshArea.properties, 'name': newName},
      );
      s = s.withSelectedLayer(layerAfter.copyWith(areas: areas));
    }
    return s;
  }
}
