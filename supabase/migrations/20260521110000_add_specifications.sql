-- Specifications module: structured spec books per project, version control,
-- client sign-off.
--
-- Model:
--   spec_books    – one per (project, version). Status lifecycle:
--                   draft -> issued -> signed -> superseded
--   spec_sections – hierarchical sections under a book (CSI-style).
--   spec_items    – line items inside a section (product, qty, unit, …).
--   spec_signoffs – immutable record of a client sign-off on a book.

-- ---------------------------------------------------------------------------
-- Enums
-- ---------------------------------------------------------------------------
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'spec_book_status') THEN
    CREATE TYPE spec_book_status AS ENUM
      ('draft', 'issued', 'signed', 'superseded');
  END IF;
END $$;

-- ---------------------------------------------------------------------------
-- spec_books
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.spec_books (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id      UUID NOT NULL REFERENCES public.workspaces(id) ON DELETE CASCADE,
  project_id        UUID NOT NULL REFERENCES public.projects(id) ON DELETE CASCADE,
  title             TEXT NOT NULL,
  description       TEXT,
  version           INT  NOT NULL DEFAULT 1,
  status            spec_book_status NOT NULL DEFAULT 'draft',
  previous_book_id  UUID REFERENCES public.spec_books(id) ON DELETE SET NULL,
  issued_at         TIMESTAMPTZ,
  signed_at         TIMESTAMPTZ,
  superseded_at     TIMESTAMPTZ,
  created_by        UUID REFERENCES auth.users(id),
  created_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (project_id, version)
);

CREATE INDEX IF NOT EXISTS idx_spec_books_project ON public.spec_books(project_id);
CREATE INDEX IF NOT EXISTS idx_spec_books_workspace ON public.spec_books(workspace_id);

-- ---------------------------------------------------------------------------
-- spec_sections (hierarchical)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.spec_sections (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id  UUID NOT NULL,
  book_id       UUID NOT NULL REFERENCES public.spec_books(id) ON DELETE CASCADE,
  parent_id     UUID REFERENCES public.spec_sections(id) ON DELETE CASCADE,
  code          TEXT,
  title         TEXT NOT NULL,
  body          TEXT,
  sort_order    INT NOT NULL DEFAULT 0,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_spec_sections_book ON public.spec_sections(book_id);
CREATE INDEX IF NOT EXISTS idx_spec_sections_parent ON public.spec_sections(parent_id);

-- ---------------------------------------------------------------------------
-- spec_items
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.spec_items (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id  UUID NOT NULL,
  book_id       UUID NOT NULL REFERENCES public.spec_books(id) ON DELETE CASCADE,
  section_id    UUID NOT NULL REFERENCES public.spec_sections(id) ON DELETE CASCADE,
  item_no       TEXT,
  description   TEXT NOT NULL,
  manufacturer  TEXT,
  model         TEXT,
  qty           NUMERIC(12,2),
  unit          TEXT,
  notes         TEXT,
  sort_order    INT NOT NULL DEFAULT 0,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_spec_items_section ON public.spec_items(section_id);
CREATE INDEX IF NOT EXISTS idx_spec_items_book ON public.spec_items(book_id);

-- ---------------------------------------------------------------------------
-- spec_signoffs (append-only)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.spec_signoffs (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id    UUID NOT NULL,
  book_id         UUID NOT NULL REFERENCES public.spec_books(id) ON DELETE CASCADE,
  version_at_sign INT  NOT NULL,
  signer_name     TEXT NOT NULL,
  signer_email    TEXT,
  signer_role     TEXT,
  signature_text  TEXT,
  signed_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  ip_address      TEXT,
  user_agent      TEXT,
  recorded_by     UUID REFERENCES auth.users(id),
  notes           TEXT
);

CREATE INDEX IF NOT EXISTS idx_spec_signoffs_book ON public.spec_signoffs(book_id);

-- ---------------------------------------------------------------------------
-- Workspace-id sync triggers (mirror parent book.workspace_id onto children
-- so RLS checks never depend on caller-supplied values).
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.spec_set_workspace_from_book()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE v_ws UUID;
BEGIN
  SELECT workspace_id INTO v_ws FROM public.spec_books WHERE id = NEW.book_id;
  IF v_ws IS NULL THEN RAISE EXCEPTION 'spec book not found'; END IF;
  NEW.workspace_id := v_ws;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_spec_sections_ws ON public.spec_sections;
CREATE TRIGGER trg_spec_sections_ws BEFORE INSERT OR UPDATE
  ON public.spec_sections FOR EACH ROW
  EXECUTE FUNCTION public.spec_set_workspace_from_book();

DROP TRIGGER IF EXISTS trg_spec_items_ws ON public.spec_items;
CREATE TRIGGER trg_spec_items_ws BEFORE INSERT OR UPDATE
  ON public.spec_items FOR EACH ROW
  EXECUTE FUNCTION public.spec_set_workspace_from_book();

DROP TRIGGER IF EXISTS trg_spec_signoffs_ws ON public.spec_signoffs;
CREATE TRIGGER trg_spec_signoffs_ws BEFORE INSERT OR UPDATE
  ON public.spec_signoffs FOR EACH ROW
  EXECUTE FUNCTION public.spec_set_workspace_from_book();

-- ---------------------------------------------------------------------------
-- Lock signed/superseded books from edits.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.spec_block_if_locked()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE
  v_status spec_book_status;
  v_book_id UUID;
BEGIN
  v_book_id := COALESCE(NEW.book_id, OLD.book_id);
  SELECT status INTO v_status FROM public.spec_books WHERE id = v_book_id;
  IF v_status IN ('signed', 'superseded') THEN
    RAISE EXCEPTION 'Spec book is % and cannot be modified. Create a new version.',
      v_status;
  END IF;
  RETURN COALESCE(NEW, OLD);
END;
$$;

DROP TRIGGER IF EXISTS trg_spec_sections_lock ON public.spec_sections;
CREATE TRIGGER trg_spec_sections_lock BEFORE INSERT OR UPDATE OR DELETE
  ON public.spec_sections FOR EACH ROW
  EXECUTE FUNCTION public.spec_block_if_locked();

DROP TRIGGER IF EXISTS trg_spec_items_lock ON public.spec_items;
CREATE TRIGGER trg_spec_items_lock BEFORE INSERT OR UPDATE OR DELETE
  ON public.spec_items FOR EACH ROW
  EXECUTE FUNCTION public.spec_block_if_locked();

-- Book itself: only allow status field + minor metadata to change when locked.
CREATE OR REPLACE FUNCTION public.spec_book_lock_check()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  IF TG_OP = 'UPDATE'
     AND OLD.status IN ('signed', 'superseded')
     AND (NEW.title IS DISTINCT FROM OLD.title
       OR NEW.description IS DISTINCT FROM OLD.description
       OR NEW.version IS DISTINCT FROM OLD.version) THEN
    RAISE EXCEPTION 'Locked spec book — only status/timestamps may change.';
  END IF;
  NEW.updated_at := NOW();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_spec_books_lock ON public.spec_books;
CREATE TRIGGER trg_spec_books_lock BEFORE UPDATE
  ON public.spec_books FOR EACH ROW
  EXECUTE FUNCTION public.spec_book_lock_check();

-- ---------------------------------------------------------------------------
-- RLS
-- ---------------------------------------------------------------------------
ALTER TABLE public.spec_books     ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.spec_sections  ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.spec_items     ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.spec_signoffs  ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS spec_books_all ON public.spec_books;
CREATE POLICY spec_books_all ON public.spec_books
  FOR ALL USING (public.is_workspace_member(workspace_id))
  WITH CHECK (public.is_workspace_member(workspace_id));

DROP POLICY IF EXISTS spec_sections_all ON public.spec_sections;
CREATE POLICY spec_sections_all ON public.spec_sections
  FOR ALL USING (public.is_workspace_member(workspace_id))
  WITH CHECK (public.is_workspace_member(workspace_id));

DROP POLICY IF EXISTS spec_items_all ON public.spec_items;
CREATE POLICY spec_items_all ON public.spec_items
  FOR ALL USING (public.is_workspace_member(workspace_id))
  WITH CHECK (public.is_workspace_member(workspace_id));

DROP POLICY IF EXISTS spec_signoffs_all ON public.spec_signoffs;
CREATE POLICY spec_signoffs_all ON public.spec_signoffs
  FOR ALL USING (public.is_workspace_member(workspace_id))
  WITH CHECK (public.is_workspace_member(workspace_id));

-- ---------------------------------------------------------------------------
-- RPC: spec_book_issue – mark draft as issued.
-- ---------------------------------------------------------------------------
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
  UPDATE public.spec_books
     SET status = 'issued', issued_at = NOW()
   WHERE id = p_book_id
   RETURNING * INTO v_book;
  RETURN v_book;
END;
$$;

REVOKE ALL ON FUNCTION public.spec_book_issue(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.spec_book_issue(UUID) TO authenticated;

-- ---------------------------------------------------------------------------
-- RPC: spec_book_sign_off – record client signature + lock the book.
-- ---------------------------------------------------------------------------
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

REVOKE ALL ON FUNCTION public.spec_book_sign_off(UUID, TEXT, TEXT, TEXT, TEXT, TEXT)
  FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.spec_book_sign_off(UUID, TEXT, TEXT, TEXT, TEXT, TEXT)
  TO authenticated;

-- ---------------------------------------------------------------------------
-- RPC: spec_book_new_version – deep-clone a signed/issued book into a
-- fresh draft with version = max(version)+1 and mark predecessor superseded.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.spec_book_new_version(p_source_id UUID)
RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_src        public.spec_books;
  v_new_id     UUID;
  v_next_ver   INT;
  v_section    RECORD;
  v_new_sec_id UUID;
  v_id_map     JSONB := '{}'::jsonb;  -- old section id -> new section id
BEGIN
  SELECT * INTO v_src FROM public.spec_books WHERE id = p_source_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Source spec book not found'; END IF;
  IF NOT public.is_workspace_member(v_src.workspace_id) THEN
    RAISE EXCEPTION 'Not authorized';
  END IF;

  SELECT COALESCE(MAX(version), 0) + 1
    INTO v_next_ver
    FROM public.spec_books WHERE project_id = v_src.project_id;

  INSERT INTO public.spec_books (
    workspace_id, project_id, title, description, version,
    status, previous_book_id, created_by
  ) VALUES (
    v_src.workspace_id, v_src.project_id, v_src.title, v_src.description,
    v_next_ver, 'draft', v_src.id, auth.uid()
  ) RETURNING id INTO v_new_id;

  -- Clone sections breadth-first so parent_id remaps stay consistent.
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

  -- Clone items.
  INSERT INTO public.spec_items (
    workspace_id, book_id, section_id, item_no, description,
    manufacturer, model, qty, unit, notes, sort_order
  )
  SELECT v_src.workspace_id, v_new_id,
         (v_id_map ->> i.section_id::text)::uuid,
         i.item_no, i.description, i.manufacturer, i.model,
         i.qty, i.unit, i.notes, i.sort_order
    FROM public.spec_items i WHERE i.book_id = p_source_id;

  -- Mark source as superseded.
  UPDATE public.spec_books
     SET status = 'superseded', superseded_at = NOW()
   WHERE id = p_source_id AND status IN ('issued', 'signed');

  RETURN v_new_id;
END;
$$;

REVOKE ALL ON FUNCTION public.spec_book_new_version(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.spec_book_new_version(UUID) TO authenticated;
