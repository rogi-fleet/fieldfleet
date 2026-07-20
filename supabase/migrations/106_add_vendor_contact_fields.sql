-- Add missing columns to vendor_contacts that the app UI uses
ALTER TABLE vendor_contacts
  ADD COLUMN IF NOT EXISTS mobile_phone TEXT,
  ADD COLUMN IF NOT EXISTS notes TEXT;
