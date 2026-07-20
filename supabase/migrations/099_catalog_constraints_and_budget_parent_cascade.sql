-- 099: Add missing constraints, indexes, and cascade to catalog_items and budget_items
-- Brings catalog_items constraint parity with budget_items, and fixes orphan risk on budget parent deletion.

-- A. Add CASCADE to budget_items.parent_id (catalog has it, budget doesn't — orphan risk)
ALTER TABLE budget_items DROP CONSTRAINT IF EXISTS budget_items_parent_id_fkey;
ALTER TABLE budget_items ADD CONSTRAINT budget_items_parent_id_fkey
  FOREIGN KEY (parent_id) REFERENCES budget_items(id) ON DELETE CASCADE;

-- B. Add CHECK constraints to catalog_items (budget has these, catalog has 0)
ALTER TABLE catalog_items
  ADD CONSTRAINT chk_catalog_items_unit_cost_non_negative CHECK (unit_cost >= 0),
  ADD CONSTRAINT chk_catalog_items_unit_price_non_negative CHECK (unit_price >= 0),
  ADD CONSTRAINT chk_catalog_items_markup_non_negative CHECK (markup >= 0),
  ADD CONSTRAINT chk_catalog_items_margin_range CHECK (margin IS NULL OR margin <= 100),
  ADD CONSTRAINT chk_catalog_items_hierarchy_level_non_negative CHECK (hierarchy_level >= 0);

-- C. Add composite tree index to catalog_items (budget has idx_budget_items_project_tree)
CREATE INDEX IF NOT EXISTS idx_catalog_items_workspace_tree
  ON catalog_items (workspace_id, hierarchy_level, sort_order);
