-- Adds a unit_system setting to workspaces so field forms can render
-- temperature (and future measurements) in the operator's preferred units.

alter table public.workspaces
  add column if not exists unit_system text not null default 'imperial'
    check (unit_system in ('metric', 'imperial'));
