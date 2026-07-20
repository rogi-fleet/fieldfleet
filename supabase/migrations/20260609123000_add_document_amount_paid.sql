-- F011: partial payments for documents-first invoices/bills.
--
-- generated_documents previously tracked payment as a binary `paid_date`
-- (set = fully paid). To support partial payments we add a cumulative
-- `amount_paid`. The outstanding balance is `total_amount - amount_paid`;
-- `paid_date` is now stamped only once the balance reaches zero.

ALTER TABLE public.generated_documents
  ADD COLUMN IF NOT EXISTS amount_paid NUMERIC(14,2) NOT NULL DEFAULT 0;

-- Backfill: anything already marked paid is fully paid.
UPDATE public.generated_documents
   SET amount_paid = total_amount
 WHERE paid_date IS NOT NULL
   AND amount_paid = 0
   AND total_amount > 0;
