import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/spec_book.dart';
import '../../models/spec_section.dart';
import '../../models/spec_sheet.dart';
import '../../utils/app_logger.dart';

class SupabaseSpecificationService {
  final SupabaseClient _supabase = Supabase.instance.client;

  // ---------------- Books ----------------

  Future<List<SpecBook>> listBooks(String projectId) async {
    try {
      final rows = await _supabase
          .from('spec_books')
          .select()
          .eq('project_id', projectId)
          .order('version', ascending: false);
      return (rows as List).map((r) => SpecBook.fromMap(r)).toList();
    } catch (e) {
      AppLogger.error('listBooks failed', error: e);
      return [];
    }
  }

  Stream<List<SpecBook>> watchBooks(String projectId) {
    return _supabase
        .from('spec_books')
        .stream(primaryKey: ['id'])
        .eq('project_id', projectId)
        .order('version', ascending: false)
        .map((rows) => rows.map((r) => SpecBook.fromMap(r)).toList());
  }

  Future<SpecBook?> getBook(String id) async {
    final row = await _supabase
        .from('spec_books')
        .select()
        .eq('id', id)
        .maybeSingle();
    return row == null ? null : SpecBook.fromMap(row);
  }

  Future<SpecBook> createBook({
    required String workspaceId,
    required String projectId,
    required String title,
    String? description,
  }) async {
    final maxRow = await _supabase
        .from('spec_books')
        .select('version')
        .eq('project_id', projectId)
        .order('version', ascending: false)
        .limit(1)
        .maybeSingle();
    final nextVer =
        maxRow == null ? 1 : ((maxRow['version'] as num).toInt() + 1);
    final row = await _supabase
        .from('spec_books')
        .insert({
          'workspace_id': workspaceId,
          'project_id': projectId,
          'title': title,
          'description': description,
          'version': nextVer,
          'created_by': _supabase.auth.currentUser?.id,
        })
        .select()
        .single();
    return SpecBook.fromMap(row);
  }

  Future<SpecBook> updateBookMeta(String id,
      {String? title, String? description}) async {
    final patch = <String, dynamic>{};
    if (title != null) patch['title'] = title;
    if (description != null) patch['description'] = description;
    final row = await _supabase
        .from('spec_books')
        .update(patch)
        .eq('id', id)
        .select()
        .single();
    return SpecBook.fromMap(row);
  }

  Future<void> deleteBook(String id) async {
    await _supabase.from('spec_books').delete().eq('id', id);
  }

  Future<SpecBook> issueBook(String id) async {
    final row = await _supabase.rpc('spec_book_issue',
        params: {'p_book_id': id});
    return SpecBook.fromMap(Map<String, dynamic>.from(row as Map));
  }

  Future<String> signOff({
    required String bookId,
    required String signerName,
    String? signerEmail,
    String? signerRole,
    String? signatureText,
    String? notes,
  }) async {
    final res = await _supabase.rpc('spec_book_sign_off', params: {
      'p_book_id': bookId,
      'p_signer_name': signerName,
      if (signerEmail != null) 'p_signer_email': signerEmail,
      if (signerRole != null) 'p_signer_role': signerRole,
      if (signatureText != null) 'p_signature_text': signatureText,
      if (notes != null) 'p_notes': notes,
    });
    return res.toString();
  }

  Future<String> newVersion(String sourceBookId) async {
    final res = await _supabase
        .rpc('spec_book_new_version', params: {'p_source_id': sourceBookId});
    return res.toString();
  }

  // ---------------- Sections ----------------

  Future<List<SpecSection>> listSections(String bookId) async {
    final rows = await _supabase
        .from('spec_sections')
        .select()
        .eq('book_id', bookId)
        .order('sort_order');
    return (rows as List).map((r) => SpecSection.fromMap(r)).toList();
  }

  Stream<List<SpecSection>> watchSections(String bookId) {
    return _supabase
        .from('spec_sections')
        .stream(primaryKey: ['id'])
        .eq('book_id', bookId)
        .order('sort_order')
        .map((rows) => rows.map((r) => SpecSection.fromMap(r)).toList());
  }

  Future<SpecSection> createSection({
    required String bookId,
    String? parentId,
    String? code,
    required String title,
    String? body,
    int? sortOrder,
  }) async {
    // workspace_id is set by trigger.
    final row = await _supabase
        .from('spec_sections')
        .insert({
          'workspace_id': '00000000-0000-0000-0000-000000000000',
          'book_id': bookId,
          'parent_id': parentId,
          'code': code,
          'title': title,
          'body': body,
          'sort_order': sortOrder ?? 0,
        })
        .select()
        .single();
    return SpecSection.fromMap(row);
  }

  Future<SpecSection> updateSection(String id, Map<String, dynamic> patch) async {
    final row = await _supabase
        .from('spec_sections')
        .update(patch)
        .eq('id', id)
        .select()
        .single();
    return SpecSection.fromMap(row);
  }

  Future<void> deleteSection(String id) async {
    await _supabase.from('spec_sections').delete().eq('id', id);
  }

  // ---------------- Items ----------------

  Future<List<SpecItem>> listItems(String bookId) async {
    final rows = await _supabase
        .from('spec_items')
        .select()
        .eq('book_id', bookId)
        .order('sort_order');
    return (rows as List).map((r) => SpecItem.fromMap(r)).toList();
  }

  Stream<List<SpecItem>> watchItems(String bookId) {
    return _supabase
        .from('spec_items')
        .stream(primaryKey: ['id'])
        .eq('book_id', bookId)
        .order('sort_order')
        .map((rows) => rows.map((r) => SpecItem.fromMap(r)).toList());
  }

  Future<SpecItem> createItem({
    required String bookId,
    required String sectionId,
    String? itemNo,
    required String description,
    String? manufacturer,
    String? model,
    num? qty,
    String? unit,
    String? notes,
    int? sortOrder,
  }) async {
    final row = await _supabase
        .from('spec_items')
        .insert({
          'workspace_id': '00000000-0000-0000-0000-000000000000',
          'book_id': bookId,
          'section_id': sectionId,
          'item_no': itemNo,
          'description': description,
          'manufacturer': manufacturer,
          'model': model,
          'qty': qty,
          'unit': unit,
          'notes': notes,
          'sort_order': sortOrder ?? 0,
        })
        .select()
        .single();
    return SpecItem.fromMap(row);
  }

  Future<SpecItem> updateItem(String id, Map<String, dynamic> patch) async {
    final row = await _supabase
        .from('spec_items')
        .update(patch)
        .eq('id', id)
        .select()
        .single();
    return SpecItem.fromMap(row);
  }

  Future<void> deleteItem(String id) async {
    await _supabase.from('spec_items').delete().eq('id', id);
  }

  // ---------------- Sign-offs ----------------

  Future<List<SpecSignoff>> listSignoffs(String bookId) async {
    final rows = await _supabase
        .from('spec_signoffs')
        .select()
        .eq('book_id', bookId)
        .order('signed_at', ascending: false);
    return (rows as List).map((r) => SpecSignoff.fromMap(r)).toList();
  }

  // ---------------- Spec Sheets (saved PDFs) ----------------

  static const String _sheetSelect =
      'id, workspace_id, project_id, title, file_attachment_id, '
      'item_ids, item_count, created_by, created_at, '
      'file_attachments(file_name, file_url, file_size, mime_type)';

  Stream<List<SpecSheet>> watchSheets(String projectId) {
    // Realtime streams don't support FK joins; subscribe to row changes for
    // the list and hydrate the joined file_attachments on each tick.
    return _supabase
        .from('spec_sheets')
        .stream(primaryKey: ['id'])
        .eq('project_id', projectId)
        .order('created_at', ascending: false)
        .asyncMap((rows) async {
      if (rows.isEmpty) return <SpecSheet>[];
      final hydrated = await _supabase
          .from('spec_sheets')
          .select(_sheetSelect)
          .eq('project_id', projectId)
          .order('created_at', ascending: false);
      return (hydrated as List)
          .map((r) => SpecSheet.fromMap(Map<String, dynamic>.from(r as Map)))
          .toList();
    });
  }

  Future<SpecSheet> createSheet({
    required String workspaceId,
    required String projectId,
    required String title,
    required String fileAttachmentId,
    required List<String> itemIds,
  }) async {
    final row = await _supabase
        .from('spec_sheets')
        .insert({
          'workspace_id': workspaceId,
          'project_id': projectId,
          'title': title,
          'file_attachment_id': fileAttachmentId,
          'item_ids': itemIds,
          'item_count': itemIds.length,
          'created_by': _supabase.auth.currentUser?.id,
        })
        .select(_sheetSelect)
        .single();
    return SpecSheet.fromMap(Map<String, dynamic>.from(row));
  }

  Future<void> deleteSheet(String sheetId) async {
    // Best-effort: load the sheet first so we can also remove the underlying
    // file_attachment (which cascades to the storage row). If the sheet is
    // already gone we treat the delete as a no-op.
    try {
      final row = await _supabase
          .from('spec_sheets')
          .select('file_attachment_id')
          .eq('id', sheetId)
          .maybeSingle();
      await _supabase.from('spec_sheets').delete().eq('id', sheetId);
      final fileId = row?['file_attachment_id'] as String?;
      if (fileId != null) {
        await _supabase.from('file_attachments').delete().eq('id', fileId);
      }
    } catch (e) {
      AppLogger.error('deleteSheet failed', error: e);
      rethrow;
    }
  }
}
