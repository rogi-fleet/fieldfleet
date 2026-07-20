-- =============================================================================
-- Catalog robustness — turn catalog_items into the canonical product/service
-- registry that integrates with documents (invoices, bills, expenses),
-- inventory, vendors, customers, and projects.
-- =============================================================================

-- ----- 1. Extend catalog_items with integration columns ----------------------

ALTER TABLE catalog_items
  ADD COLUMN IF NOT EXISTS kind                       TEXT NOT NULL DEFAULT 'service',
  ADD COLUMN IF NOT EXISTS is_active                  BOOLEAN NOT NULL DEFAULT TRUE,
  ADD COLUMN IF NOT EXISTS internal_notes             TEXT,
  ADD COLUMN IF NOT EXISTS barcode                    TEXT,
  ADD COLUMN IF NOT EXISTS tags                       TEXT[] NOT NULL DEFAULT '{}',
  ADD COLUMN IF NOT EXISTS currency                   TEXT NOT NULL DEFAULT 'USD',
  ADD COLUMN IF NOT EXISTS min_price                  NUMERIC(14,2),
  -- Sales-side defaults for invoices & estimates
  ADD COLUMN IF NOT EXISTS default_tax_rate           NUMERIC(6,3) NOT NULL DEFAULT 0,
  -- Purchase-side defaults for bills & expenses
  ADD COLUMN IF NOT EXISTS default_vendor_id          UUID REFERENCES vendors(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS purchase_unit              TEXT,
  ADD COLUMN IF NOT EXISTS purchase_cost              NUMERIC(14,2),
  ADD COLUMN IF NOT EXISTS purchase_description       TEXT,
  -- Inventory linkage
  ADD COLUMN IF NOT EXISTS inventory_tracked          BOOLEAN NOT NULL DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS inventory_item_id          UUID,
  -- Usage analytics
  ADD COLUMN IF NOT EXISTS usage_count                INTEGER NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS last_used_at               TIMESTAMPTZ;

-- Best-effort FK to inventory_items if that table exists
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'inventory_items') THEN
    BEGIN
      ALTER TABLE catalog_items
        ADD CONSTRAINT catalog_items_inventory_item_fk
        FOREIGN KEY (inventory_item_id) REFERENCES inventory_items(id) ON DELETE SET NULL;
    EXCEPTION WHEN duplicate_object THEN NULL;
    END;
  END IF;
END $$;

-- Allowed values for kind. Items remain "service" by default; existing rows
-- are upgraded based on whether they look like physical goods (have a SKU).
UPDATE catalog_items SET kind = 'product' WHERE kind = 'service' AND sku IS NOT NULL AND sku <> '';

ALTER TABLE catalog_items
  DROP CONSTRAINT IF EXISTS chk_catalog_items_kind;
ALTER TABLE catalog_items
  ADD CONSTRAINT chk_catalog_items_kind
  CHECK (kind IN ('product','service','bundle','labor','expense','fee','non_inventory'));

ALTER TABLE catalog_items
  DROP CONSTRAINT IF EXISTS chk_catalog_items_default_tax_rate;
ALTER TABLE catalog_items
  ADD CONSTRAINT chk_catalog_items_default_tax_rate
  CHECK (default_tax_rate >= 0 AND default_tax_rate <= 100);

CREATE INDEX IF NOT EXISTS idx_catalog_items_kind        ON catalog_items(workspace_id, kind);
CREATE INDEX IF NOT EXISTS idx_catalog_items_is_active   ON catalog_items(workspace_id, is_active);
CREATE INDEX IF NOT EXISTS idx_catalog_items_barcode     ON catalog_items(workspace_id, barcode) WHERE barcode IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_catalog_items_usage_desc  ON catalog_items(workspace_id, usage_count DESC);
CREATE INDEX IF NOT EXISTS idx_catalog_items_last_used   ON catalog_items(workspace_id, last_used_at DESC NULLS LAST);

-- ----- 2. Bundle components (composite items) --------------------------------

CREATE TABLE IF NOT EXISTS catalog_bundle_components (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id    UUID NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
  bundle_id       UUID NOT NULL REFERENCES catalog_items(id) ON DELETE CASCADE,
  component_id    UUID NOT NULL REFERENCES catalog_items(id) ON DELETE RESTRICT,
  quantity        NUMERIC(14,3) NOT NULL DEFAULT 1 CHECK (quantity > 0),
  sort_order      INTEGER NOT NULL DEFAULT 0,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT chk_bundle_no_self_loop CHECK (bundle_id <> component_id)
);
CREATE INDEX IF NOT EXISTS idx_catalog_bundle_workspace ON catalog_bundle_components(workspace_id);
CREATE INDEX IF NOT EXISTS idx_catalog_bundle_bundle    ON catalog_bundle_components(bundle_id);
CREATE INDEX IF NOT EXISTS idx_catalog_bundle_component ON catalog_bundle_components(component_id);
CREATE UNIQUE INDEX IF NOT EXISTS uq_catalog_bundle_pair ON catalog_bundle_components(bundle_id, component_id);

-- ----- 3. Tiered / customer-specific pricing ---------------------------------

CREATE TABLE IF NOT EXISTS catalog_price_tiers (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id    UUID NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
  catalog_item_id UUID NOT NULL REFERENCES catalog_items(id) ON DELETE CASCADE,
  -- tier scope: customer-specific OR a named tier ("retail","wholesale","contractor"…)
  customer_id     UUID REFERENCES customers(id) ON DELETE CASCADE,
  tier_name       TEXT,
  -- volume break: applies when ordered quantity >= min_quantity
  min_quantity    NUMERIC(14,3) NOT NULL DEFAULT 1 CHECK (min_quantity > 0),
  unit_price      NUMERIC(14,2) NOT NULL CHECK (unit_price >= 0),
  -- date window (NULL = open-ended)
  starts_at       DATE,
  ends_at         DATE,
  notes           TEXT,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT chk_price_tier_scope
    CHECK (customer_id IS NOT NULL OR tier_name IS NOT NULL)
);
CREATE INDEX IF NOT EXISTS idx_catalog_price_tiers_workspace ON catalog_price_tiers(workspace_id);
CREATE INDEX IF NOT EXISTS idx_catalog_price_tiers_item      ON catalog_price_tiers(catalog_item_id);
CREATE INDEX IF NOT EXISTS idx_catalog_price_tiers_customer  ON catalog_price_tiers(customer_id) WHERE customer_id IS NOT NULL;

-- ----- 5. Usage-tracking RPC -------------------------------------------------

CREATE OR REPLACE FUNCTION catalog_increment_usage(p_id UUID, p_delta INT DEFAULT 1)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE v_ws UUID;
BEGIN
  SELECT workspace_id INTO v_ws FROM catalog_items WHERE id = p_id;
  IF v_ws IS NULL THEN RETURN; END IF;
  -- Caller must belong to the same workspace.
  IF NOT EXISTS (
    SELECT 1 FROM workspace_members
      WHERE workspace_id = v_ws AND user_id = auth.uid()
  ) THEN
    RAISE EXCEPTION 'not authorized for workspace %', v_ws USING ERRCODE = '42501';
  END IF;
  UPDATE catalog_items
    SET usage_count = usage_count + GREATEST(p_delta, 0),
        last_used_at = NOW(),
        updated_at  = NOW()
    WHERE id = p_id;
END;
$$;
GRANT EXECUTE ON FUNCTION catalog_increment_usage(UUID, INT) TO authenticated;

-- ----- 6. Effective-price helper (tier resolver) -----------------------------

CREATE OR REPLACE FUNCTION catalog_effective_price(
  p_catalog_item_id UUID,
  p_customer_id     UUID DEFAULT NULL,
  p_quantity        NUMERIC DEFAULT 1
) RETURNS NUMERIC
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_price NUMERIC;
  v_ws    UUID;
BEGIN
  SELECT workspace_id INTO v_ws FROM catalog_items WHERE id = p_catalog_item_id;
  IF v_ws IS NULL THEN RETURN 0; END IF;
  IF NOT EXISTS (
    SELECT 1 FROM workspace_members
      WHERE workspace_id = v_ws AND user_id = auth.uid()
  ) THEN
    RAISE EXCEPTION 'not authorized for workspace %', v_ws USING ERRCODE = '42501';
  END IF;
  -- 1. Customer-specific tier with the highest qualifying min_quantity wins.
  IF p_customer_id IS NOT NULL THEN
    SELECT unit_price INTO v_price
      FROM catalog_price_tiers
      WHERE catalog_item_id = p_catalog_item_id
        AND customer_id = p_customer_id
        AND min_quantity <= COALESCE(p_quantity, 1)
        AND (starts_at IS NULL OR starts_at <= CURRENT_DATE)
        AND (ends_at   IS NULL OR ends_at   >= CURRENT_DATE)
      ORDER BY min_quantity DESC
      LIMIT 1;
    IF v_price IS NOT NULL THEN RETURN v_price; END IF;
  END IF;

  -- 2. Generic named-tier volume break.
  SELECT unit_price INTO v_price
    FROM catalog_price_tiers
    WHERE catalog_item_id = p_catalog_item_id
      AND customer_id IS NULL
      AND min_quantity <= COALESCE(p_quantity, 1)
      AND (starts_at IS NULL OR starts_at <= CURRENT_DATE)
      AND (ends_at   IS NULL OR ends_at   >= CURRENT_DATE)
    ORDER BY min_quantity DESC
    LIMIT 1;
  IF v_price IS NOT NULL THEN RETURN v_price; END IF;

  -- 3. Fall back to the catalog item's own unit_price.
  SELECT unit_price INTO v_price FROM catalog_items WHERE id = p_catalog_item_id;
  RETURN COALESCE(v_price, 0);
END;
$$;
GRANT EXECUTE ON FUNCTION catalog_effective_price(UUID, UUID, NUMERIC) TO authenticated;

-- ----- 6b. Workspace-consistency for the new tables --------------------------

CREATE OR REPLACE FUNCTION catalog_bundle_assert_same_workspace()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE v_b UUID; v_c UUID;
BEGIN
  SELECT workspace_id INTO v_b FROM catalog_items WHERE id = NEW.bundle_id;
  SELECT workspace_id INTO v_c FROM catalog_items WHERE id = NEW.component_id;
  IF v_b IS DISTINCT FROM NEW.workspace_id OR v_c IS DISTINCT FROM NEW.workspace_id THEN
    RAISE EXCEPTION 'workspace mismatch on catalog_bundle_components';
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_catalog_bundle_ws ON catalog_bundle_components;
CREATE TRIGGER trg_catalog_bundle_ws
  BEFORE INSERT OR UPDATE ON catalog_bundle_components
  FOR EACH ROW EXECUTE FUNCTION catalog_bundle_assert_same_workspace();

CREATE OR REPLACE FUNCTION catalog_price_tier_assert_same_workspace()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE v_i UUID; v_c UUID;
BEGIN
  SELECT workspace_id INTO v_i FROM catalog_items WHERE id = NEW.catalog_item_id;
  IF v_i IS DISTINCT FROM NEW.workspace_id THEN
    RAISE EXCEPTION 'workspace mismatch on catalog_price_tiers (item)';
  END IF;
  IF NEW.customer_id IS NOT NULL THEN
    SELECT workspace_id INTO v_c FROM customers WHERE id = NEW.customer_id;
    IF v_c IS DISTINCT FROM NEW.workspace_id THEN
      RAISE EXCEPTION 'workspace mismatch on catalog_price_tiers (customer)';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_catalog_price_tier_ws ON catalog_price_tiers;
CREATE TRIGGER trg_catalog_price_tier_ws
  BEFORE INSERT OR UPDATE ON catalog_price_tiers
  FOR EACH ROW EXECUTE FUNCTION catalog_price_tier_assert_same_workspace();

-- ----- 7. RLS for the new tables ---------------------------------------------

ALTER TABLE catalog_bundle_components ENABLE ROW LEVEL SECURITY;
ALTER TABLE catalog_price_tiers       ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS catalog_bundle_components_member ON catalog_bundle_components;
CREATE POLICY catalog_bundle_components_member ON catalog_bundle_components
  FOR ALL USING (
    workspace_id IN (SELECT workspace_id FROM workspace_members WHERE user_id = auth.uid())
  ) WITH CHECK (
    workspace_id IN (SELECT workspace_id FROM workspace_members WHERE user_id = auth.uid())
  );

DROP POLICY IF EXISTS catalog_price_tiers_member ON catalog_price_tiers;
CREATE POLICY catalog_price_tiers_member ON catalog_price_tiers
  FOR ALL USING (
    workspace_id IN (SELECT workspace_id FROM workspace_members WHERE user_id = auth.uid())
  ) WITH CHECK (
    workspace_id IN (SELECT workspace_id FROM workspace_members WHERE user_id = auth.uid())
  );

-- ----- 8. Realtime publication ----------------------------------------------

DO $$
BEGIN
  BEGIN
    EXECUTE 'ALTER PUBLICATION supabase_realtime ADD TABLE catalog_bundle_components';
  EXCEPTION WHEN duplicate_object THEN NULL; WHEN undefined_object THEN NULL;
  END;
  BEGIN
    EXECUTE 'ALTER PUBLICATION supabase_realtime ADD TABLE catalog_price_tiers';
  EXCEPTION WHEN duplicate_object THEN NULL; WHEN undefined_object THEN NULL;
  END;
END $$;
