-- Partition work_orders into Materials and Rentals.
--
-- The Rentals segment inside a project's Purchase Orders tab is a
-- vendor-issued expense flow (rental equipment requested from a
-- third-party rental house, paid later). It reuses the work_orders
-- table — same lifecycle, line items, signatures and history — and
-- is discriminated from traditional Materials work orders by this
-- `kind` column.
--
-- Numbering is per (project_id, kind): Materials uses WO-NNN,
-- Rentals uses RNT-NNN.
--
-- Already applied via the Supabase MCP on 2026-05-23; this file
-- exists so the schema change tracks with the repo for fresh
-- environments and production parity.

ALTER TABLE public.work_orders
  ADD COLUMN IF NOT EXISTS kind text NOT NULL DEFAULT 'materials';

ALTER TABLE public.work_orders
  DROP CONSTRAINT IF EXISTS work_orders_kind_check;

ALTER TABLE public.work_orders
  ADD CONSTRAINT work_orders_kind_check
  CHECK (kind IN ('materials', 'rental'));

CREATE INDEX IF NOT EXISTS work_orders_project_kind_idx
  ON public.work_orders (project_id, kind);

-- Backfill any historical NULL rows (defensive — column is NOT NULL
-- with a default, so this is a no-op on the existing dataset).
UPDATE public.work_orders SET kind = 'materials' WHERE kind IS NULL;
