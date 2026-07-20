-- Portal scoping foundation. Customer/Vendor portal users get a role template
-- that grants them module read, but until now RLS let them see every row in
-- the workspace. This migration introduces the link between an auth user
-- (workspace_members.user_id) and the external entity record they represent.

-- ==========================================================================
-- 1. Link columns. Nullable because not every contact row is a portal user —
--    only contacts who accepted a portal invite get their user_id filled in.
--    UNIQUE on user_id enforces a contact↔user 1:1 (a given auth user cannot
--    be simultaneously a portal customer for two different customer rows, or
--    a portal vendor for two different vendors).
-- ==========================================================================
ALTER TABLE public.customer_contacts
  ADD COLUMN IF NOT EXISTS user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL;
CREATE UNIQUE INDEX IF NOT EXISTS ux_customer_contacts_user_id
  ON public.customer_contacts(user_id) WHERE user_id IS NOT NULL;

ALTER TABLE public.vendor_contacts
  ADD COLUMN IF NOT EXISTS user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL;
CREATE UNIQUE INDEX IF NOT EXISTS ux_vendor_contacts_user_id
  ON public.vendor_contacts(user_id) WHERE user_id IS NOT NULL;

-- ==========================================================================
-- 2. Scope helpers — return the customer/vendor IDs the current auth user is
--    linked to as a portal member, filtered to the given workspace.
--    Used by per-table RLS clauses below.
-- ==========================================================================
CREATE OR REPLACE FUNCTION public.current_portal_customer_ids(workspace_uuid UUID)
RETURNS SETOF UUID
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT cc.customer_id
  FROM public.customer_contacts cc
  JOIN public.customers c ON c.id = cc.customer_id
  WHERE cc.user_id = auth.uid()
    AND c.workspace_id = workspace_uuid;
$$;

CREATE OR REPLACE FUNCTION public.current_portal_vendor_ids(workspace_uuid UUID)
RETURNS SETOF UUID
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT vc.vendor_id
  FROM public.vendor_contacts vc
  JOIN public.vendors v ON v.id = vc.vendor_id
  WHERE vc.user_id = auth.uid()
    AND v.workspace_id = workspace_uuid;
$$;

-- True if the current auth user is a portal customer or vendor in the given
-- workspace. Lets RLS short-circuit to "internal member" mode when false.
CREATE OR REPLACE FUNCTION public.is_external_portal_user(workspace_uuid UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.workspace_members
    WHERE workspace_id = workspace_uuid
      AND user_id = auth.uid()
      AND role::TEXT IN ('client', 'vendor')
  );
$$;
