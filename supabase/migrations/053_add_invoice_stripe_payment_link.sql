ALTER TABLE invoices
  ADD COLUMN IF NOT EXISTS stripe_payment_link_url TEXT;
