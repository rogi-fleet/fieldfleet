-- Award a bid_package to a single winning child document, atomically:
--   * Apply the winner's bid to the project budget (reuses
--     apply_vendor_bid_to_budget — does the budget write, flips doc to
--     'applied', emits bid_applied notification).
--   * Transition other responded children to 'not_selected' and notify
--     each losing vendor's portal contacts.
--   * Lock the package (status = 'awarded', awarded_document_id set).
--
-- Idempotent: if the package is already awarded, returns without re-
-- applying.

-- Helper: notify vendor portal contacts for a document. Used by
-- award_bid_package for bid_not_selected events. Separate from
-- create_document_action_notifications because the recipient rule is
-- different (vendor-side instead of GC-side).
CREATE OR REPLACE FUNCTION public.create_bid_not_selected_notifications(
  p_document_id uuid,
  p_package_name text
)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  doc_row RECORD;
  inserted_count INTEGER := 0;
BEGIN
  SELECT gd.id, gd.workspace_id, gd.project_id, gd.vendor_id,
         COALESCE(NULLIF(TRIM(gd.template_name), ''), 'Bid request') AS template_name
  INTO doc_row
  FROM public.generated_documents gd
  WHERE gd.id = p_document_id LIMIT 1;

  IF NOT FOUND OR doc_row.vendor_id IS NULL THEN
    RETURN 0;
  END IF;

  INSERT INTO public.notifications (
    user_id, workspace_id, type, title, body, metadata
  )
  SELECT
    vc.user_id,
    doc_row.workspace_id,
    'document_bid_not_selected',
    'Your bid was not selected',
    'Your bid on "' || COALESCE(NULLIF(TRIM(p_package_name), ''),
                                doc_row.template_name)
      || '" was not selected for this project. Thank you for bidding.',
    jsonb_build_object(
      'target_type', 'document',
      'document_id', doc_row.id,
      'project_id', doc_row.project_id,
      'action', 'bid_not_selected',
      'deeplink_path', '/documents/' || doc_row.id::TEXT
    )
  FROM public.vendor_contacts vc
  WHERE vc.vendor_id = doc_row.vendor_id
    AND vc.user_id IS NOT NULL;

  GET DIAGNOSTICS inserted_count = ROW_COUNT;
  RETURN inserted_count;
END;
$$;

GRANT EXECUTE ON FUNCTION public.create_bid_not_selected_notifications(uuid, text)
  TO authenticated;


CREATE OR REPLACE FUNCTION public.award_bid_package(
  p_package_id uuid,
  p_winning_document_id uuid
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_pkg bid_packages%ROWTYPE;
  v_winner generated_documents%ROWTYPE;
  v_loser_id uuid;
BEGIN
  SELECT * INTO v_pkg FROM bid_packages WHERE id = p_package_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Bid package % not found', p_package_id
      USING ERRCODE = 'P0002';
  END IF;

  -- Idempotency: if already awarded to the same winner, no-op.
  IF v_pkg.status = 'awarded' THEN
    IF v_pkg.awarded_document_id = p_winning_document_id THEN
      RETURN;
    END IF;
    RAISE EXCEPTION
      'Package already awarded to a different document (%); refusing to re-award',
      v_pkg.awarded_document_id USING ERRCODE = 'P0001';
  END IF;

  IF v_pkg.status = 'cancelled' THEN
    RAISE EXCEPTION 'Cancelled packages cannot be awarded'
      USING ERRCODE = 'P0001';
  END IF;

  IF NOT has_workspace_module_permission(
    v_pkg.workspace_id, 'bid_requests', 'write'
  ) THEN
    RAISE EXCEPTION 'Not authorized to award this package'
      USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_winner FROM generated_documents
    WHERE id = p_winning_document_id
      AND bid_package_id = p_package_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION
      'Document % is not part of package %',
      p_winning_document_id, p_package_id USING ERRCODE = 'P0001';
  END IF;

  IF v_winner.status::text <> 'responded' THEN
    RAISE EXCEPTION
      'Winning document must be in responded status (current: %)',
      v_winner.status USING ERRCODE = 'P0001';
  END IF;

  -- 1. Apply the winner to the budget (this also emits bid_applied
  -- notification and flips the doc to 'applied').
  PERFORM apply_vendor_bid_to_budget(p_winning_document_id);

  -- 2. Transition every other child doc in the package that has
  -- responded to 'not_selected' and notify their vendor contacts.
  FOR v_loser_id IN
    SELECT id FROM generated_documents
    WHERE bid_package_id = p_package_id
      AND id <> p_winning_document_id
      AND status::text = 'responded'
  LOOP
    UPDATE generated_documents
    SET status = 'not_selected', updated_at = NOW()
    WHERE id = v_loser_id;

    PERFORM create_bid_not_selected_notifications(v_loser_id, v_pkg.name);
  END LOOP;

  -- 3. Non-responders get 'withdrawn' so the vendor sees the package is
  -- closed but no "you lost" notification fires.
  UPDATE generated_documents
  SET status = 'withdrawn', updated_at = NOW()
  WHERE bid_package_id = p_package_id
    AND id <> p_winning_document_id
    AND status::text IN ('draft', 'sent', 'viewed');

  -- 4. Lock the package.
  UPDATE bid_packages
  SET status = 'awarded',
      awarded_document_id = p_winning_document_id,
      updated_at = NOW()
  WHERE id = p_package_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.award_bid_package(uuid, uuid)
  TO authenticated;

COMMENT ON FUNCTION public.award_bid_package(uuid, uuid) IS
  'Awards a bid_package to one winning child document. Wraps apply_vendor_bid_to_budget, transitions losers to not_selected/withdrawn, and notifies losing vendors. Idempotent on the same winner.';


-- Cancel a bid package before any award. Transitions all children to
-- 'withdrawn'. Allowed from draft/sent states only.
CREATE OR REPLACE FUNCTION public.cancel_bid_package(
  p_package_id uuid,
  p_reason text DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_pkg bid_packages%ROWTYPE;
BEGIN
  SELECT * INTO v_pkg FROM bid_packages WHERE id = p_package_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Bid package % not found', p_package_id
      USING ERRCODE = 'P0002';
  END IF;

  IF v_pkg.status IN ('awarded', 'cancelled') THEN
    RAISE EXCEPTION
      'Cannot cancel package in % state', v_pkg.status
      USING ERRCODE = 'P0001';
  END IF;

  IF NOT has_workspace_module_permission(
    v_pkg.workspace_id, 'bid_requests', 'write'
  ) THEN
    RAISE EXCEPTION 'Not authorized to cancel this package'
      USING ERRCODE = '42501';
  END IF;

  UPDATE generated_documents
  SET status = 'withdrawn', updated_at = NOW()
  WHERE bid_package_id = p_package_id
    AND status::text IN ('draft', 'sent', 'viewed', 'responded');

  UPDATE bid_packages
  SET status = 'cancelled', updated_at = NOW()
  WHERE id = p_package_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.cancel_bid_package(uuid, text)
  TO authenticated;
