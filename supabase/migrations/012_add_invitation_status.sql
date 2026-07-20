-- Add status column to workspace_invitations table
-- Status can be: 'pending', 'accepted', 'revoked', 'expired'

ALTER TABLE workspace_invitations
ADD COLUMN IF NOT EXISTS status TEXT NOT NULL DEFAULT 'pending';

-- Add accepted_by column to track who accepted the invitation
ALTER TABLE workspace_invitations
ADD COLUMN IF NOT EXISTS accepted_by UUID REFERENCES users(id);

-- Create an index on status for faster queries
CREATE INDEX IF NOT EXISTS idx_workspace_invitations_status
ON workspace_invitations(status);

-- Create an index on workspace_id and status for common queries
CREATE INDEX IF NOT EXISTS idx_workspace_invitations_workspace_status
ON workspace_invitations(workspace_id, status);

-- Update existing records: if accepted_at is not null, mark as accepted
UPDATE workspace_invitations
SET status = 'accepted'
WHERE accepted_at IS NOT NULL AND status = 'pending';
