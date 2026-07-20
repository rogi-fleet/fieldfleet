-- Repair production schema drift that breaks clock-in inserts from the deployed client.
-- The client sends time_entries.budget_item_id and calls this RPC before insert.

ALTER TABLE public.time_entries
  ADD COLUMN IF NOT EXISTS budget_item_id UUID;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conrelid = 'public.time_entries'::regclass
      AND conname = 'time_entries_budget_item_id_fkey'
  ) THEN
    ALTER TABLE public.time_entries
      ADD CONSTRAINT time_entries_budget_item_id_fkey
      FOREIGN KEY (budget_item_id) REFERENCES public.budget_items(id) ON DELETE SET NULL;
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_time_entries_budget_item
  ON public.time_entries(budget_item_id);

CREATE OR REPLACE FUNCTION public.get_or_create_uncategorized_labor_item(
  p_project_id UUID,
  p_workspace_id UUID
) RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_item_id UUID;
BEGIN
  SELECT id INTO v_item_id
  FROM public.budget_items
  WHERE project_id = p_project_id
    AND name = 'Uncategorized Labor'
    AND cost_type = 'labor'
    AND parent_id IS NULL
  LIMIT 1;

  IF v_item_id IS NOT NULL THEN
    RETURN v_item_id;
  END IF;

  INSERT INTO public.budget_items (
    id,
    workspace_id,
    project_id,
    parent_id,
    hierarchy_level,
    sort_order,
    name,
    description,
    item_type,
    cost_type,
    quantity,
    unit_cost,
    unit_price,
    markup,
    approved_price,
    projected_cost,
    created_at,
    updated_at
  )
  VALUES (
    gen_random_uuid(),
    p_workspace_id,
    p_project_id,
    NULL,
    0,
    99999,
    'Uncategorized Labor',
    'Default bucket for time entries not assigned to a specific budget item.',
    'item',
    'labor',
    1,
    0,
    0,
    0,
    0,
    0,
    NOW(),
    NOW()
  )
  RETURNING id INTO v_item_id;

  RETURN v_item_id;
END;
$$;

NOTIFY pgrst, 'reload schema';
