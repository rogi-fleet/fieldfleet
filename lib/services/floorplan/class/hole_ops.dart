import 'dart:ui' show Offset;

import '../../../models/floorplan/hole.dart';
import '../../../models/floorplan/line.dart';
import '../../../models/floorplan/scene.dart';
import '../../../utils/floorplan/geometry.dart';
import '../../../utils/floorplan/id_broker.dart';

/// Static operations on doors / windows. Holes ride on a wall via a
/// normalized offset in `[0, 1]`; placement and movement project a cursor
/// point onto the host wall and snap to the resulting `t`.
class HoleOps {
  const HoleOps._();

  /// Drop a hole onto [lineId] at the wall position closest to [point].
  /// Returns the new scene + the created hole id, or `null` if the wall
  /// no longer exists.
  static ({Scene scene, String holeId})? placeOnWall({
    required Scene scene,
    required IdBroker ids,
    required String lineId,
    required Offset point,
    required String prototype, // 'door' | 'window'
    double width = 80,
  }) {
    var layer = scene.selectedLayer;
    final line = layer.lines[lineId];
    if (line == null) return null;
    final a = layer.vertices[line.vertexIds[0]];
    final b = layer.vertices[line.vertexIds[1]];
    if (a == null || b == null) return null;

    final t = pointPositionOnSegment(
      Offset(a.x, a.y),
      Offset(b.x, b.y),
      point,
    );
    final clampedT = _clampOffset(t, line, scene, width);

    final holeId = ids.hole();
    final hole = Hole(
      id: holeId,
      prototype: prototype,
      lineId: lineId,
      offset: clampedT,
      width: width,
    );

    final holes = Map<String, Hole>.from(layer.holes);
    holes[holeId] = hole;
    final lines = Map<String, FloorLine>.from(layer.lines);
    lines[lineId] = line.copyWith(holeIds: [...line.holeIds, holeId]);

    return (
      scene: scene.withSelectedLayer(layer.copyWith(
        holes: holes,
        lines: lines,
      )),
      holeId: holeId,
    );
  }

  /// Move an existing hole along its wall to the offset closest to [point].
  static Scene moveAlong({
    required Scene scene,
    required String holeId,
    required Offset point,
  }) {
    final layer = scene.selectedLayer;
    final hole = layer.holes[holeId];
    if (hole == null) return scene;
    final line = layer.lines[hole.lineId];
    if (line == null) return scene;
    final a = layer.vertices[line.vertexIds[0]];
    final b = layer.vertices[line.vertexIds[1]];
    if (a == null || b == null) return scene;

    final t = pointPositionOnSegment(
      Offset(a.x, a.y),
      Offset(b.x, b.y),
      point,
    );
    final clampedT = _clampOffset(t, line, scene, hole.width);

    final holes = Map<String, Hole>.from(layer.holes);
    holes[holeId] = hole.copyWith(offset: clampedT);
    return scene.withSelectedLayer(layer.copyWith(holes: holes));
  }

  /// Delete a hole and detach it from its host wall.
  static Scene delete({required Scene scene, required String holeId}) {
    final layer = scene.selectedLayer;
    final hole = layer.holes[holeId];
    if (hole == null) return scene;
    final holes = Map<String, Hole>.from(layer.holes)..remove(holeId);
    final hostLine = layer.lines[hole.lineId];
    final lines = Map<String, FloorLine>.from(layer.lines);
    if (hostLine != null) {
      lines[hostLine.id] = hostLine.copyWith(
        holeIds: hostLine.holeIds.where((id) => id != holeId).toList(),
      );
    }
    return scene.withSelectedLayer(layer.copyWith(
      holes: holes,
      lines: lines,
    ));
  }

  /// Keep the hole inset from each wall end by half its width so the
  /// rendered opening stays inside the wall span.
  static double _clampOffset(
    double t,
    FloorLine line,
    Scene scene,
    double holeWidth,
  ) {
    final a = scene.selectedLayer.vertices[line.vertexIds[0]];
    final b = scene.selectedLayer.vertices[line.vertexIds[1]];
    if (a == null || b == null) return t.clamp(0.0, 1.0);
    final wallLen = pointsDistance(Offset(a.x, a.y), Offset(b.x, b.y));
    if (wallLen < kEpsilon) return t.clamp(0.0, 1.0);
    final inset = (holeWidth / 2) / wallLen;
    final lo = inset.clamp(0.0, 0.5);
    final hi = (1 - inset).clamp(0.5, 1.0);
    return t.clamp(lo, hi);
  }
}
