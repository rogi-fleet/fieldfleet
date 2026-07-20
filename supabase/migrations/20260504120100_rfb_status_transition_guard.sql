-- Guard the request_for_bid status state machine at the database level.
--
-- The apply_vendor_bid_to_budget() RPC validates that a document is in
-- 'responded' status before flipping it to 'applied' and pushing prices into
-- budget items. But any client with documents:write can call
-- generated_documents.update() directly and set status='applied' on an RFB
-- without ever going through the RPC, bypassing that check and potentially
-- producing budgets that look like a vendor bid was applied when none was.
--
-- This trigger enforces the state machine at the table level: an RFB can
-- only transition into 'applied' from 'responded'. The
-- apply_vendor_bid_to_budget() RPC continues to work because it reads the
-- row in 'responded' state before issuing the UPDATE.

CREATE OR REPLACE FUNCTION public.enforce_rfb_status_transitions()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  IF NEW.document_type::text = 'request_for_bid'
     AND NEW.status::text = 'applied'
     AND COALESCE(OLD.status::text, '') <> 'responded' THEN
    RAISE EXCEPTION
      'request_for_bid must be in responded status before being applied (current: %)',
      OLD.status
      USING ERRCODE = 'P0001';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS rfb_status_transitions ON public.generated_documents;
CREATE TRIGGER rfb_status_transitions
  BEFORE UPDATE OF status ON public.generated_documents
  FOR EACH ROW
  WHEN (NEW.document_type::text = 'request_for_bid')
  EXECUTE FUNCTION public.enforce_rfb_status_transitions();

COMMENT ON FUNCTION public.enforce_rfb_status_transitions() IS
  'Prevents request_for_bid documents from transitioning to applied status '
  'except from responded. Backstops the apply_vendor_bid_to_budget() RPC '
  'in case clients update generated_documents.status directly.';
