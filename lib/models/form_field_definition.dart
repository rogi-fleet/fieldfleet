import 'form_field_type.dart';

class FormFieldDefinition {
  final String id;
  final FormFieldType type;
  final String label;
  final String? description;
  final bool isRequired;
  final int order;
  final List<String>? options;
  final String? defaultValue;

  /// Column definitions for [FormFieldType.table] fields.
  /// Each column is a map with keys: `key`, `label`, `type` (text/number/time/select),
  /// and optionally `options` (for select columns).
  final List<TableColumnDef>? columns;

  /// Conditional visibility: map of `dependsOnFieldId -> allowedValues`.
  /// The field is shown only when, for every entry, the current value of the
  /// referenced field (compared as a string) is contained in the allowed list.
  /// Null or empty means always visible.
  final Map<String, List<String>>? visibleWhen;

  /// Measurement category. When set, the renderer appends a workspace-unit
  /// suffix to the label (e.g. `'temperature'` yields "(°F)" or "(°C)").
  /// Null means the label is rendered verbatim.
  final String? unit;

  FormFieldDefinition({
    required this.id,
    required this.type,
    required this.label,
    this.description,
    this.isRequired = false,
    required this.order,
    this.options,
    this.defaultValue,
    this.columns,
    this.visibleWhen,
    this.unit,
  });

  factory FormFieldDefinition.fromJson(Map<String, dynamic> json) {
    return FormFieldDefinition(
      id: json['id'] as String,
      type: FormFieldType.values.firstWhere(
        (e) => e.name == json['type'],
        orElse: () => FormFieldType.text,
      ),
      label: json['label'] as String,
      description: json['description'] as String?,
      isRequired: json['isRequired'] as bool? ?? false,
      order: json['order'] as int? ?? 0,
      options: (json['options'] as List?)?.cast<String>(),
      defaultValue: json['defaultValue'] as String?,
      columns: (json['columns'] as List?)
          ?.map((c) =>
              TableColumnDef.fromJson(c as Map<String, dynamic>))
          .toList(),
      visibleWhen: (json['visibleWhen'] as Map?)?.map(
        (k, v) => MapEntry(
          k as String,
          (v as List).map((e) => e.toString()).toList(),
        ),
      ),
      unit: json['unit'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type.name,
      'label': label,
      'description': description,
      'isRequired': isRequired,
      'order': order,
      'options': options,
      'defaultValue': defaultValue,
      if (columns != null)
        'columns': columns!.map((c) => c.toJson()).toList(),
      if (visibleWhen != null) 'visibleWhen': visibleWhen,
      if (unit != null) 'unit': unit,
    };
  }

  FormFieldDefinition copyWith({
    String? id,
    FormFieldType? type,
    String? label,
    String? description,
    bool? isRequired,
    int? order,
    List<String>? options,
    String? defaultValue,
    List<TableColumnDef>? columns,
    Map<String, List<String>>? visibleWhen,
    String? unit,
  }) {
    return FormFieldDefinition(
      id: id ?? this.id,
      type: type ?? this.type,
      label: label ?? this.label,
      description: description ?? this.description,
      isRequired: isRequired ?? this.isRequired,
      order: order ?? this.order,
      options: options ?? this.options,
      defaultValue: defaultValue ?? this.defaultValue,
      columns: columns ?? this.columns,
      visibleWhen: visibleWhen ?? this.visibleWhen,
      unit: unit ?? this.unit,
    );
  }
}

/// Column definition for table-type form fields.
class TableColumnDef {
  final String key;
  final String label;

  /// One of: text, number, time, select, employeeRef, locationRef, timesheetPull
  final String type;
  final List<String>? options;

  /// For `timesheetPull` columns: key of the sibling `employeeRef` column
  /// whose selected user drives the lookup.
  final String? computeFrom;

  /// For `timesheetPull` columns: which piece of the time entry to pull.
  /// One of: startTime, endTime, breakMinutes, totalHours.
  final String? pullField;

  /// When true the cell is not user-editable.
  final bool readOnly;

  const TableColumnDef({
    required this.key,
    required this.label,
    this.type = 'text',
    this.options,
    this.computeFrom,
    this.pullField,
    this.readOnly = false,
  });

  factory TableColumnDef.fromJson(Map<String, dynamic> json) {
    return TableColumnDef(
      key: json['key'] as String,
      label: json['label'] as String,
      type: json['type'] as String? ?? 'text',
      options: (json['options'] as List?)?.cast<String>(),
      computeFrom: json['computeFrom'] as String?,
      pullField: json['pullField'] as String?,
      readOnly: json['readOnly'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
        'key': key,
        'label': label,
        'type': type,
        if (options != null) 'options': options,
        if (computeFrom != null) 'computeFrom': computeFrom,
        if (pullField != null) 'pullField': pullField,
        if (readOnly) 'readOnly': readOnly,
      };
}
