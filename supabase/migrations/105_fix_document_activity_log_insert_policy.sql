-- Recreate the INSERT policy without a USING clause so future databases
-- apply the intended deny-all write rule cleanly.
DROP POLICY IF EXISTS document_activity_log_deny_all
ON public.document_activity_log;

CREATE POLICY document_activity_log_deny_all
ON public.document_activity_log
FOR INSERT
WITH CHECK (false);
