-- =============================================================================
-- AIA G702 / G703 Payment Applications
--   * aia_payment_applications  — one row per submitted/draft pay app (G702)
--   * aia_pay_app_lines         — one row per G703 schedule-of-values line
-- All amounts stored as NUMERIC(15,2). Computed columns (total_completed,
-- percent_complete, balance_to_finish) are derived in Dart, not stored.
-- =============================================================================

CREATE TABLE IF NOT EXISTS aia_payment_applications (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  workspace_id UUID NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
  project_id UUID NOT NULL REFERENCES projects(id) ON DELETE CASCADE,

  application_number INT NOT NULL,
  period_from DATE,
  period_to DATE,
  date_issued DATE,
  contract_date DATE,
  contract_for TEXT,

  contractor_name TEXT,
  contractor_address TEXT,
  owner_name TEXT,
  owner_address TEXT,
  architect_name TEXT,
  architect_project_no TEXT,

  original_contract_sum NUMERIC(15,2) NOT NULL DEFAULT 0,
  net_change_by_change_orders NUMERIC(15,2) NOT NULL DEFAULT 0,
  retainage_pct_completed NUMERIC(5,2) NOT NULL DEFAULT 10,
  retainage_pct_stored NUMERIC(5,2) NOT NULL DEFAULT 10,

  status TEXT NOT NULL DEFAULT 'draft'
    CHECK (status IN ('draft', 'submitted', 'certified', 'paid')),
  certified_amount NUMERIC(15,2),
  certified_by TEXT,
  certified_at TIMESTAMPTZ,
  notes TEXT,

  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),

  CONSTRAINT aia_pay_app_unique_number UNIQUE (project_id, application_number)
);

CREATE INDEX IF NOT EXISTS idx_aia_pay_app_project ON aia_payment_applications(project_id);
CREATE INDEX IF NOT EXISTS idx_aia_pay_app_workspace ON aia_payment_applications(workspace_id);

CREATE TABLE IF NOT EXISTS aia_pay_app_lines (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  pay_application_id UUID NOT NULL REFERENCES aia_payment_applications(id) ON DELETE CASCADE,
  workspace_id UUID NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
  budget_item_id UUID REFERENCES budget_items(id) ON DELETE SET NULL,

  item_no TEXT,
  description TEXT NOT NULL DEFAULT '',
  scheduled_value NUMERIC(15,2) NOT NULL DEFAULT 0,
  work_completed_previous NUMERIC(15,2) NOT NULL DEFAULT 0,
  work_completed_this_period NUMERIC(15,2) NOT NULL DEFAULT 0,
  materials_stored NUMERIC(15,2) NOT NULL DEFAULT 0,
  retainage_amount NUMERIC(15,2),
  sort_order INT NOT NULL DEFAULT 0,

  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_aia_pay_app_lines_app ON aia_pay_app_lines(pay_application_id);
CREATE INDEX IF NOT EXISTS idx_aia_pay_app_lines_budget_item ON aia_pay_app_lines(budget_item_id);
CREATE INDEX IF NOT EXISTS idx_aia_pay_app_lines_workspace ON aia_pay_app_lines(workspace_id);

-- ── RLS ────────────────────────────────────────────────────────────────
ALTER TABLE aia_payment_applications ENABLE ROW LEVEL SECURITY;
ALTER TABLE aia_pay_app_lines        ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS aia_pay_app_select ON aia_payment_applications;
DROP POLICY IF EXISTS aia_pay_app_insert ON aia_payment_applications;
DROP POLICY IF EXISTS aia_pay_app_update ON aia_payment_applications;
DROP POLICY IF EXISTS aia_pay_app_delete ON aia_payment_applications;

CREATE POLICY aia_pay_app_select ON aia_payment_applications
  FOR SELECT USING (is_workspace_member(workspace_id));
CREATE POLICY aia_pay_app_insert ON aia_payment_applications
  FOR INSERT WITH CHECK (is_workspace_member(workspace_id));
CREATE POLICY aia_pay_app_update ON aia_payment_applications
  FOR UPDATE USING (is_workspace_member(workspace_id));
CREATE POLICY aia_pay_app_delete ON aia_payment_applications
  FOR DELETE USING (is_workspace_member(workspace_id));

DROP POLICY IF EXISTS aia_pay_app_lines_select ON aia_pay_app_lines;
DROP POLICY IF EXISTS aia_pay_app_lines_insert ON aia_pay_app_lines;
DROP POLICY IF EXISTS aia_pay_app_lines_update ON aia_pay_app_lines;
DROP POLICY IF EXISTS aia_pay_app_lines_delete ON aia_pay_app_lines;

CREATE POLICY aia_pay_app_lines_select ON aia_pay_app_lines
  FOR SELECT USING (is_workspace_member(workspace_id));
CREATE POLICY aia_pay_app_lines_insert ON aia_pay_app_lines
  FOR INSERT WITH CHECK (is_workspace_member(workspace_id));
CREATE POLICY aia_pay_app_lines_update ON aia_pay_app_lines
  FOR UPDATE USING (is_workspace_member(workspace_id));
CREATE POLICY aia_pay_app_lines_delete ON aia_pay_app_lines
  FOR DELETE USING (is_workspace_member(workspace_id));

-- ── updated_at triggers ────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION aia_pay_app_set_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql SET search_path = public, pg_temp AS $$
BEGIN NEW.updated_at = now(); RETURN NEW; END $$;

DROP TRIGGER IF EXISTS trg_aia_pay_app_updated ON aia_payment_applications;
CREATE TRIGGER trg_aia_pay_app_updated BEFORE UPDATE ON aia_payment_applications
  FOR EACH ROW EXECUTE FUNCTION aia_pay_app_set_updated_at();

DROP TRIGGER IF EXISTS trg_aia_pay_app_lines_updated ON aia_pay_app_lines;
CREATE TRIGGER trg_aia_pay_app_lines_updated BEFORE UPDATE ON aia_pay_app_lines
  FOR EACH ROW EXECUTE FUNCTION aia_pay_app_set_updated_at();
