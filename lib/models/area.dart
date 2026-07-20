import 'package:cloud_firestore/cloud_firestore.dart';
import 'area_status.dart';

/// An area within a property (e.g., living room, bedroom, kitchen).
class Area {
  final String id;
  final String workspaceId;
  final String projectId;
  final String propertyId;
  final String name;
  final bool isAffected;
  final AreaStatus status;
  final String? trend; // "improving", "stable", "worsening"
  final String? notes;
  /// Freeform vector sketch of the room. Each entry is a stroke:
  /// `{ "color": int (ARGB), "width": double, "points": [{"x": double, "y": double}, ...] }`.
  /// Coordinates are normalized to a 0..1 range so they scale with any viewport.
  final List<Map<String, dynamic>> sketchStrokes;
  final DateTime createdAt;
  final DateTime updatedAt;

  Area({
    required this.id,
    required this.workspaceId,
    required this.projectId,
    required this.propertyId,
    required this.name,
    this.isAffected = false,
    this.status = AreaStatus.notAffected,
    this.trend,
    this.notes,
    this.sketchStrokes = const [],
    required this.createdAt,
    required this.updatedAt,
  });

  factory Area.fromJson(Map<String, dynamic> json, String id) {
    return Area(
      id: id,
      workspaceId: json['workspaceId'] as String,
      projectId: json['projectId'] as String,
      propertyId: json['propertyId'] as String,
      name: json['name'] as String,
      isAffected: json['isAffected'] as bool? ?? false,
      status: json['status'] != null
          ? AreaStatus.fromString(json['status'] as String)
          : AreaStatus.notAffected,
      trend: json['trend'] as String?,
      notes: json['notes'] as String?,
      sketchStrokes: (json['sketchStrokes'] as List?)
              ?.map((e) => Map<String, dynamic>.from(e as Map))
              .toList() ??
          const [],
      createdAt: (json['createdAt'] as Timestamp).toDate(),
      updatedAt: (json['updatedAt'] as Timestamp).toDate(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'workspaceId': workspaceId,
      'projectId': projectId,
      'propertyId': propertyId,
      'name': name,
      'isAffected': isAffected,
      'status': status.toDbValue(),
      'trend': trend,
      'notes': notes,
      'sketchStrokes': sketchStrokes,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
    };
  }

  Area copyWith({
    String? id,
    String? workspaceId,
    String? projectId,
    String? propertyId,
    String? name,
    bool? isAffected,
    AreaStatus? status,
    String? trend,
    String? notes,
    List<Map<String, dynamic>>? sketchStrokes,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Area(
      id: id ?? this.id,
      workspaceId: workspaceId ?? this.workspaceId,
      projectId: projectId ?? this.projectId,
      propertyId: propertyId ?? this.propertyId,
      name: name ?? this.name,
      isAffected: isAffected ?? this.isAffected,
      status: status ?? this.status,
      trend: trend ?? this.trend,
      notes: notes ?? this.notes,
      sketchStrokes: sketchStrokes ?? this.sketchStrokes,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  bool get hasSketch => sketchStrokes.isNotEmpty;

  /// Check if this area is considered dry
  bool get isDry => status == AreaStatus.dry || status == AreaStatus.restored;

  /// Get trend icon name
  String? get trendIcon {
    switch (trend) {
      case 'improving':
        return 'trending_down';
      case 'stable':
        return 'trending_flat';
      case 'worsening':
        return 'trending_up';
      default:
        return null;
    }
  }
}
