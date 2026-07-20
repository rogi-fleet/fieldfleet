-- Harden the role-template linkage: ensure role_template_id always refers to
-- a template belonging to the same workspace as the invitation / membership.
--
-- Context:
--   workspace_invitations.role_template_id and workspace_members.role_template_id
--   are FKs to workspace_role_templates(id), but the FK alone does not verify
--   workspace match. This adds a row-level guard so a template from workspace A
--   cannot be attached to a membership/invitation in workspace B.
--
-- Also hardens accept_workspace_invitation to re-validate the match at
-- acceptance time (defense in depth).

CREATE OR REPLACE FUNCTION public.validate_role_template_workspace_match()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  template_workspace_id UUID;
BEGIN
  IF NEW.role_template_id IS NULL THEN
    RETURN NEW;
  END IF;

  SELECT workspace_id
  INTO template_workspace_id
  FROM workspace_role_templates
  WHERE id = NEW.role_template_id;

  IF template_workspace_id IS NULL THEN
    RAISE EXCEPTION 'role_template_id % does not exist', NEW.role_template_id;
  END IF;

  IF template_workspace_id <> NEW.workspace_id THEN
    RAISE EXCEPTION
      'role_template_id % belongs to workspace %, not %',
      NEW.role_template_id, template_workspace_id, NEW.workspace_id;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_validate_role_template_workspace_match_invitations
  ON public.workspace_invitations;
CREATE TRIGGER trg_validate_role_template_workspace_match_invitations
  BEFORE INSERT OR UPDATE OF role_template_id, workspace_id
  ON public.workspace_invitations
  FOR EACH ROW
  EXECUTE FUNCTION public.validate_role_template_workspace_match();

DROP TRIGGER IF EXISTS trg_validate_role_template_workspace_match_members
  ON public.workspace_members;
CREATE TRIGGER trg_validate_role_template_workspace_match_members
  BEFORE INSERT OR UPDATE OF role_template_id, workspace_id
  ON public.workspace_members
  FOR EACH ROW
  EXECUTE FUNCTION public.validate_role_template_workspace_match();

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
  template_workspace_id UUID;
  effective_role_template_id UUID;
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

  effective_role_template_id := invitation_row.role_template_id;
  IF effective_role_template_id IS NOT NULL THEN
    SELECT workspace_id
    INTO template_workspace_id
    FROM workspace_role_templates
    WHERE id = effective_role_template_id;

    IF template_workspace_id IS DISTINCT FROM invitation_row.workspace_id THEN
      RAISE EXCEPTION
        'Invitation role template does not belong to the invited workspace';
    END IF;
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
      effective_role_template_id,
      COALESCE(invitation_row.interface_mode, 'manager'),
      now_ts,
      now_ts
    );
  END IF;

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
