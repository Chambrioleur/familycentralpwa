-- Run in the SQL Editor

create table if not exists meal_plan (
  id uuid primary key default gen_random_uuid(),
  datum date not null,
  mahlzeit text not null check (mahlzeit in ('fruehstueck', 'mittag', 'abend')),
  recipe_id uuid references recipes(id) on delete cascade,
  calendar_event_id uuid references calendar_events(id) on delete set null,
  created_at timestamptz not null default now(),
  unique (datum, mahlzeit)
);

alter table meal_plan enable row level security;
create policy "meal_plan_select" on meal_plan for select to authenticated using (can_view('essensplan'));
create policy "meal_plan_write" on meal_plan for insert to authenticated with check (can_edit('essensplan'));
create policy "meal_plan_update" on meal_plan for update to authenticated using (can_edit('essensplan')) with check (can_edit('essensplan'));
create policy "meal_plan_delete" on meal_plan for delete to authenticated using (can_edit('essensplan'));

insert into role_permissions (rolle, bereich, sichtbar, bearbeiten) values
  ('kind', 'essensplan', true, true)
on conflict (rolle, bereich) do nothing;
