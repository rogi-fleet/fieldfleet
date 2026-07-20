-- GC-side action for the Request-for-Bid flow: once a vendor has submitted
-- their itemized bid (document.status = 'responded'), the GC can push those
-- per-line prices into the project's budget items.
--
-- Writes each linked budget item's projected_cost and unit_cost from the
-- vendor's bid, flips the document to 'applied', overwrites each line's
-- unitPrice with the vendorBidPrice so the existing bid → PO derivation
-- (document_detail_screen.dart:2143) carries the vendor's numbers forward,
-- and records an audit row per mutation in budget_item_events.

CREATE TABLE IF NOT EXISTS public.budget_item_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id uuid NOT NULL REFERENCES public.workspaces(id) ON DELETE CASCADE,
  budget_item_id uuid NOT NULL REFERENCES public.budget_items(id) ON DELETE CASCADE,
  source_document_id uuid REFERENCES public.generated_documents(id) ON DELETE SET NULL,
  actor_id uuid,
  event_type text NOT NULL,
  previous_values jsonb,
  new_values jsonb,
  note text,
  created_at timestamptz DEFAULT NOW() NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_budget_item_events_budget_item
  ON public.budget_item_events(budget_item_id);
CREATE INDEX IF NOT EXISTS idx_budget_item_events_source_document
  ON public.budget_item_events(source_document_id);
CREATE INDEX IF NOT EXISTS idx_budget_item_events_workspace_created
  ON public.budget_item_events(workspace_id, created_at DESC);

ALTER TABLE public.budget_item_events ENABLE ROW LEVEL SECURITY;

-- Read access mirrors budget read permission. Writes only come from the
-- SECURITY DEFINER RPCs below.
DROP POLICY IF EXISTS budget_item_events_select ON public.budget_item_events;
CREATE POLICY budget_item_events_select ON public.budget_item_events
  FOR SELECT USING (
    has_workspace_module_permission(workspace_id, 'budget', 'read')
  );


CREATE OR REPLACE FUNCTION public.apply_vendor_bid_to_budget(
  p_document_id uuid
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_doc generated_documents%ROWTYPE;
  v_li jsonb;
  v_budget_item_id uuid;
  v_bid_price numeric;
  v_qty numeric;
  v_new_projected numeric;
  v_bi budget_items%ROWTYPE;
  v_actor uuid := auth.uid();
BEGIN
  SELECT * INTO v_doc FROM generated_documents WHERE id = p_document_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Document % not found', p_document_id
      USING ERRCODE = 'P0002';
  END IF;

  IF v_doc.document_type::text <> 'request_for_bid' THEN
    RAISE EXCEPTION 'Document % is not a request for bid', p_document_id
      USING ERRCODE = 'P0001';
  END IF;

  IF v_doc.status::text <> 'responded' THEN
    RAISE EXCEPTION
      'Document must be in responded status to apply to budget (current: %)',
      v_doc.status USING ERRCODE = 'P0001';
  END IF;

  IF NOT has_workspace_module_permission(
    v_doc.workspace_id, 'budget', 'write'
  ) THEN
    RAISE EXCEPTION 'Not authorized to modify budget'
      USING ERRCODE = '42501';
  END IF;

  IF NOT has_workspace_module_permission(
    v_doc.workspace_id, 'documents', 'write'
  ) THEN
    RAISE EXCEPTION 'Not authorized to modify this document'
      USING ERRCODE = '42501';
  END IF;

  FOR v_li IN SELECT * FROM jsonb_array_elements(
    COALESCE(v_doc.line_items, '[]'::jsonb)
  )
  LOOP
    v_budget_item_id := NULLIF(v_li->>'budgetItemId', '')::uuid;
    v_bid_price := NULLIF(v_li->>'vendorBidPrice', '')::numeric;
    IF v_budget_item_id IS NULL OR v_bid_price IS NULL THEN
      CONTINUE;
    END IF;

    SELECT * INTO v_bi FROM budget_items WHERE id = v_budget_item_id;
    IF NOT FOUND OR v_bi.workspace_id <> v_doc.workspace_id THEN
      CONTINUE;
    END IF;

    v_qty := COALESCE((v_li->>'quantity')::numeric, 1);
    v_new_projected := v_bid_price * v_qty;

    INSERT INTO budget_item_events (
      workspace_id, budget_item_id, source_document_id, actor_id,
      event_type, previous_values, new_values
    ) VALUES (
      v_bi.workspace_id, v_bi.id, v_doc.id, v_actor,
      'vendor_bid_applied',
      jsonb_build_object(
        'projectedCost', v_bi.projected_cost,
        'unitCost', v_bi.unit_cost
      ),
      jsonb_build_object(
        'projectedCost', v_new_projected,
        'unitCost', v_bid_price
      )
    );

    UPDATE budget_items
    SET projected_cost = v_new_projected,
        unit_cost = v_bid_price,
        updated_at = NOW()
    WHERE id = v_bi.id;
  END LOOP;

  -- Flip the document to 'applied' and overwrite each line's unitPrice with
  -- the vendor's submitted bid price, so the existing bid → PO derivation
  -- carries the vendor's numbers forward without a special case.
  UPDATE generated_documents
  SET status = 'applied',
      line_items = (
        SELECT jsonb_agg(
          CASE
            WHEN elem->>'vendorBidPrice' IS NOT NULL
              THEN jsonb_set(elem, '{unitPrice}', elem->'vendorBidPrice')
            ELSE elem
          END
        )
        FROM jsonb_array_elements(COALESCE(line_items, '[]'::jsonb)) elem
      ),
      updated_at = NOW()
  WHERE id = p_document_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.apply_vendor_bid_to_budget(uuid)
  TO authenticated;

COMMENT ON FUNCTION public.apply_vendor_bid_to_budget(uuid) IS
  'GC-facing: applies an RFB vendor bid to the linked budget items '
  '(projected_cost and unit_cost), flips the document to applied, and '
  'overwrites line_items.unitPrice with vendorBidPrice so downstream '
  'PO derivation uses the vendor''s numbers.';
