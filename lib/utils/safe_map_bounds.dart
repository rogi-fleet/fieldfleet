import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

/// Bounds for a set of map points that are always safe to hand to
/// [CameraFit.bounds].
///
/// With a zero-extent bounds (a single point, or several pins at the same
/// coordinates — e.g. multiple jobs sharing one street address)
/// `CameraFit.bounds` resolves the fit zoom to infinity and the camera
/// projection NaNs out, which surfaces as the route-level "Oops! Something
/// went wrong" error boundary. Pad any axis whose extent is ~zero so the
/// camera always has a real area to fit.
LatLngBounds safeMapBounds(List<LatLng> points, {double minSpan = 0.005}) {
  assert(points.isNotEmpty, 'safeMapBounds needs at least one point');
  var minLat = points.first.latitude;
  var maxLat = minLat;
  var minLng = points.first.longitude;
  var maxLng = minLng;
  for (final p in points) {
    if (p.latitude < minLat) minLat = p.latitude;
    if (p.latitude > maxLat) maxLat = p.latitude;
    if (p.longitude < minLng) minLng = p.longitude;
    if (p.longitude > maxLng) maxLng = p.longitude;
  }
  if ((maxLat - minLat) < minSpan) {
    final mid = (maxLat + minLat) / 2;
    minLat = mid - minSpan;
    maxLat = mid + minSpan;
  }
  if ((maxLng - minLng) < minSpan) {
    final mid = (maxLng + minLng) / 2;
    minLng = mid - minSpan;
    maxLng = mid + minSpan;
  }
  return LatLngBounds(LatLng(minLat, minLng), LatLng(maxLat, maxLng));
}
