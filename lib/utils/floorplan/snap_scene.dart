import 'dart:ui' show Offset;

import '../../models/floorplan/scene.dart';
import 'snap.dart';

/// Build the per-frame snap index from the current [Scene].
///
/// Strategy:
///   - One [PointSnap] per vertex (highest priority).
///   - One [LineSegmentSnap] per wall (so the cursor can latch onto a
///     wall mid-span — the home for door/window placement).
///   - One [GridSnap] (lowest priority).
///
/// Vertices currently being moved should be passed in [excludedVertexIds]
/// so they don't snap to themselves while being dragged.
///
/// Lines currently being drawn should be passed in [excludedLineIds] so an
/// in-flight wall doesn't try to snap to itself.
List<Snap> sceneSnaps(
  Scene scene, {
  Set<String> excludedVertexIds = const {},
  Set<String> excludedLineIds = const {},
  bool includeGrid = true,
}) {
  final layer = scene.selectedLayer;
  final out = <Snap>[];

  for (final v in layer.vertices.values) {
    if (excludedVertexIds.contains(v.id)) continue;
    out.add(PointSnap(
      point: Offset(v.x, v.y),
      metadata: {'vertexId': v.id},
    ));
  }

  for (final entry in layer.lines.entries) {
    if (excludedLineIds.contains(entry.key)) continue;
    final line = entry.value;
    final a = layer.vertices[line.vertexIds[0]];
    final b = layer.vertices[line.vertexIds[1]];
    if (a == null || b == null) continue;
    out.add(LineSegmentSnap(
      a: Offset(a.x, a.y),
      b: Offset(b.x, b.y),
      metadata: {'lineId': entry.key},
    ));
  }

  if (includeGrid && scene.gridSize > 0) {
    out.add(GridSnap(step: scene.gridSize));
  }

  return out;
}
