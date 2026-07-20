-- Link time entries directly to budget items for labor cost tracking.
-- If no budget item is chosen at clock-in, a default "Uncategorized Labor"
-- item is auto-created for the project and assigned.

-- ============================================================================
-- 1. COLUMN + FK + INDEX
-- ============================================================================

ALTER TABLE time_entries
  ADD COLUMN IF NOT EXISTS budget_item_id UUID REFERENCES budget_items(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_time_entries_budget_item
  ON time_entries(budget_item_id);

-- ============================================================================
-- 2. HELPER: get or create the default uncategorized labor budget item
-- ============================================================================

CREATE OR REPLACE FUNCTION get_or_create_uncategorized_labor_item(
  p_project_id UUID,
  p_workspace_id UUID
) RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_item_id UUID;
BEGIN
  -- Try to find an existing one first
  SELECT id INTO v_item_id
  FROM budget_items
  WHERE project_id = p_project_id
    AND name = 'Uncategorized Labor'
    AND cost_type = 'labor'
    AND parent_id IS NULL
  LIMIT 1;

  IF v_item_id IS NOT NULL THEN
    RETURN v_item_id;
  END IF;

  -- Determine next sort_order for top-level items
  INSERT INTO budget_items (
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
    NULL,           -- top-level
    0,              -- root level
    99999,          -- sort to end
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
