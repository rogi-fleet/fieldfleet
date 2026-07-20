import 'package:supabase_flutter/supabase_flutter.dart';
import '../../utils/app_logger.dart';

/// One workspace API key row (the plaintext key is never stored or listed —
/// it is returned exactly once by [ApiKeyService.createKey]).
class WorkspaceApiKey {
  final String id;
  final String workspaceId;
  final String name;
  final String keyPrefix;
  final List<String> scopes;
  final DateTime createdAt;
  final DateTime? lastUsedAt;
  final DateTime? revokedAt;

  const WorkspaceApiKey({
    required this.id,
    required this.workspaceId,
    required this.name,
    required this.keyPrefix,
    required this.scopes,
    required this.createdAt,
    this.lastUsedAt,
    this.revokedAt,
  });

  bool get isRevoked => revokedAt != null;

  factory WorkspaceApiKey.fromRow(Map<String, dynamic> row) {
    return WorkspaceApiKey(
      id: row['id'] as String,
      workspaceId: row['workspace_id'] as String,
      name: row['name'] as String,
      keyPrefix: row['key_prefix'] as String,
      scopes: (row['scopes'] as List?)?.map((e) => e.toString()).toList() ??
          const [],
      createdAt: DateTime.parse(row['created_at'] as String),
      lastUsedAt: row['last_used_at'] != null
          ? DateTime.parse(row['last_used_at'] as String)
          : null,
      revokedAt: row['revoked_at'] != null
          ? DateTime.parse(row['revoked_at'] as String)
          : null,
    );
  }
}

/// Admin management of workspace API keys (used by the MCP server / public
/// API). RLS restricts every operation to workspace admins.
class ApiKeyService {
  final SupabaseClient _supabase = Supabase.instance.client;

  Future<List<WorkspaceApiKey>> listKeys(String workspaceId) async {
    final rows = await _supabase
        .from('workspace_api_keys')
        .select()
        .eq('workspace_id', workspaceId)
        .order('created_at', ascending: false);
    return rows
        .map((row) => WorkspaceApiKey.fromRow(Map<String, dynamic>.from(row)))
        .toList();
  }

  /// Creates a key and returns its PLAINTEXT — the only time it is visible.
  Future<String> createKey({
    required String workspaceId,
    required String name,
    List<String> scopes = const ['read', 'write'],
  }) async {
    final result = await _supabase.rpc('create_workspace_api_key', params: {
      'p_workspace_id': workspaceId,
      'p_name': name,
      'p_scopes': scopes,
    });
    AppLogger.info('Created workspace API key', metadata: {
      'workspaceId': workspaceId,
      'name': name,
    });
    return (result as Map)['key'] as String;
  }

  Future<void> revokeKey(String keyId) async {
    await _supabase
        .from('workspace_api_keys')
        .update({'revoked_at': DateTime.now().toUtc().toIso8601String()})
        .eq('id', keyId);
  }
}
