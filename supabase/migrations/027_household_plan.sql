-- Run in the SQL Editor.
--
-- Household plan: a weekly grid for chores, modeled after the school
-- timetable, but with two differences:
-- - Assignable to everyone, not just children.
-- - Optional automatic rotation: multiple rows in
--   household_task_assignees = rotation pool, "whose turn this week"
--   is computed at display time (calendar week modulo number of
--   assignees), not stored in the DB.

create table if not exists household_tasks (
  id uuid primary key default gen_random_uuid(),
  titel text not null,
  rhythmus text not null default 'woechentlich' check (rhythmus in ('taeglich', 'woechentlich')),
  wochentag integer check (wochentag between 1 and 7), -- 1=Monday .. 7=Sunday; null when rhythmus='taeglich'
  geloescht boolean not null default false,
  created_at timestamptz not null default now()
);

create table if not exists household_task_assignees (
  task_id uuid not null references household_tasks(id) on delete cascade,
  member_id uuid not null references members(id) on delete cascade,
  rotation_order integer not null default 0,
  primary key (task_id, member_id)
);

-- One row per (task, calendar date) actually completed. Kept
-- permanently (no weekly reset of a column) -- streak/consistency is a
-- query over this table, not a stored counter. Works for both rhythms:
-- 'taeglich' gets one row per day it's done, 'woechentlich' gets one
-- row for its one day per week.
create table if not exists household_task_completions (
  id uuid primary key default gen_random_uuid(),
  task_id uuid not null references household_tasks(id) on delete cascade,
  datum date not null,
  member_id uuid not null references members(id),
  created_at timestamptz not null default now(),
  unique (task_id, datum)
);

alter table household_tasks enable row level security;
alter table household_task_assignees enable row level security;
alter table household_task_completions enable row level security;

-- Task definitions and assignments: an administrative action, only for
-- whoever may edit 'haushaltsplan' (same pattern as the timetable_entries).
create policy "household_tasks_select" on household_tasks for select to authenticated using (can_view('haushaltsplan'));
create policy "household_tasks_write" on household_tasks for insert to authenticated with check (can_edit('haushaltsplan'));
create policy "household_tasks_update" on household_tasks for update to authenticated using (can_edit('haushaltsplan')) with check (can_edit('haushaltsplan'));
create policy "household_tasks_delete" on household_tasks for delete to authenticated using (can_edit('haushaltsplan'));

create policy "household_task_assignees_select" on household_task_assignees for select to authenticated using (can_view('haushaltsplan'));
create policy "household_task_assignees_write" on household_task_assignees for insert to authenticated with check (can_edit('haushaltsplan'));
create policy "household_task_assignees_update" on household_task_assignees for update to authenticated using (can_edit('haushaltsplan')) with check (can_edit('haushaltsplan'));
create policy "household_task_assignees_delete" on household_task_assignees for delete to authenticated using (can_edit('haushaltsplan'));

-- Completion marks: as with tasks (tasks_insert/-delete), a person may
-- always log/remove their OWN completions, even without general edit
-- rights -- so children can check off tasks assigned to them without
-- being able to edit the whole plan.
create policy "household_task_completions_select" on household_task_completions for select to authenticated using (can_view('haushaltsplan'));
create policy "household_task_completions_insert" on household_task_completions for insert to authenticated
  with check (can_edit('haushaltsplan') or member_id = my_member_id());
create policy "household_task_completions_delete" on household_task_completions for delete to authenticated
  using (can_edit('haushaltsplan') or member_id = my_member_id());

-- Default permissions: visible to children. bearbeiten=false here means
-- (as with 'aufgaben'/'kalender'): they may NOT edit others' entries or
-- restructure the task definitions/assignments themselves. They can
-- still always log/remove their own completions -- the
-- household_task_completions policies above handle that directly via
-- "or member_id = my_member_id()", independent of this toggle (exactly
-- as with tasks, see the comment in 006_permission_management.sql).
insert into role_permissions (rolle, bereich, sichtbar, bearbeiten, nur_eigene) values
  ('kind', 'haushaltsplan', true, false, true)
on conflict (rolle, bereich) do nothing;
