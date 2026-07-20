-- Expand project_status enum with new pipeline and lifecycle states
ALTER TYPE project_status ADD VALUE IF NOT EXISTS 'lead' BEFORE 'bidding';
ALTER TYPE project_status ADD VALUE IF NOT EXISTS 'proposal_sent' AFTER 'bidding';
ALTER TYPE project_status ADD VALUE IF NOT EXISTS 'awarded' AFTER 'proposal_sent';
ALTER TYPE project_status ADD VALUE IF NOT EXISTS 'on_hold' AFTER 'active';
ALTER TYPE project_status ADD VALUE IF NOT EXISTS 'lost' AFTER 'complete';
ALTER TYPE project_status ADD VALUE IF NOT EXISTS 'canceled' AFTER 'lost';
