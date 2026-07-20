-- Migration: Add settings_audit_events table for workspace/admin setting changes

CREATE TABLE IF NOT EXISTS settings_audit_events (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id UUID NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
  actor_user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  target_type TEXT NOT NULL,
  target_id TEXT NOT NULL,
  event_type TEXT NOT NULL,
  before_data JSONB,
  after_data JSONB,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_settings_audit_events_workspace_created_at
  ON settings_audit_events(workspace_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_settings_audit_events_actor_created_at
  ON settings_audit_events(actor_user_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_settings_audit_events_event_type
  ON settings_audit_events(event_type);

ALTER TABLE settings_audit_events ENABLE ROW LEVEL SECURITY;

-- Workspace members can read audit events for their workspace
DROP POLICY IF EXISTS settings_audit_events_select ON settings_audit_events;
CREATE POLICY settings_audit_events_select ON settings_audit_events
  FOR SELECT USING (is_workspace_member(workspace_id));

-- Workspace members can write events only as themselves
DROP POLICY IF EXISTS settings_audit_events_insert ON settings_audit_events;
CREATE POLICY settings_audit_events_insert ON settings_audit_events
  FOR INSERT WITH CHECK (
    is_workspace_member(workspace_id)
    AND actor_user_id = auth.uid()
  );

