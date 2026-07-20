import 'dart:convert';

import 'form_field_definition.dart';

enum FieldFormCategory {
  inspection,
  completion,
  safety,
  assessment,
  custom;

  String get displayName {
    switch (this) {
      case FieldFormCategory.inspection:
        return 'Inspection';
      case FieldFormCategory.completion:
        return 'Completion';
      case FieldFormCategory.safety:
        return 'Safety';
      case FieldFormCategory.assessment:
        return 'Assessment';
      case FieldFormCategory.custom:
        return 'Custom';
    }
  }

  String get icon {
    switch (this) {
      case FieldFormCategory.inspection:
        return 'search';
      case FieldFormCategory.completion:
        return 'check_circle';
      case FieldFormCategory.safety:
        return 'shield';
      case FieldFormCategory.assessment:
        return 'assignment';
      case FieldFormCategory.custom:
        return 'description';
    }
  }

  static FieldFormCategory fromString(String value) {
    return FieldFormCategory.values.firstWhere(
      (e) => e.name == value,
      orElse: () => FieldFormCategory.custom,
    );
  }
}

class FieldFormTemplate {
  final String id;
  final String workspaceId;
  final String name;
  final String? description;
  final FieldFormCategory category;
  final List<FormFieldDefinition> fields;
  final bool requiresTechSignature;
  final bool requiresSupervisorSignature;
  final bool requiresCustomerSignature;
  final bool isDefault;
  final List<String> defaultTaskCategories;

  /// Stable identity for a built-in ("default") template, independent of its
  /// display name. Null for user-created templates and legacy rows not yet
  /// adopted by reconciliation. See [defaultContentHash].
  final String? defaultKey;

  /// Version of the canonical definition currently materialized in this row.
  /// Null until the row is tracked by reconciliation.
  final int? defaultVersion;

  /// Content fingerprint recorded the last time reconciliation seeded or
  /// overwrote this row. Compared against [defaultContentHash] to tell whether
  /// the workspace has since edited its copy.
  final String? defaultSeedHash;

  final String? createdBy;
  final DateTime createdAt;
  final DateTime updatedAt;

  const FieldFormTemplate({
    required this.id,
    required this.workspaceId,
    required this.name,
    this.description,
    required this.category,
    required this.fields,
    this.requiresTechSignature = false,
    this.requiresSupervisorSignature = false,
    this.requiresCustomerSignature = false,
    this.isDefault = false,
    this.defaultTaskCategories = const [],
    this.defaultKey,
    this.defaultVersion,
    this.defaultSeedHash,
    this.createdBy,
    required this.createdAt,
    required this.updatedAt,
  });

  /// Fingerprint of this template's user-meaningful content. Reconciliation
  /// compares it against [defaultSeedHash] to detect a workspace edit, so it
  /// must cover exactly the fields reconciliation writes — and nothing
  /// row-specific (id, timestamps, tracking columns).
  String get defaultContentHash => fieldFormDefaultContentHash(
        name: name,
        description: description,
        category: category,
        fields: fields,
        requiresTechSignature: requiresTechSignature,
        requiresSupervisorSignature: requiresSupervisorSignature,
        requiresCustomerSignature: requiresCustomerSignature,
        defaultTaskCategories: defaultTaskCategories,
      );

  int get fieldCount => fields.length;
  int get requiredFieldCount => fields.where((f) => f.isRequired).length;
  bool get requiresAnySignature =>
      requiresTechSignature ||
      requiresSupervisorSignature ||
      requiresCustomerSignature;

  factory FieldFormTemplate.fromRow(Map<String, dynamic> row) {
    final fieldsList = (row['fields'] as List?)
            ?.map((item) =>
                FormFieldDefinition.fromJson(item as Map<String, dynamic>))
            .toList() ??
        [];

    return FieldFormTemplate(
      id: row['id'] as String,
      workspaceId: row['workspace_id'] as String,
      name: row['name'] as String,
      description: row['description'] as String?,
      category: FieldFormCategory.fromString(row['category'] as String? ?? 'custom'),
      fields: fieldsList,
      requiresTechSignature: row['requires_tech_signature'] as bool? ?? false,
      requiresSupervisorSignature:
          row['requires_supervisor_signature'] as bool? ?? false,
      requiresCustomerSignature:
          row['requires_customer_signature'] as bool? ?? false,
      isDefault: row['is_default'] as bool? ?? false,
      defaultTaskCategories:
          (row['default_task_categories'] as List?)?.cast<String>() ?? [],
      defaultKey: row['default_key'] as String?,
      defaultVersion: (row['default_version'] as num?)?.toInt(),
      defaultSeedHash: row['default_seed_hash'] as String?,
      createdBy: row['created_by'] as String?,
      createdAt: _parseDateTime(row['created_at']),
      updatedAt: _parseDateTime(row['updated_at']),
    );
  }

  Map<String, dynamic> toInsertRow() {
    return {
      'workspace_id': workspaceId,
      'name': name,
      'description': description,
      'category': category.name,
      'fields': fields.map((f) => f.toJson()).toList(),
      'requires_tech_signature': requiresTechSignature,
      'requires_supervisor_signature': requiresSupervisorSignature,
      'requires_customer_signature': requiresCustomerSignature,
      'is_default': isDefault,
      'default_task_categories': defaultTaskCategories,
      'created_by': createdBy,
    };
  }

  static DateTime _parseDateTime(dynamic value) {
    if (value is DateTime) return value;
    if (value is String) return DateTime.parse(value);
    return DateTime.now();
  }

  FieldFormTemplate copyWith({
    String? id,
    String? workspaceId,
    String? name,
    String? description,
    FieldFormCategory? category,
    List<FormFieldDefinition>? fields,
    bool? requiresTechSignature,
    bool? requiresSupervisorSignature,
    bool? requiresCustomerSignature,
    bool? isDefault,
    List<String>? defaultTaskCategories,
    String? defaultKey,
    int? defaultVersion,
    String? defaultSeedHash,
    String? createdBy,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return FieldFormTemplate(
      id: id ?? this.id,
      workspaceId: workspaceId ?? this.workspaceId,
      name: name ?? this.name,
      description: description ?? this.description,
      category: category ?? this.category,
      fields: fields ?? this.fields,
      requiresTechSignature:
          requiresTechSignature ?? this.requiresTechSignature,
      requiresSupervisorSignature:
          requiresSupervisorSignature ?? this.requiresSupervisorSignature,
      requiresCustomerSignature:
          requiresCustomerSignature ?? this.requiresCustomerSignature,
      isDefault: isDefault ?? this.isDefault,
      defaultTaskCategories:
          defaultTaskCategories ?? this.defaultTaskCategories,
      defaultKey: defaultKey ?? this.defaultKey,
      defaultVersion: defaultVersion ?? this.defaultVersion,
      defaultSeedHash: defaultSeedHash ?? this.defaultSeedHash,
      createdBy: createdBy ?? this.createdBy,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

/// Computes the canonical content fingerprint for a built-in field form
/// template. Both the in-code definitions and stored rows hash through this
/// single function so identical content always yields the same digest,
/// regardless of which side it came from.
///
/// The components are assembled in a fixed order and serialized with
/// [jsonEncode]; `FormFieldDefinition.toJson` is deterministic and idempotent
/// across the JSONB round-trip, so a row that was never edited reproduces the
/// digest it was seeded with.
String fieldFormDefaultContentHash({
  required String name,
  String? description,
  required FieldFormCategory category,
  required List<FormFieldDefinition> fields,
  required bool requiresTechSignature,
  required bool requiresSupervisorSignature,
  required bool requiresCustomerSignature,
  required List<String> defaultTaskCategories,
}) {
  final canonical = jsonEncode({
    'name': name,
    'description': description,
    'category': category.name,
    'fields': fields.map((f) => f.toJson()).toList(),
    'tech': requiresTechSignature,
    'sup': requiresSupervisorSignature,
    'cust': requiresCustomerSignature,
    'cats': defaultTaskCategories,
  });
  return _stableHash64(canonical);
}

/// Deterministic, dependency-free 64-bit string hash (cyrb53). Stable across
/// the Dart VM and the web compiler — all arithmetic stays within 32-bit lanes
/// (web-safe) and only the final concatenation uses [BigInt]. This is for
/// change detection, not cryptographic integrity.
String _stableHash64(String input) {
  int h1 = 0xdeadbeef;
  int h2 = 0x41c6ce57;
  for (var i = 0; i < input.length; i++) {
    final ch = input.codeUnitAt(i);
    h1 = _imul32(h1 ^ ch, 2654435761);
    h2 = _imul32(h2 ^ ch, 1597334677);
  }
  h1 = _imul32(h1 ^ (h1 >>> 16), 2246822507) ^
      _imul32(h2 ^ (h2 >>> 13), 3266489909);
  h2 = _imul32(h2 ^ (h2 >>> 16), 2246822507) ^
      _imul32(h1 ^ (h1 >>> 13), 3266489909);
  final combined =
      (BigInt.from(h2 & 0xffffffff) << 32) | BigInt.from(h1 & 0xffffffff);
  return combined.toRadixString(16).padLeft(16, '0');
}

/// 32-bit integer multiply with wraparound (equivalent to JS `Math.imul`),
/// computed via 16-bit halves so no intermediate exceeds 2^53.
int _imul32(int a, int b) {
  final aLo = a & 0xffff;
  final aHi = (a >>> 16) & 0xffff;
  final bLo = b & 0xffff;
  final bHi = (b >>> 16) & 0xffff;
  final lo = aLo * bLo;
  final mid = ((aHi * bLo + aLo * bHi) & 0xffff) << 16;
  return (lo + mid) & 0xffffffff;
}
