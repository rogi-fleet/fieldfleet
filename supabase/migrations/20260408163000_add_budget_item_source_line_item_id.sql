-- Track the originating document line item for change-order budget sync.
ALTER TABLE public.budget_items
ADD COLUMN IF NOT EXISTS source_line_item_id TEXT;

CREATE INDEX IF NOT EXISTS idx_budget_items_change_order_source_line_item
ON public.budget_items(change_order_id, source_line_item_id)
WHERE change_order_id IS NOT NULL
  AND source_line_item_id IS NOT NULL;
