-- =============================================================================
-- Vendor Portal RPCs + RLS additions.
--
-- Mirrors the customer portal pattern (auth.jwt() -> email matched against
-- vendor_contacts.email) for read RPCs. Action RPCs (acknowledge work order,
-- submit bill) run SECURITY DEFINER and authorize the caller by checking the
-- email-to-vendor binding.
--
-- Reuses foundation from 20260420022721_portal_scoping_foundation.sql:
--   current_portal_vendor_ids(workspace_uuid) — vendor IDs for current user
--   is_external_portal_user(workspace_uuid)   — true if logged-in user is
--                                                a portal vendor/customer
-- =============================================================================

-- ---------------------------------------------------------------------------
-- Helper: vendor IDs accessible to current user across ALL workspaces by
-- email match (does not require vendor_contacts.user_id to be linked).
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.current_portal_vendor_ids_by_email()
RETURNS SETOF UUID
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT DISTINCT vc.vendor_id
  FROM public.vendor_contacts vc
  WHERE vc.is_active = TRUE
    AND LOWER(TRIM(COALESCE(vc.email, ''))) =
        LOWER(TRIM(COALESCE(auth.jwt() ->> 'email', '')))
    AND COALESCE(LOWER(TRIM(auth.jwt() ->> 'email')), '') <> '';
$$;

REVOKE ALL ON FUNCTION public.current_portal_vendor_ids_by_email() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.current_portal_vendor_ids_by_email()
  TO authenticated;

-- ---------------------------------------------------------------------------
-- portal_vendor_can_request_access(p_email) — used pre-magic-link to verify
-- there is at least one active vendor_contact with this email.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.portal_vendor_can_request_access(
  p_email TEXT
)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.vendor_contacts vc
    WHERE vc.is_active = TRUE
      AND LOWER(TRIM(COALESCE(vc.email, ''))) =
          LOWER(TRIM(COALESCE(p_email, '')))
      AND COALESCE(LOWER(TRIM(p_email)), '') <> ''
  );
$$;

REVOKE ALL ON FUNCTION public.portal_vendor_can_request_access(TEXT)
  FROM PUBLIC;
-- Intentionally NOT granted to `anon`: this would let unauthenticated callers
-- enumerate the vendor_contacts directory by probing emails. Authenticated
-- portal users can still call it from inside the portal if needed.
GRANT EXECUTE ON FUNCTION public.portal_vendor_can_request_access(TEXT)
  TO authenticated;

-- ---------------------------------------------------------------------------
-- portal_vendor_get_vendors() — vendor records the caller can act on.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.portal_vendor_get_vendors()
RETURNS TABLE (
  id UUID,
  workspace_id UUID,
  company_name TEXT,
  contact_email TEXT,
  contact_phone TEXT,
  status TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_email TEXT := LOWER(TRIM(COALESCE(auth.jwt() ->> 'email', '')));
BEGIN
  IF v_email = '' THEN RETURN; END IF;
  RETURN QUERY
  SELECT v.id, v.workspace_id, v.company_name,
         v.contact_email, v.contact_phone,
         COALESCE(v.status::text, 'active') AS status
  FROM public.vendors v
  WHERE v.id IN (
    SELECT vendor_id FROM public.vendor_contacts vc
    WHERE vc.is_active = TRUE
      AND LOWER(TRIM(COALESCE(vc.email, ''))) = v_email
  )
  ORDER BY v.company_name;
END;
$$;

REVOKE ALL ON FUNCTION public.portal_vendor_get_vendors() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.portal_vendor_get_vendors() TO authenticated;

-- ---------------------------------------------------------------------------
-- portal_vendor_get_bid_packages() — RFB documents assigned to the vendor.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.portal_vendor_get_bid_packages()
RETURNS TABLE (
  id UUID,
  workspace_id UUID,
  project_id UUID,
  vendor_id UUID,
  template_name TEXT,
  status document_status,
  line_items JSONB,
  total_amount DECIMAL,
  sent_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ,
  project_name TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_email TEXT := LOWER(TRIM(COALESCE(auth.jwt() ->> 'email', '')));
BEGIN
  IF v_email = '' THEN RETURN; END IF;
  RETURN QUERY
  SELECT
    gd.id, gd.workspace_id, gd.project_id, gd.vendor_id,
    gd.template_name, gd.status, gd.line_items, gd.total_amount,
    gd.sent_at, gd.created_at, p.name AS project_name
  FROM public.generated_documents gd
  LEFT JOIN public.projects p ON p.id = gd.project_id
  WHERE gd.document_type::text = 'request_for_bid'
    AND gd.vendor_id IS NOT NULL
    AND gd.vendor_id IN (
      SELECT vendor_id FROM public.vendor_contacts vc
      WHERE vc.is_active = TRUE
        AND LOWER(TRIM(COALESCE(vc.email, ''))) = v_email
    )
  ORDER BY gd.created_at DESC;
END;
$$;

REVOKE ALL ON FUNCTION public.portal_vendor_get_bid_packages() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.portal_vendor_get_bid_packages()
  TO authenticated;

-- ---------------------------------------------------------------------------
-- portal_vendor_get_work_orders() — work orders assigned to the vendor.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.portal_vendor_get_work_orders()
RETURNS TABLE (
  id UUID,
  workspace_id UUID,
  project_id UUID,
  vendor_id UUID,
  number TEXT,
  title TEXT,
  description TEXT,
  scope_of_work TEXT,
  status TEXT,
  priority TEXT,
  location TEXT,
  scheduled_start TIMESTAMPTZ,
  scheduled_end TIMESTAMPTZ,
  total_amount DECIMAL,
  client_notes TEXT,
  created_at TIMESTAMPTZ,
  updated_at TIMESTAMPTZ,
  project_name TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_email TEXT := LOWER(TRIM(COALESCE(auth.jwt() ->> 'email', '')));
BEGIN
  IF v_email = '' THEN RETURN; END IF;
  RETURN QUERY
  SELECT
    wo.id, wo.workspace_id, wo.project_id, wo.vendor_id,
    wo.number, wo.title, wo.description, wo.scope_of_work,
    wo.status, wo.priority, wo.location,
    wo.scheduled_start, wo.scheduled_end,
    wo.total_amount, wo.client_notes,
    wo.created_at, wo.updated_at, p.name AS project_name
  FROM public.work_orders wo
  LEFT JOIN public.projects p ON p.id = wo.project_id
  WHERE wo.vendor_id IS NOT NULL
    AND wo.vendor_id IN (
      SELECT vendor_id FROM public.vendor_contacts vc
      WHERE vc.is_active = TRUE
        AND LOWER(TRIM(COALESCE(vc.email, ''))) = v_email
    )
    AND wo.status IN ('issued', 'in_progress', 'on_hold', 'completed')
  ORDER BY wo.created_at DESC;
END;
$$;

REVOKE ALL ON FUNCTION public.portal_vendor_get_work_orders() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.portal_vendor_get_work_orders()
  TO authenticated;

-- ---------------------------------------------------------------------------
-- portal_vendor_get_purchase_orders() — POs the vendor can bill against.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.portal_vendor_get_purchase_orders()
RETURNS TABLE (
  id UUID,
  workspace_id UUID,
  project_id UUID,
  vendor_id UUID,
  purchase_order_number TEXT,
  status po_status,
  total DECIMAL,
  due_date DATE,
  created_at TIMESTAMPTZ,
  project_name TEXT,
  billed_total DECIMAL
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_email TEXT := LOWER(TRIM(COALESCE(auth.jwt() ->> 'email', '')));
BEGIN
  IF v_email = '' THEN RETURN; END IF;
  RETURN QUERY
  SELECT
    po.id, po.workspace_id, po.project_id, po.vendor_id,
    po.purchase_order_number, po.status, po.total, po.due_date,
    po.created_at, p.name AS project_name,
    COALESCE((
      SELECT SUM(b.total) FROM public.bills b
      WHERE b.purchase_order_id = po.id
        AND b.status::text NOT IN ('void')
    ), 0)::decimal AS billed_total
  FROM public.purchase_orders po
  LEFT JOIN public.projects p ON p.id = po.project_id
  WHERE po.vendor_id IS NOT NULL
    AND po.vendor_id IN (
      SELECT vendor_id FROM public.vendor_contacts vc
      WHERE vc.is_active = TRUE
        AND LOWER(TRIM(COALESCE(vc.email, ''))) = v_email
    )
    AND po.status::text IN ('sent', 'received', 'approved')
  ORDER BY po.created_at DESC;
END;
$$;

REVOKE ALL ON FUNCTION public.portal_vendor_get_purchase_orders() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.portal_vendor_get_purchase_orders()
  TO authenticated;

-- ---------------------------------------------------------------------------
-- portal_vendor_get_bills() — bills the vendor submitted.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.portal_vendor_get_bills()
RETURNS TABLE (
  id UUID,
  workspace_id UUID,
  project_id UUID,
  vendor_id UUID,
  purchase_order_id UUID,
  bill_number TEXT,
  status bill_status,
  total DECIMAL,
  bill_date DATE,
  due_date DATE,
  notes TEXT,
  created_at TIMESTAMPTZ,
  project_name TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_email TEXT := LOWER(TRIM(COALESCE(auth.jwt() ->> 'email', '')));
BEGIN
  IF v_email = '' THEN RETURN; END IF;
  RETURN QUERY
  SELECT
    b.id, b.workspace_id, b.project_id, b.vendor_id, b.purchase_order_id,
    b.bill_number, b.status, b.total, b.bill_date, b.due_date, b.notes,
    b.created_at, p.name AS project_name
  FROM public.bills b
  LEFT JOIN public.projects p ON p.id = b.project_id
  WHERE b.vendor_id IN (
    SELECT vendor_id FROM public.vendor_contacts vc
    WHERE vc.is_active = TRUE
      AND LOWER(TRIM(COALESCE(vc.email, ''))) = v_email
  )
  ORDER BY b.created_at DESC;
END;
$$;

REVOKE ALL ON FUNCTION public.portal_vendor_get_bills() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.portal_vendor_get_bills() TO authenticated;

-- ---------------------------------------------------------------------------
-- portal_vendor_acknowledge_work_order — vendor accepts or declines a WO.
-- On accept: status issued → in_progress, started_at = NOW().
-- On decline: status → on_hold (staff must reassign).
-- Always appends a work_order_history row.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.portal_vendor_acknowledge_work_order(
  p_work_order_id UUID,
  p_accept BOOLEAN,
  p_signer_name TEXT DEFAULT NULL,
  p_note TEXT DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_email   TEXT := LOWER(TRIM(COALESCE(auth.jwt() ->> 'email', '')));
  v_wo      public.work_orders%ROWTYPE;
  v_actor   TEXT := COALESCE(NULLIF(TRIM(p_signer_name), ''), v_email);
  v_new     TEXT;
BEGIN
  IF v_email = '' THEN
    RAISE EXCEPTION 'Not authenticated' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_wo FROM public.work_orders WHERE id = p_work_order_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Work order % not found', p_work_order_id
      USING ERRCODE = 'P0002';
  END IF;

  -- Authz: caller must be an active contact of the WO's vendor.
  IF v_wo.vendor_id IS NULL OR NOT EXISTS (
    SELECT 1 FROM public.vendor_contacts vc
    WHERE vc.vendor_id = v_wo.vendor_id
      AND vc.is_active = TRUE
      AND LOWER(TRIM(COALESCE(vc.email, ''))) = v_email
  ) THEN
    RAISE EXCEPTION 'Not authorized for work order %', p_work_order_id
      USING ERRCODE = '42501';
  END IF;

  IF v_wo.status NOT IN ('issued', 'in_progress', 'on_hold') THEN
    RAISE EXCEPTION 'Work order is not in an acknowledgeable state (%)',
      v_wo.status USING ERRCODE = 'P0001';
  END IF;

  v_new := CASE WHEN p_accept THEN 'in_progress' ELSE 'on_hold' END;

  UPDATE public.work_orders
  SET status     = v_new,
      started_at = CASE
                     WHEN p_accept AND started_at IS NULL THEN NOW()
                     ELSE started_at
                   END,
      updated_at = NOW()
  WHERE id = p_work_order_id;

  INSERT INTO public.work_order_history (
    work_order_id, workspace_id, event_type, from_status, to_status,
    message, actor_name, created_at
  ) VALUES (
    p_work_order_id, v_wo.workspace_id,
    CASE WHEN p_accept THEN 'vendor_accepted' ELSE 'vendor_declined' END,
    v_wo.status, v_new,
    p_note, v_actor, NOW()
  );
END;
$$;

REVOKE ALL ON FUNCTION
  public.portal_vendor_acknowledge_work_order(UUID, BOOLEAN, TEXT, TEXT)
  FROM PUBLIC;
GRANT EXECUTE ON FUNCTION
  public.portal_vendor_acknowledge_work_order(UUID, BOOLEAN, TEXT, TEXT)
  TO authenticated;

-- ---------------------------------------------------------------------------
-- portal_vendor_submit_bill — vendor creates a bill against a PO.
-- Auto-generates a bill_number, default bill_date = today.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.portal_vendor_submit_bill(
  p_purchase_order_id UUID,
  p_amount            DECIMAL,
  p_bill_number       TEXT DEFAULT NULL,
  p_bill_date         DATE DEFAULT NULL,
  p_due_date          DATE DEFAULT NULL,
  p_notes             TEXT DEFAULT NULL,
  p_line_items        JSONB DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_email TEXT := LOWER(TRIM(COALESCE(auth.jwt() ->> 'email', '')));
  v_po    public.purchase_orders%ROWTYPE;
  v_num   TEXT;
  v_id    UUID;
BEGIN
  IF v_email = '' THEN
    RAISE EXCEPTION 'Not authenticated' USING ERRCODE = '42501';
  END IF;

  IF p_purchase_order_id IS NULL THEN
    RAISE EXCEPTION 'purchase_order_id is required' USING ERRCODE = '22023';
  END IF;
  IF p_amount IS NULL OR p_amount <= 0 THEN
    RAISE EXCEPTION 'amount must be > 0' USING ERRCODE = '22023';
  END IF;

  SELECT * INTO v_po FROM public.purchase_orders
    WHERE id = p_purchase_order_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Purchase order % not found', p_purchase_order_id
      USING ERRCODE = 'P0002';
  END IF;

  -- Authz: caller must be an active contact of the PO's vendor.
  IF NOT EXISTS (
    SELECT 1 FROM public.vendor_contacts vc
    WHERE vc.vendor_id = v_po.vendor_id
      AND vc.is_active = TRUE
      AND LOWER(TRIM(COALESCE(vc.email, ''))) = v_email
  ) THEN
    RAISE EXCEPTION 'Not authorized for purchase order %',
      p_purchase_order_id USING ERRCODE = '42501';
  END IF;

  v_num := COALESCE(
    NULLIF(TRIM(p_bill_number), ''),
    'V-' || TO_CHAR(NOW(), 'YYYYMMDD-HH24MISS')
  );

  INSERT INTO public.bills (
    workspace_id, project_id, bill_number, vendor_id, purchase_order_id,
    line_items, subtotal, tax_amount, total,
    status, bill_date, due_date, notes, created_at, updated_at
  ) VALUES (
    v_po.workspace_id, v_po.project_id, v_num, v_po.vendor_id,
    p_purchase_order_id,
    COALESCE(p_line_items, '[]'::jsonb),
    p_amount, 0, p_amount,
    'received', COALESCE(p_bill_date, NOW()::date), p_due_date,
    p_notes, NOW(), NOW()
  )
  RETURNING id INTO v_id;

  RETURN v_id;
END;
$$;

REVOKE ALL ON FUNCTION public.portal_vendor_submit_bill(
  UUID, DECIMAL, TEXT, DATE, DATE, TEXT, JSONB) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.portal_vendor_submit_bill(
  UUID, DECIMAL, TEXT, DATE, DATE, TEXT, JSONB) TO authenticated;

-- ---------------------------------------------------------------------------
-- RLS additions for the new work_orders table so portal vendors can SELECT
-- their own rows. (portal_scope_rls_policies.sql predates work_orders.)
-- ---------------------------------------------------------------------------
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'work_orders'
      AND policyname = 'work_orders_select'
  ) THEN
    DROP POLICY work_orders_select ON public.work_orders;
  END IF;
END $$;

CREATE POLICY work_orders_select ON public.work_orders
  FOR SELECT USING (
    public.has_workspace_module_permission(workspace_id, 'projects', 'read')
    AND (
      NOT public.is_external_portal_user(workspace_id)
      OR vendor_id IN (SELECT public.current_portal_vendor_ids(workspace_id))
      OR vendor_id IN (
        SELECT vc.vendor_id FROM public.vendor_contacts vc
        WHERE vc.is_active = TRUE
          AND LOWER(TRIM(COALESCE(vc.email, ''))) =
              LOWER(TRIM(COALESCE(auth.jwt() ->> 'email', '')))
      )
    )
  );

COMMENT ON FUNCTION public.portal_vendor_submit_bill(
  UUID, DECIMAL, TEXT, DATE, DATE, TEXT, JSONB) IS
  'Vendor portal: insert a bill row scoped to a PO the caller is the vendor of.';
COMMENT ON FUNCTION public.portal_vendor_acknowledge_work_order(
  UUID, BOOLEAN, TEXT, TEXT) IS
  'Vendor portal: accept (issued→in_progress) or decline (→on_hold) a WO.';
