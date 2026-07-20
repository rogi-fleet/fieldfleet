-- Extend the workspace_member_role enum with the two new tiers required by
-- the FieldFleet roles_and_permissions schematic:
--   * master_admin — owner tier; only role that manages users and billing
--   * vendor       — external portal for subcontractors and bid requests
--
-- Split from the resolver/seed updates (20260419165030, 20260419165048) so
-- PostgreSQL lets the new enum values become visible before any function
-- body references them.

ALTER TYPE workspace_member_role ADD VALUE IF NOT EXISTS 'master_admin' BEFORE 'admin';
ALTER TYPE workspace_member_role ADD VALUE IF NOT EXISTS 'vendor';
