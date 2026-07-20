import 'dart:math' as math;
import 'package:flutter/services.dart'; // For Haptics

export 'models/room_point.dart';
export 'models/attachment.dart';
export 'models/wall_opening.dart';
export 'models/room.dart';
export 'models/plan.dart';

import 'models/room_point.dart';
import 'models/wall_opening.dart';

// --------------------------------------------------------------------------- 
// 1. Data Models (Moved to lib/models/)
// --------------------------------------------------------------------------- 
// Exported above.

// OpeningType is exported from models/wall_opening.dart


enum AppUnit { meters, feet }

class UnitConverter {
  static String formatLength(double meters, AppUnit unit) {
    if (unit == AppUnit.meters) {
      return "${meters.toStringAsFixed(2)} m";
    } else {
      double totalInches = meters * 39.3701;
      int feet = (totalInches / 12).floor();
      int inches = (totalInches % 12).round();
      return "$feet' $inches\"";
    }
  }

  static String formatArea(double sqMeters, AppUnit unit) {
    if (unit == AppUnit.meters) {
      return "${sqMeters.toStringAsFixed(2)} m²";
    } else {
      double sqFeet = sqMeters * 10.7639;
      return "${sqFeet.toStringAsFixed(2)} sq ft";
    }
  }
}

// --------------------------------------------------------------------------- 
// 2. Geometry Engine
// --------------------------------------------------------------------------- 

class GeometryEngine {
  /// Shoelace Formula for Area
  static double calculateArea(List<RoomPoint> points) {
    if (points.length < 3) return 0.0;
    double area = 0.0;
    for (int i = 0; i < points.length; i++) {
      int j = (i + 1) % points.length;
      area += points[i].x * points[j].z;
      area -= points[j].x * points[i].z;
    }
    return (area / 2.0).abs();
  }

  /// Calculates total wall perimeter
  static double calculatePerimeter(List<RoomPoint> points) {
    if (points.length < 2) return 0.0;
    double p = 0.0;
    for (int i = 0; i < points.length; i++) {
      p += points[i].distanceTo(points[(i + 1) % points.length]);
    }
    return p;
  }

  /// Smart Snapping with Haptic Feedback
  static RoomPoint applySnapping(RoomPoint current, RoomPoint? previous) {
    if (previous == null) return current;
    const double snapTolerance = 0.15; // 15cm

    double x = current.x;
    double z = current.z;
    bool snapped = false;

    if ((x - previous.x).abs() < snapTolerance) {
      x = previous.x;
      snapped = true;
    }
    if ((z - previous.z).abs() < snapTolerance) {
      z = previous.z;
      snapped = true;
    }

    if (snapped) HapticFeedback.lightImpact();
    return RoomPoint(x, z);
  }

  /// Check if user is closing the loop
  static bool isClosingLoop(RoomPoint current, RoomPoint startPoint) {
    return current.distanceTo(startPoint) < 0.25;
  }

  /// Snap an opening (door/window) to the nearest wall
  static WallOpening? snapOpeningToWall(RoomPoint touch, List<RoomPoint> walls, OpeningType type) {
    if (walls.length < 2) return null;

    double minDistance = double.infinity;
    RoomPoint? bestPos;
    double bestRotation = 0.0;
    const double snapThreshold = 1.0; // Snap if within 1m

    for (int i = 0; i < walls.length; i++) {
      RoomPoint p1 = walls[i];
      RoomPoint p2 = walls[(i + 1) % walls.length];

      _ProjectionResult proj = _projectPointToSegment(touch, p1, p2);

      if (proj.distance < minDistance && proj.distance < snapThreshold) {
        minDistance = proj.distance;
        bestPos = proj.point;
        bestRotation = math.atan2(p2.z - p1.z, p2.x - p1.x);
      }
    }

    if (bestPos != null) {
      return WallOpening(position: bestPos, rotation: bestRotation, type: type);
    }
    return null;
  }

  static RoomPoint projectPointOnSegment(RoomPoint p, RoomPoint a, RoomPoint b) {
    return _projectPointToSegment(p, a, b).point;
  }

  static _ProjectionResult _projectPointToSegment(RoomPoint p, RoomPoint a, RoomPoint b) {
    double l2 = math.pow(a.distanceTo(b), 2).toDouble();
    if (l2 == 0) return _ProjectionResult(a, p.distanceTo(a));

    double t = ((p.x - a.x) * (b.x - a.x) + (p.z - a.z) * (b.z - a.z)) / l2;
    t = math.max(0, math.min(1, t));

    RoomPoint projection = RoomPoint(a.x + t * (b.x - a.x), a.z + t * (b.z - a.z));
    return _ProjectionResult(projection, p.distanceTo(projection));
  }

  /// Rectification: Squaring walls
  static List<RoomPoint> rectifyPolygon(List<RoomPoint> input) {
    if (input.length < 3) return input;

    // 1. Find Longest Wall (Baseline)
    int bestIdx = 0;
    double maxDist = 0;
    for (int i = 0; i < input.length; i++) {
      double dist = input[i].distanceTo(input[(i + 1) % input.length]);
      if (dist > maxDist) {
        maxDist = dist;
        bestIdx = i;
      }
    }

    // 2. Rotate to align baseline with X
    final p1 = input[bestIdx];
    final p2 = input[(bestIdx + 1) % input.length];
    double angle = math.atan2(p2.z - p1.z, p2.x - p1.x);

    List<RoomPoint> rotated = input.map((p) {
      double nx = p.x * math.cos(-angle) - p.z * math.sin(-angle);
      double nz = p.x * math.sin(-angle) + p.z * math.cos(-angle);
      return RoomPoint(nx, nz);
    }).toList();

    // 3. Manhattan Snap
    List<RoomPoint> rectified = [rotated[0]];
    for (int i = 1; i < rotated.length; i++) {
      RoomPoint prev = rectified.last;
      RoomPoint curr = rotated[i];
      double dx = (curr.x - prev.x).abs();
      double dz = (curr.z - prev.z).abs();

      if (dx > dz) {
        rectified.add(RoomPoint(curr.x, prev.z));
      } else {
        rectified.add(RoomPoint(prev.x, curr.z));
      }
    }

    // 4. Rotate back
    return rectified.map((p) {
      double ox = p.x * math.cos(angle) - p.z * math.sin(angle);
      double oz = p.x * math.sin(angle) + p.z * math.cos(angle);
      return RoomPoint(ox, oz);
    }).toList();
  }
}

class _ProjectionResult {
  final RoomPoint point;
  final double distance;
  _ProjectionResult(this.point, this.distance);
}
