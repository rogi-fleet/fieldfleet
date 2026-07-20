-- Configurable asset categories per workspace.
--
-- Replaces the hardcoded client-side AssetCategory enum with a
-- per-workspace lookup table. Owners can rename, recolor, reorder, or
-- add categories (e.g. a roofing crew adds "Edge protection", a
-- restoration crew adds "Drying equipment") without a code change.
--
-- We mirror the customer_types shape (migration 108) — same column
-- semantics (sort_order, is_default), same RLS posture (members read,
-- admins write), same seed-function approach. Two differences:
--
--   * `icon` column. Categories carry a Material icon name string
--     (e.g. 'electric_bolt', 'handyman_outlined'). The client maps to
--     IconData via a curated lookup; unknown names fall back to a
--     generic category icon.
--   * Seed-on-create *trigger*. customer_types relies on an explicit
--     RPC call from the workspace creation flow; we add a trigger so
--     new workspaces get categories without an extra round-trip.
--
-- `assets.category` stays TEXT — denormalized name reference, matching
-- how customers.customer_type works. Existing rows storing the old
-- enum ids ('power_tool', 'hand_tool', …) get rewritten to the
-- corresponding display names so the foreign-key-by-name lookup still
-- resolves after this migration.

CREATE TABLE IF NOT EXISTS public.asset_categories (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  workspace_id UUID NOT NULL REFERENCES public.workspaces(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  color TEXT NOT NULL DEFAULT '#9E9E9E',
  icon TEXT NOT NULL DEFAULT 'category_outlined',
  sort_order INTEGER NOT NULL DEFAULT 0,
  is_default BOOLEAN NOT NULL DEFAULT FALSE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE(workspace_id, name)
);

CREATE INDEX IF NOT EXISTS idx_asset_categories_workspace
  ON public.asset_categories (workspace_id, sort_order);

CREATE TRIGGER update_asset_categories_updated_at
  BEFORE UPDATE ON public.asset_categories
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

-- ---------------------------------------------------------------------------
-- RLS
-- ---------------------------------------------------------------------------
ALTER TABLE public.asset_categories ENABLE ROW LEVEL SECURITY;

CREATE POLICY asset_categories_select ON public.asset_categories
  FOR SELECT USING (public.is_workspace_member(workspace_id));

CREATE POLICY asset_categories_insert ON public.asset_categories
  FOR INSERT WITH CHECK (public.is_workspace_admin(workspace_id));

CREATE POLICY asset_categories_update ON public.asset_categories
  FOR UPDATE USING (public.is_workspace_admin(workspace_id));

CREATE POLICY asset_categories_delete ON public.asset_categories
  FOR DELETE USING (public.is_workspace_admin(workspace_id));

-- ---------------------------------------------------------------------------
-- Seed function — used by both backfill and the new-workspace trigger
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.seed_asset_categories_for_workspace(
  p_workspace_id UUID
) RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO public.asset_categories (
    workspace_id, name, color, icon, sort_order, is_default
  ) VALUES
    (p_workspace_id, 'Power tool',         '#2196F3', 'electric_bolt',                 0, TRUE),
    (p_workspace_id, 'Hand tool',          '#FF9800', 'handyman_outlined',             1, TRUE),
    (p_workspace_id, 'Heavy equipment',    '#E65100', 'precision_manufacturing_outlined', 2, TRUE),
    (p_workspace_id, 'Ladder',             '#F44336', 'height',                        3, TRUE),
    (p_workspace_id, 'Safety gear',        '#4CAF50', 'health_and_safety_outlined',    4, TRUE),
    (p_workspace_id, 'Electronics',        '#3F51B5', 'devices_outlined',              5, TRUE),
    (p_workspace_id, 'Furniture',          '#795548', 'chair_outlined',                6, TRUE),
    (p_workspace_id, 'Vehicle attachment', '#00ACC1', 'rv_hookup_outlined',            7, TRUE),
    (p_workspace_id, 'Other',              '#9E9E9E', 'category_outlined',             8, TRUE)
  ON CONFLICT (workspace_id, name) DO NOTHING;
END;
$$;

-- ---------------------------------------------------------------------------
-- Backfill default categories for existing workspaces
-- ---------------------------------------------------------------------------
DO $$
DECLARE
  ws RECORD;
BEGIN
  FOR ws IN SELECT id FROM public.workspaces LOOP
    PERFORM public.seed_asset_categories_for_workspace(ws.id);
  END LOOP;
END $$;

-- ---------------------------------------------------------------------------
-- Migrate existing assets.category enum-id values to display names so
-- the lookup-by-name from the new table resolves.
-- ---------------------------------------------------------------------------
UPDATE public.assets SET category = 'Power tool'         WHERE category = 'power_tool';
UPDATE public.assets SET category = 'Hand tool'          WHERE category = 'hand_tool';
UPDATE public.assets SET category = 'Heavy equipment'    WHERE category = 'heavy_equipment';
UPDATE public.assets SET category = 'Ladder'             WHERE category = 'ladder';
UPDATE public.assets SET category = 'Safety gear'        WHERE category = 'safety';
UPDATE public.assets SET category = 'Electronics'        WHERE category = 'electronics';
UPDATE public.assets SET category = 'Furniture'          WHERE category = 'furniture';
UPDATE public.assets SET category = 'Vehicle attachment' WHERE category = 'vehicle_attachment';
UPDATE public.assets SET category = 'Other'              WHERE category = 'other';

-- The default for new asset rows now lines up with the seeded "Other"
-- category name instead of the legacy enum id.
ALTER TABLE public.assets ALTER COLUMN category SET DEFAULT 'Other';

-- ---------------------------------------------------------------------------
-- Trigger: seed defaults for newly-created workspaces.
-- Customer types relies on an explicit RPC from the app; assets get a
-- trigger so categories exist before any insert can hit the table.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.trg_seed_asset_categories()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  PERFORM public.seed_asset_categories_for_workspace(NEW.id);
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS seed_asset_categories_after_workspace_insert
  ON public.workspaces;
CREATE TRIGGER seed_asset_categories_after_workspace_insert
  AFTER INSERT ON public.workspaces
  FOR EACH ROW EXECUTE FUNCTION public.trg_seed_asset_categories();

COMMENT ON TABLE public.asset_categories IS
  'Per-workspace asset category definitions. Owners can rename, '
  'recolor, reorder, or add. Referenced by assets.category (TEXT) by '
  'name.';
