-- =============================================================================
-- Inventory Module (Phase 1)
-- =============================================================================
-- Adds suppliers, stock items (consumables), purchase orders, stock movements,
-- and equipment rentals. Also extends `assets` with leasing fields so
-- equipment such as air movers and dehumidifiers can be billed at a daily
-- rental rate, which is how restoration contractors generate revenue.
--
-- Tailored to insurance restoration / general contractors:
--   * inventory_items.category supports common restoration consumables
--   * inventory_stock_movements supports issuing stock to a project (job)
--     and writes a corresponding cost_items row downstream from the app.
--   * equipment_rentals tracks per-job equipment deployment with snapshot
--     daily/weekly/monthly rate so historical billing is preserved if the
--     asset's master rate later changes.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- 1. Suppliers / Vendors used for inventory restock
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS inventory_suppliers (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id    UUID NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
  name            TEXT NOT NULL,
  contact_name    TEXT,
  email           TEXT,
  phone           TEXT,
  address         TEXT,
  website         TEXT,
  notes           TEXT,
  is_active       BOOLEAN NOT NULL DEFAULT TRUE,
  created_by      UUID REFERENCES auth.users(id),
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_inventory_suppliers_workspace
  ON inventory_suppliers(workspace_id);

-- ---------------------------------------------------------------------------
-- 2. Stockable / consumable inventory items
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS inventory_items (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id        UUID NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
  sku                 TEXT,
  name                TEXT NOT NULL,
  description         TEXT,
  -- Common restoration / GC categories: 'antimicrobial', 'ppe', 'plastic_sheeting',
  -- 'drywall', 'lumber', 'fasteners', 'cleaning', 'tools_consumable', 'other'
  category            TEXT NOT NULL DEFAULT 'other',
  unit_of_measure     TEXT NOT NULL DEFAULT 'each',  -- e.g. each, box, gallon, sqft
  default_supplier_id UUID REFERENCES inventory_suppliers(id) ON DELETE SET NULL,
  -- Pricing snapshot used to seed new POs and to value stock issued to jobs.
  unit_cost           NUMERIC(12,2) NOT NULL DEFAULT 0,    -- what we pay
  unit_sale_price     NUMERIC(12,2),                       -- what we charge the job (optional)
  on_hand_qty         NUMERIC(14,3) NOT NULL DEFAULT 0,    -- maintained by stock movements
  reorder_point       NUMERIC(14,3) NOT NULL DEFAULT 0,
  storage_location    TEXT,
  photo_urls          TEXT[] NOT NULL DEFAULT ARRAY[]::TEXT[],
  is_active           BOOLEAN NOT NULL DEFAULT TRUE,
  created_by          UUID REFERENCES auth.users(id),
  created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_inventory_items_workspace ON inventory_items(workspace_id);
CREATE INDEX IF NOT EXISTS idx_inventory_items_supplier ON inventory_items(default_supplier_id);
CREATE UNIQUE INDEX IF NOT EXISTS uq_inventory_items_workspace_sku
  ON inventory_items(workspace_id, sku) WHERE sku IS NOT NULL;

-- ---------------------------------------------------------------------------
-- 3. Purchase orders + lines (track purchase + delivery of supplies)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS inventory_purchase_orders (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id    UUID NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
  po_number       TEXT,                                 -- human-readable, optional
  supplier_id     UUID NOT NULL REFERENCES inventory_suppliers(id) ON DELETE RESTRICT,
  project_id      UUID REFERENCES projects(id) ON DELETE SET NULL,
  -- Lifecycle: 'draft' -> 'ordered' -> 'partial' -> 'received' -> 'cancelled'
  status          TEXT NOT NULL DEFAULT 'draft',
  order_date      DATE,
  expected_date   DATE,
  received_date   DATE,
  shipping_cost   NUMERIC(12,2) NOT NULL DEFAULT 0,
  tax             NUMERIC(12,2) NOT NULL DEFAULT 0,
  notes           TEXT,
  created_by      UUID REFERENCES auth.users(id),
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_inv_po_workspace ON inventory_purchase_orders(workspace_id);
CREATE INDEX IF NOT EXISTS idx_inv_po_supplier ON inventory_purchase_orders(supplier_id);
CREATE INDEX IF NOT EXISTS idx_inv_po_project ON inventory_purchase_orders(project_id);
CREATE INDEX IF NOT EXISTS idx_inv_po_status ON inventory_purchase_orders(status);

CREATE TABLE IF NOT EXISTS inventory_purchase_order_lines (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id        UUID NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
  purchase_order_id   UUID NOT NULL REFERENCES inventory_purchase_orders(id) ON DELETE CASCADE,
  inventory_item_id   UUID NOT NULL REFERENCES inventory_items(id) ON DELETE RESTRICT,
  quantity_ordered    NUMERIC(14,3) NOT NULL,
  quantity_received   NUMERIC(14,3) NOT NULL DEFAULT 0,
  unit_cost           NUMERIC(12,2) NOT NULL,
  line_total          NUMERIC(14,2) GENERATED ALWAYS AS (quantity_ordered * unit_cost) STORED,
  notes               TEXT,
  created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_inv_pol_po ON inventory_purchase_order_lines(purchase_order_id);
CREATE INDEX IF NOT EXISTS idx_inv_pol_item ON inventory_purchase_order_lines(inventory_item_id);

-- ---------------------------------------------------------------------------
-- 4. Stock movements (the audit + inventory ledger)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS inventory_stock_movements (
  id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id          UUID NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
  inventory_item_id     UUID NOT NULL REFERENCES inventory_items(id) ON DELETE CASCADE,
  -- 'receive'  : stock arriving (PO delivery, manual receive) -> +qty
  -- 'issue'    : stock used on a job                          -> -qty
  -- 'return'   : stock returned to inventory from a job       -> +qty
  -- 'adjust'   : manual count correction                      -> ±qty
  movement_type         TEXT NOT NULL,
  quantity              NUMERIC(14,3) NOT NULL,    -- always positive; sign comes from movement_type
  unit_cost             NUMERIC(12,2),             -- snapshot at the moment of movement
  project_id            UUID REFERENCES projects(id) ON DELETE SET NULL,
  purchase_order_id     UUID REFERENCES inventory_purchase_orders(id) ON DELETE SET NULL,
  cost_item_id          UUID,                      -- backlink to financials when issued to a job
  notes                 TEXT,
  occurred_at           TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  created_by            UUID REFERENCES auth.users(id),
  created_at            TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_inv_sm_workspace ON inventory_stock_movements(workspace_id);
CREATE INDEX IF NOT EXISTS idx_inv_sm_item ON inventory_stock_movements(inventory_item_id);
CREATE INDEX IF NOT EXISTS idx_inv_sm_project ON inventory_stock_movements(project_id);
CREATE INDEX IF NOT EXISTS idx_inv_sm_po ON inventory_stock_movements(purchase_order_id);

-- Maintain inventory_items.on_hand_qty automatically as movements are
-- inserted/updated/deleted. Centralizing this in the DB removes any chance
-- of UI logic forgetting to update it.
CREATE OR REPLACE FUNCTION inventory_apply_stock_movement()
RETURNS TRIGGER AS $$
DECLARE
  delta NUMERIC(14,3) := 0;
  old_delta NUMERIC(14,3) := 0;
BEGIN
  IF TG_OP IN ('INSERT', 'UPDATE') THEN
    delta := CASE NEW.movement_type
      WHEN 'receive' THEN  NEW.quantity
      WHEN 'return'  THEN  NEW.quantity
      WHEN 'issue'   THEN -NEW.quantity
      WHEN 'adjust'  THEN  NEW.quantity   -- caller passes signed qty as positive/negative
      ELSE 0
    END;
  END IF;

  IF TG_OP IN ('UPDATE', 'DELETE') THEN
    old_delta := CASE OLD.movement_type
      WHEN 'receive' THEN  OLD.quantity
      WHEN 'return'  THEN  OLD.quantity
      WHEN 'issue'   THEN -OLD.quantity
      WHEN 'adjust'  THEN  OLD.quantity
      ELSE 0
    END;
  END IF;

  IF TG_OP = 'INSERT' THEN
    UPDATE inventory_items SET on_hand_qty = on_hand_qty + delta,
      updated_at = NOW() WHERE id = NEW.inventory_item_id;
  ELSIF TG_OP = 'UPDATE' THEN
    -- If item changed, reverse on old item then apply on new item.
    IF NEW.inventory_item_id <> OLD.inventory_item_id THEN
      UPDATE inventory_items SET on_hand_qty = on_hand_qty - old_delta,
        updated_at = NOW() WHERE id = OLD.inventory_item_id;
      UPDATE inventory_items SET on_hand_qty = on_hand_qty + delta,
        updated_at = NOW() WHERE id = NEW.inventory_item_id;
    ELSE
      UPDATE inventory_items SET on_hand_qty = on_hand_qty + (delta - old_delta),
        updated_at = NOW() WHERE id = NEW.inventory_item_id;
    END IF;
  ELSIF TG_OP = 'DELETE' THEN
    UPDATE inventory_items SET on_hand_qty = on_hand_qty - old_delta,
      updated_at = NOW() WHERE id = OLD.inventory_item_id;
  END IF;

  RETURN COALESCE(NEW, OLD);
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_inv_sm_apply ON inventory_stock_movements;
CREATE TRIGGER trg_inv_sm_apply
AFTER INSERT OR UPDATE OR DELETE ON inventory_stock_movements
FOR EACH ROW EXECUTE FUNCTION inventory_apply_stock_movement();

-- ---------------------------------------------------------------------------
-- 5. Asset leasing extension (rental fee per day/week/month)
-- ---------------------------------------------------------------------------
ALTER TABLE assets
  ADD COLUMN IF NOT EXISTS is_leasable          BOOLEAN NOT NULL DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS daily_rental_rate    NUMERIC(12,2),
  ADD COLUMN IF NOT EXISTS weekly_rental_rate   NUMERIC(12,2),
  ADD COLUMN IF NOT EXISTS monthly_rental_rate  NUMERIC(12,2),
  ADD COLUMN IF NOT EXISTS replacement_cost     NUMERIC(12,2);

-- ---------------------------------------------------------------------------
-- 6. Equipment rentals — per-job deployments of leasable assets
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS equipment_rentals (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id        UUID NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
  asset_id            UUID NOT NULL REFERENCES assets(id) ON DELETE RESTRICT,
  project_id          UUID NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
  start_date          DATE NOT NULL,
  end_date            DATE,                       -- null = still on site
  -- Snapshot rates so historical revenue isn't distorted by later edits.
  daily_rate          NUMERIC(12,2) NOT NULL DEFAULT 0,
  weekly_rate         NUMERIC(12,2),
  monthly_rate        NUMERIC(12,2),
  -- Billed = invoiced to client; controls whether financials should display.
  is_billable         BOOLEAN NOT NULL DEFAULT TRUE,
  notes               TEXT,
  cost_item_id        UUID,                       -- optional cost_items backlink
  created_by          UUID REFERENCES auth.users(id),
  created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT chk_eqr_dates CHECK (end_date IS NULL OR end_date >= start_date)
);
CREATE INDEX IF NOT EXISTS idx_eqr_workspace ON equipment_rentals(workspace_id);
CREATE INDEX IF NOT EXISTS idx_eqr_asset ON equipment_rentals(asset_id);
CREATE INDEX IF NOT EXISTS idx_eqr_project ON equipment_rentals(project_id);
CREATE INDEX IF NOT EXISTS idx_eqr_open
  ON equipment_rentals(asset_id) WHERE end_date IS NULL;

-- ---------------------------------------------------------------------------
-- 7. Row-level security — restrict everything to workspace members
-- ---------------------------------------------------------------------------
ALTER TABLE inventory_suppliers              ENABLE ROW LEVEL SECURITY;
ALTER TABLE inventory_items                  ENABLE ROW LEVEL SECURITY;
ALTER TABLE inventory_purchase_orders        ENABLE ROW LEVEL SECURITY;
ALTER TABLE inventory_purchase_order_lines   ENABLE ROW LEVEL SECURITY;
ALTER TABLE inventory_stock_movements        ENABLE ROW LEVEL SECURITY;
ALTER TABLE equipment_rentals                ENABLE ROW LEVEL SECURITY;

DO $$
DECLARE
  t TEXT;
BEGIN
  FOREACH t IN ARRAY ARRAY[
    'inventory_suppliers',
    'inventory_items',
    'inventory_purchase_orders',
    'inventory_purchase_order_lines',
    'inventory_stock_movements',
    'equipment_rentals'
  ] LOOP
    EXECUTE format('DROP POLICY IF EXISTS %1$s_select ON %1$s;', t);
    EXECUTE format('CREATE POLICY %1$s_select ON %1$s FOR SELECT USING (is_workspace_member(workspace_id));', t);
    EXECUTE format('DROP POLICY IF EXISTS %1$s_insert ON %1$s;', t);
    EXECUTE format('CREATE POLICY %1$s_insert ON %1$s FOR INSERT WITH CHECK (is_workspace_member(workspace_id));', t);
    EXECUTE format('DROP POLICY IF EXISTS %1$s_update ON %1$s;', t);
    EXECUTE format('CREATE POLICY %1$s_update ON %1$s FOR UPDATE USING (is_workspace_member(workspace_id));', t);
    EXECUTE format('DROP POLICY IF EXISTS %1$s_delete ON %1$s;', t);
    EXECUTE format('CREATE POLICY %1$s_delete ON %1$s FOR DELETE USING (is_workspace_member(workspace_id));', t);
  END LOOP;
END $$;

-- ---------------------------------------------------------------------------
-- 8. Realtime publication
-- ---------------------------------------------------------------------------
DO $$
DECLARE
  t TEXT;
BEGIN
  FOREACH t IN ARRAY ARRAY[
    'inventory_suppliers',
    'inventory_items',
    'inventory_purchase_orders',
    'inventory_purchase_order_lines',
    'inventory_stock_movements',
    'equipment_rentals'
  ] LOOP
    BEGIN
      EXECUTE format('ALTER PUBLICATION supabase_realtime ADD TABLE %I;', t);
    EXCEPTION WHEN duplicate_object THEN NULL;
    END;
  END LOOP;
END $$;
