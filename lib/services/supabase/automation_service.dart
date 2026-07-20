import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/automation_rule.dart';
import '../../utils/app_logger.dart';
import 'notification_service.dart';
import 'task_group_template_service.dart';

class SupabaseAutomationService {
  final SupabaseClient _supabase = Supabase.instance.client;

  Future<List<AutomationRule>> listRules({required String workspaceId}) async {
    try {
      final rows = await _supabase
          .from('automation_rules')
          .select('*, automation_actions(*)')
          .eq('workspace_id', workspaceId)
          .order('created_at', ascending: false);

      return rows
          .map((row) => AutomationRule.fromRow(Map<String, dynamic>.from(row)))
          .toList();
    } catch (e) {
      AppLogger.error('Failed to list automation rules', error: e);
      rethrow;
    }
  }

  Future<AutomationRule> getRuleById({required String ruleId}) async {
    try {
      final row = await _supabase
          .from('automation_rules')
          .select('*, automation_actions(*)')
          .eq('id', ruleId)
          .single();

      return AutomationRule.fromRow(Map<String, dynamic>.from(row));
    } catch (e) {
      AppLogger.error('Failed to load automation rule', error: e);
      rethrow;
    }
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
    try {
      final now = DateTime.now().toIso8601String();
      final createdRule = await _supabase
          .from('automation_rules')
          .insert({
            'workspace_id': workspaceId,
            'name': name,
            'description': description,
            'trigger_type': triggerType.dbValue,
            'conditions': conditions ?? {},
            'is_enabled': isEnabled,
            'created_by': actorUserId,
            'updated_by': actorUserId,
            'created_at': now,
            'updated_at': now,
          })
          .select('id')
          .single();

      final ruleId = createdRule['id'] as String;
      if (actions.isNotEmpty) {
        final actionRows = actions
            .map(
              (action) =>
                  action.toInsertMap(ruleId: ruleId, workspaceId: workspaceId)
                    ..addAll({'created_at': now, 'updated_at': now}),
            )
            .toList();

        await _supabase.from('automation_actions').insert(actionRows);
      }

      return getRuleById(ruleId: ruleId);
    } catch (e) {
      AppLogger.error('Failed to create automation rule', error: e);
      rethrow;
    }
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
    try {
      final now = DateTime.now().toIso8601String();
      final updates = <String, dynamic>{
        'updated_by': actorUserId,
        'updated_at': now,
      };

      if (name != null) updates['name'] = name;
      if (description != null) updates['description'] = description;
      if (triggerType != null) updates['trigger_type'] = triggerType.dbValue;
      if (conditions != null) updates['conditions'] = conditions;
      if (isEnabled != null) updates['is_enabled'] = isEnabled;

      await _supabase.from('automation_rules').update(updates).eq('id', ruleId);

      if (replaceActions != null) {
        final rule = await _supabase
            .from('automation_rules')
            .select('workspace_id')
            .eq('id', ruleId)
            .single();
        final workspaceId = rule['workspace_id'] as String;

        await _supabase
            .from('automation_actions')
            .delete()
            .eq('rule_id', ruleId);

        if (replaceActions.isNotEmpty) {
          final actionRows = replaceActions
              .map(
                (action) =>
                    action.toInsertMap(ruleId: ruleId, workspaceId: workspaceId)
                      ..addAll({'created_at': now, 'updated_at': now}),
              )
              .toList();
          await _supabase.from('automation_actions').insert(actionRows);
        }
      }
    } catch (e) {
      AppLogger.error('Failed to update automation rule', error: e);
      rethrow;
    }
  }

  Future<void> setRuleEnabled({
    required String ruleId,
    required bool isEnabled,
    required String actorUserId,
  }) async {
    return updateRule(
      ruleId: ruleId,
      isEnabled: isEnabled,
      actorUserId: actorUserId,
    );
  }

  Future<void> deleteRule({required String ruleId}) async {
    try {
      await _supabase.from('automation_rules').delete().eq('id', ruleId);
    } catch (e) {
      AppLogger.error('Failed to delete automation rule', error: e);
      rethrow;
    }
  }

  Future<List<AutomationExecution>> listExecutions({
    required String workspaceId,
    String? ruleId,
    int limit = 100,
  }) async {
    try {
      var query = _supabase
          .from('automation_executions')
          .select()
          .eq('workspace_id', workspaceId);

      if (ruleId != null && ruleId.isNotEmpty) {
        query = query.eq('rule_id', ruleId);
      }

      final rows = await query
          .order('created_at', ascending: false)
          .limit(limit);

      return rows
          .map(
            (row) =>
                AutomationExecution.fromRow(Map<String, dynamic>.from(row)),
          )
          .toList();
    } catch (e) {
      AppLogger.error('Failed to list automation executions', error: e);
      rethrow;
    }
  }

  Future<void> processTaskStatusChanged({
    required String workspaceId,
    required String taskId,
    required String projectId,
    required String taskTitle,
    required String fromStatus,
    required String toStatus,
    required String actorUserId,
    String? eventKey,
  }) async {
    await _processEvent(
      workspaceId: workspaceId,
      triggerType: AutomationTriggerType.taskStatusChanged,
      eventKey:
          eventKey ??
          'task_status_changed:$taskId:$fromStatus:$toStatus:${DateTime.now().toIso8601String()}',
      actorUserId: actorUserId,
      context: {
        'task_id': taskId,
        'project_id': projectId,
        'task_title': taskTitle,
        'from_status': fromStatus,
        'to_status': toStatus,
      },
    );
  }

  Future<void> processTaskAssigned({
    required String workspaceId,
    required String taskId,
    required String projectId,
    required String taskTitle,
    required List<String> assignedUserIds,
    required String actorUserId,
    String? eventKey,
  }) async {
    if (assignedUserIds.isEmpty) return;

    await _processEvent(
      workspaceId: workspaceId,
      triggerType: AutomationTriggerType.taskAssigned,
      eventKey:
          eventKey ??
          'task_assigned:$taskId:${assignedUserIds.join(',')}:${DateTime.now().toIso8601String()}',
      actorUserId: actorUserId,
      context: {
        'task_id': taskId,
        'project_id': projectId,
        'task_title': taskTitle,
        'assigned_user_ids': assignedUserIds,
      },
    );
  }

  Future<void> processInvoiceStatusChanged({
    required String workspaceId,
    required String invoiceId,
    required String projectId,
    required String invoiceNumber,
    required String fromStatus,
    required String toStatus,
    required String actorUserId,
    String? eventKey,
  }) async {
    await _processEvent(
      workspaceId: workspaceId,
      triggerType: AutomationTriggerType.invoiceStatusChanged,
      eventKey:
          eventKey ??
          'invoice_status_changed:$invoiceId:$fromStatus:$toStatus:${DateTime.now().toIso8601String()}',
      actorUserId: actorUserId,
      context: {
        'invoice_id': invoiceId,
        'project_id': projectId,
        'invoice_number': invoiceNumber,
        'from_status': fromStatus,
        'to_status': toStatus,
      },
    );
  }

  /// New lead entered the pipeline — e.g. auto-apply an intake to-do list.
  /// Event key is timestamp-free: an opportunity is only created once, so
  /// retries dedupe naturally.
  Future<void> processOpportunityCreated({
    required String workspaceId,
    required String opportunityId,
    required String opportunityName,
    String? customerId,
    required String actorUserId,
  }) async {
    await _processEvent(
      workspaceId: workspaceId,
      triggerType: AutomationTriggerType.opportunityCreated,
      eventKey: 'opportunity_created:$opportunityId',
      actorUserId: actorUserId,
      context: {
        'opportunity_id': opportunityId,
        'opportunity_name': opportunityName,
        if (customerId != null) 'customer_id': customerId,
      },
    );
  }

  /// New job created — e.g. preload a schedule template via
  /// the apply_task_template action.
  Future<void> processProjectCreated({
    required String workspaceId,
    required String projectId,
    required String projectName,
    required String actorUserId,
  }) async {
    await _processEvent(
      workspaceId: workspaceId,
      triggerType: AutomationTriggerType.projectCreated,
      eventKey: 'project_created:$projectId',
      actorUserId: actorUserId,
      context: {'project_id': projectId, 'project_name': projectName},
    );
  }

  /// A document was signed in-app. Note: signatures captured through the
  /// PUBLIC signing link run unauthenticated, where RLS hides the rules —
  /// those signings do not fire automations (server-side dispatch would be
  /// needed).
  Future<void> processDocumentSigned({
    required String workspaceId,
    required String documentId,
    required String documentType,
    String? documentNumber,
    String? projectId,
    required String actorUserId,
  }) async {
    await _processEvent(
      workspaceId: workspaceId,
      triggerType: AutomationTriggerType.documentSigned,
      eventKey: 'document_signed:$documentId',
      actorUserId: actorUserId,
      context: {
        'document_id': documentId,
        'document_type': documentType,
        if (documentNumber != null) 'document_number': documentNumber,
        if (projectId != null) 'project_id': projectId,
      },
    );
  }

  /// Worker clocked out — e.g. remind them to file a daily log
  /// (create_notification with target 'actor').
  Future<void> processTimeEntryClockedOut({
    required String workspaceId,
    required String timeEntryId,
    required String workerId,
    String? projectId,
    String? taskId,
    required String actorUserId,
  }) async {
    await _processEvent(
      workspaceId: workspaceId,
      triggerType: AutomationTriggerType.timeEntryClockedOut,
      eventKey: 'time_entry_clocked_out:$timeEntryId',
      actorUserId: actorUserId,
      context: {
        'time_entry_id': timeEntryId,
        'worker_id': workerId,
        if (projectId != null) 'project_id': projectId,
        if (taskId != null) 'task_id': taskId,
      },
    );
  }

  Future<void> _processEvent({
    required String workspaceId,
    required AutomationTriggerType triggerType,
    required String eventKey,
    required String actorUserId,
    required Map<String, dynamic> context,
  }) async {
    try {
      final rows = await _supabase
          .from('automation_rules')
          .select('*, automation_actions(*)')
          .eq('workspace_id', workspaceId)
          .eq('is_enabled', true)
          .eq('trigger_type', triggerType.dbValue)
          .order('created_at', ascending: false);

      final rules = rows
          .map((row) => AutomationRule.fromRow(Map<String, dynamic>.from(row)))
          .toList();

      for (final rule in rules) {
        if (!_conditionsMatch(rule.conditions, context)) {
          continue;
        }

        final duplicate = await _supabase
            .from('automation_executions')
            .select('id')
            .eq('workspace_id', workspaceId)
            .eq('rule_id', rule.id)
            .eq('event_key', eventKey)
            .limit(1)
            .maybeSingle();
        if (duplicate != null) {
          await _logExecution(
            workspaceId: workspaceId,
            ruleId: rule.id,
            triggerType: triggerType,
            eventKey: eventKey,
            status: AutomationExecutionStatus.skipped,
            metadata: {...context, 'reason': 'duplicate_event'},
            executedActions: const [],
          );
          continue;
        }

        final executedActions = <Map<String, dynamic>>[];
        try {
          for (final action in rule.actions) {
            final actionResult = await _executeAction(
              action: action,
              workspaceId: workspaceId,
              actorUserId: actorUserId,
              context: context,
            );
            executedActions.add(actionResult);
          }

          await _logExecution(
            workspaceId: workspaceId,
            ruleId: rule.id,
            triggerType: triggerType,
            eventKey: eventKey,
            status: AutomationExecutionStatus.success,
            metadata: context,
            executedActions: executedActions,
          );
        } catch (e) {
          await _logExecution(
            workspaceId: workspaceId,
            ruleId: rule.id,
            triggerType: triggerType,
            eventKey: eventKey,
            status: AutomationExecutionStatus.failed,
            metadata: context,
            executedActions: executedActions,
            errorMessage: e.toString(),
          );
        }
      }
    } catch (e) {
      AppLogger.error(
        'Failed to process automation event',
        error: e,
        metadata: {
          'workspaceId': workspaceId,
          'triggerType': triggerType.dbValue,
          'eventKey': eventKey,
        },
      );
    }
  }

  bool _conditionsMatch(
    Map<String, dynamic> conditions,
    Map<String, dynamic> context,
  ) {
    if (conditions.isEmpty) return true;

    final projectId = conditions['project_id'];
    if (projectId is String && projectId.isNotEmpty) {
      if (context['project_id'] != projectId) return false;
    }

    final taskId = conditions['task_id'];
    if (taskId is String && taskId.isNotEmpty) {
      if (context['task_id'] != taskId) return false;
    }

    final fromStatus = conditions['from_status'];
    if (fromStatus is String && fromStatus.isNotEmpty) {
      if ((context['from_status'] as String?) != fromStatus) return false;
    }

    final toStatus = conditions['to_status'];
    if (toStatus is String && toStatus.isNotEmpty) {
      if ((context['to_status'] as String?) != toStatus) return false;
    }

    final documentType = conditions['document_type'];
    if (documentType is String && documentType.isNotEmpty) {
      if ((context['document_type'] as String?) != documentType) return false;
    }

    final assignedAny = conditions['assigned_user_any'];
    if (assignedAny is List && assignedAny.isNotEmpty) {
      final eventAssigned =
          (context['assigned_user_ids'] as List?)
              ?.map((e) => e.toString())
              .toSet() ??
          <String>{};
      final required = assignedAny.map((e) => e.toString()).toSet();
      if (eventAssigned.intersection(required).isEmpty) return false;
    }

    return true;
  }

  Future<Map<String, dynamic>> _executeAction({
    required AutomationAction action,
    required String workspaceId,
    required String actorUserId,
    required Map<String, dynamic> context,
  }) async {
    switch (action.actionType) {
      case AutomationActionType.createNotification:
        return _executeCreateNotification(
          action: action,
          workspaceId: workspaceId,
          actorUserId: actorUserId,
          context: context,
        );
      case AutomationActionType.createTask:
        return _executeCreateTask(
          action: action,
          workspaceId: workspaceId,
          actorUserId: actorUserId,
          context: context,
        );
      case AutomationActionType.updateField:
        return _executeUpdateField(action: action, context: context);
      case AutomationActionType.addTag:
        return {
          'action': action.actionType.dbValue,
          'status': 'skipped',
          'reason': 'add_tag_not_implemented_yet',
        };
      case AutomationActionType.applyTaskTemplate:
        return _executeApplyTaskTemplate(
          action: action,
          workspaceId: workspaceId,
          context: context,
        );
    }
  }

  /// Instantiates a task-group template (snapshot tree with relative dates
  /// and intra-group dependencies) into the event's project. Payload:
  /// `{"template_id": "...", "project_id": "..."(optional override)}`.
  Future<Map<String, dynamic>> _executeApplyTaskTemplate({
    required AutomationAction action,
    required String workspaceId,
    required Map<String, dynamic> context,
  }) async {
    final templateId = (action.payload['template_id'] as String?)?.trim();
    final projectId =
        (action.payload['project_id'] as String?)?.trim() ??
        (context['project_id'] as String?);

    if (templateId == null || templateId.isEmpty) {
      return {
        'action': action.actionType.dbValue,
        'status': 'skipped',
        'reason': 'missing_template_id',
      };
    }
    if (projectId == null || projectId.isEmpty) {
      return {
        'action': action.actionType.dbValue,
        'status': 'skipped',
        'reason': 'no_project_context',
      };
    }

    final created =
        await SupabaseTaskGroupTemplateService().applyTemplateToProject(
      templateId: templateId,
      projectId: projectId,
      workspaceId: workspaceId,
    );

    return {
      'action': action.actionType.dbValue,
      'status': 'executed',
      'template_id': templateId,
      'project_id': projectId,
      'created_task_count': created,
    };
  }

  Future<Map<String, dynamic>> _executeCreateNotification({
    required AutomationAction action,
    required String workspaceId,
    required String actorUserId,
    required Map<String, dynamic> context,
  }) async {
    final recipients = await _resolveNotificationRecipients(
      action.payload,
      workspaceId,
      actorUserId,
      context,
    );

    if (recipients.isEmpty) {
      return {
        'action': action.actionType.dbValue,
        'status': 'skipped',
        'reason': 'no_recipients',
      };
    }

    final title = (action.payload['title'] as String?)?.trim();
    final body = (action.payload['body'] as String?)?.trim();
    final metadata = _buildNotificationMetadata(action.payload, context);

    final notificationService = SupabaseNotificationService();
    for (final recipient in recipients) {
      await notificationService.createNotification(
        userId: recipient,
        workspaceId: workspaceId,
        type: 'automation',
        title: _interpolate(
          title?.isNotEmpty == true ? title! : 'Automation alert',
          context,
        ),
        body: body == null || body.isEmpty ? null : _interpolate(body, context),
        metadata: metadata,
      );
    }

    return {
      'action': action.actionType.dbValue,
      'status': 'executed',
      'recipient_count': recipients.length,
    };
  }

  Future<List<String>> _resolveNotificationRecipients(
    Map<String, dynamic> payload,
    String workspaceId,
    String actorUserId,
    Map<String, dynamic> context,
  ) async {
    final target = (payload['target'] as String?)?.trim();

    if (target == 'actor') {
      return [actorUserId];
    }

    if (target == 'assigned_users') {
      return ((context['assigned_user_ids'] as List?) ?? const [])
          .map((e) => e.toString())
          .where((id) => id.isNotEmpty)
          .toSet()
          .toList();
    }

    if (target == 'workspace_admins') {
      final admins = await _supabase
          .from('workspace_members')
          .select('user_id')
          .eq('workspace_id', workspaceId)
          .eq('role', 'admin');
      return admins
          .map((row) => row['user_id'] as String?)
          .whereType<String>()
          .where((id) => id.isNotEmpty)
          .toSet()
          .toList();
    }

    final explicit = payload['target_user_ids'];
    if (explicit is List) {
      return explicit
          .map((e) => e.toString())
          .where((id) => id.isNotEmpty)
          .toSet()
          .toList();
    }

    return const [];
  }

  Map<String, dynamic> _buildNotificationMetadata(
    Map<String, dynamic> payload,
    Map<String, dynamic> context,
  ) {
    final merged = <String, dynamic>{};
    final payloadMetadata = payload['metadata'];
    if (payloadMetadata is Map) {
      merged.addAll(Map<String, dynamic>.from(payloadMetadata));
    }

    for (final key in const ['project_id', 'task_id', 'invoice_id']) {
      final value = context[key];
      if (value is String && value.isNotEmpty) {
        merged[key] = value;
      }
    }

    if (context['project_id'] is String && context['task_id'] is String) {
      final projectId = context['project_id'] as String;
      final taskId = context['task_id'] as String;
      merged['tab'] = 'tasks';
      merged['deeplink_path'] = '/projects/$projectId?tab=tasks&taskId=$taskId';
    } else if (context['invoice_id'] is String) {
      final invoiceId = context['invoice_id'] as String;
      merged['deeplink_path'] = '/invoices/$invoiceId';
    }

    return merged;
  }

  Future<Map<String, dynamic>> _executeCreateTask({
    required AutomationAction action,
    required String workspaceId,
    required String actorUserId,
    required Map<String, dynamic> context,
  }) async {
    final projectId =
        (action.payload['project_id'] as String?)?.trim() ??
        (context['project_id'] as String?);
    final title = (action.payload['title'] as String?)?.trim();

    if (projectId == null ||
        projectId.isEmpty ||
        title == null ||
        title.isEmpty) {
      return {
        'action': action.actionType.dbValue,
        'status': 'skipped',
        'reason': 'missing_project_or_title',
      };
    }

    final dueInDays = (action.payload['due_in_days'] as num?)?.toInt();
    final now = DateTime.now();

    final insert = await _supabase
        .from('tasks')
        .insert({
          'workspace_id': workspaceId,
          'project_id': projectId,
          'title': _interpolate(title, context),
          'description': _interpolate(
            (action.payload['description'] as String?)?.trim() ?? '',
            context,
          ),
          'status':
              (action.payload['status'] as String?)?.trim() ?? 'not_started',
          'priority':
              (action.payload['priority'] as String?)?.trim() ?? 'medium',
          'assigned_to_ids':
              ((action.payload['assigned_to_ids'] as List?) ?? const [])
                  .map((e) => e.toString())
                  .where((id) => id.isNotEmpty)
                  .toList(),
          'created_at': now.toIso8601String(),
          'updated_at': now.toIso8601String(),
          if (dueInDays != null)
            'due_date': now.add(Duration(days: dueInDays)).toIso8601String(),
        })
        .select('id')
        .single();

    return {
      'action': action.actionType.dbValue,
      'status': 'executed',
      'created_task_id': insert['id'],
    };
  }

  Future<Map<String, dynamic>> _executeUpdateField({
    required AutomationAction action,
    required Map<String, dynamic> context,
  }) async {
    final entity = (action.payload['entity'] as String?)?.trim();
    final field = (action.payload['field'] as String?)?.trim();
    final value = action.payload['value'];

    if (entity == null || field == null || field.isEmpty) {
      return {
        'action': action.actionType.dbValue,
        'status': 'skipped',
        'reason': 'missing_entity_or_field',
      };
    }

    if (entity == 'task') {
      final taskId = context['task_id'] as String?;
      if (taskId == null || taskId.isEmpty) {
        return {
          'action': action.actionType.dbValue,
          'status': 'skipped',
          'reason': 'no_task_context',
        };
      }
      await _supabase
          .from('tasks')
          .update({
            field: value,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', taskId);
      return {
        'action': action.actionType.dbValue,
        'status': 'executed',
        'entity': 'task',
        'entity_id': taskId,
      };
    }

    if (entity == 'invoice') {
      final invoiceId = context['invoice_id'] as String?;
      if (invoiceId == null || invoiceId.isEmpty) {
        return {
          'action': action.actionType.dbValue,
          'status': 'skipped',
          'reason': 'no_invoice_context',
        };
      }
      await _supabase
          .from('generated_documents')
          .update({
            field: value,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', invoiceId);
      return {
        'action': action.actionType.dbValue,
        'status': 'executed',
        'entity': 'invoice',
        'entity_id': invoiceId,
      };
    }

    return {
      'action': action.actionType.dbValue,
      'status': 'skipped',
      'reason': 'unsupported_entity',
    };
  }

  String _interpolate(String input, Map<String, dynamic> context) {
    var output = input;
    for (final entry in context.entries) {
      final value = entry.value;
      if (value is String) {
        output = output.replaceAll('{${entry.key}}', value);
      }
    }
    return output;
  }

  Future<void> _logExecution({
    required String workspaceId,
    required String? ruleId,
    required AutomationTriggerType triggerType,
    required String eventKey,
    required AutomationExecutionStatus status,
    required Map<String, dynamic> metadata,
    required List<Map<String, dynamic>> executedActions,
    String? errorMessage,
  }) async {
    await _supabase.from('automation_executions').insert({
      'workspace_id': workspaceId,
      'rule_id': ruleId,
      'trigger_type': triggerType.dbValue,
      'event_key': eventKey,
      'status': status.dbValue,
      'error_message': errorMessage,
      'metadata': metadata,
      'executed_actions': executedActions,
      'created_at': DateTime.now().toIso8601String(),
    });
  }
}
