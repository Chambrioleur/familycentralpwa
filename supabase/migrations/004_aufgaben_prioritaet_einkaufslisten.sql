-- Im SQL Editor ausführen

-- Aufgaben: Priorität ergänzen
alter table tasks add column if not exists prioritaet text not null default 'mittel' check (prioritaet in ('niedrig', 'mittel', 'hoch'));

-- Einkauf: mehrere Listen + Menge/Einheit getrennt
create table if not exists shopping_lists (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  created_at timestamptz not null default now()
);

alter table shopping_items add column if not exists liste_id uuid references shopping_lists(id) on delete cascade;
alter table shopping_items add column if not exists einheit text;

-- Bestehende Einkaufsliste (falls vorhanden) in eine Standard-Liste überführen
insert into shopping_lists (name)
  select 'Einkaufsliste'
  where not exists (select 1 from shopping_lists);

update shopping_items
  set liste_id = (select id from shopping_lists order by created_at limit 1)
  where liste_id is null;

alter table shopping_lists enable row level security;
create policy "shopping_lists_all" on shopping_lists for all to authenticated using (true) with check (true);
