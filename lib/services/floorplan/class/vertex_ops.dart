import '../../../models/floorplan/layer.dart';
import '../../../models/floorplan/vertex.dart';

/// Helpers that maintain the [Vertex] back-reference invariants
/// (`lineIds` / `areaIds` always reflect the lines/areas that actually
/// reference the vertex). All graph mutations should funnel through here.
class VertexOps {
  const VertexOps._();

  /// Add (or upsert) a vertex at `(x, y)` and link it to [lineId] (and
  /// optionally [areaId]). Returns the new layer + the vertex used.
  ///
  /// If a vertex already exists at [reuseExistingId], that one is updated
  /// in place; otherwise a new one is allocated with [vertexId].
  static ({Layer layer, Vertex vertex}) addOrReuse({
    required Layer layer,
    required String vertexId,
    required double x,
    required double y,
    String? lineId,
    String? areaId,
    String? reuseExistingId,
  }) {
    final id = reuseExistingId ?? vertexId;
    final existing = layer.vertices[id];
    final next = (existing ??
            Vertex(id: id, x: x, y: y))
        .copyWith(
      x: x,
      y: y,
      lineIds: lineId == null
          ? existing?.lineIds
          : {...?existing?.lineIds, lineId},
      areaIds: areaId == null
          ? existing?.areaIds
          : {...?existing?.areaIds, areaId},
    );
    final vertices = Map<String, Vertex>.from(layer.vertices);
    vertices[id] = next;
    return (layer: layer.copyWith(vertices: vertices), vertex: next);
  }

  /// Remove a vertex's reference to a line/area. If the vertex has no
  /// remaining references, it is deleted from the layer (matches
  /// react-planner's `Vertex.remove` semantics).
  static Layer detach({
    required Layer layer,
    required String vertexId,
    String? lineId,
    String? areaId,
  }) {
    final v = layer.vertices[vertexId];
    if (v == null) return layer;
    final lineIds = lineId == null
        ? v.lineIds
        : v.lineIds.where((id) => id != lineId).toSet();
    final areaIds = areaId == null
        ? v.areaIds
        : v.areaIds.where((id) => id != areaId).toSet();
    final vertices = Map<String, Vertex>.from(layer.vertices);
    if (lineIds.isEmpty && areaIds.isEmpty) {
      vertices.remove(vertexId);
    } else {
      vertices[vertexId] = v.copyWith(lineIds: lineIds, areaIds: areaIds);
    }
    return layer.copyWith(vertices: vertices);
  }
}
