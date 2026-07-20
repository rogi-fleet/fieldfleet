import 'custom_field_type.dart';
import 'form_field_definition.dart';

/// Workspace-scoped admin-defined field attached to an entity (v1: project).
///
/// Composes — does not extend — [FormFieldDefinition]. The form layer
/// composes a [FormFieldDefinition] on demand via [toFormFieldDefinition]
/// so the existing `FormRenderer` can render custom fields without any
/// fork. v1 ignores `visibleWhen` and `unit` from `FormFieldDefinition`;
/// they're not surfaced in the custom-fields settings UI.
class CustomFieldDefinition {
  /// Server-assigned UUID.
  final String id;

  final String workspaceId;

  /// Entity discriminator. v1: always `'project'`.
  final String entityType;

  /// Stable surrogate (nanoid). Never derived from [label]. Used as the
  /// jsonb key inside `projects.custom_fields`.
  final String key;

  /// Human-facing label. Editable; rename does not touch [key], so existing
  /// values follow the rename automatically.
  final String label;

  /// Admin-defined grouping. Renders as a collapsible subsection in the
  /// project form. Null = "Other".
  final String? fieldGroup;

  final CustomFieldType type;

  /// Picklist / multi-select options. Shape: `{'items': ['A', 'B']}`.
  /// Null for non-picklist types.
  final Map<String, dynamic>? options;

  /// Default value applied to new records. Shape depends on [type].
  final dynamic defaultValue;

  final bool isRequired;
  final bool showInForm;

  /// When true, values get mirrored into `project_custom_field_values` by
  /// trigger so reports / group-by hit an indexed table.
  final bool groupable;

  final int sortOrder;

  /// Soft-delete marker. Defs with `archivedAt != null` are hidden from new
  /// records but still rendered read-only on existing records that have a
  /// value.
  final DateTime? archivedAt;

  final DateTime createdAt;
  final DateTime updatedAt;
  final String? createdBy;

  const CustomFieldDefinition({
    required this.id,
    required this.workspaceId,
    required this.entityType,
    required this.key,
    required this.label,
    this.fieldGroup,
    required this.type,
    this.options,
    this.defaultValue,
    this.isRequired = false,
    this.showInForm = true,
    this.groupable = false,
    this.sortOrder = 0,
    this.archivedAt,
    required this.createdAt,
    required this.updatedAt,
    this.createdBy,
  });

  bool get isArchived => archivedAt != null;

  /// Picklist options as a flat list. Empty if not a picklist type.
  List<String> get optionItems {
    final items = options?['items'];
    if (items is List) {
      return items.map((e) => e.toString()).toList();
    }
    return const [];
  }

  /// Build the form-field representation for `FormRenderer`.
  FormFieldDefinition toFormFieldDefinition({int order = 0}) {
    return FormFieldDefinition(
      id: key,
      type: type.toFormFieldType(),
      label: label,
      isRequired: isRequired,
      order: order,
      options: type.hasOptions ? optionItems : null,
      defaultValue: defaultValue?.toString(),
    );
  }

  /// Read from a Postgres row already shaped by the Supabase service layer
  /// (snake_case keys converted to camelCase upstream, or raw row keys).
  factory CustomFieldDefinition.fromRow(Map<String, dynamic> row) {
    DateTime parseTs(dynamic v) {
      if (v is DateTime) return v;
      return DateTime.parse(v as String);
    }

    return CustomFieldDefinition(
      id: row['id'] as String,
      workspaceId: (row['workspace_id'] ?? row['workspaceId']) as String,
      entityType: (row['entity_type'] ?? row['entityType']) as String,
      key: row['key'] as String,
      label: row['label'] as String,
      fieldGroup: (row['field_group'] ?? row['fieldGroup']) as String?,
      type: CustomFieldType.fromWire(row['type'] as String),
      options: (row['options'] as Map?)?.cast<String, dynamic>(),
      defaultValue: row['default_value'] ?? row['defaultValue'],
      isRequired:
          (row['is_required'] ?? row['isRequired'] ?? false) as bool,
      showInForm:
          (row['show_in_form'] ?? row['showInForm'] ?? true) as bool,
      groupable: (row['groupable'] ?? false) as bool,
      sortOrder: (row['sort_order'] ?? row['sortOrder'] ?? 0) as int,
      archivedAt: row['archived_at'] != null || row['archivedAt'] != null
          ? parseTs(row['archived_at'] ?? row['archivedAt'])
          : null,
      createdAt: parseTs(row['created_at'] ?? row['createdAt']),
      updatedAt: parseTs(row['updated_at'] ?? row['updatedAt']),
      createdBy: (row['created_by'] ?? row['createdBy']) as String?,
    );
  }

  /// Insert payload for `custom_field_definitions`. Caller supplies
  /// [workspaceId] / [createdBy]; server fills [id], timestamps.
  Map<String, dynamic> toInsertRow() {
    return {
      'workspace_id': workspaceId,
      'entity_type': entityType,
      'key': key,
      'label': label,
      'field_group': fieldGroup,
      'type': type.wireName,
      'options': options,
      'default_value': defaultValue,
      'is_required': isRequired,
      'show_in_form': showInForm,
      'groupable': groupable,
      'sort_order': sortOrder,
      if (createdBy != null) 'created_by': createdBy,
    };
  }

  /// Partial-update payload. Includes only fields admins can edit.
  Map<String, dynamic> toUpdateRow() {
    return {
      'label': label,
      'field_group': fieldGroup,
      'options': options,
      'default_value': defaultValue,
      'is_required': isRequired,
      'show_in_form': showInForm,
      'groupable': groupable,
      'sort_order': sortOrder,
      'archived_at': archivedAt?.toIso8601String(),
    };
  }

  CustomFieldDefinition copyWith({
    String? id,
    String? workspaceId,
    String? entityType,
    String? key,
    String? label,
    String? fieldGroup,
    bool clearFieldGroup = false,
    CustomFieldType? type,
    Map<String, dynamic>? options,
    bool clearOptions = false,
    dynamic defaultValue,
    bool clearDefaultValue = false,
    bool? isRequired,
    bool? showInForm,
    bool? groupable,
    int? sortOrder,
    DateTime? archivedAt,
    bool clearArchivedAt = false,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? createdBy,
  }) {
    return CustomFieldDefinition(
      id: id ?? this.id,
      workspaceId: workspaceId ?? this.workspaceId,
      entityType: entityType ?? this.entityType,
      key: key ?? this.key,
      label: label ?? this.label,
      fieldGroup: clearFieldGroup ? null : (fieldGroup ?? this.fieldGroup),
      type: type ?? this.type,
      options: clearOptions ? null : (options ?? this.options),
      defaultValue:
          clearDefaultValue ? null : (defaultValue ?? this.defaultValue),
      isRequired: isRequired ?? this.isRequired,
      showInForm: showInForm ?? this.showInForm,
      groupable: groupable ?? this.groupable,
      sortOrder: sortOrder ?? this.sortOrder,
      archivedAt: clearArchivedAt ? null : (archivedAt ?? this.archivedAt),
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      createdBy: createdBy ?? this.createdBy,
    );
  }
}
