import 'package:cloud_firestore/cloud_firestore.dart';
import 'property_status.dart';

/// A property within a restoration project.
/// Each project can have multiple properties.
class Property {
  final String id;
  final String workspaceId;
  final String projectId;
  final String name;
  final String identifier; // Unique per project (e.g., "Unit A", "101")
  final String? floor;
  final String? occupant;
  final PropertyStatus status;
  final String? notes;
  final int areaCount;
  final int dryAreaCount;
  final int contentsCount;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? createdBy;


  Property({
    required this.id,
    required this.workspaceId,
    required this.projectId,
    required this.name,
    required this.identifier,
    this.floor,
    this.occupant,
    this.status = PropertyStatus.pending,
    this.notes,
    this.areaCount = 0,
    this.dryAreaCount = 0,
    this.contentsCount = 0,
    required this.createdAt,
    required this.updatedAt,
    this.createdBy,
  });

  factory Property.fromJson(Map<String, dynamic> json, String id) {
    return Property(
      id: id,
      workspaceId: json['workspaceId'] as String,
      projectId: json['projectId'] as String,
      name: json['name'] as String,
      identifier: json['identifier'] as String,
      floor: json['floor'] as String?,
      occupant: json['occupant'] as String?,
      status: json['status'] != null
          ? PropertyStatus.fromString(json['status'] as String)
          : PropertyStatus.pending,
      notes: json['notes'] as String?,
      areaCount: json['areaCount'] as int? ?? 0,
      dryAreaCount: json['dryAreaCount'] as int? ?? 0,
      contentsCount: json['contentsCount'] as int? ?? 0,
      createdAt: (json['createdAt'] as Timestamp).toDate(),
      updatedAt: (json['updatedAt'] as Timestamp).toDate(),
      createdBy: json['createdBy'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'workspaceId': workspaceId,
      'projectId': projectId,
      'name': name,
      'identifier': identifier,
      'floor': floor,
      'occupant': occupant,
      'status': status.toDbValue(),
      'notes': notes,
      'areaCount': areaCount,
      'dryAreaCount': dryAreaCount,
      'contentsCount': contentsCount,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
      'createdBy': createdBy,
    };
  }

  Property copyWith({
    String? id,
    String? workspaceId,
    String? projectId,
    String? name,
    String? identifier,
    String? floor,
    String? occupant,
    PropertyStatus? status,
    String? notes,
    int? areaCount,
    int? dryAreaCount,
    int? contentsCount,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? createdBy,
  }) {
    return Property(
      id: id ?? this.id,
      workspaceId: workspaceId ?? this.workspaceId,
      projectId: projectId ?? this.projectId,
      name: name ?? this.name,
      identifier: identifier ?? this.identifier,
      floor: floor ?? this.floor,
      occupant: occupant ?? this.occupant,
      status: status ?? this.status,
      notes: notes ?? this.notes,
      areaCount: areaCount ?? this.areaCount,
      dryAreaCount: dryAreaCount ?? this.dryAreaCount,
      contentsCount: contentsCount ?? this.contentsCount,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      createdBy: createdBy ?? this.createdBy,
    );
  }

  /// Check if all affected areas are dry
  bool get isDryingComplete => areaCount > 0 && dryAreaCount == areaCount;

  /// Calculate drying progress as a percentage (0-100)
  double get dryingProgress {
    if (areaCount == 0) return 0;
    return (dryAreaCount / areaCount) * 100;
  }

  /// Display label combining identifier and name
  String get displayLabel => '$identifier - $name';
}
