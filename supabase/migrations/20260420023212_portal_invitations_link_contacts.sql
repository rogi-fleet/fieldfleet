-- Portal invitations need to carry the contact record they're issued
-- against so that when the invitee accepts, the accept RPC can stamp the
-- new auth user_id onto customer_contacts.user_id or vendor_contacts.user_id.
-- Without this link the portal-scoped RLS we added sees the user as a
-- portal member linked to no entity → their portal shows nothing.

ALTER TABLE public.workspace_invitations
  ADD COLUMN IF NOT EXISTS portal_customer_contact_id UUID
    REFERENCES public.customer_contacts(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS portal_vendor_contact_id UUID
    REFERENCES public.vendor_contacts(id) ON DELETE SET NULL,
  ADD CONSTRAINT workspace_invitations_portal_target_unique
    CHECK (
      portal_customer_contact_id IS NULL
      OR portal_vendor_contact_id IS NULL
    );

CREATE INDEX IF NOT EXISTS idx_workspace_invitations_portal_customer_contact
  ON public.workspace_invitations(portal_customer_contact_id)
  WHERE portal_customer_contact_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_workspace_invitations_portal_vendor_contact
  ON public.workspace_invitations(portal_vendor_contact_id)
  WHERE portal_vendor_contact_id IS NOT NULL;

-- Update the accept RPC to stamp the invitee's user_id onto the linked
-- contact row after the workspace_member is created. Validates that the
-- contact belongs to the same workspace as the invitation to prevent a
-- forged invite from linking across workspaces.
CREATE OR REPLACE FUNCTION public.accept_workspace_invitation(invite_token TEXT)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  now_ts TIMESTAMPTZ := NOW();
  current_user_id UUID := auth.uid();
  current_user_email TEXT;
  invitation_row workspace_invitations%ROWTYPE;
  already_member BOOLEAN := FALSE;
  contact_workspace_id UUID;
BEGIN
  IF current_user_id IS NULL THEN
    RAISE EXCEPTION 'You must be signed in to accept an invitation';
  END IF;

  SELECT *
  INTO invitation_row
  FROM workspace_invitations
  WHERE token = invite_token
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Invitation not found or invalid';
  END IF;

  IF invitation_row.status <> 'pending' THEN
    RAISE EXCEPTION 'This invitation is no longer pending';
  END IF;

  IF invitation_row.expires_at < now_ts THEN
    UPDATE workspace_invitations
    SET status = 'expired'
    WHERE id = invitation_row.id;
    RAISE EXCEPTION 'This invitation has expired';
  END IF;

  SELECT LOWER(email)
  INTO current_user_email
  FROM users
  WHERE id = current_user_id;

  IF current_user_email IS NULL THEN
    RAISE EXCEPTION 'User account not found';
  END IF;

  IF current_user_email <> LOWER(invitation_row.email) THEN
    RAISE EXCEPTION 'This invitation was sent to a different email address';
  END IF;

  SELECT EXISTS (
    SELECT 1
    FROM workspace_members
    WHERE workspace_id = invitation_row.workspace_id
      AND user_id = current_user_id
  )
  INTO already_member;

  IF NOT already_member THEN
    INSERT INTO workspace_members (
      workspace_id,
      user_id,
      role,
      role_template_id,
      interface_mode,
      created_at,
      updated_at
    )
    VALUES (
      invitation_row.workspace_id,
      current_user_id,
      invitation_row.role,
      invitation_row.role_template_id,
      COALESCE(invitation_row.interface_mode, 'manager'),
      now_ts,
      now_ts
    );
  END IF;

  -- Portal contact link stamping ------------------------------------------
  IF invitation_row.portal_customer_contact_id IS NOT NULL THEN
    SELECT c.workspace_id
    INTO contact_workspace_id
    FROM customer_contacts cc
    JOIN customers c ON c.id = cc.customer_id
    WHERE cc.id = invitation_row.portal_customer_contact_id;

    IF contact_workspace_id IS DISTINCT FROM invitation_row.workspace_id THEN
      RAISE EXCEPTION 'Portal contact link belongs to a different workspace';
    END IF;

    UPDATE customer_contacts
    SET user_id = current_user_id
    WHERE id = invitation_row.portal_customer_contact_id;
  END IF;

  IF invitation_row.portal_vendor_contact_id IS NOT NULL THEN
    SELECT v.workspace_id
    INTO contact_workspace_id
    FROM vendor_contacts vc
    JOIN vendors v ON v.id = vc.vendor_id
    WHERE vc.id = invitation_row.portal_vendor_contact_id;

    IF contact_workspace_id IS DISTINCT FROM invitation_row.workspace_id THEN
      RAISE EXCEPTION 'Portal contact link belongs to a different workspace';
    END IF;

    UPDATE vendor_contacts
    SET user_id = current_user_id
    WHERE id = invitation_row.portal_vendor_contact_id;
  END IF;
  -- -----------------------------------------------------------------------

  UPDATE users
  SET active_workspace_id = invitation_row.workspace_id,
      updated_at = now_ts
  WHERE id = current_user_id;

  UPDATE workspace_invitations
  SET status = 'accepted',
      accepted_at = now_ts,
      accepted_by = current_user_id
  WHERE id = invitation_row.id;

  IF NOT already_member THEN
    PERFORM public.create_workspace_member_join_notifications(
      invitation_row.workspace_id,
      current_user_id,
      invitation_row.role::TEXT
    );
  END IF;

  RETURN jsonb_build_object(
    'invitationId', invitation_row.id,
    'workspaceId', invitation_row.workspace_id,
    'alreadyMember', already_member,
    'portalCustomerContactId', invitation_row.portal_customer_contact_id,
    'portalVendorContactId', invitation_row.portal_vendor_contact_id
  );
END;
$$;
