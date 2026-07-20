-- Add qr_code column to vehicles table
ALTER TABLE vehicles
ADD COLUMN IF NOT EXISTS qr_code TEXT;

-- Create an index on qr_code for faster lookups
CREATE INDEX IF NOT EXISTS idx_vehicles_qr_code
ON vehicles(qr_code);
