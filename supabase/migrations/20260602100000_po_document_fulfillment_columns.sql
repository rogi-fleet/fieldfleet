-- ===========================================================================
-- Unify purchase orders on documents — Phase 1: schema
--
-- Adds purchase-order fulfillment + tax-fidelity columns to generated_documents
-- so that document POs can absorb the capabilities of the legacy inventory PO
-- system (expected/received dates, flat shipping, flat tax). These columns are
-- inert (NULL / 0) for every non-PO document type.
--
-- Per-line fields (inventoryItemId, quantityReceived) live inside the existing
-- `line_items` JSONB column and need no DDL — they are new keys handled by the
-- Dart DocumentLineItem model.
-- ===========================================================================

ALTER TABLE generated_documents
  ADD COLUMN IF NOT EXISTS expected_date       DATE,
  ADD COLUMN IF NOT EXISTS received_date       DATE,
  ADD COLUMN IF NOT EXISTS shipping_cost       NUMERIC(12,2) NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS tax_amount_override NUMERIC(12,2);

COMMENT ON COLUMN generated_documents.expected_date IS
  'Purchase orders: vendor-promised delivery date.';
COMMENT ON COLUMN generated_documents.received_date IS
  'Purchase orders: set when every inventory-tracked line has been fully received.';
COMMENT ON COLUMN generated_documents.shipping_cost IS
  'Purchase orders: flat shipping/freight charge added to the document total.';
COMMENT ON COLUMN generated_documents.tax_amount_override IS
  'Flat tax amount that overrides the percent-based tax_rate when set '
  '(used by POs migrated from the legacy inventory PO system).';
