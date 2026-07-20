import '../../models/floorplan/hole.dart';
import '../../models/floorplan/item.dart';
import '../../models/floorplan/layer.dart';
import '../../models/floorplan/line.dart';
import '../../models/floorplan/scene.dart';
import '../../models/floorplan/vertex.dart';
import '../../utils/floorplan/id_broker.dart';
import 'class/area_ops.dart';

/// Imperative builder used by preset definitions.
///
/// Wraps id allocation and the vertex back-reference bookkeeping so
/// preset scenes read like a list of construction steps. The terminal
/// [build] call assembles a [Scene] and runs [AreaOps.recompute] so any
/// closed wall loops auto-promote to rooms.
class SceneBuilder {
  SceneBuilder({
    IdBroker? ids,
    this.unit = 'cm',
    this.width = 2000,
    this.height = 2000,
    this.gridSize = 20,
  }) : ids = ids ?? IdBroker() {
    _layerId = this.ids.layer();
  }

  final IdBroker ids;
  final String unit;
  final double width;
  final double height;
  final double gridSize;

  late final String _layerId;
  final Map<String, Vertex> _vertices = {};
  final Map<String, FloorLine> _lines = {};
  final Map<String, Hole> _holes = {};
  final Map<String, Item> _items = {};

  /// Add a vertex at the given scene-coords. Returns its id.
  String addVertex(double x, double y) {
    final id = ids.vertex();
    _vertices[id] = Vertex(id: id, x: x, y: y);
    return id;
  }

  /// Connect two existing vertices with a wall and update vertex
  /// back-references. Returns the wall id.
  String addWall(String fromVertexId, String toVertexId,
      {double thickness = 20}) {
    final id = ids.line();
    _lines[id] = FloorLine(
      id: id,
      vertexIds: [fromVertexId, toVertexId],
      thickness: thickness,
    );
    _attachLineToVertex(fromVertexId, id);
    _attachLineToVertex(toVertexId, id);
    return id;
  }

  /// Add a sequence of walls connecting consecutive points. The last
  /// segment closes back to the first if [close] is true. Returns the
  /// list of created vertex ids in order.
  List<String> addWallLoop(
    List<({double x, double y})> points, {
    bool close = true,
    double thickness = 20,
  }) {
    final vIds = points
        .map((p) => addVertex(p.x.toDouble(), p.y.toDouble()))
        .toList();
    for (var i = 0; i < vIds.length - 1; i++) {
      addWall(vIds[i], vIds[i + 1], thickness: thickness);
    }
    if (close && vIds.length >= 3) {
      addWall(vIds.last, vIds.first, thickness: thickness);
    }
    return vIds;
  }

  /// Look up a wall by its endpoint vertex ids (in either order).
  /// Returns null if no wall connects them — useful when a preset wants
  /// to drop a door on a wall that addWallLoop just created without
  /// surfacing the wall id directly.
  String? linesByVertices(String a, String b) {
    for (final entry in _lines.entries) {
      final v = entry.value.vertexIds;
      if ((v[0] == a && v[1] == b) || (v[0] == b && v[1] == a)) {
        return entry.key;
      }
    }
    return null;
  }

  /// Drop a door or window onto a wall at normalized [offset] (0..1).
  String addHole({
    required String lineId,
    required String prototype,
    double offset = 0.5,
    double width = 80,
    double height = 200,
  }) {
    final id = ids.hole();
    _holes[id] = Hole(
      id: id,
      prototype: prototype,
      lineId: lineId,
      offset: offset,
      width: width,
      height: height,
    );
    final line = _lines[lineId];
    if (line != null) {
      _lines[lineId] = line.copyWith(holeIds: [...line.holeIds, id]);
    }
    return id;
  }

  /// Place an item (furniture / fixture) at scene-coords [x],[y].
  String addItem({
    required String prototype,
    required double x,
    required double y,
    double rotation = 0,
    double width = 100,
    double height = 100,
  }) {
    final id = ids.item();
    _items[id] = Item(
      id: id,
      prototype: prototype,
      x: x,
      y: y,
      rotation: rotation,
      width: width,
      height: height,
    );
    return id;
  }

  /// Finalize the builder into a [Scene]. Auto-areas are recomputed so
  /// closed wall loops show up as rooms.
  Scene build({String name = 'New Floorplan'}) {
    final layer = Layer(
      id: _layerId,
      name: 'Default',
      vertices: _vertices,
      lines: _lines,
      holes: _holes,
      items: _items,
    );
    final scene = Scene(
      id: ids.scene(),
      name: name,
      unit: unit,
      width: width,
      height: height,
      gridSize: gridSize,
      selectedLayerId: _layerId,
      layers: {_layerId: layer},
    );
    return AreaOps.recompute(scene: scene, ids: ids);
  }

  void _attachLineToVertex(String vertexId, String lineId) {
    final v = _vertices[vertexId];
    if (v == null) return;
    _vertices[vertexId] = v.copyWith(lineIds: {...v.lineIds, lineId});
  }
}
