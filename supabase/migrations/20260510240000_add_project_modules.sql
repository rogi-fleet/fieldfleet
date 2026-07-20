-- =============================================================================
-- Project modules: Warranties, Daily Logs, Inspections, Punch Lists
-- =============================================================================
-- All workspace + project scoped, RLS via is_workspace_member, realtime-enabled.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- 1. Warranties
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS project_warranties (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id      UUID NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
  project_id        UUID NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
  title             TEXT NOT NULL,
  warranty_type     TEXT NOT NULL DEFAULT 'workmanship',
    -- labor|materials|workmanship|equipment|extended|manufacturer|other
  provider_name     TEXT,
  provider_vendor_id UUID,                     -- soft link to vendors.id
  beneficiary       TEXT,                      -- client/company covered
  description       TEXT,
  terms             TEXT,
  coverage_amount   NUMERIC(14,2),
  currency          TEXT NOT NULL DEFAULT 'USD',
  starts_on         DATE,
  ends_on           DATE,
  reference_no      TEXT,
  document_url      TEXT,
  status            TEXT NOT NULL DEFAULT 'active',
    -- active|expiring_soon|expired|claimed|void
  claim_count       INT NOT NULL DEFAULT 0,
  notes             TEXT,
  created_by        UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at        TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_proj_warranties_proj   ON project_warranties(project_id);
CREATE INDEX IF NOT EXISTS idx_proj_warranties_ws     ON project_warranties(workspace_id);
CREATE INDEX IF NOT EXISTS idx_proj_warranties_status ON project_warranties(status);
CREATE INDEX IF NOT EXISTS idx_proj_warranties_ends   ON project_warranties(ends_on);

CREATE TABLE IF NOT EXISTS project_warranty_claims (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id  UUID NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
  warranty_id   UUID NOT NULL REFERENCES project_warranties(id) ON DELETE CASCADE,
  claim_date    DATE NOT NULL DEFAULT CURRENT_DATE,
  description   TEXT NOT NULL,
  resolution    TEXT,
  status        TEXT NOT NULL DEFAULT 'open',  -- open|in_progress|resolved|denied
  resolved_at   DATE,
  cost          NUMERIC(14,2),
  created_by    UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_warranty_claims_warranty ON project_warranty_claims(warranty_id);

-- ---------------------------------------------------------------------------
-- 2. Daily logs
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS project_daily_logs (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id        UUID NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
  project_id          UUID NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
  log_date            DATE NOT NULL DEFAULT CURRENT_DATE,
  weather_conditions  TEXT,                    -- e.g. Sunny, Rain, Snow
  temperature_high    NUMERIC(5,1),
  temperature_low     NUMERIC(5,1),
  wind                TEXT,
  crew_count          INT NOT NULL DEFAULT 0,
  hours_worked        NUMERIC(8,2),
  work_performed      TEXT,
  materials_delivered TEXT,
  equipment_on_site   TEXT,
  subcontractors      TEXT,
  visitors            TEXT,
  delays              TEXT,
  safety_notes        TEXT,
  incidents           TEXT,
  notes               TEXT,
  photos              JSONB NOT NULL DEFAULT '[]'::jsonb,  -- [{url, caption}]
  status              TEXT NOT NULL DEFAULT 'draft', -- draft|submitted|approved
  submitted_by        UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  submitted_at        TIMESTAMPTZ,
  approved_by         UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  approved_at         TIMESTAMPTZ,
  created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
  -- Note: multiple logs per project per day are allowed (e.g. different shifts /
  -- crews). Add a UNIQUE(project_id, log_date) here if your team requires
  -- exactly one log per day.
);
CREATE INDEX IF NOT EXISTS idx_daily_logs_proj  ON project_daily_logs(project_id);
CREATE INDEX IF NOT EXISTS idx_daily_logs_date  ON project_daily_logs(log_date);
CREATE INDEX IF NOT EXISTS idx_daily_logs_ws    ON project_daily_logs(workspace_id);

-- ---------------------------------------------------------------------------
-- 3. Inspections (header + checklist items)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS project_inspections (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id        UUID NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
  project_id          UUID NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
  name                TEXT NOT NULL,
  inspection_type     TEXT NOT NULL DEFAULT 'quality',
    -- pre_construction|progress|punch|final|safety|quality|code|warranty|other
  location            TEXT,
  scheduled_for       TIMESTAMPTZ,
  performed_at        TIMESTAMPTZ,
  performed_by        UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  inspector_name      TEXT,
  inspector_company   TEXT,
  status              TEXT NOT NULL DEFAULT 'scheduled',
    -- scheduled|in_progress|passed|failed|requires_followup|cancelled
  pass_count          INT NOT NULL DEFAULT 0,
  fail_count          INT NOT NULL DEFAULT 0,
  total_items         INT NOT NULL DEFAULT 0,
  score               NUMERIC(5,2),            -- 0-100 (computed from items)
  notes               TEXT,
  signature_url       TEXT,
  report_url          TEXT,
  created_by          UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_inspections_proj   ON project_inspections(project_id);
CREATE INDEX IF NOT EXISTS idx_inspections_ws     ON project_inspections(workspace_id);
CREATE INDEX IF NOT EXISTS idx_inspections_status ON project_inspections(status);

CREATE TABLE IF NOT EXISTS project_inspection_items (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id  UUID NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
  inspection_id UUID NOT NULL REFERENCES project_inspections(id) ON DELETE CASCADE,
  category      TEXT,                         -- e.g. Electrical, Plumbing
  label         TEXT NOT NULL,                -- the question / item
  description   TEXT,
  result        TEXT NOT NULL DEFAULT 'pending', -- pass|fail|na|pending
  notes         TEXT,
  photo_url     TEXT,
  sort_order    INT NOT NULL DEFAULT 0,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_inspection_items_insp ON project_inspection_items(inspection_id);

-- Trigger: keep inspection rollups in sync as items change
CREATE OR REPLACE FUNCTION project_inspection_recalc()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
  v_insp UUID := COALESCE(NEW.inspection_id, OLD.inspection_id);
  v_total INT;
  v_pass  INT;
  v_fail  INT;
  v_na    INT;
  v_done  INT;
BEGIN
  SELECT COUNT(*),
         COUNT(*) FILTER (WHERE result = 'pass'),
         COUNT(*) FILTER (WHERE result = 'fail'),
         COUNT(*) FILTER (WHERE result = 'na')
    INTO v_total, v_pass, v_fail, v_na
    FROM project_inspection_items
    WHERE inspection_id = v_insp;
  v_done := v_pass + v_fail + v_na;
  UPDATE project_inspections
    SET total_items = v_total,
        pass_count  = v_pass,
        fail_count  = v_fail,
        score       = CASE WHEN (v_pass + v_fail) = 0 THEN NULL
                           ELSE ROUND((v_pass::numeric * 100) / (v_pass + v_fail), 2) END,
        updated_at  = NOW()
    WHERE id = v_insp;
  RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS trg_inspection_items_recalc ON project_inspection_items;
CREATE TRIGGER trg_inspection_items_recalc
  AFTER INSERT OR UPDATE OR DELETE ON project_inspection_items
  FOR EACH ROW EXECUTE FUNCTION project_inspection_recalc();

-- ---------------------------------------------------------------------------
-- 4. Punch lists (header + items)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS project_punch_lists (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id  UUID NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
  project_id    UUID NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
  name          TEXT NOT NULL,
  description   TEXT,
  location      TEXT,
  status        TEXT NOT NULL DEFAULT 'open',
    -- open|in_progress|ready_review|completed|closed
  due_date      DATE,
  open_count       INT NOT NULL DEFAULT 0,
  completed_count  INT NOT NULL DEFAULT 0,
  total_items      INT NOT NULL DEFAULT 0,
  created_by    UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_punch_lists_proj   ON project_punch_lists(project_id);
CREATE INDEX IF NOT EXISTS idx_punch_lists_ws     ON project_punch_lists(workspace_id);
CREATE INDEX IF NOT EXISTS idx_punch_lists_status ON project_punch_lists(status);

CREATE TABLE IF NOT EXISTS project_punch_list_items (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id    UUID NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
  punch_list_id   UUID NOT NULL REFERENCES project_punch_lists(id) ON DELETE CASCADE,
  title           TEXT NOT NULL,
  description     TEXT,
  location_detail TEXT,                       -- room / floor / area
  trade           TEXT,                       -- e.g. Electrical, Drywall
  priority        TEXT NOT NULL DEFAULT 'medium', -- low|medium|high|critical
  assignee_id     UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  assignee_name   TEXT,                       -- snapshot for vendors w/o auth user
  vendor_id       UUID,                       -- soft link
  status          TEXT NOT NULL DEFAULT 'open',
    -- open|in_progress|ready_review|completed|verified|wont_fix
  photo_url       TEXT,
  notes           TEXT,
  due_date        DATE,
  completed_at    TIMESTAMPTZ,
  completed_by    UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  verified_at     TIMESTAMPTZ,
  verified_by     UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  sort_order      INT NOT NULL DEFAULT 0,
  created_by      UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_punch_items_list   ON project_punch_list_items(punch_list_id);
CREATE INDEX IF NOT EXISTS idx_punch_items_status ON project_punch_list_items(status);
CREATE INDEX IF NOT EXISTS idx_punch_items_assignee ON project_punch_list_items(assignee_id);

-- Trigger: keep punch list rollups in sync as items change
CREATE OR REPLACE FUNCTION project_punch_list_recalc()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
  v_list UUID := COALESCE(NEW.punch_list_id, OLD.punch_list_id);
  v_total INT;
  v_open  INT;
  v_done  INT;
BEGIN
  SELECT COUNT(*),
         COUNT(*) FILTER (WHERE status IN ('open','in_progress','ready_review')),
         COUNT(*) FILTER (WHERE status IN ('completed','verified','wont_fix'))
    INTO v_total, v_open, v_done
    FROM project_punch_list_items
    WHERE punch_list_id = v_list;
  UPDATE project_punch_lists
    SET total_items     = v_total,
        open_count      = v_open,
        completed_count = v_done,
        updated_at      = NOW()
    WHERE id = v_list;
  RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS trg_punch_items_recalc ON project_punch_list_items;
CREATE TRIGGER trg_punch_items_recalc
  AFTER INSERT OR UPDATE OR DELETE ON project_punch_list_items
  FOR EACH ROW EXECUTE FUNCTION project_punch_list_recalc();

-- Trigger: warranty claim_count rollup
CREATE OR REPLACE FUNCTION project_warranty_claim_recalc()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
  v_w UUID := COALESCE(NEW.warranty_id, OLD.warranty_id);
BEGIN
  UPDATE project_warranties
    SET claim_count = (SELECT COUNT(*) FROM project_warranty_claims WHERE warranty_id = v_w),
        updated_at  = NOW()
    WHERE id = v_w;
  RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS trg_warranty_claims_recalc ON project_warranty_claims;
CREATE TRIGGER trg_warranty_claims_recalc
  AFTER INSERT OR UPDATE OR DELETE ON project_warranty_claims
  FOR EACH ROW EXECUTE FUNCTION project_warranty_claim_recalc();

-- ---------------------------------------------------------------------------
-- 5. Workspace consistency: child rows must share workspace with parent
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION project_modules_assert_ws()
RETURNS TRIGGER
LANGUAGE plpgsql AS $$
DECLARE
  parent_table TEXT := TG_ARGV[0];
  parent_col TEXT := TG_ARGV[1];
  v_parent_id UUID;
  v_parent_ws UUID;
BEGIN
  IF TG_NARGS <> 2 THEN
    RAISE EXCEPTION 'project_modules_assert_ws requires parent table and parent column trigger args';
  END IF;

  EXECUTE format('SELECT ($1).%I', parent_col) INTO v_parent_id USING NEW;
  IF v_parent_id IS NULL THEN RETURN NEW; END IF;
  EXECUTE format('SELECT workspace_id FROM %I WHERE id = $1', parent_table)
    INTO v_parent_ws USING v_parent_id;
  IF v_parent_ws IS NOT NULL AND v_parent_ws <> NEW.workspace_id THEN
    RAISE EXCEPTION 'workspace mismatch on %.%: parent=%, child=%',
      TG_TABLE_NAME, parent_col, v_parent_ws, NEW.workspace_id
      USING ERRCODE = '23514';
  END IF;
  RETURN NEW;
END;
$$;

DO $$
BEGIN
  -- Each child must match its project's workspace.
  EXECUTE 'DROP TRIGGER IF EXISTS trg_pwarranties_ws ON project_warranties';
  EXECUTE 'CREATE TRIGGER trg_pwarranties_ws BEFORE INSERT OR UPDATE ON project_warranties '
       || 'FOR EACH ROW EXECUTE FUNCTION project_modules_assert_ws(''projects'', ''project_id'')';

  EXECUTE 'DROP TRIGGER IF EXISTS trg_pwclaims_ws ON project_warranty_claims';
  EXECUTE 'CREATE TRIGGER trg_pwclaims_ws BEFORE INSERT OR UPDATE ON project_warranty_claims '
       || 'FOR EACH ROW EXECUTE FUNCTION project_modules_assert_ws(''project_warranties'', ''warranty_id'')';

  EXECUTE 'DROP TRIGGER IF EXISTS trg_pdaily_ws ON project_daily_logs';
  EXECUTE 'CREATE TRIGGER trg_pdaily_ws BEFORE INSERT OR UPDATE ON project_daily_logs '
       || 'FOR EACH ROW EXECUTE FUNCTION project_modules_assert_ws(''projects'', ''project_id'')';

  EXECUTE 'DROP TRIGGER IF EXISTS trg_pinsp_ws ON project_inspections';
  EXECUTE 'CREATE TRIGGER trg_pinsp_ws BEFORE INSERT OR UPDATE ON project_inspections '
       || 'FOR EACH ROW EXECUTE FUNCTION project_modules_assert_ws(''projects'', ''project_id'')';

  EXECUTE 'DROP TRIGGER IF EXISTS trg_pinspitems_ws ON project_inspection_items';
  EXECUTE 'CREATE TRIGGER trg_pinspitems_ws BEFORE INSERT OR UPDATE ON project_inspection_items '
       || 'FOR EACH ROW EXECUTE FUNCTION project_modules_assert_ws(''project_inspections'', ''inspection_id'')';

  EXECUTE 'DROP TRIGGER IF EXISTS trg_ppunch_ws ON project_punch_lists';
  EXECUTE 'CREATE TRIGGER trg_ppunch_ws BEFORE INSERT OR UPDATE ON project_punch_lists '
       || 'FOR EACH ROW EXECUTE FUNCTION project_modules_assert_ws(''projects'', ''project_id'')';

  EXECUTE 'DROP TRIGGER IF EXISTS trg_ppunchitems_ws ON project_punch_list_items';
  EXECUTE 'CREATE TRIGGER trg_ppunchitems_ws BEFORE INSERT OR UPDATE ON project_punch_list_items '
       || 'FOR EACH ROW EXECUTE FUNCTION project_modules_assert_ws(''project_punch_lists'', ''punch_list_id'')';
END $$;

-- ---------------------------------------------------------------------------
-- 6. RLS + realtime — workspace-member access
-- ---------------------------------------------------------------------------
DO $$
DECLARE t TEXT;
BEGIN
  FOREACH t IN ARRAY ARRAY[
    'project_warranties','project_warranty_claims',
    'project_daily_logs',
    'project_inspections','project_inspection_items',
    'project_punch_lists','project_punch_list_items'
  ] LOOP
    EXECUTE format('ALTER TABLE %I ENABLE ROW LEVEL SECURITY;', t);
    EXECUTE format('DROP POLICY IF EXISTS %1$s_select ON %1$s;', t);
    EXECUTE format('CREATE POLICY %1$s_select ON %1$s FOR SELECT USING (is_workspace_member(workspace_id));', t);
    EXECUTE format('DROP POLICY IF EXISTS %1$s_insert ON %1$s;', t);
    EXECUTE format('CREATE POLICY %1$s_insert ON %1$s FOR INSERT WITH CHECK (is_workspace_member(workspace_id));', t);
    EXECUTE format('DROP POLICY IF EXISTS %1$s_update ON %1$s;', t);
    EXECUTE format('CREATE POLICY %1$s_update ON %1$s FOR UPDATE USING (is_workspace_member(workspace_id));', t);
    EXECUTE format('DROP POLICY IF EXISTS %1$s_delete ON %1$s;', t);
    EXECUTE format('CREATE POLICY %1$s_delete ON %1$s FOR DELETE USING (is_workspace_member(workspace_id));', t);
    BEGIN
      EXECUTE format('ALTER PUBLICATION supabase_realtime ADD TABLE %I;', t);
    EXCEPTION WHEN duplicate_object THEN NULL;
    END;
  END LOOP;
END $$;
