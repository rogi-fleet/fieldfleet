import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskfleet_ops/models/project.dart';

void main() {
  group('Project.customFields round-trip', () {
    final ts = Timestamp.fromDate(DateTime.utc(2026, 4, 22));

    Map<String, dynamic> baseJson() => {
          'workspaceId': 'w1',
          'name': 'Demo Project',
          'address': '123 Main St',
          'status': 'active',
          'createdAt': ts,
          'updatedAt': ts,
        };

    test('defaults to empty map when absent from JSON', () {
      final p = Project.fromJson(baseJson(), 'p1');
      expect(p.customFields, isEmpty);
    });

    test('round-trips a populated map through fromJson/toJson', () {
      final json = baseJson()
        ..['customFields'] = {
          'fld_region': 'North',
          'fld_lot_size': 0.42,
          'fld_permits': ['BP-1', 'BP-2'],
          'fld_inspected': true,
        };
      final p = Project.fromJson(json, 'p1');
      expect(p.customFields['fld_region'], 'North');
      expect(p.customFields['fld_lot_size'], 0.42);
      expect(p.customFields['fld_permits'], ['BP-1', 'BP-2']);
      expect(p.customFields['fld_inspected'], isTrue);

      final out = p.toJson();
      expect(out['customFields'], p.customFields);
    });

    test('copyWith preserves customFields when not overridden', () {
      final p = Project.fromJson(
        baseJson()..['customFields'] = {'fld_x': 'y'},
        'p1',
      );
      final renamed = p.copyWith(name: 'Renamed');
      expect(renamed.customFields, {'fld_x': 'y'});
    });

    test('copyWith replaces customFields when provided', () {
      final p = Project.fromJson(
        baseJson()..['customFields'] = {'fld_x': 'y'},
        'p1',
      );
      final swapped = p.copyWith(customFields: {'fld_q': 1});
      expect(swapped.customFields, {'fld_q': 1});
    });

    test('ProjectUpdateField.customFields exists for partial-update tracking',
        () {
      // The Supabase service treats customFields as a single payload entry —
      // this enum value is the gate for "send a custom_fields key in the
      // UPDATE". Removing it would silently break custom-field clears.
      expect(ProjectUpdateField.values, contains(ProjectUpdateField.customFields));
    });
  });
}
