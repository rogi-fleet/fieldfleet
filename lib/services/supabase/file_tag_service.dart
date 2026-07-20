import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/file_tag.dart';
import '../../utils/app_logger.dart';

/// Supabase CRUD + join management for [FileTag]s.
///
/// Tags live in `file_tags` (workspace-scoped, colored, reusable); their
/// attachments to files live in `file_attachment_tags`.
class SupabaseFileTagService {
  final SupabaseClient _supabase = Supabase.instance.client;

  static const String _defaultColor = '#64748B';

  // ---------------------------------------------------------------------------
  // Tag CRUD
  // ---------------------------------------------------------------------------

  Future<FileTag> createTag({
    required String workspaceId,
    required String name,
    String color = _defaultColor,
    String? description,
    String? createdBy,
    List<String>? visibleToRoles,
  }) async {
    final response = await _supabase
        .from('file_tags')
        .insert({
          'workspace_id': workspaceId,
          'name': name.trim(),
          'color': color,
          if (description != null && description.trim().isNotEmpty)
            'description': description.trim(),
          if (createdBy != null) 'created_by': createdBy,
          if (visibleToRoles != null) 'visible_to_roles': visibleToRoles,
        })
        .select()
        .single();

    AppLogger.info('Created file tag', metadata: {
      'tagId': response['id'],
      'workspaceId': workspaceId,
      'name': name,
    });

    return FileTag.fromSupabase(response);
  }

  /// Return existing tag with matching case-insensitive name, or create one.
  ///
  /// Race-safe: if two callers ensure the same name simultaneously, the DB
  /// unique index rejects the loser and we refetch the canonical row.
  Future<FileTag> ensureTag({
    required String workspaceId,
    required String name,
    String color = _defaultColor,
    String? createdBy,
  }) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('Tag name cannot be empty');
    }

    final existing = await _findByCaseInsensitiveName(workspaceId, trimmed);
    if (existing != null) return existing;

    try {
      return await createTag(
        workspaceId: workspaceId,
        name: trimmed,
        color: color,
        createdBy: createdBy,
      );
    } on PostgrestException catch (e) {
      // 23505 = unique_violation — another writer got in first; refetch.
      if (e.code == '23505') {
        final racer = await _findByCaseInsensitiveName(workspaceId, trimmed);
        if (racer != null) return racer;
      }
      rethrow;
    }
  }

  /// Look up a tag by workspace + case-insensitive name. Escapes LIKE
  /// metacharacters so tag names containing `%` or `_` match literally.
  Future<FileTag?> _findByCaseInsensitiveName(
    String workspaceId,
    String name,
  ) async {
    final row = await _supabase
        .from('file_tags')
        .select()
        .eq('workspace_id', workspaceId)
        .ilike('name', _escapeLikePattern(name))
        .maybeSingle();
    return row == null ? null : FileTag.fromSupabase(row);
  }

  /// Escape `\`, `%`, `_` so a user-supplied string compares as a literal
  /// in `LIKE`/`ILIKE`. Backslash first to avoid double-escaping.
  static String _escapeLikePattern(String value) {
    return value
        .replaceAll(r'\', r'\\')
        .replaceAll('%', r'\%')
        .replaceAll('_', r'\_');
  }

  /// Live stream of workspace tags, ordered by name. By default hides
  /// archived tags so pickers stay clean; pass [includeArchived] true for
  /// the tag manager screen.
  Stream<List<FileTag>> streamWorkspaceTags(
    String workspaceId, {
    bool includeArchived = false,
  }) {
    if (workspaceId.isEmpty) {
      return Stream<List<FileTag>>.value(const []);
    }
    return _supabase
        .from('file_tags')
        .stream(primaryKey: ['id'])
        .eq('workspace_id', workspaceId)
        .order('name')
        .map((rows) {
          final all = rows.map(FileTag.fromSupabase).toList();
          return includeArchived
              ? all
              : all.where((t) => !t.isArchived).toList();
        });
  }

  Future<List<FileTag>> getWorkspaceTags(
    String workspaceId, {
    bool includeArchived = false,
  }) async {
    final rows = await _supabase
        .from('file_tags')
        .select()
        .eq('workspace_id', workspaceId)
        .order('name');
    final all = (rows as List)
        .cast<Map<String, dynamic>>()
        .map(FileTag.fromSupabase)
        .toList();
    return includeArchived
        ? all
        : all.where((t) => !t.isArchived).toList();
  }

  Future<void> updateTag(
    String tagId, {
    String? name,
    String? color,
    String? description,
    List<String>? visibleToRoles,
  }) async {
    final updates = <String, dynamic>{
      if (name != null) 'name': name.trim(),
      if (color != null) 'color': color,
      if (description != null) 'description': description.trim(),
      if (visibleToRoles != null) 'visible_to_roles': visibleToRoles,
    };
    if (updates.isEmpty) return;

    await _supabase.from('file_tags').update(updates).eq('id', tagId);
  }

  Future<void> archiveTag(String tagId) async {
    await _supabase.from('file_tags').update({
      'archived_at': DateTime.now().toIso8601String(),
    }).eq('id', tagId);
  }

  Future<void> restoreTag(String tagId) async {
    await _supabase
        .from('file_tags')
        .update({'archived_at': null})
        .eq('id', tagId);
  }

  /// Hard-delete. Prefer [archiveTag] for routine "remove from picker" UX —
  /// deletion cascades all attached join rows and cannot be undone.
  Future<void> deleteTag(String tagId) async {
    // file_attachment_tags has ON DELETE CASCADE — join rows clean up.
    await _supabase.from('file_tags').delete().eq('id', tagId);
  }

  /// Number of files currently carrying the tag.
  Future<int> getTagUsageCount(String tagId) async {
    final rows = await _supabase
        .from('file_attachment_tags')
        .select('file_attachment_id')
        .eq('file_tag_id', tagId);
    return (rows as List).length;
  }

  // ---------------------------------------------------------------------------
  // File ↔ tag attachments
  // ---------------------------------------------------------------------------

  Future<List<FileTag>> getTagsForFile(String fileAttachmentId) async {
    final rows = await _supabase
        .from('file_attachment_tags')
        .select('file_tag_id, file_tags(*)')
        .eq('file_attachment_id', fileAttachmentId);

    return (rows as List)
        .map((r) => r['file_tags'] as Map<String, dynamic>?)
        .whereType<Map<String, dynamic>>()
        .map(FileTag.fromSupabase)
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));
  }

  Future<void> attachToFile({
    required String fileAttachmentId,
    required String fileTagId,
    String? createdBy,
  }) async {
    await _supabase.from('file_attachment_tags').upsert(
      {
        'file_attachment_id': fileAttachmentId,
        'file_tag_id': fileTagId,
        if (createdBy != null) 'created_by': createdBy,
      },
      onConflict: 'file_attachment_id,file_tag_id',
      ignoreDuplicates: true,
    );
  }

  Future<void> detachFromFile({
    required String fileAttachmentId,
    required String fileTagId,
  }) async {
    await _supabase
        .from('file_attachment_tags')
        .delete()
        .eq('file_attachment_id', fileAttachmentId)
        .eq('file_tag_id', fileTagId);
  }

  /// Diff-apply a desired tag set onto a file. Inserts missing join rows,
  /// deletes the ones that are no longer desired. Idempotent.
  Future<void> setFileTags({
    required String fileAttachmentId,
    required List<String> tagIds,
    String? createdBy,
  }) async {
    final currentRows = await _supabase
        .from('file_attachment_tags')
        .select('file_tag_id')
        .eq('file_attachment_id', fileAttachmentId);

    final current = (currentRows as List)
        .map((r) => r['file_tag_id'] as String)
        .toSet();
    final desired = tagIds.toSet();

    final toAdd = desired.difference(current);
    final toRemove = current.difference(desired);

    if (toAdd.isNotEmpty) {
      await _supabase.from('file_attachment_tags').upsert(
        toAdd
            .map((tagId) => {
                  'file_attachment_id': fileAttachmentId,
                  'file_tag_id': tagId,
                  if (createdBy != null) 'created_by': createdBy,
                })
            .toList(),
        onConflict: 'file_attachment_id,file_tag_id',
        ignoreDuplicates: true,
      );
    }

    if (toRemove.isNotEmpty) {
      await _supabase
          .from('file_attachment_tags')
          .delete()
          .eq('file_attachment_id', fileAttachmentId)
          .inFilter('file_tag_id', toRemove.toList());
    }
  }
}
