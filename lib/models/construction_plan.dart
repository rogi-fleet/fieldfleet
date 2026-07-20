import 'package:cloud_firestore/cloud_firestore.dart';
import 'plan_discipline.dart';

class ConstructionPlan {
  final String id;
  final String workspaceId;
  final String projectId;
  /// Optional structure scope. Null = project-wide drawing (site plan,
  /// full-property elec riser); set = drawing of a specific property.
  final String? propertyId;
  final String name;
  final PlanDiscipline discipline;
  final String? sheetNumber;
  final String? version;
  final bool isCurrentVersion;
  final DateTime? drawingDate;
  /// PDF source. Null for editor-only plans (created via the 2D planner).
  final String? fileUrl;
  final String? fileName;
  final int? fileSize;
  final String uploadedBy;
  final DateTime uploadedAt;
  final String? notes;
  final List<String> linkedTaskIds;
  final DateTime createdAt;
  final DateTime updatedAt;

  ConstructionPlan({
    required this.id,
    required this.workspaceId,
    required this.projectId,
    this.propertyId,
    required this.name,
    required this.discipline,
    this.sheetNumber,
    this.version,
    this.isCurrentVersion = true,
    this.drawingDate,
    this.fileUrl,
    this.fileName,
    this.fileSize,
    required this.uploadedBy,
    required this.uploadedAt,
    this.notes,
    this.linkedTaskIds = const [],
    required this.createdAt,
    required this.updatedAt,
  });

  factory ConstructionPlan.fromJson(Map<String, dynamic> json, String id) {
    return ConstructionPlan(
      id: id,
      workspaceId: json['workspaceId'] as String,
      projectId: json['projectId'] as String,
      propertyId: json['propertyId'] as String?,
      name: json['name'] as String,
      discipline: PlanDiscipline.fromString(json['discipline'] as String),
      sheetNumber: json['sheetNumber'] as String?,
      version: json['version'] as String?,
      isCurrentVersion: json['isCurrentVersion'] as bool? ?? true,
      drawingDate: json['drawingDate'] != null
          ? (json['drawingDate'] as Timestamp).toDate()
          : null,
      fileUrl: json['fileUrl'] as String?,
      fileName: json['fileName'] as String?,
      fileSize: json['fileSize'] as int?,
      uploadedBy: json['uploadedBy'] as String,
      uploadedAt: (json['uploadedAt'] as Timestamp).toDate(),
      notes: json['notes'] as String?,
      linkedTaskIds: (json['linkedTaskIds'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
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
      'discipline': discipline.toString(),
      'sheetNumber': sheetNumber,
      'version': version,
      'isCurrentVersion': isCurrentVersion,
      'drawingDate':
          drawingDate != null ? Timestamp.fromDate(drawingDate!) : null,
      'fileUrl': fileUrl,
      'fileName': fileName,
      'fileSize': fileSize,
      'uploadedBy': uploadedBy,
      'uploadedAt': Timestamp.fromDate(uploadedAt),
      'notes': notes,
      'linkedTaskIds': linkedTaskIds,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
    };
  }

  ConstructionPlan copyWith({
    String? id,
    String? workspaceId,
    String? projectId,
    String? propertyId,
    bool clearPropertyId = false,
    String? name,
    PlanDiscipline? discipline,
    String? sheetNumber,
    String? version,
    bool? isCurrentVersion,
    DateTime? drawingDate,
    String? fileUrl,
    String? fileName,
    int? fileSize,
    String? uploadedBy,
    DateTime? uploadedAt,
    String? notes,
    List<String>? linkedTaskIds,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return ConstructionPlan(
      id: id ?? this.id,
      workspaceId: workspaceId ?? this.workspaceId,
      projectId: projectId ?? this.projectId,
      propertyId: clearPropertyId ? null : (propertyId ?? this.propertyId),
      name: name ?? this.name,
      discipline: discipline ?? this.discipline,
      sheetNumber: sheetNumber ?? this.sheetNumber,
      version: version ?? this.version,
      isCurrentVersion: isCurrentVersion ?? this.isCurrentVersion,
      drawingDate: drawingDate ?? this.drawingDate,
      fileUrl: fileUrl ?? this.fileUrl,
      fileName: fileName ?? this.fileName,
      fileSize: fileSize ?? this.fileSize,
      uploadedBy: uploadedBy ?? this.uploadedBy,
      uploadedAt: uploadedAt ?? this.uploadedAt,
      notes: notes ?? this.notes,
      linkedTaskIds: linkedTaskIds ?? this.linkedTaskIds,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  bool validate() {
    if (name.isEmpty) return false;
    if (fileUrl != null && !fileUrl!.startsWith('https://')) return false;
    if (sheetNumber != null && !validateSheetNumber(sheetNumber!)) {
      return false;
    }
    return true;
  }

  /// True when this plan has an underlying PDF file (legacy/uploaded plan).
  /// False for editor-only plans created via the 2D planner.
  bool get hasPdf => (fileUrl ?? '').isNotEmpty;

  static bool validateSheetNumber(String sheetNumber) {
    // Pattern: letter(s) + dash + number(s) + optional decimal
    // Examples: A-1, E-2.1, MEP-3, S-10
    final pattern = RegExp(r'^[A-Z]+-\d+(\.\d+)?$', caseSensitive: false);
    return pattern.hasMatch(sheetNumber);
  }

  // Helper getters
  bool get isArchitectural => discipline == PlanDiscipline.architectural;
  bool get isStructural => discipline == PlanDiscipline.structural;
  bool get isElectrical => discipline == PlanDiscipline.electrical;
  bool get isPlumbing => discipline == PlanDiscipline.plumbing;
  bool get isHvac => discipline == PlanDiscipline.hvac;
  bool get isSiteCivil => discipline == PlanDiscipline.siteCivil;

  String get fileSizeFormatted {
    final bytes = fileSize;
    if (bytes == null) return '—';
    if (bytes < 1024) {
      return '$bytes B';
    } else if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    } else {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
  }
}
