-- =============================================================================
-- Vendor/subcontractor visibility of selections (JobTread "share final
-- selections with crews/subs"). A vendor sees APPROVED selections only for
-- projects where they have an active work order (same scoping as work orders),
-- with the chosen option's purchasing details. No write access.
-- =============================================================================

CREATE OR REPLACE FUNCTION public.portal_vendor_get_selections()
RETURNS TABLE(
  id uuid, project_id uuid, project_name text, name text, category text,
  location text, selected_amount numeric, option_name text, option_vendor text,
  option_sku text, option_qty numeric, approved_at timestamptz
)
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE
  v_email TEXT := LOWER(TRIM(COALESCE(auth.jwt() ->> 'email', '')));
BEGIN
  IF v_email = '' THEN RETURN; END IF;
  RETURN QUERY
  SELECT s.id, s.project_id, p.name, s.name, s.category, s.location,
         s.selected_amount, o.name, o.vendor, o.sku, o.quantity, s.approved_at
  FROM public.selections s
  JOIN public.projects p ON p.id = s.project_id
  LEFT JOIN public.selection_options o ON o.id = s.selected_option_id
  WHERE s.status = 'approved'
    AND s.project_id IN (
      SELECT wo.project_id FROM public.work_orders wo
      WHERE wo.vendor_id IS NOT NULL
        AND wo.vendor_id IN (
          SELECT vendor_id FROM public.vendor_contacts vc
          WHERE vc.is_active = TRUE
            AND LOWER(TRIM(COALESCE(vc.email, ''))) = v_email)
        AND wo.status IN ('issued','in_progress','on_hold','completed'))
  ORDER BY p.name, s.location NULLS FIRST, s.name;
END;
$$;

REVOKE ALL ON FUNCTION public.portal_vendor_get_selections() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.portal_vendor_get_selections() TO authenticated;
