import '../models/ai_copilot_models.dart';

class AiCopilotService {
  Future<bool> isFeatureEnabled({
    required String workspaceId,
    required String flagKey,
  }) async {
    return false;
  }

  Future<void> setFeatureFlag({
    required String workspaceId,
    required String flagKey,
    required bool enabled,
  }) async {}

  Future<AiProjectRiskAssessment> getProjectRiskAssessment({
    required String workspaceId,
    required String userId,
    required String projectId,
  }) async {
    throw UnimplementedError('AI copilot is not available for this backend');
  }

  Future<AiScheduleOptimizationResult> getScheduleOptimization({
    required String workspaceId,
    required String userId,
    required String projectId,
  }) async {
    throw UnimplementedError('AI copilot is not available for this backend');
  }

  Future<AiWeeklyProjectDigest> generateWeeklyDigest({
    required String workspaceId,
    required String userId,
    required String projectId,
    bool force = false,
  }) async {
    throw UnimplementedError('AI copilot is not available for this backend');
  }

  Future<void> applyScheduleSuggestion({
    required String workspaceId,
    required String userId,
    required AiScheduleSuggestion suggestion,
  }) async {
    throw UnimplementedError('AI copilot is not available for this backend');
  }
}
