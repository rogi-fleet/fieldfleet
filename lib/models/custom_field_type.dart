import 'form_field_type.dart';

/// Narrower enum for workspace-defined custom fields.
///
/// Deliberately a subset of [FormFieldType] — form-rendering concepts that
/// don't fit a column-shaped value (`section`, `table`, `inspectionItem`,
/// `rating`) are excluded so groupable promotion stays sound. Map into
/// [FormFieldType] only at render time via [toFormFieldType].
enum CustomFieldType {
  text,
  longText,
  number,
  date,
  picklist,
  multiSelect,
  checkbox,
  file,
  photo;

  String get displayName {
    switch (this) {
      case CustomFieldType.text:
        return 'Text';
      case CustomFieldType.longText:
        return 'Long Text';
      case CustomFieldType.number:
        return 'Number';
      case CustomFieldType.date:
        return 'Date';
      case CustomFieldType.picklist:
        return 'Dropdown';
      case CustomFieldType.multiSelect:
        return 'Multi-Select';
      case CustomFieldType.checkbox:
        return 'Checkbox';
      case CustomFieldType.file:
        return 'File';
      case CustomFieldType.photo:
        return 'Photo';
    }
  }

  /// Stable wire name. Matches the CHECK constraint on
  /// `custom_field_definitions.type` — do not rename without a migration.
  String get wireName => name;

  static CustomFieldType fromWire(String value) {
    return CustomFieldType.values.firstWhere(
      (e) => e.name == value,
      orElse: () => CustomFieldType.text,
    );
  }

  /// Whether the field allows admin-defined picklist [options].
  bool get hasOptions =>
      this == CustomFieldType.picklist || this == CustomFieldType.multiSelect;

  /// Render-time mapping into the existing form-field renderer.
  FormFieldType toFormFieldType() {
    switch (this) {
      case CustomFieldType.text:
        return FormFieldType.text;
      case CustomFieldType.longText:
        return FormFieldType.textarea;
      case CustomFieldType.number:
        return FormFieldType.number;
      case CustomFieldType.date:
        return FormFieldType.date;
      case CustomFieldType.picklist:
        return FormFieldType.select;
      case CustomFieldType.multiSelect:
        return FormFieldType.multiSelect;
      case CustomFieldType.checkbox:
        return FormFieldType.checkbox;
      case CustomFieldType.file:
        return FormFieldType.file;
      case CustomFieldType.photo:
        return FormFieldType.photo;
    }
  }
}
