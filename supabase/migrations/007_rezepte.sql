-- Im SQL Editor ausführen

create table if not exists recipes (
  id uuid primary key default gen_random_uuid(),
  titel text not null,
  portionen integer,
  zutaten text not null,
  zubereitung text not null,
  kategorie text default 'sonstiges',
  created_at timestamptz not null default now()
);

alter table recipes enable row level security;
create policy "recipes_select" on recipes for select to authenticated using (can_view('rezepte'));
create policy "recipes_write" on recipes for insert to authenticated with check (can_edit('rezepte'));
create policy "recipes_update" on recipes for update to authenticated using (can_edit('rezepte')) with check (can_edit('rezepte'));
create policy "recipes_delete" on recipes for delete to authenticated using (can_edit('rezepte'));

insert into role_permissions (rolle, bereich, sichtbar, bearbeiten) values
  ('kind', 'rezepte', true, true)
on conflict (rolle, bereich) do nothing;
