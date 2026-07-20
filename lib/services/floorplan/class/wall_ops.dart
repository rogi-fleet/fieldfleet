import 'dart:ui' show Offset;

import '../../../models/floorplan/editor_mode.dart';
import '../../../models/floorplan/hole.dart';
import '../../../models/floorplan/layer.dart';
import '../../../models/floorplan/line.dart';
import '../../../models/floorplan/scene.dart';
import '../../../models/floorplan/vertex.dart';
import '../../../utils/floorplan/geometry.dart';
import '../../../utils/floorplan/id_broker.dart';
import 'vertex_ops.dart';

/// Static operations on walls. Each method takes a [Scene] (and any extra
/// inputs) and returns a new scene + (when relevant) the next [EditorMode].
///
/// This is the Dart analog of react-planner's `src/class/line.js` —
/// reducer-free, returns plain values.
class WallOps {
  const WallOps._();

  /// Begin drawing a wall: create the start vertex (or reuse one near [x],[y]),
  /// the end vertex at the same point, and a wall connecting them.
  static ({Scene scene, EditorMode mode}) begin({
    required Scene scene,
    required IdBroker ids,
    required double x,
    required double y,
    double snapDistance = 8.0,
  }) {
    var layer = scene.selectedLayer;

    // Reuse a near-by existing vertex if any.
    final reuseId = _vertexNear(layer, Offset(x, y), snapDistance);

    final startVertexId = reuseId ?? ids.vertex();
    final endVertexId = ids.vertex();
    final lineId = ids.line();

    final addStart = VertexOps.addOrReuse(
      layer: layer,
      vertexId: startVertexId,
      reuseExistingId: reuseId,
      x: x,
      y: y,
      lineId: lineId,
    );
    final addEnd = VertexOps.addOrReuse(
      layer: addStart.layer,
      vertexId: endVertexId,
      x: x,
      y: y,
      lineId: lineId,
    );
    layer = addEnd.layer;

    final lines = Map<String, FloorLine>.from(layer.lines);
    lines[lineId] = FloorLine(
      id: lineId,
      vertexIds: [addStart.vertex.id, addEnd.vertex.id],
    );

    return (
      scene: scene.withSelectedLayer(layer.copyWith(lines: lines)),
      mode: DrawingWallMode(
        pendingLineId: lineId,
        startVertexId: addStart.vertex.id,
        endVertexId: addEnd.vertex.id,
      ),
    );
  }

  /// Update the in-flight wall's end vertex while the user drags.
  static Scene update({
    required Scene scene,
    required DrawingWallMode mode,
    required double x,
    required double y,
  }) {
    final layer = scene.selectedLayer;
    final endVertex = layer.vertices[mode.endVertexId];
    if (endVertex == null) return scene;
    final vertices = Map<String, Vertex>.from(layer.vertices);
    vertices[mode.endVertexId] = endVertex.copyWith(x: x, y: y);
    return scene.withSelectedLayer(layer.copyWith(vertices: vertices));
  }

  /// Commit the in-flight wall. If start and end snap to the same vertex
  /// (zero-length wall), the wall + provisional vertices are discarded.
  /// Returns `(scene, IdleMode)` regardless.
  static ({Scene scene, EditorMode mode}) end({
    required Scene scene,
    required DrawingWallMode mode,
    required double x,
    required double y,
    double snapDistance = 8.0,
  }) {
    var layer = scene.selectedLayer;
    final start = layer.vertices[mode.startVertexId];
    if (start == null) {
      return (scene: scene, mode: const IdleMode());
    }

    // If the user released on top of an existing vertex (other than the
    // start one we just created), merge the end into that one.
    final mergeId = _vertexNear(
      layer,
      Offset(x, y),
      snapDistance,
      excludeId: mode.endVertexId,
    );

    if (mergeId != null &&
        mergeId != mode.endVertexId &&
        mergeId != mode.startVertexId) {
      // Re-target the line's end to mergeId, drop the provisional endVertex.
      final line = layer.lines[mode.pendingLineId];
      if (line == null) return (scene: scene, mode: const IdleMode());
      final updatedLine = line.copyWith(
        vertexIds: [mode.startVertexId, mergeId],
      );
      final lines = Map<String, FloorLine>.from(layer.lines);
      lines[updatedLine.id] = updatedLine;
      layer = layer.copyWith(lines: lines);
      // attach line back-reference to mergeId, drop the provisional end vertex
      final attached = VertexOps.addOrReuse(
        layer: layer,
        vertexId: mergeId,
        reuseExistingId: mergeId,
        x: layer.vertices[mergeId]!.x,
        y: layer.vertices[mergeId]!.y,
        lineId: updatedLine.id,
      );
      layer = VertexOps.detach(
        layer: attached.layer,
        vertexId: mode.endVertexId,
        lineId: updatedLine.id,
      );
      return (
        scene: scene.withSelectedLayer(layer),
        mode: const IdleMode(),
      );
    }

    // Discard zero-length walls (incl. start-vertex self-merge above).
    if (mergeId == mode.startVertexId ||
        samePoints(Offset(start.x, start.y), Offset(x, y), epsilon: 0.5)) {
      return (
        scene: _discardWall(scene, mode),
        mode: const IdleMode(),
      );
    }

    // Otherwise, finalize end vertex at the cursor.
    final end = layer.vertices[mode.endVertexId];
    if (end == null) return (scene: scene, mode: const IdleMode());

    final vertices = Map<String, Vertex>.from(layer.vertices);
    vertices[mode.endVertexId] = end.copyWith(x: x, y: y);
    return (
      scene: scene.withSelectedLayer(layer.copyWith(vertices: vertices)),
      mode: const IdleMode(),
    );
  }

  /// Cancel the in-flight wall (Esc key / right-click).
  static Scene cancel({required Scene scene, required DrawingWallMode mode}) =>
      _discardWall(scene, mode);

  /// Split a wall at parameter [tSplit] in `(0, 1)`, producing two new walls
  /// joined at a fresh vertex. Existing holes are reassigned to whichever
  /// new wall they end up on, with offsets **rescaled** so they stay at
  /// the same world position.
  ///
  /// This is the fiddly part of react-planner — see `src/class/line.js`
  /// `Line.split`. The math:
  ///   - hole on original wall at offset `t`
  ///   - if `t <= tSplit` → goes on wall A→S, new offset = `t / tSplit`
  ///   - if `t >  tSplit` → goes on wall S→B, new offset = `(t - tSplit) / (1 - tSplit)`
  ///
  /// Returns the new scene + the new vertex id (the split point) + ids of
  /// the two resulting walls. Returns `null` if [tSplit] is outside
  /// `(epsilon, 1-epsilon)` or the wall doesn't exist.
  static ({
    Scene scene,
    String splitVertexId,
    String firstLineId,
    String secondLineId,
  })? split({
    required Scene scene,
    required IdBroker ids,
    required String lineId,
    required double tSplit,
  }) {
    if (tSplit <= kEpsilon || tSplit >= 1 - kEpsilon) return null;

    var layer = scene.selectedLayer;
    final original = layer.lines[lineId];
    if (original == null) return null;
    final a = layer.vertices[original.vertexIds[0]];
    final b = layer.vertices[original.vertexIds[1]];
    if (a == null || b == null) return null;

    // Refuse the split if any hole's [offset - w/2, offset + w/2]
    // window straddles tSplit. Without this the rescale below sends
    // the hole's CENTER to one side but its half-extent runs off the
    // wall's end (or onto the wrong side of the split). Better to
    // skip the split than to silently corrupt door geometry —
    // splitAtCrossings will treat null as "no split happened" and
    // leave both walls intact.
    final wallLen = pointsDistance(Offset(a.x, a.y), Offset(b.x, b.y));
    if (wallLen >= kEpsilon) {
      for (final holeId in original.holeIds) {
        final hole = layer.holes[holeId];
        if (hole == null) continue;
        final halfExtentT = (hole.width / 2) / wallLen;
        final lo = hole.offset - halfExtentT;
        final hi = hole.offset + halfExtentT;
        if (lo < tSplit && tSplit < hi) {
          return null;
        }
      }
    }

    // 1. Allocate the split vertex at lerp(a, b, tSplit).
    final splitPoint = lerpPoints(Offset(a.x, a.y), Offset(b.x, b.y), tSplit);
    final splitVertexId = ids.vertex();

    // 2. Allocate the two new wall ids; the original wall is discarded.
    final firstId = ids.line();
    final secondId = ids.line();

    // 3. Reassign holes to whichever new wall they fall on, rescaling
    //    their offsets so they keep their world position.
    final firstHoleIds = <String>[];
    final secondHoleIds = <String>[];
    final updatedHoles = Map<String, Hole>.from(layer.holes);
    for (final holeId in original.holeIds) {
      final hole = updatedHoles[holeId];
      if (hole == null) continue;
      if (hole.offset <= tSplit) {
        final newT = (hole.offset / tSplit).clamp(0.0, 1.0);
        updatedHoles[holeId] = hole.copyWith(lineId: firstId, offset: newT);
        firstHoleIds.add(holeId);
      } else {
        final newT = ((hole.offset - tSplit) / (1 - tSplit)).clamp(0.0, 1.0);
        updatedHoles[holeId] = hole.copyWith(lineId: secondId, offset: newT);
        secondHoleIds.add(holeId);
      }
    }

    // 4. Build the new walls.
    final firstWall = FloorLine(
      id: firstId,
      prototype: original.prototype,
      vertexIds: [original.vertexIds[0], splitVertexId],
      holeIds: firstHoleIds,
      thickness: original.thickness,
      properties: original.properties,
    );
    final secondWall = FloorLine(
      id: secondId,
      prototype: original.prototype,
      vertexIds: [splitVertexId, original.vertexIds[1]],
      holeIds: secondHoleIds,
      thickness: original.thickness,
      properties: original.properties,
    );

    // 5. Update vertex back-references: detach old line from a/b, attach
    //    new ones, add the split vertex.
    layer = VertexOps.detach(
      layer: layer,
      vertexId: original.vertexIds[0],
      lineId: original.id,
    );
    layer = VertexOps.detach(
      layer: layer,
      vertexId: original.vertexIds[1],
      lineId: original.id,
    );
    final addA = VertexOps.addOrReuse(
      layer: layer,
      vertexId: original.vertexIds[0],
      reuseExistingId: original.vertexIds[0],
      x: a.x,
      y: a.y,
      lineId: firstId,
    );
    final addB = VertexOps.addOrReuse(
      layer: addA.layer,
      vertexId: original.vertexIds[1],
      reuseExistingId: original.vertexIds[1],
      x: b.x,
      y: b.y,
      lineId: secondId,
    );
    layer = addB.layer;
    final splitVertex = Vertex(
      id: splitVertexId,
      x: splitPoint.dx,
      y: splitPoint.dy,
      lineIds: {firstId, secondId},
    );
    final vertices = Map<String, Vertex>.from(layer.vertices);
    vertices[splitVertexId] = splitVertex;

    final lines = Map<String, FloorLine>.from(layer.lines)
      ..remove(original.id)
      ..[firstId] = firstWall
      ..[secondId] = secondWall;

    return (
      scene: scene.withSelectedLayer(
        layer.copyWith(
          vertices: vertices,
          lines: lines,
          holes: updatedHoles,
        ),
      ),
      splitVertexId: splitVertexId,
      firstLineId: firstId,
      secondLineId: secondId,
    );
  }

  static Scene _discardWall(Scene scene, DrawingWallMode mode) {
    var layer = scene.selectedLayer;
    final lines = Map<String, FloorLine>.from(layer.lines)
      ..remove(mode.pendingLineId);
    layer = layer.copyWith(lines: lines);
    layer = VertexOps.detach(
      layer: layer,
      vertexId: mode.startVertexId,
      lineId: mode.pendingLineId,
    );
    layer = VertexOps.detach(
      layer: layer,
      vertexId: mode.endVertexId,
      lineId: mode.pendingLineId,
    );
    return scene.withSelectedLayer(layer);
  }

  /// After a new wall is committed, scan the layer for any other wall it
  /// crosses and split both at each X-crossing. Hole offsets get rescaled
  /// by the underlying [split] op.
  ///
  /// X-crossings only — T-junctions (one wall's endpoint lying on the
  /// other's interior) are intentionally skipped for v1 to avoid the
  /// coincident-vertex pitfalls.
  static Scene splitAtCrossings({
    required Scene scene,
    required IdBroker ids,
    required String newLineId,
  }) {
    var s = scene;
    final layer = s.selectedLayer;
    final newLine = layer.lines[newLineId];
    if (newLine == null) return s;
    final a = layer.vertices[newLine.vertexIds[0]];
    final b = layer.vertices[newLine.vertexIds[1]];
    if (a == null || b == null) return s;
    final aP = Offset(a.x, a.y);
    final bP = Offset(b.x, b.y);

    // Collect X-crossings against every other wall, sorted by distance
    // from the new wall's start so we can walk the new-wall tail forward.
    final crossings = <({
      String otherLineId,
      Offset point,
      double distFromA,
    })>[];
    for (final entry in layer.lines.entries) {
      if (entry.key == newLineId) continue;
      final other = entry.value;
      final oa = layer.vertices[other.vertexIds[0]];
      final ob = layer.vertices[other.vertexIds[1]];
      if (oa == null || ob == null) continue;
      final oaP = Offset(oa.x, oa.y);
      final obP = Offset(ob.x, ob.y);
      final hit = twoLinesIntersection(aP, bP, oaP, obP);
      if (hit == null) continue;
      final tNew = pointPositionOnSegment(aP, bP, hit);
      final tOther = pointPositionOnSegment(oaP, obP, hit);
      // Strictly inside both — skip endpoints (T-junctions).
      if (tNew <= kEpsilon || tNew >= 1 - kEpsilon) continue;
      if (tOther <= kEpsilon || tOther >= 1 - kEpsilon) continue;
      // Verify the projected hit is actually close to the math-only
      // intersection (handles colinear-segment edge cases).
      if (pointsDistance(closestPointOnSegment(aP, bP, hit), hit) > 0.5) {
        continue;
      }
      crossings.add((
        otherLineId: entry.key,
        point: hit,
        distFromA: pointsDistance(aP, hit),
      ));
    }
    if (crossings.isEmpty) return s;

    crossings.sort((x, y) => x.distFromA.compareTo(y.distFromA));

    // Walk the new wall front-to-back: at each crossing split both the
    // other wall and the current new-wall tail, then merge the two
    // coincident split vertices into one so the crossing is degree-4
    // (not two stacked degree-2 vertices).
    var currentTailId = newLineId;
    for (final c in crossings) {
      final layer = s.selectedLayer;

      String? otherSplitVertexId;
      final other = layer.lines[c.otherLineId];
      if (other != null) {
        final oa = layer.vertices[other.vertexIds[0]];
        final ob = layer.vertices[other.vertexIds[1]];
        if (oa != null && ob != null) {
          final tOther = pointPositionOnSegment(
            Offset(oa.x, oa.y),
            Offset(ob.x, ob.y),
            c.point,
          );
          if (tOther > kEpsilon && tOther < 1 - kEpsilon) {
            final r = WallOps.split(
              scene: s,
              ids: ids,
              lineId: c.otherLineId,
              tSplit: tOther,
            );
            if (r != null) {
              s = r.scene;
              otherSplitVertexId = r.splitVertexId;
            }
          }
        }
      }

      // Now split the current new-wall tail at the crossing.
      final freshLayer = s.selectedLayer;
      final tail = freshLayer.lines[currentTailId];
      if (tail == null) continue;
      final ta = freshLayer.vertices[tail.vertexIds[0]];
      final tb = freshLayer.vertices[tail.vertexIds[1]];
      if (ta == null || tb == null) continue;
      final tTail = pointPositionOnSegment(
        Offset(ta.x, ta.y),
        Offset(tb.x, tb.y),
        c.point,
      );
      if (tTail <= kEpsilon || tTail >= 1 - kEpsilon) continue;
      final r = WallOps.split(
        scene: s,
        ids: ids,
        lineId: currentTailId,
        tSplit: tTail,
      );
      if (r == null) continue;
      s = r.scene;
      currentTailId = r.secondLineId;

      // Merge the new-wall split vertex into the other-wall split vertex
      // so the X-crossing is one degree-4 vertex.
      if (otherSplitVertexId != null &&
          otherSplitVertexId != r.splitVertexId) {
        s = _mergeVertices(
          scene: s,
          keepId: otherSplitVertexId,
          dropId: r.splitVertexId,
        );
      }
    }
    return s;
  }

  /// Replace every reference to [dropId] with [keepId] in the selected
  /// layer's lines and areas, fold [dropId]'s back-references into
  /// [keepId], then delete [dropId] from the vertex map.
  static Scene _mergeVertices({
    required Scene scene,
    required String keepId,
    required String dropId,
  }) {
    final layer = scene.selectedLayer;
    final dropV = layer.vertices[dropId];
    final keepV = layer.vertices[keepId];
    if (dropV == null || keepV == null) return scene;

    // Rewrite line vertex references.
    final lines = Map<String, FloorLine>.from(layer.lines);
    for (final entry in [...lines.entries]) {
      final l = entry.value;
      if (!l.vertexIds.contains(dropId)) continue;
      final next = l.vertexIds
          .map((id) => id == dropId ? keepId : id)
          .toList();
      lines[entry.key] = l.copyWith(vertexIds: next);
    }

    // Rewrite area vertex references.
    final areas = Map.of(layer.areas);
    for (final entry in [...areas.entries]) {
      final a = entry.value;
      if (!a.vertexIds.contains(dropId)) continue;
      final next = a.vertexIds
          .map((id) => id == dropId ? keepId : id)
          .toList();
      areas[entry.key] = a.copyWith(vertexIds: next);
    }

    // Merge back-references.
    final mergedKeep = keepV.copyWith(
      lineIds: {...keepV.lineIds, ...dropV.lineIds},
      areaIds: {...keepV.areaIds, ...dropV.areaIds},
    );

    final vertices = Map<String, Vertex>.from(layer.vertices)
      ..[keepId] = mergedKeep
      ..remove(dropId);

    return scene.withSelectedLayer(layer.copyWith(
      vertices: vertices,
      lines: lines,
      areas: areas,
    ));
  }

  static String? _vertexNear(
    Layer layer,
    Offset p,
    double maxDistance, {
    String? excludeId,
  }) {
    String? best;
    var bestDist = maxDistance;
    layer.vertices.forEach((id, v) {
      if (id == excludeId) return;
      final d = pointsDistance(Offset(v.x, v.y), p);
      if (d < bestDist) {
        bestDist = d;
        best = id;
      }
    });
    return best;
  }
}
