-- Snapshot of approved quantity/unit price at the time a linked document
-- (quotation, service agreement, work authorization, etc.) was approved.
-- Once approved_at is set, approved_price is a frozen contract total and
-- must not be recomputed from live quantity * unit_price. approved_quantity
-- and approved_unit_price let the UI surface variance vs. current values.

ALTER TABLE public.budget_items
  ADD COLUMN IF NOT EXISTS approved_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS approved_quantity NUMERIC,
  ADD COLUMN IF NOT EXISTS approved_unit_price NUMERIC;

CREATE INDEX IF NOT EXISTS idx_budget_items_approved_at
  ON public.budget_items(project_id, approved_at)
  WHERE approved_at IS NOT NULL;

-- Backfill: any budget item already linked to an approved or signed document
-- is contracted — freeze its current qty/unit_price as the approval snapshot.
-- Uses the earliest approval/signature across linked docs so the first
-- approval becomes the contract (later ones are change orders).
WITH first_approval AS (
  SELECT
    bdl.budget_item_id,
    MIN(COALESCE(gd.approved_at, gd.signed_at)) AS approved_at
  FROM public.budget_document_links bdl
  JOIN public.generated_documents gd
    ON gd.id = bdl.generated_document_id
  WHERE gd.status IN ('approved', 'signed')
    AND COALESCE(gd.approved_at, gd.signed_at) IS NOT NULL
  GROUP BY bdl.budget_item_id
)
UPDATE public.budget_items bi
SET
  approved_at = fa.approved_at,
  approved_quantity = bi.quantity,
  approved_unit_price = bi.unit_price
FROM first_approval fa
WHERE bi.id = fa.budget_item_id
  AND bi.approved_at IS NULL;
