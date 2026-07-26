-- Familienzentrale — database schema (step 1)
-- Run via: Supabase Dashboard -> SQL Editor -> execute this file in full

-- ─────────────────────────────────────────────────────────
-- Extensions
-- ─────────────────────────────────────────────────────────
create extension if not exists "pgcrypto";

-- ─────────────────────────────────────────────────────────
-- People
-- ─────────────────────────────────────────────────────────
create table members (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  farbe text not null,                       -- e.g. '#3E6C8E'
  rolle text not null check (rolle in ('erwachsen', 'kind')),
  pin_hash text,                             -- hashed PIN, never plaintext
  created_at timestamptz not null default now()
);

-- ─────────────────────────────────────────────────────────
-- Calendar
-- ─────────────────────────────────────────────────────────
create table calendar_events (
  id uuid primary key default gen_random_uuid(),
  titel text not null,
  beschreibung text,
  start_zeit timestamptz not null,
  end_zeit timestamptz not null,
  ganztaegig boolean not null default false,
  member_id uuid references members(id) on delete set null,
  ist_privat boolean not null default false,  -- hidden from child profiles
  rrule text,                                 -- recurrence rule, if any
  caldav_uid text unique,
  caldav_etag text,
  quelle text not null default 'app' check (quelle in ('app', 'apple')),
  geloescht boolean not null default false,   -- soft delete for clean sync
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index on calendar_events (start_zeit);
create index on calendar_events (caldav_uid);

-- ─────────────────────────────────────────────────────────
-- Tasks & reminders (both synced as VTODO, separate lists)
-- ─────────────────────────────────────────────────────────
create table tasks (
  id uuid primary key default gen_random_uuid(),
  titel text not null,
  frist timestamptz,
  member_id uuid references members(id) on delete set null,
  status text not null default 'offen' check (status in ('offen', 'erledigt')),
  caldav_uid text unique,
  caldav_etag text,
  geloescht boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table reminders (
  id uuid primary key default gen_random_uuid(),
  titel text not null,
  faelligkeit timestamptz,
  typ text default 'allgemein',               -- e.g. 'frist', 'geburtstag'
  status text not null default 'offen' check (status in ('offen', 'erledigt')),
  caldav_uid text unique,
  caldav_etag text,
  geloescht boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table shopping_items (
  id uuid primary key default gen_random_uuid(),
  titel text not null,
  menge text,
  erledigt boolean not null default false,
  caldav_uid text unique,
  caldav_etag text,
  geloescht boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- ─────────────────────────────────────────────────────────
-- Documents
-- ─────────────────────────────────────────────────────────
create table documents (
  id uuid primary key default gen_random_uuid(),
  titel text not null,
  kategorie text not null default 'sonstiges',
  storage_pfad text not null,
  quelle text not null default 'upload' check (quelle in ('upload', 'kamera-scan')),
  status text not null default 'neu' check (status in ('neu', 'geprueft')),
  member_id uuid references members(id) on delete set null,
  created_at timestamptz not null default now()
);

-- ─────────────────────────────────────────────────────────
-- Voting / ideas
-- ─────────────────────────────────────────────────────────
create table votes (
  id uuid primary key default gen_random_uuid(),
  frage text not null,
  status text not null default 'offen' check (status in ('offen', 'abgeschlossen')),
  created_at timestamptz not null default now()
);
create table vote_options (
  id uuid primary key default gen_random_uuid(),
  vote_id uuid not null references votes(id) on delete cascade,
  text text not null
);
create table vote_responses (
  id uuid primary key default gen_random_uuid(),
  vote_option_id uuid not null references vote_options(id) on delete cascade,
  member_id uuid not null references members(id) on delete cascade,
  unique (vote_option_id, member_id)
);

-- ─────────────────────────────────────────────────────────
-- Knowledge (family wiki)
-- ─────────────────────────────────────────────────────────
create table wiki_entries (
  id uuid primary key default gen_random_uuid(),
  titel text not null,
  inhalt text not null,
  kategorie text default 'allgemein',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- ─────────────────────────────────────────────────────────
-- Finances
-- ─────────────────────────────────────────────────────────
create table finance_entries (
  id uuid primary key default gen_random_uuid(),
  betrag numeric(10,2) not null,
  kategorie text not null,
  datum date not null default current_date,
  notiz text,
  member_id uuid references members(id) on delete set null,
  created_at timestamptz not null default now()
);

-- ─────────────────────────────────────────────────────────
-- Health
-- ─────────────────────────────────────────────────────────
create table health_records (
  id uuid primary key default gen_random_uuid(),
  member_id uuid references members(id) on delete cascade,
  typ text not null check (typ in ('impfung', 'termin', 'befund')),
  datum date not null,
  notiz text,
  created_at timestamptz not null default now()
);

-- ─────────────────────────────────────────────────────────
-- Contacts
-- ─────────────────────────────────────────────────────────
create table contacts (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  rolle text,                                 -- e.g. 'doctor', 'school', 'club', ...
  telefon text,
  notiz text,
  created_at timestamptz not null default now()
);

-- ─────────────────────────────────────────────────────────
-- Assistant
-- ─────────────────────────────────────────────────────────
create table assistant_suggestions (
  id uuid primary key default gen_random_uuid(),
  typ text not null check (typ in ('konflikt', 'freizeit', 'frist')),
  bezug_id uuid,                              -- references e.g. calendar_events.id
  text text not null,
  status text not null default 'offen' check (status in ('offen', 'erledigt', 'ignoriert')),
  created_at timestamptz not null default now()
);

-- ─────────────────────────────────────────────────────────
-- CalDAV sync
-- ─────────────────────────────────────────────────────────
create table caldav_account (
  id uuid primary key default gen_random_uuid(),
  apple_id text not null,
  app_passwort_verschluesselt text not null,  -- encrypted/decrypted via Edge Function, never in the client
  kalender_sync_token text,
  aufgaben_sync_token text,
  einkauf_sync_token text,
  status text not null default 'aktiv' check (status in ('aktiv', 'fehler', 'nicht_verbunden')),
  letzter_sync timestamptz,
  created_at timestamptz not null default now()
);

create table sync_log (
  id uuid primary key default gen_random_uuid(),
  tabelle text not null,
  richtung text not null check (richtung in ('push', 'pull')),
  ergebnis text not null check (ergebnis in ('erfolg', 'fehler')),
  details text,
  created_at timestamptz not null default now()
);

-- ─────────────────────────────────────────────────────────
-- Row Level Security
-- Single-tenant assumption: one deployment instance = one family.
-- Access is restricted to authenticated users (the one technical
-- family account); the per-person layer (PIN) is checked in the
-- app logic, not in RLS.
-- ─────────────────────────────────────────────────────────
alter table members enable row level security;
alter table calendar_events enable row level security;
alter table tasks enable row level security;
alter table reminders enable row level security;
alter table shopping_items enable row level security;
alter table documents enable row level security;
alter table votes enable row level security;
alter table vote_options enable row level security;
alter table vote_responses enable row level security;
alter table wiki_entries enable row level security;
alter table finance_entries enable row level security;
alter table health_records enable row level security;
alter table contacts enable row level security;
alter table assistant_suggestions enable row level security;
alter table caldav_account enable row level security;
alter table sync_log enable row level security;

-- Generic policy pattern: authenticated users may do everything.
-- caldav_account gets NO client policy — only the Edge Function
-- (service_role) may access it, so the app password never ends up
-- in the browser.
do $$
declare t text;
begin
  foreach t in array array[
    'members','calendar_events','tasks','reminders','shopping_items',
    'documents','votes','vote_options','vote_responses','wiki_entries',
    'finance_entries','health_records','contacts','assistant_suggestions',
    'sync_log'
  ]
  loop
    execute format(
      'create policy "authenticated_full_access" on %I for all to authenticated using (true) with check (true);', t
    );
  end loop;
end $$;

-- caldav_account: deliberately no policy for 'authenticated' -> only service_role (Edge Functions) gets access
