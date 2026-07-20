-- Vendor-facing RPC: submit an itemized bid on a Request-for-Bid document.
--
-- The RPC is SECURITY DEFINER so it can write to generated_documents (whose
-- UPDATE policy requires internal 'documents.write' module permission that
-- vendors don't have). Authorization is enforced inside the function: the
-- caller must either be an external portal user mapped to this document's
-- vendor, OR an internal user with bid_requests.write (for staff-assisted
-- submission).
--
-- Payload format for p_line_item_bids:
--   [{"id": "<line_item_uuid>", "vendorBidPrice": 1200, "vendorBidNote": "optional"}]
-- Only the two vendor-writable fields are merged into the existing
-- generated_documents.line_items JSONB — description/qty/unit/etc. are
-- preserved from the GC-authored document.

CREATE OR REPLACE FUNCTION public.submit_vendor_bid(
  p_document_id uuid,
  p_line_item_bids jsonb,
  p_overall_note text DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_doc generated_documents%ROWTYPE;
  v_bid_request bid_requests%ROWTYPE;
  v_line_items jsonb;
  v_new_line_items jsonb;
  v_li jsonb;
  v_bid jsonb;
  v_total numeric := 0;
  v_qty numeric;
  v_bid_price numeric;
BEGIN
  IF p_line_item_bids IS NULL OR jsonb_typeof(p_line_item_bids) <> 'array' THEN
    RAISE EXCEPTION 'p_line_item_bids must be a jsonb array'
      USING ERRCODE = '22023';
  END IF;

  SELECT * INTO v_doc FROM generated_documents WHERE id = p_document_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Document % not found', p_document_id
      USING ERRCODE = 'P0002';
  END IF;

  IF v_doc.document_type::text <> 'request_for_bid' THEN
    RAISE EXCEPTION 'Document % is not a request for bid', p_document_id
      USING ERRCODE = 'P0001';
  END IF;

  IF v_doc.status::text = 'applied' THEN
    RAISE EXCEPTION 'Bid has already been applied to budget and is locked'
      USING ERRCODE = 'P0001';
  END IF;

  -- Authorization: external portal vendor for this doc, or internal staff
  -- with bid_requests.write (for staff-assisted submission).
  IF NOT (
    (v_doc.vendor_id IS NOT NULL
      AND v_doc.vendor_id IN (
        SELECT current_portal_vendor_ids(v_doc.workspace_id)
      ))
    OR has_workspace_module_permission(
      v_doc.workspace_id, 'bid_requests', 'write'
    )
  ) THEN
    RAISE EXCEPTION 'Not authorized to submit a bid on document %',
      p_document_id USING ERRCODE = '42501';
  END IF;

  v_line_items := COALESCE(v_doc.line_items, '[]'::jsonb);
  v_new_line_items := '[]'::jsonb;

  FOR v_li IN SELECT * FROM jsonb_array_elements(v_line_items)
  LOOP
    -- Find a matching bid entry for this line item by id.
    FOR v_bid IN SELECT * FROM jsonb_array_elements(p_line_item_bids)
    LOOP
      IF v_bid->>'id' = v_li->>'id' THEN
        IF v_bid ? 'vendorBidPrice' THEN
          IF v_bid->>'vendorBidPrice' IS NULL THEN
            -- Explicit null clears any prior bid on this line.
            v_li := v_li - 'vendorBidPrice';
          ELSE
            v_bid_price := (v_bid->>'vendorBidPrice')::numeric;
            v_li := jsonb_set(
              v_li, '{vendorBidPrice}', to_jsonb(v_bid_price), true
            );
          END IF;
        END IF;
        IF v_bid ? 'vendorBidNote' THEN
          IF v_bid->>'vendorBidNote' IS NULL THEN
            v_li := v_li - 'vendorBidNote';
          ELSE
            v_li := jsonb_set(
              v_li, '{vendorBidNote}', v_bid->'vendorBidNote', true
            );
          END IF;
        END IF;
        EXIT;
      END IF;
    END LOOP;

    -- Accumulate the aggregate bid total from leaf items only.
    IF COALESCE(v_li->>'type', 'item') = 'item'
      AND v_li->>'vendorBidPrice' IS NOT NULL
    THEN
      v_qty := COALESCE((v_li->>'quantity')::numeric, 1);
      v_total := v_total + (v_qty * (v_li->>'vendorBidPrice')::numeric);
    END IF;

    v_new_line_items := v_new_line_items || v_li;
  END LOOP;

  UPDATE generated_documents
  SET line_items = v_new_line_items,
      status = 'responded',
      updated_at = NOW()
  WHERE id = p_document_id;

  -- Mirror the aggregate + notes onto the linked bid_requests row so the
  -- financials list views (which read vendor_bid_amount) stay consistent.
  SELECT * INTO v_bid_request FROM bid_requests
    WHERE project_id = v_doc.project_id
      AND vendor_id = v_doc.vendor_id
    ORDER BY created_at DESC
    LIMIT 1;

  IF v_bid_request.id IS NOT NULL THEN
    UPDATE bid_requests
    SET vendor_bid_amount = v_total,
        vendor_notes = p_overall_note,
        status = 'responded',
        response_date = NOW(),
        updated_at = NOW()
    WHERE id = v_bid_request.id;
  END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION public.submit_vendor_bid(uuid, jsonb, text)
  TO authenticated;

COMMENT ON FUNCTION public.submit_vendor_bid(uuid, jsonb, text) IS
  'Vendor-facing: merges per-line bid prices into a request-for-bid '
  'document and mirrors the aggregate onto bid_requests. Authorization: '
  'external portal vendor assigned to the document, or internal user '
  'with bid_requests.write.';
