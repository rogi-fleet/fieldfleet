import 'package:cloud_firestore/cloud_firestore.dart';
import 'contents_status.dart';

/// A contents item within a property (furniture, personal items, etc.).
class PropertyContents {
  final String id;
  final String workspaceId;
  final String projectId;
  final String propertyId;
  final String? areaId;
  final String itemName;
  final String? description;
  final ContentsStatus status;
  final int quantity;
  final String? photoUrl;
  final String? barcode;
  final String? notes;
  final DateTime createdAt;
  final DateTime updatedAt;

  PropertyContents({
    required this.id,
    required this.workspaceId,
    required this.projectId,
    required this.propertyId,
    this.areaId,
    required this.itemName,
    this.description,
    this.status = ContentsStatus.identified,
    this.quantity = 1,
    this.photoUrl,
    this.barcode,
    this.notes,
    required this.createdAt,
    required this.updatedAt,
  });

  factory PropertyContents.fromJson(Map<String, dynamic> json, String id) {
    return PropertyContents(
      id: id,
      workspaceId: json['workspaceId'] as String,
      projectId: json['projectId'] as String,
      propertyId: json['propertyId'] as String,
      areaId: json['areaId'] as String?,
      itemName: json['itemName'] as String,
      description: json['description'] as String?,
      status: json['status'] != null
          ? ContentsStatus.fromString(json['status'] as String)
          : ContentsStatus.identified,
      quantity: json['quantity'] as int? ?? 1,
      photoUrl: json['photoUrl'] as String?,
      barcode: json['barcode'] as String?,
      notes: json['notes'] as String?,
      createdAt: (json['createdAt'] as Timestamp).toDate(),
      updatedAt: (json['updatedAt'] as Timestamp).toDate(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'workspaceId': workspaceId,
      'projectId': projectId,
      'propertyId': propertyId,
      'areaId': areaId,
      'itemName': itemName,
      'description': description,
      'status': status.name,
      'quantity': quantity,
      'photoUrl': photoUrl,
      'barcode': barcode,
      'notes': notes,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
    };
  }

  PropertyContents copyWith({
    String? id,
    String? workspaceId,
    String? projectId,
    String? propertyId,
    String? areaId,
    String? itemName,
    String? description,
    ContentsStatus? status,
    int? quantity,
    String? photoUrl,
    String? barcode,
    String? notes,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return PropertyContents(
      id: id ?? this.id,
      workspaceId: workspaceId ?? this.workspaceId,
      projectId: projectId ?? this.projectId,
      propertyId: propertyId ?? this.propertyId,
      areaId: areaId ?? this.areaId,
      itemName: itemName ?? this.itemName,
      description: description ?? this.description,
      status: status ?? this.status,
      quantity: quantity ?? this.quantity,
      photoUrl: photoUrl ?? this.photoUrl,
      barcode: barcode ?? this.barcode,
      notes: notes ?? this.notes,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  /// Check if this item has been processed (returned or disposed)
  bool get isProcessed =>
      status == ContentsStatus.returned || status == ContentsStatus.disposed;

  /// Check if this item has a photo
  bool get hasPhoto => photoUrl != null && photoUrl!.isNotEmpty;

  /// Check if this item has a barcode
  bool get hasBarcode => barcode != null && barcode!.isNotEmpty;
}
