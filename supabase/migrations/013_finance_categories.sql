-- Run in the SQL Editor

create table if not exists finance_categories (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  created_at timestamptz not null default now()
);

alter table finance_categories enable row level security;
create policy "finance_categories_select" on finance_categories for select to authenticated using (can_view('finanzen'));
create policy "finance_categories_write" on finance_categories for insert to authenticated with check (can_edit('finanzen'));
create policy "finance_categories_delete" on finance_categories for delete to authenticated using (can_edit('finanzen'));

insert into finance_categories (name) values
  ('Lebensmittel'), ('Haushalt'), ('Kinder'), ('Freizeit'), ('Sonstiges')
on conflict (name) do nothing;
