-- Create a bid package and fan it out to N per-vendor RFB documents in
-- one atomic call. Each child document receives a copy of the line-item
-- template where every line carries:
--   * a fresh `id` (unique per-document so submit_vendor_bid merges land
--     in the right row)
--   * a shared `templateLineItemId` (same value across all clones,
--     generated here) so the GC's comparison grid can join columns by it.

CREATE OR REPLACE FUNCTION public.create_bid_package(
  p_workspace_id uuid,
  p_project_id uuid,
  p_name text,
  p_scope_description text,
  p_due_date timestamptz,
  p_vendor_ids uuid[],
  p_line_item_template jsonb,
  p_template_id uuid DEFAULT NULL,
  p_template_name text DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_package_id uuid;
  v_vendor_id uuid;
  v_actor uuid := auth.uid();
  v_prepared_template jsonb;
  v_prepared_clone jsonb;
  v_src jsonb;
  v_doc_line jsonb;
BEGIN
  IF p_vendor_ids IS NULL OR array_length(p_vendor_ids, 1) IS NULL THEN
    RAISE EXCEPTION 'p_vendor_ids must contain at least one vendor'
      USING ERRCODE = '22023';
  END IF;

  IF NOT has_workspace_module_permission(
    p_workspace_id, 'bid_requests', 'write'
  ) THEN
    RAISE EXCEPTION 'Not authorized to create a bid package'
      USING ERRCODE = '42501';
  END IF;

  -- 1. Normalize the template: assign a shared templateLineItemId to each
  -- item once, so all clones align on the same id. Any existing
  -- templateLineItemId on the input is preserved (useful for re-sending
  -- with the same scope).
  v_prepared_template := '[]'::jsonb;
  IF p_line_item_template IS NOT NULL
    AND jsonb_typeof(p_line_item_template) = 'array'
  THEN
    FOR v_src IN SELECT * FROM jsonb_array_elements(p_line_item_template)
    LOOP
      IF NOT (v_src ? 'templateLineItemId')
        OR v_src->>'templateLineItemId' IS NULL
      THEN
        v_src := jsonb_set(
          v_src, '{templateLineItemId}',
          to_jsonb(gen_random_uuid()::text), true
        );
      END IF;
      v_prepared_template := v_prepared_template || v_src;
    END LOOP;
  END IF;

  -- 2. Create the package.
  INSERT INTO bid_packages (
    workspace_id, project_id, name, scope_description, due_date,
    status, created_by
  ) VALUES (
    p_workspace_id, p_project_id, p_name, p_scope_description, p_due_date,
    'sent', v_actor
  )
  RETURNING id INTO v_package_id;

  -- 3. For each vendor, clone the template with fresh per-row ids and
  -- insert a request_for_bid generated_document.
  FOREACH v_vendor_id IN ARRAY p_vendor_ids
  LOOP
    v_prepared_clone := '[]'::jsonb;
    FOR v_src IN SELECT * FROM jsonb_array_elements(v_prepared_template)
    LOOP
      v_doc_line := jsonb_set(
        v_src, '{id}', to_jsonb(gen_random_uuid()::text), true
      );
      -- Strip any vendor-bid fields that might have leaked in from the
      -- caller — we only want a blank template here.
      v_doc_line := v_doc_line - 'vendorBidPrice' - 'vendorBidNote';
      v_prepared_clone := v_prepared_clone || v_doc_line;
    END LOOP;

    INSERT INTO generated_documents (
      workspace_id, project_id, document_type, status,
      template_id, template_name, vendor_id, bid_package_id,
      line_items, due_date, created_by
    ) VALUES (
      p_workspace_id, p_project_id, 'request_for_bid', 'sent',
      p_template_id, COALESCE(p_template_name, p_name), v_vendor_id,
      v_package_id, v_prepared_clone, p_due_date, v_actor
    );
  END LOOP;

  RETURN v_package_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.create_bid_package(
  uuid, uuid, text, text, timestamptz, uuid[], jsonb, uuid, text
) TO authenticated;

COMMENT ON FUNCTION public.create_bid_package(
  uuid, uuid, text, text, timestamptz, uuid[], jsonb, uuid, text
) IS
  'Creates a bid_package and fans out one request_for_bid generated_document per vendor, each with a clone of the line-item template. Template lines share a templateLineItemId across clones so the comparison grid can align rows.';
