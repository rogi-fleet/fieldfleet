-- Phase D polish for multi-vendor bidding:
--
--   1. award_bid_package and cancel_bid_package now mirror the child-doc
--      status transitions onto the linked bid_requests row so the vendor
--      portal (which reads bid_requests) shows 'declined' / 'expired'
--      after an award / cancel. Without this mirror the vendor keeps
--      seeing their old 'responded' tile indefinitely.
--
--   2. expire_stale_bid_packages() — walks packages in 'sent' state whose
--      due_date has passed, transitions them and their still-open child
--      docs. Intended for periodic invocation (Supabase Edge Function
--      cron or a nightly app-side poll); pg_cron isn't installed on this
--      project so we don't schedule it here.

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
  v_loser generated_documents%ROWTYPE;
  v_loser_id uuid;
BEGIN
  SELECT * INTO v_pkg FROM bid_packages WHERE id = p_package_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Bid package % not found', p_package_id USING ERRCODE = 'P0002';
  END IF;

  IF v_pkg.status = 'awarded' THEN
    IF v_pkg.awarded_document_id = p_winning_document_id THEN
      RETURN;
    END IF;
    RAISE EXCEPTION 'Package already awarded to a different document (%); refusing to re-award',
      v_pkg.awarded_document_id USING ERRCODE = 'P0001';
  END IF;

  IF v_pkg.status = 'cancelled' THEN
    RAISE EXCEPTION 'Cancelled packages cannot be awarded' USING ERRCODE = 'P0001';
  END IF;

  IF NOT has_workspace_module_permission(v_pkg.workspace_id, 'bid_requests', 'write') THEN
    RAISE EXCEPTION 'Not authorized to award this package' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_winner FROM generated_documents
    WHERE id = p_winning_document_id AND bid_package_id = p_package_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Document % is not part of package %',
      p_winning_document_id, p_package_id USING ERRCODE = 'P0001';
  END IF;

  IF v_winner.status::text <> 'responded' THEN
    RAISE EXCEPTION 'Winning document must be in responded status (current: %)',
      v_winner.status USING ERRCODE = 'P0001';
  END IF;

  PERFORM apply_vendor_bid_to_budget(p_winning_document_id);

  -- Losers who had responded: document → not_selected, bid_requests → declined.
  FOR v_loser IN
    SELECT * FROM generated_documents
    WHERE bid_package_id = p_package_id
      AND id <> p_winning_document_id
      AND status::text = 'responded'
  LOOP
    UPDATE generated_documents
    SET status = 'not_selected', updated_at = NOW()
    WHERE id = v_loser.id;

    IF v_loser.project_id IS NOT NULL AND v_loser.vendor_id IS NOT NULL THEN
      UPDATE bid_requests
      SET status = 'declined', updated_at = NOW()
      WHERE project_id = v_loser.project_id
        AND vendor_id = v_loser.vendor_id
        AND status::text IN ('sent', 'responded');
    END IF;

    PERFORM create_bid_not_selected_notifications(v_loser.id, v_pkg.name);
  END LOOP;

  -- Non-responders: document → withdrawn, bid_requests → expired.
  FOR v_loser IN
    SELECT * FROM generated_documents
    WHERE bid_package_id = p_package_id
      AND id <> p_winning_document_id
      AND status::text IN ('draft', 'sent', 'viewed')
  LOOP
    UPDATE generated_documents
    SET status = 'withdrawn', updated_at = NOW()
    WHERE id = v_loser.id;

    IF v_loser.project_id IS NOT NULL AND v_loser.vendor_id IS NOT NULL THEN
      UPDATE bid_requests
      SET status = 'expired', updated_at = NOW()
      WHERE project_id = v_loser.project_id
        AND vendor_id = v_loser.vendor_id
        AND status::text IN ('draft', 'sent');
    END IF;
  END LOOP;

  -- Suppress unused variable warnings if the loops had zero iterations.
  v_loser_id := NULL;

  UPDATE bid_packages
  SET status = 'awarded',
      awarded_document_id = p_winning_document_id,
      updated_at = NOW()
  WHERE id = p_package_id;
END;
$$;


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
  v_child generated_documents%ROWTYPE;
BEGIN
  SELECT * INTO v_pkg FROM bid_packages WHERE id = p_package_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Bid package % not found', p_package_id USING ERRCODE = 'P0002';
  END IF;

  IF v_pkg.status IN ('awarded', 'cancelled') THEN
    RAISE EXCEPTION 'Cannot cancel package in % state', v_pkg.status USING ERRCODE = 'P0001';
  END IF;

  IF NOT has_workspace_module_permission(v_pkg.workspace_id, 'bid_requests', 'write') THEN
    RAISE EXCEPTION 'Not authorized to cancel this package' USING ERRCODE = '42501';
  END IF;

  FOR v_child IN
    SELECT * FROM generated_documents
    WHERE bid_package_id = p_package_id
      AND status::text IN ('draft', 'sent', 'viewed', 'responded')
  LOOP
    UPDATE generated_documents
    SET status = 'withdrawn', updated_at = NOW()
    WHERE id = v_child.id;

    IF v_child.project_id IS NOT NULL AND v_child.vendor_id IS NOT NULL THEN
      UPDATE bid_requests
      SET status = 'expired', updated_at = NOW()
      WHERE project_id = v_child.project_id
        AND vendor_id = v_child.vendor_id
        AND status::text IN ('draft', 'sent', 'responded');
    END IF;
  END LOOP;

  UPDATE bid_packages
  SET status = 'cancelled', updated_at = NOW()
  WHERE id = p_package_id;
END;
$$;


CREATE OR REPLACE FUNCTION public.expire_stale_bid_packages()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_pkg bid_packages%ROWTYPE;
  v_child generated_documents%ROWTYPE;
  v_expired_count INTEGER := 0;
BEGIN
  FOR v_pkg IN
    SELECT * FROM bid_packages
    WHERE status IN ('draft', 'sent')
      AND due_date IS NOT NULL
      AND due_date < NOW()
  LOOP
    FOR v_child IN
      SELECT * FROM generated_documents
      WHERE bid_package_id = v_pkg.id
        AND status::text IN ('draft', 'sent', 'viewed', 'responded')
    LOOP
      UPDATE generated_documents
      SET status = 'withdrawn', updated_at = NOW()
      WHERE id = v_child.id;

      IF v_child.project_id IS NOT NULL AND v_child.vendor_id IS NOT NULL THEN
        UPDATE bid_requests
        SET status = 'expired', updated_at = NOW()
        WHERE project_id = v_child.project_id
          AND vendor_id = v_child.vendor_id
          AND status::text IN ('draft', 'sent', 'responded');
      END IF;
    END LOOP;

    UPDATE bid_packages
    SET status = 'expired', updated_at = NOW()
    WHERE id = v_pkg.id;

    v_expired_count := v_expired_count + 1;
  END LOOP;

  RETURN v_expired_count;
END;
$$;

GRANT EXECUTE ON FUNCTION public.expire_stale_bid_packages() TO authenticated;

COMMENT ON FUNCTION public.expire_stale_bid_packages() IS
  'Sweeper: transitions bid_packages with past due_date from sent/draft to expired and withdraws outstanding child RFBs. Intended for periodic invocation (Edge Function cron or app-side nightly poll); pg_cron is not installed on this project.';
