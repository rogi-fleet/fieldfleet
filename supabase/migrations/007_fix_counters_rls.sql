-- Fix counters table RLS policies
-- Add missing INSERT policy for workspace members

-- Add INSERT policy for workspace members
DROP POLICY IF EXISTS counters_insert ON counters;
CREATE POLICY counters_insert ON counters
  FOR INSERT WITH CHECK (is_workspace_member(workspace_id));

-- Also add DELETE policy in case it's needed
DROP POLICY IF EXISTS counters_delete ON counters;
CREATE POLICY counters_delete ON counters
  FOR DELETE USING (is_workspace_member(workspace_id));
