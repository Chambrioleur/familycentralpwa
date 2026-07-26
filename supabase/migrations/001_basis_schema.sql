-- Familienzentrale — Datenbankschema (Schritt 1)
-- Einspielen: Supabase Dashboard -> SQL Editor -> diese Datei komplett ausführen

-- ─────────────────────────────────────────────────────────
-- Erweiterungen
-- ─────────────────────────────────────────────────────────
create extension if not exists "pgcrypto";

-- ─────────────────────────────────────────────────────────
-- Personen
-- ─────────────────────────────────────────────────────────
create table members (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  farbe text not null,                       -- z.B. '#3E6C8E'
  rolle text not null check (rolle in ('erwachsen', 'kind')),
  pin_hash text,                             -- gehashter PIN, nie Klartext
  created_at timestamptz not null default now()
);

-- ─────────────────────────────────────────────────────────
-- Kalender
-- ─────────────────────────────────────────────────────────
create table calendar_events (
  id uuid primary key default gen_random_uuid(),
  titel text not null,
  beschreibung text,
  start_zeit timestamptz not null,
  end_zeit timestamptz not null,
  ganztaegig boolean not null default false,
  member_id uuid references members(id) on delete set null,
  ist_privat boolean not null default false,  -- vor Kind-Profilen verborgen
  rrule text,                                 -- Wiederholungsregel, falls vorhanden
  caldav_uid text unique,
  caldav_etag text,
  quelle text not null default 'app' check (quelle in ('app', 'apple')),
  geloescht boolean not null default false,   -- soft delete für sauberen Sync
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index on calendar_events (start_zeit);
create index on calendar_events (caldav_uid);

-- ─────────────────────────────────────────────────────────
-- Aufgaben & Erinnerungen (beide als VTODO synchronisiert, getrennte Listen)
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
  typ text default 'allgemein',               -- z.B. 'frist', 'geburtstag'
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
-- Dokumente
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
-- Voting / Ideen
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
-- Wissen (Familien-Wiki)
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
-- Finanzen
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
-- Gesundheit
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
-- Kontakte
-- ─────────────────────────────────────────────────────────
create table contacts (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  rolle text,                                 -- 'arzt', 'schule', 'verein', ...
  telefon text,
  notiz text,
  created_at timestamptz not null default now()
);

-- ─────────────────────────────────────────────────────────
-- Assistent
-- ─────────────────────────────────────────────────────────
create table assistant_suggestions (
  id uuid primary key default gen_random_uuid(),
  typ text not null check (typ in ('konflikt', 'freizeit', 'frist')),
  bezug_id uuid,                              -- verweist z.B. auf calendar_events.id
  text text not null,
  status text not null default 'offen' check (status in ('offen', 'erledigt', 'ignoriert')),
  created_at timestamptz not null default now()
);

-- ─────────────────────────────────────────────────────────
-- CalDAV-Sync
-- ─────────────────────────────────────────────────────────
create table caldav_account (
  id uuid primary key default gen_random_uuid(),
  apple_id text not null,
  app_passwort_verschluesselt text not null,  -- via Edge Function ver-/entschlüsselt, nie im Client
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
-- Single-Tenant-Annahme: eine Deployment-Instanz = eine Familie.
-- Zugriff ist auf authentifizierte Nutzer (der eine technische
-- Familien-Account) beschränkt; die Personen-Ebene (PIN) wird in der
-- App-Logik geprüft, nicht in RLS.
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

-- Generisches Policy-Muster: authentifizierte Nutzer dürfen alles.
-- caldav_account bekommt KEINE Client-Policy — nur die Edge Function
-- (service_role) darf darauf zugreifen, damit das App-Passwort nie
-- im Browser landet.
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

-- caldav_account: bewusst keine Policy für 'authenticated' -> nur service_role (Edge Functions) kommt ran
