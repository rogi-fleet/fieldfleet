import 'dart:math' as math;
import 'dart:ui' show Offset;

/// Pure 2D geometry helpers for the floorplan editor.
///
/// All functions operate in scene-space (architectural units, e.g. cm), not
/// pixel-space. Ported from react-planner's `src/utils/geometry.js` with
/// Dart-idiomatic naming.

const double kEpsilon = 1e-6;

bool nearZero(double v) => v.abs() < kEpsilon;

bool samePoints(Offset a, Offset b, {double epsilon = kEpsilon}) =>
    (a.dx - b.dx).abs() < epsilon && (a.dy - b.dy).abs() < epsilon;

double pointsDistance(Offset a, Offset b) {
  final dx = a.dx - b.dx;
  final dy = a.dy - b.dy;
  return math.sqrt(dx * dx + dy * dy);
}

double pointsDistanceSquared(Offset a, Offset b) {
  final dx = a.dx - b.dx;
  final dy = a.dy - b.dy;
  return dx * dx + dy * dy;
}

/// Closest point on the **infinite** line through [a]–[b] to [p].
Offset closestPointOnLine(Offset a, Offset b, Offset p) {
  final dx = b.dx - a.dx;
  final dy = b.dy - a.dy;
  final denom = dx * dx + dy * dy;
  if (denom < kEpsilon) return a;
  final t = ((p.dx - a.dx) * dx + (p.dy - a.dy) * dy) / denom;
  return Offset(a.dx + t * dx, a.dy + t * dy);
}

/// Closest point on the **segment** [a]–[b] to [p] (clamped to the segment).
Offset closestPointOnSegment(Offset a, Offset b, Offset p) {
  final dx = b.dx - a.dx;
  final dy = b.dy - a.dy;
  final denom = dx * dx + dy * dy;
  if (denom < kEpsilon) return a;
  final t = (((p.dx - a.dx) * dx + (p.dy - a.dy) * dy) / denom)
      .clamp(0.0, 1.0);
  return Offset(a.dx + t * dx, a.dy + t * dy);
}

/// Position of [p] along the segment [a]–[b], expressed as a normalized
/// `t` in `[0, 1]`. Used to compute hole offsets along walls.
///
/// If [p] does not lie on the segment, returns the projection's `t`.
double pointPositionOnSegment(Offset a, Offset b, Offset p) {
  final dx = b.dx - a.dx;
  final dy = b.dy - a.dy;
  final denom = dx * dx + dy * dy;
  if (denom < kEpsilon) return 0;
  final t = ((p.dx - a.dx) * dx + (p.dy - a.dy) * dy) / denom;
  return t.clamp(0.0, 1.0);
}

/// Intersection point of two infinite lines. Returns `null` if parallel.
Offset? twoLinesIntersection(Offset a1, Offset a2, Offset b1, Offset b2) {
  final dx1 = a2.dx - a1.dx;
  final dy1 = a2.dy - a1.dy;
  final dx2 = b2.dx - b1.dx;
  final dy2 = b2.dy - b1.dy;
  final denom = dx1 * dy2 - dy1 * dx2;
  if (denom.abs() < kEpsilon) return null;
  final t = ((b1.dx - a1.dx) * dy2 - (b1.dy - a1.dy) * dx2) / denom;
  return Offset(a1.dx + t * dx1, a1.dy + t * dy1);
}

/// Angle in radians from positive X axis to vector [a]→[b].
double angleBetweenPoints(Offset a, Offset b) =>
    math.atan2(b.dy - a.dy, b.dx - a.dx);

/// Snap [value] to the nearest multiple of [step]. Used for grid snapping.
double snapToStep(double value, double step) =>
    step <= kEpsilon ? value : (value / step).round() * step;

Offset snapToGrid(Offset p, double step) =>
    Offset(snapToStep(p.dx, step), snapToStep(p.dy, step));

/// Lerp between two points. `t = 0` returns [a]; `t = 1` returns [b].
Offset lerpPoints(Offset a, Offset b, double t) =>
    Offset(a.dx + (b.dx - a.dx) * t, a.dy + (b.dy - a.dy) * t);

/// Round a double to a fixed number of decimal places. Defaults to 4 — small
/// enough to absorb floating-point noise, large enough to preserve mm-scale
/// drawings (1 cm scene unit → 0.0001 cm = 1 µm).
double toFixedFloat(double v, [int decimals = 4]) {
  final factor = math.pow(10, decimals).toDouble();
  return (v * factor).round() / factor;
}

/// Signed shoelace area of a polygon (positive for CCW vertex order).
/// Result is always returned as |area|; callers compute orientation
/// separately if they need it.
double polygonArea(List<Offset> vertices) {
  if (vertices.length < 3) return 0;
  double sum = 0;
  for (var i = 0; i < vertices.length; i++) {
    final a = vertices[i];
    final b = vertices[(i + 1) % vertices.length];
    sum += a.dx * b.dy - b.dx * a.dy;
  }
  return sum.abs() / 2.0;
}

/// Sum of edge lengths around the polygon — perimeter for a closed loop.
double polygonPerimeter(List<Offset> vertices) {
  if (vertices.length < 2) return 0;
  double total = 0;
  for (var i = 0; i < vertices.length; i++) {
    final a = vertices[i];
    final b = vertices[(i + 1) % vertices.length];
    total += pointsDistance(a, b);
  }
  return total;
}
