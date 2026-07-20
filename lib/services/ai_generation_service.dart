import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/app_notification.dart';
import '../models/project.dart';
import '../models/workflow_template.dart';
import 'ai_service.dart';
import 'service_locator.dart';
import '../utils/app_logger.dart';

/// Singleton service that runs AI plan generation outside the widget lifecycle.
///
/// Usage:
///   AiGenerationService.instance.generateInBackground(...)
///
/// The caller can await the returned Future to get the planId, then navigate
/// away — generation continues and fires an in-app notification on completion.
class AiGenerationService {
  AiGenerationService._();
  static final AiGenerationService instance = AiGenerationService._();

  final _supabase = Supabase.instance.client;

  /// Starts background generation and returns the planId immediately.
  /// A notification is created when the plan is ready or failed.
  Future<String> generateInBackground({
    required Project project,
    required String workspaceId,
    required String userId,
    String? description,
    WorkflowTemplate? workflowTemplate,
    AiPersonaContext? persona,
    String? currency,
  }) async {
    final result = await _supabase.from('ai_generated_plans').insert({
      'project_id': project.id,
      'workspace_id': workspaceId,
      'user_id': userId,
      'status': 'generating',
    }).select('id').single();

    final planId = result['id'] as String;

    // Fire and forget — generation continues after caller navigates away
    unawaited(
      _runGeneration(
        planId: planId,
        project: project,
        workspaceId: workspaceId,
        userId: userId,
        description: description,
        workflowTemplate: workflowTemplate,
        persona: persona,
        currency: currency,
      ),
    );

    return planId;
  }

  /// Checks for any plans stuck in 'generating' status (e.g. app was killed
  /// mid-generation). Call this on app launch to surface failed plans.
  Future<void> recoverOrphanedPlans({
    required String userId,
    required String workspaceId,
    Duration staleBefore = const Duration(minutes: 10),
  }) async {
    try {
      final cutoff = DateTime.now().subtract(staleBefore).toIso8601String();
      final rows = await _supabase
          .from('ai_generated_plans')
          .select('id, project_id')
          .eq('user_id', userId)
          .eq('status', 'generating')
          .lt('created_at', cutoff);

      for (final row in rows as List) {
        final planId = row['id'] as String;
        final projectId = row['project_id'] as String;

        await _supabase.from('ai_generated_plans').update({
          'status': 'failed',
          'error_message': 'Generation interrupted — app was closed.',
          'updated_at': DateTime.now().toIso8601String(),
        }).eq('id', planId);

        await ServiceLocator.notificationService.createNotification(
          userId: userId,
          workspaceId: workspaceId,
          type: AppNotificationTypes.aiPlanFailed,
          title: 'AI plan generation was interrupted',
          body: 'Tap to retry generating the plan.',
          metadata: {'project_id': projectId, 'ai_plan_id': planId},
        );
      }
    } catch (e) {
      AppLogger.error('Error recovering orphaned AI plans', error: e);
    }
  }

  Future<void> _runGeneration({
    required String planId,
    required Project project,
    required String workspaceId,
    required String userId,
    String? description,
    WorkflowTemplate? workflowTemplate,
    AiPersonaContext? persona,
    String? currency,
  }) async {
    try {
      final aiService = AiService();
      final plan = await aiService.generateProjectPlan(
        projectName: project.name,
        description: description?.isNotEmpty == true ? description : null,
        jobType: project.jobType?.displayName,
        address: project.address.isNotEmpty ? project.address : null,
        projectContext: AiProjectContext(
          projectName: project.name,
          location: project.address.isNotEmpty ? project.address : null,
          jobType: project.jobType?.displayName,
          estimatedBudget: project.estimatedBudget,
          materialMarkupPercent: project.materialMarkupPercent,
          laborMarkupPercent: project.laborMarkupPercent,
          currency: currency,
        ),
        workflowTemplateName: workflowTemplate?.name,
        workflowTemplateDescription: workflowTemplate?.description,
        workflowTemplateMarkdown: workflowTemplate?.workflowMarkdown,
        workflowTemplateSchema: workflowTemplate?.workflowSchema,
        persona: persona,
      );

      await _supabase.from('ai_generated_plans').update({
        'status': 'ready',
        'plan_json': plan.toJson(),
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', planId);

      await ServiceLocator.notificationService.createNotification(
        userId: userId,
        workspaceId: workspaceId,
        type: AppNotificationTypes.aiPlanReady,
        title: 'AI plan ready for ${project.name}',
        body: 'Tap to review and import the generated plan.',
        metadata: {'project_id': project.id, 'ai_plan_id': planId},
      );
    } catch (e) {
      AppLogger.error('Background AI generation failed', error: e);

      await _supabase.from('ai_generated_plans').update({
        'status': 'failed',
        'error_message': e.toString(),
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', planId);

      await ServiceLocator.notificationService.createNotification(
        userId: userId,
        workspaceId: workspaceId,
        type: AppNotificationTypes.aiPlanFailed,
        title: 'AI plan generation failed for ${project.name}',
        body: 'Tap to retry.',
        metadata: {'project_id': project.id, 'ai_plan_id': planId},
      );
    }
  }
}
