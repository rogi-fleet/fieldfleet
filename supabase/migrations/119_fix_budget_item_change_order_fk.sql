-- Migration: Fix change_order_id FK on budget_items
--
-- The original migration (025) created change_order_id referencing the
-- change_orders table, but the app stores change orders as generated_documents
-- with document_type = 'change_order'. Update the FK to point to
-- generated_documents instead.

-- Drop the old FK constraint (references change_orders table)
ALTER TABLE budget_items
  DROP CONSTRAINT IF EXISTS budget_items_change_order_id_fkey;

-- Add new FK referencing generated_documents
ALTER TABLE budget_items
  ADD CONSTRAINT budget_items_change_order_id_fkey
  FOREIGN KEY (change_order_id) REFERENCES generated_documents(id) ON DELETE SET NULL;
