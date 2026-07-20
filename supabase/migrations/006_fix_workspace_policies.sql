-- Fix RLS policies for workspace creation flow
-- The issue: When creating a workspace, the user inserts a row and immediately selects it.
-- The INSERT succeeds (auth.uid() is not null), but the SELECT fails because the user
-- is not yet a member of the workspace (membership is created in a subsequent step).
-- This migration updates the SELECT policy to allow the owner to view their workspace
-- even before membership is established.

-- ============================================================================
-- WORKSPACES
-- ============================================================================

-- Drop existing SELECT policy
DROP POLICY IF EXISTS workspaces_select ON workspaces;

-- Re-create SELECT policy allowing members OR owner
CREATE POLICY workspaces_select ON workspaces
  FOR SELECT USING (
    is_workspace_member(id) OR
    owner_id = auth.uid()
  );
