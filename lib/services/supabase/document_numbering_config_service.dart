import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/document_numbering_config.dart';

/// Supabase service for managing document numbering configuration per workspace.
class SupabaseDocumentNumberingConfigService {
  final SupabaseClient _supabase = Supabase.instance.client;

  static const _table = 'document_numbering_config';

  /// Fetch all numbering configs for a workspace.
  Future<List<DocumentNumberingConfig>> getConfigs(String workspaceId) async {
    final rows = await _supabase
        .from(_table)
        .select()
        .eq('workspace_id', workspaceId);
    return rows.map((r) => DocumentNumberingConfig.fromJson(r)).toList();
  }

  /// Fetch config for a specific document type (returns null if using defaults).
  Future<DocumentNumberingConfig?> getConfig(
    String workspaceId,
    String documentType,
  ) async {
    final row = await _supabase
        .from(_table)
        .select()
        .eq('workspace_id', workspaceId)
        .eq('document_type', documentType)
        .maybeSingle();
    return row != null ? DocumentNumberingConfig.fromJson(row) : null;
  }

  /// Create or update a numbering config.
  Future<DocumentNumberingConfig> upsertConfig({
    required String workspaceId,
    required String documentType,
    required String prefix,
    int paddingWidth = 3,
    String separator = '-',
  }) async {
    final row = await _supabase
        .from(_table)
        .upsert({
          'workspace_id': workspaceId,
          'document_type': documentType,
          'prefix': prefix,
          'padding_width': paddingWidth,
          'separator': separator,
        })
        .select()
        .single();
    return DocumentNumberingConfig.fromJson(row);
  }

  /// Delete a custom config (reverts to hard-coded defaults).
  Future<void> deleteConfig({
    required String workspaceId,
    required String documentType,
  }) async {
    await _supabase
        .from(_table)
        .delete()
        .eq('workspace_id', workspaceId)
        .eq('document_type', documentType);
  }

  /// Atomically set the counter value for a document type.
  Future<void> setCounter({
    required String workspaceId,
    required String documentType,
    required int value,
  }) async {
    await _supabase.rpc('set_document_counter', params: {
      'p_workspace_id': workspaceId,
      'p_document_type': documentType,
      'p_value': value,
    });
  }

  /// Get current counter value for a document type.
  Future<int> getCurrentCounter({
    required String workspaceId,
    required String documentType,
  }) async {
    final result = await _supabase
        .from('document_counters')
        .select('current_value')
        .eq('workspace_id', workspaceId)
        .eq('document_type', documentType)
        .maybeSingle();
    return result?['current_value'] as int? ?? 0;
  }

  /// Get all counter values for a workspace (for the settings screen).
  Future<Map<String, int>> getAllCounters(String workspaceId) async {
    final rows = await _supabase
        .from('document_counters')
        .select('document_type, current_value')
        .eq('workspace_id', workspaceId);
    return {
      for (final r in rows)
        r['document_type'] as String: r['current_value'] as int,
    };
  }
}
