import 'package:flutter_test/flutter_test.dart';
import 'package:taskfleet_ops/models/file_event.dart';

void main() {
  group('FileEventAction wire mapping', () {
    test('every enum variant round-trips through wire', () {
      for (final action in FileEventAction.values) {
        expect(
          FileEventAction.fromWire(action.wire),
          action,
          reason: 'round-trip failed for $action',
        );
      }
    });

    test('unknown wire strings map to unknown (forward-compat)', () {
      expect(FileEventAction.fromWire('not_a_real_action'),
          FileEventAction.unknown);
      expect(FileEventAction.fromWire(''), FileEventAction.unknown);
    });

    test('category buckets group actions the way the UI filter expects', () {
      expect(FileEventAction.uploaded.category,
          FileEventCategory.uploadsAndEdits);
      expect(FileEventAction.taggedAdded.category,
          FileEventCategory.uploadsAndEdits);
      expect(FileEventAction.deleted.category,
          FileEventCategory.uploadsAndEdits);
      expect(FileEventAction.commented.category, FileEventCategory.comments);
      expect(FileEventAction.markedUp.category, FileEventCategory.markup);
      expect(FileEventAction.revertedMarkup.category,
          FileEventCategory.markup);
      expect(FileEventAction.shared.category, FileEventCategory.sharing);
      expect(FileEventAction.downloaded.category, FileEventCategory.sharing);
    });
  });

  group('FileEvent.fromSupabase', () {
    final isoNow = DateTime.utc(2026, 4, 20, 10).toIso8601String();

    test('decodes typical row', () {
      final ev = FileEvent.fromSupabase({
        'id': 'e1',
        'workspace_id': 'w1',
        'file_attachment_id': 'f1',
        'actor_id': 'u1',
        'action': 'tagged_added',
        'payload': {'tag_id': 't9'},
        'created_at': isoNow,
      });
      expect(ev.action, FileEventAction.taggedAdded);
      expect(ev.payload['tag_id'], 't9');
      expect(ev.actorId, 'u1');
    });

    test('nullable file_attachment_id survives (post-delete events)', () {
      final ev = FileEvent.fromSupabase({
        'id': 'e2',
        'workspace_id': 'w1',
        'file_attachment_id': null,
        'action': 'deleted',
        'payload': <String, dynamic>{},
        'created_at': isoNow,
      });
      expect(ev.fileAttachmentId, isNull,
          reason: 'ON DELETE SET NULL preserves the event but nulls the FK');
      expect(ev.action, FileEventAction.deleted);
    });

    test('unknown action surfaces as enum unknown instead of throwing', () {
      final ev = FileEvent.fromSupabase({
        'id': 'e3',
        'workspace_id': 'w1',
        'file_attachment_id': 'f1',
        'action': 'something_server_added_later',
        'payload': <String, dynamic>{},
        'created_at': isoNow,
      });
      expect(ev.action, FileEventAction.unknown);
    });
  });
}
