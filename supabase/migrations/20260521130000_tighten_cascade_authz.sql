-- Tighten authorization on catalog_cascade_to_open_jobs.
--
-- The cascade is a high-impact financial update that rewrites pricing
-- fields on every open project in a workspace. The initial RPC only
-- required workspace membership, but per code review this is too broad:
-- field crews and viewers should not be able to push catalog edits
-- into live job budgets. Restrict to admins and project managers
-- (the same gate used by `is_pm_or_admin`).

BEGIN;

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
  -- Authz: caller must be an admin or project manager in the workspace.
  IF NOT EXISTS (
    SELECT 1 FROM public.workspace_members
     WHERE workspace_id = p_workspace_id
       AND user_id = auth.uid()
       AND role IN ('admin', 'project_manager')
  ) THEN
    RAISE EXCEPTION 'Not authorized to cascade catalog edits in workspace %',
      p_workspace_id
      USING ERRCODE = '42501';
  END IF;

  IF p_catalog_ids IS NULL OR array_length(p_catalog_ids, 1) IS NULL THEN
    matched_count := 0;
    project_count := 0;
    RETURN NEXT;
    RETURN;
  END IF;

  IF NOT (v_has_unit_cost OR v_has_unit_price OR v_has_markup
       OR v_has_unit OR v_has_taxable) THEN
    matched_count := 0;
    project_count := 0;
    RETURN NEXT;
    RETURN;
  END IF;

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
       AND bi.approved_at IS NULL
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

COMMIT;
