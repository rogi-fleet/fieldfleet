-- Atomic RPCs for document <-> budget mutations.
--
-- Replaces three multi-statement client-side patterns that had observable
-- races or partial-failure modes:
--   1. snapshot_approved_budget_items  — freeze quantity/unit_price on linked
--      budget_items at approval time. The old client code read each row and
--      did per-id updates, so two concurrent approvals could both see
--      approved_at IS NULL and clobber each other's snapshot.
--   2. sync_budget_document_links      — upsert desired links and delete
--      stale links in one transaction. The old client code deleted first,
--      so a failed upsert (network, FK) left the document with zero links
--      and silently under-reported invoiced totals.
--   3. apply_deposit_to_document /
--      remove_deposit_from_document    — update the invoice metadata and
--      the deposit metadata in one transaction, and reject applying a
--      deposit that is already attached to a different invoice.
--
-- All functions run as SECURITY INVOKER: RLS on budget_items,
-- budget_document_links, and generated_documents already enforces workspace
-- membership, so no additional authz is needed here.

-- ---------------------------------------------------------------------------
-- 1. snapshot_approved_budget_items
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.snapshot_approved_budget_items(
  p_document_id uuid
)
RETURNS void
LANGUAGE sql
SECURITY INVOKER
SET search_path = public
AS $$
  UPDATE public.budget_items bi
  SET approved_at = NOW(),
      approved_quantity = bi.quantity,
      approved_unit_price = bi.unit_price
  WHERE bi.approved_at IS NULL
    AND bi.id IN (
      SELECT bdl.budget_item_id
      FROM public.budget_document_links bdl
      WHERE bdl.generated_document_id = p_document_id
    );
$$;

GRANT EXECUTE ON FUNCTION public.snapshot_approved_budget_items(uuid)
  TO authenticated;

COMMENT ON FUNCTION public.snapshot_approved_budget_items(uuid) IS
  'Atomically freeze quantity/unit_price on every budget_item linked to '
  'this document whose approved_at is still NULL. Idempotent; concurrent '
  'approvals cannot overwrite an earlier snapshot.';

-- ---------------------------------------------------------------------------
-- 2. sync_budget_document_links
-- ---------------------------------------------------------------------------
-- p_entries payload shape:
--   [{"budget_item_id": "<uuid>", "amount": 1200, "source": "from_budget_selection"}]
--
-- project_id is resolved inside the function: first from generated_documents,
-- then (for documents without a project) from the target budget_items. The
-- integrity trigger already requires a non-null project — we surface a clear
-- error instead of letting the trigger raise a generic message.
CREATE OR REPLACE FUNCTION public.sync_budget_document_links(
  p_document_id uuid,
  p_entries jsonb
)
RETURNS void
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  v_workspace_id uuid;
  v_project_id uuid;
  v_desired_ids uuid[];
BEGIN
  IF p_entries IS NULL OR jsonb_typeof(p_entries) <> 'array' THEN
    RAISE EXCEPTION 'p_entries must be a jsonb array'
      USING ERRCODE = '22023';
  END IF;

  SELECT workspace_id, project_id
  INTO v_workspace_id, v_project_id
  FROM public.generated_documents
  WHERE id = p_document_id;

  IF v_workspace_id IS NULL THEN
    RAISE EXCEPTION 'Document % not found', p_document_id
      USING ERRCODE = 'P0002';
  END IF;

  -- Fall back to the project of the first budget item when the document
  -- itself has no project (the integrity trigger enforces that all items
  -- agree, so picking the first is safe).
  IF v_project_id IS NULL AND jsonb_array_length(p_entries) > 0 THEN
    SELECT bi.project_id
    INTO v_project_id
    FROM public.budget_items bi
    WHERE bi.id = (p_entries->0->>'budget_item_id')::uuid;
  END IF;

  IF v_project_id IS NULL AND jsonb_array_length(p_entries) > 0 THEN
    RAISE EXCEPTION
      'Cannot sync budget links for document % without a project',
      p_document_id USING ERRCODE = 'P0001';
  END IF;

  SELECT COALESCE(
    array_agg((entry->>'budget_item_id')::uuid),
    ARRAY[]::uuid[]
  )
  INTO v_desired_ids
  FROM jsonb_array_elements(p_entries) AS entry;

  -- Upsert first, then delete stale. If the upsert fails (FK violation,
  -- integrity trigger, network), the existing rows remain untouched rather
  -- than leaving the document with zero links.
  IF jsonb_array_length(p_entries) > 0 THEN
    INSERT INTO public.budget_document_links (
      workspace_id,
      project_id,
      generated_document_id,
      budget_item_id,
      amount,
      source
    )
    SELECT
      v_workspace_id,
      v_project_id,
      p_document_id,
      (entry->>'budget_item_id')::uuid,
      COALESCE((entry->>'amount')::numeric, 0),
      COALESCE(
        (entry->>'source')::budget_document_link_source,
        'from_budget_selection'::budget_document_link_source
      )
    FROM jsonb_array_elements(p_entries) AS entry
    ON CONFLICT (generated_document_id, budget_item_id) DO UPDATE
      SET amount = EXCLUDED.amount,
          source = EXCLUDED.source;
  END IF;

  DELETE FROM public.budget_document_links
  WHERE generated_document_id = p_document_id
    AND NOT (budget_item_id = ANY(v_desired_ids));
END;
$$;

GRANT EXECUTE ON FUNCTION public.sync_budget_document_links(uuid, jsonb)
  TO authenticated;

COMMENT ON FUNCTION public.sync_budget_document_links(uuid, jsonb) IS
  'Atomically upsert the desired budget_document_links for a document and '
  'delete any stale links in a single transaction.';

-- ---------------------------------------------------------------------------
-- 3. apply_deposit_to_document / remove_deposit_from_document
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.apply_deposit_to_document(
  p_document_id uuid,
  p_deposit_document_id uuid,
  p_deposit_amount numeric
)
RETURNS void
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  v_invoice generated_documents%ROWTYPE;
  v_deposit generated_documents%ROWTYPE;
  v_existing_target text;
BEGIN
  IF p_document_id = p_deposit_document_id THEN
    RAISE EXCEPTION 'Deposit and invoice documents must differ'
      USING ERRCODE = '22023';
  END IF;

  SELECT * INTO v_invoice
  FROM public.generated_documents
  WHERE id = p_document_id
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Invoice document % not found', p_document_id
      USING ERRCODE = 'P0002';
  END IF;

  SELECT * INTO v_deposit
  FROM public.generated_documents
  WHERE id = p_deposit_document_id
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Deposit document % not found', p_deposit_document_id
      USING ERRCODE = 'P0002';
  END IF;

  -- Refuse to hijack a deposit already applied to a different invoice.
  v_existing_target := COALESCE(v_deposit.metadata, '{}'::jsonb)
    ->> 'applied_to_document_id';
  IF v_existing_target IS NOT NULL
     AND v_existing_target <> p_document_id::text THEN
    RAISE EXCEPTION
      'Deposit % is already applied to document %',
      p_deposit_document_id, v_existing_target
      USING ERRCODE = 'P0001';
  END IF;

  UPDATE public.generated_documents
  SET metadata = COALESCE(metadata, '{}'::jsonb)
    || jsonb_build_object(
      'applied_deposit_amount', p_deposit_amount,
      'applied_deposit_document_id', p_deposit_document_id::text
    )
  WHERE id = p_document_id;

  UPDATE public.generated_documents
  SET metadata = COALESCE(metadata, '{}'::jsonb)
    || jsonb_build_object(
      'applied_to_document_id', p_document_id::text
    )
  WHERE id = p_deposit_document_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.apply_deposit_to_document(uuid, uuid, numeric)
  TO authenticated;

COMMENT ON FUNCTION public.apply_deposit_to_document(uuid, uuid, numeric) IS
  'Atomically record a deposit application on the invoice and the deposit '
  'document. Rejects reassigning a deposit that is already applied '
  'elsewhere.';

CREATE OR REPLACE FUNCTION public.remove_deposit_from_document(
  p_document_id uuid
)
RETURNS void
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  v_invoice generated_documents%ROWTYPE;
  v_deposit_id uuid;
BEGIN
  SELECT * INTO v_invoice
  FROM public.generated_documents
  WHERE id = p_document_id
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Invoice document % not found', p_document_id
      USING ERRCODE = 'P0002';
  END IF;

  v_deposit_id := NULLIF(
    COALESCE(v_invoice.metadata, '{}'::jsonb) ->> 'applied_deposit_document_id',
    ''
  )::uuid;

  UPDATE public.generated_documents
  SET metadata = (COALESCE(metadata, '{}'::jsonb)
    - 'applied_deposit_amount'
    - 'applied_deposit_document_id')
  WHERE id = p_document_id;

  IF v_deposit_id IS NOT NULL THEN
    UPDATE public.generated_documents
    SET metadata = (COALESCE(metadata, '{}'::jsonb)
      - 'applied_to_document_id')
    WHERE id = v_deposit_id
      AND COALESCE(metadata, '{}'::jsonb) ->> 'applied_to_document_id'
          = p_document_id::text;
  END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION public.remove_deposit_from_document(uuid)
  TO authenticated;

COMMENT ON FUNCTION public.remove_deposit_from_document(uuid) IS
  'Atomically clear deposit references from the invoice and the linked '
  'deposit document. Only clears the deposit''s back-reference if it '
  'still points at this invoice.';
