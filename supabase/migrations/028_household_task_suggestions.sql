-- Run in the SQL Editor
--
-- Custom, permanently stored suggestions for the household plan form, in
-- addition to the built-in suggestion list hardcoded in the frontend.
-- Deliberately a small separate table instead of mirroring the core
-- suggestion list's categories -- a free-text category isn't needed here.
create table if not exists household_task_suggestions (
  id uuid primary key default gen_random_uuid(),
  titel text not null,
  rhythmus text not null default 'woechentlich' check (rhythmus in ('taeglich', 'woechentlich')),
  created_at timestamptz not null default now()
);

alter table household_task_suggestions enable row level security;

-- Same permissions as household_tasks itself: managing the suggestion
-- list is part of the edit right for 'haushaltsplan', not the plain
-- right to check off one's own completions.
create policy "household_task_suggestions_select" on household_task_suggestions for select to authenticated using (can_view('haushaltsplan'));
create policy "household_task_suggestions_write" on household_task_suggestions for insert to authenticated with check (can_edit('haushaltsplan'));
create policy "household_task_suggestions_delete" on household_task_suggestions for delete to authenticated using (can_edit('haushaltsplan'));
