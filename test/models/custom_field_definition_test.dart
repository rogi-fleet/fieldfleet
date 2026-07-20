import 'package:flutter_test/flutter_test.dart';
import 'package:taskfleet_ops/models/custom_field_definition.dart';
import 'package:taskfleet_ops/models/custom_field_type.dart';

void main() {
  group('CustomFieldType', () {
    test('wireName matches enum name (CHECK constraint contract)', () {
      // The migration's CHECK constraint enumerates these literally —
      // do not rename without a follow-up migration.
      const expected = {
        'text', 'longText', 'number', 'date',
        'picklist', 'multiSelect', 'checkbox', 'file', 'photo',
      };
      final actual = CustomFieldType.values.map((e) => e.wireName).toSet();
      expect(actual, expected);
    });

    test('hasOptions only true for picklist + multiSelect', () {
      expect(CustomFieldType.picklist.hasOptions, isTrue);
      expect(CustomFieldType.multiSelect.hasOptions, isTrue);
      expect(CustomFieldType.text.hasOptions, isFalse);
      expect(CustomFieldType.number.hasOptions, isFalse);
    });

    test('fromWire is total over known names + falls back on unknown', () {
      expect(CustomFieldType.fromWire('number'), CustomFieldType.number);
      expect(CustomFieldType.fromWire('multiSelect'),
          CustomFieldType.multiSelect);
      expect(CustomFieldType.fromWire('mystery'), CustomFieldType.text);
    });
  });

  group('CustomFieldDefinition.fromRow', () {
    final isoNow = DateTime.utc(2026, 4, 22, 14).toIso8601String();

    test('snake_case row from Postgres', () {
      final def = CustomFieldDefinition.fromRow({
        'id': 'd1',
        'workspace_id': 'w1',
        'entity_type': 'project',
        'key': 'fld_a3b9k2',
        'label': 'Permit Number',
        'field_group': 'Permits',
        'type': 'text',
        'options': null,
        'default_value': null,
        'is_required': false,
        'show_in_form': true,
        'groupable': false,
        'sort_order': 3,
        'archived_at': null,
        'created_at': isoNow,
        'updated_at': isoNow,
        'created_by': 'u1',
      });
      expect(def.id, 'd1');
      expect(def.key, 'fld_a3b9k2');
      expect(def.fieldGroup, 'Permits');
      expect(def.type, CustomFieldType.text);
      expect(def.isArchived, isFalse);
      expect(def.optionItems, isEmpty);
    });

    test('picklist with options exposes optionItems', () {
      final def = CustomFieldDefinition.fromRow({
        'id': 'd2',
        'workspace_id': 'w1',
        'entity_type': 'project',
        'key': 'fld_region',
        'label': 'Region',
        'type': 'picklist',
        'options': {
          'items': ['North', 'South', 'East', 'West'],
        },
        'is_required': true,
        'show_in_form': true,
        'groupable': true,
        'sort_order': 0,
        'created_at': isoNow,
        'updated_at': isoNow,
      });
      expect(def.type, CustomFieldType.picklist);
      expect(def.optionItems, ['North', 'South', 'East', 'West']);
      expect(def.isRequired, isTrue);
      expect(def.groupable, isTrue);
    });

    test('archived row reports isArchived', () {
      final archivedAt = DateTime.utc(2026, 4, 21).toIso8601String();
      final def = CustomFieldDefinition.fromRow({
        'id': 'd3',
        'workspace_id': 'w1',
        'entity_type': 'project',
        'key': 'fld_old',
        'label': 'Legacy',
        'type': 'text',
        'archived_at': archivedAt,
        'created_at': isoNow,
        'updated_at': isoNow,
      });
      expect(def.isArchived, isTrue);
    });
  });

  group('CustomFieldDefinition.toFormFieldDefinition', () {
    final base = CustomFieldDefinition(
      id: 'd1',
      workspaceId: 'w1',
      entityType: 'project',
      key: 'fld_x',
      label: 'X',
      type: CustomFieldType.picklist,
      options: const {'items': ['A', 'B']},
      isRequired: true,
      createdAt: DateTime.utc(2026, 4, 22),
      updatedAt: DateTime.utc(2026, 4, 22),
    );

    test('picklist passes options through', () {
      final ff = base.toFormFieldDefinition(order: 2);
      expect(ff.id, 'fld_x');
      expect(ff.options, ['A', 'B']);
      expect(ff.isRequired, isTrue);
      expect(ff.order, 2);
    });

    test('non-picklist drops options', () {
      final ff = base.copyWith(type: CustomFieldType.text).toFormFieldDefinition();
      expect(ff.options, isNull);
    });
  });

  group('CustomFieldDefinition.toInsertRow / toUpdateRow', () {
    final def = CustomFieldDefinition(
      id: 'd1',
      workspaceId: 'w1',
      entityType: 'project',
      key: 'fld_q',
      label: 'Quantity',
      type: CustomFieldType.number,
      isRequired: true,
      groupable: true,
      sortOrder: 5,
      createdBy: 'u1',
      createdAt: DateTime.utc(2026, 4, 22),
      updatedAt: DateTime.utc(2026, 4, 22),
    );

    test('toInsertRow emits snake_case keys + wire type', () {
      final row = def.toInsertRow();
      expect(row['workspace_id'], 'w1');
      expect(row['entity_type'], 'project');
      expect(row['type'], 'number');
      expect(row['is_required'], isTrue);
      expect(row['groupable'], isTrue);
      expect(row['sort_order'], 5);
      expect(row['created_by'], 'u1');
      // id / timestamps are server-assigned — must NOT be in the insert row
      expect(row.containsKey('id'), isFalse);
      expect(row.containsKey('created_at'), isFalse);
    });

    test('toUpdateRow excludes immutable fields (key, type)', () {
      final row = def.toUpdateRow();
      expect(row.containsKey('key'), isFalse,
          reason: 'key is immutable surrogate');
      expect(row.containsKey('type'), isFalse,
          reason: 'in-place type change is forbidden — admin must archive + recreate');
      expect(row.containsKey('workspace_id'), isFalse);
      expect(row['label'], 'Quantity');
    });
  });
}
