-- Bulk cost-item editing across catalog + open jobs
--
-- Goal: when a supervisor mass-edits catalog cost items, optionally cascade
-- the same field updates into matching `budget_items` on every *open* project
-- (status in active, on_hold, awarded), without disturbing contracted /
-- approved line items.
--
-- Strategy:
--   1. Add an optional FK `source_catalog_item_id` on budget_items so future
--      copies from catalog can be tracked precisely.
--   2. Provide a SECURITY DEFINER RPC `catalog_cascade_to_open_jobs` that
--      takes the catalog ids being changed and a JSONB of field overrides,
--      then updates matching budget_items by FK first, falling back to
--      case-insensitive name match. Approved items (approved_at IS NOT NULL)
--      are skipped to protect contracted pricing.

BEGIN;

------------------------------------------------------------------------------
-- 1. Optional link from budget item back to its source catalog item.
------------------------------------------------------------------------------
ALTER TABLE public.budget_items
  ADD COLUMN IF NOT EXISTS source_catalog_item_id UUID
    REFERENCES public.catalog_items(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_budget_items_source_catalog
  ON public.budget_items(source_catalog_item_id)
  WHERE source_catalog_item_id IS NOT NULL;

------------------------------------------------------------------------------
-- 2. Cascade RPC.
--
-- Inputs:
--   p_workspace_id  uuid    -- workspace scope (authz check)
--   p_catalog_ids   uuid[]  -- catalog items the user just edited
--   p_fields        jsonb   -- which fields to apply, e.g.
--                            -- {"unit_cost": 12.5, "unit_price": 18.0,
--                            --  "markup": 50.0, "unit": "ea",
--                            --  "is_taxable": true}
--                            -- Only keys present are applied. Other keys
--                            -- are ignored.
--
-- Returns:
--   matched_count   int     -- budget items that were updated
--   project_count   int     -- distinct open projects touched
------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.catalog_cascade_to_open_jobs(
  p_workspace_id UUID,
  p_catalog_ids  UUID[],
  p_fields       JSONB
)
RETURNS TABLE(matched_count INTEGER, project_count INTEGER)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_names         TEXT[];
  v_matched       INTEGER := 0;
  v_projects      INTEGER := 0;
  v_has_unit_cost   BOOLEAN := p_fields ? 'unit_cost';
  v_has_unit_price  BOOLEAN := p_fields ? 'unit_price';
  v_has_markup      BOOLEAN := p_fields ? 'markup';
  v_has_unit        BOOLEAN := p_fields ? 'unit';
  v_has_taxable     BOOLEAN := p_fields ? 'is_taxable';
BEGIN
  -- Authz: caller must belong to the workspace.
  IF NOT EXISTS (
    SELECT 1 FROM public.workspace_members
     WHERE workspace_id = p_workspace_id
       AND user_id = auth.uid()
  ) THEN
    RAISE EXCEPTION 'Not authorized for workspace %', p_workspace_id
      USING ERRCODE = '42501';
  END IF;

  IF p_catalog_ids IS NULL OR array_length(p_catalog_ids, 1) IS NULL THEN
    matched_count := 0;
    project_count := 0;
    RETURN NEXT;
    RETURN;
  END IF;

  -- Nothing to apply — short-circuit.
  IF NOT (v_has_unit_cost OR v_has_unit_price OR v_has_markup
       OR v_has_unit OR v_has_taxable) THEN
    matched_count := 0;
    project_count := 0;
    RETURN NEXT;
    RETURN;
  END IF;

  -- Collect normalized names from the catalog items being changed so we can
  -- match legacy budget rows that have no source_catalog_item_id yet.
  SELECT array_agg(DISTINCT lower(btrim(name)))
    INTO v_names
    FROM public.catalog_items
   WHERE workspace_id = p_workspace_id
     AND id = ANY (p_catalog_ids)
     AND name IS NOT NULL;

  WITH targets AS (
    SELECT bi.id, bi.project_id
      FROM public.budget_items bi
      JOIN public.projects p
        ON p.id = bi.project_id
       AND p.workspace_id = p_workspace_id
     WHERE bi.workspace_id = p_workspace_id
       AND bi.item_type = 'item'
       AND bi.approved_at IS NULL  -- never touch contracted rows
       AND p.status IN ('active', 'on_hold', 'awarded')
       AND (
            bi.source_catalog_item_id = ANY (p_catalog_ids)
         OR (
              bi.source_catalog_item_id IS NULL
              AND v_names IS NOT NULL
              AND lower(btrim(bi.name)) = ANY (v_names)
            )
       )
  ),
  upd AS (
    UPDATE public.budget_items bi
       SET unit_cost   = CASE WHEN v_has_unit_cost
                              THEN (p_fields->>'unit_cost')::numeric
                              ELSE bi.unit_cost END,
           unit_price  = CASE WHEN v_has_unit_price
                              THEN (p_fields->>'unit_price')::numeric
                              ELSE bi.unit_price END,
           markup      = CASE WHEN v_has_markup
                              THEN (p_fields->>'markup')::numeric
                              ELSE bi.markup END,
           unit        = CASE WHEN v_has_unit
                              THEN NULLIF(p_fields->>'unit', '')
                              ELSE bi.unit END,
           is_taxable  = CASE WHEN v_has_taxable
                              THEN (p_fields->>'is_taxable')::boolean
                              ELSE bi.is_taxable END,
           updated_at  = now()
      FROM targets t
     WHERE bi.id = t.id
    RETURNING bi.id, bi.project_id
  )
  SELECT count(*)::int, count(DISTINCT project_id)::int
    INTO v_matched, v_projects
    FROM upd;

  matched_count := v_matched;
  project_count := v_projects;
  RETURN NEXT;
END;
$$;

GRANT EXECUTE ON FUNCTION public.catalog_cascade_to_open_jobs(UUID, UUID[], JSONB)
  TO authenticated;

COMMIT;
