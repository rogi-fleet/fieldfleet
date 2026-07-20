class AutomationParseException implements Exception {
  final String message;

  const AutomationParseException(this.message);

  @override
  String toString() => 'AutomationParseException: $message';
}

enum AutomationTriggerType {
  taskStatusChanged('task_status_changed'),
  taskAssigned('task_assigned'),
  taskDueOverdue('task_due_overdue'),
  invoiceStatusChanged('invoice_status_changed'),
  opportunityCreated('opportunity_created'),
  projectCreated('project_created'),
  documentSigned('document_signed'),
  timeEntryClockedOut('time_entry_clocked_out');

  final String dbValue;
  const AutomationTriggerType(this.dbValue);

  static AutomationTriggerType fromDbValue(String value) {
    for (final item in AutomationTriggerType.values) {
      if (item.dbValue == value) return item;
    }
    throw AutomationParseException('Invalid trigger type: $value');
  }
}

enum AutomationActionType {
  createNotification('create_notification'),
  createTask('create_task'),
  updateField('update_field'),
  addTag('add_tag'),
  applyTaskTemplate('apply_task_template');

  final String dbValue;
  const AutomationActionType(this.dbValue);

  static AutomationActionType fromDbValue(String value) {
    for (final item in AutomationActionType.values) {
      if (item.dbValue == value) return item;
    }
    throw AutomationParseException('Invalid action type: $value');
  }
}

enum AutomationExecutionStatus {
  success('success'),
  failed('failed'),
  skipped('skipped');

  final String dbValue;
  const AutomationExecutionStatus(this.dbValue);

  static AutomationExecutionStatus fromDbValue(String value) {
    for (final item in AutomationExecutionStatus.values) {
      if (item.dbValue == value) return item;
    }
    throw AutomationParseException('Invalid execution status: $value');
  }
}

class AutomationActionDraft {
  final AutomationActionType actionType;
  final Map<String, dynamic> payload;
  final int sortOrder;

  const AutomationActionDraft({
    required this.actionType,
    this.payload = const {},
    required this.sortOrder,
  });

  Map<String, dynamic> toInsertMap({
    required String ruleId,
    required String workspaceId,
  }) {
    return {
      'rule_id': ruleId,
      'workspace_id': workspaceId,
      'action_type': actionType.dbValue,
      'payload': payload,
      'sort_order': sortOrder,
    };
  }
}

class AutomationAction {
  final String id;
  final String ruleId;
  final String workspaceId;
  final AutomationActionType actionType;
  final Map<String, dynamic> payload;
  final int sortOrder;
  final DateTime createdAt;
  final DateTime updatedAt;

  const AutomationAction({
    required this.id,
    required this.ruleId,
    required this.workspaceId,
    required this.actionType,
    required this.payload,
    required this.sortOrder,
    required this.createdAt,
    required this.updatedAt,
  });

  factory AutomationAction.fromRow(Map<String, dynamic> row) {
    return AutomationAction(
      id: row['id'] as String,
      ruleId: row['rule_id'] as String,
      workspaceId: row['workspace_id'] as String,
      actionType: AutomationActionType.fromDbValue(
        row['action_type'] as String,
      ),
      payload: row['payload'] != null
          ? Map<String, dynamic>.from(row['payload'] as Map)
          : const {},
      sortOrder: row['sort_order'] as int? ?? 0,
      createdAt: DateTime.parse(row['created_at'] as String),
      updatedAt: DateTime.parse(row['updated_at'] as String),
    );
  }
}

class AutomationRule {
  final String id;
  final String workspaceId;
  final String name;
  final String? description;
  final AutomationTriggerType triggerType;
  final Map<String, dynamic> conditions;
  final bool isEnabled;
  final String createdBy;
  final String? updatedBy;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<AutomationAction> actions;

  const AutomationRule({
    required this.id,
    required this.workspaceId,
    required this.name,
    this.description,
    required this.triggerType,
    this.conditions = const {},
    required this.isEnabled,
    required this.createdBy,
    this.updatedBy,
    required this.createdAt,
    required this.updatedAt,
    this.actions = const [],
  });

  factory AutomationRule.fromRow(Map<String, dynamic> row) {
    final actionRows = row['automation_actions'];
    final parsedActions = actionRows is List
        ? actionRows
              .map(
                (item) =>
                    AutomationAction.fromRow(item as Map<String, dynamic>),
              )
              .toList()
        : const <AutomationAction>[];
    parsedActions.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

    return AutomationRule(
      id: row['id'] as String,
      workspaceId: row['workspace_id'] as String,
      name: (row['name'] as String? ?? '').trim(),
      description: row['description'] as String?,
      triggerType: AutomationTriggerType.fromDbValue(
        row['trigger_type'] as String,
      ),
      conditions: row['conditions'] != null
          ? Map<String, dynamic>.from(row['conditions'] as Map)
          : const {},
      isEnabled: row['is_enabled'] as bool? ?? true,
      createdBy: row['created_by'] as String,
      updatedBy: row['updated_by'] as String?,
      createdAt: DateTime.parse(row['created_at'] as String),
      updatedAt: DateTime.parse(row['updated_at'] as String),
      actions: parsedActions,
    );
  }
}

class AutomationExecution {
  final String id;
  final String workspaceId;
  final String? ruleId;
  final AutomationTriggerType triggerType;
  final String eventKey;
  final AutomationExecutionStatus status;
  final String? errorMessage;
  final Map<String, dynamic> metadata;
  final List<dynamic> executedActions;
  final DateTime createdAt;

  const AutomationExecution({
    required this.id,
    required this.workspaceId,
    this.ruleId,
    required this.triggerType,
    required this.eventKey,
    required this.status,
    this.errorMessage,
    this.metadata = const {},
    this.executedActions = const [],
    required this.createdAt,
  });

  factory AutomationExecution.fromRow(Map<String, dynamic> row) {
    return AutomationExecution(
      id: row['id'] as String,
      workspaceId: row['workspace_id'] as String,
      ruleId: row['rule_id'] as String?,
      triggerType: AutomationTriggerType.fromDbValue(
        row['trigger_type'] as String,
      ),
      eventKey: row['event_key'] as String,
      status: AutomationExecutionStatus.fromDbValue(row['status'] as String),
      errorMessage: row['error_message'] as String?,
      metadata: row['metadata'] != null
          ? Map<String, dynamic>.from(row['metadata'] as Map)
          : const {},
      executedActions: row['executed_actions'] is List
          ? List<dynamic>.from(row['executed_actions'] as List)
          : const [],
      createdAt: DateTime.parse(row['created_at'] as String),
    );
  }
}
