import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uuid/uuid.dart';

/// Represents a single checklist item within a task
class ChecklistItem {
  final String id;
  final String title;
  final bool isComplete;
  final DateTime createdAt;

  ChecklistItem({
    required this.id,
    required this.title,
    this.isComplete = false,
    required this.createdAt,
  });

  /// Create a new checklist item with auto-generated ID
  factory ChecklistItem.create({
    required String title,
  }) {
    return ChecklistItem(
      id: const Uuid().v4(),
      title: title,
      isComplete: false,
      createdAt: DateTime.now(),
    );
  }

  factory ChecklistItem.fromJson(Map<String, dynamic> json) {
    return ChecklistItem(
      id: json['id'] as String,
      title: json['title'] as String,
      isComplete: json['isComplete'] as bool? ?? false,
      createdAt: json['createdAt'] is Timestamp
          ? (json['createdAt'] as Timestamp).toDate()
          : DateTime.parse(json['createdAt'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'isComplete': isComplete,
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }

  ChecklistItem copyWith({
    String? id,
    String? title,
    bool? isComplete,
    DateTime? createdAt,
  }) {
    return ChecklistItem(
      id: id ?? this.id,
      title: title ?? this.title,
      isComplete: isComplete ?? this.isComplete,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ChecklistItem &&
        other.id == id &&
        other.title == title &&
        other.isComplete == isComplete;
  }

  @override
  int get hashCode => id.hashCode ^ title.hashCode ^ isComplete.hashCode;
}
