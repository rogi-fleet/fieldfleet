-- Add CHECK constraints, convert cost_type to enum, and add composite indexes
-- for the budget_items table.

-- 1. CHECK constraints on numeric fields
ALTER TABLE budget_items
  ADD CONSTRAINT chk_budget_items_quantity_non_negative
    CHECK (quantity >= 0),
  ADD CONSTRAINT chk_budget_items_unit_cost_non_negative
    CHECK (unit_cost >= 0),
  ADD CONSTRAINT chk_budget_items_unit_price_non_negative
    CHECK (unit_price >= 0),
  ADD CONSTRAINT chk_budget_items_approved_price_non_negative
    CHECK (approved_price >= 0),
  ADD CONSTRAINT chk_budget_items_projected_cost_non_negative
    CHECK (projected_cost >= 0),
  ADD CONSTRAINT chk_budget_items_committed_cost_non_negative
    CHECK (committed_cost >= 0),
  ADD CONSTRAINT chk_budget_items_final_cost_non_negative
    CHECK (final_cost >= 0),
  ADD CONSTRAINT chk_budget_items_markup_non_negative
    CHECK (markup >= 0),
  ADD CONSTRAINT chk_budget_items_holdback_percent_range
    CHECK (holdback_percent IS NULL OR (holdback_percent >= 0 AND holdback_percent <= 100)),
  ADD CONSTRAINT chk_budget_items_hierarchy_level_non_negative
    CHECK (hierarchy_level >= 0);

-- 2. Convert cost_type from text to a proper enum
CREATE TYPE budget_cost_type AS ENUM ('labor', 'material', 'other', 'subcontractor');

ALTER TABLE budget_items
  ALTER COLUMN cost_type TYPE budget_cost_type
  USING cost_type::budget_cost_type;

-- 3. Composite indexes for common tree query patterns
--    Listing all items for a project ordered by hierarchy/sort
CREATE INDEX idx_budget_items_project_tree
  ON budget_items (project_id, hierarchy_level, sort_order);

--    Loading children of a parent ordered by sort
CREATE INDEX idx_budget_items_parent_sort
  ON budget_items (parent_id, sort_order);
