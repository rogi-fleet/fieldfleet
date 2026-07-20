import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/file_event.dart';

/// Read-only access to the file_events audit trail. Writes go through the
/// `record_file_event` RPC from the owning service (storage_service,
/// file_comment_service, file_markup_service) — this one just streams.
class SupabaseFileEventService {
  final SupabaseClient _supabase = Supabase.instance.client;

  /// Newest-first stream of events for a single file. RLS already filters
  /// by the workspace + documents:read gate, so subscribers only see what
  /// they're allowed to see.
  Stream<List<FileEvent>> streamForFile(String fileAttachmentId) {
    return _supabase
        .from('file_events')
        .stream(primaryKey: ['id'])
        .eq('file_attachment_id', fileAttachmentId)
        .order('created_at', ascending: false)
        .map((rows) => rows.map(FileEvent.fromSupabase).toList());
  }
}
