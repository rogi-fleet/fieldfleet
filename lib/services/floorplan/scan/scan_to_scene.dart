import 'dart:math' as math;

import '../../../models/floorplan/area.dart';
import '../../../models/floorplan/hole.dart';
import '../../../models/floorplan/layer.dart';
import '../../../models/floorplan/line.dart';
import '../../../models/floorplan/scan/floor_plan_scan_result.dart';
import '../../../models/floorplan/scene.dart';
import '../../../models/floorplan/vertex.dart';
import '../../../utils/floorplan/id_broker.dart';

/// Convert a [FloorPlanScanResult] (metres, scan world frame) into a [Scene]
/// (cm, editor frame).
///
/// One scanned room becomes one wall loop + one [Area]. Openings become
/// [Hole]s on the appropriate wall, with `offset` normalised into `[0, 1]`.
/// Multi-room scans share a single layer — wall loops sit side-by-side in
/// scene-space.
///
/// Two public entry points:
///
///   * [convert] — produce a brand-new [Scene] from a scan. The caller
///     persists it as a new plan.
///   * [appendInto] — merge a scan into an existing [Scene]'s selected
///     layer. Used when the user scans room 2 of a plan they already
///     started.
class ScanToScene {
  static const double _metersToCm = 100.0;

  /// Default wall thickness in scene units (cm). Matches the editor's
  /// default in [FloorLine.thickness].
  static const double _defaultWallThicknessCm = 20.0;

  /// Padding (cm) between scanned geometry and the canvas edge (or, in
  /// the append path, between the new room and the existing geometry).
  static const double _paddingCm = 200.0;

  /// Build a brand-new scene from a scan.
  static Scene convert(
    FloorPlanScanResult result, {
    IdBroker? ids,
    String? sceneName,
  }) {
    final broker = ids ?? IdBroker();
    final layerId = broker.layer();
    final patch = _buildScanGeometry(result, broker);
    final ceilingHeightCm = _resolveCeilingHeight(result);

    if (!patch.hasGeometry) {
      return Scene(
        id: broker.scene(),
        name: _sceneName(sceneName, result),
        ceilingHeightCm: ceilingHeightCm,
        selectedLayerId: layerId,
        layers: {
          layerId: Layer(id: layerId, name: 'Default', order: 0),
        },
      );
    }
    // Shift the geometry so the bbox sits at [_paddingCm, _paddingCm].
    final shiftX = _paddingCm - patch.minX;
    final shiftY = _paddingCm - patch.minY;
    final shifted = _shiftVertices(patch.vertices, shiftX, shiftY);

    final canvasWidth =
        (patch.maxX - patch.minX + 2 * _paddingCm).clamp(1000.0, 100000.0);
    final canvasHeight =
        (patch.maxY - patch.minY + 2 * _paddingCm).clamp(1000.0, 100000.0);

    final layer = Layer(
      id: layerId,
      name: 'Default',
      order: 0,
      vertices: shifted,
      lines: patch.lines,
      holes: patch.holes,
      areas: patch.areas,
    );

    return Scene(
      id: broker.scene(),
      name: _sceneName(sceneName, result),
      width: canvasWidth,
      height: canvasHeight,
      ceilingHeightCm: ceilingHeightCm,
      selectedLayerId: layerId,
      layers: {layerId: layer},
    );
  }

  /// Append a scan's geometry to the selected layer of [scene]. The new
  /// room is placed [`_paddingCm`] to the right of the existing geometry
  /// (or at canvas origin + padding when the scene is empty). The
  /// returned scene preserves the existing layer's identity and order;
  /// only the selected layer's element maps grow.
  ///
  /// The scene canvas widens automatically if the appended geometry
  /// would otherwise spill past the current width. We never shrink the
  /// canvas — the user may already be relying on it for off-canvas
  /// staging space.
  ///
  /// If the scene has no walls yet, this is equivalent to [convert]
  /// landed onto the existing scene's id + layer id. If the scan
  /// produced no geometry, the scene is returned unchanged.
  static Scene appendInto(
    Scene scene,
    FloorPlanScanResult result, {
    IdBroker? ids,
  }) {
    final broker = ids ?? IdBroker();
    final patch = _buildScanGeometry(result, broker);
    if (!patch.hasGeometry) return scene;

    final layer = scene.selectedLayer;

    // Compute where to place the new geometry — to the right of any
    // existing geometry, with [_paddingCm] of clearance. When the layer
    // is empty fall back to canvas origin + padding (same as convert()).
    final existingBounds = _vertexBounds(layer.vertices);
    final targetMinX = existingBounds == null
        ? _paddingCm
        : existingBounds.maxX + _paddingCm;
    final targetMinY = existingBounds?.minY ?? _paddingCm;

    final shiftX = targetMinX - patch.minX;
    final shiftY = targetMinY - patch.minY;
    final shiftedVertices = _shiftVertices(patch.vertices, shiftX, shiftY);

    // Compose the new layer maps by union. The id broker has already
    // produced ids in disjoint namespaces, so straight `addAll` is safe.
    final mergedVertices = <String, Vertex>{
      ...layer.vertices,
      ...shiftedVertices,
    };
    final mergedLines = <String, FloorLine>{
      ...layer.lines,
      ...patch.lines,
    };
    final mergedHoles = <String, Hole>{
      ...layer.holes,
      ...patch.holes,
    };
    final mergedAreas = <String, Area>{
      ...layer.areas,
      ...patch.areas,
    };

    final newLayer = layer.copyWith(
      vertices: mergedVertices,
      lines: mergedLines,
      holes: mergedHoles,
      areas: mergedAreas,
    );

    // Grow the canvas if the new geometry extends past it.
    final newGeometryRight =
        patch.maxX + shiftX + _paddingCm;
    final newGeometryBottom =
        patch.maxY + shiftY + _paddingCm;
    final canvasWidth = math.max(scene.width, newGeometryRight);
    final canvasHeight = math.max(scene.height, newGeometryBottom);

    return scene
        .withSelectedLayer(newLayer)
        .copyWith(width: canvasWidth, height: canvasHeight);
  }

  // ── private: shared geometry build ────────────────────────────────────

  /// Walk every scanned room + opening once, emit vertices/walls/holes/
  /// areas in scan-world cm. The caller decides where to place this
  /// geometry in scene-space via a uniform translation.
  static _ScanPatch _buildScanGeometry(
    FloorPlanScanResult result,
    IdBroker broker,
  ) {
    final vertices = <String, Vertex>{};
    final lines = <String, FloorLine>{};
    final holes = <String, Hole>{};
    final areas = <String, Area>{};
    final wallIdsByRoom = <String, List<String>>{};
    final edgeEndpointsByRoom =
        <String, List<({String start, String end})>>{};

    double minX = double.infinity, minY = double.infinity;
    double maxX = double.negativeInfinity, maxY = double.negativeInfinity;

    // Per-wall overrides are only emitted when a wall's height differs
    // from the scan's reference ceiling by more than this many metres.
    // Inside the tolerance, walls inherit the scene default — keeps the
    // editor's "Height" field empty for the common flat-ceiling case.
    const perWallToleranceMeters = 0.20;

    final referenceCeilingMeters = _resolveReferenceCeilingMeters(result);

    for (final room in result.rooms) {
      final polygon = room.floorPolygonMeters;
      if (polygon.length < 3) {
        wallIdsByRoom[room.id] = const [];
        edgeEndpointsByRoom[room.id] = const [];
        continue;
      }

      final worldXY = polygon
          .map((p) => _applyPose(p, room.roomToWorld))
          .map((p) => (x: p.x * _metersToCm, y: p.y * _metersToCm))
          .toList(growable: false);

      for (final p in worldXY) {
        if (p.x < minX) minX = p.x;
        if (p.y < minY) minY = p.y;
        if (p.x > maxX) maxX = p.x;
        if (p.y > maxY) maxY = p.y;
      }

      final roomVertexIds = <String>[];
      for (final p in worldXY) {
        final id = broker.vertex();
        roomVertexIds.add(id);
        vertices[id] = Vertex(id: id, x: p.x, y: p.y);
      }

      // Per-wall height array, when present, is indexed parallel to the
      // polygon's edges. Reject it if the length doesn't match — we'd
      // rather use the scene default than apply the wrong height.
      final perWall = room.perWallHeightsMeters;
      final useWallHeights = perWall != null &&
          perWall.length == roomVertexIds.length &&
          referenceCeilingMeters != null;

      final wallIds = <String>[];
      final edgeEndpoints = <({String start, String end})>[];
      for (var i = 0; i < roomVertexIds.length; i++) {
        final a = roomVertexIds[i];
        final b = roomVertexIds[(i + 1) % roomVertexIds.length];
        final lineId = broker.line();
        wallIds.add(lineId);
        edgeEndpoints.add((start: a, end: b));

        double? heightOverrideCm;
        if (useWallHeights) {
          final wallHeightM = perWall[i];
          // Lower bound at 50 cm lets through knee walls / pony walls /
          // balcony rails; below that the value is probably a baseboard
          // misread or noise. Upper bound rejects RoomPlan glitches.
          if (wallHeightM >= 0.5 && wallHeightM <= 6.0) {
            final delta = (wallHeightM - referenceCeilingMeters).abs();
            if (delta > perWallToleranceMeters) {
              heightOverrideCm = wallHeightM * _metersToCm;
            }
          }
        }

        lines[lineId] = FloorLine(
          id: lineId,
          prototype: 'wall',
          vertexIds: [a, b],
          thickness: _defaultWallThicknessCm,
          heightCm: heightOverrideCm,
        );
        vertices[a] = vertices[a]!.copyWith(
          lineIds: {...vertices[a]!.lineIds, lineId},
        );
        vertices[b] = vertices[b]!.copyWith(
          lineIds: {...vertices[b]!.lineIds, lineId},
        );
      }
      wallIdsByRoom[room.id] = wallIds;
      edgeEndpointsByRoom[room.id] = edgeEndpoints;

      final areaId = broker.area();
      areas[areaId] = Area(
        id: areaId,
        vertexIds: List<String>.from(roomVertexIds),
        fillColor: '#E8F0FE40',
        properties: {
          if (room.label != null) 'label': room.label,
          'source': 'scan',
        },
      );
      for (final vid in roomVertexIds) {
        vertices[vid] = vertices[vid]!.copyWith(
          areaIds: {...vertices[vid]!.areaIds, areaId},
        );
      }
    }

    for (final op in result.openings) {
      final walls = wallIdsByRoom[op.roomId];
      if (walls == null ||
          op.wallEdgeIndex < 0 ||
          op.wallEdgeIndex >= walls.length) {
        continue;
      }
      final lineId = walls[op.wallEdgeIndex];
      final wall = lines[lineId]!;
      final startV = vertices[wall.vertexIds[0]]!;
      final endV = vertices[wall.vertexIds[1]]!;
      final wallLengthCm = math.sqrt(
        math.pow(endV.x - startV.x, 2) + math.pow(endV.y - startV.y, 2),
      );
      if (wallLengthCm < 1e-3) continue;

      final offsetCm = op.offsetAlongWall * _metersToCm;
      final normalised = (offsetCm / wallLengthCm).clamp(0.0, 1.0);

      final holeId = broker.hole();
      holes[holeId] = Hole(
        id: holeId,
        prototype: _holePrototype(op.kind),
        lineId: lineId,
        offset: normalised.toDouble(),
        width: op.widthMeters * _metersToCm,
        height: op.heightMeters * _metersToCm,
        altitude: op.sillHeightMeters * _metersToCm,
        properties: const {'source': 'scan'},
      );
      lines[lineId] = wall.copyWith(
        holeIds: [...wall.holeIds, holeId],
      );
    }

    return _ScanPatch(
      vertices: vertices,
      lines: lines,
      holes: holes,
      areas: areas,
      minX: minX,
      minY: minY,
      maxX: maxX,
      maxY: maxY,
    );
  }

  // ── helpers ────────────────────────────────────────────────────────────

  static Map<String, Vertex> _shiftVertices(
    Map<String, Vertex> source,
    double shiftX,
    double shiftY,
  ) {
    final out = <String, Vertex>{};
    source.forEach((id, v) {
      out[id] = v.copyWith(x: v.x + shiftX, y: v.y + shiftY);
    });
    return out;
  }

  static _Bounds? _vertexBounds(Map<String, Vertex> vertices) {
    if (vertices.isEmpty) return null;
    double minX = double.infinity, minY = double.infinity;
    double maxX = double.negativeInfinity, maxY = double.negativeInfinity;
    for (final v in vertices.values) {
      if (v.x < minX) minX = v.x;
      if (v.y < minY) minY = v.y;
      if (v.x > maxX) maxX = v.x;
      if (v.y > maxY) maxY = v.y;
    }
    return _Bounds(minX: minX, minY: minY, maxX: maxX, maxY: maxY);
  }

  static double _resolveCeilingHeight(FloorPlanScanResult result) {
    final scanCeilingCm = (result.ceilingHeightMeters ?? 0) * _metersToCm;
    return scanCeilingCm >= 200 && scanCeilingCm <= 600
        ? scanCeilingCm
        : 240.0;
  }

  /// The "scene ceiling" used to decide which walls deserve a per-wall
  /// height override. Prefers the engine-reported ceiling, falls back to
  /// the median per-wall height across all scanned rooms, and returns
  /// null when neither is available (i.e. tap engines without
  /// per-wall data — leave every wall on the scene default).
  static double? _resolveReferenceCeilingMeters(FloorPlanScanResult result) {
    final reported = result.ceilingHeightMeters;
    if (reported != null && reported >= 2.0 && reported <= 6.0) {
      return reported;
    }
    final allWallHeights = <double>[];
    for (final room in result.rooms) {
      final h = room.perWallHeightsMeters;
      if (h == null) continue;
      for (final v in h) {
        if (v >= 1.5 && v <= 6.0) allWallHeights.add(v);
      }
    }
    if (allWallHeights.isEmpty) return null;
    allWallHeights.sort();
    return allWallHeights[allWallHeights.length ~/ 2];
  }

  static ({double x, double y}) _applyPose(Vec2 p, Pose pose) {
    final c = math.cos(pose.yaw);
    final s = math.sin(pose.yaw);
    return (
      x: pose.x + p.x * c - p.y * s,
      y: pose.y + p.x * s + p.y * c,
    );
  }

  static String _holePrototype(OpeningKind kind) {
    switch (kind) {
      case OpeningKind.door:
        return 'door';
      case OpeningKind.window:
        return 'window';
      case OpeningKind.opening:
        return 'door';
    }
  }

  static String _sceneName(String? override, FloorPlanScanResult result) {
    if (override != null && override.isNotEmpty) return override;
    final stamp = result.capturedAt.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    final dt = '${stamp.year}-${two(stamp.month)}-${two(stamp.day)} '
        '${two(stamp.hour)}:${two(stamp.minute)}';
    final label = switch (result.engine) {
      ScanSourceEngine.roomPlan => 'LiDAR room scan',
      ScanSourceEngine.arKitPlaneTap => 'iOS scan',
      ScanSourceEngine.arCoreDepth => 'Android scan (depth)',
      ScanSourceEngine.arCorePlaneTap => 'Android scan',
    };
    return '$label · $dt';
  }
}

class _ScanPatch {
  final Map<String, Vertex> vertices;
  final Map<String, FloorLine> lines;
  final Map<String, Hole> holes;
  final Map<String, Area> areas;
  final double minX;
  final double minY;
  final double maxX;
  final double maxY;

  const _ScanPatch({
    required this.vertices,
    required this.lines,
    required this.holes,
    required this.areas,
    required this.minX,
    required this.minY,
    required this.maxX,
    required this.maxY,
  });

  bool get hasGeometry => minX.isFinite && minY.isFinite;
}

class _Bounds {
  final double minX;
  final double minY;
  final double maxX;
  final double maxY;
  const _Bounds({
    required this.minX,
    required this.minY,
    required this.maxX,
    required this.maxY,
  });
}
