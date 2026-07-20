import 'dart:ui' show Offset;

import '../../../models/floorplan/area.dart';
import '../../../models/floorplan/scene.dart';
import '../../../models/floorplan/vertex.dart';
import '../../../utils/floorplan/graph_cycles.dart';
import '../../../utils/floorplan/id_broker.dart';

/// Auto-derive [Area] entities from closed wall loops in the current
/// selected layer. Run after [WallOps] mutations finish (typically
/// `END_DRAWING_WALL` and wall delete).
class AreaOps {
  const AreaOps._();

  /// Replace the layer's areas with whatever closed loops the wall graph
  /// currently bounds. Existing area IDs are reused when the same vertex
  /// loop is detected, so selection / property-inspector state survives a
  /// recompute.
  static Scene recompute({required Scene scene, required IdBroker ids}) {
    final layer = scene.selectedLayer;
    final vertexOffsets = <String, Offset>{
      for (final v in layer.vertices.values) v.id: Offset(v.x, v.y),
    };
    final edges = <({String a, String b})>[];
    for (final line in layer.lines.values) {
      if (line.vertexIds.length < 2) continue;
      edges.add((a: line.vertexIds[0], b: line.vertexIds[1]));
    }

    final cycles = findInnerCycles(
      vertices: vertexOffsets,
      edges: edges,
    );

    // Build a stable signature for each cycle so we can match it against
    // an existing Area and preserve its id/properties.
    String signatureFor(List<String> cycle) {
      final dedup = cycle.toSet().toList()..sort();
      return dedup.join(',');
    }

    final priorBySignature = <String, Area>{
      for (final a in layer.areas.values) signatureFor(a.vertexIds): a,
    };

    final newAreas = <String, Area>{};
    final touchedVertexIds = <String, Set<String>>{};
    for (final cycle in cycles) {
      // Drop the duplicated trailing vertex from the closed loop.
      final loop = cycle.length > 1 && cycle.first == cycle.last
          ? cycle.sublist(0, cycle.length - 1)
          : cycle;
      final sig = signatureFor(loop);
      final prior = priorBySignature[sig];
      final id = prior?.id ?? ids.area();
      newAreas[id] = (prior ?? Area(id: id, vertexIds: loop)).copyWith(
        vertexIds: loop,
      );
      for (final vid in loop) {
        touchedVertexIds.putIfAbsent(vid, () => {}).add(id);
      }
    }

    // Update vertex back-references — areaIds set should reflect the new
    // membership. Do this without disturbing lineIds.
    final vertices = Map<String, Vertex>.from(layer.vertices);
    vertexOffsets.keys.toList().forEach((vid) {
      final v = vertices[vid];
      if (v == null) return;
      final nextAreaIds = touchedVertexIds[vid] ?? const <String>{};
      if (v.areaIds.length == nextAreaIds.length &&
          v.areaIds.containsAll(nextAreaIds)) {
        return;
      }
      vertices[vid] = v.copyWith(areaIds: nextAreaIds);
    });

    return scene.withSelectedLayer(layer.copyWith(
      areas: newAreas,
      vertices: vertices,
    ));
  }
}
