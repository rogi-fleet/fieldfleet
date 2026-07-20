-- Add missing 'unit' column to budget_items table
-- This column stores the unit of measurement (e.g., 'SF', 'LF', 'EA', 'HR')

ALTER TABLE budget_items ADD COLUMN IF NOT EXISTS unit TEXT;

-- Add comment for documentation
COMMENT ON COLUMN budget_items.unit IS 'Unit of measurement (e.g., SF, LF, EA, HR)';
