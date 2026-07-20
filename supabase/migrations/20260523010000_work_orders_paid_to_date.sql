-- Track paid-to-date amount on work orders so Materials and Rentals can
-- record payments and roll up Paid / Remaining to the budget the same
-- way Subcontracts already do.
--
-- Already applied via the Supabase MCP on 2026-05-23; persisted as a
-- migration file so fresh environments and production deploys pick it up.

ALTER TABLE public.work_orders
  ADD COLUMN IF NOT EXISTS paid_to_date numeric NOT NULL DEFAULT 0;
