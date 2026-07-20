ALTER TABLE invoices
  ADD COLUMN IF NOT EXISTS retainage_percent        DECIMAL(5,2)  NOT NULL DEFAULT 0.0,
  ADD COLUMN IF NOT EXISTS retainage_amount         DECIMAL(12,2) NOT NULL DEFAULT 0.0,
  ADD COLUMN IF NOT EXISTS retainage_released       BOOLEAN       NOT NULL DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS retainage_released_date  DATE;
