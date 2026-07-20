import 'dart:ui' show Offset;

import 'geometry.dart';

/// Snap targets considered when the cursor moves. The editor builds a list
/// of these from the current scene each frame, then asks `nearestSnap`
/// for the best hit under the cursor.
///
/// Mirrors react-planner's `src/utils/snap.js` four-class taxonomy plus a
/// priority + distance tiebreak. Higher [priority] wins ties; otherwise
/// the closest hit within `radius` wins.
sealed class Snap {
  final SnapKind kind;
  final int priority;
  final double radius;
  final Map<String, Object?> metadata;

  const Snap({
    required this.kind,
    required this.priority,
    required this.radius,
    this.metadata = const {},
  });

  /// Project the cursor [p] onto this snap. Returns the snap point and the
  /// distance from [p] to it. Returns `null` if the cursor is beyond
  /// [radius].
  ({Offset point, double distance})? hit(Offset p);
}

/// What flavor of snap target this is. The editor uses the kind to draw
/// the right kind of hint marker (dot for vertex, crosshair for grid, etc.)
/// and to gate snaps via the [SnapMask].
enum SnapKind { vertex, line, lineSegment, grid }

/// Snap to a fixed point — usually a vertex.
class PointSnap extends Snap {
  final Offset point;

  const PointSnap({
    required this.point,
    super.priority = 30,
    super.radius = 12,
    super.kind = SnapKind.vertex,
    super.metadata = const {},
  });

  @override
  ({Offset point, double distance})? hit(Offset p) {
    final d = pointsDistance(point, p);
    if (d > radius) return null;
    return (point: point, distance: d);
  }
}

/// Snap to the closest point on an **infinite** line through (a,b).
/// Lower priority than [LineSegmentSnap] so segment snaps win ties.
class LineSnap extends Snap {
  final Offset a;
  final Offset b;

  const LineSnap({
    required this.a,
    required this.b,
    super.priority = 10,
    super.radius = 8,
    super.kind = SnapKind.line,
    super.metadata = const {},
  });

  @override
  ({Offset point, double distance})? hit(Offset p) {
    final proj = closestPointOnLine(a, b, p);
    final d = pointsDistance(proj, p);
    if (d > radius) return null;
    return (point: proj, distance: d);
  }
}

/// Snap to the closest point on the **segment** [a]–[b].
class LineSegmentSnap extends Snap {
  final Offset a;
  final Offset b;

  const LineSegmentSnap({
    required this.a,
    required this.b,
    super.priority = 20,
    super.radius = 8,
    super.kind = SnapKind.lineSegment,
    super.metadata = const {},
  });

  @override
  ({Offset point, double distance})? hit(Offset p) {
    final proj = closestPointOnSegment(a, b, p);
    final d = pointsDistance(proj, p);
    if (d > radius) return null;
    return (point: proj, distance: d);
  }
}

/// Snap to the regular grid (origin (0,0), step [step]).
/// Lowest priority so explicit geometry always wins.
class GridSnap extends Snap {
  final double step;

  const GridSnap({
    required this.step,
    super.priority = 5,
    super.radius = 4,
    super.kind = SnapKind.grid,
    super.metadata = const {},
  });

  @override
  ({Offset point, double distance})? hit(Offset p) {
    if (step <= kEpsilon) return null;
    final snapped = snapToGrid(p, step);
    final d = pointsDistance(snapped, p);
    if (d > radius) return null;
    return (point: snapped, distance: d);
  }
}

/// Toggleable per-kind mask. Holding Alt during a drag should drop into a
/// fresh `SnapMask.disabled()` so no snap fires; otherwise the editor uses
/// `SnapMask.all()` (or a tool-specific subset).
class SnapMask {
  final Set<SnapKind> enabled;

  const SnapMask(this.enabled);

  factory SnapMask.all() => const SnapMask({
        SnapKind.vertex,
        SnapKind.line,
        SnapKind.lineSegment,
        SnapKind.grid,
      });

  factory SnapMask.disabled() => const SnapMask({});

  bool allows(Snap s) => enabled.contains(s.kind);
}

/// Pick the best snap hit from [snaps] for cursor [p].
///
/// Sort key is `(priority desc, distance asc)` — same as react-planner's
/// `nearestSnap`. Returns `null` if no snap fires.
({Snap snap, Offset point})? nearestSnap(
  Iterable<Snap> snaps,
  Offset p, {
  SnapMask? mask,
}) {
  final m = mask ?? SnapMask.all();
  ({Snap snap, Offset point, double distance})? best;
  for (final s in snaps) {
    if (!m.allows(s)) continue;
    final h = s.hit(p);
    if (h == null) continue;
    if (best == null) {
      best = (snap: s, point: h.point, distance: h.distance);
      continue;
    }
    // Higher priority wins; tie-break by distance.
    if (s.priority > best.snap.priority ||
        (s.priority == best.snap.priority && h.distance < best.distance)) {
      best = (snap: s, point: h.point, distance: h.distance);
    }
  }
  if (best == null) return null;
  return (snap: best.snap, point: best.point);
}
