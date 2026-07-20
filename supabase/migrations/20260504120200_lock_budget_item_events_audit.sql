-- Make budget_item_events strictly append-only via RESTRICTIVE policies.
--
-- The table currently has only a permissive SELECT policy. With RLS enabled
-- and no other policies, INSERT/UPDATE/DELETE are denied for non-superusers,
-- so the table is already locked down de facto. But that protection
-- evaporates the moment someone adds a permissive UPDATE/DELETE policy in a
-- future migration. RESTRICTIVE policies are AND-combined with permissive
-- ones, so a `USING (false)` restrictive policy keeps the audit log
-- tamper-evident regardless of what permissive policies get added later.
--
-- INSERTs continue to flow via the SECURITY DEFINER RPCs
-- (apply_vendor_bid_to_budget); SECURITY DEFINER bypasses RLS, so this does
-- not break the existing write path.

DROP POLICY IF EXISTS budget_item_events_no_update ON public.budget_item_events;
CREATE POLICY budget_item_events_no_update
  ON public.budget_item_events
  AS RESTRICTIVE
  FOR UPDATE
  USING (false)
  WITH CHECK (false);

DROP POLICY IF EXISTS budget_item_events_no_delete ON public.budget_item_events;
CREATE POLICY budget_item_events_no_delete
  ON public.budget_item_events
  AS RESTRICTIVE
  FOR DELETE
  USING (false);

COMMENT ON TABLE public.budget_item_events IS
  'Append-only audit log for budget_items mutations. Inserts only via '
  'SECURITY DEFINER RPCs (e.g. apply_vendor_bid_to_budget). UPDATE and '
  'DELETE are blocked by RESTRICTIVE RLS policies.';
