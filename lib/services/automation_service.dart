import '../models/automation_rule.dart';

/// Firebase placeholder for automation rules (Supabase-only feature for now).
class AutomationService {
  UnsupportedError _unsupported() => UnsupportedError(
    'Automation rules are currently supported only on Supabase backend.',
  );

  Future<List<AutomationRule>> listRules({required String workspaceId}) async {
    throw _unsupported();
  }

  Future<AutomationRule> getRuleById({required String ruleId}) async {
    throw _unsupported();
  }

  Future<AutomationRule> createRule({
    required String workspaceId,
    required String name,
    String? description,
    required AutomationTriggerType triggerType,
    Map<String, dynamic>? conditions,
    List<AutomationActionDraft> actions = const [],
    bool isEnabled = true,
    required String actorUserId,
  }) async {
    throw _unsupported();
  }

  Future<void> updateRule({
    required String ruleId,
    String? name,
    String? description,
    AutomationTriggerType? triggerType,
    Map<String, dynamic>? conditions,
    bool? isEnabled,
    List<AutomationActionDraft>? replaceActions,
    required String actorUserId,
  }) async {
    throw _unsupported();
  }

  Future<void> setRuleEnabled({
    required String ruleId,
    required bool isEnabled,
    required String actorUserId,
  }) async {
    throw _unsupported();
  }

  Future<void> deleteRule({required String ruleId}) async {
    throw _unsupported();
  }

  Future<List<AutomationExecution>> listExecutions({
    required String workspaceId,
    String? ruleId,
    int limit = 100,
  }) async {
    throw _unsupported();
  }
}
