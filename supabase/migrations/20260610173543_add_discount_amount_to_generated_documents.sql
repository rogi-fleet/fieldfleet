-- M004: invoice-level discounts.
--
-- generated_documents gains a flat, pre-tax `discount_amount`. The net total is
-- `subtotal - discount_amount + tax`, where tax is charged on the discounted
-- taxable base (apportioned by the taxable share when lines are mixed).
-- `GeneratedDocument.computedGrandTotal` / `computedTaxAmount` are the single
-- source of truth every surface (preview, PDF, client portal) reads from.
--
-- Already applied to api.example.com via apply_migration; this file captures
-- it for fresh environments and version control. The live column is
-- unqualified `numeric`, matched here so prod and fresh setups are identical.

ALTER TABLE public.generated_documents
  ADD COLUMN IF NOT EXISTS discount_amount NUMERIC NOT NULL DEFAULT 0;
