-- Migration: Add property and area linking to tasks
-- Created: 2026-02-09
-- Purpose: Allow tasks to be linked to specific properties and areas for restoration workflow integration

-- ============================================================================
-- ADD PROPERTY AND AREA COLUMNS TO TASKS
-- ============================================================================

-- Add property_id column with foreign key to properties table
ALTER TABLE tasks
ADD COLUMN IF NOT EXISTS property_id UUID REFERENCES properties(id) ON DELETE SET NULL;

-- Add area_id column with foreign key to areas table
ALTER TABLE tasks
ADD COLUMN IF NOT EXISTS area_id UUID REFERENCES areas(id) ON DELETE SET NULL;

-- ============================================================================
-- INDEXES FOR EFFICIENT QUERIES
-- ============================================================================

-- Index for querying tasks by property
CREATE INDEX IF NOT EXISTS idx_tasks_property_id ON tasks(property_id)
WHERE property_id IS NOT NULL;

-- Index for querying tasks by area
CREATE INDEX IF NOT EXISTS idx_tasks_area_id ON tasks(area_id)
WHERE area_id IS NOT NULL;

-- Composite index for property + completion status (common filter pattern)
CREATE INDEX IF NOT EXISTS idx_tasks_property_complete ON tasks(property_id, is_complete)
WHERE property_id IS NOT NULL;
