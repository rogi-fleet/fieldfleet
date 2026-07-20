import 'package:cloud_firestore/cloud_firestore.dart';

/// A note associated with a property or area.
class PropertyNote {
  final String id;
  final String workspaceId;
  final String projectId;
  final String propertyId;
  final String? areaId;
  final String content;
  final String? tag; // e.g., "observation", "instruction", "update"
  final String authorId;
  final String authorName;
  final DateTime createdAt;
  final DateTime? updatedAt;

  PropertyNote({
    required this.id,
    required this.workspaceId,
    required this.projectId,
    required this.propertyId,
    this.areaId,
    required this.content,
    this.tag,
    required this.authorId,
    required this.authorName,
    required this.createdAt,
    this.updatedAt,
  });

  factory PropertyNote.fromJson(Map<String, dynamic> json, String id) {
    return PropertyNote(
      id: id,
      workspaceId: json['workspaceId'] as String,
      projectId: json['projectId'] as String,
      propertyId: json['propertyId'] as String,
      areaId: json['areaId'] as String?,
      content: json['content'] as String,
      tag: json['tag'] as String?,
      authorId: json['authorId'] as String,
      authorName: json['authorName'] as String,
      createdAt: (json['createdAt'] as Timestamp).toDate(),
      updatedAt: (json['updatedAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'workspaceId': workspaceId,
      'projectId': projectId,
      'propertyId': propertyId,
      'areaId': areaId,
      'content': content,
      'tag': tag,
      'authorId': authorId,
      'authorName': authorName,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': updatedAt != null ? Timestamp.fromDate(updatedAt!) : null,
    };
  }

  PropertyNote copyWith({
    String? id,
    String? workspaceId,
    String? projectId,
    String? propertyId,
    String? areaId,
    String? content,
    String? tag,
    String? authorId,
    String? authorName,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return PropertyNote(
      id: id ?? this.id,
      workspaceId: workspaceId ?? this.workspaceId,
      projectId: projectId ?? this.projectId,
      propertyId: propertyId ?? this.propertyId,
      areaId: areaId ?? this.areaId,
      content: content ?? this.content,
      tag: tag ?? this.tag,
      authorId: authorId ?? this.authorId,
      authorName: authorName ?? this.authorName,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  /// Check if this note is for a specific area
  bool get isAreaNote => areaId != null && areaId!.isNotEmpty;

  bool get isEdited =>
      updatedAt != null && !updatedAt!.isAtSameMomentAs(createdAt);

  /// Available tags for notes
  static const List<String> availableTags = [
    'observation',
    'instruction',
    'update',
    'issue',
    'resolution',
  ];
}
