import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../models/automation_rule.dart';
import '../../providers/auth_provider.dart';
import '../../providers/workspace_provider.dart';
import '../../services/service_locator.dart';
import '../../theme/theme.dart';
import '../../utils/project_terminology.dart';

import 'package:taskfleet_ops/widgets/forms/stacked_field.dart';

class AutomationRulesScreen extends StatefulWidget {
  const AutomationRulesScreen({super.key});

  @override
  State<AutomationRulesScreen> createState() => _AutomationRulesScreenState();
}

class _AutomationRulesScreenState extends State<AutomationRulesScreen> {
  final dynamic _automationService = ServiceLocator.automationService;

  bool _isLoading = true;
  bool _isSaving = false;
  String? _workspaceId;
  List<AutomationRule> _rules = const [];
  List<AutomationExecution> _executions = const [];

  String? _loadedWorkspaceId;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Re-run once the workspace hydrates. _loadData() from initState captured a
    // null workspace on cold load/refresh and rendered a permanent "No active
    // workspace selected." with no retry; listen:true re-fires here.
    final wid =
        Provider.of<AuthProvider>(context).appUser?.currentWorkspaceId;
    if (wid != null && wid.isNotEmpty && wid != _loadedWorkspaceId) {
      _loadedWorkspaceId = wid;
      _loadData();
    }
  }

  Future<void> _loadData() async {
    final workspaceId =
        context.read<AuthProvider>().appUser?.currentWorkspaceId ?? '';

    if (workspaceId.isEmpty) {
      if (!mounted) return;
      setState(() {
        _workspaceId = null;
        _rules = const [];
        _executions = const [];
        _isLoading = false;
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _workspaceId = workspaceId;
    });

    try {
      final results = await Future.wait([
        _automationService.listRules(workspaceId: workspaceId)
            as Future<List<AutomationRule>>,
        _automationService.listExecutions(workspaceId: workspaceId, limit: 20)
            as Future<List<AutomationExecution>>,
      ]);

      if (!mounted) return;
      setState(() {
        _rules = results[0] as List<AutomationRule>;
        _executions = results[1] as List<AutomationExecution>;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to load automations: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  Future<void> _toggleRule(AutomationRule rule, bool enabled) async {
    final actorUserId = context.read<AuthProvider>().currentUserId;
    if (actorUserId == null) return;

    try {
      await _automationService.setRuleEnabled(
        ruleId: rule.id,
        isEnabled: enabled,
        actorUserId: actorUserId,
      );
      await _loadData();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to update rule: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  Future<void> _deleteRule(AutomationRule rule) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Rule?'),
        content: Text('Delete "${rule.name}" permanently?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isSaving = true);
    try {
      await _automationService.deleteRule(ruleId: rule.id);
      await _loadData();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to delete rule: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _showRuleDialog({AutomationRule? rule}) async {
    final actorUserId = context.read<AuthProvider>().currentUserId;
    final workspaceId = _workspaceId;
    if (actorUserId == null || workspaceId == null) return;

    final firstAction = rule != null && rule.actions.isNotEmpty
        ? rule.actions.first
        : null;

    final nameController = TextEditingController(text: rule?.name ?? '');
    final descriptionController = TextEditingController(
      text: rule?.description ?? '',
    );
    var triggerType =
        rule?.triggerType ?? AutomationTriggerType.taskStatusChanged;
    var actionType =
        firstAction?.actionType ?? AutomationActionType.createNotification;

    final conditionsController = TextEditingController(
      text: _prettyJson(rule?.conditions ?? {}),
    );
    final payloadController = TextEditingController(
      text: _prettyJson(
        firstAction?.payload ?? _defaultPayloadForAction(actionType),
      ),
    );

    // Guided builder state
    var advancedMode = false;
    var conditionProjectId = (rule?.conditions['project_id'] as String?) ?? '';
    var conditionFromStatus =
        (rule?.conditions['from_status'] as String?) ?? '';
    var conditionToStatus = (rule?.conditions['to_status'] as String?) ?? '';
    var conditionAssignedUserAny = _csvFromDynamicList(
      rule?.conditions['assigned_user_any'],
    );

    var notificationTarget =
        (firstAction?.payload['target'] as String?) ?? 'assigned_users';
    final notificationTitleController = TextEditingController(
      text:
          (firstAction?.payload['title'] as String?) ??
          'Task needs attention: {task_title}',
    );
    final notificationBodyController = TextEditingController(
      text:
          (firstAction?.payload['body'] as String?) ??
          'Status changed from {from_status} to {to_status}',
    );
    var notificationUsersCsv = _csvFromDynamicList(
      firstAction?.payload['target_user_ids'],
    );

    final createTaskTitleController = TextEditingController(
      text:
          (firstAction?.payload['title'] as String?) ??
          'Follow up on {task_title}',
    );
    final createTaskDescriptionController = TextEditingController(
      text:
          (firstAction?.payload['description'] as String?) ??
          'Created by automation rule.',
    );
    var createTaskDueInDays =
        (firstAction?.payload['due_in_days'] as num?)?.toInt() ?? 1;
    var createTaskStatus =
        (firstAction?.payload['status'] as String?) ?? 'not_started';
    var createTaskPriority =
        (firstAction?.payload['priority'] as String?) ?? 'medium';

    var updateFieldEntity =
        (firstAction?.payload['entity'] as String?) ?? 'task';
    final updateFieldNameController = TextEditingController(
      text: (firstAction?.payload['field'] as String?) ?? 'priority',
    );
    final updateFieldValueController = TextEditingController(
      text: (firstAction?.payload['value'] as String?)?.toString() ?? 'high',
    );

    final applyTemplateIdController = TextEditingController(
      text: (firstAction?.payload['template_id'] as String?) ?? '',
    );

    final addTagController = TextEditingController(
      text: (firstAction?.payload['tag'] as String?) ?? 'at_risk',
    );
    var selectedTemplate = '';

    void applyTemplate(String key) {
      switch (key) {
        case 'blocked_task_alert':
          nameController.text = 'Blocked Task Alert';
          descriptionController.text =
              'Notify assigned users when a task becomes blocked.';
          triggerType = AutomationTriggerType.taskStatusChanged;
          actionType = AutomationActionType.createNotification;
          conditionFromStatus = '';
          conditionToStatus = 'stuck';
          notificationTarget = 'assigned_users';
          notificationTitleController.text = 'Task blocked: {task_title}';
          notificationBodyController.text =
              'Task changed to blocked status and may need attention.';
          break;
        case 'new_assignment_alert':
          nameController.text = 'New Assignment Alert';
          descriptionController.text =
              'Notify users whenever they are assigned to a task.';
          triggerType = AutomationTriggerType.taskAssigned;
          actionType = AutomationActionType.createNotification;
          conditionFromStatus = '';
          conditionToStatus = '';
          notificationTarget = 'assigned_users';
          notificationTitleController.text = 'You were assigned: {task_title}';
          notificationBodyController.text =
              'Open the task to review scope and due date.';
          break;
        case 'invoice_overdue_alert':
          nameController.text = 'Invoice Overdue Alert';
          descriptionController.text =
              'Alert workspace admins when invoices become overdue.';
          triggerType = AutomationTriggerType.invoiceStatusChanged;
          actionType = AutomationActionType.createNotification;
          conditionFromStatus = '';
          conditionToStatus = 'overdue';
          notificationTarget = 'workspace_admins';
          notificationTitleController.text =
              'Invoice overdue: {invoice_number}';
          notificationBodyController.text =
              'Invoice moved to overdue status and needs follow-up.';
          break;
        case 'new_job_schedule_template':
          nameController.text = 'Preload Schedule on New Job';
          descriptionController.text =
              'Apply a task group template automatically when a job is '
              'created.';
          triggerType = AutomationTriggerType.projectCreated;
          actionType = AutomationActionType.applyTaskTemplate;
          conditionFromStatus = '';
          conditionToStatus = '';
          applyTemplateIdController.text = '';
          break;
        case 'clockout_daily_log_reminder':
          nameController.text = 'Daily Log Reminder';
          descriptionController.text =
              'Remind crew members to file a daily log when they clock out.';
          triggerType = AutomationTriggerType.timeEntryClockedOut;
          actionType = AutomationActionType.createNotification;
          conditionFromStatus = '';
          conditionToStatus = '';
          notificationTarget = 'actor';
          notificationTitleController.text = 'Time to file your daily log';
          notificationBodyController.text =
              'You just clocked out. Take a minute to record today\'s '
              'progress, photos, and any issues.';
          break;
      }

      if (advancedMode) {
        conditionsController.text = _prettyJson(
          _buildConditionsFromGuided(
            triggerType: triggerType,
            projectId: conditionProjectId,
            fromStatus: conditionFromStatus,
            toStatus: conditionToStatus,
            assignedUserAnyCsv: conditionAssignedUserAny,
          ),
        );
        payloadController.text = _prettyJson(
          _buildPayloadFromGuided(
            actionType: actionType,
            notificationTarget: notificationTarget,
            notificationTitle: notificationTitleController.text.trim(),
            notificationBody: notificationBodyController.text.trim(),
            notificationUsersCsv: notificationUsersCsv,
            createTaskTitle: createTaskTitleController.text.trim(),
            createTaskDescription: createTaskDescriptionController.text.trim(),
            createTaskDueInDays: createTaskDueInDays,
            createTaskStatus: createTaskStatus,
            createTaskPriority: createTaskPriority,
            updateFieldEntity: updateFieldEntity,
            updateFieldName: updateFieldNameController.text.trim(),
            updateFieldValue: updateFieldValueController.text.trim(),
            addTag: addTagController.text.trim(),
            applyTemplateId: applyTemplateIdController.text.trim(),
          ),
        );
      }
    }

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(rule == null ? 'New Automation Rule' : 'Edit Rule'),
          content: SizedBox(
            width: 680,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  StackedField(
                    label: 'Rule Name',
                    child: TextField(
                      controller: nameController,
                      autofocus: rule == null,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  StackedField(
                    label: 'Description (Optional)',
                    child: TextField(
                      controller: descriptionController,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  StackedField(
                    label: 'Quick Template',
                    child: DropdownButtonFormField<String>(
                      borderRadius: AppRadius.cardRadius,
                      initialValue: selectedTemplate,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(value: '', child: Text('None')),
                        DropdownMenuItem(
                          value: 'blocked_task_alert',
                          child: Text('Blocked Task Alert'),
                        ),
                        DropdownMenuItem(
                          value: 'new_assignment_alert',
                          child: Text('New Assignment Alert'),
                        ),
                        DropdownMenuItem(
                          value: 'invoice_overdue_alert',
                          child: Text('Invoice Overdue Alert'),
                        ),
                        DropdownMenuItem(
                          value: 'new_job_schedule_template',
                          child: Text('Preload Schedule on New Job'),
                        ),
                        DropdownMenuItem(
                          value: 'clockout_daily_log_reminder',
                          child: Text('Daily Log Reminder on Clock-Out'),
                        ),
                      ],
                      onChanged: (value) {
                        if (value == null || value.isEmpty) {
                          setDialogState(() => selectedTemplate = '');
                          return;
                        }
                        setDialogState(() {
                          selectedTemplate = value;
                          applyTemplate(value);
                        });
                      },
                    ),
                  ),
                  const SizedBox(height: 12),
                  StackedField(
                    label: 'Trigger',
                    child: DropdownButtonFormField<AutomationTriggerType>(
                      borderRadius: AppRadius.cardRadius,
                      initialValue: triggerType,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                      ),
                      items: AutomationTriggerType.values
                          .map(
                            (value) => DropdownMenuItem(
                              value: value,
                              child: Text(_triggerLabel(value)),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value == null) return;
                        setDialogState(() => triggerType = value);
                      },
                    ),
                  ),
                  const SizedBox(height: 12),
                  StackedField(
                    label: 'Action',
                    child: DropdownButtonFormField<AutomationActionType>(
                      borderRadius: AppRadius.cardRadius,
                      initialValue: actionType,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                      ),
                      items: AutomationActionType.values
                          .map(
                            (value) => DropdownMenuItem(
                              value: value,
                              child: Text(_actionLabel(value)),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value == null) return;
                        setDialogState(() {
                          actionType = value;
                          if (!advancedMode) return;
                          payloadController.text = _prettyJson(
                            _defaultPayloadForAction(value),
                          );
                        });
                      },
                    ),
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Advanced JSON Mode'),
                    subtitle: const Text(
                      'Use raw JSON for custom/edge-case conditions and payloads',
                    ),
                    value: advancedMode,
                    onChanged: (value) {
                      setDialogState(() {
                        advancedMode = value;
                        if (advancedMode) {
                          conditionsController.text = _prettyJson(
                            _buildConditionsFromGuided(
                              triggerType: triggerType,
                              projectId: conditionProjectId,
                              fromStatus: conditionFromStatus,
                              toStatus: conditionToStatus,
                              assignedUserAnyCsv: conditionAssignedUserAny,
                            ),
                          );
                          payloadController.text = _prettyJson(
                            _buildPayloadFromGuided(
                              actionType: actionType,
                              notificationTarget: notificationTarget,
                              notificationTitle: notificationTitleController
                                  .text
                                  .trim(),
                              notificationBody: notificationBodyController.text
                                  .trim(),
                              notificationUsersCsv: notificationUsersCsv,
                              createTaskTitle: createTaskTitleController.text
                                  .trim(),
                              createTaskDescription:
                                  createTaskDescriptionController.text.trim(),
                              createTaskDueInDays: createTaskDueInDays,
                              createTaskStatus: createTaskStatus,
                              createTaskPriority: createTaskPriority,
                              updateFieldEntity: updateFieldEntity,
                              updateFieldName: updateFieldNameController.text
                                  .trim(),
                              updateFieldValue: updateFieldValueController.text
                                  .trim(),
                              addTag: addTagController.text.trim(),
                              applyTemplateId:
                                  applyTemplateIdController.text.trim(),
                            ),
                          );
                        }
                      });
                    },
                  ),
                  const SizedBox(height: 8),
                  if (!advancedMode) ...[
                    _buildGuidedConditionsSection(
                      triggerType: triggerType,
                      conditionProjectId: conditionProjectId,
                      conditionFromStatus: conditionFromStatus,
                      conditionToStatus: conditionToStatus,
                      conditionAssignedUserAny: conditionAssignedUserAny,
                      onProjectChanged: (value) =>
                          setDialogState(() => conditionProjectId = value),
                      onFromChanged: (value) =>
                          setDialogState(() => conditionFromStatus = value),
                      onToChanged: (value) =>
                          setDialogState(() => conditionToStatus = value),
                      onAssignedAnyChanged: (value) => setDialogState(
                        () => conditionAssignedUserAny = value,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _buildGuidedActionSection(
                      actionType: actionType,
                      notificationTarget: notificationTarget,
                      notificationTitleController: notificationTitleController,
                      notificationBodyController: notificationBodyController,
                      notificationUsersCsv: notificationUsersCsv,
                      onNotificationTargetChanged: (value) =>
                          setDialogState(() => notificationTarget = value),
                      onNotificationUsersChanged: (value) =>
                          setDialogState(() => notificationUsersCsv = value),
                      createTaskTitleController: createTaskTitleController,
                      createTaskDescriptionController:
                          createTaskDescriptionController,
                      createTaskDueInDays: createTaskDueInDays,
                      onCreateTaskDueInDaysChanged: (value) =>
                          setDialogState(() => createTaskDueInDays = value),
                      createTaskStatus: createTaskStatus,
                      onCreateTaskStatusChanged: (value) =>
                          setDialogState(() => createTaskStatus = value),
                      createTaskPriority: createTaskPriority,
                      onCreateTaskPriorityChanged: (value) =>
                          setDialogState(() => createTaskPriority = value),
                      updateFieldEntity: updateFieldEntity,
                      onUpdateFieldEntityChanged: (value) =>
                          setDialogState(() => updateFieldEntity = value),
                      updateFieldNameController: updateFieldNameController,
                      updateFieldValueController: updateFieldValueController,
                      addTagController: addTagController,
                      applyTemplateIdController: applyTemplateIdController,
                    ),
                  ] else ...[
                    StackedField(
                      label: 'Conditions JSON',
                      child: TextField(
                        controller: conditionsController,
                        minLines: 4,
                        maxLines: 10,
                        decoration: const InputDecoration(
                          helperText:
                              'Example: {"project_id":"...","from_status":"not_started","to_status":"stuck"}',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    StackedField(
                      label: 'Action Payload JSON',
                      child: TextField(
                        controller: payloadController,
                        minLines: 5,
                        maxLines: 14,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                if (nameController.text.trim().isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Rule name is required')),
                  );
                  return;
                }
                Navigator.pop(context, true);
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );

    if (saved != true || !mounted) return;

    late final Map<String, dynamic> conditions;
    late final Map<String, dynamic> payload;

    try {
      if (advancedMode) {
        conditions = _parseJsonMap(
          conditionsController.text,
          field: 'Conditions',
        );
        payload = _parseJsonMap(
          payloadController.text,
          field: 'Action payload',
        );
      } else {
        conditions = _buildConditionsFromGuided(
          triggerType: triggerType,
          projectId: conditionProjectId,
          fromStatus: conditionFromStatus,
          toStatus: conditionToStatus,
          assignedUserAnyCsv: conditionAssignedUserAny,
        );
        payload = _buildPayloadFromGuided(
          actionType: actionType,
          notificationTarget: notificationTarget,
          notificationTitle: notificationTitleController.text.trim(),
          notificationBody: notificationBodyController.text.trim(),
          notificationUsersCsv: notificationUsersCsv,
          createTaskTitle: createTaskTitleController.text.trim(),
          createTaskDescription: createTaskDescriptionController.text.trim(),
          createTaskDueInDays: createTaskDueInDays,
          createTaskStatus: createTaskStatus,
          createTaskPriority: createTaskPriority,
          updateFieldEntity: updateFieldEntity,
          updateFieldName: updateFieldNameController.text.trim(),
          updateFieldValue: updateFieldValueController.text.trim(),
          addTag: addTagController.text.trim(),
          applyTemplateId: applyTemplateIdController.text.trim(),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString()), backgroundColor: AppColors.error),
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      final actionDraft = AutomationActionDraft(
        actionType: actionType,
        payload: payload,
        sortOrder: 0,
      );

      if (rule == null) {
        await _automationService.createRule(
          workspaceId: workspaceId,
          name: nameController.text.trim(),
          description: descriptionController.text.trim().isEmpty
              ? null
              : descriptionController.text.trim(),
          triggerType: triggerType,
          conditions: conditions,
          actions: [actionDraft],
          actorUserId: actorUserId,
        );
      } else {
        await _automationService.updateRule(
          ruleId: rule.id,
          name: nameController.text.trim(),
          description: descriptionController.text.trim().isEmpty
              ? null
              : descriptionController.text.trim(),
          triggerType: triggerType,
          conditions: conditions,
          replaceActions: [actionDraft],
          actorUserId: actorUserId,
        );
      }

      await _loadData();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to save rule: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Widget _buildGuidedConditionsSection({
    required AutomationTriggerType triggerType,
    required String conditionProjectId,
    required String conditionFromStatus,
    required String conditionToStatus,
    required String conditionAssignedUserAny,
    required ValueChanged<String> onProjectChanged,
    required ValueChanged<String> onFromChanged,
    required ValueChanged<String> onToChanged,
    required ValueChanged<String> onAssignedAnyChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Conditions', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        StackedField(
          label: '${singularProjectTerminology(context.read<WorkspaceProvider>().projectTerminology)} ID (optional)',
          child: TextFormField(
            initialValue: conditionProjectId,
            onChanged: onProjectChanged,
            decoration: const InputDecoration(border: OutlineInputBorder()),
          ),
        ),
        if (triggerType == AutomationTriggerType.taskStatusChanged ||
            triggerType == AutomationTriggerType.invoiceStatusChanged) ...[
          const SizedBox(height: 8),
          StackedField(
            label: 'From Status (optional)',
            child: DropdownButtonFormField<String>(
              borderRadius: AppRadius.cardRadius,
              initialValue: conditionFromStatus.isEmpty
                  ? ''
                  : conditionFromStatus,
              decoration: const InputDecoration(border: OutlineInputBorder()),
              items: [
                const DropdownMenuItem(value: '', child: Text('Any')),
                ..._statusOptionsForTrigger(triggerType).map(
                  (status) => DropdownMenuItem(
                    value: status,
                    child: Text(_statusLabel(status)),
                  ),
                ),
              ],
              onChanged: (value) => onFromChanged(value ?? ''),
            ),
          ),
          const SizedBox(height: 8),
          StackedField(
            label: 'To Status (optional)',
            child: DropdownButtonFormField<String>(
              borderRadius: AppRadius.cardRadius,
              initialValue: conditionToStatus.isEmpty ? '' : conditionToStatus,
              decoration: const InputDecoration(border: OutlineInputBorder()),
              items: [
                const DropdownMenuItem(value: '', child: Text('Any')),
                ..._statusOptionsForTrigger(triggerType).map(
                  (status) => DropdownMenuItem(
                    value: status,
                    child: Text(_statusLabel(status)),
                  ),
                ),
              ],
              onChanged: (value) => onToChanged(value ?? ''),
            ),
          ),
        ],
        if (triggerType == AutomationTriggerType.taskAssigned) ...[
          const SizedBox(height: 8),
          StackedField(
            label: 'Assigned User IDs (comma-separated, optional)',
            child: TextFormField(
              initialValue: conditionAssignedUserAny,
              onChanged: onAssignedAnyChanged,
              decoration: const InputDecoration(border: OutlineInputBorder()),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildGuidedActionSection({
    required AutomationActionType actionType,
    required String notificationTarget,
    required TextEditingController notificationTitleController,
    required TextEditingController notificationBodyController,
    required String notificationUsersCsv,
    required ValueChanged<String> onNotificationTargetChanged,
    required ValueChanged<String> onNotificationUsersChanged,
    required TextEditingController createTaskTitleController,
    required TextEditingController createTaskDescriptionController,
    required int createTaskDueInDays,
    required ValueChanged<int> onCreateTaskDueInDaysChanged,
    required String createTaskStatus,
    required ValueChanged<String> onCreateTaskStatusChanged,
    required String createTaskPriority,
    required ValueChanged<String> onCreateTaskPriorityChanged,
    required String updateFieldEntity,
    required ValueChanged<String> onUpdateFieldEntityChanged,
    required TextEditingController updateFieldNameController,
    required TextEditingController updateFieldValueController,
    required TextEditingController addTagController,
    required TextEditingController applyTemplateIdController,
  }) {
    final triggerStatuses = _statusOptionsForTrigger(
      AutomationTriggerType.taskStatusChanged,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Action', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        if (actionType == AutomationActionType.createNotification) ...[
          StackedField(
            label: 'Notify',
            child: DropdownButtonFormField<String>(
              borderRadius: AppRadius.cardRadius,
              initialValue: notificationTarget,
              decoration: const InputDecoration(border: OutlineInputBorder()),
              items: const [
                DropdownMenuItem(
                  value: 'assigned_users',
                  child: Text('Assigned Users'),
                ),
                DropdownMenuItem(
                  value: 'workspace_admins',
                  child: Text('Workspace Admins'),
                ),
                DropdownMenuItem(value: 'actor', child: Text('Actor')),
                DropdownMenuItem(
                  value: 'target_user_ids',
                  child: Text('Specific Users'),
                ),
              ],
              onChanged: (value) =>
                  onNotificationTargetChanged(value ?? 'assigned_users'),
            ),
          ),
          if (notificationTarget == 'target_user_ids') ...[
            const SizedBox(height: 8),
            StackedField(
              label: 'Target User IDs (comma-separated)',
              child: TextFormField(
                initialValue: notificationUsersCsv,
                onChanged: onNotificationUsersChanged,
                decoration: const InputDecoration(border: OutlineInputBorder()),
              ),
            ),
          ],
          const SizedBox(height: 8),
          StackedField(
            label: 'Notification Title',
            child: TextField(
              controller: notificationTitleController,
              decoration: const InputDecoration(border: OutlineInputBorder()),
            ),
          ),
          const SizedBox(height: 8),
          StackedField(
            label: 'Notification Body (optional)',
            child: TextField(
              controller: notificationBodyController,
              decoration: const InputDecoration(border: OutlineInputBorder()),
            ),
          ),
        ] else if (actionType == AutomationActionType.createTask) ...[
          StackedField(
            label: 'Task Title',
            child: TextField(
              controller: createTaskTitleController,
              decoration: const InputDecoration(border: OutlineInputBorder()),
            ),
          ),
          const SizedBox(height: 8),
          StackedField(
            label: 'Task Description (optional)',
            child: TextField(
              controller: createTaskDescriptionController,
              decoration: const InputDecoration(border: OutlineInputBorder()),
            ),
          ),
          const SizedBox(height: 8),
          StackedField(
            label: 'Due In',
            child: DropdownButtonFormField<int>(
              borderRadius: AppRadius.cardRadius,
              initialValue: createTaskDueInDays,
              decoration: const InputDecoration(border: OutlineInputBorder()),
              items: const [
                DropdownMenuItem(value: 0, child: Text('Today')),
                DropdownMenuItem(value: 1, child: Text('1 day')),
                DropdownMenuItem(value: 2, child: Text('2 days')),
                DropdownMenuItem(value: 3, child: Text('3 days')),
                DropdownMenuItem(value: 7, child: Text('1 week')),
              ],
              onChanged: (value) => onCreateTaskDueInDaysChanged(value ?? 1),
            ),
          ),
          const SizedBox(height: 8),
          StackedField(
            label: 'Initial Status',
            child: DropdownButtonFormField<String>(
              borderRadius: AppRadius.cardRadius,
              initialValue: createTaskStatus,
              decoration: const InputDecoration(border: OutlineInputBorder()),
              items: triggerStatuses
                  .map(
                    (status) => DropdownMenuItem(
                      value: status,
                      child: Text(_statusLabel(status)),
                    ),
                  )
                  .toList(),
              onChanged: (value) =>
                  onCreateTaskStatusChanged(value ?? 'not_started'),
            ),
          ),
          const SizedBox(height: 8),
          StackedField(
            label: 'Initial Priority',
            child: DropdownButtonFormField<String>(
              borderRadius: AppRadius.cardRadius,
              initialValue: createTaskPriority,
              decoration: const InputDecoration(border: OutlineInputBorder()),
              items: const [
                DropdownMenuItem(value: 'low', child: Text('Low')),
                DropdownMenuItem(value: 'medium', child: Text('Medium')),
                DropdownMenuItem(value: 'high', child: Text('High')),
              ],
              onChanged: (value) =>
                  onCreateTaskPriorityChanged(value ?? 'medium'),
            ),
          ),
        ] else if (actionType == AutomationActionType.updateField) ...[
          StackedField(
            label: 'Entity',
            child: DropdownButtonFormField<String>(
              borderRadius: AppRadius.cardRadius,
              initialValue: updateFieldEntity,
              decoration: const InputDecoration(border: OutlineInputBorder()),
              items: const [
                DropdownMenuItem(value: 'task', child: Text('Task')),
                DropdownMenuItem(value: 'invoice', child: Text('Invoice')),
              ],
              onChanged: (value) => onUpdateFieldEntityChanged(value ?? 'task'),
            ),
          ),
          const SizedBox(height: 8),
          StackedField(
            label: 'Field Name',
            child: TextField(
              controller: updateFieldNameController,
              decoration: const InputDecoration(border: OutlineInputBorder()),
            ),
          ),
          const SizedBox(height: 8),
          StackedField(
            label: 'Field Value',
            child: TextField(
              controller: updateFieldValueController,
              decoration: const InputDecoration(border: OutlineInputBorder()),
            ),
          ),
        ] else if (actionType == AutomationActionType.applyTaskTemplate) ...[
          StackedField(
            label: 'Task Group Template ID',
            child: TextField(
              controller: applyTemplateIdController,
              decoration: const InputDecoration(border: OutlineInputBorder()),
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Applies the saved task group template (tasks, phases, relative '
            'dates, dependencies) to the project from the trigger. Copy the '
            'template ID from the task template manager.',
            style: TextStyle(fontSize: 12),
          ),
        ] else ...[
          StackedField(
            label: 'Tag',
            child: TextField(
              controller: addTagController,
              decoration: const InputDecoration(border: OutlineInputBorder()),
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Note: Add tag execution is currently marked as skipped by backend.',
            style: TextStyle(fontSize: 12),
          ),
        ],
      ],
    );
  }

  List<String> _statusOptionsForTrigger(AutomationTriggerType type) {
    if (type == AutomationTriggerType.invoiceStatusChanged) {
      return const ['draft', 'sent', 'paid', 'overdue', 'cancelled'];
    }
    return const ['not_started', 'working_on_it', 'stuck', 'done'];
  }

  String _statusLabel(String value) {
    switch (value) {
      case 'not_started':
        return 'Not Started';
      case 'working_on_it':
        return 'Working On It';
      default:
        return value[0].toUpperCase() + value.substring(1);
    }
  }

  Map<String, dynamic> _buildConditionsFromGuided({
    required AutomationTriggerType triggerType,
    required String projectId,
    required String fromStatus,
    required String toStatus,
    required String assignedUserAnyCsv,
  }) {
    final conditions = <String, dynamic>{};

    if (projectId.trim().isNotEmpty) {
      conditions['project_id'] = projectId.trim();
    }

    if ((triggerType == AutomationTriggerType.taskStatusChanged ||
            triggerType == AutomationTriggerType.invoiceStatusChanged) &&
        fromStatus.trim().isNotEmpty) {
      conditions['from_status'] = fromStatus.trim();
    }

    if ((triggerType == AutomationTriggerType.taskStatusChanged ||
            triggerType == AutomationTriggerType.invoiceStatusChanged) &&
        toStatus.trim().isNotEmpty) {
      conditions['to_status'] = toStatus.trim();
    }

    if (triggerType == AutomationTriggerType.taskAssigned &&
        assignedUserAnyCsv.trim().isNotEmpty) {
      conditions['assigned_user_any'] = _parseCsvIds(assignedUserAnyCsv);
    }

    return conditions;
  }

  Map<String, dynamic> _buildPayloadFromGuided({
    required AutomationActionType actionType,
    required String notificationTarget,
    required String notificationTitle,
    required String notificationBody,
    required String notificationUsersCsv,
    required String createTaskTitle,
    required String createTaskDescription,
    required int createTaskDueInDays,
    required String createTaskStatus,
    required String createTaskPriority,
    required String updateFieldEntity,
    required String updateFieldName,
    required String updateFieldValue,
    required String addTag,
    required String applyTemplateId,
  }) {
    switch (actionType) {
      case AutomationActionType.createNotification:
        final payload = <String, dynamic>{
          'target': notificationTarget,
          'title': notificationTitle.isNotEmpty
              ? notificationTitle
              : 'Automation alert',
        };
        if (notificationBody.isNotEmpty) {
          payload['body'] = notificationBody;
        }
        if (notificationTarget == 'target_user_ids') {
          payload['target_user_ids'] = _parseCsvIds(notificationUsersCsv);
        }
        return payload;
      case AutomationActionType.createTask:
        return {
          'title': createTaskTitle.isNotEmpty
              ? createTaskTitle
              : 'Follow up on {task_title}',
          'description': createTaskDescription,
          'due_in_days': createTaskDueInDays,
          'status': createTaskStatus,
          'priority': createTaskPriority,
        };
      case AutomationActionType.updateField:
        return {
          'entity': updateFieldEntity,
          'field': updateFieldName.isNotEmpty ? updateFieldName : 'priority',
          'value': updateFieldValue.isNotEmpty ? updateFieldValue : 'high',
        };
      case AutomationActionType.addTag:
        return {'tag': addTag.isNotEmpty ? addTag : 'at_risk'};
      case AutomationActionType.applyTaskTemplate:
        return {'template_id': applyTemplateId};
    }
  }

  List<String> _parseCsvIds(String raw) {
    return raw
        .split(',')
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toSet()
        .toList();
  }

  String _csvFromDynamicList(dynamic value) {
    if (value is! List) return '';
    return value.map((e) => e.toString()).join(', ');
  }

  String _prettyJson(Map<String, dynamic> json) {
    const encoder = JsonEncoder.withIndent('  ');
    return encoder.convert(json);
  }

  Map<String, dynamic> _parseJsonMap(String raw, {required String field}) {
    final decoded = jsonDecode(raw);
    if (decoded is! Map) {
      throw FormatException('$field must be a JSON object.');
    }
    return Map<String, dynamic>.from(decoded);
  }

  Map<String, dynamic> _defaultPayloadForAction(
    AutomationActionType actionType,
  ) {
    switch (actionType) {
      case AutomationActionType.createNotification:
        return {
          'target': 'assigned_users',
          'title': 'Task needs attention: {task_title}',
          'body': 'Status changed from {from_status} to {to_status}',
        };
      case AutomationActionType.createTask:
        return {
          'title': 'Follow up on {task_title}',
          'description': 'Created by automation rule.',
          'due_in_days': 1,
          'status': 'not_started',
          'priority': 'medium',
        };
      case AutomationActionType.updateField:
        return {'entity': 'task', 'field': 'priority', 'value': 'high'};
      case AutomationActionType.addTag:
        return {'tag': 'at_risk'};
      case AutomationActionType.applyTaskTemplate:
        return {'template_id': ''};
    }
  }

  String _triggerLabel(AutomationTriggerType type) {
    switch (type) {
      case AutomationTriggerType.taskStatusChanged:
        return 'Task Status Changed';
      case AutomationTriggerType.taskAssigned:
        return 'Task Assigned';
      case AutomationTriggerType.taskDueOverdue:
        return 'Task Overdue';
      case AutomationTriggerType.invoiceStatusChanged:
        return 'Invoice Status Changed';
      case AutomationTriggerType.opportunityCreated:
        return 'Opportunity Created';
      case AutomationTriggerType.projectCreated:
        return 'Job Created';
      case AutomationTriggerType.documentSigned:
        return 'Document Signed';
      case AutomationTriggerType.timeEntryClockedOut:
        return 'Clocked Out';
    }
  }

  String _actionLabel(AutomationActionType type) {
    switch (type) {
      case AutomationActionType.createNotification:
        return 'Create Notification';
      case AutomationActionType.createTask:
        return 'Create Task';
      case AutomationActionType.updateField:
        return 'Update Field';
      case AutomationActionType.addTag:
        return 'Add Tag';
      case AutomationActionType.applyTaskTemplate:
        return 'Apply Task Template';
    }
  }

  String _executionSummary(AutomationExecution execution) {
    final count = execution.executedActions.length;
    switch (execution.status) {
      case AutomationExecutionStatus.success:
        return 'Executed $count action${count == 1 ? '' : 's'}';
      case AutomationExecutionStatus.failed:
        return execution.errorMessage ?? 'Execution failed';
      case AutomationExecutionStatus.skipped:
        return (execution.metadata['reason'] as String?) ?? 'Skipped';
    }
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = context.watch<AuthProvider>();
    // Mirrors the is_pm_or_admin RLS check on automation_rules: admins and
    // members with projects write access can manage automations.
    final canManageRules =
        authProvider.canManageUsers || authProvider.canEditProjects;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Automation Rules'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      floatingActionButton: canManageRules
          ? FloatingActionButton.extended(
              onPressed: _isSaving ? null : () => _showRuleDialog(),
              icon: const Icon(Icons.add),
              label: const Text('New Rule'),
            )
          : null,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _workspaceId == null
          ? const Center(child: Text('No active workspace selected.'))
          : RefreshIndicator(
              onRefresh: _loadData,
              child: ListView(
                padding: const EdgeInsets.all(AppSpacing.base),
                children: [
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.auto_awesome_outlined),
                      title: const Text('Automation Engine'),
                      subtitle: Text(
                        'Rules: ${_rules.length} • Enabled: ${_rules.where((r) => r.isEnabled).length}',
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (_rules.isEmpty)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(AppSpacing.base),
                        child: Text(
                          canManageRules
                              ? 'No rules yet. Create your first workflow automation.'
                              : 'No automation rules configured.',
                        ),
                      ),
                    )
                  else
                    ..._rules.map(
                      (rule) => Card(
                        child: ListTile(
                          title: Text(rule.name),
                          subtitle: Text(
                            '${_triggerLabel(rule.triggerType)} • ${rule.actions.length} action${rule.actions.length == 1 ? '' : 's'}',
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Switch(
                                value: rule.isEnabled,
                                onChanged: canManageRules
                                    ? (value) => _toggleRule(rule, value)
                                    : null,
                              ),
                              if (canManageRules)
                                PopupMenuButton<String>(
                                  onSelected: (value) {
                                    if (value == 'edit') {
                                      _showRuleDialog(rule: rule);
                                    } else if (value == 'delete') {
                                      _deleteRule(rule);
                                    }
                                  },
                                  itemBuilder: (context) => const [
                                    PopupMenuItem(
                                      value: 'edit',
                                      child: Text('Edit'),
                                    ),
                                    PopupMenuItem(
                                      value: 'delete',
                                      child: Text('Delete'),
                                    ),
                                  ],
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  const SizedBox(height: 20),
                  Text(
                    'Recent Executions',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  if (_executions.isEmpty)
                    const Card(
                      child: Padding(
                        padding: EdgeInsets.all(AppSpacing.base),
                        child: Text('No automation executions yet.'),
                      ),
                    )
                  else
                    ..._executions
                        .take(10)
                        .map(
                          (execution) => Card(
                            child: ListTile(
                              leading: Icon(
                                execution.status ==
                                        AutomationExecutionStatus.success
                                    ? Icons.check_circle_outline
                                    : execution.status ==
                                          AutomationExecutionStatus.failed
                                    ? Icons.error_outline
                                    : Icons.skip_next,
                                color:
                                    execution.status ==
                                        AutomationExecutionStatus.success
                                    ? AppColors.success
                                    : execution.status ==
                                          AutomationExecutionStatus.failed
                                    ? AppColors.error
                                    : AppColors.warning,
                              ),
                              title: Text(_triggerLabel(execution.triggerType)),
                              subtitle: Text(_executionSummary(execution)),
                              trailing: Text(
                                '${execution.createdAt.month.toString().padLeft(2, '0')}/${execution.createdAt.day.toString().padLeft(2, '0')} ${execution.createdAt.hour.toString().padLeft(2, '0')}:${execution.createdAt.minute.toString().padLeft(2, '0')}',
                              ),
                            ),
                          ),
                        ),
                ],
              ),
            ),
    );
  }
}
