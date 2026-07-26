-- Im SQL Editor ausführen

alter table finance_entries add column if not exists zahlungsempfaenger text;

create table if not exists payee_categories (
  id uuid primary key default gen_random_uuid(),
  zahlungsempfaenger text not null unique,
  kategorie text not null,
  created_at timestamptz not null default now()
);

alter table payee_categories enable row level security;
create policy "payee_categories_select" on payee_categories for select to authenticated using (can_view('finanzen'));
create policy "payee_categories_write" on payee_categories for all to authenticated using (can_edit('finanzen')) with check (can_edit('finanzen'));
