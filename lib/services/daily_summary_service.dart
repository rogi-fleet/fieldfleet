import '../models/daily_ai_summary.dart';
import '../utils/app_logger.dart';

/// Firebase placeholder for daily AI summaries (Supabase only feature).
class DailySummaryService {
  Future<DailyAiSummary?> getTodaySummary({
    required String workspaceId,
    required String userId,
  }) async {
    AppLogger.warning('Daily summary not available for Firebase backend');
    return null;
  }

  Future<bool> generateSummary({
    required String workspaceId,
    required String userId,
    String? date,
    bool force = false,
  }) async {
    AppLogger.warning('Daily summary generation not available for Firebase backend');
    return false;
  }
}
