import 'dart:math' as math;
import 'dart:ui' show Offset;

/// Find the inner faces (room boundaries) of a 2D planar graph of walls.
///
/// Algorithm — face tracing / "next edge clockwise":
///   1. For every vertex, sort its neighbors by polar angle.
///   2. For every directed edge `u → v`, repeatedly turn at `v` to the
///      *next clockwise* outgoing edge (i.e. predecessor of `v → u` in the
///      angular order) until we return to the starting edge.
///   3. The closed loop traced this way is one face of the planar
///      embedding. The outermost face (largest absolute signed area) is
///      the unbounded background — discard it; everything else is a room.
///
/// Inputs are id-keyed for direct interop with the [Layer] model. Returns
/// inner cycles as ordered lists of vertex IDs (closed loops; first and
/// last vertex are the same convention as react-planner).
///
/// Edges are undirected: `edges` is a list of `(idA, idB)` pairs.
List<List<String>> findInnerCycles({
  required Map<String, Offset> vertices,
  required List<({String a, String b})> edges,
}) {
  if (edges.isEmpty) return const [];

  // Build adjacency: vertex → list of neighbors sorted by polar angle.
  final adjacency = <String, List<_Neighbor>>{};
  for (final e in edges) {
    final pa = vertices[e.a];
    final pb = vertices[e.b];
    if (pa == null || pb == null) continue;
    if (e.a == e.b) continue;
    adjacency.putIfAbsent(e.a, () => []).add(
          _Neighbor(id: e.b, angle: math.atan2(pb.dy - pa.dy, pb.dx - pa.dx)),
        );
    adjacency.putIfAbsent(e.b, () => []).add(
          _Neighbor(id: e.a, angle: math.atan2(pa.dy - pb.dy, pa.dx - pb.dx)),
        );
  }
  for (final list in adjacency.values) {
    list.sort((x, y) => x.angle.compareTo(y.angle));
  }

  final visited = <String>{}; // 'u|v' marks directed edge u→v as walked
  final faces = <List<String>>[];

  String key(String u, String v) => '$u|$v';

  String? nextEdge(String at, String from) {
    final nbrs = adjacency[at];
    if (nbrs == null || nbrs.isEmpty) return null;
    // Find index of the incoming edge `at → from` in the angular order.
    final idx = nbrs.indexWhere((n) => n.id == from);
    if (idx < 0) return null;
    // The "next clockwise" outgoing edge in screen coords (y-down) is the
    // *previous* one in counter-clockwise sorted order — which is one
    // step backward in our `atan2`-sorted list.
    final nextIdx = (idx - 1 + nbrs.length) % nbrs.length;
    return nbrs[nextIdx].id;
  }

  // Seed face traces from every directed edge.
  for (final e in edges) {
    final pa = vertices[e.a];
    final pb = vertices[e.b];
    if (pa == null || pb == null) continue;
    for (final pair in [(e.a, e.b), (e.b, e.a)]) {
      var u = pair.$1;
      var v = pair.$2;
      if (visited.contains(key(u, v))) continue;

      final cycle = <String>[u];
      var safety = 0;
      while (safety++ < 4096) {
        visited.add(key(u, v));
        cycle.add(v);
        final next = nextEdge(v, u);
        if (next == null) {
          // Dead end — open chain, not a face.
          break;
        }
        if (v == pair.$1 && next == pair.$2) {
          // Closed back to the seed edge: this is a face.
          faces.add(cycle);
          break;
        }
        u = v;
        v = next;
      }
    }
  }

  if (faces.isEmpty) return const [];

  // Drop the outer face — the one with the largest absolute area.
  double absArea(List<String> cycle) {
    var sum = 0.0;
    for (var i = 0; i < cycle.length - 1; i++) {
      final p = vertices[cycle[i]]!;
      final q = vertices[cycle[i + 1]]!;
      sum += p.dx * q.dy - q.dx * p.dy;
    }
    return (sum * 0.5).abs();
  }

  // Group faces by connected component. Two faces are in the same
  // component if they share at least one vertex. With disjoint
  // sub-graphs (e.g. two separate buildings on one canvas) each
  // component has its own outer face — dropping a single largest face
  // globally would let one component's outer face survive as a
  // phantom "room". Drop the largest face PER COMPONENT instead.
  final components = _groupFacesByComponent(faces);
  final innerFaces = <List<String>>[];
  for (final comp in components) {
    if (comp.length <= 1) continue; // isolated, no inner cycle to keep
    final ordered = [...comp]
      ..sort((a, b) => absArea(b).compareTo(absArea(a)));
    innerFaces.addAll(ordered.sublist(1));
  }
  return innerFaces;
}

/// Partition [faces] by connected component. Each face is a list of
/// vertex IDs; two faces belong to the same component if they share
/// at least one vertex. Uses a union-find keyed by vertex ID.
List<List<List<String>>> _groupFacesByComponent(List<List<String>> faces) {
  final parent = <String, String>{};
  String find(String x) {
    while (parent[x] != x) {
      parent[x] = parent[parent[x]!]!;
      x = parent[x]!;
    }
    return x;
  }

  void union(String a, String b) {
    final ra = find(a);
    final rb = find(b);
    if (ra != rb) parent[ra] = rb;
  }

  // Initialize parent + union all vertex pairs that appear in the
  // same face.
  for (final face in faces) {
    for (final v in face) {
      parent.putIfAbsent(v, () => v);
    }
    for (var i = 1; i < face.length; i++) {
      union(face[i - 1], face[i]);
    }
  }

  // Bucket faces by their root vertex's component.
  final buckets = <String, List<List<String>>>{};
  for (final face in faces) {
    if (face.isEmpty) continue;
    final root = find(face.first);
    buckets.putIfAbsent(root, () => []).add(face);
  }
  return buckets.values.toList();
}

class _Neighbor {
  final String id;
  final double angle;
  const _Neighbor({required this.id, required this.angle});
}
