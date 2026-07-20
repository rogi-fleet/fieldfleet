-- RLS policies for additional tables
-- Continues from 002_row_level_security.sql

-- ============================================================================
-- VEHICLES RLS
-- ============================================================================

ALTER TABLE vehicles ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can view vehicles in their workspace" ON vehicles;
CREATE POLICY "Users can view vehicles in their workspace"
  ON vehicles FOR SELECT
  USING (workspace_id IN (
    SELECT workspace_id FROM workspace_members WHERE user_id = auth.uid()
  ));

DROP POLICY IF EXISTS "Admins and managers can insert vehicles" ON vehicles;
CREATE POLICY "Admins and managers can insert vehicles"
  ON vehicles FOR INSERT
  WITH CHECK (workspace_id IN (
    SELECT workspace_id FROM workspace_members
    WHERE user_id = auth.uid() AND role IN ('admin', 'project_manager')
  ));

DROP POLICY IF EXISTS "Admins and managers can update vehicles" ON vehicles;
CREATE POLICY "Admins and managers can update vehicles"
  ON vehicles FOR UPDATE
  USING (workspace_id IN (
    SELECT workspace_id FROM workspace_members
    WHERE user_id = auth.uid() AND role IN ('admin', 'project_manager')
  ));

DROP POLICY IF EXISTS "Admins can delete vehicles" ON vehicles;
CREATE POLICY "Admins can delete vehicles"
  ON vehicles FOR DELETE
  USING (workspace_id IN (
    SELECT workspace_id FROM workspace_members
    WHERE user_id = auth.uid() AND role = 'admin'
  ));

-- ============================================================================
-- FORMS RLS
-- ============================================================================

ALTER TABLE forms ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can view forms in their workspace" ON forms;
CREATE POLICY "Users can view forms in their workspace"
  ON forms FOR SELECT
  USING (workspace_id IN (
    SELECT workspace_id FROM workspace_members WHERE user_id = auth.uid()
  ));

-- Public forms can be viewed by anyone
DROP POLICY IF EXISTS "Anyone can view public forms" ON forms;
CREATE POLICY "Anyone can view public forms"
  ON forms FOR SELECT
  USING (is_public = TRUE);

DROP POLICY IF EXISTS "Admins and managers can insert forms" ON forms;
CREATE POLICY "Admins and managers can insert forms"
  ON forms FOR INSERT
  WITH CHECK (workspace_id IN (
    SELECT workspace_id FROM workspace_members
    WHERE user_id = auth.uid() AND role IN ('admin', 'project_manager')
  ));

DROP POLICY IF EXISTS "Admins and managers can update forms" ON forms;
CREATE POLICY "Admins and managers can update forms"
  ON forms FOR UPDATE
  USING (workspace_id IN (
    SELECT workspace_id FROM workspace_members
    WHERE user_id = auth.uid() AND role IN ('admin', 'project_manager')
  ));

DROP POLICY IF EXISTS "Admins can delete forms" ON forms;
CREATE POLICY "Admins can delete forms"
  ON forms FOR DELETE
  USING (workspace_id IN (
    SELECT workspace_id FROM workspace_members
    WHERE user_id = auth.uid() AND role = 'admin'
  ));

-- ============================================================================
-- FORM SUBMISSIONS RLS
-- ============================================================================

ALTER TABLE form_submissions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can view submissions in their workspace" ON form_submissions;
CREATE POLICY "Users can view submissions in their workspace"
  ON form_submissions FOR SELECT
  USING (workspace_id IN (
    SELECT workspace_id FROM workspace_members WHERE user_id = auth.uid()
  ));

-- Anyone can submit to public forms
DROP POLICY IF EXISTS "Anyone can submit to public forms" ON form_submissions;
CREATE POLICY "Anyone can submit to public forms"
  ON form_submissions FOR INSERT
  WITH CHECK (
    form_template_id IN (SELECT id FROM forms WHERE is_public = TRUE)
    OR workspace_id IN (
      SELECT workspace_id FROM workspace_members WHERE user_id = auth.uid()
    )
  );

DROP POLICY IF EXISTS "Admins can delete submissions" ON form_submissions;
CREATE POLICY "Admins can delete submissions"
  ON form_submissions FOR DELETE
  USING (workspace_id IN (
    SELECT workspace_id FROM workspace_members
    WHERE user_id = auth.uid() AND role = 'admin'
  ));

-- ============================================================================
-- WORKSPACE SUBSCRIPTIONS RLS
-- ============================================================================

ALTER TABLE workspace_subscriptions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can view their workspace subscription" ON workspace_subscriptions;
CREATE POLICY "Users can view their workspace subscription"
  ON workspace_subscriptions FOR SELECT
  USING (workspace_id IN (
    SELECT workspace_id FROM workspace_members WHERE user_id = auth.uid()
  ));

-- Only service role can modify subscriptions (via Edge Functions)
DROP POLICY IF EXISTS "Service role can manage subscriptions" ON workspace_subscriptions;
CREATE POLICY "Service role can manage subscriptions"
  ON workspace_subscriptions FOR ALL
  USING (auth.role() = 'service_role');

-- ============================================================================
-- ANALYTICS EVENTS RLS
-- ============================================================================

ALTER TABLE analytics_events ENABLE ROW LEVEL SECURITY;

-- Users can insert their own events
DROP POLICY IF EXISTS "Users can insert analytics events" ON analytics_events;
CREATE POLICY "Users can insert analytics events"
  ON analytics_events FOR INSERT
  WITH CHECK (user_id = auth.uid() OR user_id IS NULL);

-- Only admins can view analytics
DROP POLICY IF EXISTS "Admins can view analytics" ON analytics_events;
CREATE POLICY "Admins can view analytics"
  ON analytics_events FOR SELECT
  USING (
    workspace_id IN (
      SELECT workspace_id FROM workspace_members
      WHERE user_id = auth.uid() AND role = 'admin'
    )
    OR auth.role() = 'service_role'
  );

-- ============================================================================
-- MAINTENANCE LOGS RLS (updated for entity pattern)
-- ============================================================================

-- Drop existing policies if any
DROP POLICY IF EXISTS "Users can view maintenance logs in their workspace" ON maintenance_logs;
DROP POLICY IF EXISTS "Admins and managers can insert maintenance logs" ON maintenance_logs;
DROP POLICY IF EXISTS "Admins and managers can update maintenance logs" ON maintenance_logs;
DROP POLICY IF EXISTS "Admins can delete maintenance logs" ON maintenance_logs;

CREATE POLICY "Users can view maintenance logs in their workspace"
  ON maintenance_logs FOR SELECT
  USING (workspace_id IN (
    SELECT workspace_id FROM workspace_members WHERE user_id = auth.uid()
  ));

CREATE POLICY "Admins and managers can insert maintenance logs"
  ON maintenance_logs FOR INSERT
  WITH CHECK (workspace_id IN (
    SELECT workspace_id FROM workspace_members
    WHERE user_id = auth.uid() AND role IN ('admin', 'project_manager')
  ));

CREATE POLICY "Admins and managers can update maintenance logs"
  ON maintenance_logs FOR UPDATE
  USING (workspace_id IN (
    SELECT workspace_id FROM workspace_members
    WHERE user_id = auth.uid() AND role IN ('admin', 'project_manager')
  ));

CREATE POLICY "Admins can delete maintenance logs"
  ON maintenance_logs FOR DELETE
  USING (workspace_id IN (
    SELECT workspace_id FROM workspace_members
    WHERE user_id = auth.uid() AND role = 'admin'
  ));

-- ============================================================================
-- CATALOG ITEMS RLS (ensure exists)
-- ============================================================================

ALTER TABLE catalog_items ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can view catalog items in their workspace" ON catalog_items;
DROP POLICY IF EXISTS "Admins and managers can insert catalog items" ON catalog_items;
DROP POLICY IF EXISTS "Admins and managers can update catalog items" ON catalog_items;
DROP POLICY IF EXISTS "Admins can delete catalog items" ON catalog_items;

CREATE POLICY "Users can view catalog items in their workspace"
  ON catalog_items FOR SELECT
  USING (workspace_id IN (
    SELECT workspace_id FROM workspace_members WHERE user_id = auth.uid()
  ));

CREATE POLICY "Admins and managers can insert catalog items"
  ON catalog_items FOR INSERT
  WITH CHECK (workspace_id IN (
    SELECT workspace_id FROM workspace_members
    WHERE user_id = auth.uid() AND role IN ('admin', 'project_manager')
  ));

CREATE POLICY "Admins and managers can update catalog items"
  ON catalog_items FOR UPDATE
  USING (workspace_id IN (
    SELECT workspace_id FROM workspace_members
    WHERE user_id = auth.uid() AND role IN ('admin', 'project_manager')
  ));

CREATE POLICY "Admins can delete catalog items"
  ON catalog_items FOR DELETE
  USING (workspace_id IN (
    SELECT workspace_id FROM workspace_members
    WHERE user_id = auth.uid() AND role = 'admin'
  ));

-- ============================================================================
-- CONSTRUCTION PLANS / PLANS VIEW RLS
-- ============================================================================

ALTER TABLE construction_plans ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can view plans in their workspace" ON construction_plans;
DROP POLICY IF EXISTS "Admins and managers can insert plans" ON construction_plans;
DROP POLICY IF EXISTS "Admins and managers can update plans" ON construction_plans;
DROP POLICY IF EXISTS "Admins can delete plans" ON construction_plans;

CREATE POLICY "Users can view plans in their workspace"
  ON construction_plans FOR SELECT
  USING (workspace_id IN (
    SELECT workspace_id FROM workspace_members WHERE user_id = auth.uid()
  ));

CREATE POLICY "Admins and managers can insert plans"
  ON construction_plans FOR INSERT
  WITH CHECK (workspace_id IN (
    SELECT workspace_id FROM workspace_members
    WHERE user_id = auth.uid() AND role IN ('admin', 'project_manager')
  ));

CREATE POLICY "Admins and managers can update plans"
  ON construction_plans FOR UPDATE
  USING (workspace_id IN (
    SELECT workspace_id FROM workspace_members
    WHERE user_id = auth.uid() AND role IN ('admin', 'project_manager')
  ));

CREATE POLICY "Admins can delete plans"
  ON construction_plans FOR DELETE
  USING (workspace_id IN (
    SELECT workspace_id FROM workspace_members
    WHERE user_id = auth.uid() AND role = 'admin'
  ));
