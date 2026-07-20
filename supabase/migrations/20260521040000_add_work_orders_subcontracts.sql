-- =============================================================================
-- P0-2: Operational Work Orders + Subcontracts (First-Class Domain)
--
-- Adds operational records for managing field work and vendor subcontracts as
-- live workflows (not just template-generated documents).
--
--   work_orders            — internal directive: who, what, when, where
--   work_order_items       — line items (link to budget_items / tasks)
--   work_order_signatures  — multi-party signatures (contractor / client)
--   work_order_history     — append-only audit trail
--
--   subcontracts           — contract with a vendor for scoped work
--   subcontract_items      — line items (link to budget_items)
--   subcontract_signatures — multi-party signatures (vendor / contractor / client)
--   subcontract_history    — append-only audit trail
--
-- Multi-tenant: every row carries workspace_id with both RLS and BEFORE INSERT
-- triggers that reject any row whose workspace_id is inconsistent with its
-- parent project / parent record (same hardening pattern as selections).
-- =============================================================================

-- ────────────────────────── WORK ORDERS ─────────────────────────────────────

CREATE TABLE IF NOT EXISTS work_orders (
  id                   UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  workspace_id         UUID NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
  project_id           UUID NOT NULL REFERENCES projects(id)   ON DELETE CASCADE,

  number               TEXT NOT NULL,
  title                TEXT NOT NULL,
  description          TEXT,
  scope_of_work        TEXT,

  status               TEXT NOT NULL DEFAULT 'draft'
    CHECK (status IN (
      'draft',
      'issued',
      'in_progress',
      'on_hold',
      'completed',
      'cancelled'
    )),
  priority             TEXT NOT NULL DEFAULT 'normal'
    CHECK (priority IN ('low', 'normal', 'high', 'urgent')),

  assigned_to          UUID REFERENCES users(id),
  vendor_id            UUID REFERENCES vendors(id),
  location             TEXT,

  scheduled_start      TIMESTAMPTZ,
  scheduled_end        TIMESTAMPTZ,
  started_at           TIMESTAMPTZ,
  completed_at         TIMESTAMPTZ,
  cancelled_at         TIMESTAMPTZ,

  estimated_hours      NUMERIC(10,2),
  actual_hours         NUMERIC(10,2),
  total_amount         NUMERIC(15,2) NOT NULL DEFAULT 0,

  internal_notes       TEXT,
  client_notes         TEXT,

  created_by           UUID REFERENCES users(id),
  issued_by            UUID REFERENCES users(id),
  completed_by         UUID REFERENCES users(id),

  created_at           TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at           TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_work_orders_project   ON work_orders(project_id);
CREATE INDEX IF NOT EXISTS idx_work_orders_workspace ON work_orders(workspace_id);
CREATE INDEX IF NOT EXISTS idx_work_orders_status    ON work_orders(project_id, status);
CREATE INDEX IF NOT EXISTS idx_work_orders_vendor    ON work_orders(vendor_id);
CREATE INDEX IF NOT EXISTS idx_work_orders_assignee  ON work_orders(assigned_to);

CREATE TABLE IF NOT EXISTS work_order_items (
  id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  work_order_id   UUID NOT NULL REFERENCES work_orders(id) ON DELETE CASCADE,
  workspace_id    UUID NOT NULL REFERENCES workspaces(id)  ON DELETE CASCADE,

  description     TEXT NOT NULL,
  quantity        NUMERIC(15,2) NOT NULL DEFAULT 1,
  unit            TEXT,
  unit_cost       NUMERIC(15,2) NOT NULL DEFAULT 0,

  budget_item_id  UUID REFERENCES budget_items(id) ON DELETE SET NULL,
  task_id         UUID REFERENCES tasks(id)        ON DELETE SET NULL,

  sort_order      INT NOT NULL DEFAULT 0,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_work_order_items_wo     ON work_order_items(work_order_id);
CREATE INDEX IF NOT EXISTS idx_work_order_items_budget ON work_order_items(budget_item_id);
CREATE INDEX IF NOT EXISTS idx_work_order_items_task   ON work_order_items(task_id);

CREATE TABLE IF NOT EXISTS work_order_signatures (
  id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  work_order_id   UUID NOT NULL REFERENCES work_orders(id) ON DELETE CASCADE,
  workspace_id    UUID NOT NULL REFERENCES workspaces(id)  ON DELETE CASCADE,

  role            TEXT NOT NULL
    CHECK (role IN ('contractor', 'client', 'vendor', 'witness')),
  signer_name     TEXT NOT NULL,
  signer_email    TEXT,
  signature_url   TEXT NOT NULL,
  signed_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
  ip_address      TEXT,

  created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_work_order_sigs_wo ON work_order_signatures(work_order_id);

CREATE TABLE IF NOT EXISTS work_order_history (
  id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  work_order_id   UUID NOT NULL REFERENCES work_orders(id) ON DELETE CASCADE,
  workspace_id    UUID NOT NULL REFERENCES workspaces(id)  ON DELETE CASCADE,

  event_type      TEXT NOT NULL,           -- created / status_changed / signed / item_added / note ...
  from_status     TEXT,
  to_status       TEXT,
  message         TEXT,
  metadata        JSONB NOT NULL DEFAULT '{}'::jsonb,
  actor_id        UUID REFERENCES users(id),
  actor_name      TEXT,

  created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_work_order_history_wo ON work_order_history(work_order_id, created_at DESC);

-- ────────────────────────── SUBCONTRACTS ────────────────────────────────────

CREATE TABLE IF NOT EXISTS subcontracts (
  id                   UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  workspace_id         UUID NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
  project_id           UUID NOT NULL REFERENCES projects(id)   ON DELETE CASCADE,
  vendor_id            UUID NOT NULL REFERENCES vendors(id),

  number               TEXT NOT NULL,
  title                TEXT NOT NULL,
  description          TEXT,
  scope_of_work        TEXT,

  status               TEXT NOT NULL DEFAULT 'draft'
    CHECK (status IN (
      'draft',
      'sent',
      'signed',
      'active',
      'completed',
      'terminated',
      'cancelled'
    )),

  contract_amount      NUMERIC(15,2) NOT NULL DEFAULT 0,
  retainage_percent    NUMERIC(5,2)  NOT NULL DEFAULT 0,
  paid_to_date         NUMERIC(15,2) NOT NULL DEFAULT 0,

  start_date           DATE,
  end_date             DATE,
  sent_at              TIMESTAMPTZ,
  signed_at            TIMESTAMPTZ,
  completed_at         TIMESTAMPTZ,
  terminated_at        TIMESTAMPTZ,

  payment_terms        TEXT,
  insurance_required   BOOLEAN NOT NULL DEFAULT TRUE,
  insurance_verified   BOOLEAN NOT NULL DEFAULT FALSE,
  insurance_verified_at TIMESTAMPTZ,

  internal_notes       TEXT,

  created_by           UUID REFERENCES users(id),
  created_at           TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at           TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_subcontracts_project   ON subcontracts(project_id);
CREATE INDEX IF NOT EXISTS idx_subcontracts_workspace ON subcontracts(workspace_id);
CREATE INDEX IF NOT EXISTS idx_subcontracts_vendor    ON subcontracts(vendor_id);
CREATE INDEX IF NOT EXISTS idx_subcontracts_status    ON subcontracts(project_id, status);

CREATE TABLE IF NOT EXISTS subcontract_items (
  id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  subcontract_id  UUID NOT NULL REFERENCES subcontracts(id) ON DELETE CASCADE,
  workspace_id    UUID NOT NULL REFERENCES workspaces(id)   ON DELETE CASCADE,

  description     TEXT NOT NULL,
  quantity        NUMERIC(15,2) NOT NULL DEFAULT 1,
  unit            TEXT,
  unit_cost       NUMERIC(15,2) NOT NULL DEFAULT 0,

  budget_item_id  UUID REFERENCES budget_items(id) ON DELETE SET NULL,

  sort_order      INT NOT NULL DEFAULT 0,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_subcontract_items_sc     ON subcontract_items(subcontract_id);
CREATE INDEX IF NOT EXISTS idx_subcontract_items_budget ON subcontract_items(budget_item_id);

CREATE TABLE IF NOT EXISTS subcontract_signatures (
  id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  subcontract_id  UUID NOT NULL REFERENCES subcontracts(id) ON DELETE CASCADE,
  workspace_id    UUID NOT NULL REFERENCES workspaces(id)   ON DELETE CASCADE,

  role            TEXT NOT NULL
    CHECK (role IN ('contractor', 'vendor', 'client', 'witness')),
  signer_name     TEXT NOT NULL,
  signer_email    TEXT,
  signature_url   TEXT NOT NULL,
  signed_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
  ip_address      TEXT,

  created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_subcontract_sigs_sc ON subcontract_signatures(subcontract_id);

CREATE TABLE IF NOT EXISTS subcontract_history (
  id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  subcontract_id  UUID NOT NULL REFERENCES subcontracts(id) ON DELETE CASCADE,
  workspace_id    UUID NOT NULL REFERENCES workspaces(id)   ON DELETE CASCADE,

  event_type      TEXT NOT NULL,
  from_status     TEXT,
  to_status       TEXT,
  message         TEXT,
  metadata        JSONB NOT NULL DEFAULT '{}'::jsonb,
  actor_id        UUID REFERENCES users(id),
  actor_name      TEXT,

  created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_subcontract_history_sc
  ON subcontract_history(subcontract_id, created_at DESC);

-- ─────────────────── updated_at triggers ────────────────────────────────────

DROP TRIGGER IF EXISTS trg_work_orders_updated_at ON work_orders;
CREATE TRIGGER trg_work_orders_updated_at
  BEFORE UPDATE ON work_orders
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

DROP TRIGGER IF EXISTS trg_work_order_items_updated_at ON work_order_items;
CREATE TRIGGER trg_work_order_items_updated_at
  BEFORE UPDATE ON work_order_items
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

DROP TRIGGER IF EXISTS trg_subcontracts_updated_at ON subcontracts;
CREATE TRIGGER trg_subcontracts_updated_at
  BEFORE UPDATE ON subcontracts
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

DROP TRIGGER IF EXISTS trg_subcontract_items_updated_at ON subcontract_items;
CREATE TRIGGER trg_subcontract_items_updated_at
  BEFORE UPDATE ON subcontract_items
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- ─────────────────── tenant-consistency triggers ────────────────────────────

CREATE OR REPLACE FUNCTION public.work_orders_enforce_tenant()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE proj_ws UUID;
BEGIN
  SELECT workspace_id INTO proj_ws FROM projects WHERE id = NEW.project_id;
  IF proj_ws IS NULL THEN
    RAISE EXCEPTION 'Project % does not exist', NEW.project_id;
  END IF;
  IF NEW.workspace_id IS DISTINCT FROM proj_ws THEN
    RAISE EXCEPTION 'work_orders.workspace_id (%) does not match project.workspace_id (%)',
      NEW.workspace_id, proj_ws;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_work_orders_tenant ON work_orders;
CREATE TRIGGER trg_work_orders_tenant
  BEFORE INSERT OR UPDATE OF workspace_id, project_id ON work_orders
  FOR EACH ROW EXECUTE FUNCTION public.work_orders_enforce_tenant();

CREATE OR REPLACE FUNCTION public.wo_child_enforce_tenant()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE parent_ws UUID;
BEGIN
  SELECT workspace_id INTO parent_ws FROM work_orders WHERE id = NEW.work_order_id;
  IF parent_ws IS NULL THEN
    RAISE EXCEPTION 'Work order % does not exist', NEW.work_order_id;
  END IF;
  IF NEW.workspace_id IS DISTINCT FROM parent_ws THEN
    RAISE EXCEPTION 'Child workspace_id (%) does not match parent work_order.workspace_id (%)',
      NEW.workspace_id, parent_ws;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_wo_items_tenant ON work_order_items;
CREATE TRIGGER trg_wo_items_tenant
  BEFORE INSERT OR UPDATE OF workspace_id, work_order_id ON work_order_items
  FOR EACH ROW EXECUTE FUNCTION public.wo_child_enforce_tenant();

DROP TRIGGER IF EXISTS trg_wo_sigs_tenant ON work_order_signatures;
CREATE TRIGGER trg_wo_sigs_tenant
  BEFORE INSERT OR UPDATE OF workspace_id, work_order_id ON work_order_signatures
  FOR EACH ROW EXECUTE FUNCTION public.wo_child_enforce_tenant();

DROP TRIGGER IF EXISTS trg_wo_history_tenant ON work_order_history;
CREATE TRIGGER trg_wo_history_tenant
  BEFORE INSERT OR UPDATE OF workspace_id, work_order_id ON work_order_history
  FOR EACH ROW EXECUTE FUNCTION public.wo_child_enforce_tenant();

CREATE OR REPLACE FUNCTION public.subcontracts_enforce_tenant()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE proj_ws UUID;
BEGIN
  SELECT workspace_id INTO proj_ws FROM projects WHERE id = NEW.project_id;
  IF proj_ws IS NULL THEN
    RAISE EXCEPTION 'Project % does not exist', NEW.project_id;
  END IF;
  IF NEW.workspace_id IS DISTINCT FROM proj_ws THEN
    RAISE EXCEPTION 'subcontracts.workspace_id (%) does not match project.workspace_id (%)',
      NEW.workspace_id, proj_ws;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_subcontracts_tenant ON subcontracts;
CREATE TRIGGER trg_subcontracts_tenant
  BEFORE INSERT OR UPDATE OF workspace_id, project_id ON subcontracts
  FOR EACH ROW EXECUTE FUNCTION public.subcontracts_enforce_tenant();

CREATE OR REPLACE FUNCTION public.sc_child_enforce_tenant()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE parent_ws UUID;
BEGIN
  SELECT workspace_id INTO parent_ws FROM subcontracts WHERE id = NEW.subcontract_id;
  IF parent_ws IS NULL THEN
    RAISE EXCEPTION 'Subcontract % does not exist', NEW.subcontract_id;
  END IF;
  IF NEW.workspace_id IS DISTINCT FROM parent_ws THEN
    RAISE EXCEPTION 'Child workspace_id (%) does not match parent subcontract.workspace_id (%)',
      NEW.workspace_id, parent_ws;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_sc_items_tenant ON subcontract_items;
CREATE TRIGGER trg_sc_items_tenant
  BEFORE INSERT OR UPDATE OF workspace_id, subcontract_id ON subcontract_items
  FOR EACH ROW EXECUTE FUNCTION public.sc_child_enforce_tenant();

DROP TRIGGER IF EXISTS trg_sc_sigs_tenant ON subcontract_signatures;
CREATE TRIGGER trg_sc_sigs_tenant
  BEFORE INSERT OR UPDATE OF workspace_id, subcontract_id ON subcontract_signatures
  FOR EACH ROW EXECUTE FUNCTION public.sc_child_enforce_tenant();

DROP TRIGGER IF EXISTS trg_sc_history_tenant ON subcontract_history;
CREATE TRIGGER trg_sc_history_tenant
  BEFORE INSERT OR UPDATE OF workspace_id, subcontract_id ON subcontract_history
  FOR EACH ROW EXECUTE FUNCTION public.sc_child_enforce_tenant();

-- ─────────────────── auto-history on status change ──────────────────────────

CREATE OR REPLACE FUNCTION public.work_orders_log_status_change()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  IF TG_OP = 'UPDATE' AND OLD.status IS DISTINCT FROM NEW.status THEN
    INSERT INTO work_order_history(
      work_order_id, workspace_id, event_type, from_status, to_status, message
    ) VALUES (
      NEW.id, NEW.workspace_id, 'status_changed', OLD.status, NEW.status,
      'Status changed from ' || OLD.status || ' to ' || NEW.status
    );
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_wo_status_history ON work_orders;
CREATE TRIGGER trg_wo_status_history
  AFTER UPDATE OF status ON work_orders
  FOR EACH ROW EXECUTE FUNCTION public.work_orders_log_status_change();

CREATE OR REPLACE FUNCTION public.subcontracts_log_status_change()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  IF TG_OP = 'UPDATE' AND OLD.status IS DISTINCT FROM NEW.status THEN
    INSERT INTO subcontract_history(
      subcontract_id, workspace_id, event_type, from_status, to_status, message
    ) VALUES (
      NEW.id, NEW.workspace_id, 'status_changed', OLD.status, NEW.status,
      'Status changed from ' || OLD.status || ' to ' || NEW.status
    );
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_sc_status_history ON subcontracts;
CREATE TRIGGER trg_sc_status_history
  AFTER UPDATE OF status ON subcontracts
  FOR EACH ROW EXECUTE FUNCTION public.subcontracts_log_status_change();

-- ─────────────────── RLS ─────────────────────────────────────────────────────

ALTER TABLE work_orders            ENABLE ROW LEVEL SECURITY;
ALTER TABLE work_order_items       ENABLE ROW LEVEL SECURITY;
ALTER TABLE work_order_signatures  ENABLE ROW LEVEL SECURITY;
ALTER TABLE work_order_history     ENABLE ROW LEVEL SECURITY;
ALTER TABLE subcontracts           ENABLE ROW LEVEL SECURITY;
ALTER TABLE subcontract_items      ENABLE ROW LEVEL SECURITY;
ALTER TABLE subcontract_signatures ENABLE ROW LEVEL SECURITY;
ALTER TABLE subcontract_history    ENABLE ROW LEVEL SECURITY;

DO $$
DECLARE
  t TEXT;
  tables TEXT[] := ARRAY[
    'work_orders','work_order_items','work_order_signatures','work_order_history',
    'subcontracts','subcontract_items','subcontract_signatures','subcontract_history'
  ];
BEGIN
  FOREACH t IN ARRAY tables LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I_select ON %I', t, t);
    EXECUTE format('DROP POLICY IF EXISTS %I_insert ON %I', t, t);
    EXECUTE format('DROP POLICY IF EXISTS %I_update ON %I', t, t);
    EXECUTE format('DROP POLICY IF EXISTS %I_delete ON %I', t, t);
    EXECUTE format(
      'CREATE POLICY %I_select ON %I FOR SELECT USING (is_workspace_member(workspace_id))', t, t);
    EXECUTE format(
      'CREATE POLICY %I_insert ON %I FOR INSERT WITH CHECK (is_workspace_member(workspace_id))', t, t);
    EXECUTE format(
      'CREATE POLICY %I_update ON %I FOR UPDATE USING (is_workspace_member(workspace_id))', t, t);
    EXECUTE format(
      'CREATE POLICY %I_delete ON %I FOR DELETE USING (is_workspace_member(workspace_id))', t, t);
  END LOOP;
END $$;
