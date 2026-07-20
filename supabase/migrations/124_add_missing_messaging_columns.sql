-- messages: soft delete + reply threading
ALTER TABLE messages
  ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS reply_to_id UUID REFERENCES messages(id) ON DELETE SET NULL;

-- conversations: pin + mute per user
ALTER TABLE conversations
  ADD COLUMN IF NOT EXISTS pinned_by JSONB DEFAULT '{}',
  ADD COLUMN IF NOT EXISTS muted_by  JSONB DEFAULT '{}';
