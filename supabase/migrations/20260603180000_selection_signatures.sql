-- =============================================================================
-- Multiple e-signatures per selection (JobTread "collect one or multiple
-- eSignatures"). Each signer (e.g. both homeowners) gets a row. The legacy
-- selections.approved_signature_url stays as the primary approval signature;
-- this table additionally records every signer.
-- =============================================================================

CREATE TABLE IF NOT EXISTS public.selection_signatures (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  selection_id  UUID NOT NULL REFERENCES public.selections(id) ON DELETE CASCADE,
  workspace_id  UUID NOT NULL,
  signer_name   TEXT,
  signer_email  TEXT,
  signature_url TEXT NOT NULL,
  signed_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS selection_signatures_selection_idx
  ON public.selection_signatures (selection_id, signed_at);

ALTER TABLE public.selection_signatures ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS selection_signatures_member_select ON public.selection_signatures;
CREATE POLICY selection_signatures_member_select ON public.selection_signatures
  FOR SELECT USING (is_workspace_member(workspace_id));

-- Client records a signature via the portal (used at approval and for co-signers).
CREATE OR REPLACE FUNCTION public.portal_add_selection_signature(
  p_selection_id UUID,
  p_signer_name TEXT,
  p_signer_email TEXT,
  p_signature_url TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  normalized_email TEXT := LOWER(TRIM(COALESCE(auth.jwt() ->> 'email', '')));
  v_workspace UUID;
BEGIN
  IF normalized_email = '' THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;
  IF COALESCE(TRIM(p_signature_url), '') = '' THEN
    RAISE EXCEPTION 'Signature required';
  END IF;

  SELECT s.workspace_id INTO v_workspace
    FROM selections s
    JOIN projects p ON p.id = s.project_id
    JOIN customer_contacts cc ON cc.customer_id = p.client_id
   WHERE s.id = p_selection_id
     AND cc.is_active = TRUE
     AND LOWER(TRIM(COALESCE(cc.email, ''))) = normalized_email
   LIMIT 1;
  IF v_workspace IS NULL THEN
    RAISE EXCEPTION 'Selection not found or access denied';
  END IF;

  INSERT INTO selection_signatures
    (selection_id, workspace_id, signer_name, signer_email, signature_url)
  VALUES
    (p_selection_id, v_workspace, NULLIF(TRIM(COALESCE(p_signer_name,'')),''),
     COALESCE(NULLIF(TRIM(COALESCE(p_signer_email,'')),''), normalized_email),
     p_signature_url);

  RETURN jsonb_build_object('success', true);
END;
$$;

REVOKE ALL ON FUNCTION public.portal_add_selection_signature(UUID, TEXT, TEXT, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.portal_add_selection_signature(UUID, TEXT, TEXT, TEXT) TO authenticated;
