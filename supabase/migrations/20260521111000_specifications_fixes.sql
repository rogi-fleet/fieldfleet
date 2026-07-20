-- Architect-driven hardening for the spec module:
--   1. spec_book_lock_check only blocked title/description/version edits on
--      locked books. A user could flip status signed -> draft directly to
--      bypass the lock. Restrict status transitions: any status change
--      must originate from a SECURITY DEFINER RPC, signalled via a
--      transaction-local GUC `app.spec_internal`.
--   2. spec_signoffs was mutable/deletable via the FOR ALL policy. Restrict
--      to insert+select only.
--   3. spec_sections.parent_id had no constraint that the parent belonged
--      to the same book — sections could be re-parented across books.
--      Add a BEFORE INSERT/UPDATE trigger enforcing same-book parent.

-- ---------------------------------------------------------------------------
-- 1. Lock status transitions on spec_books unless inside an RPC.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.spec_book_lock_check()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE v_internal TEXT;
BEGIN
  BEGIN
    v_internal := current_setting('app.spec_internal', true);
  EXCEPTION WHEN OTHERS THEN
    v_internal := NULL;
  END;

  IF TG_OP = 'UPDATE' THEN
    -- Status / lifecycle timestamps may only change inside a SECURITY DEFINER RPC.
    IF v_internal IS DISTINCT FROM 'on' THEN
      IF NEW.status IS DISTINCT FROM OLD.status
         OR NEW.issued_at IS DISTINCT FROM OLD.issued_at
         OR NEW.signed_at IS DISTINCT FROM OLD.signed_at
         OR NEW.superseded_at IS DISTINCT FROM OLD.superseded_at
         OR NEW.version IS DISTINCT FROM OLD.version
         OR NEW.previous_book_id IS DISTINCT FROM OLD.previous_book_id THEN
        RAISE EXCEPTION
          'Status, version, and lifecycle fields can only change via spec_book RPCs.';
      END IF;
    END IF;

    -- Title/description always frozen once the book is locked.
    IF OLD.status IN ('signed', 'superseded')
       AND (NEW.title IS DISTINCT FROM OLD.title
            OR NEW.description IS DISTINCT FROM OLD.description) THEN
      RAISE EXCEPTION 'Locked spec book — title/description are frozen.';
    END IF;
  END IF;

  NEW.updated_at := NOW();
  RETURN NEW;
END;
$$;

-- Re-create RPCs with the internal flag set for the txn duration.
CREATE OR REPLACE FUNCTION public.spec_book_issue(p_book_id UUID)
RETURNS public.spec_books
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_book public.spec_books;
BEGIN
  SELECT * INTO v_book FROM public.spec_books WHERE id = p_book_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Spec book not found'; END IF;
  IF NOT public.is_workspace_member(v_book.workspace_id) THEN
    RAISE EXCEPTION 'Not authorized';
  END IF;
  IF v_book.status <> 'draft' THEN
    RAISE EXCEPTION 'Only draft books can be issued (current: %)', v_book.status;
  END IF;
  PERFORM set_config('app.spec_internal', 'on', true);
  UPDATE public.spec_books
     SET status = 'issued', issued_at = NOW()
   WHERE id = p_book_id
   RETURNING * INTO v_book;
  RETURN v_book;
END;
$$;

CREATE OR REPLACE FUNCTION public.spec_book_sign_off(
  p_book_id        UUID,
  p_signer_name    TEXT,
  p_signer_email   TEXT DEFAULT NULL,
  p_signer_role    TEXT DEFAULT NULL,
  p_signature_text TEXT DEFAULT NULL,
  p_notes          TEXT DEFAULT NULL
) RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_book public.spec_books;
  v_id UUID;
BEGIN
  IF p_signer_name IS NULL OR length(trim(p_signer_name)) = 0 THEN
    RAISE EXCEPTION 'Signer name is required';
  END IF;
  SELECT * INTO v_book FROM public.spec_books WHERE id = p_book_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Spec book not found'; END IF;
  IF NOT public.is_workspace_member(v_book.workspace_id) THEN
    RAISE EXCEPTION 'Not authorized';
  END IF;
  IF v_book.status NOT IN ('draft', 'issued') THEN
    RAISE EXCEPTION 'Cannot sign book in status %', v_book.status;
  END IF;

  PERFORM set_config('app.spec_internal', 'on', true);

  INSERT INTO public.spec_signoffs (
    workspace_id, book_id, version_at_sign,
    signer_name, signer_email, signer_role, signature_text, notes, recorded_by
  ) VALUES (
    v_book.workspace_id, v_book.id, v_book.version,
    p_signer_name, p_signer_email, p_signer_role, p_signature_text, p_notes,
    auth.uid()
  ) RETURNING id INTO v_id;

  UPDATE public.spec_books
     SET status = 'signed', signed_at = NOW()
   WHERE id = p_book_id;

  RETURN v_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.spec_book_new_version(p_source_id UUID)
RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_src        public.spec_books;
  v_new_id     UUID;
  v_next_ver   INT;
  v_section    RECORD;
  v_new_sec_id UUID;
  v_id_map     JSONB := '{}'::jsonb;
BEGIN
  SELECT * INTO v_src FROM public.spec_books WHERE id = p_source_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Source spec book not found'; END IF;
  IF NOT public.is_workspace_member(v_src.workspace_id) THEN
    RAISE EXCEPTION 'Not authorized';
  END IF;

  SELECT COALESCE(MAX(version), 0) + 1
    INTO v_next_ver
    FROM public.spec_books WHERE project_id = v_src.project_id;

  PERFORM set_config('app.spec_internal', 'on', true);

  INSERT INTO public.spec_books (
    workspace_id, project_id, title, description, version,
    status, previous_book_id, created_by
  ) VALUES (
    v_src.workspace_id, v_src.project_id, v_src.title, v_src.description,
    v_next_ver, 'draft', v_src.id, auth.uid()
  ) RETURNING id INTO v_new_id;

  FOR v_section IN
    WITH RECURSIVE tree AS (
      SELECT id, parent_id, code, title, body, sort_order, 0 AS depth
        FROM public.spec_sections WHERE book_id = p_source_id AND parent_id IS NULL
      UNION ALL
      SELECT s.id, s.parent_id, s.code, s.title, s.body, s.sort_order, t.depth + 1
        FROM public.spec_sections s JOIN tree t ON s.parent_id = t.id
        WHERE s.book_id = p_source_id
    )
    SELECT * FROM tree ORDER BY depth, sort_order
  LOOP
    INSERT INTO public.spec_sections (
      workspace_id, book_id, parent_id, code, title, body, sort_order
    ) VALUES (
      v_src.workspace_id, v_new_id,
      CASE WHEN v_section.parent_id IS NULL THEN NULL
           ELSE (v_id_map ->> v_section.parent_id::text)::uuid END,
      v_section.code, v_section.title, v_section.body, v_section.sort_order
    ) RETURNING id INTO v_new_sec_id;
    v_id_map := v_id_map || jsonb_build_object(v_section.id::text, v_new_sec_id::text);
  END LOOP;

  INSERT INTO public.spec_items (
    workspace_id, book_id, section_id, item_no, description,
    manufacturer, model, qty, unit, notes, sort_order
  )
  SELECT v_src.workspace_id, v_new_id,
         (v_id_map ->> i.section_id::text)::uuid,
         i.item_no, i.description, i.manufacturer, i.model,
         i.qty, i.unit, i.notes, i.sort_order
    FROM public.spec_items i WHERE i.book_id = p_source_id;

  UPDATE public.spec_books
     SET status = 'superseded', superseded_at = NOW()
   WHERE id = p_source_id AND status IN ('issued', 'signed');

  RETURN v_new_id;
END;
$$;

-- ---------------------------------------------------------------------------
-- 2. spec_signoffs: insert + select only.
-- ---------------------------------------------------------------------------
DROP POLICY IF EXISTS spec_signoffs_all ON public.spec_signoffs;
CREATE POLICY spec_signoffs_select ON public.spec_signoffs
  FOR SELECT USING (public.is_workspace_member(workspace_id));
CREATE POLICY spec_signoffs_insert ON public.spec_signoffs
  FOR INSERT WITH CHECK (public.is_workspace_member(workspace_id));

-- ---------------------------------------------------------------------------
-- 3. spec_sections: enforce parent_id is in the same book.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.spec_section_check_parent()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE v_parent_book UUID;
BEGIN
  IF NEW.parent_id IS NOT NULL THEN
    SELECT book_id INTO v_parent_book
      FROM public.spec_sections WHERE id = NEW.parent_id;
    IF v_parent_book IS NULL THEN
      RAISE EXCEPTION 'Parent section not found';
    END IF;
    IF v_parent_book <> NEW.book_id THEN
      RAISE EXCEPTION
        'Parent section belongs to a different spec book';
    END IF;
    IF NEW.parent_id = NEW.id THEN
      RAISE EXCEPTION 'Section cannot be its own parent';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_spec_section_parent_check ON public.spec_sections;
CREATE TRIGGER trg_spec_section_parent_check
  BEFORE INSERT OR UPDATE ON public.spec_sections
  FOR EACH ROW EXECUTE FUNCTION public.spec_section_check_parent();
