-- Fix coordinate columns to use DOUBLE PRECISION instead of DECIMAL (which
-- defaults to integer-like precision in PostgreSQL).
ALTER TABLE customer_locations
  ALTER COLUMN latitude TYPE DOUBLE PRECISION,
  ALTER COLUMN longitude TYPE DOUBLE PRECISION;
