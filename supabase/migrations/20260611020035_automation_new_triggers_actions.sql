-- A2: extend the automations engine to JobTread-parity trigger/action coverage.
--
-- New triggers: opportunity_created (auto to-dos on new lead), project_created
-- (preload a schedule template on job creation), document_signed, and
-- time_entry_clocked_out (e.g. remind the crew to file a daily log).
-- New action: apply_task_template — instantiates a task-group template
-- (snapshot tree incl. dependencies/offsets) into the event's project.

ALTER TABLE automation_rules
  DROP CONSTRAINT IF EXISTS automation_rules_trigger_type_check;
ALTER TABLE automation_rules
  ADD CONSTRAINT automation_rules_trigger_type_check CHECK (
    trigger_type IN (
      'task_status_changed',
      'task_assigned',
      'task_due_overdue',
      'invoice_status_changed',
      'opportunity_created',
      'project_created',
      'document_signed',
      'time_entry_clocked_out'
    )
  );

ALTER TABLE automation_actions
  DROP CONSTRAINT IF EXISTS automation_actions_action_type_check;
ALTER TABLE automation_actions
  ADD CONSTRAINT automation_actions_action_type_check CHECK (
    action_type IN (
      'create_notification',
      'create_task',
      'update_field',
      'add_tag',
      'apply_task_template'
    )
  );
