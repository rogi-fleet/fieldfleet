enum FormFieldType {
  text,
  email,
  phone,
  textarea,
  number,
  date,
  select,
  multiSelect,
  checkbox,
  file,
  address,
  // Field-form specific types
  photo,
  inspectionItem,
  rating,
  datetime,
  // Layout & structure
  section,
  table,
  time,
}

extension FormFieldTypeExtension on FormFieldType {
  String get displayName {
    switch (this) {
      case FormFieldType.text:
        return 'Text';
      case FormFieldType.email:
        return 'Email';
      case FormFieldType.phone:
        return 'Phone';
      case FormFieldType.textarea:
        return 'Long Text';
      case FormFieldType.number:
        return 'Number';
      case FormFieldType.date:
        return 'Date';
      case FormFieldType.select:
        return 'Dropdown';
      case FormFieldType.multiSelect:
        return 'Multi-Select';
      case FormFieldType.checkbox:
        return 'Checkbox';
      case FormFieldType.file:
        return 'File Upload';
      case FormFieldType.address:
        return 'Address';
      case FormFieldType.photo:
        return 'Photo';
      case FormFieldType.inspectionItem:
        return 'Inspection Item';
      case FormFieldType.rating:
        return 'Rating';
      case FormFieldType.datetime:
        return 'Date & Time';
      case FormFieldType.section:
        return 'Section Header';
      case FormFieldType.table:
        return 'Table';
      case FormFieldType.time:
        return 'Time';
    }
  }

  String get icon {
    switch (this) {
      case FormFieldType.text:
        return 'text_fields';
      case FormFieldType.email:
        return 'email';
      case FormFieldType.phone:
        return 'phone';
      case FormFieldType.textarea:
        return 'notes';
      case FormFieldType.number:
        return 'numbers';
      case FormFieldType.date:
        return 'calendar_today';
      case FormFieldType.select:
        return 'arrow_drop_down_circle';
      case FormFieldType.multiSelect:
        return 'checklist';
      case FormFieldType.checkbox:
        return 'check_box';
      case FormFieldType.file:
        return 'attach_file';
      case FormFieldType.address:
        return 'location_on';
      case FormFieldType.photo:
        return 'photo_camera';
      case FormFieldType.inspectionItem:
        return 'fact_check';
      case FormFieldType.rating:
        return 'star';
      case FormFieldType.datetime:
        return 'schedule';
      case FormFieldType.section:
        return 'title';
      case FormFieldType.table:
        return 'table_chart';
      case FormFieldType.time:
        return 'access_time';
    }
  }
}
