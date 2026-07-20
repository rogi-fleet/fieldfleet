import 'package:flutter_test/flutter_test.dart';
import 'package:taskfleet_ops/models/file_tag.dart';

void main() {
  group('FileTag', () {
    final isoNow = DateTime.utc(2026, 4, 20, 10).toIso8601String();

    test('fromSupabase — minimal row', () {
      final tag = FileTag.fromSupabase({
        'id': 't1',
        'workspace_id': 'w1',
        'name': 'Photo',
        'color': '#FF0000',
        'created_at': isoNow,
        'updated_at': isoNow,
      });
      expect(tag.id, 't1');
      expect(tag.workspaceId, 'w1');
      expect(tag.name, 'Photo');
      expect(tag.color, '#FF0000');
      expect(tag.description, isNull);
      expect(tag.createdBy, isNull);
      expect(tag.visibleToRoles, isEmpty);
      expect(tag.archivedAt, isNull);
      expect(tag.isRestricted, isFalse);
      expect(tag.isArchived, isFalse);
    });

    test('fromSupabase — gated + archived', () {
      final archivedAt = DateTime.utc(2026, 4, 19).toIso8601String();
      final tag = FileTag.fromSupabase({
        'id': 't2',
        'workspace_id': 'w1',
        'name': 'Private',
        'color': '#123456',
        'description': 'PMs only',
        'created_by': 'u1',
        'visible_to_roles': ['project_manager', 'admin'],
        'archived_at': archivedAt,
        'created_at': isoNow,
        'updated_at': isoNow,
      });
      expect(tag.visibleToRoles, ['project_manager', 'admin']);
      expect(tag.isRestricted, isTrue);
      expect(tag.isArchived, isTrue);
      expect(tag.archivedAt, DateTime.parse(archivedAt));
    });

    test('fromSupabase — missing color falls back to default slate', () {
      final tag = FileTag.fromSupabase({
        'id': 't3',
        'workspace_id': 'w1',
        'name': 'x',
        'created_at': isoNow,
        'updated_at': isoNow,
      });
      expect(tag.color, '#64748B');
    });

    test('toSupabaseInsert strips optional fields when unset', () {
      final tag = FileTag(
        id: 'ignored',
        workspaceId: 'w1',
        name: 'Tag',
        color: '#FF0000',
        createdAt: _epoch,
        updatedAt: _epoch,
      );
      final json = tag.toSupabaseInsert();
      expect(json.containsKey('id'), isFalse, reason: 'DB generates id');
      expect(json.containsKey('description'), isFalse);
      expect(json.containsKey('created_by'), isFalse);
      expect(json.containsKey('visible_to_roles'), isFalse,
          reason: 'empty array sent as missing key so DB default applies');
    });

    test('toSupabaseInsert includes gated roles', () {
      final tag = FileTag(
        id: 'ignored',
        workspaceId: 'w1',
        name: 'Gated',
        color: '#FF0000',
        createdBy: 'u1',
        visibleToRoles: const ['project_manager'],
        createdAt: _epoch,
        updatedAt: _epoch,
      );
      final json = tag.toSupabaseInsert();
      expect(json['visible_to_roles'], ['project_manager']);
      expect(json['created_by'], 'u1');
    });

    test('validate accepts #RGB, #RRGGBB, #AARRGGBB; rejects junk', () {
      bool valid(String hex) => FileTag(
            id: 'x',
            workspaceId: 'w',
            name: 'n',
            color: hex,
            createdAt: _epoch,
            updatedAt: _epoch,
          ).validate();

      expect(valid('#abc'), isTrue);
      expect(valid('#AABBCC'), isTrue);
      expect(valid('#FFAABBCC'), isTrue);
      expect(valid(''), isFalse);
      expect(valid('not a color'), isFalse);
      expect(valid('#XYZ'), isFalse);
      expect(valid('FFAABBCC'), isFalse, reason: 'missing #');
    });

    test('copyWith function-wrappers let callers set nullable to null', () {
      final tag = FileTag(
        id: 't',
        workspaceId: 'w',
        name: 'n',
        color: '#FF0000',
        description: 'before',
        archivedAt: _epoch,
        createdAt: _epoch,
        updatedAt: _epoch,
      );
      final cleared = tag.copyWith(
        description: () => null,
        archivedAt: () => null,
      );
      expect(cleared.description, isNull);
      expect(cleared.archivedAt, isNull);
      expect(cleared.isArchived, isFalse);
    });
  });
}

final _epoch = DateTime.utc(2000, 1, 1);
