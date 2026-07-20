-- Scope generated_documents reads for portal users. A portal customer sees
-- a document only when it's either tagged with their customer_id OR lives
-- on a project whose client they are. A portal vendor sees documents
-- linked to them via a bid_request/purchase_order/bill they own.
--
-- Write operations remain module-gated; portal users don't create documents
-- here today (uploads go through file_attachments).

DROP POLICY IF EXISTS generated_documents_select ON public.generated_documents;
CREATE POLICY generated_documents_select ON public.generated_documents
  FOR SELECT USING (
    public.has_workspace_module_permission(workspace_id, 'documents', 'read')
    AND (
      NOT public.is_external_portal_user(workspace_id)
      OR customer_id IN (SELECT public.current_portal_customer_ids(workspace_id))
      OR EXISTS (
        SELECT 1 FROM public.projects p
        WHERE p.id = generated_documents.project_id
          AND p.client_id IN (SELECT public.current_portal_customer_ids(workspace_id))
      )
      OR EXISTS (
        SELECT 1 FROM public.bid_requests br
        WHERE br.project_id = generated_documents.project_id
          AND br.vendor_id IN (SELECT public.current_portal_vendor_ids(workspace_id))
      )
    )
  );
