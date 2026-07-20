-- Migration: Add source type and holdback fields to budget_items
-- This enables Change Orders, Upgrades & Options, and Holdback view modes

-- ============================================================================
-- NEW ENUMS
-- ============================================================================

-- Budget item source type (base scope, change order, or upgrade)
DO $$ BEGIN
  CREATE TYPE budget_item_source AS ENUM ('base', 'change_order', 'upgrade');
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- Upgrade status for tracking offered/accepted/declined upgrades
DO $$ BEGIN
  CREATE TYPE upgrade_status AS ENUM ('offered', 'accepted', 'declined');
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- ============================================================================
-- ALTER BUDGET_ITEMS TABLE
-- ============================================================================

-- Source tracking
ALTER TABLE budget_items ADD COLUMN IF NOT EXISTS source_type budget_item_source DEFAULT 'base';
ALTER TABLE budget_items ADD COLUMN IF NOT EXISTS change_order_id UUID REFERENCES change_orders(id) ON DELETE SET NULL;
ALTER TABLE budget_items ADD COLUMN IF NOT EXISTS upgrade_status upgrade_status;

-- Holdback / Retention tracking
-- Holdback is calculated as a percentage of approved_price
ALTER TABLE budget_items ADD COLUMN IF NOT EXISTS holdback_percent DECIMAL(5,2);
ALTER TABLE budget_items ADD COLUMN IF NOT EXISTS holdback_released BOOLEAN DEFAULT FALSE;
ALTER TABLE budget_items ADD COLUMN IF NOT EXISTS holdback_released_date TIMESTAMPTZ;

-- ============================================================================
-- INDEXES
-- ============================================================================

-- Index for filtering by source type (common in view modes)
CREATE INDEX IF NOT EXISTS idx_budget_items_source_type ON budget_items(project_id, source_type);

-- Index for finding items linked to a specific change order
CREATE INDEX IF NOT EXISTS idx_budget_items_change_order ON budget_items(change_order_id)
  WHERE change_order_id IS NOT NULL;

-- Index for upgrade status filtering
CREATE INDEX IF NOT EXISTS idx_budget_items_upgrade_status ON budget_items(project_id, upgrade_status)
  WHERE source_type = 'upgrade';

-- Index for holdback queries
CREATE INDEX IF NOT EXISTS idx_budget_items_holdback ON budget_items(project_id, holdback_released)
  WHERE holdback_percent IS NOT NULL AND holdback_percent > 0;

-- ============================================================================
-- COMMENTS
-- ============================================================================

COMMENT ON COLUMN budget_items.source_type IS 'Origin of budget item: base (original contract), change_order (approved CO), or upgrade (optional add-on)';
COMMENT ON COLUMN budget_items.change_order_id IS 'Reference to change_orders table if this item came from a CO';
COMMENT ON COLUMN budget_items.upgrade_status IS 'For upgrades: offered (pending), accepted (in contract), declined (not included)';
COMMENT ON COLUMN budget_items.holdback_percent IS 'Percentage of approved_price held back until conditions met (retention)';
COMMENT ON COLUMN budget_items.holdback_released IS 'Whether the holdback has been released for collection';
COMMENT ON COLUMN budget_items.holdback_released_date IS 'Timestamp when holdback was released';
