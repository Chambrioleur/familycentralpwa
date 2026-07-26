-- Run in the SQL Editor

create table if not exists shopping_suggestions (
  name text primary key,
  einheit text,
  updated_at timestamptz not null default now()
);

alter table shopping_suggestions enable row level security;
create policy "shopping_suggestions_select" on shopping_suggestions for select to authenticated using (can_view('einkauf'));
create policy "shopping_suggestions_write" on shopping_suggestions for all to authenticated using (can_edit('einkauf')) with check (can_edit('einkauf'));
