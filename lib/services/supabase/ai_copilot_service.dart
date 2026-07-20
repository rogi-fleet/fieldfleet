import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/supabase_config.dart';
import '../../models/ai_copilot_models.dart';
import '../../utils/app_logger.dart';

class SupabaseAiCopilotService {
  final SupabaseClient _supabase = Supabase.instance.client;

  static const String _functionPath = '/functions/v1/ai-copilot';
  static const String _textOpsFunctionPath = '/functions/v1/ai-text-ops';
  static const Duration _requestTimeout = Duration(seconds: 30);

  Future<String?> _getAccessToken({bool forceRefresh = false}) async {
    if (forceRefresh) {
      final refreshed = await _supabase.auth.refreshSession();
      return refreshed.session?.accessToken;
    }
    return _supabase.auth.currentSession?.accessToken ??
        (await _supabase.auth.refreshSession()).session?.accessToken;
  }

  Future<http.Response> _postInvoke({
    required String token,
    required Map<String, dynamic> body,
  }) {
    final url = '${SupabaseConfig.url}$_functionPath';
    return http
        .post(
          Uri.parse(url),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
            'apikey': SupabaseConfig.anonKey,
          },
          body: jsonEncode(body),
        )
        .timeout(_requestTimeout);
  }

  String _errorMessageFromBody(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map && decoded['error'] != null) {
        return decoded['error'].toString();
      }
    } catch (_) {
      // Body is not JSON; fall back to raw response text.
    }
    return body;
  }

  @visibleForTesting
  static bool wouldCreateCircularDependency({
    required Map<String, List<String>> predecessorGraph,
    required String taskId,
    required String newPredecessorId,
  }) {
    if (taskId == newPredecessorId) {
      return true;
    }

    final visited = <String>{};
    final queue = <String>[newPredecessorId];
    while (queue.isNotEmpty) {
      final current = queue.removeLast();
      if (!visited.add(current)) continue;
      if (current == taskId) {
        return true;
      }
      final predecessors = predecessorGraph[current] ?? const <String>[];
      queue.addAll(predecessors);
    }
    return false;
  }

  Future<Map<String, dynamic>> _invoke({
    required String operation,
    required String workspaceId,
    required String userId,
    required String projectId,
    Map<String, dynamic>? context,
    bool force = false,
  }) async {
    final token = await _getAccessToken();
    if (token == null) {
      throw Exception('Authentication required');
    }

    final requestBody = <String, dynamic>{
      'operation': operation,
      'workspace_id': workspaceId,
      'user_id': userId,
      'project_id': projectId,
      if (context != null) 'context': context,
      if (force) 'force': true,
    };

    var response = await _postInvoke(token: token, body: requestBody);
    if (response.statusCode == 401) {
      final refreshedToken = await _getAccessToken(forceRefresh: true);
      if (refreshedToken != null) {
        response = await _postInvoke(token: refreshedToken, body: requestBody);
      }
    }

    if (response.statusCode != 200) {
      final message = _errorMessageFromBody(response.body);
      throw Exception('AI copilot failed (${response.statusCode}): $message');
    }

    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    final result = payload['result'];
    if (result is! Map<String, dynamic>) {
      throw Exception('Invalid AI copilot response payload');
    }
    return result;
  }

  Future<bool> isFeatureEnabled({
    required String workspaceId,
    required String flagKey,
  }) async {
    try {
      final row = await _supabase
          .from('workspace_feature_flags')
          .select('flags')
          .eq('workspace_id', workspaceId)
          .maybeSingle();
      final flags = Map<String, dynamic>.from(
        (row?['flags'] as Map?) ?? const <String, dynamic>{},
      );
      return flags[flagKey] == true;
    } catch (e) {
      AppLogger.warning(
        'Failed to read AI feature flags',
        metadata: {
          'workspaceId': workspaceId,
          'flagKey': flagKey,
          'error': e.toString(),
        },
      );
      return false;
    }
  }

  Future<void> setFeatureFlag({
    required String workspaceId,
    required String flagKey,
    required bool enabled,
  }) async {
    final row = await _supabase
        .from('workspace_feature_flags')
        .select('flags')
        .eq('workspace_id', workspaceId)
        .maybeSingle();
    final flags = Map<String, dynamic>.from(
      (row?['flags'] as Map?) ?? const <String, dynamic>{},
    );
    flags[flagKey] = enabled;

    await _supabase.from('workspace_feature_flags').upsert({
      'workspace_id': workspaceId,
      'flags': flags,
      'updated_at': DateTime.now().toIso8601String(),
    });
  }

  Future<AiProjectRiskAssessment> getProjectRiskAssessment({
    required String workspaceId,
    required String userId,
    required String projectId,
  }) async {
    final result = await _invoke(
      operation: 'risk_score',
      workspaceId: workspaceId,
      userId: userId,
      projectId: projectId,
    );
    return AiProjectRiskAssessment.fromJson(result);
  }

  Future<AiScheduleOptimizationResult> getScheduleOptimization({
    required String workspaceId,
    required String userId,
    required String projectId,
  }) async {
    final result = await _invoke(
      operation: 'schedule_optimize',
      workspaceId: workspaceId,
      userId: userId,
      projectId: projectId,
    );
    return AiScheduleOptimizationResult.fromJson(result);
  }

  Future<AiWeeklyProjectDigest> generateWeeklyDigest({
    required String workspaceId,
    required String userId,
    required String projectId,
    bool force = false,
  }) async {
    final result = await _invoke(
      operation: 'weekly_digest',
      workspaceId: workspaceId,
      userId: userId,
      projectId: projectId,
      force: force,
    );
    return AiWeeklyProjectDigest.fromJson(result);
  }

  // ===========================================================================
  // Text ops (ai-text-ops Edge Function) — used by the file comment composer
  // for rewrite / expand / tone transforms. Gated by `ai_text_ops_v1` flag.
  // ===========================================================================

  /// Rewrite [text] in a more [style] voice ('concise' | 'clear' |
  /// 'professional'). Returns the LLM's rewritten string. Throws on failure
  /// so the caller can preserve the user's original input and show a toast.
  Future<String> rewriteText({
    required String workspaceId,
    required String text,
    String style = 'clear',
  }) {
    return _invokeTextOp({
      'operation': 'rewrite',
      'workspace_id': workspaceId,
      'text': text,
      'style': style,
    });
  }

  /// Expand [text] to a slightly longer version while preserving meaning.
  Future<String> expandText({
    required String workspaceId,
    required String text,
  }) {
    return _invokeTextOp({
      'operation': 'expand',
      'workspace_id': workspaceId,
      'text': text,
    });
  }

  /// Rewrite [text] with the given [tone] ('friendly' | 'formal' | 'direct').
  Future<String> toneText({
    required String workspaceId,
    required String text,
    String tone = 'friendly',
  }) {
    return _invokeTextOp({
      'operation': 'tone',
      'workspace_id': workspaceId,
      'text': text,
      'tone': tone,
    });
  }

  Future<String> _invokeTextOp(Map<String, dynamic> body) async {
    final token = await _getAccessToken();
    if (token == null) {
      throw Exception('Authentication required');
    }

    final url = '${SupabaseConfig.url}$_textOpsFunctionPath';
    var response = await http
        .post(
          Uri.parse(url),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
            'apikey': SupabaseConfig.anonKey,
          },
          body: jsonEncode(body),
        )
        .timeout(_requestTimeout);

    if (response.statusCode == 401) {
      final refreshed = await _getAccessToken(forceRefresh: true);
      if (refreshed != null) {
        response = await http
            .post(
              Uri.parse(url),
              headers: {
                'Content-Type': 'application/json',
                'Authorization': 'Bearer $refreshed',
                'apikey': SupabaseConfig.anonKey,
              },
              body: jsonEncode(body),
            )
            .timeout(_requestTimeout);
      }
    }

    if (response.statusCode != 200) {
      final message = _errorMessageFromBody(response.body);
      throw Exception('AI text op failed (${response.statusCode}): $message');
    }

    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    final text = payload['text'];
    if (text is! String || text.isEmpty) {
      throw Exception('Empty response from text op');
    }
    return text;
  }

  Future<void> applyScheduleSuggestion({
    required String workspaceId,
    required String userId,
    required AiScheduleSuggestion suggestion,
  }) async {
    // Human approval is enforced by caller before calling this method.
    // Here we only apply deterministic dependency updates.
    final rows = await _supabase
        .from('tasks')
        .select('id, predecessor_ids')
        .eq('workspace_id', workspaceId);
    final predecessorGraph = <String, List<String>>{
      for (final row in rows)
        (row['id'] as String): List<String>.from(
          (row['predecessor_ids'] as List?) ?? const <String>[],
        ),
    };

    for (final change in suggestion.changes) {
      if (change.taskId.isEmpty || change.addPredecessorId == null) {
        continue;
      }
      if (!predecessorGraph.containsKey(change.taskId) ||
          !predecessorGraph.containsKey(change.addPredecessorId)) {
        continue;
      }

      final existing = await _supabase
          .from('tasks')
          .select('predecessor_ids')
          .eq('workspace_id', workspaceId)
          .eq('id', change.taskId)
          .maybeSingle();
      if (existing == null) {
        continue;
      }

      final predecessors = List<String>.from(
        (existing['predecessor_ids'] as List?) ?? const <String>[],
      );
      if (wouldCreateCircularDependency(
        predecessorGraph: predecessorGraph,
        taskId: change.taskId,
        newPredecessorId: change.addPredecessorId!,
      )) {
        continue;
      }
      if (!predecessors.contains(change.addPredecessorId)) {
        predecessors.add(change.addPredecessorId!);
      }

      await _supabase
          .from('tasks')
          .update({
            'predecessor_ids': predecessors,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('workspace_id', workspaceId)
          .eq('id', change.taskId);

      predecessorGraph[change.taskId] = predecessors;
    }

    // Log accepted suggestion action
    await _supabase.from('ai_copilot_events').insert({
      'workspace_id': workspaceId,
      'user_id': userId,
      'operation': 'schedule_optimize_apply',
      'status': 'approved',
      'request_payload': {
        'suggestion_id': suggestion.id,
        'change_count': suggestion.changes.length,
      },
      'response_payload': {'title': suggestion.title},
      'provider': 'rule_based',
      'model': null,
      'latency_ms': 0,
      'error': null,
    });
  }
}
