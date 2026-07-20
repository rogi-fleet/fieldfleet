import 'dart:convert';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:http/http.dart' as http;
import '../../config/supabase_config.dart';
import '../../models/daily_ai_summary.dart';
import '../../utils/app_logger.dart';

class SupabaseDailySummaryService {
  final SupabaseClient _supabase = Supabase.instance.client;

  String _todayDateString() {
    return DateFormat('yyyy-MM-dd').format(DateTime.now());
  }

  Future<DailyAiSummary?> getTodaySummary({
    required String workspaceId,
    required String userId,
  }) async {
    return getSummaryForDate(
      workspaceId: workspaceId,
      userId: userId,
      date: _todayDateString(),
    );
  }

  Future<DailyAiSummary?> getSummaryForDate({
    required String workspaceId,
    required String userId,
    required String date,
  }) async {
    try {
      final response = await _supabase
          .from('daily_ai_summaries')
          .select()
          .eq('workspace_id', workspaceId)
          .eq('user_id', userId)
          .eq('summary_date', date)
          .order('generated_at', ascending: false)
          .limit(1)
          .maybeSingle();

      if (response == null) {
        return null;
      }

      return DailyAiSummary.fromSupabase(response);
    } catch (e) {
      AppLogger.error('Failed to fetch daily summary', error: e, metadata: {
        'workspaceId': workspaceId,
        'userId': userId,
        'date': date,
      });
      return null;
    }
  }

  Future<bool> generateSummary({
    required String workspaceId,
    required String userId,
    String? date,
    bool force = false,
  }) async {
    try {
      final session = _supabase.auth.currentSession;
      if (session == null) {
        await _supabase.auth.refreshSession();
      }
      final accessToken = _supabase.auth.currentSession?.accessToken;
      if (accessToken == null) {
        throw Exception('User must be authenticated to generate summary');
      }

      final edgeFunctionUrl = '${SupabaseConfig.url}/functions/v1/daily-ai-summary';

      final response = await http.post(
        Uri.parse(edgeFunctionUrl),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $accessToken',
          'apikey': SupabaseConfig.anonKey,
        },
        body: jsonEncode({
          'workspace_id': workspaceId,
          'user_id': userId,
          if (date != null) 'date': date,
          if (force) 'force': true,
        }),
      );

      if (response.statusCode == 200) {
        return true;
      }

      AppLogger.warning('Failed to generate daily summary', metadata: {
        'statusCode': response.statusCode,
        'response': response.body,
      });
      return false;
    } catch (e) {
      AppLogger.error('Error generating daily summary', error: e, metadata: {
        'workspaceId': workspaceId,
        'userId': userId,
        'date': date,
      });
      return false;
    }
  }
}
